import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/voice_state.dart';

void main() {
  group('MOM voice state machine', () {
    test('normal voice turn walks the complete state path', () {
      final machine = MomVoiceStateMachine();

      expect(machine.state, MomVoiceState.idle);
      machine.transition(MomVoiceState.listening);
      machine.transition(MomVoiceState.thinking);
      machine.transition(MomVoiceState.synthesizing);
      machine.transition(MomVoiceState.speaking);
      machine.transition(MomVoiceState.idle);

      expect(machine.state, MomVoiceState.idle);
    });

    test('startup speech can synthesize directly from idle', () {
      final machine = MomVoiceStateMachine();

      machine.transition(MomVoiceState.synthesizing);
      machine.transition(MomVoiceState.speaking);
      machine.transition(MomVoiceState.idle);

      expect(machine.state, MomVoiceState.idle);
    });

    test('interruption and error are first-class states', () {
      final machine = MomVoiceStateMachine();
      machine.transition(MomVoiceState.thinking);
      machine.transition(MomVoiceState.synthesizing);
      machine.transition(MomVoiceState.interrupted);
      machine.transition(MomVoiceState.listening);
      machine.transition(MomVoiceState.error);

      expect(machine.label, 'Voice error');
      machine.recover();
      expect(machine.state, MomVoiceState.idle);
    });

    test('interaction locks derive from state instead of loose booleans', () {
      final machine = MomVoiceStateMachine();
      expect(machine.blocksInput, isFalse);
      machine.transition(MomVoiceState.thinking);
      expect(machine.blocksInput, isTrue);
      machine.transition(MomVoiceState.synthesizing);
      expect(machine.blocksInput, isTrue);
      machine.transition(MomVoiceState.speaking);
      expect(machine.blocksInput, isTrue);
    });
  });

  test('app stores voice lifecycle in the state machine', () async {
    final source = await File('lib/main.dart').readAsString();

    expect(source, isNot(contains('bool _busy =')));
    expect(source, isNot(contains('bool _listening =')));
    expect(source, contains('MomVoiceStateMachine _voiceState'));
    expect(source, contains('MomVoiceState.synthesizing'));
    expect(source, contains('MomVoiceState.speaking'));
  });
}
