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
  static const Color _plasmaPurple = Color(0xFFA020F0);

  final TextEditingController _controller = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  late final AnimationController _entrance;
  late final AnimationController _zapMotion;

  bool _textMode = false;
  String _caption = '';
  int _captionRun = 0;
  String? _lastCaptionId;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2900),
    );
    _zapMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..repeat();
    _entrance.addStatusListener((status) {
      if (status == AnimationStatus.completed) _zapMotion.stop();
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

  Future<void> _handleMicTap() => widget.onMicTap();

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

  double _reveal(double start, {double span = 0.09}) {
    return ((_entrance.value - start) / span).clamp(0.0, 1.0).toDouble();
  }

  Widget _zappedIn({
    required double start,
    required Widget child,
    Alignment origin = Alignment.center,
  }) {
    final raw = _reveal(start);
    final scale = Curves.easeOutBack.transform(raw);
    return Opacity(
      opacity: _reveal(start, span: 0.05),
      child: Transform.scale(
        alignment: origin,
        scale: 0.48 + (0.52 * scale),
        child: child,
      ),
    );
  }

  String get _statusLabel {
    if (widget.busy) return 'Thinking...';
    if (widget.listening) return 'Listening...';
    return widget.status == 'online' ? 'Listening...' : widget.status;
  }

  @override
  void dispose() {
    _captionRun++;
    _entrance.dispose();
    _zapMotion.dispose();
    _textFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? Colors.black : Colors.white;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final viewport = Size(constraints.maxWidth, constraints.maxHeight);
            final orbSize = math.min(
              constraints.maxWidth * 0.64,
              constraints.maxHeight * 0.36,
            ).clamp(210.0, 360.0).toDouble();
            final orbCenter = Offset(
              viewport.width / 2,
              viewport.height * 0.46,
            );
            final orbRadius = orbSize * 0.40;

            return AnimatedBuilder(
              animation: Listenable.merge([_entrance, _zapMotion]),
              builder: (context, _) => Stack(
                children: [
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 70, 16, 92),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _statusLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _plasmaPurple,
                              fontSize: constraints.maxWidth < 500 ? 27 : 32,
                              fontWeight: FontWeight.w600,
                              shadows: const [
                                Shadow(color: _plasmaPurple, blurRadius: 14),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            label: 'MOM plasma logo',
                            image: true,
                            child: SizedBox.square(
                              dimension: orbSize,
                              child: Image.asset(
                                'assets/photopea_background_remover_1786650252951.png',
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.high,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
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
                                            color: _plasmaPurple,
                                            fontSize:
                                                constraints.maxWidth < 500 ? 18 : 21,
                                            height: 1.28,
                                            fontWeight: FontWeight.w600,
                                            shadows: [
                                              Shadow(
                                                color: _plasmaPurple.withValues(
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
                          progress: _entrance.value,
                          phase: _zapMotion.value,
                          source: orbCenter,
                          sourceRadius: orbRadius,
                          viewport: viewport,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    child: _zappedIn(
                      start: 0.34,
                      origin: Alignment.topLeft,
                      child: _OutlineIconButton(
                        icon: widget.listening
                            ? Icons.stop_rounded
                            : widget.microphone.available
                                ? Icons.mic
                                : Icons.mic_none,
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
                      start: 0.52,
                      origin: Alignment.topRight,
                      child: _OutlineIconButton(
                        icon: Icons.settings,
                        tooltip: 'Settings',
                        onPressed: widget.onSettings,
                        onLongPress: widget.onDiagnostics,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 28,
                    left: 24,
                    child: _zappedIn(
                      start: 0.68,
                      origin: Alignment.bottomLeft,
                      child: const Text(
                        'Version 1.1.0',
                        style: TextStyle(
                          color: _plasmaPurple,
                          fontWeight: FontWeight.w600,
                          shadows: [
                            Shadow(color: _plasmaPurple, blurRadius: 9),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    right: 16,
                    child: _zappedIn(
                      start: 0.80,
                      origin: Alignment.bottomRight,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _plasmaPurple, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: _plasmaPurple.withValues(alpha: 0.18),
                              blurRadius: 12,
                            ),
                          ],
                        ),
                        child: IconButton(
                          tooltip: 'Text MOM',
                          icon: const Icon(Icons.keyboard, color: _plasmaPurple),
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
                              color: _plasmaPurple.withValues(alpha: 0.72),
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
                                    : const Icon(
                                        Icons.arrow_upward,
                                        color: _plasmaPurple,
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
    required this.onPressed,
    required this.tooltip,
    this.onLongPress,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String tooltip;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tooltip,
      button: true,
      enabled: true,
      onTap: onPressed,
      onLongPress: onLongPress,
      child: ExcludeSemantics(
        child: Tooltip(
          message: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            onLongPress: onLongPress,
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _MomPlasmaColors.purple, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _MomPlasmaColors.purple.withValues(alpha: 0.20),
                    blurRadius: 13,
                  ),
                ],
              ),
              child: Icon(icon, color: _MomPlasmaColors.purple),
            ),
          ),
        ),
      ),
    );
  }
}

abstract final class _MomPlasmaColors {
  static const purple = Color(0xFFA020F0);
}

class _ControlZapPainter extends CustomPainter {
  const _ControlZapPainter({
    required this.progress,
    required this.phase,
    required this.source,
    required this.sourceRadius,
    required this.viewport,
  });

  final double progress;
  final double phase;
  final Offset source;
  final double sourceRadius;
  final Size viewport;

  @override
  void paint(Canvas canvas, Size size) {
    final targets = <_ZapTarget>[
      _ZapTarget(Offset(42, 42), 0.27, 0.40, 11),
      _ZapTarget(Offset(viewport.width - 42, 42), 0.45, 0.58, 23),
      _ZapTarget(Offset(66, viewport.height - 34), 0.61, 0.72, 37),
      _ZapTarget(
        Offset(viewport.width - 42, viewport.height - 42),
        0.73,
        0.84,
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
      (local * 1.16).clamp(0.0, 1.0).toDouble(),
    );
    final end = Offset.lerp(start, target.point, travel)!;
    final direction = end - start;
    final length = direction.distance;
    if (length <= 1) return;

    final perpendicular = Offset(-direction.dy, direction.dx) / length;
    final segments = math.max(7, (length / 30).round()).toInt();
    final path = Path()..moveTo(start.dx, start.dy);

    for (var i = 1; i < segments; i++) {
      final t = i / segments;
      final base = Offset.lerp(start, end, t)!;
      final envelope = math.sin(t * math.pi);
      final noise = math.sin(
        i * 9.17 + target.seed * 1.73 + phase * math.pi * 4,
      );
      final point = base + perpendicular * noise * 12 * envelope;
      path.lineTo(point.dx, point.dy);
    }
    path.lineTo(end.dx, end.dy);

    final flash = math.sin(local * math.pi).abs();
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 12
      ..color = _MomPlasmaColors.purple.withValues(alpha: 0.32 * flash)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    final purple = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 5
      ..color = _MomPlasmaColors.purple.withValues(alpha: 0.86 * flash)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2
      ..color = Colors.white.withValues(alpha: 0.98 * flash);

    canvas.drawPath(path, glow);
    canvas.drawPath(path, purple);
    canvas.drawPath(path, core);

    if (local > 0.68) {
      final impact = ((local - 0.68) / 0.32).clamp(0.0, 1.0).toDouble();
      final impactAlpha = math.sin(impact * math.pi).abs();
      final impactPaint = Paint()
        ..color = _MomPlasmaColors.purple.withValues(
          alpha: 0.48 * impactAlpha,
        )
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawCircle(target.point, 18 + 16 * impactAlpha, impactPaint);
      canvas.drawCircle(
        target.point,
        2.5 + 4 * impactAlpha,
        Paint()..color = Colors.white.withValues(alpha: impactAlpha),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ControlZapPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.phase != phase ||
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
