import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/config.dart';

MomConfig baseConfig() => MomConfig(
      syncUrl: MomConfig.defaultSyncUrl,
      modelApiBase: 'http://127.0.0.1:8080/v1',
      modelName: '',
      modelApiKey: '',
      useLocalLlama: false,
      modelsDir: '/tmp',
      repoRoot: '/tmp',
      cloudChatSync: true,
      productTelemetry: true,
      temperature: 0.72,
      maxHistory: 30,
    );

void main() {
  test('default desktop variables contain no fatal validation errors', () {
    final issues = baseConfig().validate();
    expect(issues.where((i) => i.fatal), isEmpty);
  });

  test('bad sync url is fatal', () {
    final config = baseConfig()..syncUrl = 'not a url';
    expect(config.validate().any((i) => i.key == 'syncUrl' && i.fatal), isTrue);
  });

  test('temperature outside model range is fatal', () {
    final config = baseConfig()..temperature = 3.0;
    expect(config.validate().any((i) => i.key == 'temperature' && i.fatal), isTrue);
  });

  test('history window is bounded', () {
    final config = baseConfig()..maxHistory = 0;
    expect(config.validate().any((i) => i.key == 'maxHistory' && i.fatal), isTrue);
  });
}
