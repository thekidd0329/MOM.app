import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ChatTurn {
  const ChatTurn({
    required this.sessionId,
    required this.role,
    required this.content,
    required this.createdAt,
    this.metadata = const {},
  });

  final String sessionId;
  final String role;
  final String content;
  final DateTime createdAt;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'role': role,
        'content': content,
        'created_at': createdAt.toUtc().toIso8601String(),
        'metadata': metadata,
      };

  static ChatTurn? fromJson(Map<String, dynamic> value) {
    final sessionId = value['session_id'];
    final role = value['role'];
    final content = value['content'];
    final createdAt = DateTime.tryParse('${value['created_at'] ?? ''}');
    if (sessionId is! String || role is! String || content is! String || createdAt == null) {
      return null;
    }
    final rawMetadata = value['metadata'];
    return ChatTurn(
      sessionId: sessionId,
      role: role,
      content: content,
      createdAt: createdAt,
      metadata: rawMetadata is Map<String, dynamic> ? rawMetadata : const {},
    );
  }
}

class ConversationStore {
  File? _file;

  Future<File> _ensureFile() async {
    if (_file != null) return _file!;
    final root = await getApplicationSupportDirectory();
    final dir = Directory('${root.path}/mom');
    await dir.create(recursive: true);
    _file = File('${dir.path}/conversations.jsonl');
    if (!await _file!.exists()) await _file!.create(recursive: true);
    return _file!;
  }

  Future<String> currentSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('current_session_id');
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString('current_session_id', id);
    }
    return id;
  }

  Future<String> newSession() async {
    final prefs = await SharedPreferences.getInstance();
    final id = const Uuid().v4();
    await prefs.setString('current_session_id', id);
    return id;
  }

  Future<void> append(ChatTurn turn) async {
    final file = await _ensureFile();
    await file.writeAsString('${jsonEncode(turn.toJson())}\n', mode: FileMode.append, flush: true);
  }

  Future<List<ChatTurn>> loadSession(String sessionId, {int limit = 200}) async {
    final file = await _ensureFile();
    final turns = <ChatTurn>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(line);
        if (decoded is! Map<String, dynamic>) continue;
        final turn = ChatTurn.fromJson(decoded);
        if (turn != null && turn.sessionId == sessionId) turns.add(turn);
      } catch (_) {
        // Ignore a damaged line rather than losing the rest of the transcript.
      }
    }
    if (turns.length <= limit) return turns;
    return turns.sublist(turns.length - limit);
  }

  Future<bool> writable() async {
    try {
      final file = await _ensureFile();
      await file.writeAsString('', mode: FileMode.append, flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
