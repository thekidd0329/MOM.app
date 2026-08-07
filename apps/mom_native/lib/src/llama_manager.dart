import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';

class LlamaStatus {
  const LlamaStatus({required this.running, required this.message, this.modelCount = 0});
  final bool running;
  final String message;
  final int modelCount;
}

class LlamaManager {
  Process? _process;

  Future<LlamaStatus> ensureRunning(MomConfig config) async {
    if (!Platform.isLinux || !config.useLocalLlama) {
      return const LlamaStatus(running: false, message: 'Local llama autostart disabled.');
    }

    final existing = await probe(config.modelApiBase);
    if (existing.running) return existing;

    final modelDir = Directory(expandHome(config.modelsDir));
    if (!await modelDir.exists()) {
      return LlamaStatus(running: false, message: 'Model directory not found: ${modelDir.path}');
    }
    final ggufs = await modelDir
        .list(followLinks: false)
        .where((e) => e is File && e.path.toLowerCase().endsWith('.gguf'))
        .cast<File>()
        .toList();
    if (ggufs.isEmpty) {
      return LlamaStatus(running: false, message: 'No GGUF models found in ${modelDir.path}.');
    }

    final executable = await _findLlama();
    if (executable == null) {
      return const LlamaStatus(running: false, message: 'llama.cpp launcher was not found.');
    }

    try {
      _process = await Process.start(
        executable,
        [
          'serve',
          '--models-dir',
          modelDir.path,
          '--cors-origins',
          'localhost',
        ],
        mode: ProcessStartMode.normal,
      );
      // Drain pipes so a verbose server cannot block itself.
      _process!.stdout.transform(const SystemEncoding().decoder).listen((_) {});
      _process!.stderr.transform(const SystemEncoding().decoder).listen((_) {});
    } catch (error) {
      return LlamaStatus(running: false, message: 'Could not start llama.cpp: $error');
    }

    for (var i = 0; i < 90; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final status = await probe(config.modelApiBase);
      if (status.running) return status;
      if (_process != null && (await _process!.exitCode.timeout(const Duration(milliseconds: 1), onTimeout: () => -1)) != -1) {
        break;
      }
    }
    return const LlamaStatus(running: false, message: 'llama.cpp did not become ready within 45 seconds.');
  }

  Future<LlamaStatus> probe(String apiBase) async {
    final base = apiBase.replaceAll(RegExp(r'/$'), '');
    try {
      final response = await http.get(Uri.parse('$base/models')).timeout(const Duration(seconds: 2));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final matches = RegExp(r'"id"\s*:').allMatches(response.body).length;
        return LlamaStatus(running: true, message: 'Local llama.cpp is online.', modelCount: matches);
      }
      return LlamaStatus(running: false, message: 'Local model server returned HTTP ${response.statusCode}.');
    } catch (_) {
      return const LlamaStatus(running: false, message: 'Local model server is offline.');
    }
  }

  Future<String?> _findLlama() async {
    final home = Platform.environment['HOME'] ?? '';
    final candidates = <String>[
      if (home.isNotEmpty) '$home/.local/bin/llama',
      if (home.isNotEmpty) '$home/.llama/bin/llama',
      '/usr/local/bin/llama',
      '/usr/bin/llama',
    ];
    for (final candidate in candidates) {
      if (await File(candidate).exists()) return candidate;
    }
    try {
      final result = await Process.run('bash', ['-lc', 'command -v llama']);
      final path = '${result.stdout}'.trim();
      if (result.exitCode == 0 && path.isNotEmpty) return path.split('\n').first;
    } catch (_) {}
    return null;
  }

  void stopIfStartedByMom() {
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
  }
}
