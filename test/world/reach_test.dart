import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vale_engine/utils/radius_cell_path.dart';

void main() {
  test('the reach rule is the set the engine outlines', () {
    // The rules claim cells by `Cell.withinReach`; the renderer draws the
    // border with `buildRadiusCellPath`. If the two ever disagreed, the
    // outline on screen would not be the land the rules gave. The path is
    // sampled at every cell's middle.
    const tileSize = 10.0;
    const origin = Cell(8, 8);
    for (var r = 0; r <= 4; r++) {
      final path = buildRadiusCellPath(
        sources: [(x: origin.x, y: origin.y, radius: r)],
        tileSize: tileSize,
      );
      for (var y = 0; y < 17; y++) {
        for (var x = 0; x < 17; x++) {
          final middle = Offset((x + 0.5) * tileSize, (y + 0.5) * tileSize);
          expect(
            path.contains(middle),
            origin.withinReach(Cell(x, y), r),
            reason: 'reach $r, cell ($x, $y)',
          );
        }
      }
    }
  });

  test(
    'a territory is outlined by calling the path with radius 0 per cell',
    () {
      // How the territory renderer will draw a border: every owned cell as a
      // source of radius 0, which outlines exactly that set.
      const tileSize = 10.0;
      final owned = {const Cell(1, 1), const Cell(2, 1), const Cell(2, 2)};
      final path = buildRadiusCellPath(
        sources: [for (final c in owned) (x: c.x, y: c.y, radius: 0)],
        tileSize: tileSize,
      );
      for (var y = 0; y < 5; y++) {
        for (var x = 0; x < 5; x++) {
          final middle = Offset((x + 0.5) * tileSize, (y + 0.5) * tileSize);
          expect(
            path.contains(middle),
            owned.contains(Cell(x, y)),
            reason: 'cell ($x, $y)',
          );
        }
      }
    },
  );
}
