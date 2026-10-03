import 'dart:typed_data';

import 'package:domivale_rules/domivale_rules.dart';
import 'package:vale_engine/world/generation/noise_generator.dart';

/// A board the generator settled on, with the hearts it placed.
class GeneratedBoard {
  const GeneratedBoard({
    required this.board,
    required this.hearts,
    required this.seed,
    required this.attempts,
    required this.accepted,
  });

  final Board board;

  /// One heart per house, in the order of the generator's anchors. Seats are
  /// dealt from these by whoever sets the match up.
  final List<Cell> hearts;

  /// The seed of the board that was kept, which is not necessarily the one
  /// asked for: a board that fails the fairness check moves to the next.
  final int seed;

  /// How many boards were raised before this one was kept.
  final int attempts;

  /// Whether every start met its band. False means this was the closest miss
  /// after [BoardGenerator.maxAttempts].
  final bool accepted;
}

/// Draws the valley: a few features of terrain on the engine's noise, and a
/// fair start for every house.
///
/// Tuned for 22 to 32 cells. The engine's own terrain pass is for 256×256
/// worlds; its noise would give a board this small one flat slope. Heights
/// and terrain kinds are cut by quantile, so each kind is a fraction of the
/// board on every seed rather than a threshold to re-tune.
///
/// The output is data: the board goes into the match header, and nothing
/// after that depends on this generator again.
abstract final class BoardGenerator {
  /// How many seeds are tried before the closest miss is kept.
  static const int maxAttempts = 40;

  /// What a start needs within reach 3 of its heart (37 cells): enough
  /// meadow to feed farms, some forest and hills to choose a second basic
  /// from, and not too much water.
  static const int minMeadow = 14;
  static const int minForest = 5;
  static const int minHills = 4;
  static const int maxWater = 5;

  /// A heart stands on height 0 or 1, so no house opens on a ridge.
  static const int maxHeartHeight = 1;

  /// How far from its anchor a heart may be moved to find fair ground.
  static const int anchorSlack = 3;

  /// Where the houses start, as fractions of the board: opposite sides for
  /// two, a triangle for three, the corners for four.
  static List<(double, double)> anchorsFor(int houses) => switch (houses) {
        2 => const [(0.22, 0.5), (0.78, 0.5)],
        3 => const [(0.5, 0.2), (0.2, 0.78), (0.8, 0.78)],
        4 => const [(0.2, 0.2), (0.8, 0.2), (0.2, 0.8), (0.8, 0.8)],
        _ => throw ArgumentError.value(houses, 'houses', '2 to 4'),
      };

