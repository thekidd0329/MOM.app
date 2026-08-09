import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mom_native/src/startup_discovery/discovery_models.dart';
import 'package:mom_native/src/startup_intro_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('MOM personality catalog contains every required personality', () {
    expect(
      MomPersonalityCatalog.all.map((p) => p.id).toSet(),
      equals({
        'mom',
        'mama_bear',
        'drama_mama',
        'granny',
        'gangster',
        'partyholic',
        'soccer_mom',
        'hippie_mom',
        'mima',
        'southern_grace',
        'christ_led',
        'wiccan',
        'stop_it_mahm',
      }),
    );
  });

  test('legacy MOM styles migrate safely', () {
    expect(MomPersonalityCatalog.normalize('balanced'), 'mom');
    expect(MomPersonalityCatalog.normalize('gentle'), 'mom');
    expect(MomPersonalityCatalog.normalize('tough_love'), 'mama_bear');
    expect(MomPersonalityCatalog.normalize('adaptive'), 'mom');
    expect(MomPersonalityCatalog.normalize('unknown'), 'mom');
  });

  test('selected personality is persisted into discovery runtime context', () async {
    final store = StartupIntroStore();
    await store.saveMomStyle('drama_mama');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('mom_style'), 'drama_mama');

    final raw = prefs.getString('mom_startup_discovery_v1');
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['personality_id'], 'drama_mama');
    expect(decoded['personality_prompt'], contains('MOM personality: Drama Mama.'));
    expect(decoded['personality_prompt'], contains('speech recognition'));
  });

  test('discovery serialization preserves personality prompt', () {
    const progress = DiscoveryProgress(
      personalityId: 'mama_bear',
      personalityPrompt: 'MOM personality: Mama Bear.\nProtective and decisive.',
    );

    final decoded = DiscoveryProgress.decode(progress.encode());
    expect(decoded.personalityId, 'mama_bear');
    expect(decoded.personalityPrompt, contains('Mama Bear'));
    expect(decoded.toPromptSummary(), contains('Chosen MOM personality'));
    expect(decoded.toPromptSummary(), contains('Protective and decisive'));
  });

  testWidgets('skipping intro performs the live MOM handoff before name setup',
      (tester) async {
    final spoken = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: StartupIntroScreen(
          onComplete: ({
            required bool allowStrongLanguage,
            required String name,
          }) async {},
          onSpeak: (text) async => spoken.add(text),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Swearing is fine'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I’m somewhere safe'));
    await tester.pumpAndSettle();

    expect(find.text('Skip intro'), findsOneWidget);
    await tester.tap(find.text('Skip intro'));
    await tester.pumpAndSettle();

    expect(
      spoken.last,
      startsWith('Haha, that’s me! Well… My name is 4D4F4DLM1.1.'),
    );
    expect(find.text('First, what should I call you?'), findsOneWidget);
    expect(find.text('Which MOM walked in?'), findsOneWidget);
  });

  test('every personality includes redirect, clarification, and resume behavior', () {
    for (final personality in MomPersonalityCatalog.all) {
      expect(personality.redirectCue.trim(), isNotEmpty, reason: personality.id);
      expect(
        personality.clarificationCue.trim(),
        isNotEmpty,
        reason: personality.id,
      );
      expect(personality.resumeCue.trim(), isNotEmpty, reason: personality.id);
      expect(
        personality.runtimePrompt,
        allOf(
          contains('brief redirect'),
          contains('speech recognition'),
          contains('prior speech was interrupted'),
        ),
        reason: personality.id,
      );
    }
  });
}
