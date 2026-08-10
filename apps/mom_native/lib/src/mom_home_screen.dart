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

class _MomHomeScreenState extends State<MomHomeScreen>
    with TickerProviderStateMixin {
  static const _canonicalArtwork = 'assets/ui/2546.png';

  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFocus = FocusNode();

  late final AnimationController _entrance;
  late final AnimationController _electricity;

  bool _textMode = false;
  String _caption = '';
  int _captionRun = 0;
  String? _lastCaptionId;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _electricity = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    )..repeat();
    _entrance.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _electricity.stop();
      }
    });
    _entrance.forward();
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
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(height: 1.4),
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

  double _reveal(double start, {double span = 0.10}) {
    return ((_entrance.value - start) / span).clamp(0.0, 1.0).toDouble();
  }

  Widget _zappedIn({
    required double start,
    required Widget child,
    Alignment origin = Alignment.center,
  }) {
    final raw = _reveal(start);
    final scaleProgress = Curves.easeOutBack.transform(raw);
    return Opacity(
      opacity: _reveal(start, span: 0.055),
      child: Transform.scale(
        alignment: origin,
        scale: 0.55 + (0.45 * scaleProgress),
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    _captionRun++;
    _entrance.dispose();
    _electricity.dispose();
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
            final viewport = Size(constraints.maxWidth, constraints.maxHeight);
            final artworkSize = math.min(
              constraints.maxWidth * 0.94,
              constraints.maxHeight * 0.66,
            ).clamp(230.0, 650.0).toDouble();

            // 2546.png includes the canonical glowing "Listening…" treatment.
            // Keep that image untouched. Its plasma center sits below the image
            // midpoint, so strikes originate from the visible globe rather than
            // from the baked-in title area.
            final strikeSource = Offset(
              viewport.width / 2,
              viewport.height * 0.52,
            );
            final sourceRadius = artworkSize * 0.22;

            return AnimatedBuilder(
              animation: Listenable.merge([_entrance, _electricity]),
              builder: (context, _) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 52, 14, 86),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Semantics(
                              label: widget.busy
                                  ? 'MOM is thinking'
                                  : widget.listening
                                      ? 'MOM is listening'
                                      : 'MOM ${widget.status}',
                              image: true,
                              child: SizedBox.square(
                                dimension: artworkSize,
                                child: Image.asset(
                                  _canonicalArtwork,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  gaplessPlayback: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 160),
                              child: _caption.isEmpty
                                  ? const SizedBox(height: 64)
                                  : ConstrainedBox(
                                      key: ValueKey(_captionWindow),
                                      constraints: BoxConstraints(
                                        maxWidth: math.min(
                                          720,
                                          constraints.maxWidth * 0.9,
                                        ),
                                      ),
                                      child: InkWell(
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
                                              fontSize:
                                                  constraints.maxWidth < 500
                                                      ? 18
                                                      : 21,
                                              height: 1.28,
                                              fontWeight: FontWeight.w600,
                                              shadows: [
                                                Shadow(
                                                  color: accent.withValues(
                                                    alpha: 0.24,
                                                  ),
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
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _ControlZapPainter(
                            accent: accent,
                            progress: _entrance.value,
                            phase: _electricity.value,
                            source: strikeSource,
                            sourceRadius: sourceRadius,
                            viewport: viewport,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      child: _zappedIn(
                        start: 0.20,
                        origin: Alignment.topLeft,
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
                      child: _zappedIn(
                        start: 0.38,
                        origin: Alignment.topRight,
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
                      child: _zappedIn(
                        start: 0.56,
                        origin: Alignment.bottomLeft,
                        child: Text(
                          'Version 1.0.1',
                          style: TextStyle(
                            color: accent,
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(
                                color: accent.withValues(alpha: 0.24),
                                blurRadius: 9,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: _zappedIn(
                        start: 0.74,
                        origin: Alignment.bottomRight,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: accent, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: accent.withValues(alpha: 0.15),
                                blurRadius: 12,
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
                                      : Icon(
                                          Icons.arrow_upward,
                                          color: accent,
                                        ),
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
            color: color.withValues(alpha: 0.17),
            blurRadius: 12,
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

class _ControlZapPainter extends CustomPainter {
  const _ControlZapPainter({
    required this.accent,
    required this.progress,
    required this.phase,
    required this.source,
    required this.sourceRadius,
    required this.viewport,
  });

  final Color accent;
  final double progress;
  final double phase;
  final Offset source;
  final double sourceRadius;
  final Size viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final targets = <_ZapTarget>[
      _ZapTarget(Offset(42, 42), 0.08, 0.25, 11),
      _ZapTarget(Offset(viewport.width - 42, 42), 0.26, 0.43, 23),
      _ZapTarget(Offset(66, viewport.height - 34), 0.44, 0.61, 37),
      _ZapTarget(
        Offset(viewport.width - 42, viewport.height - 42),
        0.62,
        0.79,
        53,
      ),
    ];

    for (final target in targets) {
      _drawStrike(canvas, target);
    }
  }

  void _drawStrike(Canvas canvas, _ZapTarget target) {
    final local = ((progress - target.start) / (target.end - target.start))
        .clamp(0.0, 1.0)
        .toDouble();
    if (local <= 0 || local >= 1) return;

    final fullDirection = target.point - source;
    final fullLength = fullDirection.distance;
    if (fullLength <= sourceRadius + 1) return;

    final unit = fullDirection / fullLength;
    final start = source + (unit * sourceRadius);
    final travel = Curves.easeOutCubic.transform(
      (local * 1.18).clamp(0.0, 1.0).toDouble(),
    );
    final end = Offset.lerp(start, target.point, travel)!;
    final direction = end - start;
    final length = direction.distance;
    if (length <= 1) return;

    final perpendicular = Offset(-direction.dy, direction.dx) / length;
    final segments = math.max(9, (length / 28).round()).toInt();
    final path = Path()..moveTo(start.dx, start.dy);
    final points = <Offset>[start];

    for (var i = 1; i < segments; i++) {
      final t = i / segments;
      final base = Offset.lerp(start, end, t)!;
      final envelope = math.sin(t * math.pi);
      final noise = math.sin(
        (i * 9.17) +
            (target.seed * 1.73) +
            (phase * math.pi * 4),
      );
      final secondary = math.sin(
        (i * 4.63) -
            (target.seed * 0.91) +
            (phase * math.pi * 7),
      );
      final jitter = perpendicular *
          (noise * 10 + secondary * 4) *
          envelope;
      final point = base + jitter;
      points.add(point);
      path.lineTo(point.dx, point.dy);
    }
    points.add(end);
    path.lineTo(end.dx, end.dy);

    final flash = math.sin(local * math.pi).abs();
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 10
      ..color = accent.withValues(alpha: 0.27 * flash)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    final purplePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.6
      ..color = accent.withValues(alpha: 0.78 * flash)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.8
      ..color = Colors.white.withValues(alpha: 0.96 * flash);

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, purplePaint);
    canvas.drawPath(path, corePaint);

    final branchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.1
      ..color = Colors.white.withValues(alpha: 0.55 * flash);
    for (var i = 3; i < points.length - 2; i += 4) {
      final point = points[i];
      final sign = ((i + target.seed).isEven) ? 1.0 : -1.0;
      final branchLength = 10.0 + ((target.seed + i) % 8);
      final branchEnd = point + (perpendicular * branchLength * sign);
      canvas.drawLine(point, branchEnd, branchPaint);
    }

    if (local > 0.67) {
      final impact = ((local - 0.67) / 0.33).clamp(0.0, 1.0).toDouble();
      final impactAlpha = math.sin(impact * math.pi).abs();
      final impactPaint = Paint()
        ..color = accent.withValues(alpha: 0.42 * impactAlpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawCircle(target.point, 18 + 15 * impactAlpha, impactPaint);

      final hotImpact = Paint()
        ..color = Colors.white.withValues(alpha: 0.92 * impactAlpha);
      canvas.drawCircle(target.point, 2.5 + 4.0 * impactAlpha, hotImpact);
    }
  }

  @override
  bool shouldRepaint(covariant _ControlZapPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
        oldDelegate.accent != accent ||
        oldDelegate.source != source ||
        oldDelegate.sourceRadius != sourceRadius ||
        oldDelegate.viewport != viewport;
  }
}

class _ZapTarget {
  const _ZapTarget(this.point, this.start, this.end, this.seed);

  final Offset point;
  final double start;
  final double end;
  final int seed;
}
