import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'local_store.dart';
import 'mic_status.dart';
import 'sync_client.dart';

enum ModelFailureKind {
  identity,
  network,
  timeout,
  providerBusy,
  provider,
  service,
  modelDiscovery,
  response,
  configuration,
  unknown,
}

class ModelFailure {
  const ModelFailure({
    required this.kind,
    required this.code,
    required this.stage,
    required this.retryable,
    this.statusCode,
    this.providerStatus,
  });

  final ModelFailureKind kind;
  final String code;
  final String stage;
  final bool retryable;
  final int? statusCode;
  final int? providerStatus;

  String get userMessage => switch (kind) {
        ModelFailureKind.identity =>
          'I lost the cloud identity for this device. I tried reconnecting, but it still is not accepting me.',
        ModelFailureKind.network =>
          'I cannot reach my brain service from this device right now. Check the connection and try again.',
        ModelFailureKind.timeout =>
          'My brain took too long to answer. The request timed out instead of disappearing silently.',
        ModelFailureKind.providerBusy =>
          'My model provider is overloaded right now. Give it a moment and try again.',
        ModelFailureKind.provider => providerStatus == 402
            ? 'My model service is out of available capacity right now. This needs a service-side fix, not anything on your phone.'
            : 'My brain service is reachable, but the model provider is not answering correctly.',
        ModelFailureKind.service =>
          'My cloud brain service is having a server problem right now.',
        ModelFailureKind.modelDiscovery =>
          'My brain service is online, but it cannot resolve a model to answer with.',
        ModelFailureKind.response =>
          'My brain answered, but the response was malformed and I refused to pretend it was usable.',
        ModelFailureKind.configuration =>
          'My brain service is missing required model configuration.',
        ModelFailureKind.unknown =>
          'Something failed in my brain path, and diagnostics has the stage instead of hiding it.',
      };

  String get diagnosticSummary {
    final parts = <String>['stage=$stage', 'code=$code'];
    if (statusCode != null) parts.add('http=$statusCode');
    if (providerStatus != null) parts.add('provider_http=$providerStatus');
    parts.add('retryable=$retryable');
    return parts.join(' · ');
  }
}

