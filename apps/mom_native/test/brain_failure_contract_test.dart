import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brain failures stay visible and stage-coded without silent voice errors', () {
    final main = File('lib/main.dart').readAsStringSync();

    expect(main, contains('content: modelFailure.userMessage'));
    expect(main, contains("'model_error_code': modelFailure.code"));
    expect(main, contains("'model_error_stage': modelFailure.stage"));
    expect(main, contains("'retryable': modelFailure.retryable"));
    expect(main, contains("'voice_error'"));
    expect(main, contains('Voice error · text still works'));
    expect(main, isNot(contains('catchError((_) {})')));
  });
}
