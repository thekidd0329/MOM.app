import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mom_native/src/config.dart';
import 'package:mom_native/src/model_client.dart';
import 'package:mom_native/src/sync_client.dart';

MomConfig config() => MomConfig(
      syncUrl: MomConfig.defaultSyncUrl,
      modelApiBase: 'https://model.example/v1',
      modelName: '',
      modelApiKey: 'test-secret',
      useLocalLlama: true,
      modelsDir: '/tmp',
      repoRoot: '/tmp',
      cloudChatSync: true,
      productTelemetry: true,
      temperature: 0.72,
      maxHistory: 30,
    );

void main() {
  test('local model discovery uses the standard models endpoint', () async {
    final mock = MockClient((request) async {
      expect(request.url.toString(), 'https://model.example/v1/models');
      expect(request.headers['authorization'], 'Bearer test-secret');
      return http.Response(jsonEncode({'data': [{'id': 'mom-test-model'}]}), 200);
    });
    final client = ModelClient(config(), client: mock);
    expect(await client.resolveModel(), 'mom-test-model');
    client.close();
  });

  test('local chat sends system, knowledge, and user content', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      if (request.url.path.endsWith('/models')) {
        return http.Response(jsonEncode({'data': [{'id': 'mom-test-model'}]}), 200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'mom-test-model');
      final messages = body['messages'] as List;
      expect('${messages.first['content']}', contains('Relevant MOM repository knowledge'));
      expect('${messages.last['content']}', 'hello mom');
      return http.Response(jsonEncode({
        'choices': [
          {'message': {'content': 'hello back'}}
        ]
      }), 200);
    });
    final client = ModelClient(config(), client: mock);
    final reply = await client.chat(
      systemPrompt: 'You are MOM.',
      history: const [],
      userText: 'hello mom',
      knowledgeContext: 'SOURCE: docs/test.md\nimportant context',
    );
    expect(reply.text, 'hello back');
    expect(calls, 2);
    client.close();
  });

  test('local probe proves model discovery plus a real completion', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      if (request.url.path.endsWith('/models')) {
        return http.Response(jsonEncode({'data': [{'id': 'mom-test-model'}]}), 200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final messages = body['messages'] as List;
      expect('${messages.last['content']}', contains('local response path'));
      return http.Response(jsonEncode({
        'choices': [
          {'message': {'content': 'ok'}}
        ]
      }), 200);
    });

    final client = ModelClient(config(), client: mock);
    final probe = await client.probe();
    expect(probe.model, 'mom-test-model');
    expect(probe.route, 'local→provider→response');
    expect(probe.latencyMs, greaterThanOrEqualTo(0));
    expect(calls, 2);
    client.close();
  });

  test('provider rate limit is classified separately from server failure', () {
    const error = MomCloudException(
      service: 'mom-brain',
      code: 'provider_error',
      message: 'busy',
      statusCode: 502,
      providerStatus: 429,
      retryable: true,
    );
    final failure = classifyModelFailure(error);
    expect(failure.kind, ModelFailureKind.providerBusy);
    expect(failure.stage, 'model_provider');
    expect(failure.providerStatus, 429);
    expect(failure.retryable, isTrue);
  });

  test('depleted provider credits are a service-side capacity failure', () {
    const error = MomCloudException(
      service: 'mom-brain',
      code: 'provider_error',
      message: 'monthly credits depleted',
      statusCode: 502,
      providerStatus: 402,
      retryable: true,
    );
    final failure = classifyModelFailure(error);
    expect(failure.kind, ModelFailureKind.provider);
    expect(failure.code, 'provider_capacity_exhausted');
    expect(failure.stage, 'model_provider_capacity');
    expect(failure.providerStatus, 402);
    expect(failure.retryable, isFalse);
    expect(failure.userMessage, contains('service-side fix'));
    expect(failure.userMessage, contains('not anything on your phone'));
  });

  test('invalid installation is classified as identity failure', () {
    const error = MomCloudException(
      service: 'mom-brain',
      code: 'invalid_installation_token',
      message: 'nope',
      statusCode: 401,
    );
    final failure = classifyModelFailure(error);
    expect(failure.kind, ModelFailureKind.identity);
    expect(failure.stage, 'installation_identity');
  });

  test('malformed successful cloud response is a response-stage failure', () {
    const error = MomCloudException(
      service: 'mom-brain',
      code: 'invalid_server_response',
      message: 'not json',
      statusCode: 200,
      retryable: true,
    );
    final failure = classifyModelFailure(error);
    expect(failure.kind, ModelFailureKind.response);
    expect(failure.stage, 'mom-brain');
  });
}
