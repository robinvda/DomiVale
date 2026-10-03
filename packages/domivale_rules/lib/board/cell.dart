/// One cell of the board, by its integer coordinates.
///
/// Value-equal and hashable, so a cell works as a map key. Immutable, so a
/// stored cell cannot be moved under its owner.
class Cell {
  const Cell(this.x, this.y);

  final int x;
  final int y;

  /// The four orthogonal neighbours. "Touching" means these and only these.
  List<Cell> get touching => [
        Cell(x, y - 1),
        Cell(x + 1, y),
        Cell(x, y + 1),
        Cell(x - 1, y),
      ];

  /// Whether [other] is one of the four orthogonal neighbours.
  bool touches(Cell other) => (x - other.x).abs() + (y - other.y).abs() == 1;

  /// The one distance rule for every range in the game: [other] is within
  /// reach [r] when `dx² + dy² <= (r + 0.5)²`.
  ///
  /// It is the rule the engine's `buildRadiusCellPath` outlines with, so what
  /// the rules claim and what the renderer draws are the same set by
  /// construction. Written as `4(dx² + dy²) <= (2r + 1)²` so it stays in
  /// integers, which is what keeps it identical on the VM and in a browser.
  bool withinReach(Cell other, int r) {
    final dx = x - other.x;
    final dy = y - other.y;
    final span = 2 * r + 1;
    return 4 * (dx * dx + dy * dy) <= span * span;
  }

  /// Every cell within reach [r] of this one, this one included, in row
  /// order. Not bounded to any board: callers filter with `Board.contains`.
  ///
  /// Reach 3 is 37 cells in a rounded shape; reach 1 is the 3×3 square.
  Iterable<Cell> cellsWithinReach(int r) sync* {
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        final cell = Cell(x + dx, y + dy);
        if (withinReach(cell, r)) yield cell;
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Cell && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'Cell($x, $y)';
}
