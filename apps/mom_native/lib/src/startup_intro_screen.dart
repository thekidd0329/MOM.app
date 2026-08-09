import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StartupIntroStore {
  static const _completeKey = 'mom_startup_intro_complete';
  static const _languageKey = 'mom_startup_language';
  static const _nameKey = 'mom_person_name';
  static const _momStyleKey = 'mom_style';

  Future<bool> isComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completeKey) ?? false;
  }

  Future<String> savedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey) ?? '';
  }

  Future<String> savedMomStyle() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_momStyleKey) ?? 'balanced';
  }

  Future<void> saveMomStyle(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_momStyleKey, value);
  }

  Future<bool> allowsStrongLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_languageKey) ?? true;
  }

  Future<void> complete({
    required bool allowStrongLanguage,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completeKey, true);
    await prefs.setBool(_languageKey, allowStrongLanguage);
    await prefs.setString(_nameKey, name.trim());
  }
}

class StartupIntroScreen extends StatefulWidget {
  const StartupIntroScreen({
    super.key,
    required this.onComplete,
    this.onSpeak,
  });

  final Future<void> Function({
    required bool allowStrongLanguage,
    required String name,
  }) onComplete;
  final Future<void> Function(String text)? onSpeak;

  @override
  State<StartupIntroScreen> createState() => _StartupIntroScreenState();
}

class _StartupIntroScreenState extends State<StartupIntroScreen> {
  final TextEditingController _name = TextEditingController();
  final StartupIntroStore _store = StartupIntroStore();
  int _stage = 0;
  bool _allowStrongLanguage = true;
  String _momStyle = 'balanced';
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _speakStage(0));
  }

  void _speakStage(int stage) {
    final speak = widget.onSpeak;
    if (speak == null) return;
    final text = switch (stage) {
      0 => 'Before MOM moves in, choose how you want her to talk. She can be blunt, emotional, opinionated, and vulgar. Choose swearing is fine, or clean pair of underwear mode.',
      1 => 'Give this your full attention. The next part introduces MOM. Do not watch while driving or doing anything that needs your eyes.',
      3 => 'What kind of mom are you looking for? Gentle and reassuring, blunt tough love, balanced, or one who learns you and adapts? Then tell me what name you want me to call you.',
      _ => '',
    };
    if (text.isNotEmpty) speak(text);
  }

  void _chooseLanguage(bool value) {
    setState(() {
      _allowStrongLanguage = value;
      _stage = 1;
    });
    _speakStage(1);
  }

  void _enterVideoStage() {
    // Keep the intro slot on screen until the user explicitly advances it.
    // The trailer asset is not bundled yet, so silently auto-skipping this
    // stage would make the first-run experience look broken.
    setState(() => _stage = 2);
  }

  void _finishVideo() {
    if (!mounted || _stage != 2) return;
    setState(() => _stage = 3);
    _speakStage(3);
  }

  void _chooseMomStyle(String value) {
    setState(() => _momStyle = value);
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final name = _name.text.trim();
    if (name.isEmpty) return;

    setState(() => _finishing = true);
    try {
      await _store.saveMomStyle(_momStyle);
      await widget.onComplete(
        allowStrongLanguage: _allowStrongLanguage,
        name: name,
      );
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFA855F7),
          brightness: Brightness.dark,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: switch (_stage) {
              0 => _DisclosureStage(onChoose: _chooseLanguage),
              1 => _AttentionStage(onContinue: _enterVideoStage),
              2 => _VideoStage(onSkip: _finishVideo),
              _ => _NameStage(
                  controller: _name,
                  onContinue: _finish,
                  finishing: _finishing,
                  momStyle: _momStyle,
                  onMomStyle: _chooseMomStyle,
                ),
            },
          ),
        ),
      ),
    );
  }
}

class _DisclosureStage extends StatelessWidget {
  const _DisclosureStage({required this.onChoose});

  final ValueChanged<bool> onChoose;

  @override
  Widget build(BuildContext context) {
    return _StageFrame(
      key: const ValueKey('disclosure'),
      eyebrow: 'BEFORE MOM MOVES IN',
      title: 'MOM talks like a real person.',
      body:
          'She can be blunt, emotional, opinionated, and she may use strong language. Choose what feels right. You can change it later.',
      children: [
        FilledButton(
          onPressed: () => onChoose(true),
          child: const Text('Swearing is fine'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () => onChoose(false),
          child: const Text('Clean pair of underwear mode'),
        ),
      ],
    );
  }
}

class _AttentionStage extends StatelessWidget {
  const _AttentionStage({required this.onContinue});

  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return _StageFrame(
      key: const ValueKey('attention'),
      eyebrow: 'ONE REAL THING',
      title: 'Give this your full attention.',
      body:
          'The next part introduces MOM. Don’t watch while driving or doing anything that needs your eyes.',
      children: [
        FilledButton(
          onPressed: onContinue,
          child: const Text('I’m somewhere safe'),
        ),
      ],
    );
  }
}

class _VideoStage extends StatelessWidget {
  const _VideoStage({required this.onSkip});

  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('video'),
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        const Center(
          child: Icon(
            Icons.play_circle_outline,
            size: 74,
            color: Color(0xFFA855F7),
          ),
        ),
        Positioned(
          right: 20,
          bottom: 20,
          child: TextButton(
            onPressed: onSkip,
            child: const Text('Skip intro'),
          ),
        ),
      ],
    );
  }
}

class _NameStage extends StatelessWidget {
  const _NameStage({
    required this.controller,
    required this.onContinue,
    required this.finishing,
    required this.momStyle,
    required this.onMomStyle,
  });

  final TextEditingController controller;
  final Future<void> Function() onContinue;
  final bool finishing;
  final String momStyle;
  final ValueChanged<String> onMomStyle;

  @override
  Widget build(BuildContext context) {
    return _StageFrame(
      key: const ValueKey('name'),
      eyebrow: 'MOM',
      title: 'What kind of mom are you looking for?',
      body: 'Pick the closest fit. MOM will keep learning you after this.',
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: const [
            ('gentle', 'Gentle and reassuring'),
            ('tough_love', 'Blunt tough love'),
            ('balanced', 'A balance of both'),
            ('adaptive', 'Learn me and adapt'),
          ].map((option) {
            return ChoiceChip(
              label: Text(option.$2),
              selected: momStyle == option.$1,
              onSelected: finishing ? null : (_) => onMomStyle(option.$1),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 28),
        Text(
          'What’s your name?',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          enabled: !finishing,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: finishing ? null : (_) => onContinue(),
          decoration: const InputDecoration(
            hintText: 'Your name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: finishing ? null : onContinue,
          child: finishing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Meet MOM'),
        ),
      ],
    );
  }
}

class _StageFrame extends StatelessWidget {
  const _StageFrame({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.children,
  });

  final String eyebrow;
  final String title;
  final String body;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            eyebrow,
            style: const TextStyle(
              color: Color(0xFFA855F7),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
          ),
          const SizedBox(height: 18),
          Text(
            body,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.white70,
                  height: 1.45,
                ),
          ),
          const SizedBox(height: 34),
          ...children,
        ],
      ),
    );
  }
}
