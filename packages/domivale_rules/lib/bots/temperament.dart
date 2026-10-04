import '../match/banner.dart';

/// How a bot weighs what a play is worth: the knobs that make a Builder, an
/// Expander and a Warlord play differently on the same board.
///
/// Each weight multiplies one kind of value in the bot's estimate. They are
/// the figures the match simulation in `tools/match_sim.py` was measured
/// with, so the bots here play like the ones the design's numbers came from.
class Temperament {
  const Temperament({
    required this.yield,
    required this.claim,
    required this.war,
    required this.walls,
    required this.monument,
    required this.market,
    required this.settle,
    required this.barracks,
  });

  final double yield;
  final double claim;
  final double war;
  final double walls;
  final double monument;
  final double market;
  final double settle;
  final double barracks;

  /// Values yield and crowns; rarely attacks, invests in Walls and places
  /// Monuments where they score.
  static const builder = Temperament(
    yield: 1.3,
    claim: 1.0,
    war: 0.5,
    walls: 1.5,
    monument: 1.3,
    market: 1.2,
    settle: 0.9,
    barracks: 0.5,
  );

  /// Values claimed land and new cities; races for open ground and buys the
  /// Settles it sees.
  static const expander = Temperament(
    yield: 1.0,
    claim: 1.3,
    war: 0.8,
    walls: 0.7,
    monument: 0.9,
    market: 0.9,
    settle: 1.5,
    barracks: 0.8,
  );

  /// Values captures and renown; keeps military cards in hand, goes for thin
  /// arms and exposed Monuments.
  static const warlord = Temperament(
    yield: 0.9,
    claim: 1.0,
    war: 1.6,
    walls: 0.8,
    monument: 0.8,
    market: 0.8,
    settle: 0.9,
    barracks: 1.6,
  );

  /// Every weight 1: the measuring stick the three are compared against.
  static const plain = Temperament(
    yield: 1.0,
    claim: 1.0,
    war: 1.0,
    walls: 1.0,
    monument: 1.0,
    market: 1.0,
    settle: 1.0,
    barracks: 1.0,
  );

  /// A bot's temperament is its banner.
  static Temperament of(Banner banner) => switch (banner) {
        Banner.builder => builder,
        Banner.expander => expander,
        Banner.warlord => warlord,
      };
}
