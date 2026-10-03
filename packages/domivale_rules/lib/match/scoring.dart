import '../board/cell.dart';
import '../cards/card_kind.dart';
import '../rules.dart';
import 'match_state.dart';

/// Crowns: the score, computed from the state whenever it is asked for.
///
/// Land is the score on purpose. A district is worth what it claims, not
/// what it is, so the border drawn in the first half is what is defended in
/// the second.
extension Scoring on MatchState {
  /// What a Monument on [cell] scores: 1 per touching cell that is its
  /// owner's plain territory, so it is worth most at the edge of a city and
  /// nothing boxed in by other districts. 0 for any other cell.
  int monumentCrowns(Cell cell) {
    final city = cityAt(cell);
    if (city == null || city.districts[cell] != CardKind.monument) return 0;
    return cell.touching
        .where((beside) => isPlainTerritoryOf(beside, city.owner))
        .length;
  }

  /// [seat]'s crowns right now: 1 per [Rules.cellsPerCrown] cells owned, 1
  /// per heart, 1 per Market, a Monument's touching plain cells, and renown.
  int crownsOf(int seat) {
    var crowns = cellsOwnedBy(seat) ~/ Rules.cellsPerCrown;
    for (final city in citiesOf(seat)) {
      crowns += 1;
      for (final entry in city.districts.entries) {
        switch (entry.value) {
          case CardKind.market:
            crowns += 1;
          case CardKind.monument:
            crowns += monumentCrowns(entry.key);
          default:
            break;
        }
      }
    }
    return crowns + houses[seat].renown;
  }

  /// Seats from first to last: most crowns wins, a tie goes to more hearts,
  /// then to the house whose turn came later in the final round.
  List<int> get standings {
    final seats = [for (final house in houses) house.seat];
    final finalFirstSeat = (Rules.rounds - 1) % houses.length;
    int turnInFinalRound(int seat) =>
        (seat - finalFirstSeat + houses.length) % houses.length;
    seats.sort((a, b) {
      final byCrowns = crownsOf(b).compareTo(crownsOf(a));
      if (byCrowns != 0) return byCrowns;
      final byHearts = cityCountOf(b).compareTo(cityCountOf(a));
      if (byHearts != 0) return byHearts;
      return turnInFinalRound(b).compareTo(turnInFinalRound(a));
    });
    return seats;
  }

  /// The seat that has won, or null while the match is still being played.
  int? get winner => isOver ? standings.first : null;
}
