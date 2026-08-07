import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/config.dart';
import 'src/diagnostics.dart';
import 'src/knowledge.dart';
import 'src/llama_manager.dart';
import 'src/local_store.dart';
import 'src/model_client.dart';
import 'src/startup_discovery/discovery_models.dart';
import 'src/startup_discovery/discovery_screen.dart';
import 'src/startup_discovery/discovery_store.dart';
import 'src/sync_client.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MomApp());
}

class MomApp extends StatefulWidget {
  const MomApp({super.key});

  @override
  State<MomApp> createState() => _MomAppState();
}

class _MomAppState extends State<MomApp> {
  final ConfigStore _configStore = ConfigStore();
  final ConversationStore _store = ConversationStore();
  final KnowledgeService _knowledge = KnowledgeService();
  final LlamaManager _llama = LlamaManager();
  final DiscoveryProgressStore _discoveryStore = DiscoveryProgressStore();

  MomConfig? _config;
  MomSyncClient? _sync;
  String _systemPrompt = 'You are MOM. Be useful, truthful, persistent, and grounded.';
  String _sessionId = '';
  List<ChatTurn> _turns = [];
  DiscoveryProgress _discovery = const DiscoveryProgress();
  bool _booting = true;
  bool _busy = false;
  String _status = 'starting';
  String _activeModel = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final config = await _configStore.load();
      _config = config;
      try {
        _systemPrompt = await rootBundle.loadString('assets/runtime_prompt.md');
      } catch (_) {}

      _discovery = await _discoveryStore.load();
      if (_discovery.complete) {
        _systemPrompt = '$_systemPrompt\n\n${_discovery.toPromptSummary()}';
      }

      await _knowledge.load(repoRoot: config.repoRoot);
      _sync = MomSyncClient(syncUrl: config.syncUrl);
      _sessionId = await _store.currentSessionId();
      _turns = await _store.loadSession(_sessionId, limit: 200);

      if (Platform.isLinux && config.useLocalLlama) {
        setState(() => _status = 'starting local brain');
        final local = await _llama.ensureRunning(config);
        _status = local.running ? 'online' : local.message;
      } else {
        _status = 'online';
      }

