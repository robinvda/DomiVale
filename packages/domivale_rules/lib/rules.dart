import 'cards/card_kind.dart';
import 'match/goods.dart';

/// The numbers the rules are tuned by, in one place.
///
/// Every figure here is one from the "Starting numbers" table of `DESIGN.md`
/// and is meant to be changed by playing. Nothing elsewhere in the package
/// repeats a value from this table.
abstract final class Rules {
  /// Which revision of the rules a match was started on. A match records it
  /// in its header, so a server can keep replaying old matches after the
  /// rules change.
  static const int version = 1;

  /// A match lasts this many rounds; every house plays one turn per round.
  static const int rounds = 20;

  static const int minHouses = 2;
  static const int maxHouses = 4;

  /// How many cards a house may play in one turn.
  static const int playsPerTurn = 3;

  /// How many cards a hand holds at most.
  static const int handCap = 5;

  /// How many face-up cards the market row holds.
  static const int rowSize = 5;

  /// How many cards may be bought from the row in one turn. The basic piles
  /// are not limited.
  static const int rowBuysPerTurn = 2;

  /// How many of each market card the deck holds: forty cards in all.
  static const Map<CardKind, int> deckMix = {
    CardKind.settle: 6,
    CardKind.march: 10,
    CardKind.siege: 6,
    CardKind.market: 5,
    CardKind.walls: 5,
    CardKind.barracks: 4,
    CardKind.monument: 4,
  };

  /// How many of one good buy one of another at the bank, and with a Market.
  static const int bankTrade = 3;
  static const int marketTrade = 2;

  /// A heart or district claims every unclaimed land cell within this reach.
  static const int claimReach = 3;

  /// A new city must be outside this reach of every city cell of every house.
  static const int settleDistance = 3;

  /// What a basic card costs a house with no districts.
  static const Goods basicPrice = Goods(grain: 1, wood: 1);

  /// How much the basic price rises for every [basicPriceStep] districts the
  /// house already has.
  static const Goods basicPriceRise = Goods(grain: 1, wood: 1);
  static const int basicPriceStep = 3;

  /// How much a Settle's printed price rises for every city the house holds
  /// beyond its first.
  static const Goods settlePriceRise = Goods(grain: 1, wood: 1, stone: 1);

  /// What every house starts the match with.
  static const Goods startingGoods = Goods(grain: 2, wood: 2, stone: 1);

  /// What a heart produces at the start of its owner's turn.
  static const Goods heartYield = Goods(grain: 1, wood: 1, stone: 1);

  /// One crown per this many cells owned, city cells included.
  static const int cellsPerCrown = 3;

  /// The board is square and sized to the number of houses, so that every
  /// match has about 250 cells per house.
  static int boardSize(int houses) {
    switch (houses) {
      case 2:
        return 22;
      case 3:
        return 27;
      case 4:
        return 32;
      default:
        throw ArgumentError.value(
            houses, 'houses', 'a match has $minHouses to $maxHouses houses');
    }
  }
}
