import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brain failures are visible, audible, and stage-coded', () {
    final main = File('lib/main.dart').readAsStringSync();

    expect(main, contains('content: modelFailure.userMessage'));
    expect(
      main,
      contains('_voice.speak(modelFailure.userMessage).catchError((_) {})'),
    );
    expect(main, contains("'model_error_code': modelFailure.code"));
    expect(main, contains("'model_error_stage': modelFailure.stage"));
    expect(main, contains("'retryable': modelFailure.retryable"));
  });
}
