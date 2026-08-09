class InterruptedThought {
  const InterruptedThought({
    required this.originalText,
    required this.completedText,
    required this.resumeText,
    required this.interruptedChunkIndex,
    required this.currentChunkMayBePartial,
  });

  final String originalText;
  final String completedText;
  final String resumeText;
  final int interruptedChunkIndex;
  final bool currentChunkMayBePartial;

  bool get hasUnfinishedText => resumeText.trim().isNotEmpty;

  String contextForNextTurn(String userText) {
    final interruption = userText.trim();
    final parts = <String>[
      'You were interrupted while speaking.',
      if (completedText.trim().isNotEmpty)
        'You had definitely finished saying: ${completedText.trim()}',
      if (resumeText.trim().isNotEmpty)
        'The thought you had not safely finished was: ${resumeText.trim()}',
      if (interruption.isNotEmpty) 'Your person cut in with: $interruption',
      'Respond to what they just said first. Continue the unfinished thought only if it still matters naturally.',
    ];
    return parts.join('\n');
  }
}

class MomBargeInController {
  int _generation = 0;
  List<String> _chunks = const [];
  int _completedCount = 0;
  int? _currentChunkIndex;
  String _originalText = '';
  InterruptedThought? _pendingThought;

  int get generation => _generation;
  bool get speaking => _chunks.isNotEmpty;
  InterruptedThought? get pendingThought => _pendingThought;

  int begin({
    required String originalText,
    required List<String> chunks,
  }) {
    _generation++;
    _originalText = originalText.trim();
    _chunks = List<String>.unmodifiable(
      chunks.map((chunk) => chunk.trim()).where((chunk) => chunk.isNotEmpty),
    );
    _completedCount = 0;
    _currentChunkIndex = null;
    _pendingThought = null;
    return _generation;
  }

  bool isCurrent(int generation) => generation == _generation;

  void markChunkStarted(int index) {
    if (index < 0 || index >= _chunks.length) return;
    _currentChunkIndex = index;
  }

  void markChunkCompleted(int index) {
    if (index < 0 || index >= _chunks.length) return;
    _completedCount = index + 1 > _completedCount ? index + 1 : _completedCount;
    if (_currentChunkIndex == index) _currentChunkIndex = null;
    if (_completedCount >= _chunks.length) {
      _chunks = const [];
      _originalText = '';
      _completedCount = 0;
      _currentChunkIndex = null;
    }
  }

  InterruptedThought? interrupt() {
    if (_chunks.isEmpty) return null;
    _generation++;

    final current = _currentChunkIndex;
    final resumeIndex = current ?? _completedCount;
    final boundedResumeIndex = resumeIndex < 0
        ? 0
        : (resumeIndex > _chunks.length ? _chunks.length : resumeIndex);
    final completed = _chunks.take(_completedCount).join(' ').trim();
    final resume = _chunks.skip(boundedResumeIndex).join(' ').trim();
    final thought = InterruptedThought(
      originalText: _originalText,
      completedText: completed,
      resumeText: resume,
      interruptedChunkIndex: boundedResumeIndex,
      currentChunkMayBePartial: current != null,
    );

    _pendingThought = thought;
    _chunks = const [];
    _originalText = '';
    _completedCount = 0;
    _currentChunkIndex = null;
    return thought;
  }

  InterruptedThought? consumePendingThought() {
    final thought = _pendingThought;
    _pendingThought = null;
    return thought;
  }

  void cancelWithoutContinuity() {
    _generation++;
    _chunks = const [];
    _originalText = '';
    _completedCount = 0;
    _currentChunkIndex = null;
    _pendingThought = null;
  }
}
