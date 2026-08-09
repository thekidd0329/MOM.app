List<String> splitSpeechChunks(
  String text, {
  int targetCharacters = 150,
  int maximumCharacters = 230,
}) {
  final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalized.isEmpty) return const [];
  if (normalized.length <= maximumCharacters) return [normalized];

  final sentences = normalized.split(RegExp(r'(?<=[.!?])\s+'));
  final chunks = <String>[];
  var current = '';

  void flush() {
    final value = current.trim();
    if (value.isNotEmpty) chunks.add(value);
    current = '';
  }

  void appendWords(String value) {
    for (final word in value.split(' ')) {
      if (word.isEmpty) continue;
      if (current.isEmpty) {
        current = word;
        continue;
      }
      final candidate = '$current $word';
      if (candidate.length > maximumCharacters) {
        flush();
        current = word;
      } else {
        current = candidate;
      }
    }
  }

  for (final sentence in sentences) {
    final value = sentence.trim();
    if (value.isEmpty) continue;

    if (value.length > maximumCharacters) {
      flush();
      appendWords(value);
      if (current.length >= targetCharacters) flush();
      continue;
    }

    if (current.isEmpty) {
      current = value;
    } else if ('$current $value'.length <= maximumCharacters &&
        current.length < targetCharacters) {
      current = '$current $value';
    } else {
      flush();
      current = value;
    }

    if (current.length >= targetCharacters &&
        RegExp(r'[.!?]$').hasMatch(current)) {
      flush();
    }
  }

  flush();
  return chunks;
}
