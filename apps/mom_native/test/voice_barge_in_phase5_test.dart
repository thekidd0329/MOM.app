import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/barge_in_controller.dart';
import 'package:mom_native/src/voice_barge_in.dart';

void main() {
  test('user speech while MOM is talking stops playback and opens mic', () {
    final controller = MomBargeInController();
    controller.begin(
      originalText: 'One. Two. Three.',
      chunks: const ['One.', 'Two.', 'Three.'],
    );
    controller.markChunkStarted(0);

    final decision = MomVoiceBargeIn(controller).interruptForUserSpeech();
    expect(decision.stopPlayback, isTrue);
    expect(decision.openMicrophone, isTrue);
    expect(decision.interruptedThought, isNotNull);
    expect(decision.interruptedThought!.resumeText, 'One. Two. Three.');
  });
}
