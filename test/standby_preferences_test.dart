import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ai_assistant/services/robot_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'five-minute default and local keyword options survive restart',
    () async {
      SharedPreferences.setMockInitialValues({});
      final p = RobotPreferences();
      await p.load();
      expect(p.autoSleep, isTrue);
      expect(p.sleepSeconds, 300);
      expect(p.wakePhrase, 'Hey Doradino');
      await p.update(
        sleepAfter: 600,
        phrase: 'Hello Robot',
        wakeSense: WakeSensitivity.high,
        wakeEnabled: false,
      );
      final restored = RobotPreferences();
      await restored.load();
      expect(restored.sleepSeconds, 600);
      expect(restored.wakePhrase, 'Hello Robot');
      expect(restored.wakeWordEnabled, isFalse);
      expect(restored.wakeSensitivity, WakeSensitivity.high);
      await restored.reset();
      expect(restored.sleepSeconds, 300);
      expect(restored.wakePhrase, 'Hey Doradino');
    },
  );
  test('bad stored or caller phrases cannot reach native inference', () async {
    SharedPreferences.setMockInitialValues({'robot_wake_phrase': 'bad @input'});
    final p = RobotPreferences();
    await p.load();
    expect(p.wakePhrase, 'Hey Doradino');
    await expectLater(p.update(phrase: 'bad @input'), throwsArgumentError);
    expect(p.wakePhrase, 'Hey Doradino');
  });
}
