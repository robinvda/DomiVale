import '../board/cell.dart';
import '../cards/card_kind.dart';

/// A heart and its districts.
///
/// Districts belong to their city by identity. A city's cells are its heart
/// plus every district placed on it; the land around them is territory, which
/// the match state tracks per cell rather than per city.
class City {
  City({required this.id, required this.owner, required this.heart});

  /// The city's place in the match's list of cities. Never reused.
  final int id;

  /// The seat of the house that founded it.
  final int owner;

  /// The cell the city was founded on.
  final Cell heart;

  final Map<Cell, CardKind> _districts = {};

  /// Each district's cell and the kind of district on it.
  Map<Cell, CardKind> get districts => Map.unmodifiable(_districts);

  int get districtCount => _districts.length;

  /// The heart and every district.
  Iterable<Cell> get cells sync* {
    yield heart;
    yield* _districts.keys;
  }

  bool contains(Cell cell) => cell == heart || _districts.containsKey(cell);

  /// Adds a district. Called by the match state when a card is played; the
  /// state has already checked the cell.
  void placeDistrict(Cell cell, CardKind kind) {
    _districts[cell] = kind;
  }

  /// How many districts of [kind] the city has.
  int count(CardKind kind) =>
      _districts.values.where((district) => district == kind).length;
}
