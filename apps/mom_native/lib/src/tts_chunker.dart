class MomTtsChunker {
  const MomTtsChunker({
    this.firstTarget = 96,
    this.laterTarget = 190,
  });

  final int firstTarget;
  final int laterTarget;

  List<String> chunk(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty) return const [];

    final units = _naturalUnits(normalized);
    final chunks = <String>[];
    var buffer = '';

    for (final unit in units) {
      var remaining = unit.trim();
      while (remaining.isNotEmpty) {
        final limit = chunks.isEmpty ? firstTarget : laterTarget;
        if (buffer.isEmpty && remaining.length > limit) {
          final split = splitNearBoundary(remaining, limit);
          chunks.add(split.$1);
          remaining = split.$2;
          continue;
        }

        final combined = buffer.isEmpty ? remaining : '$buffer $remaining';
        if (combined.length <= limit) {
          buffer = combined;
          break;
        }

        if (buffer.isNotEmpty) {
          chunks.add(buffer.trim());
          buffer = '';
        }
      }
    }

    if (buffer.trim().isNotEmpty) chunks.add(buffer.trim());
    return chunks;
  }

  List<String> _naturalUnits(String text) {
    final units = <String>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      final terminal = char == '.' || char == '!' || char == '?';
      final clause = char == ';' || char == ':' || char == ',';
      if (!terminal && !clause) continue;

      final end = i + 1;
      final candidate = text.substring(start, end).trim();
      if (candidate.isNotEmpty) units.add(candidate);
      start = end;
    }
    final tail = text.substring(start).trim();
    if (tail.isNotEmpty) units.add(tail);
    return units;
  }

  (String, String) splitNearBoundary(String text, int limit) {
    if (text.length <= limit) return (text.trim(), '');

    final searchEnd = limit.clamp(1, text.length - 1);
    var split = -1;
    for (var i = searchEnd; i >= 1; i--) {
      final char = text[i];
      if (char == ' ' || char == ',' || char == ';' || char == ':') {
        split = i;
        break;
      }
    }

    if (split < (limit * 0.45).floor()) split = searchEnd;
    final left = text.substring(0, split).trim();
    final right = text.substring(split).trim();
    return (left, right);
  }
}

class MomStreamingTtsAssembler {
  MomStreamingTtsAssembler({MomTtsChunker chunker = const MomTtsChunker()})
      : _chunker = chunker;

  final MomTtsChunker _chunker;
  String _buffer = '';
  bool _emittedFirst = false;

  List<String> add(String delta) {
    if (delta.isEmpty) return const [];
    _buffer += delta;
    final ready = <String>[];

    while (true) {
      _buffer = _buffer.replaceAll(RegExp(r'\s+'), ' ').trimLeft();
      if (_buffer.isEmpty) break;
      final limit = _emittedFirst ? _chunker.laterTarget : _chunker.firstTarget;
      final boundary = _readyBoundary(_buffer, limit);
      if (boundary <= 0) break;

      final chunk = _buffer.substring(0, boundary).trim();
      _buffer = _buffer.substring(boundary).trimLeft();
      if (chunk.isEmpty) continue;
      ready.add(chunk);
      _emittedFirst = true;
    }
    return ready;
  }

  List<String> close() {
    final tail = _buffer.trim();
    _buffer = '';
    if (tail.isEmpty) return const [];
    final chunks = _chunker.chunk(tail);
    if (chunks.isNotEmpty) _emittedFirst = true;
    return chunks;
  }

  int _readyBoundary(String value, int limit) {
    final max = value.length < limit ? value.length : limit;
    final minimumNatural = _emittedFirst ? 45 : 24;

    for (var i = minimumNatural; i < max; i++) {
      final char = value[i];
      if (char == '.' || char == '!' || char == '?') return i + 1;
    }

    final minimumClause = _emittedFirst ? 70 : 40;
    for (var i = minimumClause; i < max; i++) {
      final char = value[i];
      if (char == ';' || char == ':' || char == ',') return i + 1;
    }

    if (value.length < limit) return -1;
    final split = _chunker.splitNearBoundary(value, limit);
    return split.$1.length;
  }
}
