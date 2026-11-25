import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novabeam/src/handshake.dart';

void main() {
  BeamHandshake sample() => BeamHandshake(
        endpoint: 'a1b2c3d4',
        token: '00112233445566778899aabbccddeeff',
        deviceName: 'NovaBeam-a1b2c3d4',
        hasFile: true,
      );

  String encode(Map<String, Object?> json) => jsonEncode(json);

  test('encode/decode round trip', () {
    final h = sample();
    final decoded = BeamHandshake.decode(h.encode());
    expect(decoded.version, 1);
    expect(decoded.endpoint, h.endpoint);
    expect(decoded.token, h.token);
    expect(decoded.deviceName, h.deviceName);
    expect(decoded.hasFile, isTrue);
  });

  test('rejects non-object payloads', () {
    expect(() => BeamHandshake.decode('"hello"'), throwsFormatException);
    expect(() => BeamHandshake.decode('42'), throwsFormatException);
    expect(() => BeamHandshake.decode('not json'), throwsFormatException);
  });

  test('rejects unsupported version', () {
    expect(
      () => BeamHandshake.decode(
          '{"v":2,"endpoint":"a1b2c3d4","token":"00112233445566778899aabbccddeeff","name":"x","hasFile":false}'),
      throwsFormatException,
    );
  });

  test('rejects malformed endpoint and token', () {
    final base = sample().toJson();
    base['endpoint'] = 'not-hex!!';
    expect(() => BeamHandshake.decode(encode(base)), throwsFormatException);
    base['endpoint'] = 'a1b2c3d4';
    base['token'] = 'tooshort';
    expect(() => BeamHandshake.decode(encode(base)), throwsFormatException);
  });

  test('rejects wrong types', () {
    final base = sample().toJson();
    base['hasFile'] = 'yes';
    expect(() => BeamHandshake.decode(encode(base)), throwsFormatException);
    base['hasFile'] = true;
    base['name'] = 123;
    expect(() => BeamHandshake.decode(encode(base)), throwsFormatException);
  });
}
