import '../match/goods.dart';

/// What a card is for.
enum CardFamily {
  /// A gathering district from the always-available piles.
  basic,

  /// A district from the market row.
  district,

  /// A new city.
  settle,

  /// An army: takes a cell from a rival.
  military,
}

/// The base set. One row per card: what it is, what it costs printed on the
/// card, and the one number that makes it work.
///
/// Prices here are the printed ones. The basic price rises with the districts
/// a house has and the Settle price with the cities it holds; both are
/// computed by the match state from the figures in `Rules`.
enum CardKind {
  farm(
    label: 'Farm',
    family: CardFamily.basic,
    price: Goods(grain: 1, wood: 1),
    gathers: Good.grain,
  ),
  lumberCamp(
    label: 'Lumber camp',
    family: CardFamily.basic,
    price: Goods(grain: 1, wood: 1),
    gathers: Good.wood,
  ),
  quarry(
    label: 'Quarry',
    family: CardFamily.basic,
    price: Goods(grain: 1, wood: 1),
    gathers: Good.stone,
  ),
  market(
    label: 'Market',
    family: CardFamily.district,
    price: Goods(grain: 2, wood: 2),
  ),
  walls(
    label: 'Walls',
    family: CardFamily.district,
    price: Goods(stone: 3),
  ),
  barracks(
    label: 'Barracks',
    family: CardFamily.district,
    price: Goods(grain: 2, wood: 1, stone: 1),
  ),
  monument(
    label: 'Monument',
    family: CardFamily.district,
    price: Goods(wood: 2, stone: 3),
  ),
  settle(
    label: 'Settle',
    family: CardFamily.settle,
    price: Goods(grain: 2, wood: 2, stone: 1),
  ),
  march(
    label: 'March',
    family: CardFamily.military,
    price: Goods(grain: 1, wood: 1),
    strength: 2,
  ),
  siege(
    label: 'Siege',
    family: CardFamily.military,
    price: Goods(grain: 2, stone: 2),
    strength: 4,
  );

  const CardKind({
    required this.label,
    required this.family,
    required this.price,
    this.gathers,
    this.strength = 0,
  });

  final String label;
  final CardFamily family;

  /// The price printed on the card.
  final Goods price;

  /// The good a gathering district collects from the cells touching it, or
  /// null for every other card.
  final Good? gathers;

  /// What a military card brings against a target's defence; 0 for the rest.
  final int strength;

  /// The three cards that are always in the piles.
  static const List<CardKind> basics = [farm, lumberCamp, quarry];

  bool get isBasic => family == CardFamily.basic;

  /// Whether playing this card places a district on a city.
  bool get isDistrict =>
      family == CardFamily.basic || family == CardFamily.district;

  bool get isMilitary => family == CardFamily.military;
}
