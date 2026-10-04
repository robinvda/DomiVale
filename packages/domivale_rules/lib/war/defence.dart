part of '../match/match_state.dart';

/// What an attack on a cell would do.
class AttackOutcome {
  const AttackOutcome({
    required this.defence,
    required this.strength,
    required this.abandoned,
  });

  /// What the target needs.
  final int defence;

  /// What the attacker would bring against it once the card is played: the
  /// card, every military card already played on the target this turn, and
  /// a Barracks in reach.
  final int strength;

  /// The districts that would be abandoned if the capture happens: cut off
  /// from their heart by it.
  final List<Cell> abandoned;

  /// Whether the capture happens on this play. A tie goes to the defender.
  bool get takes => strength > defence;

  /// How much more the target needs after this play, or 0 if it falls.
  int get shortfall => takes ? 0 : defence - strength + 1;
}

/// War: what a cell needs to be taken, what a card brings against it, and
/// what a capture does.
///
/// Military cards played on one target in one turn add up, so the first
/// Siege on a heart presses it and the second takes it. A target is offered
/// only when the hand could still finish the attack this turn, so an attack
/// that is started can always be completed - or taken back with undo.
extension War on MatchState {
  /// What [target] needs: 0 for open land, 1 for territory, 3 for a
  /// district, 5 for a heart; plus 1 on forest or hills, plus 1 if it stands
  /// higher than every cell of [attacker]'s that touches it, plus 2 if one
  /// of the owner's Walls is within reach 1. A fallen house has no Walls.
  int defenceOf(Cell target, int attacker) {
    final owner = ownerOf(target);
    var defence = 0;
    if (owner != MatchState.noHouse) {
      final city = cityAt(target);
      defence = city == null
          ? Rules.territoryDefence
          : city.heart == target
              ? Rules.heartDefence
              : Rules.districtDefence;
    }
    final terrain = board.terrainAt(target);
    if (terrain == TerrainKind.forest || terrain == TerrainKind.hills) {
      defence += Rules.terrainDefenceBonus;
    }
    if (_standsAbove(target, attacker)) defence += Rules.heightDefenceBonus;
    if (owner != MatchState.noHouse &&
        isAlive(owner) &&
        _hasDistrictWithin(owner, CardKind.walls, target, Rules.wallsReach)) {
      defence += Rules.wallsBonus;
    }
    return defence;
  }

  /// Whether [target] is higher than every cell of [attacker]'s touching it.
  bool _standsAbove(Cell target, int attacker) {
    final height = board.heightAt(target);
    var touchesAny = false;
    for (final beside in target.touching) {
      if (ownerOf(beside) != attacker) continue;
      touchesAny = true;
      if (board.heightAt(beside) >= height) return false;
    }
    return touchesAny;
  }

  /// Whether [seat] has a district of [kind] within [reach] of [cell].
  bool _hasDistrictWithin(int seat, CardKind kind, Cell cell, int reach) {
    for (final city in citiesOf(seat)) {
      for (final entry in city.districts.entries) {
        if (entry.value == kind && entry.key.withinReach(cell, reach)) {
          return true;
        }
      }
    }
    return false;
  }

  /// The strength [attacker] brings to [target] beyond the cards: 1 for a
  /// Barracks within reach 3, counted once per attack.
  int barracksBonus(Cell target, int attacker) => _hasDistrictWithin(
          attacker, CardKind.barracks, target, Rules.barracksReach)
      ? Rules.barracksBonus
      : 0;

  /// Strength already played on [target] by the current house this turn.
  int pressureOn(Cell target) => _pressure[target] ?? 0;

  /// Whether [target] is a cell the current house may attack at all with
  /// [kind], before strength is counted. Null if it is, or why not.
  Refusal? _targetRefusal(CardKind kind, Cell target) {
    final seat = currentSeat;
    if (!board.contains(target)) return Refusal.cellOutsideBoard;
    if (!board.terrainAt(target).isLand) return Refusal.notLand;
    if (ownerOf(target) == seat) return Refusal.cellIsYours;
    if (!target.touching.any((beside) => ownerOf(beside) == seat)) {
      return Refusal.notTouchingYourLand;
    }
    if (isCityCell(target)) {
      if (kind == CardKind.march) return Refusal.marchOnCity;
      if (!_cityTargetsAtTurnStart.contains(target)) {
        return Refusal.cityNotReachableAtTurnStart;
      }
    }
    return null;
  }

  /// What playing [kind] on [target] would do, or null if [target] is not a
  /// cell the current house may attack.
  AttackOutcome? attackOutcome(CardKind kind, Cell target) {
    if (!kind.isMilitary || _targetRefusal(kind, target) != null) return null;
    final seat = currentSeat;
    final strength =
        pressureOn(target) + kind.strength + barracksBonus(target, seat);
    final defence = defenceOf(target, seat);
    final city = cityAt(target);
    final abandoned = city == null || city.heart == target
        ? const <Cell>[]
        : _cutOffBy(city, target);
    return AttackOutcome(
        defence: defence, strength: strength, abandoned: abandoned);
  }

