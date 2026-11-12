import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/services/robot_preferences.dart';
import 'package:ai_assistant/widgets/standby_settings_panel.dart';

void main() {
  testWidgets(
    'custom wake phrase validates, saves and confirms in Vietnamese',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: StandbySettingsPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Này robot');
      final save = find.text('Lưu câu gọi đánh thức');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(
        find.text('Nhập 2–5 từ bằng chữ cái tiếng Anh, tối đa 48 ký tự.'),
        findsOneWidget,
      );
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Hey Doredino');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(RobotPreferences.instance.wakePhrase, 'Hey Doredino');
      final restored = RobotPreferences();
      await restored.load();
      expect(restored.wakePhrase, 'Hey Doredino');
      expect(find.text('Đã lưu câu gọi “Hey Doredino”.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
