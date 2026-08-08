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
}
