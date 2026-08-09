import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'local_store.dart';
import 'mic_status.dart';
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

  Uri _url(String path) =>
      Uri.parse('${config.modelApiBase.replaceAll(RegExp(r'/$'), '')}$path');

  String _withRuntimeContext(String systemPrompt) {
    final base = systemPrompt.trim();
    final device = MomRuntimeDeviceState.promptContext;
    return device.isEmpty ? base : '$base\n\n$device';
  }

  String _directSystem(String systemPrompt, String knowledgeContext) {
    final system = StringBuffer(_withRuntimeContext(systemPrompt));
    if (knowledgeContext.trim().isNotEmpty) {
      system.write('\n\n## Relevant MOM repository knowledge\n');
      system.write(
        'Use this as reference material. It may be incomplete or stale; do not treat it as user-confirmed memory.\n',
      );
      system.write(knowledgeContext.trim());
    }
    return system.toString();
  }

  List<Map<String, String>> _directMessages({
    required String systemPrompt,
    required List<ChatTurn> history,
    required String userText,
    String knowledgeContext = '',
  }) {
    final recent = history.length > config.maxHistory
        ? history.sublist(history.length - config.maxHistory)
        : history;
    return <Map<String, String>>[
      {
        'role': 'system',
        'content': _directSystem(systemPrompt, knowledgeContext),
      },
      ...recent
          .where((turn) => turn.role == 'user' || turn.role == 'assistant')
          .map((turn) => {
                'role': turn.role,
                'content': turn.content,
              }),
      {'role': 'user', 'content': userText},
    ];
  }

  Future<List<String>> _listDirectModels({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final response =
        await _http.get(_url('/models'), headers: _headers).timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Model API HTTP ${response.statusCode}',
        uri: _url('/models'),
      );
    }
    final data = jsonDecode(response.body);
    if (data is! Map<String, dynamic> || data['data'] is! List) return const [];
    return (data['data'] as List)
        .whereType<Map>()
        .map((item) => '${item['id'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> listModels({
    Duration timeout = const Duration(seconds: 10),
  }) async {
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
    final response = await _http
        .post(
          _url('/chat/completions'),
          headers: _headers,
          body: jsonEncode({
            'model': model,
            'messages': _directMessages(
              systemPrompt: systemPrompt,
              history: history,
              userText: userText,
              knowledgeContext: knowledgeContext,
            ),
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

  Future<ModelReply> _directChatStream({
    required String systemPrompt,
    required List<ChatTurn> history,
    required String userText,
    required void Function(String delta) onDelta,
    String knowledgeContext = '',
  }) async {
    final model = await resolveModel();
    final target = _url('/chat/completions');
    final request = http.Request('POST', target)
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': model,
        'messages': _directMessages(
          systemPrompt: systemPrompt,
          history: history,
          userText: userText,
          knowledgeContext: knowledgeContext,
        ),
        'temperature': config.temperature,
        'stream': true,
      });
    final response = await _http.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = await response.stream.bytesToString();
      throw HttpException(
        'Model API HTTP ${response.statusCode}: $detail',
        uri: target,
      );
    }

    final text = StringBuffer();
    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(minutes: 5));
    await for (final rawLine in lines) {
      final line = rawLine.trim();
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty) continue;
      if (payload == '[DONE]') break;
      final decoded = jsonDecode(payload);
      if (decoded is! Map<String, dynamic>) continue;
      try {
        final delta = decoded['choices'][0]['delta']['content'];
        if (delta is String && delta.isNotEmpty) {
          text.write(delta);
          onDelta(delta);
        }
      } catch (_) {}
    }
    if (text.toString().trim().isEmpty) {
      throw const FormatException('Model stream returned no text.');
    }
    return ModelReply(text: text.toString().trim(), model: model);
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
      systemPrompt: _withRuntimeContext(systemPrompt),
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

  Future<ModelReply> chatStream({
    required String systemPrompt,
    required List<ChatTurn> history,
    required String userText,
    required void Function(String delta) onDelta,
    String knowledgeContext = '',
  }) async {
    if (_useDirectLocalModel) {
      return _directChatStream(
        systemPrompt: systemPrompt,
        history: history,
        userText: userText,
        knowledgeContext: knowledgeContext,
        onDelta: onDelta,
      );
    }

    final recent = history.length > config.maxHistory
        ? history.sublist(history.length - config.maxHistory)
        : history;
    final reply = await _sync.brainChatStream(
      systemPrompt: _withRuntimeContext(systemPrompt),
      history: recent
          .where((turn) => turn.role == 'user' || turn.role == 'assistant')
          .map((turn) => {'role': turn.role, 'content': turn.content})
          .toList(growable: false),
      userText: userText,
      model: config.modelName.trim(),
      temperature: config.temperature,
      maxHistory: config.maxHistory,
      onDelta: onDelta,
    );
    return ModelReply(text: reply.text, model: reply.model);
  }

  void close() {
    _http.close();
    _sync.close();
  }
}
