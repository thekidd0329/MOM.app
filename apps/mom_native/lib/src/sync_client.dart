import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'privacy_filter.dart';

class MomCloudException implements Exception {
  const MomCloudException({
    required this.service,
    required this.code,
    required this.message,
    this.statusCode,
    this.providerStatus,
    this.retryable = false,
  });

  final String service;
  final String code;
  final String message;
  final int? statusCode;
  final int? providerStatus;
  final bool retryable;

  @override
  String toString() {
    final status = statusCode == null ? '' : ' HTTP $statusCode';
    final provider = providerStatus == null ? '' : ' provider $providerStatus';
    return 'MOM cloud $service/$code$status$provider: $message';
  }
}

class BrainReply {
  const BrainReply({required this.text, required this.model});

  final String text;
  final String model;
}

class BrainProbeResult {
  const BrainProbeResult({
    required this.model,
    required this.latencyMs,
  });

  final String model;
  final int latencyMs;
}

class MomRuntimeConfig {
  const MomRuntimeConfig({
    required this.schemaVersion,
    required this.release,
    required this.temperature,
    required this.maxHistory,
    required this.requestTimeoutSeconds,
    required this.rawMemoryLocation,
    required this.cloudRawChatStorage,
    required this.bundledRuntimePromptRequired,
    required this.bundledRepositoryKnowledgeRequired,
    required this.updatedAt,
    required this.source,
  });

  final int schemaVersion;
  final String release;
  final double temperature;
  final int maxHistory;
  final int requestTimeoutSeconds;
  final String rawMemoryLocation;
  final bool cloudRawChatStorage;
  final bool bundledRuntimePromptRequired;
  final bool bundledRepositoryKnowledgeRequired;
  final String updatedAt;
  final String source;

  static const safeDefaults = MomRuntimeConfig(
    schemaVersion: 1,
    release: '1.1.0',
    temperature: 0.72,
    maxHistory: 8,
    requestTimeoutSeconds: 300,
    rawMemoryLocation: 'device_only',
    cloudRawChatStorage: false,
    bundledRuntimePromptRequired: false,
    bundledRepositoryKnowledgeRequired: false,
    updatedAt: '',
    source: 'safe_defaults',
  );

  factory MomRuntimeConfig.fromJson(
    Map<String, dynamic> value, {
    required String source,
  }) {
    final temperature = value['temperature'];
    final maxHistory = value['max_history'];
    final timeout = value['request_timeout_seconds'];
    return MomRuntimeConfig(
      schemaVersion: (value['schema_version'] as num?)?.round() ?? 1,
      release: '${value['release'] ?? '1.1.0'}',
      temperature: temperature is num
          ? temperature.toDouble().clamp(0, 2)
          : safeDefaults.temperature,
      maxHistory: maxHistory is num
          ? maxHistory.round().clamp(2, 200)
          : safeDefaults.maxHistory,
      requestTimeoutSeconds: timeout is num
          ? timeout.round().clamp(10, 600)
          : safeDefaults.requestTimeoutSeconds,
      rawMemoryLocation: '${value['raw_memory_location'] ?? 'device_only'}',
      cloudRawChatStorage: value['cloud_raw_chat_storage'] == true,
      bundledRuntimePromptRequired:
          value['bundled_runtime_prompt_required'] == true,
      bundledRepositoryKnowledgeRequired:
          value['bundled_repository_knowledge_required'] == true,
      updatedAt: '${value['updated_at'] ?? ''}',
      source: source,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'release': release,
        'temperature': temperature,
        'max_history': maxHistory,
        'request_timeout_seconds': requestTimeoutSeconds,
        'raw_memory_location': rawMemoryLocation,
        'cloud_raw_chat_storage': cloudRawChatStorage,
        'bundled_runtime_prompt_required': bundledRuntimePromptRequired,
        'bundled_repository_knowledge_required':
            bundledRepositoryKnowledgeRequired,
        'updated_at': updatedAt,
      };
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
  static const _runtimeConfigKey = 'mom_runtime_config_v1';
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

  String get intelligenceUrl => _serviceUrl('mom-intelligence');

  String get loginUrl => _serviceUrl('mom-login');

  String _serviceName(Uri target) {
    if (target.pathSegments.isEmpty) return 'cloud';
    return target.pathSegments.last;
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
        throw const MomCloudException(
          service: 'identity',
          code: 'installation_not_registered',
          message: 'This MOM installation is not registered with the cloud.',
        );
      }
      headers['x-mom-installation'] = installation;
      headers['x-mom-token'] = token;
    }

