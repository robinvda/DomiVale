import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../game/render_profiler.dart';
import 'package:vale_engine/theme/engine_palette.dart';
import 'package:vale_engine/utils/viewport_utils.dart';

/// A single expanding ring, in world-tile coordinates.
class _Ripple {
  _Ripple(this.x, this.y);

  final double x;
  final double y;

  /// Seconds since the press, counted in real time.
  double age = 0.0;
}

/// Draws a ring spreading out from wherever the player pressed, so whatever
/// the game does in response reads as having been set off by it.
class TapRippleRenderer extends Component {
  TapRippleRenderer({
    required this.maxRadiusTiles,
    required this.tileSize,
  });

  /// How far the ring spreads, in tiles.
  final double maxRadiusTiles;

  final double tileSize;

  /// How long a ring takes to fade out.
  static const double _duration = 0.55;

  /// Opacity the ring starts at.
  static const double _startOpacity = 0.55;

  /// Ring thickness at the start and end of its life, in logical pixels.
  static const double _startStroke = 3.0;
  static const double _endStroke = 1.0;

  /// How far the second ring trails the first, as a share of the duration,
  /// and how much fainter it is.
  static const double _trailingLag = 0.18;
  static const double _trailingOpacity = 0.6;

  /// Rings kept at once. Rapid pressing drops the oldest rather than piling
  /// up work for the renderer.
  static const int _maxRipples = 8;

  final List<_Ripple> _ripples = [];

  final Paint _paint = Paint()..style = PaintingStyle.stroke;

  /// Rings currently on screen.
  int get activeRipples => _ripples.length;

  /// Starts a ring at the given world-tile position.
  void spawn(double tileX, double tileY) {
    if (_ripples.length >= _maxRipples) _ripples.removeAt(0);
    _ripples.add(_Ripple(tileX, tileY));
  }

  @override
  void update(double dt) {
    if (_ripples.isEmpty) return;
    // Deliberately real time, not simulation time: this answers a press the
    // player just made, so it plays out even while the game is paused.
    for (var i = _ripples.length - 1; i >= 0; i--) {
      final ripple = _ripples[i];
      ripple.age += dt;
      if (ripple.age >= _duration) _ripples.removeAt(i);
    }
  }

  @override
  void render(Canvas canvas) {
    if (_ripples.isEmpty) return;
    final game = findGame();
    if (game is! FlameGame) return;

    RenderProfiler.instance.begin('TapRipple');
    final visibleRect = getVisibleWorldRect(game, tileSize);
    final maxRadius = maxRadiusTiles * tileSize;

    for (final ripple in _ripples) {
      final x = ripple.x * tileSize;
      final y = ripple.y * tileSize;
      if (x + maxRadius < visibleRect.left ||
          x - maxRadius > visibleRect.right ||
          y + maxRadius < visibleRect.top ||
          y - maxRadius > visibleRect.bottom) {
        continue;
      }

      final t = ripple.age / _duration;
      _drawRing(canvas, x, y, t, maxRadius, 1.0);
      // A second ring chasing the first is what makes it read as a ripple
      // rather than a single expanding circle.
      final trailing = t - _trailingLag;
      if (trailing > 0.0) {
        _drawRing(canvas, x, y, trailing, maxRadius, _trailingOpacity);
      }
    }
    RenderProfiler.instance.end('TapRipple');
  }

  /// Draws one ring at [phase] through its life (0 at the press, 1 when gone).
  void _drawRing(
    Canvas canvas,
    double x,
    double y,
    double phase,
    double maxRadius,
    double opacityScale,
  ) {
    // Races out and eases off, the way a disturbance actually spreads.
    final eased = 1.0 - (1.0 - phase) * (1.0 - phase);
    _paint
      ..color = EnginePalette.tapRipple
          .withValues(alpha: _startOpacity * opacityScale * (1.0 - phase))
      ..strokeWidth = _startStroke + (_endStroke - _startStroke) * phase;
    canvas.drawCircle(Offset(x, y), maxRadius * eased, _paint);
  }
}
