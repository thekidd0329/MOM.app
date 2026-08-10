import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/partial_redirector.dart';

void main() {
  const redirector = MomPartialRedirector();

  test('clearly off-track long partial gets one redirect', () {
    final redirect = redirector.redirectFor(
      lastMomSpeech: 'Why did you leave work early today?',
      partialTranscript:
          'So anyway my friend called me and then we started talking about his new truck and what he wants to buy next month',
    );

    expect(redirect, 'Wait, you’re dodging the question.');
  });

  test('partial that engages the question topic is left alone', () {
    final redirect = redirector.redirectFor(
      lastMomSpeech: 'Why did you leave work early today?',
      partialTranscript:
          'I left work early because my manager told me the shift was over and then I went straight home after that',
    );

    expect(redirect, isNull);
  });

  test('uncertain or direct-answer language is never treated as dodging', () {
    expect(
      redirector.redirectFor(
        lastMomSpeech: 'Why did you leave work early today?',
        partialTranscript:
            "I don't know honestly I am trying to remember what happened because that whole afternoon is blurry to me",
      ),
      isNull,
    );
    expect(
      redirector.redirectFor(
        lastMomSpeech: 'Did you call her back?',
        partialTranscript:
            'No I did not and then I got distracted after dinner and forgot about the whole thing until this morning',
      ),
      isNull,
    );
  });

  test('short partial never triggers a redirect', () {
    expect(
      redirector.redirectFor(
        lastMomSpeech: 'Why did you leave work early today?',
        partialTranscript: 'I was going to tell you',
      ),
      isNull,
    );
  });

  test('voice service redirects, speaks briefly, then resumes the same listen path', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains('_redirector.redirectFor('));
    expect(source, contains('Future<void> _interruptOffTrackUser('));
    expect(source, contains('await speak(redirect, automaticBargeIn: false)'));
    expect(source, contains('await listen(onFinal: onFinal, onState: onState)'));
    expect(source, contains('partialResults: true'));
  });
}
