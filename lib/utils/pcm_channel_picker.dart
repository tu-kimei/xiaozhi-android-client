import 'dart:math' as math;
import 'dart:typed_data';

/// Some devices (e.g. the UBTech Visbot mic array) ignore the requested
/// mono format and stream several interleaved int16 channels while the
/// AudioRecord still reports mono. Treating that as mono garbles speech
/// (the server's ASR hears noise), so this measures the real byte rate for
/// a short window, works out how many channels are interleaved, and from
/// then on keeps only the loudest channel.
class PcmChannelPicker {
  /// Expected bytes per second for the requested mono int16 stream.
  final int expectedBytesPerSecond;

  /// Ignore the first chunks: the recorder may flush a backlog at start.
  final int warmupMs;

  /// Length of the rate measurement window after the warmup.
  final int measureMs;

  PcmChannelPicker({
    required this.expectedBytesPerSecond,
    this.warmupMs = 300,
    this.measureMs = 1000,
  });

  /// Result shared by every recording in this process: the hardware does not
  /// change, and re-detecting would delay each push-to-talk by a second.
  static int? _cachedStride;
  static int _cachedChannel = 0;

  static void resetCache() {
    _cachedStride = null;
    _cachedChannel = 0;
  }

  static int? get detectedStride => _cachedStride;

  int? _startMs;
  int? _measureStartMs;
  int _measuredBytes = 0;
  final BytesBuilder _pending = BytesBuilder();

  /// Feed a raw chunk received at [nowMs]. Returns mono int16 PCM ready to
  /// use, or an empty list while the channel layout is still being measured.
  Uint8List process(Uint8List chunk, int nowMs) {
    final stride = _cachedStride;
    if (stride != null) return _extract(chunk, stride, _cachedChannel);

    _pending.add(chunk);
    _startMs ??= nowMs;
    final sinceStart = nowMs - _startMs!;
    if (sinceStart < warmupMs) return Uint8List(0);
    if (_measureStartMs == null) {
      // Bytes of this chunk were produced before the window opened.
      _measureStartMs = nowMs;
      return Uint8List(0);
    }
    _measuredBytes += chunk.length;
    final window = nowMs - _measureStartMs!;
    if (window < measureMs) return Uint8List(0);

    final ratio = _measuredBytes * 1000 / window / expectedBytesPerSecond;
    final raw = _pending.takeBytes();
    final detected = detectStride(ratio, raw);
    _cachedStride = detected;
    _cachedChannel = detected == 1 ? 0 : loudestChannel(raw, detected);
    return _extract(raw, detected, _cachedChannel);
  }

  /// Map a measured rate ratio to an interleaved channel count.
  static int strideForRatio(double ratio) {
    const candidates = [1, 2, 4, 6, 8];
    int best = 1;
    double bestErr = double.infinity;
    for (final c in candidates) {
      final err = (ratio - c).abs() / c;
      if (err < bestErr) {
        bestErr = err;
        best = c;
      }
    }
    // Only trust a multi-channel guess when the rate clearly matches it.
    return bestErr <= 0.15 ? best : 1;
  }

  /// Delivery jitter (UI jank, backlog flushes) makes the measured rate
  /// approximate, so it only narrows the candidates; the interleave itself is
  /// confirmed by the signal: samples one frame apart (lag = stride) are
  /// strongly correlated, unlike neighbouring samples from other channels.
  static int detectStride(double ratio, Uint8List pcm) {
    if (strideForRatio(ratio) == 1 && ratio < 1.5) return 1;
    const candidates = [2, 4, 6, 8];
    // A real mono signal is smoother at lag 1 than at any longer lag, while
    // neighbouring samples of an interleave come from different channels.
    final floor = math.max(0.5, lagCorrelation(pcm, 1) + 0.2);
    final corr = <int, double>{};
    double maxCorr = 0;
    for (final c in candidates) {
      // Jitter only ever inflates the apparent rate enough to overshoot, so
      // keep every smaller stride as a candidate and let the signal decide.
      if (c > ratio * 1.5) continue;
      corr[c] = lagCorrelation(pcm, c);
      if (corr[c]! > maxCorr) maxCorr = corr[c]!;
    }
    if (maxCorr < floor) return 1;
    // Multiples of the true stride correlate just as well (lag 8 on a
    // 4-channel stream), so take the smallest stride close to the best.
    int best = 1;
    for (final c in candidates) {
      final v = corr[c];
      if (v != null && v >= maxCorr - 0.1) {
        best = c;
        break;
      }
    }
    return best;
  }

  static double lagCorrelation(Uint8List pcm, int lag) {
    final data = pcm.buffer.asByteData(pcm.offsetInBytes, pcm.lengthInBytes);
    final n = math.min(pcm.lengthInBytes ~/ 2, 64000) - lag;
    if (n <= 0) return 0;
    double sa = 0, sb = 0, saa = 0, sbb = 0, sab = 0;
    for (int i = 0; i < n; i++) {
      final a = data.getInt16(i * 2, Endian.little).toDouble();
      final b = data.getInt16((i + lag) * 2, Endian.little).toDouble();
      sa += a;
      sb += b;
      saa += a * a;
      sbb += b * b;
      sab += a * b;
    }
    final cov = sab / n - (sa / n) * (sb / n);
    final va = saa / n - (sa / n) * (sa / n);
    final vb = sbb / n - (sb / n) * (sb / n);
    if (va <= 0 || vb <= 0) return 0;
    return cov / math.sqrt(va * vb);
  }

  static int loudestChannel(Uint8List pcm, int stride) {
    final samples = pcm.buffer.asByteData(pcm.offsetInBytes, pcm.lengthInBytes);
    final count = pcm.lengthInBytes ~/ 2 ~/ stride;
    int best = 0;
    double bestEnergy = -1;
    for (int ch = 0; ch < stride; ch++) {
      double energy = 0;
      for (int i = 0; i < count; i++) {
        final v = samples.getInt16((i * stride + ch) * 2, Endian.little);
        energy += v * v;
      }
      if (energy > bestEnergy) {
        bestEnergy = energy;
        best = ch;
      }
    }
    return best;
  }

  static Uint8List _extract(Uint8List pcm, int stride, int channel) {
    if (stride == 1) return pcm;
    final frames = pcm.lengthInBytes ~/ (2 * stride);
    final out = Uint8List(frames * 2);
    final o = math.min(channel, stride - 1) * 2;
    for (int i = 0; i < frames; i++) {
      final src = i * stride * 2 + o;
      out[i * 2] = pcm[src];
      out[i * 2 + 1] = pcm[src + 1];
    }
    return out;
  }
}
