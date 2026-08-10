import 'barge_in_controller.dart';

class MomVoiceBargeInDecision {
  const MomVoiceBargeInDecision({
    required this.stopPlayback,
    required this.openMicrophone,
    required this.interruptedThought,
  });

  final bool stopPlayback;
  final bool openMicrophone;
  final InterruptedThought? interruptedThought;
}

class MomVoiceBargeIn {
  MomVoiceBargeIn(this.controller);

  final MomBargeInController controller;

  MomVoiceBargeInDecision interruptForUserSpeech() {
    final thought = controller.interrupt();
    return MomVoiceBargeInDecision(
      stopPlayback: true,
      openMicrophone: true,
      interruptedThought: thought,
    );
  }
}
