enum MomVoiceState {
  idle,
  listening,
  thinking,
  synthesizing,
  speaking,
  interrupted,
  error,
}

class MomVoiceStateMachine {
  MomVoiceStateMachine({MomVoiceState initial = MomVoiceState.idle})
      : _state = initial;

  MomVoiceState _state;

  MomVoiceState get state => _state;

  bool get listening => _state == MomVoiceState.listening;

  bool get blocksTextInput => switch (_state) {
        MomVoiceState.thinking ||
        MomVoiceState.synthesizing ||
        MomVoiceState.speaking => true,
        _ => false,
      };

  bool get energized => switch (_state) {
        MomVoiceState.listening ||
        MomVoiceState.thinking ||
        MomVoiceState.synthesizing ||
        MomVoiceState.speaking => true,
        _ => false,
      };

  String get label => switch (_state) {
        MomVoiceState.idle => 'Tap the mic',
        MomVoiceState.listening => 'Listening...',
        MomVoiceState.thinking => 'Thinking...',
        MomVoiceState.synthesizing => 'Finding my voice...',
        MomVoiceState.speaking => 'MOM',
        MomVoiceState.interrupted => 'Interrupted',
        MomVoiceState.error => 'Try me again',
      };

  void transition(MomVoiceState next) {
    if (next == _state) return;
    if (!_allowed(_state, next)) {
      throw StateError('Invalid MOM voice transition: $_state -> $next');
    }
    _state = next;
  }

  void recover() => _state = MomVoiceState.idle;

  static bool _allowed(MomVoiceState from, MomVoiceState to) {
    if (to == MomVoiceState.error) return true;
    return switch (from) {
      MomVoiceState.idle =>
        to == MomVoiceState.listening || to == MomVoiceState.thinking,
      MomVoiceState.listening =>
        to == MomVoiceState.idle ||
            to == MomVoiceState.thinking ||
            to == MomVoiceState.interrupted,
      MomVoiceState.thinking =>
        to == MomVoiceState.synthesizing || to == MomVoiceState.idle,
      MomVoiceState.synthesizing =>
        to == MomVoiceState.speaking ||
            to == MomVoiceState.interrupted ||
            to == MomVoiceState.idle,
      MomVoiceState.speaking =>
        to == MomVoiceState.idle || to == MomVoiceState.interrupted,
      MomVoiceState.interrupted =>
        to == MomVoiceState.listening || to == MomVoiceState.idle,
      MomVoiceState.error => to == MomVoiceState.idle,
    };
  }
}
