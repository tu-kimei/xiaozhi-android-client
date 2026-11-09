import 'dart:async';

import 'package:ai_assistant/utils/pcm_stream_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('xiaozhi/pcm_player');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  Future<void> outputState(bool active) async {
    final done = Completer<void>();
    messenger.handlePlatformMessage(
      channel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('playbackState', active),
      ),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'Only native output progress opens the mouth; stop and release reset it',
    () async {
      final player = PcmStreamPlayer();
      await player.initialize(sampleRate: 24000);
      await player.play();
      await player.feed(Uint8List(28800));
      expect(PcmStreamPlayer.playbackActive.value, isFalse);
      await outputState(true);
      expect(PcmStreamPlayer.playbackActive.value, isTrue);
      await outputState(false); // output stalled / drained
      expect(PcmStreamPlayer.playbackActive.value, isFalse);
      await outputState(true);
      await player.stop();
      expect(PcmStreamPlayer.playbackActive.value, isFalse);
      await outputState(true);
      await player.release();
      expect(PcmStreamPlayer.playbackActive.value, isFalse);
    },
  );
}
