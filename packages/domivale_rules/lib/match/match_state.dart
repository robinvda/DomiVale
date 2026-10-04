import '../board/board.dart';
import '../board/cell.dart';
import '../board/terrain_kind.dart';
import '../cards/card_kind.dart';
import '../cards/market.dart';
import '../cards/prng.dart';
import '../rules.dart';
import 'action.dart';
import 'city.dart';
import 'goods.dart';
import 'house.dart';
import 'match.dart';

part 'apply.dart';
part '../war/defence.dart';

/// The whole state of a match at one moment: who owns which cell, the
/// cities, the houses' goods and hands, and whose turn it is.
///
/// Built by applying a match's log to the starting state. Everything derived
/// - yields, prices, crowns, offered cells - is computed from this on demand
/// and never stored, so nothing can fall out of step.
class MatchState {
  /// The state at the start of a match, before any action: every house has
  /// claimed the land around its heart, holds its opening hand and goods,
  /// and the first house has collected for its first turn.
  MatchState.start(this.header)
      : houses = [
          for (var seat = 0; seat < header.houses.length; seat++)
            House(seat: seat, setup: header.houses[seat]),
        ],
        _owner = List.filled(header.board.cellCount, noHouse),
        _cityOf = List.filled(header.board.cellCount, noCity),
        market = header.deck == null
            ? Market.start(header.seed)
            : Market.deal(header.deck!, Prng(header.seed)),
        round = 1,
        turnInRound = 0,
        playsLeft = Rules.playsPerTurn,
        rowBuysLeft = Rules.rowBuysPerTurn {
    for (final house in houses) {
      final heart = house.setup.heart;
      if (!board.isLand(heart)) {
        throw ArgumentError.value(
            heart, 'heart', '${house.name} starts on water or off the board');
      }
      for (final other in houses) {
        if (other.seat < house.seat &&
            heart.withinReach(other.setup.heart, Rules.settleDistance)) {
          throw ArgumentError.value(heart, 'heart',
              '${house.name} starts within reach of ${other.name}');
        }
      }
    }
    for (final house in houses) {
      _foundCity(house.seat, house.setup.heart);
      house.hand.addAll(house.setup.openingHand);
      house.goods = Rules.startingGoods;
    }
    _beginTurn();
  }

  /// The state [log] leads to from [header]'s start. A log is a record of
  /// accepted actions, so one the rules refuse is an error, not a result.
  factory MatchState.replay(MatchHeader header, Iterable<Action> log) {
    final state = MatchState.start(header);
    var index = 0;
    for (final action in log) {
      final refusal = state.apply(action);
      if (refusal != null) {
        throw StateError('action $index of the log, $action, was refused: '
            '${refusal.name}');
      }
      index++;
    }
    return state;
  }

  /// The owner value of a cell nobody holds.
  static const int noHouse = -1;

  /// The city value of a cell no city stands on.
  static const int noCity = -1;

  final MatchHeader header;

  Board get board => header.board;

  /// The houses in seat order.
  final List<House> houses;

  /// Every city founded so far, by id. Cities are never removed.
  final List<City> cities = [];

  /// Per cell, the seat of the house that owns it, or [noHouse].
  final List<int> _owner;

  /// Per cell, the id of the city standing on it, or [noCity].
  final List<int> _cityOf;

  /// 1-based. Past [Rules.rounds] once the match is over.
  int round;

  /// How many houses have finished their turn this round.
  int turnInRound;

  /// Cards the current house may still play this turn.
  int playsLeft;

  /// Cards the current house may still buy from the row this turn.
  int rowBuysLeft;

  /// The shared row, deck and discard pile.
  final Market market;

  /// Strength the current house has played on each target this turn that
  /// has not yet taken it. Cleared when the turn ends.
  final Map<Cell, int> _pressure = {};

  /// The rival city cells that touched the current house's land when its
  /// turn began. Only these can be attacked this turn.
  Set<Cell> _cityTargetsAtTurnStart = const {};

  /// The rival city cells the current house may attack this turn: those
  /// that touched its land when the turn began.
  Set<Cell> get cityTargetsAtTurnStart =>
      Set.unmodifiable(_cityTargetsAtTurnStart);

