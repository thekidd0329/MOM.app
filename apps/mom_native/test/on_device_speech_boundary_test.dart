import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android speech recognition is local-only and text-only', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final voice = File('lib/src/voice_service.dart').readAsStringSync();
    final bridge =
        File('lib/src/on_device_speech_recognizer.dart').readAsStringSync();
    final android = File(
      'android/app/src/main/kotlin/app/mom/mom_native/MainActivity.kt',
    ).readAsStringSync();
    final brainClient =
        File('lib/src/brain_stream_client.dart').readAsStringSync();
    final brainFunction = File(
      '../../supabase/functions/mom-brain-stream/index.ts',
    ).readAsStringSync();
    final syncFunction =
        File('../../supabase/functions/mom-sync/index.ts').readAsStringSync();
    final intelligenceFunction = File(
      '../../supabase/functions/mom-intelligence/index.ts',
    ).readAsStringSync();

    expect(pubspec, isNot(contains('speech_to_text')));
    expect(voice, isNot(contains('SpeechToText')));
    expect(voice, contains('AndroidOnDeviceSpeechRecognizer'));
    expect(android, contains('isOnDeviceRecognitionAvailable'));
    expect(android, contains('createOnDeviceSpeechRecognizer'));
    expect(
      android,
      isNot(contains('SpeechRecognizer.createSpeechRecognizer(')),
    );
    expect(android, contains('EXTRA_PREFER_OFFLINE'));
    expect(android, isNot(contains('audio_bytes')));
    expect(android, isNot(contains('pcm')));
    expect(bridge, isNot(contains("package:http")));
    expect(bridge, isNot(contains("dart:io")));
    expect(brainClient, contains("'input_transport': 'text'"));
    expect(brainClient, contains("'audio_uploaded': false"));
    expect(brainFunction, contains('audio_input_forbidden'));
    expect(syncFunction, contains('"audio_bytes"'));
    expect(intelligenceFunction, contains('"audio_bytes"'));
  });
}
