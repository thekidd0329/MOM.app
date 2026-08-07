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
      issues.isEmpty ? 'All configured variables are in range and parse correctly.' : issues.map((e) => '${e.key}: ${e.message}').join(' | '),
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
      results.add(DiagnosticResult(
        'Live repository folders',
        await repo.exists(),
        await repo.exists() ? 'MOM can read ${repo.path}.' : 'Repository folder is not available: ${repo.path}',
        warning: !await repo.exists(),
      ));
    }

    final syncHealth = await sync.health();
    results.add(DiagnosticResult(
      'Supabase sync service',
      syncHealth,
      syncHealth ? 'mom-sync Edge Function is reachable.' : 'mom-sync Edge Function could not be reached.',
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
      registered ? 'This MOM install has a server-validated device identity.' : 'Device registration is not complete.',
    ));

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
      'Model endpoint',
      modelHealth,
      modelHealth ? 'The OpenAI-compatible model endpoint responds.' : 'The configured model endpoint is unavailable.',
    ));
    if (modelHealth) {
      try {
        final model = await client.resolveModel();
        results.add(DiagnosticResult('Model selection', model.isNotEmpty, 'Resolved model: $model'));
      } catch (error) {
        results.add(DiagnosticResult('Model selection', false, '$error'));
      }
    }
    client.close();

    return results;
  }
}
