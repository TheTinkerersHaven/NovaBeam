package com.tinkerershaven.novabeam

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/// Host card emulation endpoint for the tap handshake. When another phone
/// running NovaBeam taps this one, its reader sends SELECT-by-AID and this
/// service answers with this device's current handshake payload + SW 9000.
class BeamHceService : HostApduService() {

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        if (commandApdu.size >= 2 && commandApdu[1] == 0xA4.toByte()) {
            val payload = NfcBeamPlugin.currentPayload() ?: ByteArray(0)
            return payload + byteArrayOf(0x90.toByte(), 0x00)
        }
        return byteArrayOf(0x6D.toByte(), 0x00)
    }

    override fun onDeactivated(reason: Int) {
        // No state to clean up.
    }
}
