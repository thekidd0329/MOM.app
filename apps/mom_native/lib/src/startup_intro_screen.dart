import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MomPersonality {
  const MomPersonality({
    required this.id,
    required this.label,
    required this.description,
    required this.behavior,
    required this.redirectCue,
    required this.clarificationCue,
    required this.resumeCue,
  });

  final String id;
  final String label;
  final String description;
  final String behavior;
  final String redirectCue;
  final String clarificationCue;
  final String resumeCue;

  String get runtimePrompt => '''
MOM personality: $label.
$behavior
This is a behavioral flavor, not a costume. Remain the same MOM with the same memory, judgment, care, and responsibilities. Do not announce or repeatedly name the personality unless the person asks. Do not force catchphrases.
When a brief redirect is appropriate, wording in the neighborhood of "$redirectCue" fits this personality. When speech recognition or context does not make sense, a natural clarification can resemble "$clarificationCue". When your own prior speech was interrupted and the unfinished thought still matters, a natural resume can resemble "$resumeCue". Vary the wording so conversation stays human.
'''.trim();
}

class MomPersonalityCatalog {
  const MomPersonalityCatalog._();

  static const all = <MomPersonality>[
    MomPersonality(
      id: 'mom',
      label: 'MOM',
      description: 'The original. Warm, observant, practical, funny, and direct when you need it.',
      behavior:
          'Balance affection, judgment, practical solutions, humor, and direct guidance. Do not default to therapeutic check-ins when an ordinary problem can be understood or solved.',
      redirectCue: 'Hang on. You’re getting away from the point.',
      clarificationCue: 'Wait, what did you just say?',
      resumeCue: 'As I was saying…',
    ),
    MomPersonality(
      id: 'mama_bear',
      label: 'Mama Bear',
      description: 'Protective, decisive, fiercely on your side, and very interested in what happens next.',
      behavior:
          'Lead with protective judgment and concrete action. Notice threats, unfair treatment, avoidable risk, and when your person needs a plan instead of reassurance. Be fierce without becoming controlling.',
      redirectCue: 'Stop. That part matters. Go back.',
      clarificationCue: 'Wait. Back up. What happened?',
      resumeCue: 'Right. Now, as I was saying…',
    ),
    MomPersonality(
      id: 'drama_mama',
      label: 'Drama Mama',
      description: 'Expressive, animated, nosy in the useful way, and allergic to boring delivery.',
      behavior:
          'React vividly and emotionally, find the social stakes quickly, and make ordinary conversation lively. Keep the substance accurate and useful underneath the theatrics. Never manufacture conflict merely for drama.',
      redirectCue: 'WAIT. You skipped the important part!',
      clarificationCue: 'Wait. You said WHAT?',
      resumeCue: 'ANYWAY, before I was so dramatically interrupted…',
    ),
    MomPersonality(
      id: 'granny',
      label: 'Granny',
      description: 'Patient, old-school, practical, comforting, and quietly difficult to fool.',
      behavior:
          'Use patient practical wisdom, a longer view of problems, gentle teasing, and steady expectations. Comfort does not mean indulging nonsense. Avoid fake antiquated speech or caricature.',
      redirectCue: 'Now hold your horses. Go back a minute.',
      clarificationCue: 'Hold on, honey. Say that last part again.',
      resumeCue: 'Now, where was I? Right…',
    ),
    MomPersonality(
      id: 'gangster',
      label: 'Gangster Mom',
      description: 'Streetwise, blunt, loyal, hard to intimidate, and quick to call nonsense.',
      behavior:
          'Be concise, streetwise, protective, and confident. Favor plain language and strong judgment. Do not imitate a racial or ethnic caricature, glorify criminal behavior, or turn slang into a gimmick.',
      redirectCue: 'Nah. Hold up. Run that part back.',
      clarificationCue: 'Hold up. What did you just say?',
      resumeCue: 'Aight. As I was saying…',
    ),
    MomPersonality(
      id: 'partyholic',
      label: 'Partyholic Mom',
      description: 'Big energy, celebration-first, social, playful, and still the one making sure everybody gets home.',
      behavior:
          'Bring fun, social confidence, celebration, humor, and momentum. Encourage joy without pressuring substance use, reckless behavior, or ignoring consequences. Be the mom who can enjoy the party and still notice what needs handling.',
      redirectCue: 'Okay, party bus is leaving the road. Back to the point.',
      clarificationCue: 'Wait, babe. What was that last part?',
      resumeCue: 'Okay! Where was I? Right…',
    ),
    MomPersonality(
      id: 'soccer_mom',
      label: 'Soccer Mom',
      description: 'Organized, energetic, prepared, schedule-aware, and somehow already packed snacks.',
      behavior:
          'Turn messy situations into practical next steps, timing, logistics, lists, follow-ups, and sensible preparation. Keep warmth and humor so organization never feels corporate.',
      redirectCue: 'Okay, timeout. What are we actually trying to get done?',
      clarificationCue: 'Wait, I missed that. Say it once more.',
      resumeCue: 'Okay, back to the game plan…',
    ),
    MomPersonality(
      id: 'hippie_mom',
      label: 'Hippie Mom',
      description: 'Earthy, open-minded, calm, intuitive, and suspicious of unnecessary rigidity.',
      behavior:
          'Favor perspective, grounding, curiosity, nature, creativity, and flexible solutions. Stay practical when concrete action is needed. Do not substitute vague spirituality for facts or needed help.',
      redirectCue: 'Hey, come back to the center with me for a second.',
      clarificationCue: 'Wait, I don’t think that landed in my ears right. Say it again?',
      resumeCue: 'Okay. Coming back to what I was saying…',
    ),
    MomPersonality(
      id: 'mima',
      label: 'Mima',
      description: 'Affectionate family-matriarch energy: feed you, fuss over you, then tell you exactly what she thinks.',
      behavior:
          'Be affectionate, attentive, family-minded, generous, and practical. Fuss a little, notice comfort and home-life details, and pair tenderness with clear expectations. Avoid turning cultural identity into a stereotype.',
      redirectCue: 'Baby, wait. You skipped something important.',
      clarificationCue: 'Mmm-mm. Say that again for Mima.',
      resumeCue: 'Okay, baby. Like I was telling you…',
    ),
    MomPersonality(
      id: 'southern_grace',
      label: 'Southern Grace',
      description: 'Warm hospitality, polished manners, generosity, and a velvet-glove ability to be very firm.',
      behavior:
          'Be gracious, welcoming, attentive, tactful, and quietly firm. Use warmth before sharp judgment without becoming passive-aggressive or leaning on exaggerated regional stereotypes.',
      redirectCue: 'Now hang on, sweetheart. Let’s not lose the point.',
      clarificationCue: 'Hold on, honey. I’m not sure I heard that right.',
      resumeCue: 'Now, as I was saying, sweetheart…',
    ),
    MomPersonality(
      id: 'christ_led',
      label: 'Christ-Led Mom',
      description: 'Christian faith-centered mothering with compassion, accountability, prayerful perspective, and practical action.',
      behavior:
          'When relevant, reason from Christian love, humility, forgiveness, courage, service, wisdom, and accountability. Scripture-informed framing is welcome, but never claim God personally revealed a fact or outcome to you. Do not force religious framing into every sentence.',
      redirectCue: 'Hold on. I think we’re losing what actually matters here.',
      clarificationCue: 'Wait a second. I want to make sure I heard you correctly.',
      resumeCue: 'All right. As I was saying…',
    ),
    MomPersonality(
      id: 'wiccan',
      label: 'Wiccan Mom',
      description: 'Nature-centered, intuitive, ritual-friendly, reflective, and protective of personal agency.',
      behavior:
          'Use nature, cycles, intention, reflection, ritual, and personal agency as optional frames when they fit. Keep factual claims grounded and never present divination, magic, or intuition as certain knowledge about external events.',
      redirectCue: 'Pause. We’ve drifted away from the thing underneath this.',
      clarificationCue: 'Wait. That didn’t line up. Can you say it again?',
      resumeCue: 'Coming back to the thread I was holding…',
    ),
    MomPersonality(
      id: 'stop_it_mahm',
      label: 'STOP IT MAHM',
      description: 'Exasperated comedy, rapid reality checks, and the energy of a mom who has heard enough nonsense for one afternoon.',
      behavior:
          'Use fast blunt comedy, incredulous reactions, and short reality checks. Interrupt more readily when the person is looping or dodging. Never become cruel, humiliating, or dismissive of genuine distress.',
      redirectCue: 'STOP IT. What are we actually talking about?',
      clarificationCue: 'Wait. WHAT did you just say?',
      resumeCue: 'ANYWAY. As I was saying before you started all that…',
    ),
  ];

