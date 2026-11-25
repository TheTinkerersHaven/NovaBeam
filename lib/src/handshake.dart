import 'dart:convert';

/// Bootstrap payload exchanged over NFC as an NDEF MIME record
/// (`application/x-novabeam`).
///
/// NFC is unauthenticated and plaintext, so this carries only non-sensitive
/// bootstrap data (endpoint id + one-time token). Every field is strictly
/// validated on parse because the bytes come from whatever phone was tapped.
class BeamHandshake {
  BeamHandshake({
    required this.endpoint,
    required this.token,
    required this.deviceName,
    required this.hasFile,
  }) : version = 1;

  static const int currentVersion = 1;
  static final RegExp _hex = RegExp(r'^[0-9a-f]+$');

  final int version;
  final String endpoint;
  final String token;
  final String deviceName;
  final bool hasFile;

  Map<String, Object?> toJson() => {
        'v': version,
        'endpoint': endpoint,
        'token': token,
        'name': deviceName,
        'hasFile': hasFile,
      };

  String encode() => jsonEncode(toJson());

  factory BeamHandshake.decode(String raw) {
    final Object? decoded = jsonDecode(raw);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('handshake: expected a JSON object');
    }
    final v = decoded['v'];
    final endpoint = decoded['endpoint'];
    final token = decoded['token'];
    final name = decoded['name'];
    final hasFile = decoded['hasFile'];
    if (v is! int || v != currentVersion) {
      throw const FormatException('handshake: unsupported version');
    }
    if (endpoint is! String ||
        endpoint.isEmpty ||
        endpoint.length > 64 ||
        !_hex.hasMatch(endpoint)) {
      throw const FormatException('handshake: bad endpoint');
    }
    if (token is! String || token.length != 32 || !_hex.hasMatch(token)) {
      throw const FormatException('handshake: bad token');
    }
    if (name is! String || name.isEmpty || name.length > 64) {
      throw const FormatException('handshake: bad name');
    }
    if (hasFile is! bool) {
      throw const FormatException('handshake: bad hasFile');
    }
    return BeamHandshake(
      endpoint: endpoint,
      token: token,
      deviceName: name,
      hasFile: hasFile,
    );
  }
}
