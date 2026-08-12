import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mic permission gates speech recognition before listening', () {
    final main = File('lib/main.dart').readAsStringSync();
    final mic = File('lib/src/mic_status.dart').readAsStringSync();

    expect(mic, contains('hasPermission(request: requestPermission)'));
    expect(mic, contains('listInputDevices()'));
    expect(main, contains('await _probeMicrophone(true);'));
    expect(main, contains('if (!_microphone.permissionGranted) return;'));
    expect(main, contains('await _voice.listen('));
  });

  test('final speech transcript enters the MOM response path', () {
    final main = File('lib/main.dart').readAsStringSync();
    final voice = File('lib/src/voice_service.dart').readAsStringSync();

    expect(voice, contains('_speech.initialize('));
    expect(voice, contains('await _speech.listen('));
    expect(voice, contains('result.finalResult'));
    expect(voice, contains('result.recognizedWords.trim()'));
    expect(main, contains('onFinal: (text)'));
    expect(main, contains('unawaited(_send(text));'));
    expect(main, contains('final client = ModelClient(config.copy());'));
    expect(main, contains('final reply = await client.chat('));
  });

  test('successful MOM response is synthesized to wav and played', () {
    final main = File('lib/main.dart').readAsStringSync();
    final voice = File('lib/src/voice_service.dart').readAsStringSync();

    expect(main, contains('unawaited(_voice.speak(reply.text).catchError((_) {}));'));
    expect(voice, contains('final wav = await Isolate.run(() => _synthesize(request));'));
    expect(voice, contains('return _pcmToWav(pcm, 24000);'));
    expect(voice, contains('await _player.play(DeviceFileSource(output.path));'));
  });

  test('generated mobile shells declare microphone and speech discovery access', () {
    final workflow =
        File('../../.github/workflows/mom-native.yml').readAsStringSync();

    expect(workflow, contains('android.permission.RECORD_AUDIO'));
    expect(workflow, contains('android.speech.RecognitionService'));
    expect(workflow, contains('NSMicrophoneUsageDescription'));
  });
}
