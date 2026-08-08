import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('beta mic remains a safe keyboard dictation handoff', () {
    final source = File('lib/src/mom_home_screen.dart').readAsStringSync();

    expect(source, contains('onProbeMicrophone(false)'));
    expect(source, isNot(contains('onProbeMicrophone(true)')));
    expect(source, contains('My ears are still being constructed.'));
    expect(source, contains('setState(() => _textMode = true)'));
    expect(source, contains('_textFocus.requestFocus()'));
    expect(
      source,
      contains('Go ahead and use your mic on your keyboard right here.'),
    );
  });

  test('keyboard handoff focus lifecycle remains balanced', () {
    final source = File('lib/src/mom_home_screen.dart').readAsStringSync();

    expect(source, contains('final FocusNode _textFocus = FocusNode()'));
    expect(source, contains('focusNode: _textFocus'));
    expect(source, contains('_textFocus.unfocus()'));
    expect(source, contains('_textFocus.dispose()'));
  });
}
