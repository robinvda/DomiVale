import '../cards/card_kind.dart';
import 'goods.dart';
import 'house_setup.dart';

/// One player or bot as the match sees it: what it holds and what it has
/// earned. Everything else about a house - its cells, cities, yields and
/// crowns - is derived from the match state and never stored here.
class House {
  House({required this.seat, required this.setup})
      : goods = Goods.none,
        hand = [],
        renown = 0;

  /// The house's place in the turn order, 0-based.
  final int seat;

  final HouseSetup setup;

  String get name => setup.name;

  Goods goods;

  /// The cards held, in the order they were taken. Hidden from rivals; its
  /// length is not.
  final List<CardKind> hand;

  /// Crowns earned by war, kept for the rest of the match whatever happens to
  /// the cells afterwards.
  int renown;
}
