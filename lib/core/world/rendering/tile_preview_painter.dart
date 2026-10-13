import 'dart:ui';

import 'package:vale_engine/theme/engine_palette.dart';
import 'package:vale_engine/utils/grid_pos.dart';
import '../grid/tile_targeting.dart';

/// How a previewed tile reads to the player.
enum TileTint {
  /// The action would work here.
  valid,

  /// It would work, but something about it is worth flagging.
  warning,

  /// It would not work here.
  invalid,

  /// One of the tiles on offer, but not the one being pointed at. Faint and
  /// thinly outlined, so the tile under the pointer stands out from a whole
  /// ring of them by brightness and not only by hue.
  offered,
}

/// Draws the tiles a player is pointing at, tinted by what would happen there.
///
/// Every paint is a field, allocated once. A preview redraws every frame while
/// a tool is in hand, and a `Paint` per tile per frame is exactly the shape of
/// allocation that shows up as jank on a phone.
class TilePreviewPainter {
  TilePreviewPainter({required this.tileSize});

  /// Side of one tile, in world units.
  final double tileSize;

  final Paint _fill = Paint();
  final Paint _border = Paint()..style = PaintingStyle.stroke;

  /// Ordinary outline width. An offered tile draws thinner — see
  /// [_borderWidthOf].
  static const double _strokeWidth = 2.0;

  /// Offered tiles outline thinner as well as fainter, so a ring of them
  /// reads as a soft field rather than a grid of boxes.
  double _borderWidthOf(TileTint tint) =>
      tint == TileTint.offered ? 1.5 : _strokeWidth;

  Color _fillColorOf(TileTint tint) => switch (tint) {
        TileTint.valid => EnginePalette.ghostValidFill,
        TileTint.warning => EnginePalette.ghostWarningFill,
        TileTint.invalid => EnginePalette.ghostInvalidFill,
        TileTint.offered => EnginePalette.tileOfferedFill,
      };

  Color _borderColorOf(TileTint tint) => switch (tint) {
        TileTint.valid => EnginePalette.ghostValidBorder,
        TileTint.warning => EnginePalette.ghostWarningBorder,
        TileTint.invalid => EnginePalette.ghostInvalidBorder,
        TileTint.offered => EnginePalette.tileOfferedBorder,
      };

  /// The world rectangle covering one tile.
  Rect rectOf(GridPos tile) =>
      Rect.fromLTWH(tile.x * tileSize, tile.y * tileSize, tileSize, tileSize);

  /// Draws one tile.
  void drawTile(Canvas canvas, GridPos tile, TileTint tint,
      {bool border = true}) {
    final rect = rectOf(tile);
    _fill.color = _fillColorOf(tint);
    canvas.drawRect(rect, _fill);
    if (!border) return;
    _border
      ..color = _borderColorOf(tint)
      ..strokeWidth = _borderWidthOf(tint);
    canvas.drawRect(rect, _border);
  }

  /// Draws every tile in [tiles] the same way.
  void drawTiles(Canvas canvas, Iterable<GridPos> tiles, TileTint tint,
      {bool border = true}) {
    for (final tile in tiles) {
      drawTile(canvas, tile, tint, border: border);
    }
  }

  /// Draws the tiles on offer, with the one under [pointingAt] brought
  /// forward so the player can see which of them they are about to take.
  void drawOffered(
    Canvas canvas,
    Iterable<GridPos> tiles, {
    GridPos? pointingAt,
  }) {
    for (final tile in tiles) {
      drawTile(
        canvas,
        tile,
        tile == pointingAt ? TileTint.valid : TileTint.offered,
      );
    }
  }

  /// Draws the rectangle the player is sweeping out, as one shape rather than
  /// tile by tile — a grid of borders reads as a mesh, not a selection.
  void drawSweep(Canvas canvas, GridPos start, GridPos end) {
    final rect = TileTargeting.worldRectOf(start, end, tileSize);
    _fill.color = EnginePalette.selectionRectFill;
    canvas.drawRect(rect, _fill);
    _border
      ..color = EnginePalette.selectionRectBorder
      ..strokeWidth = _strokeWidth;
    canvas.drawRect(rect, _border);
  }
}
