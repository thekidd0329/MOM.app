import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'sync_client.dart';

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

class MomBrainStreamClient {
  MomBrainStreamClient({
    required this.syncUrl,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
    MomSyncClient? registrationClient,
  })  : _secure = secureStorage ?? const FlutterSecureStorage(),
        _http = httpClient ?? http.Client(),
        _registration = registrationClient ?? MomSyncClient(syncUrl: syncUrl),
        _ownsRegistration = registrationClient == null;

  static const _installationKey = 'mom_installation_id';
  static const _tokenKey = 'mom_installation_token';

  final String syncUrl;
  final FlutterSecureStorage _secure;
  final http.Client _http;
  final MomSyncClient _registration;
  final bool _ownsRegistration;

  String get streamUrl {
    final uri = Uri.parse(syncUrl);
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty && segments.last == 'mom-sync') {
      segments[segments.length - 1] = 'mom-brain-stream';
    } else if (segments.isEmpty || segments.last != 'mom-brain-stream') {
      segments.add('mom-brain-stream');
    }
    return uri.replace(pathSegments: segments).toString();
  }

  Future<Map<String, String>> _authenticatedHeaders() async {
    await _registration.ensureRegistered();
    final installation = await _secure.read(key: _installationKey);
    final token = await _secure.read(key: _tokenKey);
    if (installation == null || token == null) {
      throw StateError('MOM cloud installation is not registered.');
    }
    return {
      'content-type': 'application/json',
      'accept': 'text/event-stream',
      'x-mom-installation': installation,
      'x-mom-token': token,
    };
  }

  Stream<BrainStreamChunk> chat({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userText,
    String model = '',
    double temperature = 0.72,
    int maxHistory = 8,
  }) async* {
    final text = userText.trim();
    if (text.isEmpty) throw const FormatException('MOM needs user text to stream.');

    final request = http.Request('POST', Uri.parse(streamUrl));
    request.headers.addAll(await _authenticatedHeaders());
    request.body = jsonEncode({
      'system_prompt': systemPrompt,
      'history': history,
      'user_text': text,
      'model': model,
      'temperature': temperature,
      'max_history': maxHistory,
    });

    final response = await _http.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await utf8.decoder.bind(response.stream).join();
      throw HttpException(
        'MOM brain stream HTTP ${response.statusCode}: $body',
        uri: Uri.parse(streamUrl),
      );
    }

    var resolvedModel = response.headers['x-mom-model']?.trim() ?? '';
    await for (final line in response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('data:')) continue;
      final data = trimmed.substring(5).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') {
        yield BrainStreamChunk(delta: '', model: resolvedModel, done: true);
        return;
      }

      dynamic decoded;
      try {
        decoded = jsonDecode(data);
      } catch (_) {
        continue;
      }
      if (decoded is! Map) continue;
      final responseModel = '${decoded['model'] ?? ''}'.trim();
      if (responseModel.isNotEmpty) resolvedModel = responseModel;
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty || choices.first is! Map) continue;
      final choice = choices.first as Map;
      final delta = choice['delta'];
      if (delta is! Map) continue;
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        yield BrainStreamChunk(
          delta: content,
          model: resolvedModel,
          done: false,
        );
      }
    }

    yield BrainStreamChunk(delta: '', model: resolvedModel, done: true);
  }

  void close() {
    _http.close();
    if (_ownsRegistration) _registration.close();
  }
}
