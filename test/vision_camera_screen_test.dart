import 'dart:async';

import 'package:ai_assistant/screens/vision_camera_screen.dart';
import 'package:ai_assistant/services/vision/vision_camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLabCamera extends VisionCamera {
  final controller = StreamController<VisionCameraEvent>.broadcast();
  bool configured = false;
  int opened = 0;
  int closed = 0;
  int captures = 0;
  int deletes = 0;
  Completer<void>? delayedClose;
  bool failClose = false;
  bool failDelete = false;
  final consent = <bool>[];

  @override
  Future<bool> get pinConfigured async => configured;
  @override
  Stream<VisionCameraEvent> get events => controller.stream;
  @override
  Future<void> configureParentPin(String newPin, {String? currentPin}) async {
    configured = true;
  }

  @override
  Future<void> authorizeParentPin(String pin) async {}
  @override
  Future<void> setConsent(bool enabled) async {
    consent.add(enabled);
  }

  @override
  Future<void> startPrewarm() async {
    opened++;
  }

  @override
  Future<VisionSnapshot> captureSnapshot(String requestId) async {
    captures++;
    return VisionSnapshot.fromMap({
      'reference': '0123456789abcdef0123456789abcdef',
      'mimeType': 'image/jpeg',
      'width': 640,
      'height': 480,
      'bytes': 120000,
      'rotation': 0,
      'capturedAt': 100000,
      'expiresAt': 160000,
      'canMove': false,
    });
  }

  @override
  Future<void> deleteSnapshot(String reference) async {
    deletes++;
    if (failDelete) throw const VisionCameraException('storage_error');
  }

  @override
  Future<void> close() async {
    closed++;
    if (delayedClose != null) await delayedClose!.future;
    if (failClose) throw const VisionCameraException('storage_error');
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('defaults off, enrollment alone never opens or uploads', (
    tester,
  ) async {
    final camera = FakeLabCamera();
    await tester.pumpWidget(
      MaterialApp(
        home: VisionCameraScreen(
          camera: camera,
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Không tải lên'), findsWidgets);
    expect(find.text('Mở camera 60 giây'), findsNothing);
    expect(camera.opened, 0);
    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Thiết lập PIN trên thiết bị'));
    await tester.pumpAndSettle();
    expect(camera.configured, isTrue);
    expect(camera.opened, 0);
    expect(camera.consent, isEmpty);
    await camera.controller.close();
  });

  testWidgets('explicit PIN, opt-in and opening precede capture and deletion', (
    tester,
  ) async {
    final camera = FakeLabCamera()..configured = true;
    await tester.pumpWidget(
      MaterialApp(
        home: VisionCameraScreen(
          camera: camera,
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(camera.opened, 0);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Xác nhận PIN cho một lần mở'));
    await tester.tap(find.text('Xác nhận PIN cho một lần mở'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vision-indicator')), findsOneWidget);
    await tester.ensureVisible(find.text('Mở camera 60 giây'));
    await tester.tap(find.text('Mở camera 60 giây'));
    await tester.pumpAndSettle();
    expect(camera.consent, [true]);
    expect(camera.opened, 1);
    camera.controller.add(const VisionCameraEvent('ready', null, null));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chụp một ảnh thử — xóa ngay'));
    await tester.pumpAndSettle();
    expect(camera.captures, 1);
    expect(camera.deletes, 1);
    expect(find.byKey(const Key('vision-metadata')), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(camera.closed, greaterThan(0));
    expect(camera.consent.last, isFalse);
    await camera.controller.close();
  });

  testWidgets('pause while permission is pending never opens camera', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'vision_parent_lab_opt_in': true});
    final camera = FakeLabCamera()..configured = true;
    final permission = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: VisionCameraScreen(
          camera: camera,
          requestPermission: () => permission.future,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.ensureVisible(find.text('Xác nhận PIN cho một lần mở'));
    await tester.tap(find.text('Xác nhận PIN cho một lần mở'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Mở camera 60 giây'));
    await tester.tap(find.text('Mở camera 60 giây'));
    await tester.pump();
    expect(find.byKey(const Key('vision-active-indicator')), findsOneWidget);
    expect(camera.opened, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    permission.complete(true);
    await tester.pumpAndSettle();
    expect(camera.opened, 0);
    expect(camera.consent, isNot(contains(true)));
    await camera.controller.close();
  });

  testWidgets(
    'delayed close keeps stopping indicator until native confirmation',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'vision_parent_lab_opt_in': true,
      });
      final camera = FakeLabCamera()..configured = true;
      await tester.pumpWidget(
        MaterialApp(
          home: VisionCameraScreen(
            camera: camera,
            requestPermission: () async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '123456');
      await tester.tap(find.text('Xác nhận PIN cho một lần mở'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mở camera 60 giây'));
      await tester.pumpAndSettle();
      camera.delayedClose = Completer<void>();
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dừng camera và xóa ảnh tạm'));
      await tester.pump();
      expect(find.textContaining('CAMERA ĐANG ĐÓNG'), findsOneWidget);
      camera.controller.add(const VisionCameraEvent('closed', null, null));
      await tester.pump();
      expect(find.textContaining('CAMERA ĐANG ĐÓNG'), findsOneWidget);
      expect(
        tester
            .widget<ElevatedButton>(
              find.widgetWithText(ElevatedButton, 'Mở camera 60 giây'),
            )
            .onPressed,
        isNull,
      );
      camera.delayedClose!.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('CAMERA ĐANG ĐÓNG'), findsNothing);
      expect(find.textContaining('Đã xác nhận đóng camera'), findsOneWidget);
      await camera.controller.close();
    },
  );

  testWidgets('cleanup failure remains visible after late closed event', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'vision_parent_lab_opt_in': true});
    final camera =
        FakeLabCamera()
          ..configured = true
          ..failClose = true;
    await tester.pumpWidget(
      MaterialApp(
        home: VisionCameraScreen(
          camera: camera,
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Xác nhận PIN cho một lần mở'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mở camera 60 giây'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dừng camera và xóa ảnh tạm'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không thể xác nhận đã đóng'), findsWidgets);
    camera.controller.add(const VisionCameraEvent('closed', null, null));
    await tester.pump();
    expect(find.textContaining('Không thể xác nhận đã đóng'), findsWidgets);
    expect(find.textContaining('Đã xác nhận đóng camera'), findsNothing);
    camera.failClose = false;
    await tester.tap(find.text('Thử lại dọn dẹp camera'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Đã xác nhận đóng camera'), findsOneWidget);
    await camera.controller.close();
  });

  testWidgets('snapshot deletion failure never claims deletion', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'vision_parent_lab_opt_in': true});
    final camera =
        FakeLabCamera()
          ..configured = true
          ..failDelete = true
          ..failClose = true;
    await tester.pumpWidget(
      MaterialApp(
        home: VisionCameraScreen(
          camera: camera,
          requestPermission: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.tap(find.text('Xác nhận PIN cho một lần mở'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mở camera 60 giây'));
    await tester.pumpAndSettle();
    camera.controller.add(const VisionCameraEvent('ready', null, null));
    await tester.pump();
    await tester.drag(find.byType(ListView), const Offset(0, -180));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chụp một ảnh thử — xóa ngay'));
    await tester.pumpAndSettle();
    expect(camera.deletes, 1);
    expect(camera.closed, greaterThan(0));
    expect(find.textContaining('Đã chụp và xóa'), findsNothing);
    expect(find.textContaining('Không thể xác nhận đã đóng'), findsWidgets);
    await camera.controller.close();
  });
}
