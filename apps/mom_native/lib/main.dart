import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/brain_stream_client.dart';
import 'src/config.dart';
import 'src/diagnostics.dart';
import 'src/knowledge.dart';
import 'src/llama_manager.dart';
import 'src/local_store.dart';
import 'src/mic_status.dart';
import 'src/model_client.dart';
import 'src/mom_home_screen.dart';
import 'src/mom_login_screen.dart';
import 'src/startup_discovery/discovery_models.dart';
import 'src/startup_discovery/discovery_screen.dart';
import 'src/startup_discovery/discovery_store.dart';
import 'src/startup_intro_screen.dart';
import 'src/sync_client.dart';
import 'src/voice_service.dart';
import 'src/voice_state.dart';

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
  final MomVoiceStateMachine _voiceState = MomVoiceStateMachine();

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
  bool _startupIntroComplete = false;
  String _status = 'starting';

  bool get _busy => _voiceState.blocksInput;
  bool get _listening => _voiceState.listening;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  void _setVoiceState(MomVoiceState next, {String? status}) {
    if (_voiceState.state == next) {
      if (status != null && mounted) setState(() => _status = status);
      return;
    }
    void apply() {
      _voiceState.transition(next);
      _status = status ?? _voiceState.label;
    }

    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  void _recoverVoiceState({String status = 'online'}) {
    void apply() {
      _voiceState.recover();
      _status = status;
    }

    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  Future<void> _voiceFailed(Object error, {required String fallbackStage}) async {
    final stage = error is MomVoiceException ? error.stage : fallbackStage;
    if (_voiceState.state != MomVoiceState.error) {
      _setVoiceState(
        MomVoiceState.error,
        status: 'Voice error · text still works',
      );
    } else if (mounted) {
      setState(() => _status = 'Voice error · text still works');
    }
    await _safeEvent('voice_error', payload: {
      'stage': stage,
      'error_type': error.runtimeType.toString(),
    });
  }

  Future<void> _speakText(String text) async {
    if (text.trim().isEmpty) return;
    if (_voiceState.state == MomVoiceState.error) {
      _recoverVoiceState();
    }
    if (_voiceState.state == MomVoiceState.idle ||
        _voiceState.state == MomVoiceState.thinking) {
      _setVoiceState(MomVoiceState.synthesizing);
    } else if (_voiceState.state != MomVoiceState.synthesizing) {
      return;
    }

    try {
      await _voice.speak(
        text,
        onSynthesisStart: () {
          if (_voiceState.state == MomVoiceState.thinking ||
              _voiceState.state == MomVoiceState.idle) {
            _setVoiceState(MomVoiceState.synthesizing);
          }
        },
        onPlaybackStart: () {
          if (_voiceState.state == MomVoiceState.synthesizing) {
            _setVoiceState(MomVoiceState.speaking);
          }
        },
      );
      if (_voiceState.state == MomVoiceState.speaking ||
          _voiceState.state == MomVoiceState.synthesizing) {
        _setVoiceState(MomVoiceState.idle);
      }
    } catch (error) {
      await _voiceFailed(error, fallbackStage: 'output');
    }
  }

  Future<void> _speakDeltaStream(Stream<String> deltas) async {
    try {
      await _voice.speakStream(
        deltas,
        onSynthesisStart: () {
          if (_voiceState.state == MomVoiceState.thinking ||
              _voiceState.state == MomVoiceState.idle) {
            _setVoiceState(MomVoiceState.synthesizing);
          }
        },
        onPlaybackStart: () {
          if (_voiceState.state == MomVoiceState.synthesizing) {
            _setVoiceState(MomVoiceState.speaking);
          }
        },
      );
      if (_voiceState.state == MomVoiceState.speaking ||
          _voiceState.state == MomVoiceState.synthesizing) {
        _setVoiceState(MomVoiceState.idle);
      }
    } catch (error) {
      await _voiceFailed(error, fallbackStage: 'stream_playback');
    }
  }

  Future<void> _bootstrap() async {
    try {
      final config = await _configStore.load();
      _config = config;
      try {
        _systemPrompt = await rootBundle.loadString('assets/runtime_prompt.md');
      } catch (_) {}

      _startupIntroComplete = await _startupIntroStore.isComplete();
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
          'microphone': _microphone.toJson(),
        }));
      }
    } catch (_) {
      _status = 'startup issue';
    } finally {
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
    if (_voiceState.state == MomVoiceState.listening) {
      await _voice.stopListening();
      _setVoiceState(MomVoiceState.idle);
      return;
    }

    if (_voiceState.state == MomVoiceState.error) {
      _recoverVoiceState();
    }
    if (_voiceState.state != MomVoiceState.idle) return;

    await _probeMicrophone(true);
    if (!_microphone.permissionGranted) {
      if (mounted) setState(() => _status = 'Microphone permission needed');
      return;
    }

    _setVoiceState(MomVoiceState.listening);
    try {
      await _voice.listen(
        onState: (value) {
          if (value && _voiceState.state == MomVoiceState.idle) {
            _setVoiceState(MomVoiceState.listening);
          } else if (!value &&
              _voiceState.state == MomVoiceState.listening) {
            _setVoiceState(MomVoiceState.idle);
          }
        },
        onFinal: (text) {
          if (_voiceState.state == MomVoiceState.listening) {
            _setVoiceState(MomVoiceState.idle);
          }
          unawaited(_send(text, inputMode: 'voice'));
        },
      );
    } catch (error) {
      await _voiceFailed(error, fallbackStage: 'speech_recognition');
    }
  }

  Future<void> _send(String text, {String inputMode = 'text'}) async {
    final config = _config;
    final sync = _sync;
    if (config == null || sync == null || text.trim().isEmpty) return;

    if (_voiceState.state == MomVoiceState.listening) {
      await _voice.stopListening();
      _setVoiceState(MomVoiceState.idle);
    }
    if (_voiceState.state == MomVoiceState.error) {
      _recoverVoiceState();
    }
    if (_voiceState.state != MomVoiceState.idle) return;

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
        'input_mode': inputMode,
        'microphone': _microphone.toJson(),
      },
    );
    _setVoiceState(MomVoiceState.thinking);
    if (mounted) {
      setState(() => _turns = [..._turns, userTurn]);
    } else {
      _turns = [..._turns, userTurn];
    }
    await _store.append(userTurn);
    unawaited(_safeSyncTurn(userTurn));
    unawaited(_safeEvent('chat_sent', payload: {
      'characters': text.length,
      'input_mode': inputMode,
      'microphone': _microphone.toJson(),
    }));

    final started = DateTime.now();
    final client = ModelClient(config.copy());
    MomBrainStreamClient? streamClient;
    StreamController<String>? deltaController;
    Future<void>? speechFuture;
    try {
      final useLocal = Platform.isLinux && config.useLocalLlama;
      final knowledge = useLocal ? _knowledge.contextFor(text) : '';
      ModelReply reply;

      if (useLocal) {
        reply = await client.chat(
          systemPrompt: _systemPrompt,
          history: prior,
          userText: text.trim(),
          knowledgeContext: knowledge,
        );
      } else {
        streamClient = MomBrainStreamClient(
          syncUrl: config.syncUrl,
          syncClient: sync,
        );
        deltaController = StreamController<String>();
        speechFuture = _speakDeltaStream(deltaController.stream);

        Object? streamError;
        StackTrace? streamStack;
        BrainReply? streamedReply;
        try {
          streamedReply = await streamClient.chat(
            history: prior
                .where((turn) =>
                    turn.role == 'user' || turn.role == 'assistant')
                .map((turn) => {'role': turn.role, 'content': turn.content})
                .toList(growable: false),
            userText: text.trim(),
            temperature: config.temperature,
            maxHistory: config.maxHistory,
            onDelta: deltaController.add,
          );
        } catch (error, stack) {
          streamError = error;
          streamStack = stack;
        } finally {
          await deltaController.close();
        }

        if (streamError != null) {
          await speechFuture;
          Error.throwWithStackTrace(streamError, streamStack!);
        }
        final completed = streamedReply!;
        reply = ModelReply(text: completed.text, model: completed.model);
      }

      final assistantTurn = ChatTurn(
        sessionId: _sessionId,
        role: 'assistant',
        content: reply.text,
        createdAt: DateTime.now(),
        metadata: {
          'model': reply.model,
          'knowledge_chars': knowledge.length,
          'output_mode': 'orb_caption_and_voice',
          'caption_display': 'immediate',
          'caption_persists': true,
          'brain_transport': useLocal ? 'local_complete' : 'secure_sse',
        },
      );
      await _store.append(assistantTurn);
      if (mounted) {
        setState(() {
          _turns = [..._turns, assistantTurn];
          _captionTurns = [..._captionTurns, assistantTurn];
        });
      } else {
        _turns = [..._turns, assistantTurn];
        _captionTurns = [..._captionTurns, assistantTurn];
      }
      unawaited(_safeSyncTurn(assistantTurn, model: reply.model));

      if (useLocal) {
        await _speakText(reply.text);
      } else if (speechFuture != null) {
        await speechFuture;
      }

      unawaited(_safeEvent('response_received', payload: {
        'latency_ms': DateTime.now().difference(started).inMilliseconds,
        'model': reply.model,
        'response_characters': reply.text.length,
        'knowledge_characters': knowledge.length,
        'output_mode': 'orb_caption_and_voice',
        'brain_transport': useLocal ? 'local_complete' : 'secure_sse',
      }));
    } catch (error) {
      if (_voiceState.state == MomVoiceState.thinking) {
        _recoverVoiceState();
      }
      final modelFailure = classifyModelFailure(error);
      final failure = ChatTurn(
        sessionId: _sessionId,
        role: 'assistant',
        content: modelFailure.userMessage,
        createdAt: DateTime.now(),
        metadata: {
          'local_error': true,
          'model_error_code': modelFailure.code,
          'model_error_stage': modelFailure.stage,
          'model_error_retryable': modelFailure.retryable,
          'output_mode': 'orb_caption',
        },
      );
      await _store.append(failure);
      if (mounted) {
        setState(() {
          _turns = [..._turns, failure];
          _captionTurns = [..._captionTurns, failure];
          _status = switch (modelFailure.kind) {
            ModelFailureKind.identity => 'identity reconnect failed',
            ModelFailureKind.network => 'network issue',
            ModelFailureKind.timeout => 'brain timeout',
            ModelFailureKind.providerBusy => 'provider busy',
            ModelFailureKind.provider => 'provider issue',
            ModelFailureKind.service => 'brain service issue',
            ModelFailureKind.modelDiscovery => 'model unavailable',
            ModelFailureKind.response => 'brain response issue',
            ModelFailureKind.configuration => 'brain configuration issue',
            ModelFailureKind.unknown => 'brain issue',
          };
        });
      }
      unawaited(_safeEvent(
        'model_error',
        payload: {
          'error_code': modelFailure.code,
          'error_stage': modelFailure.stage,
          'retryable': modelFailure.retryable,
          if (modelFailure.statusCode != null)
            'http_status': modelFailure.statusCode,
          if (modelFailure.providerStatus != null)
            'provider_http_status': modelFailure.providerStatus,
        },
      ));
    } finally {
      streamClient?.close();
      client.close();
    }
  }

  Future<void> _openSettings() async {
    final current = _config;
    final sync = _sync;
    if (current == null || sync == null) return;
    final updated = await Navigator.of(context).push<MomConfig>(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(initial: current.copy(), sync: sync),
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
    } else if (!_startupIntroComplete) {
      home = StartupIntroScreen(
        onComplete: _completeStartupIntro,
        onSpeak: _speakText,
      );
    } else if (!_discovery.complete) {
      home = StartupDiscoveryScreen(
        onComplete: _completeDiscovery,
        onSpeak: _speakText,
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

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.initial,
    required this.sync,
  });

  final MomConfig initial;
  final MomSyncClient sync;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late MomConfig config;
  late final TextEditingController apiBase;
  late final TextEditingController model;
  late final TextEditingController modelsDir;
  late final TextEditingController repoRoot;

  @override
  void initState() {
    super.initState();
    config = widget.initial.copy();
    apiBase = TextEditingController(text: config.modelApiBase);
    model = TextEditingController(text: config.modelName);
    modelsDir = TextEditingController(text: config.modelsDir);
    repoRoot = TextEditingController(text: config.repoRoot);
  }

  @override
  void dispose() {
    apiBase.dispose();
    model.dispose();
    modelsDir.dispose();
    repoRoot.dispose();
    super.dispose();
  }

  void _save() {
    if (Platform.isLinux) {
      config.modelApiBase = apiBase.text.trim();
      config.modelName = model.text.trim();
      config.modelsDir = modelsDir.text.trim();
      config.repoRoot = repoRoot.text.trim();
    }
    config.modelApiKey = '';

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
          if (Platform.isLinux) ...[
            SwitchListTile(
              title: const Text('Use local MOM model'),
              subtitle: const Text(
                'Run MOM through the local llama.cpp model service on this computer.',
              ),
              value: config.useLocalLlama,
              onChanged: (v) => setState(() => config.useLocalLlama = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: apiBase,
              decoration: const InputDecoration(
                labelText: 'Local model endpoint',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: model,
              decoration: const InputDecoration(
                labelText: 'Local model name',
                helperText: 'Leave blank to use the first model exposed locally.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modelsDir,
              decoration: const InputDecoration(
                labelText: 'GGUF model folder',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: repoRoot,
              decoration: const InputDecoration(
                labelText: 'Live MOM repository folder',
              ),
            ),
            const Divider(height: 36),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.devices_other),
            title: const Text('Use MOM on another device'),
            subtitle: const Text(
              'Optional cross-device identity. MOM stays anonymous unless you choose to link devices.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => MomLoginScreen(sync: widget.sync),
              ),
            ),
          ),
          const Divider(height: 24),
          SwitchListTile(
            title: const Text('Cloud conversation sync'),
            subtitle: const Text(
              'Keep MOM conversation history available to her cloud memory.',
            ),
            value: config.cloudChatSync,
            onChanged: (v) => setState(() => config.cloudChatSync = v),
          ),
          SwitchListTile(
            title: const Text('Product/runtime data collection'),
            subtitle: const Text(
              'Collect app performance and reliability data.',
            ),
            value: config.productTelemetry,
            onChanged: (v) => setState(() => config.productTelemetry = v),
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
