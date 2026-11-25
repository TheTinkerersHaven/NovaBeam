package com.tinkerershaven.novabeam

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NfcBeamPlugin.registerWith(flutterEngine, this)
        NearbyBeamPlugin.registerWith(flutterEngine, this)
    }
}
