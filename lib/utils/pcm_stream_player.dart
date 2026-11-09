import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Dart side of the app's native PcmStreamPlayer (16-bit mono PCM).
///
/// Same method names as flutter_pcm_player, but the native AudioTrack has a
/// 4x buffer and an URGENT_AUDIO writer thread so replies don't stutter.
class PcmStreamPlayer {
  static const _channel = MethodChannel('xiaozhi/pcm_player');
  static final _playbackActive = ValueNotifier(false);

  /// True only while the native AudioTrack playback head is advancing.
  /// Receiving TTS packets or filling the jitter buffer does not set this.
  static ValueListenable<bool> get playbackActive => _playbackActive;

  PcmStreamPlayer() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'playbackState' && call.arguments is bool) {
        _playbackActive.value = call.arguments as bool;
      }
    });
  }

  Future<void> initialize({required int sampleRate}) =>
      _channel.invokeMethod('initialize', {'sampleRate': sampleRate});

  Future<void> play() => _channel.invokeMethod('play');

  /// Drops queued audio immediately; the player stays ready for more.
  Future<void> stop() {
    _playbackActive.value = false;
    return _channel.invokeMethod('stop');
  }

  Future<void> feed(Uint8List pcm) =>
      _channel.invokeMethod('feed', {'data': pcm});

  Future<void> release() {
    _playbackActive.value = false;
    return _channel.invokeMethod('release');
  }
}
