class MomPartialRedirector {
  const MomPartialRedirector();

  static const _stopWords = <String>{
    'a', 'an', 'and', 'are', 'at', 'be', 'but', 'did', 'do', 'does', 'for',
    'from', 'had', 'has', 'have', 'how', 'i', 'in', 'is', 'it', 'me', 'my',
    'of', 'on', 'or', 'so', 'that', 'the', 'then', 'this', 'to', 'was', 'we',
    'were', 'what', 'when', 'where', 'which', 'who', 'why', 'with', 'you',
    'your',
  };

  String? redirectFor({
    required String lastMomSpeech,
    required String partialTranscript,
  }) {
    final question = _lastQuestion(lastMomSpeech);
    if (question == null) return null;

    final partialWords = _words(partialTranscript);
    if (partialWords.length < 12) return null;
    if (_soundsLikeDirectAnswer(partialTranscript)) return null;

    final questionTopics = _topics(question);
    if (questionTopics.length < 2) return null;
    final partialTopics = _topics(partialTranscript);
    if (partialTopics.any(questionTopics.contains)) return null;

    return 'Wait, you’re dodging the question.';
  }

  String? _lastQuestion(String speech) {
    final normalized = speech.replaceAll(RegExp(r'\s+'), ' ').trim();
    final questionMark = normalized.lastIndexOf('?');
    if (questionMark < 0) return null;

    var start = questionMark - 1;
    while (start >= 0) {
      final char = normalized[start];
      if (char == '.' || char == '!' || char == '?') break;
      start--;
    }
    final question = normalized.substring(start + 1, questionMark + 1).trim();
    return question.length >= 8 ? question : null;
  }

  Set<String> _topics(String value) => _words(value)
      .where((word) => word.length >= 4 && !_stopWords.contains(word))
      .toSet();

  List<String> _words(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList(growable: false);

  bool _soundsLikeDirectAnswer(String value) {
    final normalized = value.toLowerCase();
    return normalized.contains("i don't know") ||
        normalized.contains('i dont know') ||
        normalized.contains("i'm not sure") ||
        normalized.contains('im not sure') ||
        normalized.startsWith('yes ') ||
        normalized == 'yes' ||
        normalized.startsWith('no ') ||
        normalized == 'no' ||
        normalized.contains('because ');
  }
}
