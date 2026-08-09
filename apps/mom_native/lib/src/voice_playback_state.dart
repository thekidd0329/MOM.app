enum MomVoicePlaybackPhase {
  idle,
  preparing,
  speaking,
}

class MomVoicePlaybackState {
  const MomVoicePlaybackState({
    required this.phase,
    this.chunkIndex = 0,
    this.chunkCount = 0,
  });

  const MomVoicePlaybackState.idle()
      : phase = MomVoicePlaybackPhase.idle,
        chunkIndex = 0,
        chunkCount = 0;

  final MomVoicePlaybackPhase phase;
  final int chunkIndex;
  final int chunkCount;

  bool get active => phase != MomVoicePlaybackPhase.idle;
}
