import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MOM 1.0.1 voice pipeline contract', () {
    late String appSource;
    late String microphoneSource;
    late String voiceSource;

    setUpAll(() async {
      appSource = await File('lib/main.dart').readAsString();
      microphoneSource = await File('lib/src/mic_status.dart').readAsString();
      voiceSource = await File('lib/src/voice_service.dart').readAsString();
    });

    test('permission reaches STT', () {
      expect(
        microphoneSource,
        contains('_recorder.hasPermission(request: requestPermission)'),
      );
      expect(appSource, contains('await _probeMicrophone(true)'));
      expect(appSource, contains('if (!_microphone.permissionGranted)'));
      expect(voiceSource, contains('final SpeechToText _speech = SpeechToText()'));
      expect(voiceSource, contains('await _speech.listen('));
    });

    test('final transcript remains a voice-originated turn', () {
      expect(appSource, contains('onFinal: (text)'));
      expect(appSource, contains("_send(text, inputMode: 'voice')"));
      expect(appSource, contains("'input_mode': inputMode"));
    });

    test('transcript reaches MOM brain and response remains captioned', () {
      expect(appSource, contains('streamedReply = await streamClient.chat('));
      expect(appSource, contains('reply = await client.chat('));
      expect(appSource, contains('userText: text.trim()'));
      expect(
        appSource,
        contains("'brain_transport': useLocal ? 'local_complete' : 'secure_sse'"),
      );
      expect(appSource, contains("'caption_persists': true"));
    });

    test('brain reply reaches Kokoro synthesis', () {
      expect(appSource, contains('await _speakText(reply.text)'));
      expect(appSource, contains('speechFuture = _speakDeltaStream(deltaController.stream)'));
      expect(voiceSource, contains("backend: 'kokoro'"));
      expect(voiceSource, contains('session.setVoice(request.voicePath)'));
      expect(voiceSource, contains('session.synthesize(request.text)'));
    });

    test('Kokoro output reaches device speaker', () {
      expect(
        voiceSource,
        contains('await _player.play(DeviceFileSource(output.path))'),
      );
      expect(voiceSource, contains('onPlaybackStart?.call()'));
    });

    test('voice failures are visible instead of silently swallowed', () {
      expect(appSource, isNot(contains('catchError((_) {})')));
      expect(appSource, contains("'voice_error'"));
      expect(appSource, contains('Voice error · text still works'));
      expect(voiceSource, contains('class MomVoiceException'));
    });

    test('downloaded Kokoro assets must actually be GGUF', () {
      expect(voiceSource, contains('Future<bool> _isValidGguf'));
      expect(voiceSource, contains('header[0] == 0x47'));
      expect(voiceSource, contains('header[3] == 0x46'));
    });
  });
}
