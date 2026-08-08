import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'local_store.dart';
import 'mic_status.dart';

class MomHomeScreen extends StatefulWidget {
  const MomHomeScreen({
    super.key,
    required this.turns,
    required this.busy,
    required this.status,
    required this.microphone,
    required this.onSend,
    required this.onSettings,
    required this.onDiagnostics,
    required this.onProbeMicrophone,
  });

  final List<ChatTurn> turns;
  final bool busy;
  final String status;
  final MomMicrophoneStatus microphone;
  final Future<void> Function(String) onSend;
  final VoidCallback onSettings;
  final VoidCallback onDiagnostics;
  final Future<void> Function(bool requestPermission) onProbeMicrophone;

  @override
  State<MomHomeScreen> createState() => _MomHomeScreenState();
}

class _MomHomeScreenState extends State<MomHomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  late final AnimationController _thinking;
  bool _textMode = false;
  String _caption = '';
  int _captionRun = 0;
  String? _lastCaptionId;

  @override
  void initState() {
    super.initState();
    _thinking = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncThinking();
    _maybeStartLatestCaption();
  }

  @override
  void didUpdateWidget(covariant MomHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busy != widget.busy) _syncThinking();
    if (oldWidget.turns.length != widget.turns.length) {
      _maybeStartLatestCaption();
    }
  }

  void _syncThinking() {
    if (widget.busy) {
      if (!_thinking.isAnimating) _thinking.repeat();
    } else {
      _thinking.stop();
      _thinking.value = 0;
    }
  }

  void _maybeStartLatestCaption() {
    for (final turn in widget.turns.reversed) {
      if (turn.role != 'assistant' || turn.content.trim().isEmpty) continue;
      final id = '${turn.createdAt.microsecondsSinceEpoch}:${turn.content.hashCode}';
      if (_lastCaptionId == id) return;
      _lastCaptionId = id;
      unawaited(_playCaption(turn.content));
      return;
    }
  }

  Future<void> _playCaption(String text) async {
    final run = ++_captionRun;
    final words = RegExp(r'\S+').allMatches(text).map((m) => m.group(0)!).toList();
    if (words.isEmpty) return;

    var visible = '';
    for (final word in words) {
      if (!mounted || run != _captionRun) return;
      visible = visible.isEmpty ? word : '$visible $word';
      setState(() => _caption = visible);
      final syllables = _estimateSyllables(word);
      await Future<void>.delayed(Duration(milliseconds: 500 * syllables));
    }

    await Future<void>.delayed(const Duration(seconds: 10));
    if (!mounted || run != _captionRun) return;
    setState(() => _caption = '');
  }

  int _estimateSyllables(String raw) {
    final word = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z]'), '')
        .replaceAll(RegExp(r'e$'), '');
    if (word.isEmpty) return 1;
    final groups = RegExp(r'[aeiouy]+').allMatches(word).length;
    return math.max(1, groups);
  }

  String get _captionWindow {
    const maxChars = 260;
    if (_caption.length <= maxChars) return _caption;
    final start = _caption.length - maxChars;
    final space = _caption.indexOf(' ', start);
    return space < 0 ? _caption.substring(start) : _caption.substring(space + 1);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    _controller.clear();
    setState(() => _textMode = false);
    widget.onSend(text);
  }

  @override
  void dispose() {
    _captionRun++;
    _thinking.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final orbSize = math.min(
              constraints.maxWidth * 0.62,
              constraints.maxHeight * 0.44,
            );
            final resolvedOrbSize = orbSize.clamp(180.0, 520.0).toDouble();

            return Stack(
              children: [
                Positioned(
                  top: 16,
                  left: 16,
                  child: _OutlineIconButton(
                    icon: Icons.mic,
                    color: accent,
                    tooltip: _microphoneTooltip,
                    onPressed: () => widget.onProbeMicrophone(true),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: GestureDetector(
                    onLongPress: widget.onDiagnostics,
                    child: _OutlineIconButton(
                      icon: Icons.settings,
                      color: accent,
                      tooltip: 'Settings',
                      onPressed: widget.onSettings,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 58, 24, 92),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.busy ? 'Thinking...' : 'Listening...',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: constraints.maxWidth < 500 ? 27 : 34,
                            fontWeight: FontWeight.w600,
                            color: accent,
                            shadows: [
                              Shadow(
                                color: accent.withOpacity(0.28),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        AnimatedBuilder(
                          animation: _thinking,
                          child: _PlasmaOrb(
                            size: resolvedOrbSize,
                            accent: accent,
                            lightMode: !dark,
                          ),
                          builder: (context, child) {
                            final wave = widget.busy
                                ? math.sin(_thinking.value * math.pi * 2)
                                : 0.0;
                            return Transform.translate(
                              offset: Offset(0, -14 * wave.abs()),
                              child: Transform.scale(
                                scale: 1 + (widget.busy ? 0.025 * wave : 0),
                                child: child,
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _caption.isEmpty
                              ? const SizedBox(height: 64)
                              : ConstrainedBox(
                                  key: ValueKey(_captionWindow),
                                  constraints: BoxConstraints(
                                    maxWidth: math.min(
                                      720,
                                      constraints.maxWidth * 0.88,
                                    ),
                                  ),
                                  child: Text(
                                    _captionWindow,
                                    maxLines: 4,
                                    overflow: TextOverflow.fade,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: accent,
                                      fontSize:
                                          constraints.maxWidth < 500 ? 18 : 21,
                                      height: 1.28,
                                      fontWeight: FontWeight.w600,
                                      shadows: [
                                        Shadow(
                                          color: accent.withOpacity(0.24),
                                          blurRadius: 10,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 28,
                  left: 24,
                  child: Text(
                    'Version 1.0.0',
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent, width: 2),
                    ),
                    child: IconButton(
                      tooltip: 'Text MOM',
                      icon: Icon(Icons.keyboard, color: accent),
                      onPressed: () => setState(() => _textMode = !_textMode),
                    ),
                  ),
                ),
                if (_textMode)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 78,
                    child: Material(
                      color: dark
                          ? const Color(0xF0141019)
                          : const Color(0xF7FFFFFF),
                      elevation: 12,
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: accent.withOpacity(0.72),
                            width: 1.4,
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                enabled: !widget.busy,
                                autofocus: true,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                decoration: const InputDecoration(
                                  hintText: 'Text MOM…',
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) => _submit(),
                              ),
                            ),
                            IconButton(
                              onPressed: widget.busy ? null : _submit,
                              icon: widget.busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Icon(Icons.arrow_upward, color: accent),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  String get _microphoneTooltip {
    switch (widget.microphone.state) {
      case MomMicrophoneState.available:
        return 'Microphone available';
      case MomMicrophoneState.permissionNeeded:
        return 'Check microphone permission';
      case MomMicrophoneState.unavailable:
        return 'No microphone detected';
      case MomMicrophoneState.error:
        return 'Microphone check failed';
      case MomMicrophoneState.unknown:
        return 'Check microphone';
    }
  }
}

class _OutlineIconButton extends StatelessWidget {
  const _OutlineIconButton({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.tooltip,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.12),
            blurRadius: 10,
          ),
        ],
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }
}

class _PlasmaOrb extends StatelessWidget {
  const _PlasmaOrb({
    required this.size,
    required this.accent,
    required this.lightMode,
  });

  final double size;
  final Color accent;
  final bool lightMode;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 34,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: size - 8,
            child: Container(
              width: size * 0.58,
              height: 24,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: RadialGradient(
                  colors: [
                    accent.withOpacity(lightMode ? 0.22 : 0.34),
                    accent.withOpacity(0),
                  ],
                ),
              ),
            ),
          ),
          SizedBox.square(
            dimension: size,
            child: CustomPaint(
              painter: _PlasmaOrbPainter(
                accent: accent,
                lightMode: lightMode,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlasmaOrbPainter extends CustomPainter {
  const _PlasmaOrbPainter({
    required this.accent,
    required this.lightMode,
  });

  final Color accent;
  final bool lightMode;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;

    final glow = Paint()
      ..color = accent.withOpacity(lightMode ? 0.24 : 0.38)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.12);
    canvas.drawCircle(center, radius * 0.98, glow);

    final sphere = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.08, -0.08),
        radius: 0.9,
        colors: [
          const Color(0xFFFFFFFF),
          accent.withOpacity(0.96),
          const Color(0xFF5B0FA3),
          const Color(0xFF170026),
        ],
        stops: const [0.0, 0.08, 0.46, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sphere);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    final branchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, radius * 0.006)
      ..color = const Color(0xFFE9C5FF).withOpacity(0.88)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.005);

    final faintPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.55, radius * 0.0038)
      ..color = accent.withOpacity(0.58);

    for (var i = 0; i < 30; i++) {
      final baseAngle = (math.pi * 2 * i / 30) + math.sin(i * 2.17) * 0.08;
      final path = Path()..moveTo(center.dx, center.dy);
      var previous = center;

      for (var step = 1; step <= 8; step++) {
        final fraction = step / 8;
        final jitter = math.sin((i + 1) * 12.91 + step * 4.73) * 0.11;
        final angle = baseAngle + jitter * fraction;
        final r = radius * fraction * (0.96 + 0.03 * math.sin(i + step));
        final point = Offset(
          center.dx + math.cos(angle) * r,
          center.dy + math.sin(angle) * r,
        );
        path.lineTo(point.dx, point.dy);

        if (step == 4 || step == 6) {
          final branchAngle = angle + (i.isEven ? 0.28 : -0.28);
          final branchLength = radius * (step == 4 ? 0.22 : 0.15);
          final branchEnd = Offset(
            point.dx + math.cos(branchAngle) * branchLength,
            point.dy + math.sin(branchAngle) * branchLength,
          );
          final branch = Path()
            ..moveTo(previous.dx, previous.dy)
            ..quadraticBezierTo(
              point.dx,
              point.dy,
              branchEnd.dx,
              branchEnd.dy,
            );
          canvas.drawPath(branch, faintPaint);
        }
        previous = point;
      }
      canvas.drawPath(path, i % 3 == 0 ? branchPaint : faintPaint);
    }

    final centerGlow = Paint()
      ..shader = const RadialGradient(
        colors: [Colors.white, Color(0xFFEBD2FF), Color(0x00FFFFFF)],
      ).createShader(
        Rect.fromCircle(center: center, radius: radius * 0.16),
      );
    canvas.drawCircle(center, radius * 0.16, centerGlow);

    canvas.restore();

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, radius * 0.008)
      ..color = accent.withOpacity(0.82);
    canvas.drawCircle(center, radius, edge);
  }

  @override
  bool shouldRepaint(covariant _PlasmaOrbPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.lightMode != lightMode;
}