  // ── Turn order ─────────────────────────────────────────────────────────

  /// Every house has played its last turn, or only one still has a heart.
  bool get isOver => round > Rules.rounds || aliveCount <= 1;

  /// The seat round [round] starts with: one later every round, wrapping.
  int get firstSeat => (round - 1) % houses.length;

  /// Whose turn it is.
  int get currentSeat => (firstSeat + turnInRound) % houses.length;

  House get currentHouse => houses[currentSeat];

  // ── Ownership ──────────────────────────────────────────────────────────

  /// The seat owning [cell], or [noHouse] for open land, water or a cell
  /// off the board.
  int ownerOf(Cell cell) =>
      board.contains(cell) ? _owner[board.indexOf(cell)] : noHouse;

  /// The city standing on [cell], or null.
  City? cityAt(Cell cell) {
    if (!board.contains(cell)) return null;
    final id = _cityOf[board.indexOf(cell)];
    return id == noCity ? null : cities[id];
  }

  bool isCityCell(Cell cell) => cityAt(cell) != null;

  /// Land nobody owns yet.
  bool isUnclaimed(Cell cell) => board.isLand(cell) && ownerOf(cell) == noHouse;

  /// A cell [seat] owns with no city on it: what yields, what a Monument
  /// scores, where a district can go.
  bool isPlainTerritoryOf(Cell cell, int seat) =>
      ownerOf(cell) == seat && !isCityCell(cell);

  /// Every cell [seat] owns, in row order.
  Iterable<Cell> cellsOf(int seat) sync* {
    for (var index = 0; index < _owner.length; index++) {
      if (_owner[index] == seat) yield board.cellAt(index);
    }
  }

  int cellsOwnedBy(int seat) => _owner.where((owner) => owner == seat).length;

  /// How much of the valley nobody has claimed.
  int get openLandCount {
    var open = 0;
    for (var index = 0; index < _owner.length; index++) {
      if (_owner[index] == noHouse && board.terrain[index].isLand) open++;
    }
    return open;
  }

  Iterable<City> citiesOf(int seat) =>
      cities.where((city) => city.owner == seat);

  int cityCountOf(int seat) => citiesOf(seat).length;

  int districtCountOf(int seat) =>
      citiesOf(seat).fold(0, (sum, city) => sum + city.districtCount);

  /// How many districts of [kind] [seat] has across its cities.
  int districtsOfKind(int seat, CardKind kind) =>
      citiesOf(seat).fold(0, (sum, city) => sum + city.count(kind));

  // ── Prices ─────────────────────────────────────────────────────────────

  /// What a basic card costs [seat] now: the printed price plus one rise for
  /// every [Rules.basicPriceStep] districts it already has.
  Goods basicPriceFor(int seat) =>
      Rules.basicPrice +
      Rules.basicPriceRise * (districtCountOf(seat) ~/ Rules.basicPriceStep);

  /// What a Settle costs [seat] now: the printed price plus one rise for
  /// every city beyond its first.
  Goods settlePriceFor(int seat) =>
      CardKind.settle.price +
      Rules.settlePriceRise * (cityCountOf(seat) - 1).clamp(0, cities.length);

  /// What [kind] costs [seat] now.
  Goods priceOf(CardKind kind, int seat) {
    if (kind.isBasic) return basicPriceFor(seat);
    if (kind == CardKind.settle) return settlePriceFor(seat);
    return kind.price;
  }

  /// How many of one good [seat] gives for one of another: fewer with a
  /// Market.
  int tradeRateFor(int seat) => districtsOfKind(seat, CardKind.market) > 0
      ? Rules.marketTrade
      : Rules.bankTrade;

  // ── Yields ─────────────────────────────────────────────────────────────

  /// What the gathering district on [cell] produces: 1 of its good for each
  /// touching cell of its terrain that is its owner's plain territory. 0 for
  /// any other cell.
  int districtYield(Cell cell) {
    final city = cityAt(cell);
    final kind = city?.districts[cell];
    final good = kind?.gathers;
    if (city == null || good == null) return 0;
    var yield = 0;
    for (final beside in cell.touching) {
      if (!board.contains(beside)) continue;
      if (board.terrainAt(beside).yields != good) continue;
      if (isPlainTerritoryOf(beside, city.owner)) yield++;
    }
    return yield;
  }

