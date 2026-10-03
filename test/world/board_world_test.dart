import 'package:domivale/world/board_world.dart';
import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vale_engine/world/terrain/biome.dart';
import 'package:vale_engine/world/terrain/terrain_type.dart';

void main() {
  test('every cell becomes the engine tile for its kind and height', () {
    final board = Board.parse(
      const ['mf~', 'hmm', 'mmm'],
      heightRows: const ['010', '200', '000'],
    );
    final world = BoardWorld(board: board, seed: 1);
    expect(world.isGenerated, isTrue);
    expect(world.width, 3);

    final meadow = world.getTileAtCoords(0, 0)!;
    expect(meadow.biome, Biome.grassland);
    expect(meadow.type, TerrainType.grass);
    expect(meadow.height, 0);

    final forest = world.getTileAtCoords(1, 0)!;
    expect(forest.biome, Biome.forest);
    expect(forest.height, 1);

    final water = world.getTileAtCoords(2, 0)!;
    expect(water.biome, Biome.water);
    expect(water.type.isWater, isTrue);
    expect(water.height, lessThan(0), reason: 'drawn a level below the land');

    final hills = world.getTileAtCoords(0, 1)!;
    expect(hills.biome, Biome.rocky);
    expect(hills.type, TerrainType.rock);
    expect(hills.height, 2);
  });

  test('draws the same colours from the same seed', () {
    final board = Board.filled(size: 8);
    final one = BoardWorld(board: board, seed: 5);
    final two = BoardWorld(board: board, seed: 5);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        expect(
            one.getTileAtCoords(x, y)!.color, two.getTileAtCoords(x, y)!.color);
      }
    }
  });
}
