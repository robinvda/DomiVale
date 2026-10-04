import '../board/cell.dart';
import '../cards/card_kind.dart';
import '../match/action.dart';
import '../match/banner.dart';
import '../match/goods.dart';
import '../match/match_state.dart';
import '../match/scoring.dart';
import '../rules.dart';
import 'temperament.dart';

/// A bot house: plays by the same rules and sees what a player sees - the
/// board, the row, its own hand - and never a rival's hand or the deck.
///
/// Greedy, one step at a time. [nextAction] values every play, buy and
/// attack open to the house right now in crowns per play, weighted by the
/// house's temperament, and answers the best one; the caller applies it and
/// asks again until the answer is to end the turn. Nothing is random and
/// the board is walked in row order, so the same state always gets the same
/// answer, which is what lets a match of bots replay.
///
/// The estimates are the ones `tools/match_sim.py` measured the design
/// with. Difficulty, when it comes, is search depth, never extra goods.
class Bot {
  const Bot(this.temperament);

  /// The bot for a house with [banner].
  factory Bot.forBanner(Banner banner) => Bot(Temperament.of(banner));

  final Temperament temperament;

  /// A play worth less than this a play is not made; the turn ends instead.
  static const double minValuePerPlay = 0.1;

  /// What the current house should do next, ending the turn when nothing is
  /// worth doing. Never an action the rules would refuse.
  Action nextAction(MatchState state) {
    if (state.isOver) return const EndTurn();
    final house = state.currentHouse;
    final seat = house.seat;
    final options = <_Option>[];

    if (state.playsLeft > 0) {
      final legal = _legalDistrictCells(state, seat);
      final claims = {
        for (final cell in legal) cell: _claimCount(state, cell),
      };

      // Play what is in hand.
      for (final kind in house.hand.toSet()) {
        final option = _playOption(state, kind, legal, claims, fromHand: true);
        if (option != null) options.add(option);
      }

      if (house.hand.length < Rules.handCap) {
        // Buy a basic and play it now.
        _Option? bestBasic;
        for (final kind in CardKind.basics) {
          final found = _bestDistrict(state, kind, legal, claims);
          if (found != null &&
              (bestBasic == null || found.value > bestBasic.value)) {
            bestBasic = _Option(
              found.value - 0.01,
              BuyBasic(kind),
              price: state.basicPriceFor(seat),
            );
          }
        }
        if (bestBasic != null && bestBasic.value > minValuePerPlay) {
          options.add(bestBasic);
        }

        // Buy a row card and play it now.
        if (state.rowBuysLeft > 0) {
          for (var slot = 0; slot < Rules.rowSize; slot++) {
            final kind = state.market.at(slot);
            if (kind == null) continue;
            final option =
                _playOption(state, kind, legal, claims, fromHand: false);
            if (option == null) continue;
            options.add(_Option(
              option.value - 0.01,
              BuyFromRow(slot),
              price: state.priceOf(kind, seat),
            ));
          }
        }
      }
    }

    // Buy a row card to keep for a later turn, or to keep from a rival.
    if (state.rowBuysLeft > 0 && house.hand.length < Rules.handCap) {
      for (var slot = 0; slot < Rules.rowSize; slot++) {
        final kind = state.market.at(slot);
        if (kind == null) continue;
        final hold = _holdValue(state, kind);
        final denial = _denialValue(state, kind);
        var value = hold > denial ? hold : denial;
        if (kind.isMilitary &&
            house.setup.banner != Banner.warlord &&
            house.hand.length >= Rules.handCap - 1) {
          value *= 0.5;
        }
        if (value <= minValuePerPlay) continue;
        options.add(
            _Option(value, BuyFromRow(slot), price: state.priceOf(kind, seat)));
      }
    }

    // The best option the house can pay for, trading if it has to.
    options.sort((a, b) => b.value.compareTo(a.value));
    for (final option in options) {
      if (option.value <= minValuePerPlay) break;
      final price = option.price;
      if (price == null || house.goods.covers(price)) return option.action;
      final trade = _tradeToward(state, price);
      if (trade != null) return trade;
    }
    return const EndTurn();
  }

  // ── Plays ──────────────────────────────────────────────────────────────

