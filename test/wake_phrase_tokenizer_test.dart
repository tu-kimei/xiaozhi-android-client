import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_assistant/services/standby/wake_phrase_tokenizer.dart';

void main() {
  final tokenizer = WakePhraseTokenizer(
    jsonDecode(File('assets/wake_word/bpe_vocab.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  test('tokenization matches the original SentencePiece model fixtures', () {
    expect(tokenizer.encode('Hey Doradino'), [
      '▁HE',
      'Y',
      '▁DO',
      'RA',
      'D',
      'IN',
      'O',
    ]);
    expect(tokenizer.encode('Hello Robot'), [
      '▁HE',
      'LL',
      'O',
      '▁RO',
      'B',
      'O',
      'T',
    ]);
    expect(tokenizer.encode('Hey Siri'), ['▁HE', 'Y', '▁S', 'I', 'RI']);
    expect(tokenizer.encode('Hey Dora Dino'), [
      '▁HE',
      'Y',
      '▁DO',
      'RA',
      '▁DI',
      'N',
      'O',
    ]);
    expect(
      tokenizer.keywords('Hey Doradino'),
      File('assets/wake_word/default_keywords.txt').readAsStringSync(),
    );
    expect(tokenizer.keywords('Hello Robot').contains('@HELLO_ROBOT'), isTrue);
  });
  test('Doredino spelling retains calibrated acoustic alternatives', () {
    final keywords = tokenizer.keywords('Hey Doredino');
    expect(keywords.split('\n').where((line) => line.isNotEmpty).length, 10);
    expect(keywords.contains('@HEY_DOREDINO'), isTrue);
    expect(keywords.contains('@HEY_DORADINO'), isFalse);
    expect(keywords, contains(tokenizer.encode('HI DARIO').join(' ')));
  });
  test('reject unsupported or control text before native decoding', () {
    for (final word in [
      'Doradino',
      'Này robot',
      'hey @robot',
      'hey robot\n@BAD',
      '123 robot',
      'hey robot hello good morning world',
    ]) {
      expect(WakePhraseTokenizer.valid(word), isFalse, reason: word);
      expect(() => tokenizer.encode(word), throwsFormatException);
    }
    expect(WakePhraseTokenizer.valid('Hey Doradino'), isTrue);
  });
}
