package com.tinkerershaven.novabeam

import android.content.Intent
import android.nfc.NfcAdapter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NfcBeamPlugin.registerWith(flutterEngine, this)
        NearbyBeamPlugin.registerWith(flutterEngine, this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        when (intent.action) {
            NfcAdapter.ACTION_NDEF_DISCOVERED,
            NfcAdapter.ACTION_TECH_DISCOVERED,
            NfcAdapter.ACTION_TAG_DISCOVERED -> NfcBeamPlugin.handleIntent(intent)
        }
    }
}