    final target = Uri.parse(endpoint ?? syncUrl);
    final service = _serviceName(target);
    late http.Response response;
    try {
      response = await _http
          .post(target, headers: headers, body: jsonEncode(payload))
          .timeout(timeout);
    } on TimeoutException {
      throw MomCloudException(
        service: service,
        code: 'request_timeout',
        message: 'The request timed out before $service answered.',
        retryable: true,
      );
    } on SocketException catch (error) {
      throw MomCloudException(
        service: service,
        code: 'network_unreachable',
        message: error.message,
        retryable: true,
      );
    } on http.ClientException catch (error) {
      throw MomCloudException(
        service: service,
        code: 'network_request_failed',
        message: error.message,
        retryable: true,
      );
    }

    Map<String, dynamic> decoded = {};
    if (response.body.isNotEmpty) {
      try {
        final value = jsonDecode(response.body);
        if (value is Map<String, dynamic>) {
          decoded = value;
        } else if (response.statusCode >= 200 && response.statusCode < 300) {
          throw const FormatException('Expected a JSON object.');
        }
      } on FormatException catch (error) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw MomCloudException(
            service: service,
            code: 'invalid_server_response',
            message: error.message,
            statusCode: response.statusCode,
            retryable: true,
          );
        }
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final code = '${decoded['error'] ?? 'http_${response.statusCode}'}';
      final providerStatus = decoded['provider_status'] is num
          ? (decoded['provider_status'] as num).round()
          : null;
      final retryable = response.statusCode == 408 ||
          response.statusCode == 429 ||
          response.statusCode >= 500;
      throw MomCloudException(
        service: service,
        code: code,
        message: '${decoded['detail'] ?? decoded['error'] ?? response.body}',
        statusCode: response.statusCode,
        providerStatus: providerStatus,
        retryable: retryable,
      );
    }
    return decoded;
  }

  Future<Map<String, dynamic>> _brainPost(
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    await ensureRegistered();
    try {
      return await _post(
        payload,
        authenticated: true,
        endpoint: brainUrl,
        timeout: timeout,
      );
    } on MomCloudException catch (error) {
      if (error.statusCode != 401 || error.code != 'invalid_installation_token') {
        rethrow;
      }

      // Heal a revoked/stale installation once. Do not blindly retry provider
      // errors or timeouts because the upstream model may still be working.
      await clearCloudRegistration();
      await ensureRegistered();
      return _post(
        payload,
        authenticated: true,
        endpoint: brainUrl,
        timeout: timeout,
      );
    }
  }

  Future<MomRuntimeConfig> cachedRuntimeConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_runtimeConfigKey);
    if (cached == null || cached.isEmpty) return MomRuntimeConfig.safeDefaults;
    try {
      final decoded = jsonDecode(cached);
      if (decoded is! Map<String, dynamic>) {
        return MomRuntimeConfig.safeDefaults;
      }
      return MomRuntimeConfig.fromJson(decoded, source: 'cache');
    } catch (_) {
      return MomRuntimeConfig.safeDefaults;
    }
  }

  Future<MomRuntimeConfig> runtimeConfig({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    await ensureRegistered(appVersion: '1.1.0');
    final result = await _post(
      {'action': 'runtime_config'},
      authenticated: true,
      timeout: timeout,
    );
    final raw = result['config'];
    if (raw is! Map<String, dynamic>) {
      throw const MomCloudException(
        service: 'mom-sync',
        code: 'invalid_runtime_config',
        message: 'MOM runtime configuration was not a JSON object.',
        retryable: true,
      );
    }
    final config = MomRuntimeConfig.fromJson({
      ...raw,
      'updated_at': result['updated_at'],
    }, source: 'server');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_runtimeConfigKey, jsonEncode(config.toJson()));
    return config;
  }

  Future<MomRuntimeConfig> refreshRuntimeConfig() async {
    final cached = await cachedRuntimeConfig();
    try {
      return await runtimeConfig();
    } catch (_) {
      return cached;
    }
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
      } on MomCloudException catch (error) {
        if (attempt == 0 && error.code == 'device_already_registered') {
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

  Future<void> clearCloudRegistration() async {
    await _secure.delete(key: _installationKey);
    await _secure.delete(key: _tokenKey);
  }

  Future<Map<String, dynamic>> loginStatus() async {
    await ensureRegistered();
    return _post(
      {'action': 'status'},
      authenticated: true,
      endpoint: loginUrl,
    );
  }

  Future<Map<String, dynamic>> createLoginTransferToken() async {
    await ensureRegistered();
    final result = await _post(
      {
        'action': 'create_transfer_token',
        'privacy_acknowledged': true,
      },
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
    if (token.isEmpty) {
      throw const FormatException('Enter a MOM transfer code.');
    }
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
    await _post(
      {'action': 'revoke_transfer_tokens'},
      authenticated: true,
      endpoint: loginUrl,
    );
  }

  Future<List<String>> brainModels() async {
    final result = await _brainPost(
      {'action': 'models'},
      timeout: const Duration(seconds: 30),
    );
    final raw = result['models'];
    if (raw is! List) return const [];
    return raw
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
  }

  Future<BrainProbeResult> brainProbe({String model = ''}) async {
    final timer = Stopwatch()..start();
    final result = await _brainPost(
      {
        'action': 'chat',
        'system_prompt':
            'This is a transport health probe. Reply with one very short acknowledgement.',
        'history': const <Map<String, String>>[],
        'user_text': 'Confirm that the response path is working.',
        'context_mode': 'none',
        'knowledge_context': '',
        'model': model.trim(),
        'temperature': 0,
        'max_history': 2,
      },
      timeout: const Duration(seconds: 45),
    );
    timer.stop();
    final text = result['text'];
    final resolvedModel = result['model'];
    if (text is! String || text.trim().isEmpty || resolvedModel is! String) {
      throw const MomCloudException(
        service: 'mom-brain',
        code: 'unexpected_brain_response',
        message: 'The brain endpoint completed but returned no usable reply.',
        retryable: true,
      );
    }
    return BrainProbeResult(
      model: resolvedModel.trim(),
      latencyMs: timer.elapsedMilliseconds,
    );
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
    final result = await _brainPost(
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
      timeout: const Duration(minutes: 5),
    );
    final text = result['text'];
    final resolvedModel = result['model'];
    if (text is! String || text.trim().isEmpty || resolvedModel is! String) {
      throw const MomCloudException(
        service: 'mom-brain',
        code: 'unexpected_brain_response',
        message: 'MOM brain returned an unexpected response.',
        retryable: true,
      );
    }
    return BrainReply(text: text.trim(), model: resolvedModel.trim());
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

  /// Raw chat is already persisted by ConversationStore on the device.
  /// This compatibility method now sends only locally de-identified USER text
  /// to the research/intelligence endpoint. Assistant turns never leave the
  /// device through the sync path.
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

  /// Persistent raw memories are local-only. This intentionally performs no
  /// cloud write; callers should use ConversationStore/local memory instead.
  Future<void> memory({
    required String content,
    String? sessionId,
    String kind = 'observation',
    String? subject,
    String truthState = 'candidate',
    double confidence = 0.5,
  }) async {}

  /// Cloud transcript history is disabled by design. Raw history is loaded
  /// from ConversationStore on-device.
  Future<Map<String, dynamic>> history({int limit = 100}) async => const {
        'sessions': <dynamic>[],
        'messages': <dynamic>[],
        'local_only': true,
      };

  void close() => _http.close();
}
