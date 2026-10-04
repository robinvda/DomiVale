import 'package:domivale_rules/domivale_rules.dart';
import 'package:test/test.dart';

import '../support/two_houses.dart';

void main() {
  test('the base deck is forty cards in the mix the design names', () {
    final deck = Market.baseDeck();
    expect(deck, hasLength(40));
    for (final entry in Rules.deckMix.entries) {
      expect(deck.where((card) => card == entry.key).length, entry.value,
          reason: entry.key.label);
    }
    expect(deck.any((card) => card.isBasic), isFalse,
        reason: 'the basic piles are not in the deck');
  });

  test('a seed deals the same row every time, and another seed another', () {
    final one = Market.start(9);
    final two = Market.start(9);
    expect(one.row, two.row);
    expect(one.row.whereType<CardKind>(), hasLength(Rules.rowSize));
    expect(one.deckSize, 40 - Rules.rowSize);
    final other = Market.start(10);
    expect(other.row, isNot(one.row));
  });

  test('a bought card leaves a gap until the turn ends', () {
    final state = MatchState.start(twoHouses(deck: _richDeck()));
    // The house has 3/3/2 after collecting; a March costs 1 grain, 1 wood.
    final slot = state.market.row.indexOf(CardKind.march);
    accept(state, BuyFromRow(slot));
    expect(state.houses[0].hand.last, CardKind.march);
    expect(state.houses[0].goods, const Goods(grain: 2, wood: 2, stone: 2));
    expect(state.market.at(slot), isNull);
    expect(state.rowBuysLeft, 1);
    expect(state.apply(BuyFromRow(slot)), Refusal.rowSlotEmpty);
    accept(state, const EndTurn());
    expect(state.market.at(slot), isNotNull, reason: 'refilled at end of turn');
    expect(state.rowBuysLeft, Rules.rowBuysPerTurn);
  });

  test('a third row buy in a turn is refused; the piles are not limited', () {
    // A row of Marches at 1 grain, 1 wood each; the house holds 3/3/2 and
    // could pay for three.
    final state = MatchState.start(
        twoHouses(deck: List.filled(Rules.rowSize, CardKind.march)));
    accept(state, const BuyFromRow(0));
    accept(state, const BuyFromRow(1));
    expect(state.rowBuysLeft, 0);
    expect(state.apply(const BuyFromRow(2)), Refusal.noRowBuysLeft);
    // The hand is at the cap now, so a basic is refused for that and not
    // for the buys: the piles are not limited.
    expect(state.houses[0].hand, hasLength(Rules.handCap));
    expect(state.apply(const BuyBasic(CardKind.farm)), Refusal.handFull);
    accept(state, const PlayCard(0, Cell(4, 3)));
    accept(state, const BuyBasic(CardKind.farm));
  });

  test('a row card costs its printed price, and a full hand refuses it', () {
    final state = MatchState.start(twoHouses(deck: _richDeck()));
    final walls = state.market.row.indexOf(CardKind.walls);
    expect(state.apply(BuyFromRow(walls)), Refusal.cannotAfford,
        reason: 'Walls cost 3 stone and the house holds 2');
    accept(state, const BuyBasic(CardKind.farm));
    accept(state, const BuyBasic(CardKind.farm));
    expect(state.houses[0].hand, hasLength(Rules.handCap));
    final march = state.market.row.indexOf(CardKind.march);
    expect(state.apply(BuyFromRow(march)), Refusal.handFull);
  });

  test('a Settle\'s price follows the cities held', () {
    final state = MatchState.start(twoHouses(deck: _richDeck()));
    final seat = state.currentSeat;
    expect(state.settlePriceFor(seat), CardKind.settle.price);
    final slot = state.market.row.indexOf(CardKind.settle);
    accept(state, BuyFromRow(slot));
    expect(state.houses[seat].goods,
        const Goods(grain: 3, wood: 3, stone: 2) - CardKind.settle.price);
    // Found the second city on open land.
    final settle = state.houses[seat].hand.indexOf(CardKind.settle);
    accept(state, PlayCard(settle, const Cell(3, 12)));
    expect(state.cityCountOf(seat), 2);
    expect(state.settlePriceFor(seat),
        CardKind.settle.price + Rules.settlePriceRise);
    expect(state.priceOf(CardKind.settle, seat),
        const Goods(grain: 3, wood: 3, stone: 2));
    expect(state.market.discardPile, [CardKind.settle],
        reason: 'a played market card goes to the discard pile');
  });

  test('played basics go nowhere; played market cards go to the discard', () {
    final state = MatchState.start(twoHouses(deck: _richDeck()));
    accept(state, const PlayCard(0, Cell(4, 3)));
    expect(state.market.discardSize, 0);
    final monument = state.houses[0].hand.indexOf(CardKind.monument);
    accept(state, PlayCard(monument, const Cell(5, 3)));
    expect(state.market.discardPile, [CardKind.monument]);
  });

  test('the deck recycles the discard pile in seed order', () {
    // A deck of exactly a row: after the deal the deck is empty, so the next
    // refill has to shuffle whatever has been discarded.
    final deck = List.filled(Rules.rowSize, CardKind.march);
    final header = MatchHeader(
      board: Board.filled(size: 16),
      seed: 4,
      deck: deck,
      houses: twoHouses().houses,
    );
    final state = MatchState.start(header);
    expect(state.market.deckSize, 0);
    accept(state, const BuyFromRow(0));
    accept(state, const BuyFromRow(1));
    // Play the Builder's Monument so there is something to recycle, then
    // end the turn: two gaps, one card in the discard.
    final monument = state.houses[0].hand.indexOf(CardKind.monument);
    accept(state, PlayCard(monument, const Cell(4, 3)));
    accept(state, const EndTurn());
    final row = state.market.row;
    expect(row.where((card) => card == CardKind.monument), hasLength(1));
    expect(row.where((card) => card == null), hasLength(1),
        reason: 'one gap stays: nothing is left anywhere');
    expect(state.market.discardSize, 0);

    // Same seed, same log, same row - here and on any other platform.
    final again = MatchState.replay(header, [
      const BuyFromRow(0),
      const BuyFromRow(1),
      PlayCard(monument, const Cell(4, 3)),
      const EndTurn(),
    ]);
    expect(again.market.row, row);
    expect(again.fingerprint(), state.fingerprint());
  });

  test('trading is three for one at the bank and two for one with a Market',
      () {
    final state = MatchState.start(twoHouses(deck: _richDeck()));
    expect(state.tradeRateFor(0), Rules.bankTrade);
    expect(state.apply(const Trade(give: Good.grain, take: Good.grain)),
        Refusal.sameGood);
    expect(state.apply(const Trade(give: Good.stone, take: Good.grain)),
        Refusal.cannotAfford,
        reason: '2 stone is short of 3');
    accept(state, const Trade(give: Good.grain, take: Good.stone));
    expect(state.houses[0].goods, const Goods(grain: 0, wood: 3, stone: 3));

    // A Market district halves the rate. The house pays 2 grain, 2 wood for
    // it and plays it beside the heart.
    accept(state, const Trade(give: Good.wood, take: Good.grain));
    accept(state, const Trade(give: Good.stone, take: Good.grain));
    expect(state.houses[0].goods, const Goods(grain: 2, wood: 0, stone: 0));
    final state2 = MatchState.start(twoHouses(deck: _richDeck()));
    final market = state2.market.row.indexOf(CardKind.market);
    accept(state2, BuyFromRow(market));
    accept(
        state2,
        PlayCard(
            state2.houses[0].hand.indexOf(CardKind.market), const Cell(4, 3)));
    expect(state2.tradeRateFor(0), Rules.marketTrade);
    expect(state2.houses[0].goods, const Goods(grain: 1, wood: 1, stone: 2));
    accept(state2, const Trade(give: Good.stone, take: Good.grain));
    expect(state2.houses[0].goods, const Goods(grain: 2, wood: 1, stone: 0));
  });
}

/// A deck whose first row is a Settle, a Market, Walls and three Marches:
/// dealt from the end, so the end of the list is the row.
List<CardKind> _richDeck() => const [
      CardKind.siege,
      CardKind.monument,
      CardKind.barracks,
      CardKind.march,
      CardKind.march,
      CardKind.march,
      CardKind.walls,
      CardKind.market,
      CardKind.settle,
    ];
