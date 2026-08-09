import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MOM voice loop remains wired end to end', () {
    final main = File('lib/main.dart').readAsStringSync();
    final mic = File('lib/src/mic_status.dart').readAsStringSync();
    final voice = File('lib/src/voice_service.dart').readAsStringSync();
    final workflow = File('../../.github/workflows/mom-native.yml').readAsStringSync();

    expect(mic, contains('hasPermission(request: requestPermission)'));
    expect(main, contains('await _probeMicrophone(true);'));
    expect(main, contains('await _voice.listen('));
    expect(voice, contains('await _speech.listen('));
    expect(voice, contains('result.finalResult'));
    expect(main, contains('unawaited(_send(text));'));
    expect(main, contains('final reply = await client.chat('));
    expect(main, contains('_voice.speak(reply.text)'));
    expect(voice, contains('await _player.play(DeviceFileSource(output.path));'));
    expect(workflow, contains('android.permission.RECORD_AUDIO'));
    expect(workflow, contains('android.speech.RecognitionService'));
  });
}
