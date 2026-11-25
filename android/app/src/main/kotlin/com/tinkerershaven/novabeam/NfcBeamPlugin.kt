package com.tinkerershaven.novabeam

import android.app.Activity
import android.content.ComponentName
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.cardemulation.CardEmulation
import android.nfc.tech.IsoDep
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// NFC beam engine for phone-to-phone taps.
///
/// Android 16 removed the NDEF push APIs (the old Android Beam mechanism), so
/// this uses the modern replacement: while armed, the app runs NFC reader mode
/// (IsoDep) and sends a SELECT-by-AID APDU to whatever phone is tapped; the
/// peer's [BeamHceService] (host card emulation on the same custom AID)
/// answers with its handshake payload + SW 9000. Both phones do this on tap,
/// so each receives the other's handshake.
class NfcBeamPlugin(private val activity: Activity) :
    MethodChannel.MethodCallHandler, NfcAdapter.ReaderCallback {

    private var eventSink: EventChannel.EventSink? = null
    private val nfcAdapter: NfcAdapter? = NfcAdapter.getDefaultAdapter(activity)

    companion object {
        private const val METHOD_CHANNEL = "dev.tinkerershaven.novabeam/nfc"
        private const val EVENT_CHANNEL = "dev.tinkerershaven.novabeam/nfc_events"

        // Custom AID: 0xF0 + ASCII "NovaBeam", registered at runtime via
        // CardEmulation.registerAidsForService (hex string form).
        const val AID_HEX = "F04E6F76614265616D"
        val AID: ByteArray =
            AID_HEX.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

        @Volatile
        private var pendingPayload: ByteArray? = null

        fun currentPayload(): ByteArray? = pendingPayload

        fun registerWith(engine: FlutterEngine, activity: Activity) {
            val plugin = NfcBeamPlugin(activity)
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
        when (call.method) {
            "isAvailable" -> result.success(nfcAdapter != null && nfcAdapter!!.isEnabled)
            "startBeam" -> {
                val payload = call.argument<String>("payload")
                if (payload == null) {
                    result.error("bad_args", "payload is required", null)
                    return
                }
                pendingPayload = payload.toByteArray(Charsets.UTF_8)
                startReaderMode()
                result.success(null)
            }
            "stopBeam" -> {
                stopReaderMode()
                pendingPayload = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startReaderMode() {
        val adapter = nfcAdapter ?: return
        CardEmulation.getInstance(adapter).registerAidsForService(
            ComponentName(activity, BeamHceService::class.java),
            CardEmulation.CATEGORY_OTHER,
            listOf(AID_HEX)
        )
        adapter.enableReaderMode(
            activity,
            this,
            NfcAdapter.FLAG_READER_NFC_A or
                NfcAdapter.FLAG_READER_NFC_B or
                NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
            null
        )
    }

    private fun stopReaderMode() {
        val adapter = nfcAdapter ?: return
        try {
            CardEmulation.getInstance(adapter).removeAidsForService(
                ComponentName(activity, BeamHceService::class.java),
                CardEmulation.CATEGORY_OTHER
            )
        } catch (_: Exception) {
            // Service may already be unregistered; ignore.
        }
        adapter.disableReaderMode(activity)
    }

    override fun onTagDiscovered(tag: Tag) {
        val isoDep = IsoDep.get(tag) ?: return
        try {
            isoDep.connect()
            isoDep.timeout = 5000
            val select = ByteArray(6 + AID.size)
            select[0] = 0x00
            select[1] = 0xA4.toByte()
            select[2] = 0x04
            select[3] = 0x00
            select[4] = AID.size.toByte()
            System.arraycopy(AID, 0, select, 5, AID.size)
            select[5 + AID.size] = 0x00
            val resp = isoDep.transceive(select) ?: return
            if (resp.size >= 2 &&
                resp[resp.size - 2] == 0x90.toByte() &&
                resp[resp.size - 1] == 0x00.toByte()
            ) {
                val payload = resp.copyOf(resp.size - 2)
                eventSink?.success(
                    mapOf("type" to "ndef", "payload" to String(payload, Charsets.UTF_8))
                )
            }
        } catch (_: Exception) {
            // Peer went away mid-exchange; ignore.
        } finally {
            try {
                isoDep.close()
            } catch (_: Exception) {
            }
        }
    }
}
