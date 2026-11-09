import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/xiaozhi_service.dart';
import 'package:ai_assistant/services/face_controller.dart';

void main() {
  test('FaceController map các chuỗi emotion thành RobotFaceEmotion phù hợp', () {
    expect(FaceController.mapEmotion('happy'), RobotFaceEmotion.happy);
    expect(FaceController.mapEmotion('laughing'), RobotFaceEmotion.happy);
    expect(FaceController.mapEmotion('sad'), RobotFaceEmotion.sad);
    expect(FaceController.mapEmotion('crying'), RobotFaceEmotion.sad);
    expect(FaceController.mapEmotion('angry'), RobotFaceEmotion.angry);
    expect(FaceController.mapEmotion('surprised'), RobotFaceEmotion.surprised);
    expect(FaceController.mapEmotion('thinking'), RobotFaceEmotion.thinking);
    expect(FaceController.mapEmotion('sleepy'), RobotFaceEmotion.sleepy);
    expect(FaceController.mapEmotion('unknown_xyz'), RobotFaceEmotion.neutral);
  });

  test('FaceController ưu tiên trạng thái voiceState (thinking, listening)', () {
    final vState = ValueNotifier<XiaozhiVoiceState>(XiaozhiVoiceState.idle);
    final emotion = ValueNotifier<String>('happy');

    final controller = FaceController(
      voiceStateListenable: vState,
      emotionListenable: emotion,
    );

    expect(controller.currentEmotion, RobotFaceEmotion.happy);

    // Khi đang nghe -> chuyển sang ngạc nhiên/chú ý
    vState.value = XiaozhiVoiceState.listening;
    expect(controller.currentEmotion, RobotFaceEmotion.surprised);
    expect(controller.isListening, isTrue);

    // Khi đang nghĩ -> suy nghĩ
    vState.value = XiaozhiVoiceState.thinking;
    expect(controller.currentEmotion, RobotFaceEmotion.thinking);
    expect(controller.isThinking, isTrue);

    controller.dispose();
  });
}