  /// The best play of [kind] for the current house, or null if it has none
  /// worth making. [fromHand] says whether the card is already held; a card
  /// still on the row is valued as if it were.
  _Option? _playOption(
    MatchState state,
    CardKind kind,
    List<Cell> legal,
    Map<Cell, int> claims, {
    required bool fromHand,
  }) {
    final hand = state.currentHouse.hand;
    final index = fromHand ? hand.indexOf(kind) : hand.length;
    if (kind.isDistrict) {
      final found = _bestDistrict(state, kind, legal, claims);
      if (found == null) return null;
      return _Option(found.value, PlayCard(index, found.cell));
    }
    if (kind == CardKind.settle) {
      final found = _bestSettle(state);
      if (found == null) return null;
      return _Option(found.value, PlayCard(index, found.cell));
    }
    return _bestAttack(state, kind, fromHand: fromHand);
  }

  /// Own plain cells touching one of the house's city cells, in row order.
  List<Cell> _legalDistrictCells(MatchState state, int seat) {
    final cells = <Cell>{};
    for (final city in state.citiesOf(seat)) {
      for (final own in city.cells) {
        for (final beside in own.touching) {
          if (state.board.isLand(beside) &&
              state.isPlainTerritoryOf(beside, seat)) {
            cells.add(beside);
          }
        }
      }
    }
    final list = cells.toList()
      ..sort(
          (a, b) => state.board.indexOf(a).compareTo(state.board.indexOf(b)));
    return list;
  }

  /// How many open land cells a heart or district on [cell] would claim.
  int _claimCount(MatchState state, Cell cell) {
    var count = 0;
    for (final near in cell.cellsWithinReach(Rules.claimReach)) {
      if (state.isUnclaimed(near)) count++;
    }
    return count;
  }

  /// How much of the match is left, 1 at the start and nearly 0 at the end.
  double _remaining(MatchState state) =>
      (Rules.rounds - state.round + 1) / Rules.rounds;

  /// What [amount] of yield a turn is worth in crowns over the rest of the
  /// match, less for a house already rich in income.
  double _yieldValue(MatchState state, int seat, int amount) {
    if (amount <= 0) return 0;
    final income = state.yieldOf(seat).total;
    final scarcity = income <= 12 ? 1.0 : 12 / income;
    return amount * _remaining(state) * 1.5 * scarcity;
  }

  /// What a district of [kind] on [cell] would gather.
  int _yieldAt(MatchState state, int seat, Cell cell, CardKind kind) {
    final good = kind.gathers;
    if (good == null) return 0;
    var count = 0;
    for (final beside in cell.touching) {
      if (!state.board.contains(beside)) continue;
      if (state.board.terrainAt(beside).yields != good) continue;
      if (state.isPlainTerritoryOf(beside, seat)) count++;
    }
    return count;
  }

  /// How many own plain cells touch [cell]: what a Monument there scores.
  int _monumentCrownsAt(MatchState state, int seat, Cell cell) => cell.touching
      .where((beside) => state.isPlainTerritoryOf(beside, seat))
      .length;

  /// The value every district on [cell] shares: the land it claims, less
  /// what the cell was feeding.
  double _placeBase(MatchState state, int seat, Cell cell, int claims) {
    final w = temperament;
    var value = claims / Rules.cellsPerCrown * w.claim + 0.04 * claims;
    var lostYield = 0;
    for (final beside in cell.touching) {
      final city = state.cityAt(beside);
      if (city == null || city.owner != seat) continue;
      final kind = city.districts[beside];
      if (kind == CardKind.monument) {
        value -= 1.0;
      } else if (kind?.gathers != null &&
          state.board.terrainAt(cell).yields == kind!.gathers) {
        lostYield++;
      }
    }
    return value - _yieldValue(state, seat, lostYield) * w.yield;
  }

