enum MomVoiceConversationPhase {
  idle,
  listening,
  thinking,
  speaking,
  error,
}

class MomVoiceConversationController {
  bool _active = false;
  MomVoiceConversationPhase _phase = MomVoiceConversationPhase.idle;
  int _generation = 0;

  bool get active => _active;
  MomVoiceConversationPhase get phase => _phase;
  int get generation => _generation;

  int enable() {
    _active = true;
    _phase = MomVoiceConversationPhase.idle;
    return ++_generation;
  }

  int disable() {
    _active = false;
    _phase = MomVoiceConversationPhase.idle;
    return ++_generation;
  }

  bool canListen({required bool busy}) {
    return _active &&
        !busy &&
        _phase != MomVoiceConversationPhase.listening &&
        _phase != MomVoiceConversationPhase.thinking &&
        _phase != MomVoiceConversationPhase.speaking;
  }

  void markListening() {
    if (_active) _phase = MomVoiceConversationPhase.listening;
  }

  void markThinking() {
    if (_active) _phase = MomVoiceConversationPhase.thinking;
  }

  void markSpeaking() {
    if (_active) _phase = MomVoiceConversationPhase.speaking;
  }

  bool finishTurn() {
    _phase = MomVoiceConversationPhase.idle;
    return _active;
  }

  bool listeningEndedWithoutTurn() {
    if (_phase == MomVoiceConversationPhase.listening) {
      _phase = MomVoiceConversationPhase.idle;
    }
    return _active;
  }

  void fail() {
    _phase = MomVoiceConversationPhase.error;
    _active = false;
    _generation++;
  }
}
