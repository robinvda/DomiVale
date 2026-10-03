import '../match/goods.dart';

/// The four kinds of ground a cell can be, and what each one yields.
enum TerrainKind {
  meadow(label: 'Meadow', yields: Good.grain),
  forest(label: 'Forest', yields: Good.wood),
  hills(label: 'Hills', yields: Good.stone),
  water(label: 'Water', yields: null);

  const TerrainKind({required this.label, required this.yields});

  final String label;

  /// The good a gathering district beside a cell of this kind collects from
  /// it, or null for water, which yields nothing.
  final Good? yields;

  /// Whether a house can own a cell of this kind. Water sits outside every
  /// border.
  bool get isLand => this != TerrainKind.water;
}
