import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/voice_continuity.dart';

void main() {
  tearDown(MomVoiceContinuity.clear);

  test('unfinished thought distinguishes heard and unsaid speech', () {
    const thought = InterruptedMomThought(
      heardText: 'I need you to listen',
      unsaidText: 'because this next part matters',
      currentChunkMayBePartial: true,
    );

    expect(thought.hasUnsaidText, isTrue);
    final context = thought.toAssistantHistoryContext();
    expect(context, contains('They heard approximately: I need you to listen'));
    expect(context, contains('You had not finished saying: because this next part matters'));
    expect(context, contains('Respond to the user interruption first'));
  });

  test('continuity is one-shot so an old interruption cannot haunt later turns', () {
    const thought = InterruptedMomThought(
      heardText: 'one',
      unsaidText: 'two three',
      currentChunkMayBePartial: false,
    );
    MomVoiceContinuity.preserve(thought);

    expect(MomVoiceContinuity.consume(), same(thought));
    expect(MomVoiceContinuity.consume(), isNull);
  });

  test('voice service estimates the heard boundary from actual playback time', () async {
    final source = await File('lib/src/voice_service.dart').readAsString();

    expect(source, contains('_activeChunkStartedAt'));
    expect(source, contains('_activeChunkDuration'));
    expect(source, contains('sampleCount / _kokoroSampleRate'));
    expect(source, contains('heardInActive = (activeWords.length * fraction).floor()'));
    expect(source, contains('stopSpeaking(preserveContinuity: true)'));
  });

  test('next secure brain turn receives the unfinished thought as history', () async {
    final source = await File('lib/src/brain_stream_client.dart').readAsString();

    expect(source, contains('final interrupted = MomVoiceContinuity.consume()'));
    expect(source, contains("'role': 'assistant'"));
    expect(source, contains('interrupted.toAssistantHistoryContext()'));
    expect(source, isNot(contains("'system_prompt':")));
  });
}
