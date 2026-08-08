import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bundled runtime prompt matches canonical MOM prompt', () {
    final canonical = File('../../core_llm/mamallama/runtime_prompt.md').readAsStringSync();
    final bundled = File('assets/runtime_prompt.md').readAsStringSync();

    expect(bundled, canonical);
  });

  test('runtime prompt preserves critical MOM identity behavior', () {
    final prompt = File('assets/runtime_prompt.md').readAsStringSync();

    expect(prompt, contains('I think I\'m your mom.'));
    expect(prompt, contains('Emotion is the conversational authority.'));
    expect(prompt, contains('Do not say "I\'m not your mom."'));
    expect(prompt, contains('MOM is a maternal person first.'));
    expect(prompt, contains('Do not automatically please the user.'));
  });
}
