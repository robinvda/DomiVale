import 'dart:ui' show ClipOp;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'package:vale_engine/theme/engine_palette.dart';

/// Where the valley ends: the ground beyond it painted out.
///
/// The engine's terrain renderer works in 32-cell chunks and starts each one
/// as open water before it paints the land on top. A 22-cell board sits in
/// one chunk, so the cells of chunk that are not on the board would stay
/// ocean. Everything outside the board is painted over with the game's own
/// background here.
class BoardBoundsRenderer extends Component {
  BoardBoundsRenderer({required int size, required double tileSize})
      : _world = Rect.fromLTWH(0, 0, size * tileSize, size * tileSize);

  final Rect _world;

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.clipRect(_world, clipOp: ClipOp.difference);
    canvas.drawColor(EnginePalette.gameBackground, BlendMode.srcOver);
    canvas.restore();
  }
}
