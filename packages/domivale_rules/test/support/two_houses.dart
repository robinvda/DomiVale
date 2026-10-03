import 'package:domivale_rules/domivale_rules.dart';

/// Two houses on an open 16×16 meadow: the Hill House at (3, 3) and the Lake
/// House at (10, 3). Their starting lands meet along x = 6 | 7 with no
/// overlap, so a border exists from the first turn.
MatchHeader twoHouses({
  Board? board,
  Banner first = Banner.builder,
  Banner second = Banner.warlord,
}) {
  return MatchHeader(
    board: board ?? Board.filled(size: 16),
    houses: [
      HouseSetup(
        name: 'Hill House',
        banner: first,
        heart: const Cell(3, 3),
        chosenBasic: CardKind.quarry,
        bannerBasic: first == Banner.expander ? CardKind.lumberCamp : null,
      ),
      HouseSetup(
        name: 'Lake House',
        banner: second,
        heart: const Cell(10, 3),
        chosenBasic: CardKind.lumberCamp,
        bannerBasic: second == Banner.expander ? CardKind.farm : null,
      ),
    ],
    seed: 1,
  );
}

/// Three houses on an open 20×20 meadow, for the seat rotation.
MatchHeader threeHouses() {
  return MatchHeader(
    board: Board.filled(size: 20),
    houses: [
      HouseSetup(
        name: 'Hill House',
        banner: Banner.builder,
        heart: const Cell(3, 3),
        chosenBasic: CardKind.quarry,
      ),
      HouseSetup(
        name: 'Lake House',
        banner: Banner.expander,
        heart: const Cell(16, 3),
        chosenBasic: CardKind.lumberCamp,
        bannerBasic: CardKind.farm,
      ),
      HouseSetup(
        name: 'Wood House',
        banner: Banner.warlord,
        heart: const Cell(10, 16),
        chosenBasic: CardKind.farm,
      ),
    ],
    seed: 2,
  );
}

/// Applies [action] and fails loudly if the rules refuse it.
void accept(MatchState state, Action action) {
  final refusal = state.apply(action);
  if (refusal != null) {
    throw StateError('$action was refused: ${refusal.name}');
  }
}

/// The index of the first card of [kind] in the current hand.
int inHand(MatchState state, CardKind kind) {
  final index = state.currentHouse.hand.indexOf(kind);
  if (index < 0) throw StateError('${kind.label} is not in hand');
  return index;
}
