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

  test('first four questions are routing gateways', () {
    const engine = DiscoveryEngine();
    var progress = const DiscoveryProgress();

    for (final expectedId in DiscoveryEngine.gatewayIds) {
      final node = engine.nextNode(progress);
      expect(node?.id, expectedId);
      progress = engine.answer(progress, node!, node.choices.first);
    }

    expect(progress.answeredCount, 4);
    expect(engine.nextNode(progress)?.id, isNot(inInclusiveRange(0, 0)));
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

  test('mixed answers keep discovery open longer without exceeding 20', () {
    const engine = DiscoveryEngine();
    var progress = const DiscoveryProgress();

    while (!progress.complete && progress.answeredCount < DiscoveryEngine.maximumQuestions) {
      final node = engine.nextNode(progress);
      expect(node, isNotNull);
      progress = engine.answer(progress, node!, node.choices.last);
    }

    expect(progress.complete, isTrue);
    expect(progress.answeredCount, DiscoveryEngine.maximumQuestions);
  });
}
