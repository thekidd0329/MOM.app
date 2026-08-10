import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/local_store.dart';
import 'package:mom_native/src/mic_status.dart';
import 'package:mom_native/src/mom_home_screen.dart';

void main() {
  const reply = 'I am still right here with you.';

  Future<void> pumpHome(
    WidgetTester tester, {
    required bool busy,
    required bool listening,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: MomHomeScreen(
          turns: [
            ChatTurn(
              sessionId: 'caption-gate',
              role: 'assistant',
              content: reply,
              createdAt: DateTime.fromMillisecondsSinceEpoch(1),
              metadata: const {},
            ),
          ],
          busy: busy,
          listening: listening,
          status: 'online',
          microphone: const MomMicrophoneStatus(
            state: MomMicrophoneState.available,
            permissionGranted: true,
            inputCount: 1,
          ),
          onSend: (_) async {},
          onSettings: () {},
          onDiagnostics: () {},
          onProbeMicrophone: (_) async {},
          onMicTap: () async {},
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('MOM caption stays visible while idle, listening, and thinking',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHome(tester, busy: false, listening: false);
    expect(find.text(reply), findsOneWidget);

    await pumpHome(tester, busy: false, listening: true);
    expect(find.text('Listening...'), findsOneWidget);
    expect(find.text(reply), findsOneWidget);

    await pumpHome(tester, busy: true, listening: false);
    expect(find.text('Thinking...'), findsOneWidget);
    expect(find.text(reply), findsOneWidget);
  });

  testWidgets('MOM caption stays visible when the text composer is open',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await pumpHome(tester, busy: false, listening: false);
    expect(find.text(reply), findsOneWidget);

    await tester.tap(find.byTooltip('Text MOM'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text(reply), findsOneWidget);
  });
}
