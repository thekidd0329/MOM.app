import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/startup_intro_screen.dart';

void main() {
  testWidgets('Meet MOM only completes once while save is pending', (tester) async {
    final gate = Completer<void>();
    var calls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StartupIntroScreen(
          onComplete: ({
            required bool allowStrongLanguage,
            required String name,
          }) async {
            calls += 1;
            await gate.future;
          },
        ),
      ),
    );

    await tester.tap(find.text('Swearing is fine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I’m somewhere safe'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Chris');
    await tester.tap(find.text('Meet MOM'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
  });
}
