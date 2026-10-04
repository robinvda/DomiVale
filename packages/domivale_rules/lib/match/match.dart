import '../board/board.dart';
import '../cards/card_kind.dart';
import '../rules.dart';
import 'action.dart';
import 'house_setup.dart';
import 'match_state.dart';

/// Everything a match starts from. Same header, same log, same state, on
/// every platform.
class MatchHeader {
  MatchHeader({
    this.rulesVersion = Rules.version,
    required this.board,
    required this.houses,
    required this.seed,
    this.deck,
  }) {
    if (houses.length < Rules.minHouses || houses.length > Rules.maxHouses) {
      throw ArgumentError.value(houses.length, 'houses',
          'a match has ${Rules.minHouses} to ${Rules.maxHouses} houses');
    }
  }

  /// The revision of the rules the match was started on.
  final int rulesVersion;

  final Board board;

  /// The houses in seat order. Seats are dealt before the match; round 1
  /// starts with the first and every round after it one seat later.
  final List<HouseSetup> houses;

  /// Seeds the market shuffle, and every reshuffle of the discard pile.
  final int seed;

  /// A deck in a given order, dealt from the end, instead of the base deck
  /// shuffled from [seed]. For hand-made boards and tests; null for a
  /// skirmish.
  final List<CardKind>? deck;
}

/// A match is data plus a log: its header and the actions taken so far. The
/// current state is what applying the log to the starting state gives.
class Match {
  Match(this.header, [Iterable<Action> log = const []]) : _log = [...log];

  final MatchHeader header;

  final List<Action> _log;

  /// Every action taken, in order.
  List<Action> get log => List.unmodifiable(_log);

  /// Records an action the rules have accepted.
  void append(Action action) => _log.add(action);

  /// Forgets the last [count] actions - how a turn is undone before it is
  /// committed.
  void truncate(int count) {
    _log.removeRange(_log.length - count, _log.length);
  }

  /// The state the log leads to, replayed from the start.
  MatchState replay() => MatchState.replay(header, _log);
}