  _Found? _bestDistrict(MatchState state, CardKind kind, List<Cell> legal,
      Map<Cell, int> claims) {
    final seat = state.currentSeat;
    final w = temperament;
    _Found? best;
    for (final cell in legal) {
      var value = _placeBase(state, seat, cell, claims[cell]!);
      switch (kind) {
        case CardKind.farm:
        case CardKind.lumberCamp:
        case CardKind.quarry:
          value += _yieldValue(state, seat, _yieldAt(state, seat, cell, kind)) *
              w.yield;
        case CardKind.market:
          value += 1.0 * w.market +
              (state.districtsOfKind(seat, CardKind.market) == 0 ? 0.3 : 0.05);
        case CardKind.monument:
          value += _monumentCrownsAt(state, seat, cell) * w.monument;
        case CardKind.walls:
          value += _wallsValue(state, seat, cell) * w.walls;
        case CardKind.barracks:
          value += _barracksValue(state, seat, cell) * w.barracks;
        default:
          break;
      }
      if (best == null || value > best.value) best = _Found(value, cell);
    }
    return best;
  }

  /// Whether a living rival owns a cell within reach 2 of [cell].
  bool _exposed(MatchState state, int seat, Cell cell) {
    for (final near in cell.cellsWithinReach(2)) {
      final owner = state.ownerOf(near);
      if (owner != MatchState.noHouse &&
          owner != seat &&
          state.isAlive(owner)) {
        return true;
      }
    }
    return false;
  }

  /// Whether one of [seat]'s Walls is within reach 1 of [cell].
  bool _walledAt(MatchState state, int seat, Cell cell) {
    for (final city in state.citiesOf(seat)) {
      for (final entry in city.districts.entries) {
        if (entry.value == CardKind.walls &&
            entry.key.withinReach(cell, Rules.wallsReach)) {
          return true;
        }
      }
    }
    return false;
  }

  double _wallsValue(MatchState state, int seat, Cell cell) {
    var value = 0.0;
    for (final near in cell.cellsWithinReach(Rules.wallsReach)) {
      final city = state.cityAt(near);
      if (city == null || city.owner != seat) continue;
      if (_walledAt(state, seat, near) || !_exposed(state, seat, near)) {
        continue;
      }
      value += city.heart == near ? 1.0 : 0.3;
    }
    if (_exposed(state, seat, cell)) value += 0.1;
    return value;
  }

  double _barracksValue(MatchState state, int seat, Cell cell) {
    var value = 0.0;
    for (final near in cell.cellsWithinReach(Rules.barracksReach)) {
      final owner = state.ownerOf(near);
      if (owner == MatchState.noHouse ||
          owner == seat ||
          !state.isAlive(owner)) {
        continue;
      }
      final city = state.cityAt(near);
      if (city == null) {
        value += 0.02;
      } else {
        value += city.heart == near ? 0.5 : 0.25;
      }
    }
    return value;
  }

  /// The open cell a new city would claim most from, valued.
  _Found? _bestSettle(MatchState state) {
    final w = temperament;
    Cell? bestCell;
    var bestClaims = -1;
    for (final cell in state.offeredCells(CardKind.settle)) {
      final claims = _claimCount(state, cell);
      if (claims > bestClaims) {
        bestClaims = claims;
        bestCell = cell;
      }
    }
    if (bestCell == null) return null;
    final value = (bestClaims / Rules.cellsPerCrown * w.claim +
            1 +
            2.5 * _remaining(state) +
            0.5) *
        w.settle;
    return _Found(value, bestCell);
  }

  // ── War ────────────────────────────────────────────────────────────────

  /// Whether the house holds a Siege, sees one on the row, or is a Warlord.
  bool _canSiegeSoon(MatchState state) {
    final house = state.currentHouse;
    return house.hand.contains(CardKind.siege) ||
        state.market.row.contains(CardKind.siege) ||
        house.setup.banner == Banner.warlord;
  }

