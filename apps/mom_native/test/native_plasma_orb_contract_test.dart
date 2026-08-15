import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/local_store.dart';
import 'package:mom_native/src/mic_status.dart';
import 'package:mom_native/src/mom_home_screen.dart';
import 'package:mom_native/src/native_plasma_orb.dart';

Widget _home({
  bool busy = false,
  bool listening = false,
  String status = 'online',
}) {
  return MaterialApp(
    home: MomHomeScreen(
      turns: const <ChatTurn>[],
      busy: busy,
      listening: listening,
      status: status,
      microphone: const MomMicrophoneStatus.unknown(),
      onSend: (_) async {},
      onSettings: () {},
      onDiagnostics: () {},
      onProbeMicrophone: (_) async {},
      onMicTap: () async {},
    ),
  );
}

PlasmaOrbState _renderedOrbState(WidgetTester tester) {
  return tester.widget<NativePlasmaOrb>(find.byType(NativePlasmaOrb)).state;
}

void main() {
  testWidgets(
    'home maps every MOM runtime condition to the right orb state',
    (tester) async {
      await tester.pumpWidget(_home());
      expect(_renderedOrbState(tester), PlasmaOrbState.idle);

      await tester.pumpWidget(_home(busy: true));
      expect(_renderedOrbState(tester), PlasmaOrbState.thinking);

      // Speaking must win over the generic busy flag used by voice playback.
      await tester.pumpWidget(_home(busy: true, status: 'Speaking...'));
      expect(_renderedOrbState(tester), PlasmaOrbState.talking);

      for (final status in <String>[
        'Voice error · text still works',
        'offline',
        'unavailable',
      ]) {
        await tester.pumpWidget(_home(status: status));
        expect(_renderedOrbState(tester), PlasmaOrbState.error);
      }

      // Listening is the immediate user-facing state and has highest priority.
      await tester.pumpWidget(
        _home(
          busy: true,
          listening: true,
          status: 'Voice error · text still works',
        ),
      );
      expect(_renderedOrbState(tester), PlasmaOrbState.listening);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'non-Android platforms retain the approved static fallback',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        const fallbackKey = Key('approved-orb-fallback');
        await tester.pumpWidget(
          const MaterialApp(
            home: NativePlasmaOrb(
              state: PlasmaOrbState.idle,
              fallback: SizedBox(key: fallbackKey),
            ),
          ),
        );

        expect(find.byKey(fallbackKey), findsOneWidget);
        expect(find.byType(AndroidView), findsNothing);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  test('source contract keeps artwork, bridge, registration, and lifecycle',
      () {
    final home = File('lib/src/mom_home_screen.dart').readAsStringSync();
    final bridge = File('lib/src/native_plasma_orb.dart').readAsStringSync();
    final native = File(
      'android/app/src/main/kotlin/app/mom/mom_native/PlasmaOrbView.kt',
    ).readAsStringSync();
    final activity = File(
      'android/app/src/main/kotlin/app/mom/mom_native/MainActivity.kt',
    ).readAsStringSync();

    expect(home, contains('NativePlasmaOrb('));
    expect(home, contains('PlasmaOrbState.listening'));
    expect(home, contains('PlasmaOrbState.thinking'));
    expect(home, contains('PlasmaOrbState.talking'));
    expect(home, contains('PlasmaOrbState.error'));
    expect(home, contains('PlasmaOrbState.idle'));

    expect(bridge, contains("viewType: 'mom/plasma_orb'"));
    expect(bridge, contains("MethodChannel('mom/plasma_orb/\$id')"));
    expect(bridge, contains('String get wireName => name'));
    expect(bridge, contains("invokeMethod<void>('setState'"));
    expect(bridge, contains("'state': widget.state.wireName"));
    expect(
      "'state': widget.state.wireName".allMatches(bridge),
      hasLength(2),
    );
    expect(bridge, contains('creationParamsCodec'));
    expect(bridge, contains('return widget.fallback'));
    expect(bridge, contains('oldWidget.state != widget.state'));

    expect(native, contains('APPROVED_ORB_ASSET'));
    expect(
      native,
      contains('photopea_background_remover_1786650252951.png'),
    );
    expect(native, contains('IDLE("idle"'));
    expect(native, contains('LISTENING("listening"'));
    expect(native, contains('THINKING("thinking"'));
    expect(native, contains('TALKING("talking"'));
    expect(native, contains('ERROR("error"'));
    expect(native, contains('canvas.drawBitmap(artwork'));
    expect(native, contains('repeat(orbState.branches)'));
    expect(native, contains('repeat(orbState.edgeArcs)'));
    expect(
      native,
      contains('if (running) postInvalidateDelayed(orbState.frameDelayMs)'),
    );
    expect(native, contains('override fun onAttachedToWindow()'));
    expect(native, contains('override fun onDetachedFromWindow()'));

    expect(activity, contains('PlasmaOrbViewFactory('));
    expect(activity, contains('registry.registerViewFactory('));
    expect(activity, contains('flutterEngine.dartExecutor.binaryMessenger'));
    expect(
      activity,
      contains('MethodChannel(messenger, "mom/plasma_orb/\$viewId")'),
    );
    expect(activity, contains('setOrbState(initialState)'));
    expect(activity, contains('orb.setOrbState('));
    expect(activity, contains('channel.setMethodCallHandler(null)'));
    expect(activity, contains('orb.dispose()'));
  });
}
