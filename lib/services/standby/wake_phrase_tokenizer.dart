/// Viterbi segmentation using the published English SentencePiece unigram scores.
/// Validated against the original model; no network tokenizer is required.
class WakePhraseTokenizer {
  final Map<String, double> vocabulary;
  WakePhraseTokenizer(Map<String, dynamic> scores)
    : vocabulary = scores.map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      );

  static String normalize(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ').toUpperCase();
  static bool valid(String text) =>
      text.trim().length <= 48 &&
      RegExp(r'^[a-zA-Z]+(?: +[a-zA-Z]+){1,4}$').hasMatch(text.trim());

  List<String> encode(String phrase) {
    if (!valid(phrase)) {
      throw const FormatException('Nhập 2–5 từ bằng chữ cái tiếng Anh.');
    }
    final text = '▁${normalize(phrase).replaceAll(' ', '▁')}';
    final score = List<double>.filled(text.length + 1, double.negativeInfinity);
    final paths = List<List<String>?>.filled(text.length + 1, null);
    score[0] = 0;
    paths[0] = [];
    for (var i = 0; i < text.length; i++) {
      if (paths[i] == null) continue;
      for (final piece in vocabulary.entries) {
        if (!text.startsWith(piece.key, i)) continue;
        final end = i + piece.key.length;
        final next = score[i] + piece.value;
        if (next > score[end]) {
          score[end] = next;
          paths[end] = [...paths[i]!, piece.key];
        }
      }
    }
    if (paths.last == null) {
      throw const FormatException('Cụm từ chưa được bộ nhận hỗ trợ.');
    }
    return paths.last!;
  }

  String keywords(String phrase) {
    // Every acoustic alternative reports the same canonical wake event.
    final normalized = normalize(phrase);
    // Acoustic alternatives for the proper name, calibrated from real mic input.
    // They all map to the one configured wake phrase.
    final phrases =
        (normalized == 'HEY DORADINO' || normalized == 'HEY DOREDINO')
            ? [
              if (normalized == 'HEY DOREDINO') 'HEY DOREDINO',
              'HEY DORADINO',
              'HEY DORA DINO',
              'HEY DORA DEENO',
              'HI DORADINO',
              'HI DORA DINO',
              'HI DURALIA',
              'HI DARIO',
              'HIGH DURALIA',
              'HIGH DARIO',
            ]
            : [normalized];
    return '${phrases.map((p) => '${encode(p).join(' ')} @${normalized.replaceAll(' ', '_')}').join('\n')}\n';
  }
}
