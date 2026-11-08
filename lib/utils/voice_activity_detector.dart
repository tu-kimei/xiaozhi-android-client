import 'dart:math' as math;
import 'dart:typed_data';

/// VAD 事件
enum VadEvent { none, speechStart, speechEnd }

/// 基于能量 + 浊音度（基音周期性）的语音活动检测（每帧 60ms）。
///
/// - 浊音度：人声在 80–450Hz 有稳定的基音周期，风扇、碰撞、白噪声没有；
///   只有“够响且有基音”的帧才算开口，过滤大部分环境噪声
/// - 说话中音量比本句峰值低 [dropDb] 以上、或持续无基音，都算安静
/// - 噪声底噪自适应：非语音帧时缓慢跟踪环境噪声，适应吵闹/安静的房间
/// - 语音阈值 = 噪声底噪 + [speechMarginDb]
/// - 连续 [startFrames] 帧超过阈值才算开始说话（过滤短促杂音）
/// - 开始后连续 [endFrames] 帧低于阈值算说完（允许孩子说话中间停顿）
/// - 单句最长 [maxFrames] 帧，超过强制结束
class VoiceActivityDetector {
  final double speechMarginDb;
  final double minSpeechDb;
  final int startFrames;
  final int endFrames;
  final int maxFrames;

  /// 开头先用这些帧测量环境底噪，期间不触发
  static const int calibrationFrames = 8; // ~480ms
  /// 说话中低于（开始阈值 - hysteresisDb）才算安静，避免在阈值附近抖动
  static const double hysteresisDb = 0;

  /// 开口所需的最低浊音度（归一化自相关峰值）。
  /// 实测 Visbot：人声 0.74–0.96，房间噪声多在 0.1–0.5
  static const double voicedMin = 0.6;

  /// 说话中低于此浊音度的帧按“安静”计
  static const double unvoicedBelow = 0.3;

  /// 比本句峰值低这么多就算说完（拖尾的环境噪声不再延长语句）
  static const double dropDb = 18;

  double _noiseDb = 0;
  int _calibrated = 0;
  int _aboveCount = 0;
  int _belowCount = 0;
  int _speechFrames = 0;
  bool _inSpeech = false;
  double _peakDb = 0;

  VoiceActivityDetector({
    this.speechMarginDb = 6,
    this.minSpeechDb = 50,
    this.startFrames = 4, // 240ms
    this.endFrames = 13, // ~800ms
    this.maxFrames = 200, // 12s
  });

  bool get inSpeech => _inSpeech;
  double get noiseDb => _noiseDb;
  double get thresholdDb => math.max(_noiseDb + speechMarginDb, minSpeechDb);

  /// 当前语句已持续的毫秒数
  int get speechMs => _speechFrames * 60;

  void reset() {
    _aboveCount = 0;
    _belowCount = 0;
    _speechFrames = 0;
    _inSpeech = false;
    _peakDb = 0;
  }

  /// 计算一帧 PCM16(小端) 的能量，单位 dB（满幅约 90dB）
  static double frameDb(Uint8List pcm) {
    final bd = ByteData.sublistView(pcm);
    final n = pcm.length ~/ 2;
    if (n == 0) return 0;
    double sum = 0;
    for (int i = 0; i < n; i++) {
      final v = bd.getInt16(i * 2, Endian.little).toDouble();
      sum += v * v;
    }
    final rms = math.sqrt(sum / n);
    return 20 * math.log(rms + 1) / math.ln10;
  }

  /// 浊音度：去直流后 2 倍降采样到 8kHz，在 80–450Hz 基音周期范围内
  /// 求归一化自相关的最大值。人声浊音段通常 > 0.5，噪声 < 0.3。
  static double voicing(Uint8List pcm) {
    final bd = ByteData.sublistView(pcm);
    final n = pcm.length ~/ 4; // 降采样后的点数
    if (n < 220) return 0;
    final x = Float64List(n);
    double mean = 0;
    for (int i = 0; i < n; i++) {
      final a = bd.getInt16(i * 4, Endian.little);
      final b = bd.getInt16(i * 4 + 2, Endian.little);
      x[i] = (a + b) / 2;
      mean += x[i];
    }
    mean /= n;
    for (int i = 0; i < n; i++) {
      x[i] -= mean;
    }
    const minLag = 18; // 8000/18 ≈ 444Hz
    const maxLag = 100; // 8000/100 = 80Hz
    double best = 0;
    for (int lag = minLag; lag <= maxLag; lag++) {
      double xy = 0, xx = 0, yy = 0;
      for (int i = 0; i + lag < n; i++) {
        final a = x[i], b = x[i + lag];
        xy += a * b;
        xx += a * a;
        yy += b * b;
      }
      if (xx <= 0 || yy <= 0) continue;
      final r = xy / math.sqrt(xx * yy);
      if (r > best) best = r;
    }
    return best;
  }

  VadEvent process(double db, {double voicing = 1.0}) {
    if (_calibrated < calibrationFrames) {
      _calibrated++;
      _noiseDb += (db - _noiseDb) / _calibrated; // 求平均
      return VadEvent.none;
    }

    if (!_inSpeech) {
      final loud = db >= thresholdDb;
      final speechLike = loud && voicing >= voicedMin;
      if (speechLike) {
        _aboveCount++;
        // 持续的高噪声（风扇、电视）也会被慢慢吸收进底噪
        _noiseDb += (db - _noiseDb) * 0.01;
      } else if (loud) {
        // 响但无基音（碰撞、风扇、白噪声）：不算开口，慢慢并入底噪
        _aboveCount = 0;
        _noiseDb += (db - _noiseDb) * 0.02;
      } else {
        _aboveCount = 0;
        // 上升慢、下降快
        final alpha = db > _noiseDb ? 0.05 : 0.2;
        _noiseDb += (db - _noiseDb) * alpha;
      }
      if (_aboveCount >= startFrames) {
        _inSpeech = true;
        _peakDb = db;
        _speechFrames = _aboveCount;
        _belowCount = 0;
        return VadEvent.speechStart;
      }
      return VadEvent.none;
    }

    _speechFrames++;
    if (db > _peakDb) _peakDb = db;
    final floor = math.max(thresholdDb - hysteresisDb, _peakDb - dropDb);
    final stillSpeaking = db >= floor && voicing >= unvoicedBelow;
    _belowCount = stillSpeaking ? 0 : _belowCount + 1;
    if (_belowCount >= endFrames || _speechFrames >= maxFrames) {
      reset();
      return VadEvent.speechEnd;
    }
    return VadEvent.none;
  }
}
