class InterruptedMomThought {
  const InterruptedMomThought({
    required this.heardText,
    required this.unsaidText,
    required this.currentChunkMayBePartial,
  });

  final String heardText;
  final String unsaidText;
  final bool currentChunkMayBePartial;

  bool get hasUnsaidText => unsaidText.trim().isNotEmpty;

  String toAssistantHistoryContext() {
    final parts = <String>[
      '[MOM VOICE CONTINUITY]',
      'Your previous spoken response was interrupted by the user.',
      if (heardText.trim().isNotEmpty)
        'They heard approximately: ${heardText.trim()}',
      if (unsaidText.trim().isNotEmpty)
        'You had not finished saying: ${unsaidText.trim()}',
      if (currentChunkMayBePartial)
        'The interruption happened during a spoken chunk, so the heard boundary is an estimate.',
      'Respond to the user interruption first. Resume the unfinished thought only if it still matters naturally. Do not recite this continuity note.',
      '[/MOM VOICE CONTINUITY]',
    ];
    return parts.join('\n');
  }
}

class MomVoiceContinuity {
  static InterruptedMomThought? _pending;

  static InterruptedMomThought? get pending => _pending;

  static void preserve(InterruptedMomThought thought) {
    if (!thought.hasUnsaidText) return;
    _pending = thought;
  }

  static InterruptedMomThought? consume() {
    final thought = _pending;
    _pending = null;
    return thought;
  }

  static void clear() => _pending = null;
}
