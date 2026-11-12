import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/services/robot_preferences.dart';
import 'package:ai_assistant/widgets/robot_settings_panel.dart';

void main() {
  testWidgets(
    'Vietnamese settings fit Visbot, preview works, reset requires confirmation',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = MethodChannel('com.lhht.ai_assistant/robot');
      messenger.setMockMethodCallHandler(
        channel,
        (call) async => call.method == 'isAvailable' ? true : null,
      );
      tester.view.physicalSize = const Size(308, 240);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: RobotSettingsPanel())),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.text('Xem thử mặt'), 100, scrollable: find.byType(Scrollable).first);
      await Scrollable.ensureVisible(
        tester.element(find.text('Xem thử mặt')),
        alignment: .5,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xem thử mặt'));
      await tester.pumpAndSettle();
      expect(find.text('Xem thử khuôn mặt'), findsOneWidget);
      await tester.tap(find.text('Nói'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await RobotPreferences.instance.update(
        voice: true,
        wheels: true,
        autoMove: true,
      );
      await tester.scrollUntilVisible(
        find.text('Khôi phục cài đặt robot mặc định'),
        180, scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Khôi phục cài đặt robot mặc định'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Khôi phục cài đặt robot mặc định'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hủy'));
      await tester.pumpAndSettle();
      expect(RobotPreferences.instance.wheelsEnabled, isTrue);
      await tester.tap(find.text('Khôi phục cài đặt robot mặc định'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Khôi phục'));
      await tester.pumpAndSettle();
      expect(RobotPreferences.instance.wheelsEnabled, isFalse);
      expect(RobotPreferences.instance.moveWhenConversing, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 7));
    },
  );
}
