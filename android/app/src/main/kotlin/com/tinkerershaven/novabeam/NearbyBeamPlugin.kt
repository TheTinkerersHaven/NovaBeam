package com.tinkerershaven.novabeam

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.AdvertisingOptions
import com.google.android.gms.nearby.connection.ConnectionsClient
import com.google.android.gms.nearby.connection.ConnectionsStatusCodes
import com.google.android.gms.nearby.connection.ConnectionInfo
import com.google.android.gms.nearby.connection.ConnectionLifecycleCallback
import com.google.android.gms.nearby.connection.ConnectionResolution
import com.google.android.gms.nearby.connection.DiscoveredEndpointInfo
import com.google.android.gms.nearby.connection.DiscoveryOptions
import com.google.android.gms.nearby.connection.EndpointDiscoveryCallback
import com.google.android.gms.nearby.connection.Payload
import com.google.android.gms.nearby.connection.PayloadCallback
import com.google.android.gms.nearby.connection.PayloadTransferUpdate
import com.google.android.gms.nearby.connection.Strategy
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.security.DigestInputStream
import java.security.MessageDigest

/// Flutter wrapper around the Google Play services Nearby Connections API
/// (ConnectionsClient). Advertises/discovers on P2P_POINT_TO_POINT, manages
/// the connection lifecycle, sends BYTES control messages and STREAM file
/// payloads, and persists incoming streams to app-specific external storage
/// with a SHA-256 check against the manifest.
class NearbyBeamPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private val appContext: Context get() = activity.applicationContext
    private var serviceId: String = ""
    private var localName: String = "novabeam"
    private var client: ConnectionsClient? = null
    private var eventSink: EventChannel.EventSink? = null
    private val connectedEndpoints = mutableSetOf<String>()
    private var incomingName: String = "received.bin"
    private var incomingSha256: String? = null

    companion object {
        private const val METHOD_CHANNEL = "dev.tinkerershaven.novabeam/nearby"
        private const val EVENT_CHANNEL = "dev.tinkerershaven.novabeam/nearby_events"
        private const val PERMISSION_REQUEST_CODE = 1001

        fun registerWith(engine: FlutterEngine, activity: Activity) {
            val plugin = NearbyBeamPlugin(activity)
            MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
                .setMethodCallHandler(plugin)
            EventChannel(engine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
                .setStreamHandler(object : EventChannel.StreamHandler {
                    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                        plugin.eventSink = sink
                    }

                    override fun onCancel(arguments: Any?) {
                        plugin.eventSink = null
                    }
                })
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "init" -> {
                    serviceId = call.argument<String>("serviceId") ?: ""
                    client = Nearby.getConnectionsClient(appContext)
                    result.success(null)
                }
                "requestPermissions" -> {
                    requestRuntimePermissions()
                    result.success(null)
                }
                "startAdvertising" -> {
                    localName = call.argument<String>("name") ?: localName
                    client()!!.startAdvertising(
                        localName,
                        serviceId,
                        connectionCallback,
                        AdvertisingOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build()
                    )
                    result.success(null)
                }
                "startDiscovery" -> {
                    client()!!.startDiscovery(
                        serviceId,
                        discoveryCallback,
                        DiscoveryOptions.Builder().setStrategy(Strategy.P2P_POINT_TO_POINT).build()
                    )
                    result.success(null)
                }
                "stopAll" -> {
                    client()?.stopAdvertising()
                    client()?.stopDiscovery()
                    client()?.stopAllEndpoints()
                    connectedEndpoints.clear()
                    BeamTransferService.stop(appContext)
                    result.success(null)
                }
                "requestConnection" -> {
                    val endpointId = call.argument<String>("endpointId")!!
                    client()!!.requestConnection(localName, endpointId, connectionCallback)
                    result.success(null)
                }
                "acceptConnection" -> {
                    val endpointId = call.argument<String>("endpointId")!!
                    client()!!.acceptConnection(endpointId, payloadCallback)
                    result.success(null)
                }
                "rejectConnection" -> {
                    val endpointId = call.argument<String>("endpointId")!!
                    client()!!.rejectConnection(endpointId)
                    result.success(null)
                }
                "sendControl" -> {
                    val endpointId = call.argument<String>("endpointId")!!
                    val json = call.argument<String>("json")!!
                    client()!!.sendPayload(
                        endpointId,
                        Payload.fromBytes(json.toByteArray(Charsets.UTF_8))
                    )
                    result.success(null)
                }
                "sendFile" -> {
                    val endpointId = call.argument<String>("endpointId")!!
                    val path = call.argument<String>("path")
                    val bytes = call.argument<ByteArray>("bytes")
                    val stream: InputStream = when {
                        bytes != null -> ByteArrayInputStream(bytes)
                        path != null && path.startsWith("content://") ->
                            appContext.contentResolver.openInputStream(Uri.parse(path))
                                ?: throw IllegalArgumentException("cannot open $path")
                        path != null && path.startsWith("file://") ->
                            File(Uri.parse(path).path!!).inputStream()
                        path != null -> File(path).inputStream()
                        else -> throw IllegalArgumentException("sendFile needs path or bytes")
                    }
                    client()!!.sendPayload(endpointId, Payload.fromStream(stream))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("nearby_error", e.message ?: "unknown error", null)
        }
    }

    private fun client(): ConnectionsClient? = client

    private fun requestRuntimePermissions() {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            needed += Manifest.permission.BLUETOOTH_SCAN
            needed += Manifest.permission.BLUETOOTH_ADVERTISE
            needed += Manifest.permission.BLUETOOTH_CONNECT
        } else {
            needed += Manifest.permission.ACCESS_FINE_LOCATION
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            needed += Manifest.permission.NEARBY_WIFI_DEVICES
            needed += Manifest.permission.POST_NOTIFICATIONS
        }
        val toRequest = needed.filter {
            ContextCompat.checkSelfPermission(appContext, it) != PackageManager.PERMISSION_GRANTED
        }
        if (toRequest.isNotEmpty()) {
            ActivityCompat.requestPermissions(activity, toRequest.toTypedArray(), PERMISSION_REQUEST_CODE)
        }
    }

    private val discoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            emit(
                mapOf(
                    "type" to "endpointFound",
                    "endpointId" to endpointId,
                    "name" to info.endpointName
                )
            )
        }

        override fun onEndpointLost(endpointId: String) {
            emit(mapOf("type" to "endpointLost", "endpointId" to endpointId))
        }
    }

    private val connectionCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            emit(
                mapOf(
                    "type" to "connectionInitiated",
                    "endpointId" to endpointId,
                    "name" to info.endpointName,
                    "digits" to info.authenticationDigits
                )
            )
        }

        override fun onConnectionResult(endpointId: String, resolution: ConnectionResolution) {
            val ok = resolution.status.statusCode == ConnectionsStatusCodes.STATUS_OK
            emit(
                mapOf(
                    "type" to "connectionResult",
                    "endpointId" to endpointId,
                    "status" to resolution.status.statusCode,
                    "ok" to ok
                )
            )
            if (ok) {
                connectedEndpoints.add(endpointId)
                BeamTransferService.start(appContext)
            }
        }

        override fun onDisconnected(endpointId: String) {
            connectedEndpoints.remove(endpointId)
            emit(mapOf("type" to "disconnected", "endpointId" to endpointId))
            if (connectedEndpoints.isEmpty()) {
                BeamTransferService.stop(appContext)
            }
        }
    }

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            when (payload.type) {
                Payload.Type.BYTES -> {
                    val text = payload.asBytes()?.toString(Charsets.UTF_8)
                    if (text != null) {
                        trackManifest(text)
                        emit(
                            mapOf(
                                "type" to "control",
                                "endpointId" to endpointId,
                                "payloadId" to payload.id,
                                "data" to text
                            )
                        )
                    }
                }
                Payload.Type.STREAM, Payload.Type.FILE -> {
                    val stream = payload.asStream()?.asInputStream() ?: return
                    handleIncomingStream(endpointId, payload.id, stream)
                }
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            emit(
                mapOf(
                    "type" to "transferUpdate",
                    "endpointId" to endpointId,
                    "payloadId" to update.payloadId,
                    "status" to update.status,
                    "transferred" to update.bytesTransferred,
                    "total" to update.totalBytes
                )
            )
        }
    }

    private fun trackManifest(text: String) {
        try {
            val obj = JSONObject(text)
            if (obj.optString("type") == "manifest") {
                incomingName = sanitize(obj.optString("name", "received.bin"))
                incomingSha256 = if (obj.has("sha256")) obj.optString("sha256") else null
            }
        } catch (_: Exception) {
            // Not JSON or not a manifest; the Dart side validates properly.
        }
    }

    private fun handleIncomingStream(endpointId: String, payloadId: Long, raw: InputStream) {
        try {
            val dir = appContext.getExternalFilesDir(null) ?: appContext.filesDir
            val outFile = File(dir, incomingName)
            val digest = MessageDigest.getInstance("SHA-256")
            DigestInputStream(raw, digest).use { input ->
                outFile.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buffer)
                        if (n < 0) break
                        output.write(buffer, 0, n)
                    }
                }
            }
            val shaOk = incomingSha256 == null ||
                incomingSha256.equals(toHex(digest.digest()), ignoreCase = true)
            emit(
                mapOf(
                    "type" to "fileReceived",
                    "endpointId" to endpointId,
                    "payloadId" to payloadId,
                    "name" to incomingName,
                    "size" to outFile.length(),
                    "path" to outFile.absolutePath,
                    "shaOk" to shaOk
                )
            )
        } catch (e: Exception) {
            emit(
                mapOf(
                    "type" to "transferError",
                    "endpointId" to endpointId,
                    "payloadId" to payloadId,
                    "error" to (e.message ?: "io error")
                )
            )
        }
    }

    private fun sanitize(name: String): String {
        val base = name.substringAfterLast('/').substringAfterLast('\\')
        return if (base.isEmpty()) "received.bin" else base.take(128)
    }

    private fun toHex(bytes: ByteArray): String =
        bytes.joinToString("") { "%02x".format(it) }

    private fun emit(map: Map<String, Any?>) {
        eventSink?.success(map)
    }
}
