import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'wake_phrase_tokenizer.dart';

abstract interface class WakeWordDetector {
  set onDetected(void Function()? callback);
  set onError(void Function(Object)? callback);
  Future<void> prepare(String phrase, double threshold);
  void accept(Uint8List pcm);
  void reset();
  Future<void> dispose();
}

/// Native inference lives in its own isolate; the UI and Opus path stay free.
class LocalWakeWord implements WakeWordDetector {
  @override
  void Function()? onDetected;
  @override
  void Function(Object)? onError;
  Isolate? _worker;
  ReceivePort? _events;
  SendPort? _input;
  Completer<void>? _closed;
  final _queue = Queue<Uint8List>();
  bool _busy = false;
  String? _configuration;
  Future<void>? _preparing;
  int _generation = 0;
  int lastDecodeMs = 0;

  @override
  Future<void> prepare(String phrase, double threshold) {
    final key = '$phrase:$threshold';
    if (_configuration == key && _input != null) return Future.value();
    return _preparing ??= _prepare(
      phrase,
      threshold,
    ).whenComplete(() => _preparing = null);
  }

  Future<void> _prepare(String phrase, double threshold) async {
    await dispose();
    final generation = _generation;
    final root = Directory(
      '${(await getApplicationSupportDirectory()).path}/wake_word_v1',
    );
    await root.create(recursive: true);
    const expectedSizes = {
      "encoder.int8.onnx": 4807159,
      "decoder.onnx": 1063189,
      "joiner.int8.onnx": 163380,
      "tokens.txt": 5006,
    };
    for (final file in [
      'encoder.int8.onnx',
      'decoder.onnx',
      'joiner.int8.onnx',
      'tokens.txt',
    ]) {
      final target = File('${root.path}/$file');
      if (!await target.exists() ||
          await target.length() != expectedSizes[file]) {
        final data = await rootBundle.load('assets/wake_word/$file');
        final temporary = File('${target.path}.part');
        await temporary.writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true,
        );
        await temporary.rename(target.path);
      }
    }
    final tokenizer = WakePhraseTokenizer(
      jsonDecode(await rootBundle.loadString('assets/wake_word/bpe_vocab.json'))
          as Map<String, dynamic>,
    );
    final keywords = tokenizer.keywords(phrase);
    if (generation != _generation) {
      throw StateError('Đã hủy chuẩn bị từ đánh thức.');
    }
    final ready = Completer<void>();
    final closed = Completer<void>();
    _closed = closed;
    _events = ReceivePort();
    _events!.listen((dynamic event) {
      final data = event as Map;
      if (data['closed'] == true) {
        if (!closed.isCompleted) closed.complete();
        return;
      }
      if (generation != _generation) {
        if (data['ready'] is SendPort) {
          (data['ready'] as SendPort).send('close');
        }
        if (!ready.isCompleted) {
          ready.completeError(StateError('Đã hủy bộ nghe.'));
        }
        return;
      }
      if (data['ready'] is SendPort) {
        _input = data['ready'] as SendPort;
        _configuration = '$phrase:$threshold';
        if (!ready.isCompleted) ready.complete();
      } else if (data['error'] != null) {
        _configuration = null;
        _busy = false;
        final error = StateError('${data['error']}');
        if (!ready.isCompleted) {
          ready.completeError(error);
        } else {
          onError?.call(error);
        }
      } else {
        _busy = false;
        lastDecodeMs = data['ms'] as int? ?? 0;
        if (data['keyword'] == true) onDetected?.call();
        _pump();
      }
    });
    _worker = await Isolate.spawn(_keywordWorker, <String, dynamic>{
      'events': _events!.sendPort,
      'root': root.path,
      'keywords': keywords,
      'threshold': threshold,
    }, debugName: 'doradino-local-wake');
    try {
      await ready.future.timeout(const Duration(seconds: 30));
    } catch (_) {
      await dispose();
      rethrow;
    }
  }

  @override
  void accept(Uint8List pcm) {
    if (_input == null) return;
    if (_queue.length >= 50) {
      _queue.clear();
      reset();
      onError?.call(
        StateError('Bộ nhận từ đánh thức xử lý không kịp âm thanh.'),
      );
      return;
    }
    _queue.add(pcm);
    _pump();
  }

  void _pump() {
    if (_busy || _queue.isEmpty || _input == null) return;
    final bytes = BytesBuilder(copy: false);
    for (var count = 0; count < 5 && _queue.isNotEmpty; count++) {
      bytes.add(_queue.removeFirst());
    }
    _busy = true;
    _input!.send(TransferableTypedData.fromList([bytes.takeBytes()]));
  }

  @override
  void reset() {
    _queue.clear();
    _input?.send('reset');
  }

  @override
  Future<void> dispose() async {
    _generation++;
    final input = _input, worker = _worker, events = _events, closed = _closed;
    _input = null;
    _worker = null;
    _events = null;
    _closed = null;
    _queue.clear();
    _busy = false;
    _configuration = null;
    input?.send('close');
    if (closed != null) {
      try {
        await closed.future.timeout(const Duration(seconds: 35));
      } on TimeoutException {
        worker?.kill(priority: Isolate.beforeNextEvent);
      }
    }
    events?.close();
  }
}

