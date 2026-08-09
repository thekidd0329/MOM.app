import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'local_store.dart';
import 'mic_status.dart';

enum _OrbMode {
  idle,
  listening,
  thinking,
  speaking,
  interrupted,
  confused,
  error,
}

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

  @override
  State<MomHomeScreen> createState() => _MomHomeScreenState();
}

class _MomHomeScreenState extends State<MomHomeScreen> {
  static const _purple = Color(0xFFA855F7);
  static const _lavender = Color(0xFFD990FF);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  bool _textMode = false;
  String _caption = '';
  String? _lastCaptionId;
  int _captionRun = 0;

  @override
  void initState() {
    super.initState();
    _captureLatestReply();
  }

  @override
  void didUpdateWidget(covariant MomHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turns.length != widget.turns.length) _captureLatestReply();
  }

  _OrbMode get _mode {
    if (widget.listening) return _OrbMode.listening;
    if (widget.busy) return _OrbMode.thinking;

    final status = widget.status.toLowerCase();
    if (status.contains('speaking') || status.contains('talking')) {
      return _OrbMode.speaking;
    }
    if (status.contains('interrupt')) return _OrbMode.interrupted;
    if (status.contains('clarif') ||
        status.contains('didn\'t hear') ||
        status.contains('did not hear') ||
        status.contains('say that again')) {
      return _OrbMode.confused;
    }
    if (status.contains('offline') ||
        status.contains('error') ||
        status.contains('unavailable') ||
        status.contains('issue')) {
      return _OrbMode.error;
    }
    return _OrbMode.idle;
  }

  String get _modeLabel {
    return switch (_mode) {
      _OrbMode.listening => 'Listening...',
      _OrbMode.thinking => 'Thinking...',
      _OrbMode.speaking => 'MOM',
      _OrbMode.interrupted => 'I\'m listening.',
      _OrbMode.confused => 'Wait, what?',
      _OrbMode.error => 'MOM needs a second.',
      _OrbMode.idle => 'Ready',
    };
  }

  String get _orbSemantics {
    return switch (_mode) {
      _OrbMode.listening => 'MOM is listening',
      _OrbMode.thinking => 'MOM is thinking',
      _OrbMode.speaking => 'MOM is speaking',
      _OrbMode.interrupted => 'MOM was interrupted and is listening',
      _OrbMode.confused => 'MOM needs clarification',
      _OrbMode.error => 'MOM has a temporary problem',
      _OrbMode.idle => 'MOM is ready',
    };
  }

  void _captureLatestReply() {
    for (final turn in widget.turns.reversed) {
      if (turn.role != 'assistant' || turn.content.trim().isEmpty) continue;
      final id = '${turn.createdAt.microsecondsSinceEpoch}:${turn.content.hashCode}';
      if (id == _lastCaptionId) return;
      _lastCaptionId = id;
      unawaited(_showCaption(turn.content));
      return;
    }
  }

  Future<void> _showCaption(String text) async {
    final run = ++_captionRun;
    if (!mounted || text.trim().isEmpty) return;
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

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty || widget.busy) return;
    _controller.clear();
    _textFocus.unfocus();
    setState(() => _textMode = false);
    widget.onSend(text);
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
      backgroundColor: const Color(0xFF100916),
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: replies.isEmpty
              ? const Center(
                  child: Text(
                    'No replies yet.',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  itemCount: replies.length,
                  separatorBuilder: (_, __) => const Divider(height: 28),
                  itemBuilder: (_, index) => SelectableText(
                    replies[index].content,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          height: 1.4,
                        ),
                  ),
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _captionRun++;
    _textFocus.unfocus();
    _textFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.35);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (_, constraints) {
            final orbSize = math.min(
              constraints.maxWidth * 0.84,
              constraints.maxHeight * 0.55,
            ).clamp(180.0, 520.0).toDouble();

            return Stack(
              children: [
                Positioned(
                  top: 16,
                  left: 16,
                  child: _RoundButton(
                    icon: widget.listening
                        ? Icons.stop_rounded
                        : widget.microphone.available
                            ? Icons.mic
                            : Icons.mic_none,
                    color: accent,
                    tooltip: widget.microphone.permissionGranted
                        ? 'Talk to MOM'
                        : 'Enable microphone',
                    onPressed: _handleMicTap,
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: GestureDetector(
                    onLongPress: widget.onDiagnostics,
                    child: _RoundButton(
                      icon: Icons.settings_outlined,
                      color: accent,
                      tooltip: 'MOM settings',
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
                        Semantics(
                          liveRegion: true,
                          label: _modeLabel,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Text(
                              _modeLabel,
                              key: ValueKey(_mode),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _mode == _OrbMode.error
                                    ? const Color(0xFFE7A6FF)
                                    : _lavender,
                                fontSize: (constraints.maxWidth < 500 ? 30 : 36) /
                                    textScale,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    color: accent.withValues(alpha: 0.55),
                                    blurRadius: 24,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        Semantics(
                          image: true,
                          label: _orbSemantics,
                          child: ExcludeSemantics(
                            child: _PlasmaOrb(
                              size: orbSize,
                              accent: accent,
                              mode: _mode,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _caption.isEmpty
                              ? const SizedBox(height: 64)
                              : InkWell(
                                  key: ValueKey(_captionWindow),
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: _showHistory,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: math.min(
                                        720,
                                        constraints.maxWidth * 0.88,
                                      ),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: Text(
                                        _captionWindow,
                                        maxLines: 5,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: _lavender,
                                          fontSize:
                                              (constraints.maxWidth < 500 ? 18 : 21) /
                                                  textScale,
                                          height: 1.28,
                                          fontWeight: FontWeight.w600,
                                          shadows: [
                                            Shadow(
                                              color: accent.withValues(alpha: 0.36),
                                              blurRadius: 12,
                                            ),
                                          ],
                                        ),
                                      ),
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
                  child: Semantics(
                    label: 'MOM version 0.5.0',
                    child: ExcludeSemantics(
                      child: Text(
                        'MOM 0.5.0',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: _RoundButton(
                    icon: Icons.keyboard_alt_outlined,
                    color: accent,
                    tooltip: 'Type to MOM',
                    onPressed: _toggleTextMode,
                  ),
                ),
                if (_textMode)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 78,
                    child: Material(
                      color: const Color(0xF0141019),
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
                                style: const TextStyle(color: Colors.white),
                                cursorColor: _purple,
                                decoration: const InputDecoration(
                                  hintText: 'Type to MOM…',
                                  hintStyle: TextStyle(color: Colors.white54),
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) => _submit(),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Send',
                              onPressed: widget.busy ? null : _submit,
                              icon: widget.busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _purple,
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
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: ExcludeSemantics(
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black.withValues(alpha: 0.48),
            border: Border.all(color: color, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.22),
                blurRadius: 14,
              ),
            ],
          ),
          child: IconButton(
            tooltip: tooltip,
            icon: Icon(icon, color: color),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }
}

class _PlasmaOrb extends StatefulWidget {
  const _PlasmaOrb({
    required this.size,
    required this.accent,
    required this.mode,
  });

  final double size;
  final Color accent;
  final _OrbMode mode;

  @override
  State<_PlasmaOrb> createState() => _PlasmaOrbState();
}

class _PlasmaOrbState extends State<_PlasmaOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  bool? _reducedMotion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reducedMotion == reduced) return;
    _reducedMotion = reduced;
    if (reduced) {
      _motion.stop();
      _motion.value = 0.24;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size + 40,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: widget.size - 5,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (_, __) {
                final pulse = 0.5 + 0.5 * math.sin(_motion.value * math.pi * 4);
                final intensity = switch (widget.mode) {
                  _OrbMode.listening => 1.0,
                  _OrbMode.thinking => 0.88,
                  _OrbMode.speaking => 1.0,
                  _OrbMode.interrupted => 0.94,
                  _OrbMode.confused => 0.82,
                  _OrbMode.error => 0.42,
                  _OrbMode.idle => 0.58,
                };
                return Container(
                  width: widget.size * (0.58 + 0.08 * pulse),
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: RadialGradient(
                      colors: [
                        widget.accent.withValues(
                          alpha: (0.36 + 0.12 * pulse) * intensity,
                        ),
                        widget.accent.withValues(alpha: 0.08 * intensity),
                        Colors.transparent,
                      ],
                      stops: const [0, 0.46, 1],
                    ),
                  ),
                );
              },
            ),
          ),
          SizedBox.square(
            dimension: widget.size,
            child: AnimatedBuilder(
              animation: _motion,
              builder: (_, __) => CustomPaint(
                painter: _PlasmaOrbPainter(
                  accent: widget.accent,
                  phase: _motion.value,
                  mode: widget.mode,
                ),
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
    required this.phase,
    required this.mode,
  });

  final Color accent;
  final double phase;
  final _OrbMode mode;

  double get _energy => switch (mode) {
        _OrbMode.listening => 1.08,
        _OrbMode.thinking => 0.98,
        _OrbMode.speaking => 1.12,
        _OrbMode.interrupted => 1.0,
        _OrbMode.confused => 0.88,
        _OrbMode.error => 0.43,
        _OrbMode.idle => 0.68,
      };

  int get _filamentCount => switch (mode) {
        _OrbMode.listening => 40,
        _OrbMode.thinking => 34,
        _OrbMode.speaking => 44,
        _OrbMode.interrupted => 26,
        _OrbMode.confused => 22,
        _OrbMode.error => 12,
        _OrbMode.idle => 25,
      };

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 11;
    final spin = phase * math.pi * 2;
    final pulse = 0.5 + 0.5 * math.sin(spin * 2.15);
    final energy = _energy;

    canvas.drawCircle(
      center,
      radius * (1.01 + 0.018 * pulse),
      Paint()
        ..color = accent.withValues(
          alpha: math.min(1.0, (0.29 + 0.09 * pulse) * energy),
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.17),
    );

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          center: Alignment(0.08, 0.06),
          radius: 1.03,
          colors: [
            Color(0xFF2A0047),
            Color(0xFF18002D),
            Color(0xFF0C0016),
            Color(0xFF020004),
          ],
          stops: [0, 0.40, 0.78, 1],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: radius)),
    );

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(3.2, radius * 0.025)
      ..color = const Color(0xFF9B31FF).withValues(
        alpha: math.min(1.0, 0.30 * energy),
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.025);

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(0.9, radius * 0.0065)
      ..color = const Color(0xFFDFA6FF).withValues(
        alpha: math.min(1.0, 0.92 * energy),
      );

    final branch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.55, radius * 0.004)
      ..color = const Color(0xFFA83FFF).withValues(
        alpha: math.min(1.0, 0.66 * energy),
      );

    for (var i = 0; i < _filamentCount; i++) {
      final seed = i * 12.9898;
      var base = math.pi * 2 * i / _filamentCount;
      base += spin * (i.isEven ? 0.20 : -0.13);

      if (mode == _OrbMode.confused) {
        base += 0.16 * math.sin(spin * 7 + seed);
      } else if (mode == _OrbMode.interrupted) {
        base += 0.10 * math.sin(spin * 10 + seed);
      }

      final path = Path();
      Offset? previous;
      for (var step = 0; step <= 10; step++) {
        final t = step / 10;
        final radial = radius * (0.025 + 0.94 * t);
        final curl = 0.20 * math.sin(seed + t * 4.2 + spin * 1.3);
        final zig = 0.060 * math.sin(seed * 0.7 + step * 5.7 + spin * 3.2);
        final angle = base + curl * (1 - t * 0.32) + zig;
        final point = Offset(
          center.dx + math.cos(angle) * radial,
          center.dy + math.sin(angle) * radial,
        );

        if (step == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }

        if (previous != null && step >= 5 && step <= 8 && i % 3 == 0) {
          final direction = i.isEven ? 1.0 : -1.0;
          final branchAngle = angle + direction * (0.28 + 0.05 * math.sin(seed));
          final branchLength = radius * (0.12 + (8 - step) * 0.025);
          final end = Offset(
            point.dx + math.cos(branchAngle) * branchLength,
            point.dy + math.sin(branchAngle) * branchLength,
          );
          canvas.drawPath(
            Path()
              ..moveTo(previous.dx, previous.dy)
              ..quadraticBezierTo(point.dx, point.dy, end.dx, end.dy),
            branch,
          );
        }
        previous = point;
      }

      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
    }

    final coreRadius = radius * switch (mode) {
      _OrbMode.listening => 0.080 + 0.018 * pulse,
      _OrbMode.thinking => 0.090 + 0.026 * pulse,
      _OrbMode.speaking => 0.110 + 0.035 * pulse,
      _OrbMode.interrupted => 0.075 + 0.012 * pulse,
      _OrbMode.confused => 0.066 + 0.020 * pulse,
      _OrbMode.error => 0.055,
      _OrbMode.idle => 0.070 + 0.010 * pulse,
    };

    canvas.drawCircle(
      center,
      coreRadius * 2.6,
      Paint()
        ..color = accent.withValues(
          alpha: math.min(1.0, 0.44 * energy),
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.09),
    );
    canvas.drawCircle(
      center,
      coreRadius,
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Colors.white,
            Color(0xFFF6E8FF),
            Color(0xFFC968FF),
            Color(0x00A855F7),
          ],
          stops: [0, 0.28, 0.68, 1],
        ).createShader(
          Rect.fromCircle(center: center, radius: coreRadius * 1.25),
        ),
    );

    canvas.restore();

    if (mode == _OrbMode.confused || mode == _OrbMode.interrupted) {
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, radius * 0.008)
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFEAC8FF).withValues(alpha: 0.62);
      final gap = mode == _OrbMode.confused ? 0.62 : 0.38;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius * 0.88),
        spin,
        math.pi * 2 - gap,
        false,
        arc,
      );
    }

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.6, radius * 0.010)
        ..color = accent.withValues(
          alpha: math.min(1.0, 0.78 * energy),
        ),
    );

    canvas.drawCircle(
      center,
      radius * 1.015,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(4.0, radius * 0.025)
        ..color = accent.withValues(
          alpha: math.min(1.0, 0.18 * energy),
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.05),
    );
  }

  @override
  bool shouldRepaint(covariant _PlasmaOrbPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.accent != accent ||
      oldDelegate.mode != mode;
}
