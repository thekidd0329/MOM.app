import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mom_native/src/sync_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('concurrent clients perform only one first-launch registration', () async {
    var registrationCalls = 0;
    final mock = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['action'], 'register');
      registrationCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response(
        jsonEncode({
          'installation_id': '11111111-1111-4111-8111-111111111111',
          'token': 'a' * 64,
        }),
        201,
      );
    });

    final first = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );
    final second = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );
    final third = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );

    await Future.wait([
      first.ensureRegistered(),
      second.ensureRegistered(),
      third.ensureRegistered(),
    ]);

    expect(registrationCalls, 1);
    expect(await first.registered(), isTrue);
    expect(await second.registered(), isTrue);
    expect(await third.registered(), isTrue);
  });

  test('login status uses authenticated mom-login endpoint', () async {
    FlutterSecureStorage.setMockInitialValues({
      'mom_installation_id': '11111111-1111-4111-8111-111111111111',
      'mom_installation_token': 'b' * 64,
    });

    final mock = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/functions/v1/mom-login',
      );
      expect(
        request.headers['x-mom-installation'],
        '11111111-1111-4111-8111-111111111111',
      );
      expect(request.headers['x-mom-token'], 'b' * 64);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {'action': 'status'});
      return http.Response(jsonEncode({'ok': true, 'linked': false}), 200);
    });

    final client = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );

    final status = await client.loginStatus();
    expect(status['linked'], isFalse);
    client.close();
  });

  test('transfer code creation always includes privacy acknowledgement', () async {
    FlutterSecureStorage.setMockInitialValues({
      'mom_installation_id': '22222222-2222-4222-8222-222222222222',
      'mom_installation_token': 'c' * 64,
    });

    final mock = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/functions/v1/mom-login',
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['action'], 'create_transfer_token');
      expect(body['privacy_acknowledged'], isTrue);
      return http.Response(
        jsonEncode({
          'ok': true,
          'transfer_token': 'MOM-2345-6789-ABCD-EFGH-JKMN-PQRS',
          'expires_at': '2026-08-08T23:59:00Z',
        }),
        201,
      );
    });

    final client = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );

    final result = await client.createLoginTransferToken();
    expect(result['transfer_token'], startsWith('MOM-'));
    client.close();
  });

  test('transfer code redemption trims input and acknowledges privacy', () async {
    FlutterSecureStorage.setMockInitialValues({
      'mom_installation_id': '33333333-3333-4333-8333-333333333333',
      'mom_installation_token': 'd' * 64,
    });

    final mock = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://example.test/functions/v1/mom-login',
      );
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['action'], 'redeem_transfer_token');
      expect(body['transfer_token'], 'MOM-2345-6789');
      expect(body['privacy_acknowledged'], isTrue);
      return http.Response(jsonEncode({'ok': true, 'linked': true}), 200);
    });

    final client = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );

    final result = await client.redeemLoginTransferToken('  MOM-2345-6789  ');
    expect(result['linked'], isTrue);
    client.close();
  });

  test('runtime config authenticates, validates, and caches server values',
      () async {
    FlutterSecureStorage.setMockInitialValues({
      'mom_installation_id': '88888888-8888-4888-8888-888888888888',
      'mom_installation_token': 'i' * 64,
    });

    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      expect(request.url.path.endsWith('/mom-sync'), isTrue);
      expect(request.headers['x-mom-installation'],
          '88888888-8888-4888-8888-888888888888');
      expect(request.headers['x-mom-token'], 'i' * 64);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body, {'action': 'runtime_config'});
      return http.Response(
        jsonEncode({
          'ok': true,
          'config': {
            'schema_version': 1,
            'release': '1.1.0',
            'temperature': 0.61,
            'max_history': 12,
            'request_timeout_seconds': 240,
            'raw_memory_location': 'device_only',
            'cloud_raw_chat_storage': false,
            'bundled_runtime_prompt_required': false,
            'bundled_repository_knowledge_required': false,
          },
          'updated_at': '2026-08-10T12:00:00Z',
        }),
        200,
      );
    });

    final client = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );
    final live = await client.runtimeConfig();
    expect(live.source, 'server');
    expect(live.temperature, 0.61);
    expect(live.maxHistory, 12);
    expect(live.rawMemoryLocation, 'device_only');
    expect(live.cloudRawChatStorage, isFalse);

    final cached = await client.cachedRuntimeConfig();
    expect(cached.source, 'cache');
    expect(cached.temperature, 0.61);
    expect(cached.maxHistory, 12);
    expect(calls, 1);
    client.close();
  });

  test('runtime config falls back to safe cache while offline', () async {
    SharedPreferences.setMockInitialValues({
      'mom_runtime_config_v1': jsonEncode({
        'schema_version': 1,
        'release': '1.1.0',
        'temperature': 0.55,
        'max_history': 10,
        'request_timeout_seconds': 180,
        'raw_memory_location': 'device_only',
        'cloud_raw_chat_storage': false,
        'bundled_runtime_prompt_required': false,
        'bundled_repository_knowledge_required': false,
      }),
    });
    FlutterSecureStorage.setMockInitialValues({
      'mom_installation_id': '99999999-9999-4999-8999-999999999999',
      'mom_installation_token': 'j' * 64,
    });

    final mock = MockClient((request) async {
      throw http.ClientException('offline');
    });
    final client = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );

    final config = await client.refreshRuntimeConfig();
    expect(config.source, 'cache');
    expect(config.temperature, 0.55);
    expect(config.maxHistory, 10);
    client.close();
  });

  test('provider failures preserve provider stage and status', () async {
    FlutterSecureStorage.setMockInitialValues({
      'mom_installation_id': '44444444-4444-4444-8444-444444444444',
      'mom_installation_token': 'e' * 64,
    });

    final mock = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'error': 'provider_error',
          'provider_status': 503,
          'detail': {'message': 'provider unavailable'},
        }),
        502,
      );
    });

    final client = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );

    await expectLater(
      client.brainChat(
        systemPrompt: 'MOM',
        history: const [],
        userText: 'hello',
      ),
      throwsA(
        isA<MomCloudException>()
            .having((e) => e.code, 'code', 'provider_error')
            .having((e) => e.statusCode, 'statusCode', 502)
            .having((e) => e.providerStatus, 'providerStatus', 503)
            .having((e) => e.retryable, 'retryable', isTrue),
      ),
    );
    client.close();
  });

  test('stale brain identity re-registers once and retries chat once', () async {
    SharedPreferences.setMockInitialValues({
      'mom_device_id': 'mom-device-recovery-test',
    });
    FlutterSecureStorage.setMockInitialValues({
      'mom_installation_id': '55555555-5555-4555-8555-555555555555',
      'mom_installation_token': 'f' * 64,
    });

    var brainCalls = 0;
    var registrationCalls = 0;
    final mock = MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.url.path.endsWith('/mom-sync')) {
        registrationCalls++;
        expect(body['action'], 'register');
        return http.Response(
          jsonEncode({
            'installation_id': '66666666-6666-4666-8666-666666666666',
            'token': 'g' * 64,
          }),
          201,
        );
      }

      expect(request.url.path.endsWith('/mom-brain'), isTrue);
      brainCalls++;
      if (brainCalls == 1) {
        return http.Response(
          jsonEncode({'error': 'invalid_installation_token'}),
          401,
        );
      }
      expect(
        request.headers['x-mom-installation'],
        '66666666-6666-4666-8666-666666666666',
      );
      expect(request.headers['x-mom-token'], 'g' * 64);
      return http.Response(
        jsonEncode({'text': 'back online', 'model': 'mom-test-model'}),
        200,
      );
    });

    final client = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );

    final reply = await client.brainChat(
      systemPrompt: 'MOM',
      history: const [],
      userText: 'hello',
    );
    expect(reply.text, 'back online');
    expect(brainCalls, 2);
    expect(registrationCalls, 1);
    client.close();
  });

  test('brain probe proves a context-free provider completion', () async {
    FlutterSecureStorage.setMockInitialValues({
      'mom_installation_id': '77777777-7777-4777-8777-777777777777',
      'mom_installation_token': 'h' * 64,
    });

    final mock = MockClient((request) async {
      expect(request.url.path.endsWith('/mom-brain'), isTrue);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['action'], 'chat');
      expect(body['context_mode'], 'none');
      expect(body['history'], isEmpty);
      expect(body['temperature'], 0);
      return http.Response(
        jsonEncode({'text': 'ok', 'model': 'mom-test-model'}),
        200,
      );
    });

    final client = MomSyncClient(
      syncUrl: 'https://example.test/functions/v1/mom-sync',
      secureStorage: const FlutterSecureStorage(),
      httpClient: mock,
    );

    final probe = await client.brainProbe();
    expect(probe.model, 'mom-test-model');
    expect(probe.latencyMs, greaterThanOrEqualTo(0));
    client.close();
  });
}
