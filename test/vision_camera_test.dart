import 'package:ai_assistant/services/vision/vision_camera.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('visbot/vision');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Map<String, Object?> metadata() => {
    'reference': '0123456789abcdef0123456789abcdef',
    'mimeType': 'image/jpeg',
    'width': 640,
    'height': 480,
    'bytes': 120000,
    'rotation': 0,
    'capturedAt': 100000,
    'expiresAt': 160000,
    'canMove': false,
  };

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('capture transports request ID and returns metadata only', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return metadata();
    });
    final result = await VisionCamera().captureSnapshot('request_1');
    expect(calls.single.method, 'captureSnapshot');
    expect(calls.single.arguments, {'requestId': 'request_1'});
    expect(result.width, 640);
    expect(result.height, 480);
    expect(result.mimeType, 'image/jpeg');
    expect(result.canMove, isFalse);
    expect(result.reference, metadata()['reference']);
  });

  test('rejects invalid request before native invocation', () async {
    var called = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      called = true;
      return metadata();
    });
    await expectLater(
      VisionCamera().captureSnapshot('../image.jpg'),
      throwsA(isA<VisionCameraException>()),
    );
    expect(called, isFalse);
  });

  test('refuses movement, paths, excessive TTL and malformed image bounds', () {
    final badValues = <String, Object?>{
      'reference': '/data/user/0/private.jpg',
      'canMove': true,
      'mimeType': 'image/png',
      'bytes': 2097153,
      'width': 0,
      'height': 1921,
      'rotation': 45,
      'expiresAt': 160001,
      'capturedAt': -1,
    };
    for (final entry in badValues.entries) {
      expect(
        () => VisionSnapshot.fromMap({...metadata(), entry.key: entry.value}),
        throwsA(isA<VisionCameraException>()),
        reason: entry.key,
      );
    }
  });

  test('redacts unknown native errors', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(
        code: 'vendor_private_state',
        message: '/private/child.jpg secret',
        details: {'token': 'secret'},
      );
    });
    await expectLater(
      VisionCamera().startPrewarm(),
      throwsA(
        isA<VisionCameraException>().having(
          (error) => error.toString(),
          'safe error',
          'VisionCameraException(camera_error)',
        ),
      ),
    );
  });

  test('permission denial remains a safe code', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'permission_denied', message: 'private');
    });
    await expectLater(
      VisionCamera().startPrewarm(),
      throwsA(
        isA<VisionCameraException>().having(
          (error) => error.code,
          'code',
          'permission_denied',
        ),
      ),
    );
  });

  test('consent and cleanup calls do not implicitly capture', () async {
    final methods = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      methods.add(call.method);
      return null;
    });
    final camera = VisionCamera();
    await camera.setConsent(false);
    await camera.cancel('request_1');
    await camera.deleteSnapshot('0123456789abcdef0123456789abcdef');
    await camera.cleanupStaleSnapshots();
    await camera.close();
    expect(methods, [
      'setConsent',
      'cancel',
      'deleteSnapshot',
      'cleanupStaleSnapshots',
      'close',
    ]);
  });

  test('PIN enrollment and authorization send arguments only to native gate', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getParentGateStatus') {
        return {'pinConfigured': true, 'authorized': false};
      }
      return <String, Object?>{};
    });
    final camera = VisionCamera();
    expect(await camera.pinConfigured, isTrue);
    await camera.configureParentPin('654321', currentPin: '123456');
    await camera.authorizeParentPin('654321');
    expect(calls.map((call) => call.method), [
      'getParentGateStatus',
      'configureParentPin',
      'authorizeParentPin',
    ]);
    expect(calls[1].arguments, {'newPin': '654321', 'currentPin': '123456'});
    expect(calls[2].arguments, {'pin': '654321'});
    expect(calls[1].arguments, isNot(contains('reference')));
  });

  test('parent gate rejection is a safe code without native details', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(
        code: 'parent_auth_required',
        message: 'sensitive native detail',
      );
    });
    await expectLater(
      VisionCamera().setConsent(true),
      throwsA(isA<VisionCameraException>().having(
        (error) => error.code,
        'safe code',
        'parent_auth_required',
      )),
    );
  });

  test('events reject unknown states and never carry image data', () {
    final event = VisionCameraEvent.fromMap({
      'state': 'ready',
      'expiresAt': 160000,
      'idleExpiresAt': 130000,
    });
    expect(event.state, 'ready');
    expect(event.expiresAt, isNotNull);
    expect(
      () => VisionCameraEvent.fromMap({'state': 'preview_jpeg'}),
      throwsA(isA<VisionCameraException>()),
    );
  });
}
