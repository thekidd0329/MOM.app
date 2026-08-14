import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plasma orb keeps the approved art and reacts to MOM state', () {
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

    expect(bridge, contains("viewType: 'mom/plasma_orb'"));
    expect(bridge, contains("invokeMethod<void>('setState'"));
    expect(bridge, contains('creationParamsCodec'));

    expect(native, contains('APPROVED_ORB_ASSET'));
    expect(
      native,
      contains('photopea_background_remover_1786650252951.png'),
    );
    expect(native, contains('IDLE("idle"'));
    expect(native, contains('LISTENING("listening"'));
    expect(native, contains('THINKING("thinking"'));
    expect(native, contains('TALKING("talking"'));
    expect(native, contains('postInvalidateDelayed(orbState.frameDelayMs)'));

    expect(activity, contains('PlasmaOrbViewFactory('));
    expect(activity, contains('flutterEngine.dartExecutor.binaryMessenger'));
    expect(activity, contains('MethodChannel(messenger, "mom/plasma_orb/'));
    expect(activity, contains('orb.setOrbState('));
  });
}
