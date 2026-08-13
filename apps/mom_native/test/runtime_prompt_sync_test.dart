import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mobile runtime prompt authority is Supabase mom-brain', () {
    final migration = File(
      '../../supabase/migrations/20260810021810_mom_110_server_runtime_config.sql',
    ).readAsStringSync();
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(migration, contains("'prompt_authority', 'mom-brain'"));
    expect(migration, contains("'bundled_runtime_prompt_required', false"));
    expect(
      migration,
      contains("'bundled_repository_knowledge_required', false"),
    );
    expect(pubspec, isNot(contains('assets/runtime_prompt.md')));
    expect(pubspec, isNot(contains('assets/knowledge/mom_knowledge.jsonl')));
  });

  test('canonical server prompt preserves critical MOM identity behavior', () {
    final prompt =
        File('../../core_llm/mamallama/runtime_prompt.md').readAsStringSync();

    expect(prompt, contains('I think I\'m your mom.'));
    expect(prompt, contains('Emotion is the conversational authority.'));
    expect(prompt, contains('Do not say "I\'m not your mom."'));
    expect(prompt, contains('MOM is a maternal person first.'));
    expect(prompt, contains('Do not automatically please the user.'));
  });
}
