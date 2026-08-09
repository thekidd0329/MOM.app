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

    test('interruption is a first-class state', () {
      final machine = MomVoiceStateMachine();

      machine.transition(MomVoiceState.thinking);
      machine.transition(MomVoiceState.synthesizing);
      machine.transition(MomVoiceState.interrupted);
      machine.transition(MomVoiceState.listening);

      expect(machine.state, MomVoiceState.listening);
      expect(machine.label, 'Listening...');
    });

    test('errors are recoverable without inventing boolean state', () {
      final machine = MomVoiceStateMachine();

      machine.transition(MomVoiceState.listening);
      machine.transition(MomVoiceState.error);
      expect(machine.label, 'Try me again');
      machine.recover();

      expect(machine.state, MomVoiceState.idle);
    });

    test('invalid transitions are rejected', () {
      final machine = MomVoiceStateMachine();

      expect(
        () => machine.transition(MomVoiceState.speaking),
        throwsStateError,
      );
    });

    test('derived interaction flags come from the state', () {
      final machine = MomVoiceStateMachine();

      expect(machine.blocksTextInput, isFalse);
      expect(machine.listening, isFalse);

      machine.transition(MomVoiceState.listening);
      expect(machine.listening, isTrue);
      expect(machine.energized, isTrue);
      expect(machine.blocksTextInput, isFalse);

      machine.transition(MomVoiceState.thinking);
      expect(machine.blocksTextInput, isTrue);
      machine.transition(MomVoiceState.synthesizing);
      expect(machine.blocksTextInput, isTrue);
      machine.transition(MomVoiceState.speaking);
      expect(machine.blocksTextInput, isTrue);
    });
  });

  test('app no longer stores loose busy/listening voice booleans', () async {
    final source = await File('lib/main.dart').readAsString();

    expect(source, isNot(contains('bool _busy =')));
    expect(source, isNot(contains('bool _listening =')));
    expect(source, contains('MomVoiceStateMachine _voiceState'));
    expect(source, contains('MomVoiceState.synthesizing'));
    expect(source, contains('MomVoiceState.speaking'));
  });
}
