import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/brain_stream_parser.dart';

void main() {
  group('BrainSseParser', () {
    test('ignores non-data lines and malformed events', () {
      final parser = BrainSseParser();
      expect(parser.parseLine('event: message'), isNull);
      expect(parser.parseLine('data: not-json'), isNull);
      expect(parser.parseLine('data:'), isNull);
    });

    test('parses content deltas and learns provider model', () {
      final parser = BrainSseParser(initialModel: 'fallback-model');
      final chunk = parser.parseLine(
        'data: {"model":"mom-model","choices":[{"delta":{"content":"Hey"}}]}',
      );

      expect(chunk, isNotNull);
      expect(chunk!.delta, 'Hey');
      expect(chunk.model, 'mom-model');
      expect(chunk.done, isFalse);
      expect(parser.model, 'mom-model');
    });

    test('keeps model across later delta events', () {
      final parser = BrainSseParser(initialModel: 'mom-model');
      final chunk = parser.parseLine(
        'data: {"choices":[{"delta":{"content":" there"}}]}',
      );

      expect(chunk, isNotNull);
      expect(chunk!.delta, ' there');
      expect(chunk.model, 'mom-model');
    });

    test('ignores role-only provider deltas', () {
      final parser = BrainSseParser();
      expect(
        parser.parseLine(
          'data: {"choices":[{"delta":{"role":"assistant"}}]}',
        ),
        isNull,
      );
    });

    test('emits an explicit done event', () {
      final parser = BrainSseParser(initialModel: 'mom-model');
      final done = parser.parseLine('data: [DONE]');
      expect(done, isNotNull);
      expect(done!.done, isTrue);
      expect(done.delta, isEmpty);
      expect(done.model, 'mom-model');
    });
  });
}
