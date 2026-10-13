import 'dart:math' as math;
import 'dart:ui';

import 'package:vale_engine/utils/grid_pos.dart';

/// Where the player is pointing, and what an action would do to the tiles
/// there — before they commit to it.
///
/// Three shapes of that question, which between them cover most of what a grid
/// game asks:
///
/// - **Offered cells.** Here are the tiles this may go on. Set them when a
///   tool becomes active and the player can see their options.
/// - **A sweep.** The player is dragging a rectangle out — a selection box, a
///   region to level, an area to clear.
/// - **A drag with an answer per tile.** The same rectangle, but each tile
///   carries whether the action would actually work there, so a preview can
///   show the ones that would fail before anything happens.
///
/// This is the state and the geometry only; drawing it is
/// `TilePreviewPainter`'s job, and what any of it *means* is the game's.
class TileTargeting {
  /// Tiles offered to the player as places the action may go. Empty when
  /// there is no such restriction.
  List<GridPos> offeredCells = const [];

  /// Whether anything is being offered.
  bool get hasOfferedCells => offeredCells.isNotEmpty;

  /// Whether [tile] is one of the offered ones. Always true when nothing is
  /// being offered, since then nothing is being restricted.
  bool isOffered(GridPos tile) =>
      offeredCells.isEmpty || offeredCells.contains(tile);

  /// Corners of the rectangle the player is sweeping out, or null when they
  /// are not.
  GridPos? sweepStart;
  GridPos? sweepEnd;

  /// Whether a sweep is under way and has both corners.
  bool get isSweeping => sweepStart != null && sweepEnd != null;

  /// Clears the sweep.
  void endSweep() {
    sweepStart = null;
    sweepEnd = null;
  }

  /// Where the current drag began, or null when none is under way.
  GridPos? get dragOrigin => _dragOrigin;
  GridPos? _dragOrigin;

  /// Whether a drag is under way.
  bool get isDragging => _dragOrigin != null;

  /// The tiles the drag currently covers.
  List<GridPos> get draggedTiles => _draggedTiles;
  List<GridPos> _draggedTiles = const [];

  /// Whether the action would work on each of [draggedTiles], in the same
  /// order.
  List<bool> get draggedValidity => _draggedValidity;
  List<bool> _draggedValidity = const [];

  /// Begins a drag at [origin]. The drag covers that one tile until
  /// [updateDrag] is called.
  void beginDrag(GridPos origin, {bool Function(GridPos tile)? isValid}) {
    _dragOrigin = origin;
    updateDrag(origin, isValid: isValid);
  }

  /// Grows the drag to reach [corner], asking [isValid] about each tile it now
  /// covers. Does nothing if no drag is under way.
  void updateDrag(GridPos corner, {bool Function(GridPos tile)? isValid}) {
    final origin = _dragOrigin;
    if (origin == null) return;
    _draggedTiles = tilesInRect(origin, corner);
    _draggedValidity = isValid == null
        ? List<bool>.filled(_draggedTiles.length, true)
        : [for (final tile in _draggedTiles) isValid(tile)];
  }

  /// Ends the drag and forgets what it covered.
  void endDrag() {
    _dragOrigin = null;
    _draggedTiles = const [];
    _draggedValidity = const [];
  }

  /// Forgets everything — a tool being put down, or a mode being left.
  void clear() {
    offeredCells = const [];
    endSweep();
    endDrag();
  }

  /// Every tile in the rectangle with [a] and [b] at opposite corners, both
  /// included. Never empty: one tile when the corners are the same.
  ///
  /// Column by column, so y varies fastest. Don't "tidy" the loops the other
  /// way round — a preview drawn in this order and an action applied in that
  /// one disagree about which tile a per-tile answer belongs to.
  static List<GridPos> tilesInRect(GridPos a, GridPos b) {
    final minX = math.min(a.x, b.x);
    final maxX = math.max(a.x, b.x);
    final minY = math.min(a.y, b.y);
    final maxY = math.max(a.y, b.y);
    final tiles = <GridPos>[];
    for (var x = minX; x <= maxX; x++) {
      for (var y = minY; y <= maxY; y++) {
        tiles.add(GridPos(x, y));
      }
    }
    return tiles;
  }

  /// The rectangle in world units covering the tiles between [a] and [b],
  /// both included — so the far edge reaches the *outside* of that tile
  /// rather than its corner.
  static Rect worldRectOf(GridPos a, GridPos b, double tileSize) =>
      Rect.fromLTRB(
        math.min(a.x, b.x) * tileSize,
        math.min(a.y, b.y) * tileSize,
        (math.max(a.x, b.x) + 1) * tileSize,
        (math.max(a.y, b.y) + 1) * tileSize,
      );
}
