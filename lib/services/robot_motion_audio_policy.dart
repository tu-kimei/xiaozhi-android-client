/// Wheel motion prioritizes hearing stop commands over playing a reply.
class RobotMotionAudioPolicy {
  bool _motionActive = false;
  bool _suppressTts = false;

  bool get suppressTts => _suppressTts;

  /// Returns true once when wheels start, so existing playback can be flushed.
  bool syncMotion(bool moving) {
    final entered = moving && !_motionActive;
    _motionActive = moving;
    if (entered) _suppressTts = true;
    return entered;
  }

  /// Keep the old reply suppressed after stopping; only a fresh reply resets it.
  bool beginTts(bool moving) {
    _suppressTts = moving;
    return moving;
  }
}
