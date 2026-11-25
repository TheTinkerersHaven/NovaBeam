import 'dart:convert';

/// Small BYTES payloads sent over the Nearby Connections link.
///
/// Two kinds exist: [TransferManifest] (describes the file that follows as a
/// STREAM payload) and [ControlMessage] (auth token echo + final ack).
/// File bytes themselves always travel as STREAM payloads, never as BYTES.

class TransferManifest {
  TransferManifest({
    required this.name,
    required this.size,
    required this.mime,
    this.sha256,
  });

  static final RegExp _hex64 = RegExp(r'^[0-9a-f]{64}$');

  final String name;
  final int size;
  final String mime;
  final String? sha256;

  Map<String, Object?> toJson() => {
        'type': 'manifest',
        'name': name,
        'size': size,
        'mime': mime,
        if (sha256 != null) 'sha256': sha256,
      };

  String encode() => jsonEncode(toJson());

  factory TransferManifest.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    final name = json['name'];
    final size = json['size'];
    final mime = json['mime'];
    final sha256 = json['sha256'];
    if (type != 'manifest') {
      throw const FormatException('manifest: wrong type');
    }
    if (name is! String || name.isEmpty || name.length > 255) {
      throw const FormatException('manifest: bad name');
    }
    if (size is! int || size < 0) {
      throw const FormatException('manifest: bad size');
    }
    if (mime is! String || mime.isEmpty || mime.length > 128) {
      throw const FormatException('manifest: bad mime');
    }
    if (sha256 != null &&
        (sha256 is! String || !_hex64.hasMatch(sha256))) {
      throw const FormatException('manifest: bad sha256');
    }
    return TransferManifest(
      name: name,
      size: size,
      mime: mime,
      sha256: sha256 as String?,
    );
  }
}

class ControlMessage {
  ControlMessage.auth(String this.token) : type = 'auth';
  ControlMessage.ack()
      : type = 'ack',
        token = null;

  static final RegExp _hex32 = RegExp(r'^[0-9a-f]{32}$');

  final String type;
  final String? token;

  Map<String, Object?> toJson() => {
        'type': type,
        if (token != null) 'token': token,
      };

  String encode() => jsonEncode(toJson());

  factory ControlMessage.fromJson(Map<String, Object?> json) {
    final type = json['type'];
    final token = json['token'];
    if (type == 'auth') {
      if (token is! String || !_hex32.hasMatch(token)) {
        throw const FormatException('auth: bad token');
      }
      return ControlMessage.auth(token);
    }
    if (type == 'ack') {
      return ControlMessage.ack();
    }
    throw const FormatException('control: unknown type');
  }
}

/// Parses any control-channel payload into a [TransferManifest] or
/// [ControlMessage]. Throws [FormatException] on anything else.
Object decodeBeamMessage(String raw) {
  final Object? decoded = jsonDecode(raw);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('message: expected a JSON object');
  }
  switch (decoded['type']) {
    case 'manifest':
      return TransferManifest.fromJson(decoded);
    case 'auth':
    case 'ack':
      return ControlMessage.fromJson(decoded);
    default:
      throw const FormatException('message: unknown type');
  }
}