  /// What [seat]'s cities produce at the start of its turn.
  Goods yieldOf(int seat) {
    var goods = Goods.none;
    for (final city in citiesOf(seat)) {
      goods += Rules.heartYield;
      for (final entry in city.districts.entries) {
        final good = entry.value.gathers;
        if (good == null) continue;
        goods += Goods.only(good, districtYield(entry.key));
      }
    }
    return goods;
  }

  // ── Offered cells ──────────────────────────────────────────────────────

  /// Every cell the current house could play [kind] on. What the game
  /// highlights when a card is armed. For a military card, [handIndex] says
  /// which card, since the rest of the hand decides what can be finished.
  Iterable<Cell> offeredCells(CardKind kind, {int? handIndex}) sync* {
    final index = handIndex ?? currentHouse.hand.indexOf(kind);
    for (final cell in board.cells) {
      final refusal = kind.isMilitary
          ? _attackRefusal(kind, cell, index)
          : _placementRefusal(kind, cell);
      if (refusal == null) yield cell;
    }
  }

  // ── Mutation ───────────────────────────────────────────────────────────

  /// Founds a city for [seat] on [cell] and claims the land around it.
  void _foundCity(int seat, Cell cell) {
    final city = City(id: cities.length, owner: seat, heart: cell);
    cities.add(city);
    _owner[board.indexOf(cell)] = seat;
    _cityOf[board.indexOf(cell)] = city.id;
    _claimAround(cell, seat);
  }

  /// Adds a district of [kind] to [city] on [cell] and claims the land
  /// around it.
  void _placeDistrict(City city, Cell cell, CardKind kind) {
    city.placeDistrict(cell, kind);
    _cityOf[board.indexOf(cell)] = city.id;
    _claimAround(cell, city.owner);
  }

  /// The whole claiming rule: every unclaimed land cell within
  /// [Rules.claimReach] of [cell] becomes [seat]'s.
  void _claimAround(Cell cell, int seat) {
    for (final near in cell.cellsWithinReach(Rules.claimReach)) {
      if (isUnclaimed(near)) _owner[board.indexOf(near)] = seat;
    }
  }

  /// Opens the current house's turn: its cities collect and it has its
  /// plays again.
  void _beginTurn() {
    playsLeft = Rules.playsPerTurn;
    rowBuysLeft = Rules.rowBuysPerTurn;
    _pressure.clear();
    _cityTargetsAtTurnStart = _reachableCityCells();
    currentHouse.goods += yieldOf(currentSeat);
  }

  // ── Identity ───────────────────────────────────────────────────────────

  /// A number that changes whenever anything in the state does. Two replays
  /// of one log on two platforms must give the same fingerprint, which is
  /// what the browser test checks.
  ///
  /// Folded in integer arithmetic that stays well under 2⁵³.
  int fingerprint() {
    const modulus = 1000000007;
    var hash = 17;
    void fold(int value) {
      hash = (hash * 31 + value + 1) % modulus;
    }

    fold(round);
    fold(turnInRound);
    fold(playsLeft);
    fold(rowBuysLeft);
    market.fingerprint(fold);
    final pressed = _pressure.keys.toList()
      ..sort((a, b) => board.indexOf(a).compareTo(board.indexOf(b)));
    for (final cell in pressed) {
      fold(board.indexOf(cell));
      fold(_pressure[cell]!);
    }
    _owner.forEach(fold);
    _cityOf.forEach(fold);
    for (final house in houses) {
      fold(house.goods.grain);
      fold(house.goods.wood);
      fold(house.goods.stone);
      fold(house.renown);
      fold(house.hand.length);
      for (final card in house.hand) {
        fold(card.index);
      }
    }
    for (final city in cities) {
      fold(city.owner);
      fold(board.indexOf(city.heart));
      final districts = city.districts.entries.toList()
        ..sort((a, b) => board.indexOf(a.key).compareTo(board.indexOf(b.key)));
      for (final district in districts) {
        fold(board.indexOf(district.key));
        fold(district.value.index);
      }
    }
    return hash;
  }
}
