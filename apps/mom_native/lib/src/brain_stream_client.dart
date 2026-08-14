import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'sync_client.dart';
import 'voice_continuity.dart';

class MomBrainStreamClient {
  MomBrainStreamClient({
    required this.syncUrl,
    required MomSyncClient syncClient,
    FlutterSecureStorage? secureStorage,
    http.Client? httpClient,
  })  : _sync = syncClient,
        _secure = secureStorage ?? const FlutterSecureStorage(),
        _http = httpClient ?? http.Client();

  final String syncUrl;
  final MomSyncClient _sync;
  final FlutterSecureStorage _secure;
  final http.Client _http;

  static const _installationKey = 'mom_installation_id';
  static const _tokenKey = 'mom_installation_token';

  Uri get _target {
    final uri = Uri.parse(syncUrl);
    final segments = uri.pathSegments.toList();
    if (segments.isNotEmpty && segments.last == 'mom-sync') {
      segments[segments.length - 1] = 'mom-brain-stream';
    } else if (segments.isEmpty || segments.last != 'mom-brain-stream') {
      segments.add('mom-brain-stream');
    }
    return uri.replace(pathSegments: segments);
  }

  Future<Map<String, String>> _headers() async {
    final installation = await _secure.read(key: _installationKey);
    final token = await _secure.read(key: _tokenKey);
    if (installation == null || token == null) {
      throw const MomCloudException(
        service: 'mom-brain-stream',
        code: 'installation_not_registered',
        message: 'MOM streaming identity is not registered.',
      );
    }
    return {
      'content-type': 'application/json',
      'accept': 'text/event-stream',
      'x-mom-installation': installation,
      'x-mom-token': token,
    };
  }

  Future<BrainReply> chat({
    required List<Map<String, String>> history,
    required String userText,
    required void Function(String delta) onDelta,
    double temperature = 0.72,
    int maxHistory = 8,
  }) async {
    await _sync.ensureRegistered();

    final effectiveHistory = List<Map<String, String>>.from(history);
    final interrupted = MomVoiceContinuity.consume();
    if (interrupted != null) {
      effectiveHistory.add({
        'role': 'assistant',
        'content': interrupted.toAssistantHistoryContext(),
      });
    }

    try {
      return await _chatOnce(
        history: effectiveHistory,
        userText: userText,
        onDelta: onDelta,
        temperature: temperature,
        maxHistory: maxHistory,
      );
    } on MomCloudException catch (error) {
      if (error.statusCode != 401 || error.code != 'invalid_installation_token') {
        rethrow;
      }
      await _sync.clearCloudRegistration();
      await _sync.ensureRegistered();
      return _chatOnce(
        history: effectiveHistory,
        userText: userText,
        onDelta: onDelta,
        temperature: temperature,
        maxHistory: maxHistory,
      );
    }
  }

  Future<BrainReply> _chatOnce({
    required List<Map<String, String>> history,
    required String userText,
    required void Function(String delta) onDelta,
    required double temperature,
    required int maxHistory,
  }) async {
    final request = http.Request('POST', _target)
      ..headers.addAll(await _headers())
      ..body = jsonEncode({
        'action': 'chat_stream',
        'input_transport': 'text',
        'audio_uploaded': false,
        'history': history,
        'user_text': userText,
        'temperature': temperature,
        'max_history': maxHistory.clamp(2, 8),
      });

    late http.StreamedResponse response;
    try {
      response = await _http
          .send(request)
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw const MomCloudException(
        service: 'mom-brain-stream',
        code: 'request_timeout',
        message: 'The streaming brain did not open in time.',
        retryable: true,
      );
    } on SocketException catch (error) {
      throw MomCloudException(
        service: 'mom-brain-stream',
        code: 'network_unreachable',
        message: error.message,
        retryable: true,
      );
    } on http.ClientException catch (error) {
      throw MomCloudException(
        service: 'mom-brain-stream',
        code: 'network_request_failed',
        message: error.message,
        retryable: true,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.bytesToString();
      var code = 'http_${response.statusCode}';
      int? providerStatus;
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) {
          code = '${decoded['error'] ?? code}';
          if (decoded['provider_status'] is num) {
            providerStatus = (decoded['provider_status'] as num).round();
          }
        }
      } catch (_) {}
      throw MomCloudException(
        service: 'mom-brain-stream',
        code: code,
        message: code,
        statusCode: response.statusCode,
        providerStatus: providerStatus,
        retryable: response.statusCode == 408 ||
            response.statusCode == 429 ||
            response.statusCode >= 500,
      );
    }

    final text = StringBuffer();
    var model = '';
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

      Map<String, dynamic> decoded;
      try {
        final value = jsonDecode(payload);
        if (value is! Map<String, dynamic>) continue;
        decoded = value;
      } catch (_) {
        continue;
      }

      if (decoded['type'] == 'meta' && decoded['model'] is String) {
        model = (decoded['model'] as String).trim();
        continue;
      }
      if (decoded['type'] == 'delta' && decoded['delta'] is String) {
        final delta = decoded['delta'] as String;
        if (delta.isNotEmpty) {
          text.write(delta);
          onDelta(delta);
        }
        continue;
      }
      if (decoded['type'] == 'error') {
        throw const MomCloudException(
          service: 'mom-brain-stream',
          code: 'stream_failed',
          message: 'The provider stream ended with an error.',
          retryable: true,
        );
      }
    }

    final reply = text.toString().trim();
    if (reply.isEmpty) {
      throw const MomCloudException(
        service: 'mom-brain-stream',
        code: 'unexpected_brain_response',
        message: 'The streaming brain returned no usable text.',
        retryable: true,
      );
    }
    return BrainReply(text: reply, model: model);
  }

  void close() => _http.close();
}
