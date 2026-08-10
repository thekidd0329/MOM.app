import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/transcript_quality.dart';

void main() {
  const quality = MomTranscriptQuality();

  test('short legitimate answers are never rejected', () {
    for (final answer in ['yes', 'no', 'okay', 'maybe']) {
      expect(
        quality.shouldClarify(finalTranscript: answer),
        isFalse,
        reason: answer,
      );
    }
  });

  test('obvious recognizer garbage requests clarification', () {
    expect(
      quality.shouldClarify(finalTranscript: 'blah blah blah blah blah'),
      isTrue,
    );
    expect(
      quality.shouldClarify(finalTranscript: '12345 !!! ??? 7777'),
      isTrue,
    );
  });

  test('wildly inconsistent final result is repaired instead of sent', () {
    expect(
      quality.shouldClarify(
        previousPartial: 'I left work early because my manager sent me home after lunch',
        finalTranscript: 'purple bicycle window sandwich tomorrow',
      ),
      isTrue,
    );
  });

  test('normal refinement from partial to final stays valid', () {
    expect(
      quality.shouldClarify(
        previousPartial: 'I left work early because my manager',
        finalTranscript: 'I left work early because my manager told me to go home',
      ),
      isFalse,
    );
  });

  test('bad transcript triggers spoken clarification and resumes same turn', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains('_transcriptQuality.shouldClarify('));
    expect(source, contains('Future<void> _clarifyTranscript('));
    expect(source, contains("await speak('Wait, what did you just say?', automaticBargeIn: false)"));
    expect(source, contains('await listen(onFinal: onFinal, onState: onState)'));
  });
}
