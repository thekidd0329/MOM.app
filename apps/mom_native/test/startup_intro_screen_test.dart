import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/startup_intro_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('startup intro store persists completion and preferences', () async {
    final store = StartupIntroStore();

    expect(await store.isComplete(), isFalse);
    expect(await store.savedName(), isEmpty);
    expect(await store.allowsStrongLanguage(), isTrue);

    await store.complete(
      allowStrongLanguage: false,
      name: '  Christian  ',
    );

    expect(await store.isComplete(), isTrue);
    expect(await store.savedName(), 'Christian');
    expect(await store.allowsStrongLanguage(), isFalse);
  });

  testWidgets('first-run intro bypasses the unbundled trailer placeholder',
      (tester) async {
    bool? completedStrongLanguage;
    String? completedName;

    await tester.pumpWidget(
      MaterialApp(
        home: StartupIntroScreen(
          onComplete: ({
            required bool allowStrongLanguage,
            required String name,
          }) async {
            completedStrongLanguage = allowStrongLanguage;
            completedName = name;
          },
        ),
      ),
    );

    expect(find.text('BEFORE MOM MOVES IN'), findsOneWidget);
    expect(find.text('Swearing is fine'), findsOneWidget);
    expect(find.text('Clean pair of underwear mode'), findsOneWidget);

    await tester.tap(find.text('Swearing is fine'));
    await tester.pumpAndSettle();

    expect(find.text('ONE REAL THING'), findsOneWidget);
    expect(find.text('I’m somewhere safe'), findsOneWidget);

    await tester.tap(find.text('I’m somewhere safe'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_circle_outline), findsNothing);
    expect(find.text('Skip intro'), findsNothing);
    expect(find.text('What’s your name?'), findsOneWidget);
    expect(find.text('Meet MOM'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Christian');
    await tester.tap(find.text('Meet MOM'));
    await tester.pump();

    expect(completedStrongLanguage, isTrue);
    expect(completedName, 'Christian');
  });
}