      if (config.productTelemetry) {
        unawaited(_safeEvent('app_launch', payload: {
          'platform': Platform.operatingSystem,
          'knowledge_documents': _knowledge.entryCount,
          'local_llama': config.useLocalLlama,
          'startup_discovery_complete': _discovery.complete,
          'startup_discovery_answers': _discovery.answeredCount,
        }));
      }
    } catch (error) {
      _status = 'startup issue: $error';
    } finally {
      if (mounted) setState(() => _booting = false);
    }
  }

  Future<void> _completeDiscovery(DiscoveryProgress progress) async {
    final completed = progress.complete ? progress : progress.copyWith(complete: true);
    await _discoveryStore.save(completed);
    if (!mounted) return;

    setState(() {
      _discovery = completed;
      _systemPrompt = '$_systemPrompt\n\n${completed.toPromptSummary()}';
      _status = 'online';
    });

    unawaited(_safeEvent('startup_discovery_complete', payload: {
      'answers': completed.answeredCount,
      'average_certainty': completed.averageCertainty,
    }));
  }

  Future<void> _safeEvent(String name, {Map<String, dynamic> payload = const {}}) async {
    final config = _config;
    final sync = _sync;
    if (config == null || sync == null || !config.productTelemetry) return;
    try {
      await sync.event(
        name,
        sessionId: _sessionId.isEmpty ? null : _sessionId,
        payload: payload,
      );
    } catch (_) {}
  }

  Future<void> _safeSyncTurn(ChatTurn turn, {String model = ''}) async {
    final config = _config;
    final sync = _sync;
    if (config == null || sync == null || !config.cloudChatSync) return;
    try {
      await sync.syncChat(
        sessionId: turn.sessionId,
        role: turn.role,
        content: turn.content,
        modelProvider: config.modelApiBase,
        modelName: model.isEmpty ? config.modelName : model,
        metadata: turn.metadata,
      );
    } catch (_) {
      if (mounted) setState(() => _status = 'cloud sync delayed');
    }
  }

  Future<void> _send(String text) async {
    final config = _config;
    if (config == null || _busy || text.trim().isEmpty) return;

    final issues = config.validate().where((e) => e.fatal).toList();
    if (issues.isNotEmpty) {
      setState(() => _status = 'settings need attention');
      await _openSettings();
      return;
    }

    final prior = List<ChatTurn>.from(_turns);
    final userTurn = ChatTurn(
      sessionId: _sessionId,
      role: 'user',
      content: text.trim(),
      createdAt: DateTime.now(),
    );

    setState(() {
      _busy = true;
      _status = 'thinking';
      _turns = [..._turns, userTurn];
    });

    await _store.append(userTurn);
    unawaited(_safeSyncTurn(userTurn));
    unawaited(_safeEvent('chat_sent', payload: {'characters': text.length}));

    final started = DateTime.now();
    final client = ModelClient(config.copy());
    try {
      final knowledge = _knowledge.contextFor(text);
      final reply = await client.chat(
        systemPrompt: _systemPrompt,
        history: prior,
        userText: text.trim(),
        knowledgeContext: knowledge,
      );

      final assistantTurn = ChatTurn(
        sessionId: _sessionId,
        role: 'assistant',
        content: reply.text,
        createdAt: DateTime.now(),
        metadata: {
          'model': reply.model,
          'knowledge_chars': knowledge.length,
        },
      );

      await _store.append(assistantTurn);
      if (mounted) {
        setState(() {
          _turns = [..._turns, assistantTurn];
          _activeModel = reply.model;
          _status = 'online';
        });
      }

      unawaited(_safeSyncTurn(assistantTurn, model: reply.model));
      unawaited(_safeEvent('response_received', payload: {
        'latency_ms': DateTime.now().difference(started).inMilliseconds,
        'model': reply.model,
        'response_characters': reply.text.length,
        'knowledge_characters': knowledge.length,
      }));
    } catch (error) {
      final failure = ChatTurn(
        sessionId: _sessionId,
        role: 'assistant',
        content: 'I cannot reach my brain yet: $error',
        createdAt: DateTime.now(),
        metadata: const {'local_error': true},
      );

      await _store.append(failure);
      if (mounted) {
        setState(() {
          _turns = [..._turns, failure];
          _status = 'model unavailable';
        });
      }
      unawaited(_safeEvent('model_error', payload: {
        'error_type': error.runtimeType.toString(),
      }));
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newConversation() async {
    _sessionId = await _store.newSession();
    setState(() {
      _turns = [];
      _activeModel = '';
      _status = 'online';
    });
    unawaited(_safeEvent('new_conversation'));
  }

  Future<void> _openSettings() async {
    final current = _config;
    if (current == null) return;

    final updated = await Navigator.of(context).push<MomConfig>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(initial: current.copy()),
      ),
    );
    if (updated == null) return;

    await _configStore.save(updated);
    _sync?.close();
    _sync = MomSyncClient(syncUrl: updated.syncUrl);
    _config = updated;
    await _knowledge.load(repoRoot: updated.repoRoot);

    if (Platform.isLinux && updated.useLocalLlama) {
      final status = await _llama.ensureRunning(updated);
      _status = status.running ? 'online' : status.message;
    }
    if (mounted) setState(() {});
  }

  Future<void> _openDiagnostics() async {
    final config = _config;
    final sync = _sync;
    if (config == null || sync == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiagnosticsScreen(
          runner: DiagnosticsRunner(
            config: config,
            store: _store,
            knowledge: _knowledge,
            sync: sync,
            llama: _llama,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _sync?.close();
    _llama.stopIfStartedByMom();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFE46C7A),
      brightness: Brightness.dark,
    );

    Widget home;
    if (_booting) {
      home = Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 18),
              Text(_status),
            ],
          ),
        ),
      );
    } else if (!_discovery.complete) {
      home = StartupDiscoveryScreen(onComplete: _completeDiscovery);
    } else {
      home = ChatScreen(
        turns: _turns,
        busy: _busy,
        status: _status,
        activeModel: _activeModel,
        onSend: _send,
        onSettings: _openSettings,
        onDiagnostics: _openDiagnostics,
        onNewConversation: _newConversation,
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MOM',
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      home: home,
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.turns,
    required this.busy,
    required this.status,
    required this.activeModel,
    required this.onSend,
    required this.onSettings,
    required this.onDiagnostics,
    required this.onNewConversation,
  });

  final List<ChatTurn> turns;
  final bool busy;
  final String status;
  final String activeModel;
  final Future<void> Function(String) onSend;
  final VoidCallback onSettings;
  final VoidCallback onDiagnostics;
  final VoidCallback onNewConversation;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant ChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turns.length != widget.turns.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    _controller.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('MOM', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(widget.status, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
        actions: [
          if (widget.activeModel.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  widget.activeModel,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          IconButton(
            tooltip: 'New conversation',
            onPressed: widget.onNewConversation,
            icon: const Icon(Icons.add_comment_outlined),
          ),
          IconButton(
            tooltip: 'Diagnostics',
            onPressed: widget.onDiagnostics,
            icon: const Icon(Icons.monitor_heart_outlined),
          ),
          IconButton(
            tooltip: 'Settings',
            onPressed: widget.onSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.turns.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text(
                        'MOM is awake.\n\nText naturally. She can use the MOM repository as reference knowledge and keeps local conversation history.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    itemCount: widget.turns.length,
                    itemBuilder: (context, index) {
                      final turn = widget.turns[index];
                      final user = turn.role == 'user';
                      return Align(
                        alignment: user ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 760),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: user
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Theme.of(context).colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(18).copyWith(
                              bottomRight: user ? const Radius.circular(5) : null,
                              bottomLeft: user ? null : const Radius.circular(5),
                            ),
                          ),
                          child: SelectableText(turn.content),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !widget.busy,
                      minLines: 1,
                      maxLines: 6,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Text MOM…',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        if (!Platform.isAndroid && !Platform.isIOS) _submit();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: widget.busy ? null : _submit,
                    icon: widget.busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_upward),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.initial});

  final MomConfig initial;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late MomConfig config;
  late final TextEditingController apiBase;
  late final TextEditingController apiKey;
  late final TextEditingController model;
  late final TextEditingController modelsDir;
  late final TextEditingController repoRoot;

  @override
  void initState() {
    super.initState();
    config = widget.initial.copy();
    apiBase = TextEditingController(text: config.modelApiBase);
    apiKey = TextEditingController(text: config.modelApiKey);
    model = TextEditingController(text: config.modelName);
    modelsDir = TextEditingController(text: config.modelsDir);
    repoRoot = TextEditingController(text: config.repoRoot);
  }

  @override
  void dispose() {
    apiBase.dispose();
    apiKey.dispose();
    model.dispose();
    modelsDir.dispose();
    repoRoot.dispose();
    super.dispose();
  }

  void _save() {
    config.modelApiBase = apiBase.text.trim();
    config.modelApiKey = apiKey.text.trim();
    config.modelName = model.text.trim();
    config.modelsDir = modelsDir.text.trim();
    config.repoRoot = repoRoot.text.trim();

    final fatal = config.validate().where((i) => i.fatal).toList();
    if (fatal.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fatal.map((e) => e.message).join('\n'))),
      );
      return;
    }
    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MOM settings'),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          if (Platform.isLinux)
            SwitchListTile(
              title: const Text('Start local llama.cpp automatically'),
              subtitle: const Text(
                'MOM starts the local router and discovers GGUF models without a terminal.',
              ),
              value: config.useLocalLlama,
              onChanged: (v) => setState(() => config.useLocalLlama = v),
            ),
          TextField(
            controller: apiBase,
            decoration: const InputDecoration(
              labelText: 'Model API URL',
              helperText: 'Linux local default: http://127.0.0.1:8080/v1 · phones: use HTTPS hosted endpoint',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: model,
            decoration: const InputDecoration(
              labelText: 'Model name',
              helperText: 'Leave blank to use the first model exposed by the endpoint.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: apiKey,
            obscureText: true,
            enableSuggestions: false,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Model API key',
              helperText: 'Stored in platform secure storage, never Supabase telemetry.',
            ),
          ),
          if (Platform.isLinux) ...[
            const SizedBox(height: 12),
            TextField(
              controller: modelsDir,
              decoration: const InputDecoration(labelText: 'GGUF model folder'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: repoRoot,
              decoration: const InputDecoration(
                labelText: 'Live MOM repository folder',
                helperText: 'Desktop MOM reads supported text/code files here as reference knowledge.',
              ),
            ),
          ],
          const Divider(height: 36),
          SwitchListTile(
            title: const Text('Cloud conversation sync'),
            subtitle: const Text(
              'Mirrors chats to MOM Supabase through the per-install device token.',
            ),
            value: config.cloudChatSync,
            onChanged: (v) => setState(() => config.cloudChatSync = v),
          ),
          SwitchListTile(
            title: const Text('Product/runtime data collection'),
            subtitle: const Text(
              'Collects app launches, latency, model/error type, platform, and document counts. API keys are excluded.',
            ),
            value: config.productTelemetry,
            onChanged: (v) => setState(() => config.productTelemetry = v),
          ),
          const SizedBox(height: 12),
          Text(
            'Supabase sync: ${config.syncUrl}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.runner});

  final DiagnosticsRunner runner;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  List<DiagnosticResult>? results;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => results = null);
    final value = await widget.runner.run();
    if (mounted) setState(() => results = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MOM diagnostics'),
        actions: [
          IconButton(onPressed: _run, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: results == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: results!.length,
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (context, index) {
                final result = results![index];
                final icon = result.ok
                    ? Icons.check_circle
                    : result.warning
                        ? Icons.warning_amber
                        : Icons.cancel;
                final color = result.ok
                    ? Colors.green
                    : result.warning
                        ? Colors.amber
                        : Colors.red;

                return ListTile(
                  leading: Icon(icon, color: color),
                  title: Text(result.name),
                  subtitle: Text(result.detail),
                );
              },
            ),
    );
  }
}
