import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'handshake.dart';
import 'nearby_channel.dart';
import 'nfc_beam_channel.dart';
import 'transfer_messages.dart';

enum BeamStatus { idle, beaming, connecting, transferring, done, error }

enum BeamRole { none, sender, receiver }

/// Orchestrates one beam session:
///
/// 1. Both phones enter beam mode: NFC NDEF push armed + Nearby
///    advertise/discovery running.
/// 2. On tap, each phone receives the other's [BeamHandshake] over NFC.
/// 3. The phone without a file (or, if both have one, the one with the
///    smaller endpoint id) requests a Nearby connection to the peer.
/// 4. Receiver echoes the NFC token over the encrypted Nearby link; the
///    sender verifies it before sending the manifest + file.
class BeamController extends ChangeNotifier {
  BeamController({NfcBeamChannel? nfc, NearbyChannel? nearby})
      : _nfc = nfc ?? NfcBeamChannel(),
        _nearby = nearby ?? NearbyChannel();

  final NfcBeamChannel _nfc;
  final NearbyChannel _nearby;

  BeamStatus status = BeamStatus.idle;
  BeamRole role = BeamRole.none;
  String endpoint = '';
  String token = '';
  bool nfcAvailable = false;

  PlatformFile? file;
  Uint8List? fileBytes;

  String? peerEndpoint;
  String? peerName;
  TransferManifest? incoming;

  double progress = 0;
  int transferred = 0;
  int total = 0;

  String? receivedPath;
  bool? shaOk;
  String? errorMessage;
  final List<String> logLines = [];

