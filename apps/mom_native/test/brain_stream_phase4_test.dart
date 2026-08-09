import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Workload 1 Phase 4 streaming contract', () {
    late String clientSource;
    late String parserSource;
    late String edgeSource;

    setUpAll(() async {
      clientSource = await File('lib/src/brain_stream_client.dart').readAsString();
      parserSource = await File('lib/src/brain_stream_parser.dart').readAsString();
      edgeSource = await File('../../supabase/functions/mom-brain-stream/index.ts')
          .readAsString();
    });

    test('client uses authenticated SSE transport', () {
      expect(clientSource, contains("'accept': 'text/event-stream'"));
      expect(clientSource, contains("'x-mom-installation': installation"));
      expect(clientSource, contains("'x-mom-token': token"));
      expect(clientSource, contains("'mom-brain-stream'"));
    });

    test('client consumes response incrementally instead of buffering success', () {
      expect(clientSource, contains('.transform(const LineSplitter())'));
      expect(clientSource, contains('final chunk = parser.parseLine(line)'));
      expect(parserSource, contains("if (data == '[DONE]')"));
    });

    test('edge function requests provider streaming', () {
      expect(edgeSource, contains('stream: true'));
      expect(edgeSource, contains('"Content-Type": "text/event-stream; charset=utf-8"'));
    });

    test('edge function forwards provider stream body directly', () {
      expect(edgeSource, contains('return new Response(provider.body'));
      final providerRequest = edgeSource.indexOf('const provider = await providerFetch');
      final directResponse = edgeSource.indexOf('return new Response(provider.body');
      expect(providerRequest, greaterThanOrEqualTo(0));
      expect(directResponse, greaterThan(providerRequest));
    });

    test('stream endpoint retains installation authentication and awareness', () {
      expect(edgeSource, contains('await authenticate(req)'));
      expect(edgeSource, contains('await awarenessContext(req)'));
      expect(edgeSource, contains('MOM_RUNTIME_GUARD'));
    });

    test('provider capacity failures are surfaced before streaming begins', () {
      expect(edgeSource, contains('provider_status: provider.status'));
      expect(edgeSource, contains('error: "provider_error"'));
    });
  });
}