  /// What taking [target] is worth to the current house, in crowns.
  double _captureValue(MatchState state, Cell target) {
    final seat = state.currentSeat;
    final w = temperament.war;
    final owner = state.ownerOf(target);
    if (owner == MatchState.noHouse) return 1 / Rules.cellsPerCrown;
    final alive = state.isAlive(owner);
    final remaining = _remaining(state);
    final city = state.cityAt(target);

    if (city == null) {
      var value =
          1 / Rules.cellsPerCrown + (alive ? 1 / Rules.cellsPerCrown : 0.0);
      if (alive) {
        for (final beside in target.touching) {
          final near = state.cityAt(beside);
          if (near == null) continue;
          if (near.owner == owner) {
            final kind = near.districts[beside];
            final terrain = state.board.terrainAt(target);
            if (kind?.gathers != null && kind!.gathers == terrain.yields) {
              value += 0.35 * remaining;
            } else if (kind == CardKind.monument) {
              value += 1.0;
            }
            if (!state.cityTargetsAtTurnStart.contains(beside) &&
                _canSiegeSoon(state)) {
              value += (kind == null ? 1.2 : 0.5) * w;
            }
          }
          if (near.owner == seat) {
            // Retaking a foothold beside one of our own city cells.
            value += near.heart == beside ? 1.0 : 0.5;
          }
        }
      }
      return value * w;
    }

    if (city.heart == target) {
      var following = 0;
      for (final cell in state.cellsOf(owner)) {
        if (state.isCityCell(cell)) continue;
        if (!city.cells.any((c) => cell.withinReach(c, Rules.claimReach))) {
          continue;
        }
        final elsewhere = state.citiesOf(owner).any((other) =>
            other.id != city.id &&
            other.cells.any((c) => cell.withinReach(c, Rules.claimReach)));
        if (!elsewhere) following++;
      }
      var value = 1 +
          Rules.renownPerCityCell +
          2 * following / Rules.cellsPerCrown +
          0.3 * city.districtCount;
      for (final entry in city.districts.entries) {
        if (entry.value == CardKind.monument) {
          value += state.monumentCrowns(entry.key);
        } else if (entry.value == CardKind.market) {
          value += 1;
        }
      }
      if (state.cityCountOf(owner) == 1) value += 2;
      return value * w;
    }

    final outcome = state.attackOutcome(CardKind.siege, target);
    final abandoned = outcome?.abandoned.length ?? 0;
    final kind = city.districts[target]!;
    var value =
        2 / Rules.cellsPerCrown + Rules.renownPerCityCell + 0.4 * abandoned;
    switch (kind) {
      case CardKind.monument:
        value += state.monumentCrowns(target);
      case CardKind.market:
        value += 1;
      case CardKind.walls:
      case CardKind.barracks:
        value += 0.5;
      default:
        value += 0.25 * remaining * state.districtYield(target);
    }
    for (final beside in target.touching) {
      final near = state.cityAt(beside);
      if (near != null && near.owner == owner && near.heart == beside) {
        value += 1.0;
      }
    }
    return value * w;
  }

  /// The best attack to start with [kind]: the target worth most per card
  /// it takes, among those the hand can finish this turn.
  _Option? _bestAttack(MatchState state, CardKind kind,
      {required bool fromHand}) {
    final house = state.currentHouse;
    final hand = fromHand ? house.hand : [...house.hand, kind];
    final index = fromHand ? hand.indexOf(kind) : hand.length - 1;
    final marches = hand.where((c) => c == CardKind.march).length;
    final sieges = hand.where((c) => c == CardKind.siege).length;

    _Option? best;
    for (final target in _borderCells(state, house.seat)) {
      final isCity = state.isCityCell(target);
      if (isCity && kind == CardKind.march) continue;
      if (isCity && !state.cityTargetsAtTurnStart.contains(target)) continue;
      final need = state.defenceOf(target, house.seat) -
          state.barracksBonus(target, house.seat) -
          state.pressureOn(target);
      final combo = _combo(
        marches: isCity ? 0 : marches,
        sieges: sieges,
        playsLeft: state.playsLeft,
        need: need,
        leadWith: kind,
      );
      if (combo == null) continue;
      final value = _captureValue(state, target) / combo;
      if (best == null || value > best.value) {
        best = _Option(value, PlayCard(index, target));
      }
    }
    return best;
  }

  /// Land cells beside the house's own that are not its own.
  Iterable<Cell> _borderCells(MatchState state, int seat) sync* {
    final seen = <Cell>{};
    for (final own in state.cellsOf(seat)) {
      for (final beside in own.touching) {
        if (!state.board.isLand(beside)) continue;
        if (state.ownerOf(beside) == seat) continue;
        if (seen.add(beside)) yield beside;
      }
    }
  }

