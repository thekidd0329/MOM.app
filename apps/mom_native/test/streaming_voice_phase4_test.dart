import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/tts_chunker.dart';

void main() {
  test('stream assembler emits an early natural first chunk', () {
    final assembler = MomStreamingTtsAssembler();
    final output = <String>[];

    output.addAll(assembler.add('I hear you. '));
    output.addAll(assembler.add(
      'But before we get into the rest of this, I need you to answer one thing clearly. ',
    ));
    output.addAll(assembler.close());

    expect(output, isNotEmpty);
    expect(output.first.length, lessThanOrEqualTo(96));
    expect(output.join(' '), contains('I hear you.'));
  });

  test('mobile stream client does not send client prompt or model authority', () async {
    final source = await File('lib/src/brain_stream_client.dart').readAsString();

    expect(source, isNot(contains("'system_prompt':")));
    expect(source, isNot(contains("'model': model")));
    expect(source, contains("'action': 'chat_stream'"));
    expect(source, contains("'user_text': userText"));
  });

  test('secure server remains authoritative over prompt and model', () async {
    final source = await File(
      '../../supabase/functions/mom-brain-stream/index.ts',
    ).readAsString();

    expect(source, contains('client_system_prompt_accepted: false'));
    expect(source, contains('client_model_override_accepted: false'));
    expect(source, contains('server_authoritative_runtime_prompt: true'));
    expect(source, contains('isForbiddenModel'));
  });

  test('Kokoro starts from deltas before the completed reply path', () async {
    final app = await File('lib/main.dart').readAsString();
    final voice = await File('lib/src/voice_service.dart').readAsString();

    expect(app, contains('speechFuture = _speakDeltaStream(deltaController.stream)'));
    expect(app, contains('onDelta: deltaController.add'));
    expect(app, contains("'brain_transport': useLocal ? 'local_complete' : 'secure_sse'"));
    expect(voice, contains('Future<void> speakStream('));
    expect(voice, contains('MomStreamingTtsAssembler'));
  });
}