  StreamSubscription<String>? _nfcSub;
  StreamSubscription<NearbyEvent>? _nearbySub;
  bool _initialised = false;
  bool _connectionRequested = false;

  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    endpoint = _randomHex(4);
    token = _randomHex(16);
    nfcAvailable = await _nfc.isAvailable();
    await _nearby.init();
    _nfcSub = _nfc.ndefPayloads().listen(_onNdef, onError: _logNfcError);
    _nearbySub = _nearby.events().listen(_onNearbyEvent, onError: _logNfcError);
    _log(nfcAvailable ? 'NFC ready' : 'NFC not available on this device');
    notifyListeners();
  }

  Future<void> pickFile() async {
    final result =
        await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (result == null || result.files.isEmpty) return;
    file = result.files.first;
    fileBytes = file!.bytes ?? await file!.readAsBytes();
    errorMessage = null;
    _log('Picked ${file!.name} (${file!.size} bytes)');
    notifyListeners();
  }

  void clearFile() {
    file = null;
    fileBytes = null;
    notifyListeners();
  }

  Future<void> toggleBeaming() async {
    if (status == BeamStatus.beaming ||
        status == BeamStatus.connecting ||
        status == BeamStatus.transferring) {
      await stopBeaming();
      return;
    }
    await startBeaming();
  }

  Future<void> startBeaming() async {
    errorMessage = null;
    receivedPath = null;
    shaOk = null;
    incoming = null;
    progress = 0;
    transferred = 0;
    total = 0;
    role = BeamRole.none;
    peerEndpoint = null;
    peerName = null;
    _connectionRequested = false;
    try {
      await _nearby.requestPermissions();
      final handshake = BeamHandshake(
        endpoint: endpoint,
        token: token,
        deviceName: 'NovaBeam-$endpoint',
        hasFile: file != null,
      );
      await _nfc.startBeam(handshake.encode());
      await _nearby.startAdvertising(endpoint);
      await _nearby.startDiscovery();
      status = BeamStatus.beaming;
      _log(file == null
          ? 'Beaming (receive-only) — tap another phone'
          : 'Beaming ${file!.name} — tap another phone');
    } on PlatformException catch (e) {
      status = BeamStatus.error;
      errorMessage = 'Failed to start beaming: ${e.message}';
    }
    notifyListeners();
  }

  Future<void> stopBeaming() async {
    try {
      await _nfc.stopBeam();
      await _nearby.stopAll();
    } catch (_) {
      // Best effort teardown.
    }
    status = BeamStatus.idle;
    role = BeamRole.none;
    notifyListeners();
  }

  Future<void> _onNdef(String raw) async {
    final BeamHandshake peer;
    try {
      peer = BeamHandshake.decode(raw);
    } catch (e) {
      _log('Ignored malformed NDEF payload: $e');
      return;
    }
    if (peer.endpoint == endpoint) return;
    peerEndpoint = peer.endpoint;
    peerName = peer.deviceName;
    _log('NFC tap from ${peer.deviceName}');

    if (peer.hasFile && file == null) {
      role = BeamRole.receiver;
      await _requestPeerConnection();
    } else if (peer.hasFile && file != null) {
      if (peer.endpoint.compareTo(endpoint) < 0) {
        role = BeamRole.receiver;
        await _requestPeerConnection();
      } else {
        role = BeamRole.sender;
        _log('Both have files; waiting for ${peer.deviceName} to connect');
      }
    } else if (!peer.hasFile && file != null) {
      role = BeamRole.sender;
      _log('Waiting for ${peer.deviceName} to connect...');
    } else {
      _log('${peer.deviceName} has nothing to send');
    }
    notifyListeners();
  }

  Future<void> _requestPeerConnection() async {
    final target = peerEndpoint;
    if (target == null) return;
    status = BeamStatus.connecting;
    try {
      await _nearby.requestConnection(target);
      _connectionRequested = true;
    } on PlatformException catch (e) {
      _connectionRequested = false;
      _log('Connection request deferred (${e.message}); waiting for discovery');
    }
  }

  Future<void> _onNearbyEvent(NearbyEvent event) async {
    switch (event.type) {
      case 'endpointFound':
        _log('Discovered ${event.data['name']}');
        if (role == BeamRole.receiver &&
            !_connectionRequested &&
            event.data['endpointId'] == peerEndpoint) {
          await _requestPeerConnection();
        }
        break;
      case 'connectionInitiated':
        final ep = event.data['endpointId'] as String;
        peerEndpoint ??= ep;
        _log('Connection initiated by $ep (auth digits: ${event.data['digits']})');
        if (file != null) {
          role = BeamRole.sender;
          await _nearby.acceptConnection(ep);
        } else {
          await _nearby.rejectConnection(ep);
        }
        break;
      case 'connectionResult':
        final ep = event.data['endpointId'] as String;
        final ok = event.data['ok'] == true;
        _log('Connection with $ep ${ok ? 'established' : 'failed (status ${event.data['status']})'}');
        if (!ok) {
          if (role == BeamRole.receiver) {
            role = BeamRole.none;
            _connectionRequested = false;
            status = BeamStatus.beaming;
          }
          break;
        }
        if (role == BeamRole.receiver) {
          await _nearby.sendControl(ep, ControlMessage.auth(token).encode());
        }
        break;
      case 'control':
        await _onControl(
            event.data['endpointId'] as String, event.data['data'] as String? ?? '');
        break;
      case 'transferUpdate':
        _onTransferUpdate(event.data);
        break;
      case 'fileReceived':
        receivedPath = event.data['path'] as String?;
        shaOk = event.data['shaOk'] == true;
        status = BeamStatus.done;
        _log('Received ${event.data['name']} -> $receivedPath '
            '(sha256 ${shaOk == true ? 'verified' : 'MISMATCH/unknown'})');
        await _nearby.sendControl(
            event.data['endpointId'] as String, ControlMessage.ack().encode());
        break;
      case 'transferError':
        status = BeamStatus.error;
        errorMessage = 'Transfer error: ${event.data['error']}';
        break;
      case 'disconnected':
        _log('Disconnected from ${event.data['endpointId']}');
        if (status == BeamStatus.connecting || status == BeamStatus.transferring) {
          role = BeamRole.none;
          _connectionRequested = false;
          status = BeamStatus.beaming;
        }
        break;
      default:
        break;
    }
    notifyListeners();
  }

  Future<void> _onControl(String endpointId, String data) async {
    final Object message;
    try {
      message = decodeBeamMessage(data);
    } catch (_) {
      _log('Ignored unknown control message');
      return;
    }
    if (message is ControlMessage && message.type == 'auth') {
      if (role == BeamRole.sender && message.token == token) {
        _log('Peer authenticated via NFC token, sending file');
        await _sendFile(endpointId);
      } else {
        _log('Auth token mismatch, ignoring peer');
      }
    } else if (message is TransferManifest) {
      incoming = message;
      total = message.size;
      transferred = 0;
      progress = 0;
      status = BeamStatus.transferring;
      _log('Incoming ${message.name} (${message.size} bytes, ${message.mime})');
    } else if (message is ControlMessage && message.type == 'ack') {
      status = BeamStatus.done;
      _log('Peer confirmed receipt');
    }
  }

  Future<void> _sendFile(String endpointId) async {
    final f = file;
    if (f == null) return;
    final bytes = fileBytes ?? await f.readAsBytes();
    fileBytes = bytes;
    final digest = sha256.convert(bytes).toString();
    final manifest = TransferManifest(
      name: f.name,
      size: bytes.length,
      mime: _mimeFor(f.name),
      sha256: digest,
    );
    status = BeamStatus.transferring;
    total = bytes.length;
    await _nearby.sendControl(endpointId, manifest.encode());
    await _nearby.sendFile(
      endpointId,
      name: f.name,
      size: bytes.length,
      mime: manifest.mime,
      bytes: bytes,
      path: f.path,
    );
    _log('Sending ${f.name} (${bytes.length} bytes)...');
  }

  void _onTransferUpdate(Map<String, dynamic> data) {
    transferred = (data['transferred'] as num?)?.toInt() ?? transferred;
    final t = (data['total'] as num?)?.toInt() ?? 0;
    if (t > 0) total = t;
    if (total > 0) progress = (transferred / total).clamp(0.0, 1.0);
    final s = data['status'];
    if (s == 3) {
      status = BeamStatus.error;
      errorMessage = 'Transfer failed on the link';
    }
  }

  void _logNfcError(Object e) => _log('Channel error: $e');

  void _log(String line) {
    final time = DateTime.now().toIso8601String().substring(11, 19);
    logLines.add('[$time] $line');
    if (logLines.length > 120) logLines.removeAt(0);
  }

  static String _randomHex(int byteCount) {
    final rng = Random.secure();
    final bytes = List<int>.generate(byteCount, (_) => rng.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  static String _mimeFor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    const map = {
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'json': 'application/json',
      'mp4': 'video/mp4',
      'mov': 'video/quicktime',
      'mp3': 'audio/mpeg',
      'zip': 'application/zip',
      'apk': 'application/vnd.android.package-archive',
    };
    return map[ext] ?? 'application/octet-stream';
  }

  @override
  void dispose() {
    _nfcSub?.cancel();
    _nearbySub?.cancel();
    stopBeaming();
    super.dispose();
  }
}
