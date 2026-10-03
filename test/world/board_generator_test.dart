import 'package:domivale/world/board_generator.dart';
import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a board is sized to its houses and the same from the same seed', () {
    for (var houses = 2; houses <= 4; houses++) {
      final one = BoardGenerator.generate(houses: houses, seed: 7);
      final two = BoardGenerator.generate(houses: houses, seed: 7);
      expect(one.board.size, Rules.boardSize(houses));
      expect(one.hearts, hasLength(houses));
      expect(one.board.terrain, two.board.terrain);
      expect(one.board.heights, two.board.heights);
      expect(one.hearts, two.hearts);
    }
  });

  test('every start is fair, on low land, and clear of the others', () {
    for (var houses = 2; houses <= 4; houses++) {
      for (var seed = 1; seed <= 12; seed++) {
        final generated = BoardGenerator.generate(houses: houses, seed: seed);
        final board = generated.board;
        expect(generated.accepted, isTrue,
            reason: '$houses houses, seed $seed, ${generated.attempts} tries');
        for (final heart in generated.hearts) {
          expect(board.isLand(heart), isTrue);
          expect(board.heightAt(heart),
              lessThanOrEqualTo(BoardGenerator.maxHeartHeight));
          final counts = BoardGenerator.startCounts(board, heart);
          expect(counts[TerrainKind.meadow],
              greaterThanOrEqualTo(BoardGenerator.minMeadow));
          expect(counts[TerrainKind.forest],
              greaterThanOrEqualTo(BoardGenerator.minForest));
          expect(counts[TerrainKind.hills],
              greaterThanOrEqualTo(BoardGenerator.minHills));
          expect(counts[TerrainKind.water],
              lessThanOrEqualTo(BoardGenerator.maxWater));
          for (final other in generated.hearts) {
            if (other == heart) continue;
            expect(heart.withinReach(other, Rules.settleDistance), isFalse);
          }
        }
        // The rules accept the same starts.
        expect(
          () => MatchState.start(MatchHeader(
            board: board,
            seed: seed,
            houses: [
              for (final heart in generated.hearts)
                HouseSetup(
                  name: 'A',
                  banner: Banner.builder,
                  heart: heart,
                  chosenBasic: CardKind.farm,
                ),
            ],
          )),
          returnsNormally,
        );
      }
    }
  });

  test('the valley has a few features rather than one slope', () {
    final board = BoardGenerator.raise(size: 32, seed: 3);
    final counts = {for (final kind in TerrainKind.values) kind: 0};
    for (final kind in board.terrain) {
      counts.update(kind, (n) => n + 1);
    }
    final total = board.cellCount;
    // Hills are the high ground, about a fifth; forest about a fifth; a
    // little water; meadow the rest.
    expect(counts[TerrainKind.hills]! / total, inInclusiveRange(0.15, 0.25));
    expect(counts[TerrainKind.forest]! / total, inInclusiveRange(0.12, 0.26));
    expect(counts[TerrainKind.water]! / total, inInclusiveRange(0.02, 0.08));
    expect(counts[TerrainKind.meadow]! / total, greaterThan(0.4));
    expect(board.heights.toSet(), containsAll([0, 1, 2, 3]));
    // Water is flat, and hills are high.
    for (final cell in board.cells) {
      switch (board.terrainAt(cell)) {
        case TerrainKind.water:
          expect(board.heightAt(cell), 0);
        case TerrainKind.hills:
          expect(board.heightAt(cell), greaterThanOrEqualTo(2));
        default:
          expect(board.heightAt(cell), lessThanOrEqualTo(1));
      }
    }
  });

  test('a seed that fails fairness moves to the next and says so', () {
    final generated = BoardGenerator.generate(houses: 4, seed: 1);
    expect(generated.seed, greaterThanOrEqualTo(1));
    expect(generated.attempts, generated.seed - 1 + 1);
  });
}
