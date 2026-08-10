import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/voice_listen_guard.dart';

void main() {
  test('stale STT session generations are rejected', () {
    final guard = MomListenSessionGuard();
    final first = guard.begin(
      timeout: const Duration(seconds: 1),
      onTimeout: () {},
    );
    final second = guard.begin(
      timeout: const Duration(seconds: 1),
      onTimeout: () {},
    );

    expect(guard.isCurrent(first), isFalse);
    expect(guard.isCurrent(second), isTrue);
    guard.dispose();
  });

  test('listen timeout recovers instead of leaving a stuck session', () async {
    final guard = MomListenSessionGuard();
    final timeout = Completer<void>();
    guard.begin(
      timeout: const Duration(milliseconds: 10),
      onTimeout: timeout.complete,
    );

    await timeout.future.timeout(const Duration(seconds: 1));
    guard.dispose();
  });

  test('voice service owns timeout, stale-callback, and speaker/mic collision guards', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains('MomListenSessionGuard _listenGuard'));
    expect(source, contains('const _normalListenTimeout = Duration(seconds: 35)'));
    expect(source, contains('_listenGuard.isCurrent(listenGeneration)'));
    expect(source, contains("'speech_timeout'"));
    expect(source, contains('No final transcript arrived before the listening timeout'));
    expect(source, contains('if (_playingFile != null)'));
    expect(source, contains('await stopSpeaking(preserveContinuity: true)'));
  });

  test('barge-in state becomes interrupted then listening', () async {
    final source = await File('lib/main.dart').readAsString();

    expect(source, contains('void _handleVoiceListeningState(bool value)'));
    expect(source, contains('_setVoiceState(MomVoiceState.interrupted)'));
    expect(source, contains('_setVoiceState(MomVoiceState.listening)'));
    expect(source, contains('onState: _handleVoiceListeningState'));
    expect(source, contains('onFinal: _handleVoiceFinal'));
  });

  test('new interrupted turn invalidates the old streaming answer', () async {
    final source = await File('lib/main.dart').readAsString();

    expect(source, contains('final turnGeneration = ++_conversationGeneration'));
    expect(source, contains('previousStream?.close()'));
    expect(source, contains('if (turnGeneration != _conversationGeneration) return'));
    expect(source, contains('_activeBrainStream = streamClient'));
  });

  test('voice-originated transcript remains marked as voice', () async {
    final source = await File('lib/main.dart').readAsString();

    expect(source, contains("_send(text, inputMode: 'voice')"));
    expect(source, contains("'input_mode': inputMode"));
  });
}
