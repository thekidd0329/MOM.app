import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/mic_status.dart';
import 'package:mom_native/src/mom_home_screen.dart';

void main() {
  testWidgets('MOM home launches with the trademark electric orb',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: MomHomeScreen(
          turns: const [],
          busy: false,
          listening: false,
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

    expect(find.text('Tap the mic'), findsOneWidget);
    expect(find.byTooltip('Use microphone'), findsOneWidget);
    expect(find.byTooltip('Text MOM'), findsOneWidget);

    final paints = tester.widgetList<CustomPaint>(find.byType(CustomPaint));
    expect(
      paints.any(
        (paint) => paint.painter?.runtimeType.toString() == '_ElectricOrbPainter',
      ),
      isTrue,
      reason: 'The trademark MOM electric orb painter must remain on the phone home surface.',
    );
  });
}
