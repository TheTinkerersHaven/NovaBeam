package com.tinkerershaven.novabeam

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.IntentFilter
import android.nfc.NdefMessage
import android.nfc.NdefRecord
import android.nfc.NfcAdapter
import android.nfc.tech.Ndef
import android.os.Build
import android.os.Parcelable
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// NFC beam engine: the Android Beam successor pattern.
///
/// While armed, the activity runs foreground NDEF dispatch and registers an
/// NDEF push callback, so tapping two phones running the app delivers this
/// device's payload to the other phone's dispatch intent. Incoming NDEF
/// MIME records (`application/x-novabeam`) are forwarded to Flutter as events.
class NfcBeamPlugin(private val activity: Activity) : MethodChannel.MethodCallHandler {

    private var eventSink: EventChannel.EventSink? = null
    private var pendingPayload: ByteArray? = null
    private val nfcAdapter: NfcAdapter? = NfcAdapter.getDefaultAdapter(activity)

    companion object {
        private const val METHOD_CHANNEL = "dev.tinkerershaven.novabeam/nfc"
        private const val EVENT_CHANNEL = "dev.tinkerershaven.novabeam/nfc_events"
        const val MIME_TYPE = "application/x-novabeam"
        private var instance: NfcBeamPlugin? = null

        fun registerWith(engine: FlutterEngine, activity: Activity) {
            val plugin = NfcBeamPlugin(activity)
            instance = plugin
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

        fun handleIntent(intent: Intent) {
            instance?.onNfcIntent(intent)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(nfcAdapter != null && nfcAdapter!!.isEnabled)
            "startBeam" -> {
                val payload = call.argument<String>("payload")
                if (payload == null) {
                    result.error("bad_args", "payload is required", null)
                    return
                }
                pendingPayload = payload.toByteArray(Charsets.UTF_8)
                startDispatch()
                result.success(null)
            }
            "stopBeam" -> {
                stopDispatch()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startDispatch() {
        val adapter = nfcAdapter ?: return
        val intent = Intent(activity, activity.javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val pendingIntent = PendingIntent.getActivity(activity, 0, intent, flags)
        val filters = arrayOf(IntentFilter(NfcAdapter.ACTION_NDEF_DISCOVERED))
        val techLists = arrayOf(arrayOf(Ndef::class.java.name))
        adapter.enableForegroundDispatch(activity, pendingIntent, filters, techLists)
        adapter.setNdefPushMessageCallback({ createPushMessage() }, activity)
    }

    private fun stopDispatch() {
        val adapter = nfcAdapter ?: return
        adapter.setNdefPushMessageCallback(null, activity)
        adapter.disableForegroundDispatch(activity)
        pendingPayload = null
    }

    private fun createPushMessage(): NdefMessage {
        val payload = pendingPayload ?: ByteArray(0)
        val record = NdefRecord.createMime(MIME_TYPE, payload)
        return NdefMessage(arrayOf(record))
    }

    private fun onNfcIntent(intent: Intent) {
        val messages: Array<out Parcelable>? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES, NdefMessage::class.java)
                ?.mapNotNull { it as? NdefMessage }?.toTypedArray()
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES)
        }
        val message = messages?.firstOrNull() ?: return
        for (record in message.records) {
            if (record.tnf == NdefRecord.TNF_MIME_MEDIA &&
                String(record.type, Charsets.ISO_8859_1) == MIME_TYPE
            ) {
                eventSink?.success(
                    mapOf(
                        "type" to "ndef",
                        "payload" to String(record.payload, Charsets.UTF_8)
                    )
                )
            }
        }
    }
}
