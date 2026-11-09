import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/services/face_controller.dart';
import 'package:ai_assistant/widgets/face_view.dart';

void main() {
  testWidgets('FaceView mounts, animates speech and disposes on Visbot', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(308, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final voice = ValueNotifier<XiaozhiVoiceState>(XiaozhiVoiceState.idle);
    final emotion = ValueNotifier<String>('happy');
    final playback = ValueNotifier(false);
    final controller = FaceController(
      voiceStateListenable: voice,
      emotionListenable: emotion,
      playbackActiveListenable: playback,
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: FaceView(controller: controller))),
    );
    expect(tester.takeException(), isNull);
    voice.value = XiaozhiVoiceState.speaking;
    playback.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 7));
    expect(tester.takeException(), isNull);
    controller.dispose();
    voice.dispose();
    emotion.dispose();
    playback.dispose();
  });

  test(
    'FaceController map các chuỗi emotion thành RobotFaceEmotion phù hợp',
    () {
      expect(FaceController.mapEmotion('happy'), RobotFaceEmotion.happy);
      expect(FaceController.mapEmotion('laughing'), RobotFaceEmotion.happy);
      expect(FaceController.mapEmotion('sad'), RobotFaceEmotion.sad);
      expect(FaceController.mapEmotion('crying'), RobotFaceEmotion.sad);
      expect(FaceController.mapEmotion('angry'), RobotFaceEmotion.angry);
      expect(
        FaceController.mapEmotion('surprised'),
        RobotFaceEmotion.surprised,
      );
      expect(FaceController.mapEmotion('thinking'), RobotFaceEmotion.thinking);
      expect(FaceController.mapEmotion('sleepy'), RobotFaceEmotion.sleepy);
      expect(
        FaceController.mapEmotion('unknown_xyz'),
        RobotFaceEmotion.neutral,
      );
    },
  );

  test(
    'FaceController ưu tiên trạng thái voiceState (thinking, listening)',
    () {
      final vState = ValueNotifier<XiaozhiVoiceState>(XiaozhiVoiceState.idle);
      final emotion = ValueNotifier<String>('happy');
      final playback = ValueNotifier(false);

      final controller = FaceController(
        voiceStateListenable: vState,
        emotionListenable: emotion,
        playbackActiveListenable: playback,
      );

      expect(controller.currentEmotion, RobotFaceEmotion.happy);

      // Khi đang nghe -> mắt tự nhiên, không dùng mặt ngạc nhiên.
      vState.value = XiaozhiVoiceState.listening;
      expect(controller.currentEmotion, RobotFaceEmotion.neutral);
      expect(controller.isListening, isTrue);

      // Khi đang nghĩ -> suy nghĩ
      vState.value = XiaozhiVoiceState.thinking;
      expect(controller.currentEmotion, RobotFaceEmotion.thinking);
      expect(controller.isThinking, isTrue);

      controller.dispose();
      vState.dispose();
      emotion.dispose();
      playback.dispose();
    },
  );

  test(
    'Face waits for actual playback and closes mouth during a buffer gap',
    () {
      final voice = ValueNotifier(XiaozhiVoiceState.thinking);
      final emotion = ValueNotifier('happy');
      final playback = ValueNotifier(false);
      final controller = FaceController(
        voiceStateListenable: voice,
        emotionListenable: emotion,
        playbackActiveListenable: playback,
      );
      voice.value =
          XiaozhiVoiceState.speaking; // server tts start, still buffering
      expect(controller.isSpeaking, isFalse);
      expect(controller.isThinking, isTrue);
      playback.value = true; // AudioTrack advances after prebuffering
      expect(controller.isSpeaking, isTrue);
      expect(controller.isThinking, isFalse);
      expect(controller.currentEmotion, RobotFaceEmotion.happy);
      playback.value = false; // underrun or the last frame has finished
      expect(controller.isSpeaking, isFalse);
      playback.value = true; // buffered output resumes
      expect(controller.isSpeaking, isTrue);
      voice.value = XiaozhiVoiceState.waiting;
      expect(
        controller.isSpeaking,
        isTrue,
      ); // output wins over early state changes
      playback.value = false;
      expect(controller.isSpeaking, isFalse);
      expect(controller.isThinking, isFalse);
      controller.dispose();
      // Disposed controllers must not retain playback/voice/emotion listeners.
      playback.value = true;
      voice.dispose();
      emotion.dispose();
      playback.dispose();
    },
  );
}
