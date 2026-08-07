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
}
