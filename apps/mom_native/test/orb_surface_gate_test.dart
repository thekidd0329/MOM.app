import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/local_store.dart';
import 'package:mom_native/src/mic_status.dart';
import 'package:mom_native/src/mom_home_screen.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    required bool listening,
    bool busy = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: MomHomeScreen(
          turns: [
            ChatTurn(
              sessionId: 'ui-gate',
              role: 'assistant',
              content: 'MOM caption stays visible.',
              createdAt: DateTime(2026, 8, 9),
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

  tearDown(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('MOM home launches with the trademark electric orb',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, listening: false);

    expect(find.text('Tap the mic'), findsOneWidget);
    expect(find.byTooltip('Use microphone'), findsOneWidget);
    expect(find.byTooltip('Text MOM'), findsOneWidget);
    expect(find.text('MOM caption stays visible.'), findsOneWidget);

    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(
      paints.any(
        (paint) => paint.painter?.runtimeType.toString() == '_ElectricOrbPainter',
      ),
      isTrue,
      reason:
          'The trademark MOM electric orb painter must remain on the phone home surface.',
    );
  });

  testWidgets('MOM caption remains visible while listening', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, listening: true);

    expect(find.text('Listening...'), findsOneWidget);
    expect(find.text('MOM caption stays visible.'), findsOneWidget);
  });

  testWidgets('MOM caption remains visible while thinking', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, listening: false, busy: true);

    expect(find.text('Thinking...'), findsOneWidget);
    expect(find.text('MOM caption stays visible.'), findsOneWidget);
  });

  testWidgets('MOM caption remains visible when text input is opened',
      (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pumpHome(tester, listening: false);

    await tester.tap(find.byTooltip('Text MOM'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('MOM caption stays visible.'), findsOneWidget);
  });
}
