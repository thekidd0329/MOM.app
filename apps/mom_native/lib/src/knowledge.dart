import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'config.dart';

class KnowledgeEntry {
  const KnowledgeEntry(this.path, this.text);
  final String path;
  final String text;
}

class KnowledgeHit {
  const KnowledgeHit(this.entry, this.score);
  final KnowledgeEntry entry;
  final int score;
}

class KnowledgeService {
  final List<KnowledgeEntry> _entries = [];

  int get entryCount => _entries.length;

  static const allowedExtensions = {
    '.md', '.txt', '.json', '.yaml', '.yml', '.toml', '.sql', '.py', '.dart', '.js', '.ts', '.html', '.css'
  };

  static const excludedDirectoryNames = {
    '.git', '.venv', 'venv', 'node_modules', 'build', '.dart_tool', '.idea', '.vscode', 'models', '__pycache__'
  };

  Future<void> load({required String repoRoot}) async {
    _entries.clear();
    await _loadBundled();
    if (Platform.isLinux && repoRoot.trim().isNotEmpty) {
      await _loadLiveRepo(expandHome(repoRoot));
    }
  }

  Future<void> _loadBundled() async {
    try {
      final raw = await rootBundle.loadString('assets/knowledge/mom_knowledge.jsonl');
      for (final line in const LineSplitter().convert(raw)) {
        if (line.trim().isEmpty) continue;
        try {
          final value = jsonDecode(line);
          if (value is Map<String, dynamic>) {
            final path = value['path'];
            final text = value['text'];
            if (path is String && text is String && text.trim().isNotEmpty) {
              _entries.add(KnowledgeEntry(path, text));
            }
          }
        } catch (_) {}
      }
    } catch (_) {
      // The build still runs if the optional generated knowledge bundle is absent.
    }
  }

  Future<void> _loadLiveRepo(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) return;
    final bundledPaths = _entries.map((e) => e.path).toSet();
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final relative = entity.path.substring(root.path.length).replaceFirst(RegExp(r'^[/\\]+'), '');
      final parts = relative.split(RegExp(r'[/\\]+'));
      if (parts.any(excludedDirectoryNames.contains)) continue;
      if (bundledPaths.contains(relative)) continue;
      final lower = relative.toLowerCase();
      if (!allowedExtensions.any(lower.endsWith)) continue;
      try {
        if (await entity.length() > 160000) continue;
        final text = await entity.readAsString();
        if (text.trim().isNotEmpty) _entries.add(KnowledgeEntry(relative, text));
      } catch (_) {}
    }
  }

  List<KnowledgeHit> search(String query, {int limit = 6}) {
    final tokens = _tokens(query);
    if (tokens.isEmpty) return const [];
    final hits = <KnowledgeHit>[];
    for (final entry in _entries) {
      final path = entry.path.toLowerCase();
      final text = entry.text.toLowerCase();
      var score = 0;
      for (final token in tokens) {
        if (path.contains(token)) score += 8;
        final count = _countOccurrences(text, token);
        score += count > 6 ? 6 : count;
      }
      if (score > 0) hits.add(KnowledgeHit(entry, score));
    }
    hits.sort((a, b) => b.score.compareTo(a.score));
    return hits.take(limit).toList(growable: false);
  }

  String contextFor(String query, {int maxChars = 10000}) {
    final buffer = StringBuffer();
    for (final hit in search(query)) {
      final chunk = hit.entry.text.length > 2200 ? hit.entry.text.substring(0, 2200) : hit.entry.text;
      final addition = '\n\nSOURCE: ${hit.entry.path}\n$chunk';
      if (buffer.length + addition.length > maxChars) break;
      buffer.write(addition);
    }
    return buffer.toString().trim();
  }

  static Set<String> _tokens(String value) => RegExp(r'[A-Za-z0-9_]{3,}')
      .allMatches(value.toLowerCase())
      .map((m) => m.group(0)!)
      .where((t) => !const {'the', 'and', 'that', 'this', 'with', 'from', 'have', 'what', 'when', 'your', 'you', 'for'}.contains(t))
      .toSet();

  static int _countOccurrences(String haystack, String needle) {
    var count = 0;
    var start = 0;
    while (count < 8) {
      final found = haystack.indexOf(needle, start);
      if (found < 0) break;
      count++;
      start = found + needle.length;
    }
    return count;
  }
}
