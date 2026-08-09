import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Workload 1 Phase 2 hands-free voice contract', () {
    late String voiceSource;
    late String controllerSource;

    setUpAll(() async {
      voiceSource = await File('lib/src/voice_service.dart').readAsString();
      controllerSource =
          await File('lib/src/voice_conversation_controller.dart').readAsString();
    });

    test('voice service owns a persistent conversation controller', () {
      expect(
        voiceSource,
        contains('final MomVoiceConversationController _conversation'),
      );
      expect(voiceSource, contains('bool get handsFreeActive'));
    });

    test('manual listen starts or stops one persistent voice session', () {
      expect(voiceSource, contains('if (_conversation.active)'));
      expect(voiceSource, contains('await stopListening()'));
      expect(voiceSource, contains('_conversation.enable()'));
      expect(voiceSource, contains('await _startListeningCycle()'));
    });

    test('final transcript blocks premature silent relisten', () {
      expect(voiceSource, contains('_conversation.markThinking()'));
      expect(
        controllerSource,
        contains('if (_phase != MomVoiceConversationPhase.listening) return false'),
      );
    });

    test('silent recognition timeout schedules a new listening cycle', () {
      expect(voiceSource, contains('_scheduleSilentRelisten()'));
      expect(
        voiceSource,
        contains('Future<void>.delayed(const Duration(milliseconds: 250)'),
      );
    });

    test('MOM speech pauses recognition and resumes listening afterwards', () {
      expect(voiceSource, contains('_conversation.markSpeaking()'));
      expect(voiceSource, contains('await _speech.stop()'));
      expect(voiceSource, contains('_conversation.finishTurn()'));
      expect(voiceSource, contains('await _startListeningCycle()'));
    });

    test('manual stop invalidates delayed relisten callbacks', () {
      expect(voiceSource, contains('final generation = _conversation.generation'));
      expect(
        voiceSource,
        contains('generation != _conversation.generation'),
      );
      expect(controllerSource, contains('int disable()'));
    });
  });
}
