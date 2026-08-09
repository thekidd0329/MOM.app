import 'dart:math' as math;

import 'package:flutter/material.dart';

class MomLaunchScreen extends StatefulWidget {
  const MomLaunchScreen({super.key, required this.status});

  final String status;

  @override
  State<MomLaunchScreen> createState() => _MomLaunchScreenState();
}

class _MomLaunchScreenState extends State<MomLaunchScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4400),
    )..repeat();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFA855F7);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final lockupWidth = math.min(constraints.maxWidth * 0.90, 520.0);
            final rawOrb = (constraints.maxWidth * 0.30).clamp(104.0, 158.0).toDouble();
            return Stack(
              children: [
                Center(
                  child: Transform.translate(
                    offset: const Offset(0, -24),
                    child: SizedBox(
                      width: lockupWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Text(
                                  'M',
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 178,
                                    height: 0.82,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -9,
                                  ),
                                ),
                                SizedBox(
                                  width: rawOrb,
                                  height: rawOrb + 20,
                                  child: AnimatedBuilder(
                                    animation: _spin,
                                    builder: (context, _) => CustomPaint(
                                      painter: _LaunchOrbPainter(
                                        accent: accent,
                                        phase: _spin.value,
                                      ),
                                    ),
                                  ),
                                ),
                                const Text(
                                  'M',
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 178,
                                    height: 0.82,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -9,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(width: 72, height: 2, color: accent),
                                const SizedBox(width: 16),
                                const Text(
                                  'app',
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 60,
                                    height: 0.9,
                                    fontWeight: FontWeight.w200,
                                    letterSpacing: 5,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Container(width: 72, height: 2, color: accent),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: AnimatedOpacity(
                    opacity: widget.status == 'online' ? 0 : 0.56,
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      widget.status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
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

class _LaunchOrbPainter extends CustomPainter {
  const _LaunchOrbPainter({required this.accent, required this.phase});

  final Color accent;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height - 20);
    final center = Offset(size.width / 2, side / 2);
    final radius = side / 2 - 6;
    final spin = phase * math.pi * 2;
    final pulse = 0.5 + 0.5 * math.sin(spin * 2.0);

    final shadow = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: 0.30),
          accent.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCenter(
          center: Offset(center.dx, side + 5),
          width: radius * 1.5,
          height: 22,
        ),
      );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center.dx, side + 5),
        width: radius * 1.5,
        height: 22,
      ),
      shadow,
    );

    final glow = Paint()
      ..color = accent.withValues(alpha: 0.30 + 0.10 * pulse)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.14);
    canvas.drawCircle(center, radius, glow);

    final body = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.16, -0.18),
        radius: 1.0,
        colors: [
          Colors.white,
          const Color(0xFFEBCBFF),
          accent,
          const Color(0xFF5D159C),
          const Color(0xFF12001E),
        ],
        stops: const [0.0, 0.06, 0.28, 0.66, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, body);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));

    final faint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(0.8, radius * 0.009)
      ..color = accent.withValues(alpha: 0.68);
    final hot = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = math.max(1.2, radius * 0.014)
      ..color = Colors.white.withValues(alpha: 0.92)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.008);

    const rays = 22;
    for (var i = 0; i < rays; i++) {
      final base = spin * (i.isEven ? 0.42 : -0.32) + math.pi * 2 * i / rays;
      final path = Path()..moveTo(center.dx, center.dy);
      for (var step = 1; step <= 8; step++) {
        final t = step / 8;
        final radial = radius * (0.08 + 0.90 * t);
        final kink = 0.10 * math.sin(i * 9.1 + step * 4.7 + spin * 3.0);
        final angle = base + kink + 0.20 * math.sin(t * math.pi) * math.sin(i + spin);
        path.lineTo(
          center.dx + math.cos(angle) * radial,
          center.dy + math.sin(angle) * radial * 0.82,
        );
      }
      canvas.drawPath(path, i % 4 == 0 ? hot : faint);
    }

    final core = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.white.withValues(alpha: 0.80),
          accent.withValues(alpha: 0),
        ],
      ).createShader(
        Rect.fromCircle(center: center, radius: radius * (0.18 + 0.03 * pulse)),
      );
    canvas.drawCircle(center, radius * (0.18 + 0.03 * pulse), core);
    canvas.restore();

    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.2, radius * 0.012)
      ..color = const Color(0xFFF4E4FF).withValues(alpha: 0.78);
    canvas.drawCircle(center, radius, rim);
  }

  @override
  bool shouldRepaint(covariant _LaunchOrbPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.accent != accent;
}
