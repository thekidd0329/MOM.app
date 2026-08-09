import 'dart:io';

import 'config.dart';
import 'knowledge.dart';
import 'llama_manager.dart';
import 'local_store.dart';
import 'model_client.dart';
import 'sync_client.dart';

class DiagnosticResult {
  const DiagnosticResult(this.name, this.ok, this.detail, {this.warning = false});
  final String name;
  final bool ok;
  final String detail;
  final bool warning;
}

class DiagnosticsRunner {
  DiagnosticsRunner({
    required this.config,
    required this.store,
    required this.knowledge,
    required this.sync,
    required this.llama,
  });

  final MomConfig config;
  final ConversationStore store;
  final KnowledgeService knowledge;
  final MomSyncClient sync;
  final LlamaManager llama;

  Future<List<DiagnosticResult>> run() async {
    final results = <DiagnosticResult>[];

    final issues = config.validate();
    results.add(DiagnosticResult(
      'Configuration variables',
      !issues.any((i) => i.fatal),
      issues.isEmpty
          ? 'All configured variables are in range and parse correctly.'
          : issues.map((e) => '${e.key}: ${e.message}').join(' | '),
      warning: issues.isNotEmpty && !issues.any((i) => i.fatal),
    ));

    results.add(DiagnosticResult(
      'Local storage',
      await store.writable(),
      'MOM application-support transcript path is writable.',
    ));

    results.add(DiagnosticResult(
      'Knowledge access',
      knowledge.entryCount > 0,
      '${knowledge.entryCount} knowledge documents are available to MOM.',
      warning: knowledge.entryCount == 0,
    ));

    if (Platform.isLinux && config.repoRoot.trim().isNotEmpty) {
      final repo = Directory(expandHome(config.repoRoot));
      final exists = await repo.exists();
      results.add(DiagnosticResult(
        'Live repository folders',
        exists,
        exists
            ? 'MOM can read ${repo.path}.'
            : 'Repository folder is not available: ${repo.path}',
        warning: !exists,
      ));
    }

    final syncHealth = await sync.health();
    results.add(DiagnosticResult(
      'Supabase sync service',
      syncHealth,
      syncHealth
          ? 'mom-sync Edge Function is reachable.'
          : 'mom-sync Edge Function could not be reached.',
    ));

    var registered = false;
    if (syncHealth) {
      try {
        await sync.ensureRegistered();
        registered = await sync.registered();
      } catch (_) {}
    }
    results.add(DiagnosticResult(
      'Cloud installation identity',
      registered,
      registered
          ? 'This MOM install has a server-validated device identity.'
          : 'Device registration is not complete.',
    ));

    if (registered) {
      try {
        final snapshot = await sync.intelligenceSnapshot();
        final totals = snapshot['totals'];
        final latest = snapshot['latest_facts'];
        final temporal = snapshot['open_temporal_items'];

        final totalMap = totals is Map<String, dynamic>
            ? totals
            : <String, dynamic>{};
        final factCount = NumberHelper.asInt(totalMap['profile_facts']);
        final extractionCount = NumberHelper.asInt(totalMap['extractions']);
        final temporalCount = NumberHelper.asInt(totalMap['temporal_items']);
        final uniquePoints = NumberHelper.asInt(totalMap['unique_data_points']);
        final userChars = NumberHelper.asInt(totalMap['user_input_characters']);
        final density = NumberHelper.asDouble(
          totalMap['data_points_per_1000_user_chars'],
        );

        final latestFacts = latest is List
            ? latest.whereType<Map>().take(4).map((raw) {
                final value = raw['value'];
                final category = raw['category'];
                final evidence = NumberHelper.asInt(raw['evidence_count']);
                return '${category ?? 'fact'}: ${value ?? ''}${evidence > 1 ? ' (evidence ×$evidence)' : ''}';
              }).where((value) => value.trim().isNotEmpty).toList()
            : const <String>[];

        final openItems = temporal is List
            ? temporal.whereType<Map>().take(2).map((raw) {
                final title = raw['title'];
                final timeText = raw['time_text'];
                final urgency = NumberHelper.asDouble(raw['urgency']);
                return '${title ?? 'time item'}${timeText == null ? '' : ' · $timeText'} · urgency ${(urgency * 100).round()}%';
              }).toList()
            : const <String>[];

        final detail = <String>[
          '$extractionCount user messages analyzed → $factCount persistent profile facts + $temporalCount time-aware items.',
          '$uniquePoints unique structured data points from $userChars user characters.',
          '${density.toStringAsFixed(2)} structured data points per 1,000 user characters.',
          if (latestFacts.isNotEmpty) 'Latest: ${latestFacts.join(' | ')}',
          if (openItems.isNotEmpty) 'Open time layer: ${openItems.join(' | ')}',
        ].join('\n');

        results.add(DiagnosticResult(
          'MOM intelligence proof',
          snapshot['ok'] == true,
          detail,
        ));
      } catch (error) {
        results.add(DiagnosticResult(
          'MOM intelligence proof',
          false,
          'Structured context snapshot unavailable: $error',
        ));
      }
    }

    if (Platform.isLinux && config.useLocalLlama) {
      final local = await llama.probe(config.modelApiBase);
      results.add(DiagnosticResult(
        'Local llama.cpp',
        local.running,
        local.message,
        warning: !local.running,
      ));
    }

    final client = ModelClient(config.copy());
    final modelHealth = await client.health();
    results.add(DiagnosticResult(
      'Brain service configuration',
      modelHealth,
      modelHealth
          ? 'The configured brain service is reachable and reports model credentials present.'
          : 'The configured brain service is unavailable or missing model credentials.',
    ));

    if (modelHealth) {
      try {
        final model = await client.resolveModel();
        results.add(DiagnosticResult(
          'Model selection',
          model.isNotEmpty,
          'Resolved model: $model',
        ));
      } catch (error) {
        final failure = classifyModelFailure(error);
        results.add(DiagnosticResult(
          'Model selection',
          false,
          failure.diagnosticSummary,
        ));
      }

      try {
        final probe = await client.probe();
        results.add(DiagnosticResult(
          'End-to-end brain answer',
          true,
          '${probe.route} completed in ${probe.latencyMs} ms using ${probe.model}. This proves a real model completion reached the app.',
        ));
      } catch (error) {
        final failure = classifyModelFailure(error);
        results.add(DiagnosticResult(
          'End-to-end brain answer',
          false,
          '${failure.userMessage}\n${failure.diagnosticSummary}',
        ));
      }
    }
    client.close();

    return results;
  }
}

class NumberHelper {
  static int asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse('$value') ?? 0;
  }

  static double asDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}
