import 'dart:math' as math;

import 'package:flutter/material.dart';

const garibaldiInk = Color(0xFF080D10);
const garibaldiGold = Color(0xFFF0B35D);

class GaribaldiSplash extends StatefulWidget {
  const GaribaldiSplash({super.key});

  @override
  State<GaribaldiSplash> createState() => _GaribaldiSplashState();
}

class _GaribaldiSplashState extends State<GaribaldiSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: garibaldiInk,
    body: Stack(
      fit: StackFit.expand,
      children: [
        const _AmbientLight(),
        SafeArea(
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final eased = Curves.easeInOut.transform(_controller.value);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.scale(
                      scale: .96 + eased * .04,
                      child: CustomPaint(
                        size: const Size(142, 142),
                        painter: _SoundMarkPainter(progress: eased),
                      ),
                    ),
                    const SizedBox(height: 28),
                    Opacity(
                      opacity: .72 + eased * .28,
                      child: const Text(
                        'GARIBALDI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 6.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'MÚSICA EN VIVO, MÁS CERCA DE TI.',
                      style: TextStyle(
                        color: Color(0xFFB9BDC0),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 2.4,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );
}

class _AmbientLight extends StatelessWidget {
  const _AmbientLight();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(.15, -.22),
        radius: 1.05,
        colors: [Color(0x332F3538), garibaldiInk],
        stops: [0, 1],
      ),
    ),
  );
}

class _SoundMarkPainter extends CustomPainter {
  const _SoundMarkPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const heights = [44.0, 76.0, 120.0, 76.0, 44.0];
    final center = Offset(size.width / 2, size.height / 2);
    const barWidth = 15.0;
    const gap = 9.0;

    for (var index = 0; index < heights.length; index++) {
      final pulse = .92 + .08 * math.sin(progress * math.pi + index * .72);
      final height = heights[index] * pulse;
      final x = center.dx + (index - 2) * (barWidth + gap) - barWidth / 2;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, center.dy - height / 2, barWidth, height),
        const Radius.circular(12),
      );
      final paint =
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors:
                  index == 2
                      ? const [Color(0xFFFFD99E), garibaldiGold]
                      : const [Colors.white, Color(0xFFC6C8CA)],
            ).createShader(rect.outerRect);
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_SoundMarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
