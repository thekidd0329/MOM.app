import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/config.dart';
import 'src/diagnostics.dart';
import 'src/knowledge.dart';
import 'src/llama_manager.dart';
import 'src/local_store.dart';
import 'src/mic_status.dart';
import 'src/model_client.dart';
import 'src/mom_home_screen.dart';
import 'src/mom_settings_screen.dart';
import 'src/startup_discovery/discovery_models.dart';
import 'src/startup_discovery/discovery_screen.dart';
import 'src/startup_discovery/discovery_store.dart';
import 'src/startup_intro_screen.dart';
import 'src/sync_client.dart';
import 'src/voice_service.dart';

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
  final MomMicrophoneProbe _micProbe = MomMicrophoneProbe();
  final StartupIntroStore _startupIntroStore = StartupIntroStore();
  final MomVoiceService _voice = MomVoiceService();

  MomConfig? _config;
  MomSyncClient? _sync;
  String _systemPrompt =
      'MOM exists to act in the direct best interest of her user; every response should serve that purpose.';
  String _sessionId = '';
  List<ChatTurn> _turns = [];
  List<ChatTurn> _captionTurns = [];
  DiscoveryProgress _discovery = const DiscoveryProgress();
  MomMicrophoneStatus _microphone = const MomMicrophoneStatus.unknown();
  bool _booting = true;
  bool _startupIntroKnown = false;
  bool _startupIntroComplete = false;
  bool _returningBoot = false;
  bool _busy = false;
  bool _listening = false;
  DateTime? _returningBootShownAt;
  String _status = 'starting';

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

      _startupIntroComplete = await _startupIntroStore.isComplete();
      _startupIntroKnown = true;
      _returningBoot = _startupIntroComplete;
      if (_returningBoot) {
        _returningBootShownAt = DateTime.now();
        if (mounted) setState(() {});
      }

      if (_startupIntroComplete) {
        final savedName = await _startupIntroStore.savedName();
        final strongLanguage = await _startupIntroStore.allowsStrongLanguage();
        final momStyle = await _startupIntroStore.savedMomStyle();
        if (savedName.isNotEmpty) {
          _systemPrompt = '$_systemPrompt\n\nThe person wants to be called $savedName.';
        }
        _systemPrompt =
            '$_systemPrompt\nLanguage preference: ${strongLanguage ? 'strong language is allowed' : 'keep language clean'}.\nPreferred mothering style: ${_momStylePrompt(momStyle)}.';
      }

      _discovery = await _discoveryStore.load();
      if (_discovery.complete) {
        _systemPrompt = '$_systemPrompt\n\n${_discovery.toPromptSummary()}';
      }

      await _knowledge.load(repoRoot: config.repoRoot);
      _sync = MomSyncClient(syncUrl: config.syncUrl);
      _sessionId = await _store.currentSessionId();
      _turns = await _store.loadSession(_sessionId, limit: 200);
      _captionTurns = _turns
          .where((turn) => turn.role == 'assistant')
          .toList(growable: false);
      _microphone = await _micProbe.probe();
      await _voice.initialize();

      if (Platform.isLinux && config.useLocalLlama) {
        if (mounted) setState(() => _status = 'starting local brain');
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
          'microphone': _microphone.toJson(),
        }));
      }
    } catch (_) {
      _status = 'startup issue';
    } finally {
      if (_returningBoot && _returningBootShownAt != null) {
        const minimumSplash = Duration(milliseconds: 900);
        final elapsed = DateTime.now().difference(_returningBootShownAt!);
        if (elapsed < minimumSplash) {
          await Future<void>.delayed(minimumSplash - elapsed);
        }
      }
      if (mounted) setState(() => _booting = false);
    }
  }

  String _momStylePrompt(String value) {
    return switch (value) {
      'gentle' => 'gentle, patient, and reassuring',
      'tough_love' => 'blunt, direct, and willing to use tough love',
      'adaptive' => 'observe the person and adapt naturally over time',
      _ => 'balance comfort with honest, direct guidance',
    };
  }

  Future<void> _completeStartupIntro({
    required bool allowStrongLanguage,
    required String name,
  }) async {
    await _startupIntroStore.complete(
      allowStrongLanguage: allowStrongLanguage,
      name: name,
    );
    if (!mounted) return;
    final momStyle = await _startupIntroStore.savedMomStyle();
    if (!mounted) return;
    setState(() {
      _startupIntroComplete = true;
      _systemPrompt =
          '$_systemPrompt\n\nThe person wants to be called $name.\nLanguage preference: ${allowStrongLanguage ? 'strong language is allowed' : 'keep language clean'}.\nPreferred mothering style: ${_momStylePrompt(momStyle)}.';
    });
  }

  Future<void> _completeDiscovery(DiscoveryProgress progress) async {
    final completed =
        progress.complete ? progress : progress.copyWith(complete: true);
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

  Future<void> _safeEvent(
    String name, {
    Map<String, dynamic> payload = const {},
  }) async {
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

  Future<void> _probeMicrophone(bool requestPermission) async {
    final next = await _micProbe.probe(requestPermission: requestPermission);
    if (mounted) setState(() => _microphone = next);
    unawaited(_safeEvent('microphone_status', payload: {
      'permission_requested': requestPermission,
      ...next.toJson(),
    }));
  }

  Future<void> _toggleListening() async {
    if (_listening) {
      await _voice.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }

    await _probeMicrophone(true);
    if (!_microphone.permissionGranted) return;
    await _voice.listen(
      onState: (value) {
        if (mounted) setState(() => _listening = value);
      },
      onFinal: (text) {
        if (mounted) setState(() => _listening = false);
        unawaited(_send(text));
      },
    );
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
      metadata: {
        'input_mode': 'text',
        'microphone': _microphone.toJson(),
      },
    );
    setState(() {
      _busy = true;
      _status = 'thinking';
      _turns = [..._turns, userTurn];
    });
    await _store.append(userTurn);
    unawaited(_safeSyncTurn(userTurn));
    unawaited(_safeEvent('chat_sent', payload: {
      'characters': text.length,
      'input_mode': 'text',
      'microphone': _microphone.toJson(),
    }));

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
          'output_mode': 'orb_caption',
          'caption_display': 'immediate',
          'caption_persists': true,
        },
      );
      await _store.append(assistantTurn);
      if (mounted) {
        setState(() {
          _turns = [..._turns, assistantTurn];
          _captionTurns = [..._captionTurns, assistantTurn];
          _status = 'online';
        });
      }
      unawaited(_safeSyncTurn(assistantTurn, model: reply.model));
      unawaited(_voice.speak(reply.text).catchError((_) {}));
      unawaited(_safeEvent('response_received', payload: {
        'latency_ms': DateTime.now().difference(started).inMilliseconds,
        'model': reply.model,
        'response_characters': reply.text.length,
        'knowledge_characters': knowledge.length,
        'output_mode': 'orb_caption',
      }));
    } catch (error) {
      final failure = ChatTurn(
        sessionId: _sessionId,
        role: 'assistant',
        content:
            'Something between me and my brain is not answering. Try that again in a second.',
        createdAt: DateTime.now(),
        metadata: const {
          'local_error': true,
          'output_mode': 'orb_caption',
        },
      );
      await _store.append(failure);
      if (mounted) {
        setState(() {
          _turns = [..._turns, failure];
          _captionTurns = [..._captionTurns, failure];
          _status = 'offline';
        });
      }
      unawaited(_safeEvent(
        'model_error',
        payload: {'error_type': error.runtimeType.toString()},
      ));
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    final current = _config;
    final sync = _sync;
    if (current == null || sync == null) return;
    final updated = await Navigator.of(context).push<MomConfig>(
      MaterialPageRoute(
        builder: (_) => MomSettingsScreen(
          initial: current.copy(),
          sync: sync,
        ),
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
    unawaited(_micProbe.dispose());
    unawaited(_voice.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFFA855F7);
    final lightScheme = ColorScheme.fromSeed(
      seedColor: purple,
      brightness: Brightness.light,
    );
    final darkScheme = ColorScheme.fromSeed(
      seedColor: purple,
      brightness: Brightness.dark,
    );

    Widget home;
    if (_booting) {
      home = _startupIntroKnown && _returningBoot
          ? MomBootScreen(status: _status)
          : const Scaffold(
              backgroundColor: Colors.black,
              body: SizedBox.expand(),
            );
    } else if (!_startupIntroComplete) {
      home = StartupIntroScreen(
        onComplete: _completeStartupIntro,
        onSpeak: (text) => _voice.speak(text).catchError((_) {}),
      );
    } else if (!_discovery.complete) {
      home = StartupDiscoveryScreen(
        onComplete: _completeDiscovery,
        onSpeak: (text) => _voice.speak(text).catchError((_) {}),
      );
    } else {
      home = MomHomeScreen(
        turns: _captionTurns,
        busy: _busy,
        listening: _listening,
        status: _status,
        microphone: _microphone,
        onSend: _send,
        onSettings: _openSettings,
        onDiagnostics: _openDiagnostics,
        onProbeMicrophone: _probeMicrophone,
        onMicTap: _toggleListening,
        playStartupEntrance: _returningBoot,
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MOM',
      themeMode: ThemeMode.system,
      theme: ThemeData(
        colorScheme: lightScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
      ),
      darkTheme: ThemeData(
        colorScheme: darkScheme,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: home,
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
