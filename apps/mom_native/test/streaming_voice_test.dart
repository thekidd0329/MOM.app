import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/tts_chunker.dart';

String normalize(String value) => value.replaceAll(RegExp(r'\s+'), ' ').trim();

void main() {
  test('stream assembler emits a complete first thought before stream close', () {
    final assembler = MomStreamingTtsAssembler();

    final ready = assembler.add(
      "I hear what you're saying, and I'm paying attention. More is coming after this.",
    );

    expect(ready, isNotEmpty);
    expect(ready.first, contains("I hear what you're saying"));
  });

  test('stream assembler preserves the unsent tail until close', () {
    final assembler = MomStreamingTtsAssembler();
    final emitted = <String>[];

    emitted.addAll(assembler.add('This is a complete opening sentence with enough words. '));
    emitted.addAll(assembler.add('This tail is still arriving'));
    emitted.addAll(assembler.close());

    expect(
      normalize(emitted.join(' ')),
      normalize(
        'This is a complete opening sentence with enough words. This tail is still arriving',
      ),
    );
  });

  test('app starts voice pipeline from model deltas instead of final reply', () async {
    final app = await File('lib/main.dart').readAsString();
    final model = await File('lib/src/model_client.dart').readAsString();
    final sync = await File('lib/src/sync_client.dart').readAsString();
    final voice = await File('lib/src/voice_service.dart').readAsString();

    expect(app, contains('final voiceDeltas = StreamController<String>()'));
    expect(app, contains('.speakStream('));
    expect(app, contains('final reply = await client.chatStream('));
    expect(app, contains('voiceDeltas.add(delta)'));
    expect(model, contains("'stream': true"));
    expect(model, contains('brainChatStream('));
    expect(sync, contains("String get brainStreamUrl => _serviceUrl('mom-brain-stream')"));
    expect(sync, contains("decoded['type'] == 'delta'"));
    expect(voice, contains('Future<void> speakStream('));
  });

  test('server streaming source emits SSE deltas from provider stream', () async {
    final server = await File(
      '../../supabase/functions/mom-brain-stream/index.ts',
    ).readAsString();

    expect(server, contains('stream: true'));
    expect(server, contains('text/event-stream'));
    expect(server, contains('type: "delta"'));
    expect(server, contains('data: [DONE]'));
  });
}
