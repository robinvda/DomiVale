import 'package:domivale_rules/domivale_rules.dart';
import 'package:test/test.dart';

void main() {
  group('reach', () {
    test('3 covers 37 cells in a rounded shape, 1 the 3×3 square', () {
      const origin = Cell(0, 0);
      expect(origin.cellsWithinReach(0).length, 1);
      expect(origin.cellsWithinReach(1).length, 9);
      expect(origin.cellsWithinReach(2).length, 21);
      expect(origin.cellsWithinReach(3).length, 37);
      // The corners of the 7×7 square are out; the middle of each edge is in.
      expect(origin.withinReach(const Cell(3, 3), 3), isFalse);
      expect(origin.withinReach(const Cell(3, 0), 3), isTrue);
      expect(origin.withinReach(const Cell(3, 1), 3), isTrue);
      expect(origin.withinReach(const Cell(3, 2), 3), isFalse);
      expect(origin.withinReach(const Cell(2, 2), 3), isTrue);
    });

    test('is the engine formula dx² + dy² <= (r + 0.5)², in integers', () {
      const origin = Cell(0, 0);
      for (var r = 0; r <= 5; r++) {
        for (var dy = -7; dy <= 7; dy++) {
          for (var dx = -7; dx <= 7; dx++) {
            final byFormula = dx * dx + dy * dy <= (r + 0.5) * (r + 0.5);
            expect(origin.withinReach(Cell(dx, dy), r), byFormula,
                reason: 'reach $r, ($dx, $dy)');
          }
        }
      }
    });

    test('is symmetric and includes the cell itself', () {
      const a = Cell(4, 7);
      const b = Cell(6, 9);
      expect(a.withinReach(a, 0), isTrue);
      expect(a.withinReach(b, 3), b.withinReach(a, 3));
      expect(a.cellsWithinReach(3), contains(a));
    });
  });

  group('touching', () {
    test('means the four orthogonal neighbours and only those', () {
      const cell = Cell(5, 5);
      expect(cell.touching, hasLength(4));
      expect(
        cell.touching,
        unorderedEquals(const [Cell(5, 4), Cell(6, 5), Cell(5, 6), Cell(4, 5)]),
      );
      expect(cell.touches(const Cell(6, 5)), isTrue);
      expect(cell.touches(const Cell(6, 6)), isFalse);
      expect(cell.touches(cell), isFalse);
    });
  });

  test('a cell is a value', () {
    expect(const Cell(1, 2), const Cell(1, 2));
    expect(const Cell(1, 2).hashCode, const Cell(1, 2).hashCode);
    expect(const Cell(1, 2), isNot(const Cell(2, 1)));
    final set = <Cell>{}
      ..add(const Cell(1, 2))
      ..add(const Cell(1, 2));
    expect(set, hasLength(1));
  });
}
