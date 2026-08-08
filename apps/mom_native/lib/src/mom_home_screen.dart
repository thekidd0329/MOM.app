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

class _MomHomeScreenState extends State<MomHomeScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  bool _textMode = false;
  String _caption = '';
  int _captionRun = 0;
  String? _lastCaptionId;

  @override
  void initState() {
    super.initState();
    _maybeStartLatestCaption();
  }

  @override
  void didUpdateWidget(covariant MomHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.turns.length != widget.turns.length) {
      _maybeStartLatestCaption();
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

    // Keep the latest reply visible until MOM says something else. Reading speed
    // belongs to the user; the UI must not drip-feed text or erase it.
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
    await widget.onProbeMicrophone(true);
    if (!mounted) return;

    setState(() {
      _textMode = true;
      _caption = 'Use the microphone on your keyboard to talk to me.';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _textFocus.requestFocus();
    });
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

  @override
  void dispose() {
    _captionRun++;
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
                    icon: widget.microphone.available ? Icons.mic : Icons.mic_none,
                    color: accent,
                    tooltip: widget.microphone.permissionGranted
                        ? 'Use microphone'
                        : 'Enable microphone',
                    onPressed: _handleMicTap,
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
                        _ElectricOrb(
                          size: resolvedOrbSize,
                          accent: accent,
                          lightMode: !dark,
                          energized: widget.busy,
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
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(12),
                                    onTap: _showHistory,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: Text(
                                        _captionWindow,
                                        maxLines: 5,
                                        overflow: TextOverflow.ellipsis,
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
                    'MOM Beta 0.4',
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
                      onPressed: _toggleTextMode,
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
        ),
      ),
    );
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
                        widget.accent.withOpacity(
                          widget.lightMode ? 0.15 + 0.08 * pulse : 0.25 + 0.12 * pulse,
                        ),
                        widget.accent.withOpacity(0),
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
      ..color = accent.withOpacity(
        (lightMode ? 0.18 : 0.31) * (0.86 + 0.18 * pulse) * heat,
      )
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.18);
    canvas.drawCircle(center, radius * (0.98 + 0.025 * pulse), outerGlow);

    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.18, -0.22),
        radius: 1.05,
        colors: [
          Colors.white.withOpacity(lightMode ? 0.97 : 0.93),
          const Color(0xFFE9C5FF).withOpacity(0.98),
          accent.withOpacity(0.94),
          const Color(0xFF5B0FA3),
          const Color(0xFF140020),
        ],
        stops: const [0.0, 0.07, 0.28, 0.66, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, body);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    final deepGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withOpacity(0.14 + 0.08 * pulse),
          const Color(0x00140020),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.88));
    canvas.drawCircle(center, radius * 0.9, deepGlow);

    final ringPaintBack = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.8, radius * 0.005)
      ..color = accent.withOpacity(lightMode ? 0.20 : 0.28);
    final ringPaintFront = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, radius * 0.007)
      ..color = const Color(0xFFF5E6FF).withOpacity(0.32 + 0.12 * pulse)
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
      ..color = accent.withOpacity(0.48 * heat);

    final hot = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(1.0, radius * 0.007)
      ..color = const Color(0xFFF8EEFF).withOpacity(0.88 * heat)
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
          Colors.white.withOpacity(0.98),
          const Color(0xFFF3DEFF).withOpacity(0.92),
          accent.withOpacity(0.55),
          accent.withOpacity(0),
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
      ..color = accent.withOpacity((lightMode ? 0.12 : 0.20) * heat)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.05);
    canvas.drawCircle(center, radius, rimGlow);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, radius * 0.009)
      ..shader = SweepGradient(
        transform: GradientRotation(spin),
        colors: [
          accent.withOpacity(0.35),
          const Color(0xFFF4E4FF).withOpacity(0.95),
          accent.withOpacity(0.45),
          const Color(0xFF7D26C9).withOpacity(0.75),
          accent.withOpacity(0.35),
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
