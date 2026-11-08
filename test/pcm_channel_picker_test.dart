import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/utils/pcm_channel_picker.dart';

const _monoBytesPerSecond = 16000 * 2;
const _chunkBytes = 2560;

Int16List _speech() {
  final bytes = File('test/fixtures/hello_vi_16k.pcm').readAsBytesSync();
  return bytes.buffer.asInt16List(0, bytes.lengthInBytes ~/ 2);
}

/// Visbot layout: [main mic, weak mic, 0, 0] per sample.
Uint8List _interleave(Int16List mono, int stride, {int speechChannel = 0}) {
  final rnd = math.Random(1);
  final out = Int16List(mono.length * stride);
  for (int i = 0; i < mono.length; i++) {
    for (int ch = 0; ch < stride; ch++) {
      int v = 0;
      if (ch == speechChannel) {
        v = mono[i];
      } else if (ch == (speechChannel + 1) % stride) {
        v = (mono[i] ~/ 6) + rnd.nextInt(20) - 10;
      }
      out[i * stride + ch] = v;
    }
  }
  return out.buffer.asUint8List();
}

/// Feed [raw] in recorder-sized chunks at the rate the hardware delivers it.
Uint8List _feed(PcmChannelPicker picker, Uint8List raw, int stride) {
  final bytesPerSecond = _monoBytesPerSecond * stride;
  final out = BytesBuilder();
  for (int start = 0; start < raw.length; start += _chunkBytes) {
    final end = math.min(start + _chunkBytes, raw.length);
    final nowMs = 1000000 + end * 1000 ~/ bytesPerSecond;
    out.add(picker.process(Uint8List.sublistView(raw, start, end), nowMs));
  }
  return out.toBytes();
}

void main() {
  setUp(PcmChannelPicker.resetCache);

  test('strideForRatio picks clear multiples only', () {
    expect(PcmChannelPicker.strideForRatio(1.0), 1);
    expect(PcmChannelPicker.strideForRatio(1.1), 1);
    expect(PcmChannelPicker.strideForRatio(4.27), 4);
    expect(PcmChannelPicker.strideForRatio(3.9), 4);
    expect(PcmChannelPicker.strideForRatio(2.05), 2);
    expect(PcmChannelPicker.strideForRatio(3.0), 1);
  });

  test('real Visbot capture is 4 channels even with a jittery rate', () {
    final raw = File('test/fixtures/visbot_raw_4ch.pcm').readAsBytesSync();
    for (final ratio in [3.2, 4.27, 6.0, 7.5, 8.0]) {
      expect(PcmChannelPicker.detectStride(ratio, raw), 4, reason: '$ratio');
    }
    expect(PcmChannelPicker.loudestChannel(raw, 4), 0);
  });

  test('mono speech is never split, even with a misleading rate', () {
    final raw = _speech().buffer.asUint8List();
    for (final ratio in [1.0, 1.6, 2.2, 4.0]) {
      expect(PcmChannelPicker.detectStride(ratio, raw), 1, reason: '$ratio');
    }
  });

  test('mono stream passes through unchanged', () {
    final mono = _speech();
    final raw = mono.buffer.asUint8List();
    final out = _feed(
      PcmChannelPicker(expectedBytesPerSecond: _monoBytesPerSecond),
      raw,
      1,
    );
    expect(PcmChannelPicker.detectedStride, 1);
    expect(out, raw);
  });

  for (final speechChannel in [0, 2]) {
    test('4-channel interleave recovers speech channel $speechChannel', () {
      final mono = _speech();
      final raw = _interleave(mono, 4, speechChannel: speechChannel);
      final out = _feed(
        PcmChannelPicker(expectedBytesPerSecond: _monoBytesPerSecond),
        raw,
        4,
      );
      expect(PcmChannelPicker.detectedStride, 4);
      expect(out, mono.buffer.asUint8List());
    });
  }

  test('detection is cached for later recordings', () {
    final mono = _speech();
    _feed(
      PcmChannelPicker(expectedBytesPerSecond: _monoBytesPerSecond),
      _interleave(mono, 4),
      4,
    );
    final second = PcmChannelPicker(expectedBytesPerSecond: _monoBytesPerSecond);
    final chunk = _interleave(Int16List.fromList(mono.sublist(0, 320)), 4);
    expect(second.process(chunk, 0), mono.sublist(0, 320).buffer.asUint8List());
  });
}
