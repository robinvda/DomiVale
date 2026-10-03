import 'package:domivale_rules/domivale_rules.dart';
import 'package:test/test.dart';

void main() {
  test('the board is sized to the number of houses', () {
    expect(Rules.boardSize(2), 22);
    expect(Rules.boardSize(3), 27);
    expect(Rules.boardSize(4), 32);
    expect(() => Rules.boardSize(5), throwsArgumentError);
    expect(() => Rules.boardSize(1), throwsArgumentError);
  });

  test('a board is read and addressed in row order', () {
    final board = Board.parse(
      const ['mf~', 'hmm', 'mmm'],
      heightRows: const ['012', '000', '300'],
    );
    expect(board.size, 3);
    expect(board.cellCount, 9);
    expect(board.terrainAt(const Cell(0, 0)), TerrainKind.meadow);
    expect(board.terrainAt(const Cell(1, 0)), TerrainKind.forest);
    expect(board.terrainAt(const Cell(2, 0)), TerrainKind.water);
    expect(board.terrainAt(const Cell(0, 1)), TerrainKind.hills);
    expect(board.heightAt(const Cell(2, 0)), 2);
    expect(board.heightAt(const Cell(0, 2)), 3);
    expect(board.landCount, 8);
    expect(board.indexOf(const Cell(2, 1)), 5);
    expect(board.cellAt(5), const Cell(2, 1));
    expect(board.cells.toList(), hasLength(9));
    expect(board.cells.first, const Cell(0, 0));
    expect(board.cells.last, const Cell(2, 2));
  });

  test('water is not land, and nothing off the board is either', () {
    final board = Board.parse(const ['m~', 'mm']);
    expect(board.isLand(const Cell(0, 0)), isTrue);
    expect(board.isLand(const Cell(1, 0)), isFalse);
    expect(board.isLand(const Cell(2, 0)), isFalse);
    expect(board.contains(const Cell(-1, 0)), isFalse);
    expect(board.contains(const Cell(1, 1)), isTrue);
  });

  test('a board refuses the wrong shape or an impossible height', () {
    expect(() => Board.parse(const ['mm', 'm']), throwsArgumentError);
    expect(() => Board.parse(const ['mx', 'mm']), throwsArgumentError);
    expect(
      () => Board.parse(const ['mm', 'mm'], heightRows: const ['04', '00']),
      throwsArgumentError,
    );
    expect(
      () => Board(
          size: 2,
          terrain: List.filled(3, TerrainKind.meadow),
          heights: List.filled(4, 0)),
      throwsArgumentError,
    );
  });

  test('a board is immutable', () {
    final board = Board.filled(size: 2);
    expect(() => board.terrain[0] = TerrainKind.water, throwsUnsupportedError);
    expect(() => board.heights[0] = 1, throwsUnsupportedError);
  });
}