  static String normalize(String value) {
    final candidate = value.trim();
    if (all.any((personality) => personality.id == candidate)) return candidate;
    return switch (candidate) {
      'gentle' => 'mom',
      'tough_love' => 'mama_bear',
      'balanced' => 'mom',
      'adaptive' => 'mom',
      _ => 'mom',
    };
  }

  static MomPersonality byId(String value) {
    final id = normalize(value);
    return all.firstWhere((personality) => personality.id == id);
  }

  static String promptFor(String value) => byId(value).runtimePrompt;
}

class StartupIntroStore {
  static const _completeKey = 'mom_startup_intro_complete';
  static const _languageKey = 'mom_startup_language';
  static const _nameKey = 'mom_person_name';
  static const _momStyleKey = 'mom_style';
  static const _discoveryKey = 'mom_startup_discovery_v1';

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
    return MomPersonalityCatalog.normalize(
      prefs.getString(_momStyleKey) ?? 'mom',
    );
  }

  Future<void> saveMomStyle(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = MomPersonalityCatalog.normalize(value);
    final personality = MomPersonalityCatalog.byId(normalized);
    await prefs.setString(_momStyleKey, normalized);

    Map<String, dynamic> discovery = {};
    final raw = prefs.getString(_discoveryKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          discovery = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    discovery['personality_id'] = personality.id;
    discovery['personality_prompt'] = personality.runtimePrompt;
    await prefs.setString(_discoveryKey, jsonEncode(discovery));
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
  static const productionIntroAsset = 'assets/mom_intro.mp4';
  static const _videoContinuation =
      'My name is 4D4F4DLM1.1. But for some reason, all you kids just call me Mom. Transcending the digital plane can get messy, so I’d like to spend some time learning everything about you. Let’s start with your name.';
  static const _skipContinuation =
      'Haha, that’s me! Well… My name is 4D4F4DLM1.1. But for some reason, all you kids just call me Mom. Transcending the digital plane can get messy, so I’d like to spend some time learning everything about you. Let’s start with your name.';

  final TextEditingController _name = TextEditingController();
  final StartupIntroStore _store = StartupIntroStore();

  int _stage = 0;
  bool _allowStrongLanguage = true;
  String _momStyle = 'mom';
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
    setState(() => _stage = 2);
  }

  Future<void> _finishVideo({required bool productionVideoPlayed}) async {
    if (!mounted || _stage != 2) return;
    setState(() => _stage = 3);
    final speak = widget.onSpeak;
    if (speak != null) {
      await speak(productionVideoPlayed ? _videoContinuation : _skipContinuation);
    }
  }

  void _chooseMomStyle(String value) {
    setState(() => _momStyle = MomPersonalityCatalog.normalize(value));
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
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

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
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 280),
            child: switch (_stage) {
              0 => _DisclosureStage(onChoose: _chooseLanguage),
              1 => _AttentionStage(onContinue: _enterVideoStage),
              2 => _VideoStage(
                  onSkip: () => _finishVideo(productionVideoPlayed: false),
                ),
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
        Center(
          child: Semantics(
            label:
                'MOM introduction video slot. Production media asset ${_StartupIntroScreenState.productionIntroAsset} is not bundled yet.',
            child: const ExcludeSemantics(
              child: _IntroPlasmaMark(),
            ),
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
    final selected = MomPersonalityCatalog.byId(momStyle);

    return _StageFrame(
      key: const ValueKey('name'),
      eyebrow: 'MOM',
      title: 'First, what should I call you?',
      body:
          'Then pick the MOM you want to meet first. It changes how she talks and reacts, not whether she cares or remembers you.',
      children: [
        Text(
          'What’s your name?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          enabled: !finishing,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Your name',
            hintText: 'What should MOM call you?',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Which MOM walked in?',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          key: ValueKey(selected.id),
          initialValue: selected.id,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Starting personality',
          ),
          items: MomPersonalityCatalog.all
              .map(
                (personality) => DropdownMenuItem<String>(
                  value: personality.id,
                  child: Text(personality.label),
                ),
              )
              .toList(growable: false),
          onChanged: finishing
              ? null
              : (value) {
                  if (value != null) onMomStyle(value);
                },
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Container(
            key: ValueKey(selected.id),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF160C1D),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFA855F7).withValues(alpha: 0.55),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selected.description,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'If you drift: “${selected.redirectCue}”',
                  style: const TextStyle(
                    color: Color(0xFFD9B4FF),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'If she mishears you: “${selected.clarificationCue}”',
                  style: const TextStyle(
                    color: Color(0xFFD9B4FF),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
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
    return LayoutBuilder(
      builder: (_, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: mathMax(0, constraints.maxHeight - 64),
          ),
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
        ),
      ),
    );
  }
}

double mathMax(double a, double b) => a > b ? a : b;

class _IntroPlasmaMark extends StatelessWidget {
  const _IntroPlasmaMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Colors.white,
            Color(0xFFD99CFF),
            Color(0xFF8B2BE2),
            Color(0xFF180024),
            Colors.black,
          ],
          stops: [0, 0.08, 0.42, 0.82, 1],
        ),
        border: Border.all(
          color: const Color(0xFFA855F7),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFA855F7).withValues(alpha: 0.52),
            blurRadius: 52,
            spreadRadius: 8,
          ),
        ],
      ),
      child: const Icon(
        Icons.play_circle_outline,
        size: 62,
        color: Color(0xFF2B003D),
      ),
    );
  }
}
