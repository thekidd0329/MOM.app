import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/speech_chunker.dart';

void main() {
  group('splitSpeechChunks', () {
    test('empty input produces no chunks', () {
      expect(splitSpeechChunks('   \n  '), isEmpty);
    });

    test('short input stays in one chunk', () {
      expect(splitSpeechChunks('Hey, I am right here.'), ['Hey, I am right here.']);
    });

    test('normalizes whitespace', () {
      expect(
        splitSpeechChunks('Hey,   I am\nright here.'),
        ['Hey, I am right here.'],
      );
    });

    test('long reply splits into bounded chunks and preserves content', () {
      final text = List.generate(
        16,
        (index) => 'Sentence $index has enough words to make MOM sound natural.',
      ).join(' ');
      final chunks = splitSpeechChunks(
        text,
        targetCharacters: 90,
        maximumCharacters: 120,
      );

      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.length <= 120), isTrue);
      expect(chunks.join(' '), text);
    });

    test('prefers sentence boundaries', () {
      const text =
          'First sentence ends here. Second sentence ends here too. Third sentence is the last one.';
      final chunks = splitSpeechChunks(
        text,
        targetCharacters: 30,
        maximumCharacters: 58,
      );

      expect(chunks.length, greaterThan(1));
      expect(chunks.take(chunks.length - 1).every((chunk) => RegExp(r'[.!?]$').hasMatch(chunk)), isTrue);
      expect(chunks.join(' '), text);
    });

    test('oversized sentence falls back to word boundaries', () {
      final text = List.generate(35, (index) => 'word$index').join(' ');
      final chunks = splitSpeechChunks(
        text,
        targetCharacters: 55,
        maximumCharacters: 70,
      );

      expect(chunks.length, greaterThan(1));
      expect(chunks.every((chunk) => chunk.length <= 70), isTrue);
      expect(chunks.join(' '), text);
    });
  });
}
