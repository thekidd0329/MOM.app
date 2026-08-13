class MomTranscriptQuality {
  const MomTranscriptQuality();

  static const _shortValidAnswers = <String>{
    'yes', 'yeah', 'yep', 'no', 'nope', 'okay', 'ok', 'sure', 'maybe',
  };

  static const _stopWords = <String>{
    'a', 'an', 'and', 'are', 'at', 'be', 'but', 'did', 'do', 'does', 'for',
    'from', 'had', 'has', 'have', 'i', 'in', 'is', 'it', 'me', 'my', 'of',
    'on', 'or', 'so', 'that', 'the', 'then', 'this', 'to', 'was', 'we',
    'were', 'with', 'you', 'your',
  };

  bool shouldClarify({
    required String finalTranscript,
    String previousPartial = '',
  }) {
    final normalized = _normalize(finalTranscript);
    if (normalized.isEmpty) return true;
    if (_shortValidAnswers.contains(normalized.toLowerCase())) return false;

    final words = _words(normalized);
    if (words.isEmpty) return true;

    final alphabetic = normalized.runes
        .where((rune) =>
            (rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122))
        .length;
    final visible = normalized.runes.where((rune) => rune > 32).length;
    if (visible > 0 && alphabetic / visible < 0.45) return true;

    if (words.length >= 4) {
      final counts = <String, int>{};
      for (final word in words) {
        counts[word] = (counts[word] ?? 0) + 1;
      }
      final mostRepeated = counts.values.fold<int>(0, (a, b) => a > b ? a : b);
      if (mostRepeated >= 4 && mostRepeated / words.length >= 0.70) return true;
    }

    final partialWords = _contentWords(previousPartial);
    final finalWords = _contentWords(normalized);
    if (partialWords.length >= 6 && finalWords.length >= 4) {
      final overlap = partialWords.intersection(finalWords);
      if (overlap.isEmpty) return true;
    }

    return false;
  }

  String _normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

  List<String> _words(String value) => _normalize(value)
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z0-9'\s]"), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);

  Set<String> _contentWords(String value) => _words(value)
      .where((word) => word.length >= 3 && !_stopWords.contains(word))
      .toSet();
}
