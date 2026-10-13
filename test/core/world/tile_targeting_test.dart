import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vale_engine/utils/grid_pos.dart';
import 'package:domivale/core/world/grid/tile_targeting.dart';

/// What the player is pointing at, before they commit to anything. The
/// geometry has to be exact — a rectangle that misses its far edge, or a
/// validity list that drifts out of step with the tiles it describes, both
/// show up as a preview that lies about what an action will do.
void main() {
  group('the rectangle between two corners', () {
    test('the same tile twice is that one tile', () {
      expect(
        TileTargeting.tilesInRect(const GridPos(3, 4), const GridPos(3, 4)),
        [const GridPos(3, 4)],
      );
    });

    test('both corners are included', () {
      final tiles =
          TileTargeting.tilesInRect(const GridPos(1, 1), const GridPos(2, 2));
      expect(tiles, hasLength(4));
      expect(tiles, contains(const GridPos(1, 1)));
      expect(tiles, contains(const GridPos(2, 2)));
    });

    test('it does not matter which corner is which', () {
      final forwards =
          TileTargeting.tilesInRect(const GridPos(1, 1), const GridPos(3, 2));
      for (final pair in [
        (const GridPos(3, 2), const GridPos(1, 1)),
        (const GridPos(1, 2), const GridPos(3, 1)),
        (const GridPos(3, 1), const GridPos(1, 2)),
      ]) {
        expect(TileTargeting.tilesInRect(pair.$1, pair.$2).toSet(),
            forwards.toSet());
      }
    });

    test('the order is column by column, y fastest', () {
      // Pinned because a preview drawn in one order and an action applied in
      // the other disagree about which tile an answer belongs to — and a
      // horizontal line cannot tell the two apart.
      expect(
        TileTargeting.tilesInRect(const GridPos(0, 0), const GridPos(1, 1)),
        [
          const GridPos(0, 0),
          const GridPos(0, 1),
          const GridPos(1, 0),
          const GridPos(1, 1),
        ],
      );
    });

    test('a line is a rectangle one tile wide', () {
      expect(
        TileTargeting.tilesInRect(const GridPos(0, 0), const GridPos(0, 3)),
        hasLength(4),
      );
    });

    test('negative coordinates are handled the same way', () {
      final tiles =
          TileTargeting.tilesInRect(const GridPos(-2, -1), const GridPos(0, 0));
      expect(tiles, hasLength(6));
      expect(tiles, contains(const GridPos(-2, -1)));
    });
  });

  group('the world rectangle', () {
    test('reaches the outside of the far tile, not its corner', () {
      // The trap: stopping at the far tile's origin draws a rectangle one
      // tile short in each direction.
      expect(
        TileTargeting.worldRectOf(const GridPos(0, 0), const GridPos(1, 1), 32),
        const Rect.fromLTRB(0, 0, 64, 64),
      );
    });

    test('one tile is one tile square', () {
      expect(
        TileTargeting.worldRectOf(const GridPos(2, 3), const GridPos(2, 3), 10),
        const Rect.fromLTRB(20, 30, 30, 40),
      );
    });

    test('the corners can arrive either way round', () {
      expect(
        TileTargeting.worldRectOf(const GridPos(3, 3), const GridPos(1, 1), 8),
        TileTargeting.worldRectOf(const GridPos(1, 1), const GridPos(3, 3), 8),
      );
    });
  });

  group('offered cells', () {
    test('with nothing offered nothing is restricted', () {
      final targeting = TileTargeting();
      expect(targeting.hasOfferedCells, isFalse);
      expect(targeting.isOffered(const GridPos(9, 9)), isTrue,
          reason: 'no restriction means every tile is allowed');
    });

    test('with cells offered only those are allowed', () {
      final targeting = TileTargeting()
        ..offeredCells = const [GridPos(1, 1), GridPos(1, 2)];
      expect(targeting.hasOfferedCells, isTrue);
      expect(targeting.isOffered(const GridPos(1, 2)), isTrue);
      expect(targeting.isOffered(const GridPos(5, 5)), isFalse);
    });
  });

  group('a drag', () {
    test('starts covering just the tile it began on', () {
      final targeting = TileTargeting()..beginDrag(const GridPos(4, 4));
      expect(targeting.isDragging, isTrue);
      expect(targeting.dragOrigin, const GridPos(4, 4));
      expect(targeting.draggedTiles, [const GridPos(4, 4)]);
      expect(targeting.draggedValidity, [true]);
    });

    test('grows to the corner it is dragged to', () {
      final targeting = TileTargeting()
        ..beginDrag(const GridPos(0, 0))
        ..updateDrag(const GridPos(2, 1));
      expect(targeting.draggedTiles, hasLength(6));
    });

    test('shrinks again when the drag comes back', () {
      final targeting = TileTargeting()
        ..beginDrag(const GridPos(0, 0))
        ..updateDrag(const GridPos(4, 4))
        ..updateDrag(const GridPos(1, 0));
      expect(targeting.draggedTiles, hasLength(2));
    });

    test('an answer per tile, in the same order as the tiles', () {
      final targeting = TileTargeting()
        ..beginDrag(const GridPos(0, 0))
        ..updateDrag(const GridPos(2, 0), isValid: (tile) => tile.x != 1);

      expect(targeting.draggedTiles,
          [const GridPos(0, 0), const GridPos(1, 0), const GridPos(2, 0)]);
      expect(targeting.draggedValidity, [true, false, true]);
    });

    test('the two lists always match in length', () {
      // What keeps a preview from tinting a tile by another tile's answer.
      final targeting = TileTargeting()..beginDrag(const GridPos(0, 0));
      for (final corner in [
        const GridPos(3, 3),
        const GridPos(0, 0),
        const GridPos(-2, 5),
      ]) {
        targeting.updateDrag(corner, isValid: (_) => true);
        expect(
            targeting.draggedValidity, hasLength(targeting.draggedTiles.length),
            reason: 'after dragging to $corner');
      }
    });

    test('dragging without having started does nothing', () {
      final targeting = TileTargeting()..updateDrag(const GridPos(5, 5));
      expect(targeting.isDragging, isFalse);
      expect(targeting.draggedTiles, isEmpty);
    });

    test('ending forgets what it covered', () {
      final targeting = TileTargeting()
        ..beginDrag(const GridPos(0, 0))
        ..updateDrag(const GridPos(3, 3))
        ..endDrag();
      expect(targeting.isDragging, isFalse);
      expect(targeting.draggedTiles, isEmpty);
      expect(targeting.draggedValidity, isEmpty);
    });
  });

  group('a sweep', () {
    test('needs both corners before it counts', () {
      final targeting = TileTargeting()..sweepStart = const GridPos(1, 1);
      expect(targeting.isSweeping, isFalse);
      targeting.sweepEnd = const GridPos(2, 2);
      expect(targeting.isSweeping, isTrue);
    });

    test('ending it drops both corners', () {
      final targeting = TileTargeting()
        ..sweepStart = const GridPos(1, 1)
        ..sweepEnd = const GridPos(2, 2)
        ..endSweep();
      expect(targeting.isSweeping, isFalse);
      expect(targeting.sweepStart, isNull);
      expect(targeting.sweepEnd, isNull);
    });
  });

  test('clearing puts everything down at once', () {
    final targeting = TileTargeting()
      ..offeredCells = const [GridPos(1, 1)]
      ..sweepStart = const GridPos(0, 0)
      ..sweepEnd = const GridPos(1, 1)
      ..beginDrag(const GridPos(2, 2));

    targeting.clear();

    expect(targeting.hasOfferedCells, isFalse);
    expect(targeting.isSweeping, isFalse);
    expect(targeting.isDragging, isFalse);
  });
}
