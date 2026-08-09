import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConfigIssue {
  const ConfigIssue(this.key, this.message, {this.fatal = false});
  final String key;
  final String message;
  final bool fatal;
}

class MomConfig {
  MomConfig({
    required this.syncUrl,
    required this.modelApiBase,
    required this.modelName,
    required this.modelApiKey,
    required this.useLocalLlama,
    required this.modelsDir,
    required this.repoRoot,
    required this.cloudChatSync,
    required this.productTelemetry,
    required this.temperature,
    required this.maxHistory,
  });

  static const defaultSyncUrl =
      'https://ghdgrcwvpsxbarxmopdp.supabase.co/functions/v1/mom-sync';
  static const defaultBrainUrl =
      'https://ghdgrcwvpsxbarxmopdp.supabase.co/functions/v1/mom-brain';
  static const defaultHostedModel = 'Qwen/Qwen2.5-7B-Instruct';

  String syncUrl;
  String modelApiBase;
  String modelName;
  String modelApiKey;
  bool useLocalLlama;
  String modelsDir;
  String repoRoot;
  bool cloudChatSync;
  bool productTelemetry;
  double temperature;
  int maxHistory;

  bool get isDesktopLinux => Platform.isLinux;
  bool get isMobile => Platform.isAndroid || Platform.isIOS;

  List<ConfigIssue> validate() {
    final issues = <ConfigIssue>[];

    final sync = Uri.tryParse(syncUrl);
    if (sync == null || !sync.hasScheme || !sync.hasAuthority) {
      issues.add(const ConfigIssue('syncUrl', 'Supabase sync URL is invalid.', fatal: true));
    } else if (sync.scheme != 'https') {
      issues.add(const ConfigIssue('syncUrl', 'Supabase sync must use HTTPS.', fatal: true));
    }

    if (useLocalLlama) {
      final api = Uri.tryParse(modelApiBase);
      if (api == null || !api.hasScheme || !api.hasAuthority) {
        issues.add(const ConfigIssue('modelApiBase', 'Local model API URL is invalid.', fatal: true));
      }
    }

    if (temperature < 0 || temperature > 2) {
      issues.add(const ConfigIssue('temperature', 'Temperature must be between 0 and 2.', fatal: true));
    }
    if (maxHistory < 2 || maxHistory > 200) {
      issues.add(const ConfigIssue('maxHistory', 'History window must be between 2 and 200.', fatal: true));
    }

    if (useLocalLlama && !isDesktopLinux) {
      issues.add(const ConfigIssue(
        'useLocalLlama',
        'Local llama autostart is only supported by the Linux client.',
      ));
    }

    if (useLocalLlama && isDesktopLinux) {
      final dir = Directory(expandHome(modelsDir));
      if (!dir.existsSync()) {
        issues.add(ConfigIssue('modelsDir', 'Model directory does not exist: ${dir.path}'));
      }
    }

    if (isDesktopLinux && repoRoot.trim().isNotEmpty) {
      final dir = Directory(expandHome(repoRoot));
      if (!dir.existsSync()) {
        issues.add(ConfigIssue('repoRoot', 'Repository knowledge folder does not exist: ${dir.path}'));
      }
    }

    return issues;
  }

  MomConfig copy() => MomConfig(
        syncUrl: syncUrl,
        modelApiBase: modelApiBase,
        modelName: modelName,
        modelApiKey: modelApiKey,
        useLocalLlama: useLocalLlama,
        modelsDir: modelsDir,
        repoRoot: repoRoot,
        cloudChatSync: cloudChatSync,
        productTelemetry: productTelemetry,
        temperature: temperature,
        maxHistory: maxHistory,
      );
}

String expandHome(String input) {
  if (!input.startsWith('~')) return input;
  final home = Platform.environment['HOME'] ?? '';
  if (home.isEmpty) return input;
  if (input == '~') return home;
  if (input.startsWith('~/')) return '$home/${input.substring(2)}';
  return input;
}

class ConfigStore {
  ConfigStore({FlutterSecureStorage? secureStorage})
      : _secure = secureStorage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _secure;
  static const _apiKeyKey = 'mom_model_api_key';

  Future<MomConfig> load() async {
    final prefs = await SharedPreferences.getInstance();
    final home = Platform.environment['HOME'] ?? '';
    final defaultModels = home.isEmpty ? 'models' : '$home/MomBrain/models';
    final mainRepo = home.isEmpty ? '' : '$home/MomBrain/MOM.app-main';
    final fallbackRepo = home.isEmpty ? '' : '$home/MomBrain';
    final repo = Directory(mainRepo).existsSync() ? mainRepo : fallbackRepo;
    final savedModel = (prefs.getString('model_name') ?? '').trim();

    // Hosted provider credentials belong on the Supabase server now. Remove any
    // legacy on-device copy left by older MOM builds.
    await _secure.delete(key: _apiKeyKey);

    return MomConfig(
      syncUrl: prefs.getString('sync_url') ?? MomConfig.defaultSyncUrl,
      modelApiBase: prefs.getString('model_api_base') ?? MomConfig.defaultBrainUrl,
      modelName:
          savedModel.isEmpty ? MomConfig.defaultHostedModel : savedModel,
      modelApiKey: '',
      useLocalLlama: prefs.getBool('use_local_llama') ?? false,
      modelsDir: prefs.getString('models_dir') ?? defaultModels,
      repoRoot: prefs.getString('repo_root') ?? repo,
      cloudChatSync: prefs.getBool('cloud_chat_sync') ?? true,
      productTelemetry: prefs.getBool('product_telemetry') ?? true,
      temperature: prefs.getDouble('temperature') ?? 0.72,
      maxHistory: prefs.getInt('max_history') ?? 30,
    );
  }

  Future<void> save(MomConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sync_url', config.syncUrl.trim());
    await prefs.setString('model_api_base', config.modelApiBase.trim());
    await prefs.setString('model_name', config.modelName.trim());
    await prefs.setBool('use_local_llama', config.useLocalLlama);
    await prefs.setString('models_dir', config.modelsDir.trim());
    await prefs.setString('repo_root', config.repoRoot.trim());
    await prefs.setBool('cloud_chat_sync', config.cloudChatSync);
    await prefs.setBool('product_telemetry', config.productTelemetry);
    await prefs.setDouble('temperature', config.temperature);
    await prefs.setInt('max_history', config.maxHistory);

    // Never persist hosted model credentials in the client.
    config.modelApiKey = '';
    await _secure.delete(key: _apiKeyKey);
  }
}