void _keywordWorker(Map<String, dynamic> config) {
  final events = config['events'] as SendPort;
  sherpa.KeywordSpotter? spotter;
  sherpa.OnlineStream? stream;
  try {
    sherpa.initBindings();
    final root = config['root'] as String;
    final keywords = config['keywords'] as String;
    spotter = sherpa.KeywordSpotter(
      sherpa.KeywordSpotterConfig(
        model: sherpa.OnlineModelConfig(
          transducer: sherpa.OnlineTransducerModelConfig(
            encoder: '$root/encoder.int8.onnx',
            decoder: '$root/decoder.onnx',
            joiner: '$root/joiner.int8.onnx',
          ),
          tokens: '$root/tokens.txt',
          numThreads: 1,
          provider: 'cpu',
          modelType: 'zipformer2',
        ),
        keywordsBuf: keywords,
        keywordsBufSize: utf8.encode(keywords).length,
        // Keep proper-name alternatives alive instead of pruning at four paths.
        maxActivePaths: 8,
        keywordsScore: 1.5,
        keywordsThreshold: config['threshold'] as double,
        numTrailingBlanks: 2,
      ),
    );
    stream = spotter.createStream();
    final input = ReceivePort();
    input.listen((dynamic message) {
      try {
        if (message == 'close') {
          stream?.free();
          spotter?.free();
          events.send({'closed': true});
          input.close();
          return;
        }
        if (message == 'reset') {
          spotter!.reset(stream!);
          return;
        }
        final watch = Stopwatch()..start();
        final pcm =
            (message as TransferableTypedData).materialize().asUint8List();
        final data = ByteData.sublistView(pcm);
        final samples = Float32List(pcm.length ~/ 2);
        for (var i = 0; i < samples.length; i++) {
          samples[i] = data.getInt16(i * 2, Endian.little) / 32768;
        }
        stream!.acceptWaveform(samples: samples, sampleRate: 16000);
        var found = false;
        while (spotter!.isReady(stream)) {
          spotter.decode(stream);
          if (spotter.getResult(stream).keyword.isNotEmpty) {
            found = true;
            spotter.reset(stream);
          }
        }
        events.send({'keyword': found, 'ms': watch.elapsedMilliseconds});
      } catch (e) {
        events.send({'error': e.toString()});
      }
    });
    events.send({'ready': input.sendPort});
  } catch (e) {
    stream?.free();
    spotter?.free();
    events.send({'error': e.toString()});
    events.send({'closed': true});
  }
}
