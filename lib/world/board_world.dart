import 'package:domivale_rules/domivale_rules.dart';
import 'package:vale_engine/world/generation/noise_generator.dart';
import 'package:vale_engine/world/terrain/biome.dart';
import 'package:vale_engine/world/terrain/terrain_tile.dart';
import 'package:vale_engine/world/terrain_world.dart';

/// The board as the engine draws it: one terrain tile per cell, made from
/// the match's [Board].
///
/// The rules own the board; this only translates it into what the terrain
/// renderer reads. Meadow is grassland, forest is forest, hills are rocky
/// ground, and water sits a level below the land so the engine's colour ramp
/// darkens it. Heights are the board's own integer levels, which is what the
/// engine's cliff strokes are drawn between.
class BoardWorld extends TerrainWorld {
  BoardWorld({required this.board, required int seed})
      : super(
          width: board.size,
          height: board.size,
          seed: seed,
          // The engine keeps these for the terrain pass this game does not
          // use. The board already says where its water and hills are.
          waterLevel: 0,
          hilliness: 0,
        ) {
    installTerrain(_tilesFor(board, seed));
  }

  final Board board;

  /// How wet each kind of ground reads to the engine's colour ramp. Only the
  /// saturation moves with it; the biome sets the colour.
  static const Map<TerrainKind, double> _moisture = {
    TerrainKind.meadow: 0.55,
    TerrainKind.forest: 0.75,
    TerrainKind.hills: 0.35,
    TerrainKind.water: 0.5,
  };

  static Biome _biomeOf(TerrainKind kind) => switch (kind) {
        TerrainKind.meadow => Biome.grassland,
        TerrainKind.forest => Biome.forest,
        TerrainKind.hills => Biome.rocky,
        TerrainKind.water => Biome.water,
      };

  static List<List<TerrainTile>> _tilesFor(Board board, int seed) {
    // A little per-cell variety in the colour, from the seed rather than from
    // a random number, so a board draws the same every time it is opened.
    final noise = NoiseGenerator(seed: seed);
    return [
      for (var y = 0; y < board.size; y++)
        [
          for (var x = 0; x < board.size; x++)
            _tileAt(board, Cell(x, y), noise.noise2D(x * 0.5, y * 0.5)),
        ],
    ];
  }

  static TerrainTile _tileAt(Board board, Cell cell, double variation) {
    final kind = board.terrainAt(cell);
    final biome = _biomeOf(kind);
    return TerrainTile(
      type: biome.terrainType,
      biome: biome,
      height: kind.isLand ? board.heightAt(cell).toDouble() : -1.0,
      moisture: _moisture[kind]!,
      variation: variation,
    );
  }
}
