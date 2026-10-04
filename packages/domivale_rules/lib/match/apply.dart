part of 'match_state.dart';

/// State + action → state, or a refusal.
///
/// Every action is validated here and nowhere else. The game asks the rules
/// what is legal and sends an action; it never changes state on its own.
extension MatchStateActions on MatchState {
  /// Applies [action] for the house whose turn it is. Returns null when it
  /// was done, or why it was not - in which case nothing changed.
  Refusal? apply(Action action) {
    if (isOver) return Refusal.matchOver;
    switch (action) {
      case BuyBasic(:final kind):
        return _buyBasic(kind);
      case BuyFromRow(:final slot):
        return _buyFromRow(slot);
      case Trade(:final give, :final take):
        return _trade(give, take);
      case PlayCard(:final handIndex, :final cell):
        return _playCard(handIndex, cell);
      case EndTurn():
        _endTurn();
        return null;
    }
  }

  Refusal? _buyBasic(CardKind kind) {
    final house = currentHouse;
    if (!kind.isBasic) return Refusal.notABasicCard;
    if (house.hand.length >= Rules.handCap) return Refusal.handFull;
    final price = basicPriceFor(house.seat);
    if (!house.goods.covers(price)) return Refusal.cannotAfford;
    house.goods -= price;
    house.hand.add(kind);
    return null;
  }

  Refusal? _buyFromRow(int slot) {
    final house = currentHouse;
    final kind = market.at(slot);
    if (kind == null) return Refusal.rowSlotEmpty;
    if (rowBuysLeft == 0) return Refusal.noRowBuysLeft;
    if (house.hand.length >= Rules.handCap) return Refusal.handFull;
    final price = priceOf(kind, house.seat);
    if (!house.goods.covers(price)) return Refusal.cannotAfford;
    house.goods -= price;
    house.hand.add(market.take(slot));
    rowBuysLeft--;
    return null;
  }

  Refusal? _trade(Good give, Good take) {
    final house = currentHouse;
    if (give == take) return Refusal.sameGood;
    final rate = tradeRateFor(house.seat);
    if (house.goods.of(give) < rate) return Refusal.cannotAfford;
    house.goods = house.goods - Goods.only(give, rate) + Goods.only(take, 1);
    return null;
  }

  Refusal? _playCard(int handIndex, Cell cell) {
    final house = currentHouse;
    if (handIndex < 0 || handIndex >= house.hand.length) {
      return Refusal.noSuchCard;
    }
    if (playsLeft == 0) return Refusal.noPlaysLeft;
    final kind = house.hand[handIndex];
    final refusal = kind.isMilitary
        ? _attackRefusal(kind, cell, handIndex)
        : _placementRefusal(kind, cell);
    if (refusal != null) return refusal;

    house.hand.removeAt(handIndex);
    playsLeft--;
    // Market cards come back round through the discard pile; a basic card
    // came from a pile without limit and goes nowhere.
    if (!kind.isBasic) market.discard(kind);
    if (kind.isDistrict) {
      _placeDistrict(_cityToGrow(house.seat, cell)!, cell, kind);
    } else if (kind == CardKind.settle) {
      _foundCity(house.seat, cell);
    } else {
      _attack(kind, cell);
    }
    return null;
  }

  /// Why the current house could not play military [kind] on [cell], or
  /// null if it could: a legal target that the hand can finish this turn.
  Refusal? _attackRefusal(CardKind kind, Cell cell, int handIndex) {
    final refusal = _targetRefusal(kind, cell);
    if (refusal != null) return refusal;
    if (!_canFinishAttack(kind, cell, handIndex)) {
      return Refusal.notEnoughStrength;
    }
    return null;
  }

  /// Why the current house could not play [kind] on [cell], or null if it
  /// could. Shared by playing and by the offered-cells query, so what the
  /// game highlights is exactly what the rules accept.
  Refusal? _placementRefusal(CardKind kind, Cell cell) {
    final seat = currentSeat;
    if (!board.contains(cell)) return Refusal.cellOutsideBoard;
    if (!board.terrainAt(cell).isLand) return Refusal.notLand;
    if (kind.isDistrict) {
      if (ownerOf(cell) != seat) return Refusal.cellNotYours;
      if (isCityCell(cell)) return Refusal.cellIsCity;
      if (_cityToGrow(seat, cell) == null) return Refusal.notTouchingYourCity;
      return null;
    }
    if (kind == CardKind.settle) {
      final owner = ownerOf(cell);
      if (owner != MatchState.noHouse && owner != seat) {
        return Refusal.cellNotYours;
      }
      for (final near in cell.cellsWithinReach(Rules.settleDistance)) {
        if (isCityCell(near)) return Refusal.tooCloseToACity;
      }
      return null;
    }
    // Military cards go through _attackRefusal.
    return Refusal.cellIsYours;
  }

  /// The city of [seat] a district on [cell] would join: the one with the
  /// lowest id among those with a cell touching [cell], or null if none.
  City? _cityToGrow(int seat, Cell cell) {
    City? found;
    for (final beside in cell.touching) {
      final city = cityAt(beside);
      if (city == null || city.owner != seat) continue;
      if (found == null || city.id < found.id) found = city;
    }
    return found;
  }

  /// Passes the turn to the next house still in the match. The row refills
  /// first, so nothing new is revealed until the turn is committed. When
  /// every house has played, the round ends and the next one starts one seat
  /// later; after the last round the match is over and nothing more is
  /// collected.
  void _endTurn() {
    market.refill();
    _pressure.clear();
    do {
      turnInRound++;
      if (turnInRound == houses.length) {
        turnInRound = 0;
        round++;
      }
    } while (!isOver && !isAlive(currentSeat));
    if (!isOver) _beginTurn();
  }
}
