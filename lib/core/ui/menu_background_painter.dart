import 'dart:math';

import 'package:flutter/material.dart';

/// Animated background with dot grid and soft floating particles.
class MenuBackgroundPainter extends CustomPainter {
  const MenuBackgroundPainter({required this.time});

  final double time;

  static const _particleColors = [
    Color(0x28A8D4B0), // sage
    Color(0x225A9E6A), // meadow
    Color(0x22C8A87A), // sand
    Color(0x227AB0CC), // sky
    Color(0x22C4864A), // copper
    Color(0x223A6B47), // forest
    Color(0x228A9E8C), // mist
  ];

  @override
  void paint(Canvas canvas, Size size) {
    // Soft dot grid
    final dotPaint = Paint()..color = const Color(0x0DFFFFFF);
    const spacing = 40.0;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 0.8, dotPaint);
      }
    }

    // Floating particles — soft colored bokeh drifting gently.
    final rng = Random(42);
    for (int i = 0; i < 15; i++) {
      final baseX = rng.nextDouble();
      final baseY = rng.nextDouble();
      final radius = 8.0 + rng.nextDouble() * 28;
      final freq = (1 + rng.nextInt(3)).toDouble();
      final phaseX = rng.nextDouble() * 2 * pi;
      final phaseY = rng.nextDouble() * 2 * pi;
      final drift = 12.0 + rng.nextDouble() * 20;

      final x = baseX * size.width + sin(time * 2 * pi * freq + phaseX) * drift;
      final y =
          baseY * size.height + cos(time * 2 * pi * freq + phaseY) * drift;

      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()
          ..color = _particleColors[i % _particleColors.length]
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.6),
      );
    }

    // Soft vignette
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x00000000), Color(0x30000000)],
          stops: [0.6, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(MenuBackgroundPainter old) => old.time != time;
}
