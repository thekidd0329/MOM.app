import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/config.dart';
import 'package:mom_native/src/mic_status.dart';
import 'package:mom_native/src/mom_build_info.dart';
import 'package:mom_native/src/mom_home_screen.dart';
import 'package:mom_native/src/mom_launch_screen.dart';
import 'package:mom_native/src/mom_settings_screen.dart';
import 'package:mom_native/src/sync_client.dart';

void main() {
  testWidgets('beta home keeps the launch controls and current version', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: MomHomeScreen(
          turns: const [],
          busy: false,
          listening: false,
          status: 'online',
          microphone: const MomMicrophoneStatus.unknown(),
          onSend: (_) async {},
          onSettings: () {},
          onDiagnostics: () {},
          onProbeMicrophone: (_) async {},
          onMicTap: () async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text(MomBuildInfo.displayVersion), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.byIcon(Icons.keyboard), findsOneWidget);
    expect(find.text('Tap the mic'), findsOneWidget);
  });

  testWidgets('returning-user boot carries the MOM app lockup on a phone', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      const MaterialApp(home: MomLaunchScreen(status: 'starting')),
    );
    await tester.pump(const Duration(milliseconds: 40));

    expect(find.text('M'), findsNWidgets(2));
    expect(find.text('app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings exposes the UI-first product controls', (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final sync = MomSyncClient(syncUrl: MomConfig.defaultSyncUrl);
    addTearDown(sync.close);
    final config = MomConfig(
      syncUrl: MomConfig.defaultSyncUrl,
      modelApiBase: MomConfig.defaultBrainUrl,
      modelName: '',
      modelApiKey: '',
      useLocalLlama: false,
      modelsDir: 'models',
      repoRoot: '',
      cloudChatSync: true,
      productTelemetry: true,
      temperature: 0.72,
      maxHistory: 30,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: MomSettingsScreen(initial: config, sync: sync),
      ),
    );
    await tester.pump();

    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('Electrical effects'), findsOneWidget);
    expect(find.text('VOICE & LISTENING'), findsOneWidget);
    expect(find.text('Auto-listen'), findsOneWidget);
    expect(find.text('On-screen captions'), findsOneWidget);
    expect(find.text('MEMORY & PRIVACY'), findsOneWidget);
    expect(find.text(MomBuildInfo.fullVersion), findsWidgets);
  });
}
