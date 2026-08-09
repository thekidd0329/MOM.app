import 'dart:convert';

class BrainStreamChunk {
  const BrainStreamChunk({
    required this.delta,
    required this.model,
    required this.done,
  });

  final String delta;
  final String model;
  final bool done;
}

class BrainSseParser {
  BrainSseParser({String initialModel = ''}) : _model = initialModel.trim();

  String _model;
  String get model => _model;

  BrainStreamChunk? parseLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('data:')) return null;
    final data = trimmed.substring(5).trim();
    if (data.isEmpty) return null;
    if (data == '[DONE]') {
      return BrainStreamChunk(delta: '', model: _model, done: true);
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(data);
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    final responseModel = '${decoded['model'] ?? ''}'.trim();
    if (responseModel.isNotEmpty) _model = responseModel;

    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return null;
    }
    final choice = choices.first as Map;
    final delta = choice['delta'];
    if (delta is! Map) return null;
    final content = delta['content'];
    if (content is! String || content.isEmpty) return null;

    return BrainStreamChunk(delta: content, model: _model, done: false);
  }
}
