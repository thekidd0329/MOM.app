import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/voice_conversation_controller.dart';

void main() {
  group('MomVoiceConversationController', () {
    test('starts disabled and idle', () {
      final controller = MomVoiceConversationController();
      expect(controller.active, isFalse);
      expect(controller.phase, MomVoiceConversationPhase.idle);
      expect(controller.canListen(busy: false), isFalse);
    });

    test('enabled conversation can enter listening state', () {
      final controller = MomVoiceConversationController();
      controller.enable();
      expect(controller.canListen(busy: false), isTrue);
      controller.markListening();
      expect(controller.phase, MomVoiceConversationPhase.listening);
      expect(controller.canListen(busy: false), isFalse);
    });

    test('one voice turn moves listening to thinking to speaking then relistens', () {
      final controller = MomVoiceConversationController();
      controller.enable();
      controller.markListening();
      controller.markThinking();
      expect(controller.phase, MomVoiceConversationPhase.thinking);
      controller.markSpeaking();
      expect(controller.phase, MomVoiceConversationPhase.speaking);
      expect(controller.finishTurn(), isTrue);
      expect(controller.phase, MomVoiceConversationPhase.idle);
      expect(controller.canListen(busy: false), isTrue);
    });

    test('silent recognizer completion remains hands free', () {
      final controller = MomVoiceConversationController();
      controller.enable();
      controller.markListening();
      expect(controller.listeningEndedWithoutTurn(), isTrue);
      expect(controller.phase, MomVoiceConversationPhase.idle);
    });

    test('manual stop invalidates active voice loop', () {
      final controller = MomVoiceConversationController();
      final enabledGeneration = controller.enable();
      final stoppedGeneration = controller.disable();
      expect(stoppedGeneration, greaterThan(enabledGeneration));
      expect(controller.active, isFalse);
      expect(controller.canListen(busy: false), isFalse);
    });

    test('failure exits the hands-free loop', () {
      final controller = MomVoiceConversationController();
      controller.enable();
      controller.markListening();
      controller.fail();
      expect(controller.active, isFalse);
      expect(controller.phase, MomVoiceConversationPhase.error);
    });
  });
}
