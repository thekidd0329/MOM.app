import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'local_store.dart';
import 'mic_status.dart';
import 'mom_build_info.dart';

class MomHomeScreen extends StatefulWidget {
  const MomHomeScreen({
    super.key,
    required this.turns,
    required this.busy,
    required this.listening,
    required this.status,
    required this.microphone,
    required this.onSend,
    required this.onSettings,
    required this.onDiagnostics,
    required this.onProbeMicrophone,
    required this.onMicTap,
    this.playStartupEntrance = false,
  });

  final List<ChatTurn> turns;
  final bool busy;
  final bool listening;
  final String status;
  final MomMicrophoneStatus microphone;
  final Future<void> Function(String) onSend;
  final VoidCallback onSettings;
  final VoidCallback onDiagnostics;
  final Future<void> Function(bool requestPermission) onProbeMicrophone;
  final Future<void> Function() onMicTap;
  final bool playStartupEntrance;

  @override
  State<MomHomeScreen> createState() => _MomHomeScreenState();
}

class _MomHomeScreenState extends State<MomHomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  late final AnimationController _entrance;
  bool _textMode = false;
  String _caption = '';
  int _captionRun = 0;
  String? _lastCaptionId;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1850),
      value: widget.playStartupEntrance ? 0 : 1,
    );
    if (widget.playStartupEntrance) {
      unawaited(_entrance.forward());
    }
    _maybeStartLatestCaption();
  }

  @override
  void didUpdateWidget(covariant MomHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turns.length != widget.turns.length) {
      _maybeStartLatestCaption();
    }
    if (!oldWidget.playStartupEntrance && widget.playStartupEntrance) {
      unawaited(_entrance.forward(from: 0));
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
    if (text.trim().isEmpty || !mounted) return;
    setState(() => _caption = text.trim());
    await Future<void>.delayed(Duration.zero);
    if (!mounted || run != _captionRun) return;
  }

  String get _captionWindow {
    const maxChars = 260;
    if (_caption.length <= maxChars) return _caption;
    final start = _caption.length - maxChars;
    final space = _caption.indexOf(' ', start);
    return space < 0 ? _caption.substring(start) : _caption.substring(space + 1);
  }

  Future<void> _handleMicTap() async {
    await widget.onMicTap();
  }

  void _toggleTextMode() {
    setState(() => _textMode = !_textMode);
    if (_textMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _textFocus.requestFocus();
      });
    } else {
      _textFocus.unfocus();
    }
  }

  void _showHistory() {
    final replies = widget.turns
        .where((turn) => turn.role == 'assistant' && turn.content.trim().isNotEmpty)
        .toList()
        .reversed
        .toList(growable: false);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: replies.isEmpty
              ? const Center(child: Text('No replies yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  itemCount: replies.length,
                  separatorBuilder: (_, __) => const Divider(height: 28),
                  itemBuilder: (context, index) => SelectableText(
                    replies[index].content,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
                  ),
                ),
        ),
      ),
    );
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    _controller.clear();
    _textFocus.unfocus();
    setState(() => _textMode = false);
    widget.onSend(text);
  }

  double _segment(double value, double start, double end) {
    if (value <= start) return 0;
    if (value >= end) return 1;
    return ((value - start) / (end - start)).clamp(0.0, 1.0);
  }

  @override
  void dispose() {
    _captionRun++;
    _entrance.dispose();
    _textFocus.dispose();
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
      resizeToAvoidBottomInset: true,
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;
            final orbSize = math.min(width * 0.78, height * 0.49)
                .clamp(180.0, 500.0)
                .toDouble();
            final finalOrbTop = (height * 0.355)
                .clamp(142.0, math.max(142.0, height - orbSize - 145.0))
                .toDouble();
            final statusTop = math.max(70.0, finalOrbTop - 66.0);
            final captionTop = math.min(
              finalOrbTop + orbSize + 16,
              math.max(statusTop + 90, height - 162),
            );

            return AnimatedBuilder(
              animation: _entrance,
              builder: (context, _) {
                final raw = _entrance.value;
                final fall = Curves.easeOutCubic.transform(_segment(raw, 0.0, 0.58));
                final orbScale = lerpDouble(0.48, 1.0, fall)!;
                final orbLift = lerpDouble(-height * 0.17, 0, fall)!;
                final statusReveal = Curves.easeOut.transform(_segment(raw, 0.48, 0.64));
                final micReveal = Curves.easeOutBack.transform(_segment(raw, 0.56, 0.70));
                final settingsReveal = Curves.easeOutBack.transform(_segment(raw, 0.66, 0.80));
                final versionReveal = Curves.easeOutBack.transform(_segment(raw, 0.76, 0.90));
                final keyboardReveal = Curves.easeOutBack.transform(_segment(raw, 0.86, 1.0));
                final contentReveal = Curves.easeOut.transform(_segment(raw, 0.82, 1.0));
                final orbCenter = Offset(
                  width / 2,
                  finalOrbTop + orbSize / 2 + orbLift,
                );

                return Stack(
                  children: [
                    if (raw < 0.999)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: _WorkflowZapPainter(
                              accent: accent,
                              progress: raw,
                              origin: orbCenter,
                              sizeHint: Size(width, height),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: statusTop,
                      left: 20,
                      right: 20,
                      child: Opacity(
                        opacity: statusReveal.clamp(0.0, 1.0),
                        child: Text(
                          widget.busy
                              ? 'Thinking...'
                              : widget.listening
                                  ? 'Listening...'
                                  : 'Tap the mic',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: width < 500 ? 27 : 34,
                            fontWeight: FontWeight.w600,
                            color: accent,
                            shadows: [
                              Shadow(
                                color: accent.withValues(alpha: 0.28),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: finalOrbTop,
                      left: (width - orbSize) / 2,
                      child: Transform.translate(
                        offset: Offset(0, orbLift),
                        child: Transform.scale(
                          scale: orbScale,
                          child: _ElectricOrb(
                            size: orbSize,
                            accent: accent,
                            lightMode: !dark,
                            energized: widget.busy || widget.listening || raw < 1,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: captionTop,
                      left: 24,
                      right: 24,
                      child: Opacity(
                        opacity: contentReveal.clamp(0.0, 1.0),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _caption.isEmpty
                              ? const SizedBox(height: 64)
                              : InkWell(
                                  key: ValueKey(_captionWindow),
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _showHistory,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    child: Text(
                                      _captionWindow,
                                      maxLines: 5,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: accent,
                                        fontSize: width < 500 ? 18 : 21,
                                        height: 1.28,
                                        fontWeight: FontWeight.w600,
                                        shadows: [
                                          Shadow(
                                            color: accent.withValues(alpha: 0.24),
                                            blurRadius: 10,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _RevealControl(
                        progress: micReveal,
                        child: _OutlineIconButton(
                          icon: widget.listening
                              ? Icons.stop_rounded
                              : widget.microphone.available
                                  ? Icons.mic
                                  : Icons.mic_none,
                          color: accent,
                          tooltip: widget.microphone.permissionGranted
                              ? 'Use microphone'
                              : 'Enable microphone',
                          onPressed: _handleMicTap,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      right: 16,
                      child: _RevealControl(
                        progress: settingsReveal,
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
                    ),
                    Positioned(
                      bottom: 28,
                      left: 24,
                      child: _RevealControl(
                        progress: versionReveal,
                        child: Text(
                          MomBuildInfo.displayVersion,
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: _RevealControl(
                        progress: keyboardReveal,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: accent, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.10),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: IconButton(
                            tooltip: 'Text MOM',
                            icon: Icon(Icons.keyboard, color: accent),
                            onPressed: _toggleTextMode,
                          ),
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
                                color: accent.withValues(alpha: 0.72),
                                width: 1.4,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _controller,
                                    focusNode: _textFocus,
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
            );
          },
        ),
      ),
    );
  }
}

class _RevealControl extends StatelessWidget {
  const _RevealControl({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: p < 0.92,
      child: Opacity(
        opacity: p,
        child: Transform.scale(
          scale: 0.62 + 0.38 * p,
          child: child,
        ),
      ),
    );
  }
}

class _WorkflowZapPainter extends CustomPainter {
  const _WorkflowZapPainter({
    required this.accent,
    required this.progress,
    required this.origin,
    required this.sizeHint,
  });

  final Color accent;
  final double progress;
  final Offset origin;
  final Size sizeHint;

  double _segment(double start, double end) {
    if (progress <= start || progress >= end) return 0;
    final local = (progress - start) / (end - start);
    return math.sin(local * math.pi).clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final targets = <Offset>[
      const Offset(44, 44),
      Offset(sizeHint.width - 44, 44),
      Offset(62, sizeHint.height - 38),
      Offset(sizeHint.width - 44, sizeHint.height - 42),
    ];
    final windows = <(double, double)>[
      (0.52, 0.70),
      (0.62, 0.80),
      (0.72, 0.90),
      (0.82, 1.0),
    ];

    for (var i = 0; i < targets.length; i++) {
      final alpha = _segment(windows[i].$1, windows[i].$2);
      if (alpha <= 0) continue;
      final target = targets[i];
      final delta = target - origin;
      final length = delta.distance;
      if (length <= 0) continue;
      final normal = Offset(-delta.dy / length, delta.dx / length);
      final path = Path()..moveTo(origin.dx, origin.dy);
      const segments = 9;
      for (var j = 1; j < segments; j++) {
        final t = j / segments;
        final base = Offset(
          origin.dx + delta.dx * t,
          origin.dy + delta.dy * t,
        );
        final wiggle = math.sin((j * 7.37) + i * 2.9 + progress * 31) *
            (10.0 * (1 - (t - 0.5).abs()));
        final p = base + normal * wiggle;
        path.lineTo(p.dx, p.dy);
      }
      path.lineTo(target.dx, target.dy);

      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.22 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      final hot = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.1
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.84 * alpha);
      final purple = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.74 * alpha);
      canvas.drawPath(path, glow);
      canvas.drawPath(path, purple);
      canvas.drawPath(path, hot);
    }
  }

  @override
  bool shouldRepaint(covariant _WorkflowZapPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.origin != origin ||
      oldDelegate.accent != accent ||
      oldDelegate.sizeHint != sizeHint;
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
            color: color.withValues(alpha: 0.12),
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

class _ElectricOrb extends StatefulWidget {
  const _ElectricOrb({
    required this.size,
    required this.accent,
    required this.lightMode,
    required this.energized,
  });

  final double size;
  final Color accent;
  final bool lightMode;
  final bool energized;

  @override
  State<_ElectricOrb> createState() => _ElectricOrbState();
}

class _ElectricOrbState extends State<_ElectricOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size + 34,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: widget.size - 8,
            child: AnimatedBuilder(
              animation: _rotation,
              builder: (context, _) {
                final pulse = 0.5 +
                    0.5 * math.sin(_rotation.value * math.pi * 4);
                return Container(
                  width: widget.size * (0.52 + 0.08 * pulse),
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: RadialGradient(
                      colors: [
                        widget.accent.withValues(
                          alpha: widget.lightMode
                              ? 0.15 + 0.08 * pulse
                              : 0.25 + 0.12 * pulse,
                        ),
                        widget.accent.withValues(alpha: 0),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: _rotation,
              builder: (context, _) => CustomPaint(
                painter: _ElectricOrbPainter(
                  accent: widget.accent,
                  lightMode: widget.lightMode,
                  phase: _rotation.value,
                  energized: widget.energized,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElectricOrbPainter extends CustomPainter {
  const _ElectricOrbPainter({
    required this.accent,
    required this.lightMode,
    required this.phase,
    required this.energized,
  });

  final Color accent;
  final bool lightMode;
  final double phase;
  final bool energized;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;
    final spin = phase * math.pi * 2;
    final pulse = 0.5 + 0.5 * math.sin(spin * 2.3);
    final heat = energized ? 1.0 : 0.72;

    final outerGlow = Paint()
      ..color = accent.withValues(
        alpha: (lightMode ? 0.18 : 0.31) * (0.86 + 0.18 * pulse) * heat,
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.18);
    canvas.drawCircle(center, radius * (0.98 + 0.025 * pulse), outerGlow);

    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.18, -0.22),
        radius: 1.05,
        colors: [
          Colors.white.withValues(alpha: lightMode ? 0.97 : 0.93),
          const Color(0xFFE9C5FF).withValues(alpha: 0.98),
          accent.withValues(alpha: 0.94),
          const Color(0xFF5B0FA3),
          const Color(0xFF140020),
        ],
        stops: const [0.0, 0.07, 0.28, 0.66, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, body);

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );

    final deepGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.14 + 0.08 * pulse),
          const Color(0x00140020),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.88));
    canvas.drawCircle(center, radius * 0.9, deepGlow);

    final ringPaintBack = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, radius * 0.005)
      ..color = accent.withValues(alpha: lightMode ? 0.20 : 0.28);
    final ringPaintFront = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, radius * 0.007)
      ..color = const Color(0xFFF5E6FF).withValues(alpha: 0.32 + 0.12 * pulse)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.006);

    for (var r = 0; r < 4; r++) {
      final tilt = -0.62 + r * 0.38;
      final rect = Rect.fromCenter(
        center: center,
        width: radius * 1.76,
        height: radius * (0.36 + r * 0.11),
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilt + spin * (r.isEven ? 0.055 : -0.045));
      canvas.translate(-center.dx, -center.dy);
      canvas.drawArc(rect, math.pi, math.pi, false, ringPaintBack);
      canvas.drawArc(rect, 0, math.pi, false, ringPaintFront);
      canvas.restore();
    }

    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(0.55, radius * 0.004)
      ..color = accent.withValues(alpha: 0.48 * heat);

    final hot = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.0, radius * 0.007)
      ..color = const Color(0xFFF8EEFF).withValues(alpha: 0.88 * heat)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.006);

    final filamentCount = energized ? 34 : 26;
    for (var i = 0; i < filamentCount; i++) {
      final seed = i * 12.9898;
      final rotationRate = i.isEven ? 1.0 : -0.72;
      final base = spin * rotationRate +
          math.pi * 2 * i / filamentCount +
          0.18 * math.sin(seed);
      final path = Path();
      Offset? previous;

      for (var step = 0; step <= 11; step++) {
        final t = step / 11;
        final radial = radius * (0.06 + 0.91 * t);
        final curl =
            0.72 * math.sin(t * math.pi) * math.sin(seed * 0.7 + spin * 1.6);
        final jitter =
            0.075 * math.sin(seed + step * 4.73 + spin * (2.0 + (i % 3)));
        final angle = base + curl + jitter;
        final depth = math.sin(base + t * 1.4 + spin * 0.22);
        final squash = 0.72 + 0.18 * depth;
        final point = Offset(
          center.dx + math.cos(angle) * radial,
          center.dy + math.sin(angle) * radial * squash,
        );

        if (step == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }

        if (previous != null && (step == 6 || step == 8) && i % 3 == 0) {
          final branchAngle = angle + (i.isEven ? 0.34 : -0.34);
          final branchLength = radius * (step == 6 ? 0.18 : 0.12);
          final end = Offset(
            point.dx + math.cos(branchAngle) * branchLength,
            point.dy + math.sin(branchAngle) * branchLength * 0.72,
          );
          final branch = Path()
            ..moveTo(previous.dx, previous.dy)
            ..quadraticBezierTo(point.dx, point.dy, end.dx, end.dy);
          canvas.drawPath(branch, faint);
        }
        previous = point;
      }

      final facing = 0.5 + 0.5 * math.cos(base + spin * 0.12);
      if (i % 4 == 0 || facing > 0.78) {
        canvas.drawPath(path, hot);
      } else {
        canvas.drawPath(path, faint);
      }
    }

    final core = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.98),
          const Color(0xFFF3DEFF).withValues(alpha: 0.92),
          accent.withValues(alpha: 0.55),
          accent.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.22, 0.52, 1.0],
      ).createShader(
        Rect.fromCircle(
          center: center,
          radius: radius * (0.22 + 0.035 * pulse),
        ),
      );
    canvas.drawCircle(center, radius * (0.22 + 0.035 * pulse), core);

    canvas.restore();

    final rimGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(4.0, radius * 0.035)
      ..color = accent.withValues(alpha: (lightMode ? 0.12 : 0.20) * heat)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.05);
    canvas.drawCircle(center, radius, rimGlow);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, radius * 0.009)
      ..shader = SweepGradient(
        transform: GradientRotation(spin),
        colors: [
          accent.withValues(alpha: 0.35),
          const Color(0xFFF4E4FF).withValues(alpha: 0.95),
          accent.withValues(alpha: 0.45),
          const Color(0xFF7D26C9).withValues(alpha: 0.75),
          accent.withValues(alpha: 0.35),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, edge);
  }

  @override
  bool shouldRepaint(covariant _ElectricOrbPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.accent != accent ||
      oldDelegate.lightMode != lightMode ||
      oldDelegate.energized != energized;
}
