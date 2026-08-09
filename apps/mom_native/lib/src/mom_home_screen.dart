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
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.72,
          child: replies.isEmpty
              ? const Center(child: Text('No replies yet.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                  itemCount: replies.length,
                  separatorBuilder: (_, __) => const Divider(height: 28),
                  itemBuilder: (_, index) => SelectableText(
                    replies[index].content,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
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
                    child: _RoundButton(
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
                          widget.busy
                              ? 'Thinking...'
                              : widget.listening
                                  ? 'Listening...'
                                  : 'Tap the mic',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: const Color(0xFFD990FF),
                            fontSize: constraints.maxWidth < 500 ? 30 : 36,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: accent.withOpacity(0.55), blurRadius: 24),
                            ],
                          ),
                        ),
                        const SizedBox(height: 22),
                        _PlasmaOrb(
                          size: orbSize,
                          accent: accent,
                          energized: widget.busy || widget.listening,
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
                                          color: const Color(0xFFD990FF),
                                          fontSize: constraints.maxWidth < 500 ? 18 : 21,
                                          height: 1.28,
                                          fontWeight: FontWeight.w600,
                                          shadows: [
                                            Shadow(
                                              color: accent.withOpacity(0.36),
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
                  child: Text(
                    'MOM 0.5.0',
                    style: TextStyle(color: accent, fontWeight: FontWeight.w600),
                  ),
                ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: _RoundButton(
                    icon: Icons.keyboard,
                    color: accent,
                    tooltip: 'Text MOM',
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
                          border: Border.all(color: accent.withOpacity(0.72), width: 1.4),
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
                                decoration: const InputDecoration(
                                  hintText: 'Text MOM…',
                                  hintStyle: TextStyle(color: Colors.white54),
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
                                      child: CircularProgressIndicator(strokeWidth: 2),
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
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withOpacity(0.48),
        border: Border.all(color: color, width: 2),
        boxShadow: [BoxShadow(color: color.withOpacity(0.22), blurRadius: 14)],
      ),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: color),
        onPressed: onPressed,
      ),
    );
  }
}

class _PlasmaOrb extends StatefulWidget {
  const _PlasmaOrb({
    required this.size,
    required this.accent,
    required this.energized,
  });

  final double size;
  final Color accent;
  final bool energized;

  @override
  State<_PlasmaOrb> createState() => _PlasmaOrbState();
}

class _PlasmaOrbState extends State<_PlasmaOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    )..repeat();
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
                return Container(
                  width: widget.size * (0.58 + 0.08 * pulse),
                  height: 34,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: RadialGradient(
                      colors: [
                        widget.accent.withOpacity(0.36 + 0.12 * pulse),
                        widget.accent.withOpacity(0.08),
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

class _PlasmaOrbPainter extends CustomPainter {
  const _PlasmaOrbPainter({
    required this.accent,
    required this.phase,
    required this.energized,
  });

  final Color accent;
  final double phase;
  final bool energized;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 11;
    final spin = phase * math.pi * 2;
    final pulse = 0.5 + 0.5 * math.sin(spin * 2.15);
    final energy = energized ? 1.0 : 0.78;

    canvas.drawCircle(
      center,
      radius * (1.01 + 0.018 * pulse),
      Paint()
        ..color = accent.withOpacity((0.29 + 0.09 * pulse) * energy)
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
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(3.2, radius * 0.025)
      ..color = const Color(0xFF9B31FF).withOpacity(0.30 * energy)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.025);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(0.9, radius * 0.0065)
      ..color = const Color(0xFFDFA6FF).withOpacity(0.92 * energy);
    final branch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = math.max(0.55, radius * 0.004)
      ..color = const Color(0xFFC56CFF).withOpacity(0.70 * energy);

    final count = energized ? 22 : 18;
    for (var i = 0; i < count; i++) {
      final seed = (i + 1) * 13.731;
      final base = math.pi * 2 * i / count +
          0.08 * math.sin(seed) +
          spin * (i.isEven ? 0.018 : -0.014);
      final points = <Offset>[];
      final filament = Path();
      for (var step = 0; step <= 11; step++) {
        final t = step / 11;
        final radial = radius * (0.035 + 0.935 * t);
        final jitter =
            0.12 * math.sin(seed + step * 2.47 + spin * 0.8) +
            0.045 * math.sin(seed * 0.43 + step * 5.31 - spin * 1.2);
        final angle = base + jitter * (0.35 + 0.65 * t);
        final point = Offset(
          center.dx + math.cos(angle) * radial,
          center.dy + math.sin(angle) * radial,
        );
        points.add(point);
        if (step == 0) {
          filament.moveTo(point.dx, point.dy);
        } else {
          filament.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(filament, glow);
      canvas.drawPath(filament, line);

      for (final at in const [4, 7]) {
        if ((i + at) % 3 != 0) continue;
        final start = points[at];
        final sign = (i + at).isEven ? 1.0 : -1.0;
        final twig = Path()..moveTo(start.dx, start.dy);
        for (var j = 1; j <= 3; j++) {
          final t = ((at + j) / 11).clamp(0.0, 1.0).toDouble();
          final radial = radius * (0.035 + 0.935 * t);
          final angle = base +
              sign * (0.20 + j * 0.055) +
              0.07 * math.sin(seed + at + j * 3.2 + spin);
          final point = Offset(
            center.dx + math.cos(angle) * radial,
            center.dy + math.sin(angle) * radial,
          );
          twig.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(twig, branch);
      }
    }

    canvas.drawCircle(
      center,
      radius * (0.12 + 0.014 * pulse),
      Paint()
        ..shader = const RadialGradient(
          colors: [
            Colors.white,
            Color(0xFFFFE9FF),
            Color(0xFFD677FF),
            Color(0x009C2CFF),
          ],
          stops: [0, 0.26, 0.58, 1],
        ).createShader(
          Rect.fromCircle(center: center, radius: radius * 0.14),
        ),
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(5.0, radius * 0.035)
        ..color = const Color(0xFF9F2EFF).withOpacity(0.34 * energy)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.045),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.3, radius * 0.009)
        ..color = const Color(0xFFE7B5FF).withOpacity(0.90 * energy),
    );
  }

  @override
  bool shouldRepaint(covariant _PlasmaOrbPainter oldDelegate) =>
      oldDelegate.phase != phase ||
      oldDelegate.accent != accent ||
      oldDelegate.energized != energized;
}
