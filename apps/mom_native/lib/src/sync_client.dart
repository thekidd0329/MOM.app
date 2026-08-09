import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'privacy_filter.dart';

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
  static final Map<String, Future<void>> _registrationFlights = {};

  String _serviceUrl(String service) {
    final uri = Uri.parse(syncUrl);
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty && segments.last == 'mom-sync') {
      segments[segments.length - 1] = service;
    } else if (segments.isEmpty || segments.last != service) {
      segments.add(service);
    }
    return uri.replace(pathSegments: segments).toString();
  }

  String get brainUrl => _serviceUrl('mom-brain');
  String get brainStreamUrl => _serviceUrl('mom-brain-stream');
  String get intelligenceUrl => _serviceUrl('mom-intelligence');
  String get loginUrl => _serviceUrl('mom-login');

  Future<Map<String, String>> _authenticatedHeaders() async {
    final installation = await _secure.read(key: _installationKey);
    final token = await _secure.read(key: _tokenKey);
    if (installation == null || token == null) {
      throw StateError('MOM cloud installation is not registered.');
    }
    return {
      'content-type': 'application/json',
      'x-mom-installation': installation,
      'x-mom-token': token,
    };
  }

  Future<Map<String, dynamic>> _post(
    Map<String, dynamic> payload, {
    bool authenticated = false,
    Duration timeout = const Duration(seconds: 20),
    String? endpoint,
  }) async {
    final headers = authenticated
        ? await _authenticatedHeaders()
        : <String, String>{'content-type': 'application/json'};
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

  Future<bool> intelligenceHealth() async {
    try {
      final result = await _post({'action': 'health'}, endpoint: intelligenceUrl);
      return result['ok'] == true && result['configured'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> loginHealth() async {
    try {
      final result = await _post({'action': 'health'}, endpoint: loginUrl);
      return result['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureRegistered({String appVersion = '0.4.0'}) async {
    if (await registered()) return;
    final inFlight = _registrationFlights[syncUrl];
    if (inFlight != null) {
      await inFlight;
      if (await registered()) return;
    }
    final registration = _register(appVersion: appVersion);
    _registrationFlights[syncUrl] = registration;
    try {
      await registration;
    } finally {
      if (identical(_registrationFlights[syncUrl], registration)) {
        _registrationFlights.remove(syncUrl);
      }
    }
  }

  Future<void> _register({required String appVersion}) async {
    if (await registered()) return;
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
          'metadata': const {'privacy_mode': 'local_raw_deid_cloud_v1'},
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

  Future<Map<String, dynamic>> loginStatus() async {
    await ensureRegistered();
    return _post({'action': 'status'}, authenticated: true, endpoint: loginUrl);
  }

  Future<Map<String, dynamic>> createLoginTransferToken() async {
    await ensureRegistered();
    final result = await _post(
      {'action': 'create_transfer_token', 'privacy_acknowledged': true},
      authenticated: true,
      endpoint: loginUrl,
    );
    final token = result['transfer_token'];
    final expiresAt = result['expires_at'];
    if (token is! String || token.trim().isEmpty || expiresAt is! String) {
      throw const FormatException('MOM login token response was incomplete.');
    }
    return result;
  }

  Future<Map<String, dynamic>> redeemLoginTransferToken(String transferToken) async {
    final token = transferToken.trim();
    if (token.isEmpty) throw const FormatException('Enter a MOM transfer code.');
    await ensureRegistered();
    final result = await _post(
      {
        'action': 'redeem_transfer_token',
        'transfer_token': token,
        'privacy_acknowledged': true,
      },
      authenticated: true,
      endpoint: loginUrl,
    );
    if (result['linked'] != true) {
      throw const FormatException('MOM login did not finish linking this device.');
    }
    return result;
  }

  Future<void> revokeLoginTransferTokens() async {
    await ensureRegistered();
    await _post({'action': 'revoke_transfer_tokens'}, authenticated: true, endpoint: loginUrl);
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

  Future<BrainReply> brainChatStream({
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userText,
    required void Function(String delta) onDelta,
    String model = '',
    double temperature = 0.72,
    int maxHistory = 30,
  }) async {
    await ensureRegistered();
    final target = Uri.parse(brainStreamUrl);
    final request = http.Request('POST', target)
      ..headers.addAll(await _authenticatedHeaders())
      ..body = jsonEncode({
        'action': 'chat_stream',
        'system_prompt': systemPrompt,
        'history': history,
        'user_text': userText,
        'model': model,
        'temperature': temperature,
        'max_history': maxHistory,
      });
    final response = await _http.send(request).timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = await response.stream.bytesToString();
      throw HttpException('MOM brain stream HTTP ${response.statusCode}: $detail', uri: target);
    }

    final text = StringBuffer();
    var resolvedModel = model.trim();
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
      if (decoded['type'] == 'meta' && decoded['model'] is String) {
        resolvedModel = (decoded['model'] as String).trim();
      } else if (decoded['type'] == 'delta' && decoded['delta'] is String) {
        final delta = decoded['delta'] as String;
        if (delta.isNotEmpty) {
          text.write(delta);
          onDelta(delta);
        }
      } else if (decoded['type'] == 'error') {
        throw HttpException('MOM brain stream failed: ${decoded['error'] ?? 'unknown'}', uri: target);
      }
    }
    if (text.toString().trim().isEmpty) {
      throw const FormatException('MOM brain stream returned no text.');
    }
    if (resolvedModel.isEmpty) resolvedModel = model.trim();
    return BrainReply(text: text.toString().trim(), model: resolvedModel);
  }

  Future<Map<String, dynamic>> intelligenceSnapshot() async {
    await ensureRegistered();
    return _post(
      {'action': 'snapshot'},
      authenticated: true,
      endpoint: intelligenceUrl,
      timeout: const Duration(seconds: 30),
    );
  }

  Future<void> syncChat({
    required String sessionId,
    required String role,
    required String content,
    String modelProvider = '',
    String modelName = '',
    Map<String, dynamic> metadata = const {},
  }) async {
    if (role != 'user') return;
    final deidentified = MomPrivacyFilter.deidentify(content);
    if (!deidentified.isUseful) return;
    await ensureRegistered();
    await _post(
      {
        'action': 'process_deidentified',
        'privacy_version': 'deid-v1',
        'sanitized_text': deidentified.text,
        'original_characters': content.length,
        'redaction_count': deidentified.redactionCount,
        'redaction_kinds': deidentified.redactionKinds.toList()..sort(),
      },
      authenticated: true,
      endpoint: intelligenceUrl,
      timeout: const Duration(minutes: 2),
    );
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
  }) async {}

  Future<Map<String, dynamic>> history({int limit = 100}) async => const {
        'sessions': <dynamic>[],
        'messages': <dynamic>[],
        'local_only': true,
      };

  void close() => _http.close();
}
