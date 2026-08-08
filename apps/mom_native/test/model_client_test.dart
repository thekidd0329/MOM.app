import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mom_native/src/config.dart';
import 'package:mom_native/src/model_client.dart';

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
}
