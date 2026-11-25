import 'package:flutter/services.dart';

/// Thin wrapper over the native NFC beam plugin.
///
/// `startBeam` arms Android foreground NDEF dispatch + the NDEF push callback
/// (the Android Beam successor); incoming pushes arrive on [ndefPayloads].
class NfcBeamChannel {
  NfcBeamChannel({MethodChannel? methodChannel, EventChannel? eventChannel})
      : _method = methodChannel ??
            const MethodChannel('dev.tinkerershaven.novabeam/nfc'),
        _events = eventChannel ??
            const EventChannel('dev.tinkerershaven.novabeam/nfc_events');

  final MethodChannel _method;
  final EventChannel _events;

  Future<bool> isAvailable() async =>
      await _method.invokeMethod<bool>('isAvailable') ?? false;

  Future<void> startBeam(String payload) =>
      _method.invokeMethod<void>('startBeam', {'payload': payload});

  Future<void> stopBeam() => _method.invokeMethod<void>('stopBeam');

  Stream<String> ndefPayloads() =>
      _events.receiveBroadcastStream().map((event) {
        final map = Map<String, dynamic>.from(event as Map);
        if (map['type'] == 'ndef' && map['payload'] is String) {
          return map['payload'] as String;
        }
        throw const FormatException('unexpected nfc event');
      });
}
