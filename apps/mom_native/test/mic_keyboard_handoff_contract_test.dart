import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mic routes through the runtime speech handler', () {
    final source = File('lib/src/mom_home_screen.dart').readAsStringSync();

    expect(source, contains('required this.onMicTap'));
    expect(source, contains('final Future<void> Function() onMicTap'));
    expect(source, contains('widget.onMicTap()'));
    expect(source, contains('onPressed: _handleMicTap'));
    expect(source, isNot(contains('My ears are still being constructed.')));
    expect(
      source,
      isNot(contains('Go ahead and use your mic on your keyboard right here.')),
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
