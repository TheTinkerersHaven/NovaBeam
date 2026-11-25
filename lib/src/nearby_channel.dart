import 'dart:typed_data';

import 'package:flutter/services.dart';

/// One event arriving from the native Nearby Connections wrapper.
class NearbyEvent {
  NearbyEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  factory NearbyEvent.from(dynamic raw) {
    final map = Map<String, dynamic>.from(raw as Map);
    return NearbyEvent(map['type'] as String? ?? 'unknown', map);
  }
}

/// Thin wrapper over the native Nearby Connections (ConnectionsClient) plugin.
class NearbyChannel {
  NearbyChannel({MethodChannel? methodChannel, EventChannel? eventChannel})
      : _method = methodChannel ??
            const MethodChannel('dev.tinkerershaven.novabeam/nearby'),
        _events = eventChannel ??
            const EventChannel('dev.tinkerershaven.novabeam/nearby_events');

  static const String serviceId = 'dev.tinkerershaven.novabeam';

  final MethodChannel _method;
  final EventChannel _events;

  Future<void> init() =>
      _method.invokeMethod<void>('init', {'serviceId': serviceId});

  Future<void> requestPermissions() =>
      _method.invokeMethod<void>('requestPermissions');

  Future<void> startAdvertising(String endpointName) =>
      _method.invokeMethod<void>('startAdvertising', {'name': endpointName});

  Future<void> startDiscovery() => _method.invokeMethod<void>('startDiscovery');

  Future<void> stopAll() => _method.invokeMethod<void>('stopAll');

  Future<void> requestConnection(String endpointId) =>
      _method.invokeMethod<void>('requestConnection', {'endpointId': endpointId});

  Future<void> acceptConnection(String endpointId) =>
      _method.invokeMethod<void>('acceptConnection', {'endpointId': endpointId});

  Future<void> rejectConnection(String endpointId) =>
      _method.invokeMethod<void>('rejectConnection', {'endpointId': endpointId});

  /// Sends a small JSON control message as a BYTES payload.
  Future<void> sendControl(String endpointId, String json) =>
      _method.invokeMethod<void>('sendControl', {
        'endpointId': endpointId,
        'json': json,
      });

  /// Sends a file as a STREAM payload. Either [bytes] or [path] must be set;
  /// [path] may be a content:// URI from the system file picker.
  Future<void> sendFile(
    String endpointId, {
    required String name,
    required int size,
    required String mime,
    Uint8List? bytes,
    String? path,
  }) =>
      _method.invokeMethod<void>('sendFile', {
        'endpointId': endpointId,
        'name': name,
        'size': size,
        'mime': mime,
        if (bytes != null) 'bytes': bytes,
        if (path != null) 'path': path,
      });

  Stream<NearbyEvent> events() =>
      _events.receiveBroadcastStream().map(NearbyEvent.from);
}
