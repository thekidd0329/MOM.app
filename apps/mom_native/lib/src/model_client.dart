import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'local_store.dart';
import 'sync_client.dart';

class ModelReply {
  const ModelReply({required this.text, required this.model});
  final String text;
  final String model;
}

class ModelClient {
  ModelClient(this.config, {http.Client? client, MomSyncClient? syncClient})
      : _http = client ?? http.Client(),
        _sync = syncClient ?? MomSyncClient(syncUrl: config.syncUrl);

  final MomConfig config;
  final http.Client _http;
  final MomSyncClient _sync;

  bool get _useDirectLocalModel => Platform.isLinux && config.useLocalLlama;

  Map<String, String> get _headers {
    final headers = <String, String>{'content-type': 'application/json'};
    if (config.modelApiKey.trim().isNotEmpty) {
      headers['authorization'] = 'Bearer ${config.modelApiKey.trim()}';
    }
    return headers;
  }

  Uri _url(String path) => Uri.parse('${config.modelApiBase.replaceAll(RegExp(r'/$'), '')}$path');

  Future<List<String>> _listDirectModels({Duration timeout = const Duration(seconds: 10)}) async {
    final response = await _http.get(_url('/models'), headers: _headers).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Model API HTTP ${response.statusCode}', uri: _url('/models'));
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['data'] is! List) return const [];
    return (data['data'] as List)
        .whereType<Map>()
        .map((item) => '${item['id'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> listModels({Duration timeout = const Duration(seconds: 10)}) async {
    if (_useDirectLocalModel) return _listDirectModels(timeout: timeout);
    return _sync.brainModels();
  }

  Future<String> resolveModel() async {
    if (config.modelName.trim().isNotEmpty) return config.modelName.trim();
    final models = await listModels();
    if (models.isEmpty) {
      throw StateError('The model endpoint is online but exposes no models.');
    }
    return models.first;
  }

  Future<bool> health() async {
    if (!_useDirectLocalModel) return _sync.brainHealth();
    try {
      await _listDirectModels();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<ModelReply> _directChat({
    required String systemPrompt,
    required List<ChatTurn> history,
    required String userText,
    String knowledgeContext = '',
  }) async {
    final model = await resolveModel();
    final system = StringBuffer(systemPrompt.trim());
    if (knowledgeContext.trim().isNotEmpty) {
      system.write('\n\n## Relevant MOM repository knowledge\n');
      system.write('Use this as reference material. It may be incomplete or stale; do not treat it as user-confirmed memory.\n');
      system.write(knowledgeContext.trim());
    }

    final recent = history.length > config.maxHistory
        ? history.sublist(history.length - config.maxHistory)
        : history;
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system.toString()},
      ...recent.where((t) => t.role == 'user' || t.role == 'assistant').map((t) => {
            'role': t.role,
            'content': t.content,
          }),
      {'role': 'user', 'content': userText},
    ];

    final response = await _http
        .post(
          _url('/chat/completions'),
          headers: _headers,
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': config.temperature,
            'stream': false,
          }),
        )
        .timeout(const Duration(minutes: 5));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Model API HTTP ${response.statusCode}: ${response.body}',
        uri: _url('/chat/completions'),
      );
    }
    final data = jsonDecode(response.body);
    try {
      final content = data['choices'][0]['message']['content'];
      if (content is String && content.trim().isNotEmpty) {
        return ModelReply(text: content.trim(), model: model);
      }
    } catch (_) {}
    throw const FormatException('Model returned an unexpected response.');
  }

  Future<ModelReply> chat({
    required String systemPrompt,
    required List<ChatTurn> history,
    required String userText,
    String knowledgeContext = '',
  }) async {
    if (_useDirectLocalModel) {
      return _directChat(
        systemPrompt: systemPrompt,
        history: history,
        userText: userText,
        knowledgeContext: knowledgeContext,
      );
    }

    final recent = history.length > config.maxHistory
        ? history.sublist(history.length - config.maxHistory)
        : history;
    final reply = await _sync.brainChat(
      systemPrompt: systemPrompt,
      history: recent
          .where((turn) => turn.role == 'user' || turn.role == 'assistant')
          .map((turn) => {'role': turn.role, 'content': turn.content})
          .toList(growable: false),
      userText: userText,
      knowledgeContext: knowledgeContext,
      model: config.modelName.trim(),
      temperature: config.temperature,
      maxHistory: config.maxHistory,
    );
    return ModelReply(text: reply.text, model: reply.model);
  }

  void close() {
    _http.close();
    _sync.close();
  }
}
