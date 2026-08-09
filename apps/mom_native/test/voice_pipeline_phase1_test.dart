import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Workload 1 Phase 1 voice pipeline contract', () {
    late String appSource;
    late String microphoneSource;
    late String voiceSource;

    setUpAll(() async {
      appSource = await File('lib/main.dart').readAsString();
      microphoneSource = await File('lib/src/mic_status.dart').readAsString();
      voiceSource = await File('lib/src/voice_service.dart').readAsString();
    });

    test('permission link requests microphone permission', () {
      expect(
        microphoneSource,
        contains('_recorder.hasPermission(request: requestPermission)'),
      );
      expect(appSource, contains('await _probeMicrophone(true)'));
      expect(appSource, contains('if (!_microphone.permissionGranted) return'));
    });

    test('STT link uses the platform speech recognizer', () {
      expect(voiceSource, contains('final SpeechToText _speech = SpeechToText()'));
      expect(voiceSource, contains('await _speech.listen('));
      expect(voiceSource, contains('result.recognizedWords.trim()'));
    });

    test('final transcript enters MOM as voice input', () {
      expect(appSource, contains('onFinal: (text)'));
      expect(appSource, contains("_send(text, inputMode: 'voice')"));
      expect(appSource, contains("'input_mode': inputMode"));
    });

    test('transcript reaches the brain request', () {
      expect(appSource, contains('final reply = await client.chatStream('));
      expect(appSource, contains('userText: text.trim()'));
    });

    test('brain output reaches Kokoro synthesis', () {
      expect(appSource, contains('.speakStream('));
      expect(appSource, contains('onDelta: (delta)'));
      expect(voiceSource, contains("backend: 'kokoro'"));
      expect(voiceSource, contains('session.setVoice(request.voicePath)'));
      expect(voiceSource, contains('session.synthesize(request.text)'));
    });

    test('synthesized audio reaches the speaker', () {
      expect(voiceSource, contains('await _player.play(DeviceFileSource(output.path))'));
    });
  });
}
