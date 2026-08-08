import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mom_native/src/local_store.dart';
import 'package:mom_native/src/mic_status.dart';
import 'package:mom_native/src/mom_home_screen.dart';
import 'package:mom_native/src/startup_discovery/discovery_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('first launch starts with disclosure and profanity enabled',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StartupDiscoveryScreen(onComplete: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Before we meet.'), findsOneWidget);
    expect(
      find.text('Swearing & potentially offensive content'),
      findsOneWidget,
    );

    final toggle = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(toggle.value, isTrue);
  });

  testWidgets('turning profanity off shows MOM reaction', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StartupDiscoveryScreen(onComplete: (_) async {}),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(find.text("Awww, you're no fun. Are you sure??"), findsOneWidget);
  });

  testWidgets('home has no chat field until keyboard control opens it',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MomHomeScreen(
          turns: const <ChatTurn>[],
          busy: false,
          status: 'online',
          microphone: const MomMicrophoneStatus.unknown(),
          onSend: (_) async {},
          onSettings: () {},
          onDiagnostics: () {},
          onProbeMicrophone: (_) async {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Listening...'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byTooltip('Text MOM'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Text MOM…'), findsOneWidget);
  });
}
