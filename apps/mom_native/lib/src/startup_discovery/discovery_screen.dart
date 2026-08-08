import 'dart:async';

import 'package:flutter/material.dart';

import 'discovery_engine.dart';
import 'discovery_models.dart';
import 'discovery_store.dart';

enum _SetupStage {
  disclosure,
  underwear,
  attention,
  video,
  discovery,
  comeBackLater,
}

class StartupDiscoveryScreen extends StatefulWidget {
  const StartupDiscoveryScreen({
    super.key,
    required this.onComplete,
  });

  final Future<void> Function(DiscoveryProgress progress) onComplete;

  @override
  State<StartupDiscoveryScreen> createState() => _StartupDiscoveryScreenState();
}

class _StartupDiscoveryScreenState extends State<StartupDiscoveryScreen> {
  static const _purple = Color(0xFFA855F7);
  static const _softPurple = Color(0xFFD7A7FF);

  final DiscoveryEngine _engine = const DiscoveryEngine();
  final DiscoveryProgressStore _store = DiscoveryProgressStore();
  final PageController _carousel = PageController(viewportFraction: 0.88);

  DiscoveryProgress _progress = const DiscoveryProgress();
  _SetupStage _stage = _SetupStage.disclosure;
  bool _loading = true;
  bool _saving = false;
  bool _allowProfanity = true;
  int _selectedCard = 0;
  Timer? _transitionTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final progress = await _store.load();
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _stage = progress.answeredCount > 0
          ? _SetupStage.discovery
          : _SetupStage.disclosure;
      _loading = false;
    });
    if (progress.complete) {
      await widget.onComplete(progress);
    }
  }

  void _continueDisclosure() {
    setState(() => _stage = _SetupStage.underwear);
    _transitionTimer?.cancel();
    _transitionTimer = Timer(const Duration(milliseconds: 1350), () {
      if (mounted) setState(() => _stage = _SetupStage.attention);
    });
  }

  void _beginSetup() {
    setState(() => _stage = _SetupStage.video);

    // The finished trailer asset is intentionally not bundled yet. Until the
    // cached production video is available, first run glides through this stage
    // automatically instead of showing a broken player or blocking setup.
    _transitionTimer?.cancel();
    _transitionTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _stage = _SetupStage.discovery);
    });
  }

  Future<void> _choose(DiscoveryNode node, DiscoveryChoice choice) async {
    if (_saving) return;
    setState(() => _saving = true);

    final next = _engine.answer(_progress, node, choice);
    await _store.save(next);

    if (!mounted) return;
    if (next.complete || _engine.nextNode(next) == null) {
      final completed = next.copyWith(complete: true);
      await _store.save(completed);
      setState(() => _progress = completed);
      await widget.onComplete(completed);
      return;
    }

    setState(() {
      _progress = next;
      _selectedCard = 0;
      _saving = false;
    });
    if (_carousel.hasClients) _carousel.jumpToPage(0);
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    _carousel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _BlackStage(
        child: Center(
          child: CircularProgressIndicator(color: _purple),
        ),
      );
    }

    return switch (_stage) {
      _SetupStage.disclosure => _buildDisclosure(),
      _SetupStage.underwear => _buildUnderwear(),
      _SetupStage.attention => _buildAttention(),
      _SetupStage.video => _buildVideoStage(),
      _SetupStage.discovery => _buildDiscovery(),
      _SetupStage.comeBackLater => _buildComeBackLater(),
    };
  }

  Widget _buildDisclosure() {
    return _BlackStage(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const _MomMark(size: 78),
            const SizedBox(height: 28),
            const Text(
              'Before we meet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 31,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Some swearing will happen. MOM may also say things some people find offensive. Turning this on allows it. It does not guarantee anything.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                height: 1.45,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 26),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF120A18),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _purple.withValues(alpha: 0.48),
                ),
              ),
              child: SwitchListTile.adaptive(
                value: _allowProfanity,
                activeThumbColor: _purple,
                activeTrackColor: _purple.withValues(alpha: 0.38),
                title: const Text(
                  'Swearing & potentially offensive content',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: !_allowProfanity
                    ? const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          "Awww, you're no fun. Are you sure??",
                          style: TextStyle(
                            color: _softPurple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : null,
                onChanged: (value) {
                  setState(() => _allowProfanity = value);
                },
              ),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: _continueDisclosure,
              child: const Text(
                'CONTINUE',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnderwear() {
    return const _BlackStage(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text(
            'I hope you brought a clean pair of underwear.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _softPurple,
              fontSize: 28,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAttention() {
    return _BlackStage(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 36, 28, 30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            const _MomMark(size: 72),
            const SizedBox(height: 30),
            const Text(
              'The initial setup of MOM requires YOUR FULL attention.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                height: 1.18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Are you sitting down somewhere safe for the next 5 min?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _softPurple,
                fontSize: 20,
                height: 1.3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(58),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: _beginSetup,
              child: const Text(
                "YES MA'AM",
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: _softPurple,
                side: BorderSide(
                  color: _purple.withValues(alpha: 0.7),
                ),
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: () {
                setState(() => _stage = _SetupStage.comeBackLater);
              },
              child: const Text("NO, I'M NOT"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComeBackLater() {
    return _BlackStage(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const _MomMark(size: 70),
            const SizedBox(height: 28),
            const Text(
              'Please re-open the app when you have a moment for setup.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                height: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                setState(() => _stage = _SetupStage.attention);
              },
              child: const Text(
                'I have time now',
                style: TextStyle(color: _softPurple),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoStage() {
    return _BlackStage(
      child: Stack(
        children: [
          const Center(
            child: _MomMark(size: 104, glow: true),
          ),
          Positioned(
            top: 18,
            right: 18,
            child: TextButton(
              onPressed: () {
                _transitionTimer?.cancel();
                setState(() => _stage = _SetupStage.discovery);
              },
              child: const Text(
                'SKIP',
                style: TextStyle(
                  color: _softPurple,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscovery() {
    final node = _engine.nextNode(_progress);
    if (node == null) {
      return const _BlackStage(
        child: Center(
          child: CircularProgressIndicator(color: _purple),
        ),
      );
    }

    final prompt = _engine.promptFor(node, _progress);
    final progressValue = (_progress.answeredCount /
            DiscoveryEngine.maximumQuestions)
        .clamp(0.0, 1.0);

    return _BlackStage(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progressValue,
                        minHeight: 3,
                        backgroundColor: Colors.white12,
                        color: _purple,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    '${_progress.answeredCount + 1}',
                    style: const TextStyle(
                      color: _softPurple,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 30),
              Text(
                _progress.answeredCount < 4
                    ? 'Let me get my bearings.'
                    : 'Okay. Keep going.',
                style: const TextStyle(
                  color: _purple,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                prompt,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Swipe through these. Pick the one that feels closest.',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 22),
              Expanded(
                child: PageView.builder(
                  controller: _carousel,
                  itemCount: node.choices.length,
                  onPageChanged: (value) {
                    setState(() => _selectedCard = value);
                  },
                  itemBuilder: (context, index) {
                    final choice = node.choices[index];
                    final selected = index == _selectedCard;
                    return AnimatedPadding(
                      duration: const Duration(milliseconds: 160),
                      padding: EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: selected ? 5 : 16,
                      ),
                      child: Material(
                        color: selected
                            ? const Color(0xFF180D21)
                            : const Color(0xFF0E0912),
                        borderRadius: BorderRadius.circular(26),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(26),
                          onTap: _saving
                              ? null
                              : () => _choose(node, choice),
                          child: Container(
                            padding: const EdgeInsets.all(25),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(26),
                              border: Border.all(
                                color: _purple.withValues(
                                  alpha: selected ? 0.9 : 0.32,
                                ),
                                width: selected ? 1.8 : 1,
                              ),
                              boxShadow: selected
                                  ? [
                                      BoxShadow(
                                        color: _purple.withValues(alpha: 0.12),
                                        blurRadius: 24,
                                      ),
                                    ]
                                  : const [],
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  choice.label,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 25,
                                    height: 1.1,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  choice.detail,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 17,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 30),
                                const Row(
                                  children: [
                                    Icon(
                                      Icons.touch_app_outlined,
                                      color: _purple,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'That sounds like me',
                                      style: TextStyle(
                                        color: _softPurple,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  node.choices.length,
                  (index) => AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: index == _selectedCard ? 20 : 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: index == _selectedCard
                          ? _purple
                          : Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ),
              if (_saving) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(
                  minHeight: 2,
                  color: _purple,
                  backgroundColor: Colors.white12,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BlackStage extends StatelessWidget {
  const _BlackStage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: child),
    );
  }
}

class _MomMark extends StatelessWidget {
  const _MomMark({required this.size, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [
              Colors.white,
              Color(0xFFD89BFF),
              Color(0xFF7C20D6),
              Color(0xFF1A0028),
            ],
            stops: [0, 0.08, 0.48, 1],
          ),
          border: Border.all(
            color: _StartupDiscoveryScreenState._purple,
            width: 1.5,
          ),
          boxShadow: glow
              ? [
                  BoxShadow(
                    color: _StartupDiscoveryScreenState._purple
                        .withValues(alpha: 0.5),
                    blurRadius: 42,
                    spreadRadius: 7,
                  ),
                ]
              : [
                  BoxShadow(
                    color: _StartupDiscoveryScreenState._purple
                        .withValues(alpha: 0.24),
                    blurRadius: 18,
                  ),
                ],
        ),
      ),
    );
  }
}
