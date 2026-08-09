import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mic delegates to the real listening flow', () {
    final home = File('lib/src/mom_home_screen.dart').readAsStringSync();
    final app = File('lib/main.dart').readAsStringSync();

    expect(home, contains('required this.onMicTap'));
    expect(home, contains('await widget.onMicTap()'));
    expect(app, contains('Future<void> _toggleListening() async'));
    expect(app, contains('await _probeMicrophone(true)'));
    expect(app, contains('await _voice.listen('));
    expect(app, contains('onFinal: (text)'));
    expect(app, contains('unawaited(_send(text))'));
    expect(home, isNot(contains('My ears are still being constructed.')));
  });

  test('keyboard fallback focus lifecycle remains balanced', () {
    final source = File('lib/src/mom_home_screen.dart').readAsStringSync();

    expect(source, contains('final FocusNode _textFocus = FocusNode()'));
    expect(source, contains('focusNode: _textFocus'));
    expect(source, contains('_textFocus.unfocus()'));
    expect(source, contains('_textFocus.dispose()'));
  });
}
