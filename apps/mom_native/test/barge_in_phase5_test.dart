import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/voice_service.dart';

void main() {
  test('speaker echo is ignored but novel user speech is not', () {
    expect(
      looksLikeMomSpeakerEcho(
        'before we get into the rest of this',
        'But before we get into the rest of this, answer me clearly.',
      ),
      isTrue,
    );
    expect(
      looksLikeMomSpeakerEcho(
        'wait listen to me',
        'But before we get into the rest of this, answer me clearly.',
      ),
      isFalse,
    );
  });

  test('voice service arms partial STT while MOM is speaking', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains('Future<void> listenForBargeIn('));
    expect(source, contains('partialResults: true'));
    expect(source, contains('_armAutomaticBargeIn'));
    expect(source, contains('unawaited(_armAutomaticBargeIn(() => text))'));
  });

  test('real user speech immediately cancels audible playback', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains('await stopSpeaking()'));
    expect(source, contains('_playbackCancelled'));
    expect(source, contains('Future.any<void>([completed, cancelled])'));
    expect(source, contains('await _player.stop()'));
  });

  test('barge-in final transcript reuses the conversation voice handler', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains('_conversationFinal = onFinal'));
    expect(source, contains('_conversationListeningState = onState'));
    expect(source, contains('stateHandler(false)'));
    expect(source, contains('finalHandler(text.trim())'));
  });
}
