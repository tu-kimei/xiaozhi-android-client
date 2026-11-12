import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/robot_motion_audio_policy.dart';

void main() {
  test('motion flushes once and suppresses the old reply through stopping', () {
    final policy = RobotMotionAudioPolicy();
    expect(policy.beginTts(false), isFalse);
    expect(policy.suppressTts, isFalse);
    expect(policy.syncMotion(true), isTrue);
    expect(policy.suppressTts, isTrue);
    expect(policy.syncMotion(true), isFalse);
    expect(policy.syncMotion(false), isFalse);
    expect(policy.suppressTts, isTrue);
    expect(policy.beginTts(false), isFalse);
    expect(policy.suppressTts, isFalse);
  });

  test(
    'a reply during motion keeps listening and still flushes old playback',
    () {
      final policy = RobotMotionAudioPolicy();
      expect(policy.beginTts(true), isTrue);
      expect(policy.suppressTts, isTrue);
      expect(policy.syncMotion(true), isTrue);
      expect(policy.syncMotion(false), isFalse);
      expect(policy.syncMotion(true), isTrue);
    },
  );
}
