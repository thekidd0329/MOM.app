import 'dart:convert';

class DiscoveryChoice {
  const DiscoveryChoice({
    required this.id,
    required this.label,
    required this.detail,
    required this.signals,
    required this.opens,
    required this.suppresses,
    required this.certainty,
  });

  final String id;
  final String label;
  final String detail;
  final Map<String, double> signals;
  final List<String> opens;
  final List<String> suppresses;
  final double certainty;
}

class DiscoveryNode {
  const DiscoveryNode({
    required this.id,
    required this.domain,
    required this.promptVariants,
    required this.choices,
    this.depth = 1,
  });

  final String id;
  final String domain;
  final List<String> promptVariants;
  final List<DiscoveryChoice> choices;
  final int depth;
}

class DiscoveryAnswer {
  const DiscoveryAnswer({
    required this.nodeId,
    required this.choiceId,
    required this.certainty,
    required this.answeredAt,
  });

  final String nodeId;
  final String choiceId;
  final double certainty;
  final DateTime answeredAt;

  Map<String, dynamic> toJson() => {
        'node_id': nodeId,
        'choice_id': choiceId,
        'certainty': certainty,
        'answered_at': answeredAt.toUtc().toIso8601String(),
      };

  static DiscoveryAnswer? fromJson(Map<String, dynamic> json) {
    final nodeId = json['node_id'];
    final choiceId = json['choice_id'];
    final certainty = (json['certainty'] as num?)?.toDouble();
    final answeredAt = DateTime.tryParse('${json['answered_at'] ?? ''}');
    if (nodeId is! String ||
        choiceId is! String ||
        certainty == null ||
        answeredAt == null) {
      return null;
    }
    return DiscoveryAnswer(
      nodeId: nodeId,
      choiceId: choiceId,
      certainty: certainty,
      answeredAt: answeredAt,
    );
  }
}

class DiscoveryProgress {
  const DiscoveryProgress({
    this.answers = const [],
    this.signalTotals = const {},
    this.signalWeights = const {},
    this.domainWeights = const {},
    this.domainHits = const {},
    this.personalityId = '',
    this.personalityPrompt = '',
    this.complete = false,
  });

  final List<DiscoveryAnswer> answers;
  final Map<String, double> signalTotals;
  final Map<String, double> signalWeights;
  final Map<String, double> domainWeights;
  final Map<String, int> domainHits;
  final String personalityId;
  final String personalityPrompt;
  final bool complete;

  int get answeredCount => answers.length;
  Set<String> get answeredIds => answers.map((a) => a.nodeId).toSet();

  double get averageCertainty {
    if (answers.isEmpty) return 0;
    return answers.fold<double>(0, (sum, a) => sum + a.certainty) /
        answers.length;
  }

  double scoreFor(String signal) {
    final weight = signalWeights[signal] ?? 0;
    if (weight <= 0) return 0;
    return (signalTotals[signal] ?? 0) / weight;
  }

  DiscoveryProgress copyWith({
    List<DiscoveryAnswer>? answers,
    Map<String, double>? signalTotals,
    Map<String, double>? signalWeights,
    Map<String, double>? domainWeights,
    Map<String, int>? domainHits,
    String? personalityId,
    String? personalityPrompt,
    bool? complete,
  }) {
    return DiscoveryProgress(
      answers: answers ?? this.answers,
      signalTotals: signalTotals ?? this.signalTotals,
      signalWeights: signalWeights ?? this.signalWeights,
      domainWeights: domainWeights ?? this.domainWeights,
      domainHits: domainHits ?? this.domainHits,
      personalityId: personalityId ?? this.personalityId,
      personalityPrompt: personalityPrompt ?? this.personalityPrompt,
      complete: complete ?? this.complete,
    );
  }

  Map<String, dynamic> toJson() => {
        'answers': answers.map((a) => a.toJson()).toList(),
        'signal_totals': signalTotals,
        'signal_weights': signalWeights,
        'domain_weights': domainWeights,
        'domain_hits': domainHits,
        if (personalityId.isNotEmpty) 'personality_id': personalityId,
        if (personalityPrompt.isNotEmpty) 'personality_prompt': personalityPrompt,
        'complete': complete,
      };

  static DiscoveryProgress fromJson(Map<String, dynamic> json) {
    final rawAnswers = json['answers'];
    final answers = <DiscoveryAnswer>[];
    if (rawAnswers is List) {
      for (final item in rawAnswers) {
        if (item is Map) {
          final parsed =
              DiscoveryAnswer.fromJson(Map<String, dynamic>.from(item));
          if (parsed != null) answers.add(parsed);
        }
      }
    }

    Map<String, double> doubles(String key) {
      final raw = json[key];
      if (raw is! Map) return {};
      return raw.map(
        (k, v) => MapEntry('$k', (v as num?)?.toDouble() ?? 0),
      );
    }

    Map<String, int> ints(String key) {
      final raw = json[key];
      if (raw is! Map) return {};
      return raw.map((k, v) => MapEntry('$k', (v as num?)?.toInt() ?? 0));
    }

    return DiscoveryProgress(
      answers: answers,
      signalTotals: doubles('signal_totals'),
      signalWeights: doubles('signal_weights'),
      domainWeights: doubles('domain_weights'),
      domainHits: ints('domain_hits'),
      personalityId: '${json['personality_id'] ?? ''}'.trim(),
      personalityPrompt: '${json['personality_prompt'] ?? ''}'.trim(),
      complete: json['complete'] == true,
    );
  }

  String encode() => jsonEncode(toJson());

  static DiscoveryProgress decode(String value) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map<String, dynamic>) {
        return DiscoveryProgress.fromJson(decoded);
      }
    } catch (_) {}
    return const DiscoveryProgress();
  }

  String toPromptSummary() {
    final ranked = signalWeights.keys
        .where((key) => (signalWeights[key] ?? 0) > 0)
        .map((key) => MapEntry(key, scoreFor(key)))
        .toList()
      ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));

    final strongest = ranked.take(14).map((entry) {
      final value = entry.value;
      final direction =
          value > 0.25 ? 'higher' : value < -0.25 ? 'lower' : 'mixed';
      return '- ${entry.key}: $direction (${value.toStringAsFixed(2)})';
    }).join('\n');

    final personality = personalityPrompt.trim();
    final personalitySection = personality.isEmpty
        ? ''
        : '''
## Chosen MOM personality
This personality was explicitly chosen by the person. It is a conversational style preference, not an inferred psychological trait. It can be changed later.
$personality

''';

    return '''
${personalitySection}MOM startup discovery profile
This is a non-diagnostic working profile inferred only from the user's own setup answers.
Treat it as revisable, never as a fixed label. Ask/confirm when important rather than assuming.
Discovery answers: $answeredCount
Average answer certainty: ${averageCertainty.toStringAsFixed(2)}
Strongest current signals:
$strongest
''';
  }
}
