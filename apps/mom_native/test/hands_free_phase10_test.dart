import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/voice_state.dart';

void main() {
  test('conversation state can repeat for several hands-free turns', () {
    final machine = MomVoiceStateMachine();
    for (var turn = 0; turn < 5; turn++) {
      machine.transition(MomVoiceState.listening);
      machine.transition(MomVoiceState.thinking);
      machine.transition(MomVoiceState.synthesizing);
      machine.transition(MomVoiceState.speaking);
      machine.transition(MomVoiceState.idle);
    }
    expect(machine.state, MomVoiceState.idle);
  });

  test('one voice listen arms automatic re-listen after completed speech', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains('_handsFreeArmed = true'));
    expect(source, contains('void _scheduleHandsFreeResume('));
    expect(source, contains('await listen(onFinal: finalHandler, onState: stateHandler)'));
    expect(source, contains('if (resumeHandsFree) _scheduleHandsFreeResume()'));
    expect(source, contains('_scheduleHandsFreeResume();'));
  });

  test('no-speech timeout re-arms hands-free instead of getting stuck', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains("'speech_timeout'"));
    expect(
      source,
      contains('_scheduleHandsFreeResume(delay: const Duration(milliseconds: 650))'),
    );
  });

  test('manual stop and voice error can disarm the automatic loop', () async {
    final voice = await File('lib/src/voice_service.dart').readAsString();
    final app = await File('lib/main.dart').readAsString();

    expect(voice, contains('void disarmHandsFree()'));
    expect(voice, contains('if (!_finalTranscriptDelivered)'));
    expect(app, contains('_voice.disarmHandsFree()'));
  });

  test('keyboard input explicitly leaves voice hands-free mode', () async {
    final source = await File('lib/main.dart').readAsString();

    expect(source, contains("if (inputMode != 'voice') _voice.disarmHandsFree()"));
    expect(source, contains("_send(text, inputMode: 'voice')"));
  });

  test('redirect and clarification do not create duplicate re-listen loops', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains('resumeHandsFree: false'));
    expect(source, contains('automaticBargeIn: false'));
  });
}
