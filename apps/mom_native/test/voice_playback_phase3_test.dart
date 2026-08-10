import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Workload 1 Phase 3 chunked TTS contract', () {
    late String voiceSource;
    late String chunkerSource;
    late String playbackSource;

    setUpAll(() async {
      voiceSource = await File('lib/src/voice_service.dart').readAsString();
      chunkerSource = await File('lib/src/speech_chunker.dart').readAsString();
      playbackSource =
          await File('lib/src/voice_playback_state.dart').readAsString();
    });

    test('speech is split before synthesis', () {
      expect(voiceSource, contains('final chunks = splitSpeechChunks(text)'));
      expect(chunkerSource, contains('List<String> splitSpeechChunks('));
    });

    test('playback state is observable', () {
      expect(
        voiceSource,
        contains('StreamController<MomVoicePlaybackState>.broadcast'),
      );
      expect(voiceSource, contains('Stream<MomVoicePlaybackState> get playbackStates'));
      expect(playbackSource, contains('enum MomVoicePlaybackPhase'));
    });

    test('preparing state is emitted before each synthesis', () {
      final preparing = voiceSource.indexOf('phase: MomVoicePlaybackPhase.preparing');
      final synthesize = voiceSource.indexOf('Isolate.run(() => _synthesize(request))');
      expect(preparing, greaterThanOrEqualTo(0));
      expect(synthesize, greaterThan(preparing));
    });

    test('speaking state is emitted before each player start', () {
      final speaking = voiceSource.indexOf('phase: MomVoicePlaybackPhase.speaking');
      final play = voiceSource.indexOf('await _player.play(DeviceFileSource(output.path))');
      expect(speaking, greaterThanOrEqualTo(0));
      expect(play, greaterThan(speaking));
    });

    test('each chunk gets its own generation-indexed audio file', () {
      expect(
        voiceSource,
        contains("mom-response-\$generation-\$index.wav"),
      );
    });

    test('playback always returns to idle', () {
      expect(
        voiceSource,
        contains('_emitPlayback(const MomVoicePlaybackState.idle())'),
      );
    });

    test('hands-free session resumes only after chunk loop finishes', () {
      final loop = voiceSource.indexOf('for (var index = 0; index < chunks.length; index++)');
      final finishTurn = voiceSource.lastIndexOf('_conversation.finishTurn()');
      final relisten = voiceSource.lastIndexOf('await _startListeningCycle()');
      expect(loop, greaterThanOrEqualTo(0));
      expect(finishTurn, greaterThan(loop));
      expect(relisten, greaterThan(finishTurn));
    });
  });
}
