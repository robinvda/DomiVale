import 'cell.dart';
import 'terrain_kind.dart';

/// The valley: a square grid of cells, each with a terrain kind and a height
/// level. Immutable - a match stores its board in the header and nothing ever
/// changes it.
///
/// The board is data in the match, not something the rules generate. The
/// generator lives in the game, so a server never needs one and generation
/// can change between versions without breaking old matches.
class Board {
  Board({
    required this.size,
    required List<TerrainKind> terrain,
    required List<int> heights,
  })  : terrain = List.unmodifiable(terrain),
        heights = List.unmodifiable(heights) {
    if (size < 1) {
      throw ArgumentError.value(size, 'size', 'must be at least 1');
    }
    if (terrain.length != size * size) {
      throw ArgumentError.value(terrain.length, 'terrain',
          'a $size×$size board has ${size * size} cells');
    }
    if (heights.length != size * size) {
      throw ArgumentError.value(heights.length, 'heights',
          'a $size×$size board has ${size * size} cells');
    }
    for (final height in heights) {
      if (height < minHeight || height > maxHeight) {
        throw ArgumentError.value(
            height, 'heights', 'a height is $minHeight to $maxHeight');
      }
    }
  }

  /// A board of one terrain kind at one height.
  factory Board.filled({
    required int size,
    TerrainKind kind = TerrainKind.meadow,
    int height = 0,
  }) {
    return Board(
      size: size,
      terrain: List.filled(size * size, kind),
      heights: List.filled(size * size, height),
    );
  }

  /// A board drawn as text, one string per row: `m` meadow, `f` forest, `h`
  /// hills, `~` water. [heightRows] is the same shape in digits `0`-`3`, or
  /// absent for a flat board.
  ///
  /// This is how tests and hand-made campaign boards are written.
  factory Board.parse(List<String> rows, {List<String>? heightRows}) {
    final size = rows.length;
    final terrain = <TerrainKind>[];
    for (final row in rows) {
      if (row.length != size) {
        throw ArgumentError.value(row, 'rows', 'every row is $size cells');
      }
      for (final letter in row.split('')) {
        terrain.add(switch (letter) {
          'm' => TerrainKind.meadow,
          'f' => TerrainKind.forest,
          'h' => TerrainKind.hills,
          '~' => TerrainKind.water,
          _ => throw ArgumentError.value(
              letter, 'rows', 'a cell is one of m, f, h or ~'),
        });
      }
    }
    final heights = <int>[];
    if (heightRows == null) {
      heights.addAll(List.filled(size * size, 0));
    } else {
      if (heightRows.length != size) {
        throw ArgumentError.value(
            heightRows, 'heightRows', 'the same shape as rows');
      }
      for (final row in heightRows) {
        if (row.length != size) {
          throw ArgumentError.value(
              row, 'heightRows', 'every row is $size cells');
        }
        for (final digit in row.split('')) {
          final height = int.tryParse(digit);
          if (height == null) {
            throw ArgumentError.value(digit, 'heightRows', 'a digit');
          }
          heights.add(height);
        }
      }
    }
    return Board(size: size, terrain: terrain, heights: heights);
  }

  /// Height is a few integer levels; it does one thing, which is to make an
  /// attack uphill cost more.
  static const int minHeight = 0;
  static const int maxHeight = 3;

  /// Cells per side.
  final int size;

  /// Terrain per cell, in row order: index `y * size + x`.
  final List<TerrainKind> terrain;

  /// Height level per cell, in the same order.
  final List<int> heights;

  int get cellCount => size * size;

  /// Every cell, in row order.
  Iterable<Cell> get cells sync* {
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        yield Cell(x, y);
      }
    }
  }

  /// How many cells a house could ever own.
  int get landCount => terrain.where((kind) => kind.isLand).length;

  bool contains(Cell cell) =>
      cell.x >= 0 && cell.y >= 0 && cell.x < size && cell.y < size;

  /// The position of [cell] in [terrain] and [heights].
  int indexOf(Cell cell) => cell.y * size + cell.x;

  Cell cellAt(int index) => Cell(index % size, index ~/ size);

  TerrainKind terrainAt(Cell cell) => terrain[indexOf(cell)];

  int heightAt(Cell cell) => heights[indexOf(cell)];

  bool isLand(Cell cell) => contains(cell) && terrainAt(cell).isLand;
}
