import 'package:shared_preferences/shared_preferences.dart';

import 'discovery_models.dart';

class DiscoveryProgressStore {
  static const _key = 'mom_startup_discovery_v1';

  Future<DiscoveryProgress> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const DiscoveryProgress();
    return DiscoveryProgress.decode(raw);
  }

  Future<void> save(DiscoveryProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, progress.encode());
  }

  Future<bool> isComplete() async => (await load()).complete;

  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
