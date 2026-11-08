import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ai_assistant/utils/voice_activity_detector.dart';
import 'package:flutter_test/flutter_test.dart';

const int frameSamples = 960; // 60ms @ 16kHz

/// silenceBefore + speech + silenceAfter, with gaussian noise of [noiseRms] mixed in
Int16List buildSignal({
  required Int16List speech,
  required double noiseRms,
  double speechGain = 1.0,
  double before = 2.0,
  double after = 3.0,
  int seed = 1,
}) {
  final rnd = Random(seed);
  final total = ((before + after) * 16000).toInt() + speech.length;
  final out = Int16List(total);
  final start = (before * 16000).toInt();
  for (int i = 0; i < total; i++) {
    // Box-Muller
    final u1 = rnd.nextDouble() + 1e-12, u2 = rnd.nextDouble();
    final n = sqrt(-2 * log(u1)) * cos(2 * pi * u2) * noiseRms;
    final si = i - start;
    final s = (si >= 0 && si < speech.length) ? speech[si] * speechGain : 0.0;
    out[i] = (n + s).round().clamp(-32768, 32767);
  }
  return out;
}

/// Runs the VAD over the signal, returns (startMs, endMs) of events (-1 if none)
({int start, int end, int starts}) runVad(Int16List signal) {
  final vad = VoiceActivityDetector();
  int start = -1, end = -1, starts = 0;
  for (int f = 0; f + frameSamples <= signal.length; f += frameSamples) {
    final bytes = Uint8List(frameSamples * 2);
    final bd = ByteData.sublistView(bytes);
    for (int i = 0; i < frameSamples; i++) {
      bd.setInt16(i * 2, signal[f + i], Endian.little);
    }
    final ev = vad.process(
      VoiceActivityDetector.frameDb(bytes),
      voicing: VoiceActivityDetector.voicing(bytes),
    );
    final ms = (f + frameSamples) * 1000 ~/ 16000;
    if (ev == VadEvent.speechStart) {
      starts++;
      if (start < 0) start = ms;
    }
    if (ev == VadEvent.speechEnd && end < 0) end = ms;
  }
  return (start: start, end: end, starts: starts);
}

void main() {
  final raw = File('test/fixtures/hello_vi_16k.pcm').readAsBytesSync();
  final speech = Int16List.view(raw.buffer, raw.offsetInBytes, raw.length ~/ 2);
  final speechMs = speech.length * 1000 ~/ 16000; // ~3119ms, starts at 2000ms

  for (final noise in [0.0, 300.0, 1000.0, 1500.0]) {
    test('detects one utterance with noise rms $noise', () {
      final r = runVad(buildSignal(speech: speech, noiseRms: noise));
      // ignore: avoid_print
      print('noise=$noise -> start=${r.start}ms end=${r.end}ms starts=${r.starts}');
      expect(r.starts, 1, reason: 'exactly one utterance');
      expect(r.start, inInclusiveRange(2000, 2700), reason: 'starts soon after speech');
      expect(r.end, inInclusiveRange(2000 + speechMs, 2000 + speechMs + 1500),
          reason: 'ends within 1.5s after speech stops');
    });
  }

  for (final noise in [300.0, 1500.0, 4000.0]) {
    test('stays silent on pure noise rms $noise', () {
      final r = runVad(buildSignal(
          speech: Int16List(0), noiseRms: noise, before: 5, after: 5, seed: 7));
      expect(r.starts, 0);
    });
  }

  test('sudden loud unvoiced noise burst does not trigger', () {
    // 3s quiet room, then 2s of loud white noise (door slam / fan / rustle)
    final quiet = buildSignal(speech: Int16List(0), noiseRms: 100, before: 3, after: 0);
    final burst = buildSignal(
        speech: Int16List(0), noiseRms: 3000, before: 2, after: 0, seed: 3);
    final r = runVad(Int16List.fromList([...quiet, ...burst]));
    expect(r.starts, 0);
  });

  test('utterance ends promptly even if loud noise follows the speech', () {
    final head = buildSignal(speech: speech, noiseRms: 100, after: 0);
    final tail = buildSignal(
        speech: Int16List(0), noiseRms: 2500, before: 6, after: 0, seed: 5);
    final r = runVad(Int16List.fromList([...head, ...tail]));
    // ignore: avoid_print
    print('noisy tail -> start=${r.start}ms end=${r.end}ms');
    expect(r.starts, 1);
    expect(r.end, inInclusiveRange(2000 + speechMs, 2000 + speechMs + 1500));
  });
}