  /// Whether the current house could finish an attack on [target] this
  /// turn, starting with [kind]: with the plays it has left and the military
  /// cards in its hand after this one, strongest first.
  bool _canFinishAttack(CardKind kind, Cell target, int handIndex) {
    final outcome = attackOutcome(kind, target);
    if (outcome == null) return false;
    if (outcome.takes) return true;
    final hand = currentHouse.hand;
    final others = <int>[
      for (var i = 0; i < hand.length; i++)
        if (i != handIndex &&
            hand[i].isMilitary &&
            !(isCityCell(target) && hand[i] == CardKind.march))
          hand[i].strength,
    ]..sort((a, b) => b.compareTo(a));
    var strength = outcome.strength;
    final plays = playsLeft - 1;
    for (var i = 0; i < others.length && i < plays; i++) {
      strength += others[i];
      if (strength > outcome.defence) return true;
    }
    return false;
  }

  /// The districts of [city] that would no longer reach its heart through
  /// touching city cells if [removed] were gone.
  List<Cell> _cutOffBy(City city, Cell removed) {
    final members = city.districts.keys.toSet()..remove(removed);
    final seen = <Cell>{city.heart};
    final stack = <Cell>[city.heart];
    while (stack.isNotEmpty) {
      final cell = stack.removeLast();
      for (final beside in cell.touching) {
        if (members.contains(beside) && seen.add(beside)) stack.add(beside);
      }
    }
    return [
      for (final cell in city.districts.keys)
        if (cell != removed && !seen.contains(cell)) cell,
    ];
  }

  /// Whether [seat] still has a heart. A house with none is out of the
  /// match; its land is fallen land.
  bool isAlive(int seat) => citiesOf(seat).isNotEmpty;

  /// How many houses still have a heart.
  int get aliveCount => houses.where((house) => isAlive(house.seat)).length;

  /// Whether [cell] is fallen land: owned by a house that is out of the
  /// match. It yields nothing, scores for nobody, and growth never claims
  /// it; it is taken by war like any territory cell.
  bool isFallenLand(Cell cell) {
    final owner = ownerOf(cell);
    return owner != MatchState.noHouse && !isAlive(owner);
  }

  // ── Mutation ───────────────────────────────────────────────────────────

  /// Plays a military card on [target]: adds its strength to the pressure
  /// there and, if that now beats the defence, captures the cell.
  void _attack(CardKind kind, Cell target) {
    final seat = currentSeat;
    final outcome = attackOutcome(kind, target)!;
    if (!outcome.takes) {
      _pressure[target] = pressureOn(target) + kind.strength;
      return;
    }
    _pressure.remove(target);
    _capture(target, seat);
  }

  /// What a capture does: a territory cell changes hands; a district is
  /// razed into the attacker's plain territory and earns renown; a heart
  /// brings its whole city over with the land around it and earns renown.
  /// A city left without its heart's connection loses the cut-off districts.
  void _capture(Cell target, int attacker) {
    final city = cityAt(target);
    if (city == null) {
      _owner[board.indexOf(target)] = attacker;
      return;
    }
    final victim = city.owner;
    if (city.heart == target) {
      _takeCity(city, attacker);
    } else {
      final abandoned = _cutOffBy(city, target);
      city.removeDistrict(target);
      _cityOf[board.indexOf(target)] = MatchState.noCity;
      _owner[board.indexOf(target)] = attacker;
      for (final cell in abandoned) {
        city.removeDistrict(cell);
        _cityOf[board.indexOf(cell)] = MatchState.noCity;
      }
    }
    houses[attacker].renown += Rules.renownPerCityCell;
    if (!isAlive(victim)) _fall(victim);
  }

  /// The heart falls: the city, every district of it, and every plain cell
  /// the old owner holds within reach 3 of the city and of no other city of
  /// theirs become the attacker's.
  void _takeCity(City city, int attacker) {
    final victim = city.owner;
    final following = <Cell>[];
    for (final cell in cellsOf(victim)) {
      if (isCityCell(cell)) continue;
      if (!_withinReachOfCity(cell, city)) continue;
      final otherCity = citiesOf(victim).any(
          (other) => other.id != city.id && _withinReachOfCity(cell, other));
      if (!otherCity) following.add(cell);
    }
    city.owner = attacker;
    for (final cell in city.cells) {
      _owner[board.indexOf(cell)] = attacker;
    }
    for (final cell in following) {
      _owner[board.indexOf(cell)] = attacker;
    }
  }

  bool _withinReachOfCity(Cell cell, City city) =>
      city.cells.any((own) => cell.withinReach(own, Rules.claimReach));

  /// A house with no hearts left is out of the match. Its cards go; its
  /// cells stay in its colour as fallen land.
  void _fall(int seat) {
    houses[seat].hand.clear();
  }

  /// The city cells of rivals that touch the current house's land now:
  /// recorded when the turn begins, since a city cell can be targeted only
  /// if it was reachable then.
  Set<Cell> _reachableCityCells() {
    final seat = currentSeat;
    final cells = <Cell>{};
    for (final city in cities) {
      if (city.owner == seat) continue;
      for (final cell in city.cells) {
        if (cell.touching.any((beside) => ownerOf(beside) == seat)) {
          cells.add(cell);
        }
      }
    }
    return cells;
  }
}