  /// The fewest cards from the hand whose strength together beats [need],
  /// using [leadWith] first; null when the hand cannot. Among sets of the
  /// same size, the one spending fewer Sieges.
  int? _combo({
    required int marches,
    required int sieges,
    required int playsLeft,
    required int need,
    required CardKind leadWith,
  }) {
    if (leadWith == CardKind.march && marches == 0) return null;
    if (leadWith == CardKind.siege && sieges == 0) return null;
    for (var k = 1; k <= playsLeft; k++) {
      for (var s = 0; s <= k && s <= sieges; s++) {
        final m = k - s;
        if (m > marches) continue;
        if (leadWith == CardKind.siege && s == 0) continue;
        if (leadWith == CardKind.march && m == 0) continue;
        if (CardKind.march.strength * m + CardKind.siege.strength * s > need) {
          return k;
        }
      }
    }
    return null;
  }

  // ── Holding and denying ────────────────────────────────────────────────

  /// What a card is worth in hand for a later turn.
  double _holdValue(MatchState state, CardKind kind) {
    final seat = state.currentSeat;
    final w = temperament;
    switch (kind) {
      case CardKind.siege:
        final near = _borderCells(state, seat).any(state.isCityCell);
        return (near ? 0.9 : 0.35) * w.war;
      case CardKind.march:
        final near = _borderCells(state, seat)
            .any((cell) => state.ownerOf(cell) != MatchState.noHouse);
        return (near ? 0.45 : 0.1) * w.war;
      case CardKind.settle:
        return _bestSettle(state) == null ? 0.0 : 0.8 * w.settle;
      case CardKind.monument:
        return 0.6 * w.monument;
      case CardKind.market:
        return state.districtsOfKind(seat, CardKind.market) == 0
            ? 0.5 * w.market
            : 0.2;
      case CardKind.walls:
        return 0.3 * w.walls;
      case CardKind.barracks:
        return 0.3 * w.barracks;
      default:
        return 0.0;
    }
  }

  /// What buying a card so a rival cannot have it is worth.
  double _denialValue(MatchState state, CardKind kind) {
    final seat = state.currentSeat;
    if (kind == CardKind.settle) {
      final rivalGrowing = state.houses.any((house) =>
          house.seat != seat &&
          state.isAlive(house.seat) &&
          state.cityCountOf(house.seat) < 3);
      final open = state.openLandCount / state.board.landCount;
      if (rivalGrowing && open > 0.1) return 0.5;
    }
    if (kind == CardKind.siege) {
      for (final cell in _borderCells(state, seat)) {
        final owner = state.ownerOf(cell);
        if (owner == MatchState.noHouse || !state.isAlive(owner)) continue;
        if (state.houses[owner].setup.banner == Banner.warlord) return 0.4;
      }
    }
    return 0.0;
  }

  // ── Goods ──────────────────────────────────────────────────────────────

  /// One trade toward affording [price], or null when no trade helps: the
  /// good most in surplus goes for the good most short.
  Trade? _tradeToward(MatchState state, Goods price) {
    final house = state.currentHouse;
    final rate = state.tradeRateFor(house.seat);
    var deficit = 0;
    var surplus = 0;
    for (final good in Good.values) {
      final gap = price.of(good) - house.goods.of(good);
      if (gap > 0) deficit += gap;
      if (gap < 0) surplus += -gap ~/ rate;
    }
    if (deficit == 0 || surplus < deficit) return null;
    Good? short;
    for (final good in Good.values) {
      if (house.goods.of(good) < price.of(good)) {
        short = good;
        break;
      }
    }
    Good? donor;
    var donorSpare = -1;
    for (final good in Good.values) {
      if (good == short) continue;
      final spare = house.goods.of(good) - price.of(good);
      if (spare >= rate && spare > donorSpare) {
        donorSpare = spare;
        donor = good;
      }
    }
    if (short == null || donor == null) return null;
    return Trade(give: donor, take: short);
  }
}

/// One thing the bot could do, and what it is worth per play.
class _Option {
  const _Option(this.value, this.action, {this.price});

  final double value;
  final Action action;

  /// What the action costs, or null for a play.
  final Goods? price;
}

/// A cell and the value of playing there.
class _Found {
  const _Found(this.value, this.cell);

  final double value;
  final Cell cell;
}
