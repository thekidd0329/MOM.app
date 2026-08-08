import 'discovery_bank.dart';
import 'discovery_models.dart';

class DiscoveryEngine {
  const DiscoveryEngine();

  static const List<String> gatewayIds = [
    'orientation_when_life_slips',
    'orientation_mom_role',
    'orientation_reminder_feel',
    'orientation_control_level',
  ];

  static const int minimumQuestions = 8;
  static const int mediumQuestions = 12;
  static const int maximumQuestions = 20;

  DiscoveryNode? nextNode(DiscoveryProgress progress) {
    if (progress.complete || shouldFinish(progress)) return null;

    final answered = progress.answeredIds;
    for (final id in gatewayIds) {
      if (!answered.contains(id)) return discoveryById[id];
    }

    final candidates = discoveryBank.where((node) => !answered.contains(node.id)).toList();
    if (candidates.isEmpty) return null;

    candidates.sort((a, b) {
      final scoreCompare = _candidateScore(b, progress).compareTo(_candidateScore(a, progress));
      if (scoreCompare != 0) return scoreCompare;
      // Explicit lexical tie-break keeps a resumed setup deterministic across
      // processes and platforms instead of relying on runtime hash behavior.
      return a.id.compareTo(b.id);
    });
    return candidates.first;
  }

  double _candidateScore(DiscoveryNode node, DiscoveryProgress progress) {
    final requested = progress.domainWeights[node.domain] ?? 0;
    final hits = progress.domainHits[node.domain] ?? 0;

    var score = requested * 3.0;
    score += hits == 0 ? 2.5 : hits == 1 ? 0.8 : -1.5 * (hits - 1);

    if (progress.answeredCount < 6) score -= node.depth * 0.8;
    if (progress.averageCertainty < 0.65) score += node.depth == 1 ? 1.0 : 0;

    return score;
  }

  DiscoveryProgress answer(
    DiscoveryProgress progress,
    DiscoveryNode node,
    DiscoveryChoice choice,
  ) {
    final totals = Map<String, double>.from(progress.signalTotals);
    final weights = Map<String, double>.from(progress.signalWeights);
    final domainWeights = Map<String, double>.from(progress.domainWeights);
    final domainHits = Map<String, int>.from(progress.domainHits);

    choice.signals.forEach((signal, value) {
      totals[signal] = (totals[signal] ?? 0) + value * choice.certainty;
      weights[signal] = (weights[signal] ?? 0) + choice.certainty;
    });

    for (final domain in choice.opens) {
      domainWeights[domain] = (domainWeights[domain] ?? 0) + 1.0 + choice.certainty;
    }
    for (final domain in choice.suppresses) {
      domainWeights[domain] = (domainWeights[domain] ?? 0) - 1.5;
    }

    domainHits[node.domain] = (domainHits[node.domain] ?? 0) + 1;

    final updated = progress.copyWith(
      answers: [
        ...progress.answers,
        DiscoveryAnswer(
          nodeId: node.id,
          choiceId: choice.id,
          certainty: choice.certainty,
          answeredAt: DateTime.now(),
        ),
      ],
      signalTotals: totals,
      signalWeights: weights,
      domainWeights: domainWeights,
      domainHits: domainHits,
    );

    return shouldFinish(updated) ? updated.copyWith(complete: true) : updated;
  }

  bool shouldFinish(DiscoveryProgress progress) {
    if (progress.complete) return true;
    if (progress.answeredCount >= maximumQuestions) return true;
    if (progress.answeredCount < minimumQuestions) return false;

    final highPriorityUnexplored = progress.domainWeights.entries.where((entry) {
      final hits = progress.domainHits[entry.key] ?? 0;
      return entry.value >= 3.2 && hits == 0;
    }).length;

    // Clear early answers let MOM leave more discovery for ordinary life.
    if (progress.averageCertainty >= 0.86 && highPriorityUnexplored == 0) return true;

    // Mixed answers keep branches open longer, but startup still has a ceiling.
    if (progress.answeredCount >= mediumQuestions &&
        progress.averageCertainty >= 0.70 &&
        highPriorityUnexplored <= 1) {
      return true;
    }

    return false;
  }

  String promptFor(DiscoveryNode node, DiscoveryProgress progress) {
    if (node.promptVariants.isEmpty) return '';
    final index = progress.answeredCount % node.promptVariants.length;
    return node.promptVariants[index];
  }
}
