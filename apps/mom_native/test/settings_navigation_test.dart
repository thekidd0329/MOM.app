import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/local_store.dart';
import 'package:mom_native/src/mic_status.dart';
import 'package:mom_native/src/mom_home_screen.dart';

void main() {
  testWidgets('Settings button opens the settings route', (tester) async {
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: MomHomeScreen(
          turns: const <ChatTurn>[],
          busy: false,
          listening: false,
          status: 'online',
          microphone: const MomMicrophoneStatus.unknown(),
          onSend: (_) async {},
          onSettings: () {
            navigatorKey.currentState!.push<void>(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('MOM settings')),
                ),
              ),
            );
          },
          onDiagnostics: () {},
          onProbeMicrophone: (_) async {},
          onMicTap: () async {},
        ),
      ),
    );

    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('MOM settings'), findsOneWidget);
  });
}
