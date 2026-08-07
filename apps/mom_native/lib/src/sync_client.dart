import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class BrainReply {
  const BrainReply({required this.text, required this.model});

  final String text;
  final String model;
}

class MomSyncClient {
  MomSyncClient({
    required this.syncUrl,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
  })  : _secure = secureStorage ?? const FlutterSecureStorage(),
        _http = httpClient ?? http.Client();

  final String syncUrl;
  final FlutterSecureStorage _secure;
  final http.Client _http;

  static const _installationKey = 'mom_installation_id';
  static const _tokenKey = 'mom_installation_token';
  static const _deviceKey = 'mom_device_id';

  String get brainUrl {
    final uri = Uri.parse(syncUrl);
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty && segments.last == 'mom-sync') {
      segments[segments.length - 1] = 'mom-brain';
    } else if (segments.isEmpty || segments.last != 'mom-brain') {
      segments.add('mom-brain');
    }
    return uri.replace(pathSegments: segments).toString();
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> payload, {
    bool authenticated = false,
    Duration timeout = const Duration(seconds: 20),
    String? endpoint,
  }) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (authenticated) {
      final installation = await _secure.read(key: _installationKey);
      final token = await _secure.read(key: _tokenKey);
      if (installation == null || token == null) {
        throw StateError('MOM cloud installation is not registered.');
      }
      headers['x-mom-installation'] = installation;
      headers['x-mom-token'] = token;
    }
    final target = Uri.parse(endpoint ?? syncUrl);
    final response = await _http
        .post(target, headers: headers, body: jsonEncode(payload))
        .timeout(timeout);
    Map<String, dynamic> decoded = {};
    if (response.body.isNotEmpty) {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) decoded = value;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'MOM cloud HTTP ${response.statusCode}: ${decoded['error'] ?? response.body}',
        uri: target,
      );
    }
    return decoded;
  }

  Future<bool> health() async {
    try {
      final result = await _post({'action': 'health'});
      return result['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> brainHealth() async {
    try {
      final result = await _post({'action': 'health'}, endpoint: brainUrl);
      return result['ok'] == true && result['configured'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureRegistered({String appVersion = '0.2.0'}) async {
    final installation = await _secure.read(key: _installationKey);
    final token = await _secure.read(key: _tokenKey);
    if (installation != null && token != null) return;

    final prefs = await SharedPreferences.getInstance();
    var deviceId = prefs.getString(_deviceKey) ?? 'mom-${const Uuid().v4()}';
    await prefs.setString(_deviceKey, deviceId);

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final result = await _post({
          'action': 'register',
          'device_id': deviceId,
          'platform': Platform.operatingSystem,
          'app_version': appVersion,
          'metadata': {
            'os_version': Platform.operatingSystemVersion,
            'locale': Platform.localeName,
          },
        });
        final id = result['installation_id'];
        final newToken = result['token'];
        if (id is! String || newToken is! String) {
          throw const FormatException('Registration response was incomplete.');
        }
        await _secure.write(key: _installationKey, value: id);
        await _secure.write(key: _tokenKey, value: newToken);
        return;
      } on HttpException catch (error) {
        if (attempt == 0 && error.message.contains('device_already_registered')) {
          deviceId = 'mom-${const Uuid().v4()}';
          await prefs.setString(_deviceKey, deviceId);
          continue;
        }
        rethrow;
      }
    }
  }

  Future<bool> registered() async {
    return await _secure.read(key: _installationKey) != null &&
        await _secure.read(key: _tokenKey) != null;
  }

  Future<List<String>> brainModels() async {
    await ensureRegistered();
    final result = await _post(
      {'action': 'models'},
      authenticated: true,
      endpoint: brainUrl,
      timeout: const Duration(seconds: 30),
    );
    final raw = result['models'];
    if (raw is! List) return const [];
    return raw.whereType<String>().where((value) => value.trim().isNotEmpty).toList(growable: false);
  }

  Future<BrainReply> brainChat({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userText,
    String knowledgeContext = '',
    String model = '',
    double temperature = 0.72,
    int maxHistory = 30,
  }) async {
    await ensureRegistered();
    final result = await _post(
      {
        'action': 'chat',
        'system_prompt': systemPrompt,
        'history': history,
        'user_text': userText,
        'knowledge_context': knowledgeContext,
        'model': model,
        'temperature': temperature,
        'max_history': maxHistory,
      },
      authenticated: true,
      endpoint: brainUrl,
      timeout: const Duration(minutes: 5),
    );
    final text = result['text'];
    final resolvedModel = result['model'];
    if (text is! String || text.trim().isEmpty || resolvedModel is! String) {
      throw const FormatException('MOM brain returned an unexpected response.');
    }
    return BrainReply(text: text.trim(), model: resolvedModel.trim());
  }

  Future<void> syncChat({
    required String sessionId,
    required String role,
    required String content,
    String modelProvider = '',
    String modelName = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    await ensureRegistered();
    await _post({
      'action': 'sync_chat',
      'session_id': sessionId,
      'role': role,
      'content': content,
      'model_provider': modelProvider,
      'model_name': modelName,
      'metadata': metadata,
    }, authenticated: true);
  }

  Future<void> event(
    String eventType, {
    String? sessionId,
    Map<String, dynamic> payload = const {},
  }) async {
    await ensureRegistered();
    await _post({
      'action': 'event',
      'event_type': eventType,
      if (sessionId != null) 'session_id': sessionId,
      'payload': payload,
    }, authenticated: true);
  }

  Future<void> memory({
    required String content,
    String? sessionId,
    String kind = 'observation',
    String? subject,
    String truthState = 'candidate',
    double confidence = 0.5,
  }) async {
    await ensureRegistered();
    await _post({
      'action': 'memory',
      'content': content,
      if (sessionId != null) 'session_id': sessionId,
      'kind': kind,
      if (subject != null) 'subject': subject,
      'truth_state': truthState,
      'confidence': confidence,
    }, authenticated: true);
  }

  Future<Map<String, dynamic>> history({int limit = 100}) async {
    await ensureRegistered();
    return _post({'action': 'history', 'limit': limit}, authenticated: true);
  }

  void close() => _http.close();
}