ModelFailure classifyModelFailure(Object error) {
  if (error is MomCloudException) {
    if (error.code == 'installation_not_registered' ||
        error.code == 'invalid_installation_token') {
      return ModelFailure(
        kind: ModelFailureKind.identity,
        code: error.code,
        stage: 'installation_identity',
        retryable: true,
        statusCode: error.statusCode,
      );
    }
    if (error.code == 'request_timeout') {
      return ModelFailure(
        kind: ModelFailureKind.timeout,
        code: error.code,
        stage: error.service,
        retryable: true,
      );
    }
    if (error.code == 'network_unreachable' ||
        error.code == 'network_request_failed') {
      return ModelFailure(
        kind: ModelFailureKind.network,
        code: error.code,
        stage: error.service,
        retryable: true,
      );
    }
    if (error.code == 'hf_secret_missing') {
      return ModelFailure(
        kind: ModelFailureKind.configuration,
        code: error.code,
        stage: 'provider_configuration',
        retryable: false,
        statusCode: error.statusCode,
      );
    }
    if (error.code == 'provider_error') {
      if (error.providerStatus == 402) {
        return ModelFailure(
          kind: ModelFailureKind.provider,
          code: 'provider_capacity_exhausted',
          stage: 'model_provider_capacity',
          retryable: false,
          statusCode: error.statusCode,
          providerStatus: error.providerStatus,
        );
      }
      return ModelFailure(
        kind: error.providerStatus == 429
            ? ModelFailureKind.providerBusy
            : ModelFailureKind.provider,
        code: error.code,
        stage: 'model_provider',
        retryable: true,
        statusCode: error.statusCode,
        providerStatus: error.providerStatus,
      );
    }
    if (error.code == 'unexpected_provider_response' ||
        error.code == 'unexpected_brain_response' ||
        error.code == 'invalid_server_response') {
      return ModelFailure(
        kind: ModelFailureKind.response,
        code: error.code,
        stage: error.code == 'invalid_server_response'
            ? error.service
            : 'model_provider_response',
        retryable: true,
        statusCode: error.statusCode,
        providerStatus: error.providerStatus,
      );
    }
    if (error.code.startsWith('model_discovery_') ||
        error.code == 'no_models_available') {
      return ModelFailure(
        kind: ModelFailureKind.modelDiscovery,
        code: error.code,
        stage: 'model_discovery',
        retryable: error.retryable,
        statusCode: error.statusCode,
        providerStatus: error.providerStatus,
      );
    }
    return ModelFailure(
      kind: ModelFailureKind.service,
      code: error.code,
      stage: error.service,
      retryable: error.retryable,
      statusCode: error.statusCode,
      providerStatus: error.providerStatus,
    );
  }

  if (error is TimeoutException) {
    return const ModelFailure(
      kind: ModelFailureKind.timeout,
      code: 'local_model_timeout',
      stage: 'local_model',
      retryable: true,
    );
  }
  if (error is SocketException || error is http.ClientException) {
    return const ModelFailure(
      kind: ModelFailureKind.network,
      code: 'local_model_network',
      stage: 'local_model',
      retryable: true,
    );
  }
  if (error is StateError) {
    return const ModelFailure(
      kind: ModelFailureKind.modelDiscovery,
      code: 'no_models_available',
      stage: 'model_discovery',
      retryable: true,
    );
  }
  if (error is FormatException) {
    return const ModelFailure(
      kind: ModelFailureKind.response,
      code: 'malformed_model_response',
      stage: 'model_provider_response',
      retryable: true,
    );
  }
  if (error is HttpException) {
    return const ModelFailure(
      kind: ModelFailureKind.provider,
      code: 'local_model_http_error',
      stage: 'local_model_provider',
      retryable: true,
    );
  }
  return ModelFailure(
    kind: ModelFailureKind.unknown,
    code: error.runtimeType.toString(),
    stage: 'unknown',
    retryable: true,
  );
}

class ModelReply {
  const ModelReply({required this.text, required this.model});
  final String text;
  final String model;
}

class ModelProbeResult {
  const ModelProbeResult({
    required this.model,
    required this.latencyMs,
    required this.route,
  });

  final String model;
  final int latencyMs;
  final String route;
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

  Future<ModelProbeResult> probe() async {
    if (!_useDirectLocalModel) {
      final result = await _sync.brainProbe(model: config.modelName.trim());
      return ModelProbeResult(
        model: result.model,
        latencyMs: result.latencyMs,
        route: 'supabase→provider→response',
      );
    }

    final timer = Stopwatch()..start();
    final reply = await _directChat(
      systemPrompt:
          'This is a transport health probe. Reply with one very short acknowledgement.',
      history: const [],
      userText: 'Confirm that the local response path is working.',
    );
    timer.stop();
    return ModelProbeResult(
      model: reply.model,
      latencyMs: timer.elapsedMilliseconds,
      route: 'local→provider→response',
    );
  }

  Future<ModelReply> _directChat({
    required String systemPrompt,
    required List<ChatTurn> history,
    required String userText,
    String knowledgeContext = '',
  }) async {
    final model = await resolveModel();
    final system = StringBuffer(_withRuntimeContext(systemPrompt));
    if (knowledgeContext.trim().isNotEmpty) {
      system.write('\n\n## Relevant MOM repository knowledge\n');
      system.write(
        'Use this as reference material. It may be incomplete or stale; do not treat it as user-confirmed memory.\n',
      );
      system.write(knowledgeContext.trim());
    }

    final recent = history.length > config.maxHistory
        ? history.sublist(history.length - config.maxHistory)
        : history;
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': system.toString()},
      ...recent
          .where((t) => t.role == 'user' || t.role == 'assistant')
          .map((t) => {
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

  void close() {
    _http.close();
    _sync.close();
  }
}
