import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/tts_chunker.dart';

String normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  const chunker = MomTtsChunker();

  test('short replies stay in one natural chunk', () {
    expect(chunker.chunk('Nope. Put your shoes on.'), ['Nope. Put your shoes on.']);
  });

  test('first chunk stays small so MOM starts talking quickly', () {
    final chunks = chunker.chunk(
      'This is the first thought, and it keeps going for a while because we want the opening audio to start quickly instead of waiting for a giant paragraph to synthesize. Then this is the second sentence with more detail.',
    );
    expect(chunks, isNotEmpty);
    expect(chunks.first.length, lessThanOrEqualTo(96));
  });

  test('later chunks stay bounded without dropping text', () {
    final text = List.generate(
      18,
      (index) => 'Sentence $index has a useful clause, and another piece of context.',
    ).join(' ');
    final chunks = chunker.chunk(text);

    expect(chunks.length, greaterThan(2));
    expect(chunks.first.length, lessThanOrEqualTo(96));
    for (final chunk in chunks.skip(1)) {
      expect(chunk.length, lessThanOrEqualTo(190));
    }
    expect(normalize(chunks.join(' ')), normalize(text));
  });

  test('unpunctuated speech remains bounded and complete', () {
    final text = List.generate(90, (index) => 'word$index').join(' ');
    final chunks = chunker.chunk(text);
    expect(chunks.first.length, lessThanOrEqualTo(96));
    for (final chunk in chunks.skip(1)) {
      expect(chunk.length, lessThanOrEqualTo(190));
    }
    expect(normalize(chunks.join(' ')), normalize(text));
  });

  test('voice service synthesizes no more than two chunks ahead', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();
    expect(source, contains('const _maxSynthesizedAhead = 2'));
    expect(source, contains('pending.length > _maxSynthesizedAhead'));
    expect(source, contains('index + _maxSynthesizedAhead'));
    expect(source, contains(r'mom-response-$generation-$index.wav'));
  });
}