  /// A board for [houses] houses from [seed], or from the first seed after it
  /// whose starts are all fair.
  static GeneratedBoard generate({required int houses, required int seed}) {
    final size = Rules.boardSize(houses);
    GeneratedBoard? closest;
    var closestMiss = 1 << 30;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final board = raise(size: size, seed: seed + attempt);
      final hearts = <Cell>[];
      var miss = 0;
      for (final anchor in anchorsFor(houses)) {
        final found = _heartNear(board, anchor);
        hearts.add(found.cell);
        miss += found.miss;
      }
      final candidate = GeneratedBoard(
        board: board,
        hearts: hearts,
        seed: seed + attempt,
        attempts: attempt + 1,
        accepted: miss == 0,
      );
      if (miss == 0) return candidate;
      if (miss < closestMiss) {
        closestMiss = miss;
        closest = candidate;
      }
    }
    return closest!;
  }

  /// The terrain alone: heights by quantile of one noise field, hills on the
  /// high ground, a forest belt from a second field, water in the low places
  /// of a third.
  static Board raise({required int size, required int seed}) {
    final count = size * size;
    final noise = NoiseGenerator(seed: seed);

    final relief = Float32List(count);
    final moisture = Float32List(count);
    final wetness = Float32List(count);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        final i = y * size + x;
        relief[i] = _unit(noise.fbm(
          x: x * 0.09,
          y: y * 0.09,
          octaves: 3,
          persistence: 0.5,
        ));
        moisture[i] = _unit(noise.fbm(
          x: x * 0.07 + 40.0,
          y: y * 0.07 + 17.0,
          octaves: 2,
          persistence: 0.6,
        ));
        wetness[i] = _unit(noise.fbm(
          x: x * 0.08 + 133.0,
          y: y * 0.08 + 77.0,
          octaves: 3,
          persistence: 0.55,
        ));
      }
    }

    // Heights: most of the valley is the floor, and hills are the two
    // highest steps. Cut by quantile so the fractions hold on every seed.
    final level1 = _quantile(relief, 0.58);
    final level2 = _quantile(relief, 0.80);
    final level3 = _quantile(relief, 0.94);
    final heights = List<int>.filled(count, 0);
    for (var i = 0; i < count; i++) {
      final v = relief[i];
      heights[i] = v >= level3
          ? 3
          : v >= level2
              ? 2
              : v >= level1
                  ? 1
                  : 0;
    }

    // Forest: the wettest quarter of the low ground. Water: the lowest
    // stretch of the third field, on the floor only, so a lake is flat.
    final forestCut = _quantile(moisture, 0.74);
    final waterCut = _quantile(wetness, 0.07);
    final terrain = List<TerrainKind>.filled(count, TerrainKind.meadow);
    for (var i = 0; i < count; i++) {
      if (heights[i] >= 2) {
        terrain[i] = TerrainKind.hills;
      } else if (heights[i] == 0 && wetness[i] <= waterCut) {
        terrain[i] = TerrainKind.water;
      } else if (moisture[i] >= forestCut) {
        terrain[i] = TerrainKind.forest;
      }
    }

    return Board(size: size, terrain: terrain, heights: heights);
  }

  /// The fair cell nearest [anchor], or the least unfair one within
  /// [anchorSlack] of it, with how far short of the bands it falls.
  static ({Cell cell, int miss}) _heartNear(
      Board board, (double, double) anchor) {
    final ax = (anchor.$1 * (board.size - 1)).round();
    final ay = (anchor.$2 * (board.size - 1)).round();
    Cell best = Cell(ax, ay);
    var bestMiss = 1 << 30;
    // Rings outward, so the nearest fair cell wins and the heart stays where
    // the anchor put it whenever it can.
    for (var ring = 0; ring <= anchorSlack; ring++) {
      for (var dy = -ring; dy <= ring; dy++) {
        for (var dx = -ring; dx <= ring; dx++) {
          if (dx.abs() != ring && dy.abs() != ring) continue;
          final cell = Cell(ax + dx, ay + dy);
          final miss = startMiss(board, cell);
          if (miss < bestMiss) {
            bestMiss = miss;
            best = cell;
            if (miss == 0) return (cell: cell, miss: 0);
          }
        }
      }
    }
    return (cell: best, miss: bestMiss);
  }

  /// How far [cell] falls short of being a fair start: 0 when it meets every
  /// band, the total shortfall otherwise, and a large number when a heart
  /// could not stand there at all.
  static int startMiss(Board board, Cell cell) {
    if (!board.isLand(cell) || board.heightAt(cell) > maxHeartHeight) {
      return 1 << 20;
    }
    final counts = startCounts(board, cell);
    var miss = 0;
    miss += _short(counts[TerrainKind.meadow]!, minMeadow);
    miss += _short(counts[TerrainKind.forest]!, minForest);
    miss += _short(counts[TerrainKind.hills]!, minHills);
    miss += _short(maxWater, counts[TerrainKind.water]!);
    return miss;
  }

  /// How many cells of each kind lie within reach 3 of [cell], on the board.
  static Map<TerrainKind, int> startCounts(Board board, Cell cell) {
    final counts = {for (final kind in TerrainKind.values) kind: 0};
    for (final near in cell.cellsWithinReach(Rules.claimReach)) {
      if (!board.contains(near)) continue;
      counts.update(board.terrainAt(near), (n) => n + 1);
    }
    return counts;
  }

  static int _short(int value, int floor) => value >= floor ? 0 : floor - value;

  /// Simplex noise runs about -1 to 1; this puts it in 0 to 1.
  static double _unit(double v) => ((v + 1.0) * 0.5).clamp(0.0, 1.0);

  /// The value at [fraction] through the sorted field.
  static double _quantile(Float32List field, double fraction) {
    final sorted = Float32List.fromList(field)..sort();
    final index =
        (fraction * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[index];
  }
}
