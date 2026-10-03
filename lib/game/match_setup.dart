import 'package:domivale_rules/domivale_rules.dart';

import '../world/board_generator.dart';

/// One house as the setup screen describes it, before seats are dealt.
class HouseChoice {
  const HouseChoice({required this.name, required this.banner});

  final String name;
  final Banner banner;
}

/// The names the houses go by, in the order they are handed out.
const List<String> houseNames = [
  'Hill House',
  'Lake House',
  'Wood House',
  'Stone House',
];

/// Builds a match from what the setup screen chose: a board for the house
/// count, seats dealt at random, and each house's opening choice made from
/// the land around its heart.
MatchHeader buildMatch({required List<HouseChoice> houses, required int seed}) {
  final generated = BoardGenerator.generate(houses: houses.length, seed: seed);
  final board = generated.board;

  // Seats are dealt at random, and the dealing is part of the seed so the
  // same seed is the same match.
  final order = List.generate(houses.length, (i) => i);
  Prng(seed).shuffle(order);

  return MatchHeader(
    board: board,
    seed: seed,
    houses: [
      for (final (seat, index) in order.indexed)
        _setupFor(houses[index], generated.hearts[seat], board),
    ],
  );
}

/// The house's opening choice is made from its land: the second basic card
/// gathers whichever of wood and stone there is more of within reach of the
/// heart, and an Expander's banner card gathers the other.
HouseSetup _setupFor(HouseChoice choice, Cell heart, Board board) {
  final counts = BoardGenerator.startCounts(board, heart);
  final moreForest = counts[TerrainKind.forest]! >= counts[TerrainKind.hills]!;
  final chosen = moreForest ? CardKind.lumberCamp : CardKind.quarry;
  final other = moreForest ? CardKind.quarry : CardKind.lumberCamp;
  return HouseSetup(
    name: choice.name,
    banner: choice.banner,
    heart: heart,
    chosenBasic: chosen,
    bannerBasic: choice.banner == Banner.expander ? other : null,
  );
}
