import 'package:flutter_test/flutter_test.dart';
import 'package:novabeam/src/transfer_messages.dart';

void main() {
  test('manifest round trip', () {
    final m = TransferManifest(
      name: 'photo.jpg',
      size: 12345,
      mime: 'image/jpeg',
      sha256: 'ab' * 32,
    );
    final decoded = decodeBeamMessage(m.encode());
    expect(decoded, isA<TransferManifest>());
    final manifest = decoded as TransferManifest;
    expect(manifest.name, 'photo.jpg');
    expect(manifest.size, 12345);
    expect(manifest.mime, 'image/jpeg');
    expect(manifest.sha256, 'ab' * 32);
  });

  test('manifest without sha256 is valid', () {
    final m = TransferManifest(name: 'a.bin', size: 1, mime: 'application/octet-stream');
    final decoded = decodeBeamMessage(m.encode()) as TransferManifest;
    expect(decoded.sha256, isNull);
  });

  test('manifest rejects bad fields', () {
    expect(
      () => decodeBeamMessage(
          '{"type":"manifest","name":"","size":1,"mime":"text/plain"}'),
      throwsFormatException,
    );
    expect(
      () => decodeBeamMessage(
          '{"type":"manifest","name":"a","size":-1,"mime":"text/plain"}'),
      throwsFormatException,
    );
    expect(
      () => decodeBeamMessage(
          '{"type":"manifest","name":"a","size":1,"mime":"text/plain","sha256":"xyz"}'),
      throwsFormatException,
    );
  });

  test('control messages round trip', () {
    final auth = decodeBeamMessage(ControlMessage.auth('cd' * 16).encode());
    expect(auth, isA<ControlMessage>());
    expect((auth as ControlMessage).type, 'auth');
    expect(auth.token, 'cd' * 16);

    final ack = decodeBeamMessage(ControlMessage.ack().encode()) as ControlMessage;
    expect(ack.type, 'ack');
    expect(ack.token, isNull);
  });

  test('auth requires a 32-char hex token', () {
    expect(
      () => decodeBeamMessage('{"type":"auth","token":"short"}'),
      throwsFormatException,
    );
  });

  test('unknown message type is rejected', () {
    expect(
      () => decodeBeamMessage('{"type":"rm -rf /"}'),
      throwsFormatException,
    );
    expect(() => decodeBeamMessage('[1,2,3]'), throwsFormatException);
  });
}
