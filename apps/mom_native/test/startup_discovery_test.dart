import 'package:flutter_test/flutter_test.dart';
import 'package:mom_native/src/startup_discovery/discovery_bank.dart';
import 'package:mom_native/src/startup_discovery/discovery_engine.dart';
import 'package:mom_native/src/startup_discovery/discovery_models.dart';

void main() {
  test('bank contains 200 fully mapped discoveries', () {
    expect(discoveryBank.length, 200);
    expect(discoveryBank.map((node) => node.id).toSet().length, 200);

    for (final node in discoveryBank) {
      expect(node.promptVariants.length, greaterThanOrEqualTo(3), reason: node.id);
      expect(node.choices.length, greaterThanOrEqualTo(4), reason: node.id);
      expect(node.choices.map((choice) => choice.id).toSet().length, node.choices.length, reason: node.id);
      for (final choice in node.choices) {
        expect(choice.certainty, inInclusiveRange(0.0, 1.0), reason: choice.id);
      }
    }
  });

  test('all routed domains exist in the discovery bank', () {
    final domains = discoveryBank.map((node) => node.domain).toSet();
    for (final node in discoveryBank) {
      for (final choice in node.choices) {
        for (final domain in [...choice.opens, ...choice.suppresses]) {
          expect(domains, contains(domain), reason: '${choice.id} references $domain');
        }
      }
    }
  });

  test('first four questions are routing gateways', () {
    const engine = DiscoveryEngine();
    var progress = const DiscoveryProgress();

    for (final expectedId in DiscoveryEngine.gatewayIds) {
      final node = engine.nextNode(progress);
      expect(node?.id, expectedId);
      progress = engine.answer(progress, node!, node.choices.first);
    }

    expect(progress.answeredCount, 4);
    expect(engine.nextNode(progress), isNotNull);
  });

  test('a saved partial path resumes at the same next discovery', () {
    const engine = DiscoveryEngine();
    var progress = const DiscoveryProgress();

    for (var i = 0; i < 6; i++) {
      final node = engine.nextNode(progress);
      expect(node, isNotNull);
      final choice = node!.choices[i % node.choices.length];
      progress = engine.answer(progress, node, choice);
    }

    final expected = engine.nextNode(progress)?.id;
    final restored = DiscoveryProgress.decode(progress.encode());
    expect(engine.nextNode(restored)?.id, expected);
  });

  test('clear answers can stop early but never before minimum', () {
    const engine = DiscoveryEngine();
    var progress = const DiscoveryProgress();

    while (!progress.complete && progress.answeredCount < DiscoveryEngine.maximumQuestions) {
      final node = engine.nextNode(progress);
      expect(node, isNotNull);
      progress = engine.answer(progress, node!, node.choices.first);
    }

    expect(progress.complete, isTrue);
    expect(progress.answeredCount, greaterThanOrEqualTo(DiscoveryEngine.minimumQuestions));
    expect(progress.answeredCount, lessThanOrEqualTo(DiscoveryEngine.maximumQuestions));
  });

  test('mixed answers explore longer without exceeding the ceiling', () {
    const engine = DiscoveryEngine();
    var progress = const DiscoveryProgress();

    while (!progress.complete && progress.answeredCount < DiscoveryEngine.maximumQuestions) {
      final node = engine.nextNode(progress);
      expect(node, isNotNull);
      progress = engine.answer(progress, node!, node.choices.last);
    }

    expect(progress.complete, isTrue);
    expect(progress.answeredCount, greaterThanOrEqualTo(DiscoveryEngine.mediumQuestions));
    expect(progress.answeredCount, lessThanOrEqualTo(DiscoveryEngine.maximumQuestions));
  });
}
