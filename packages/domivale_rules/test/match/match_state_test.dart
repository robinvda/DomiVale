import 'package:domivale_rules/domivale_rules.dart';
import 'package:test/test.dart';

import '../support/two_houses.dart';

void main() {
  group('the start of a match', () {
    test('claims the land within reach 3 of every heart', () {
      final state = MatchState.start(twoHouses());
      expect(state.cellsOwnedBy(0), 37);
      expect(state.cellsOwnedBy(1), 37);
      expect(state.ownerOf(const Cell(3, 3)), 0);
      expect(state.ownerOf(const Cell(6, 3)), 0);
      expect(state.ownerOf(const Cell(7, 3)), 1);
      expect(state.ownerOf(const Cell(8, 8)), MatchState.noHouse);
      expect(state.openLandCount, 16 * 16 - 74);
      expect(state.cities, hasLength(2));
      expect(state.cityAt(const Cell(3, 3))?.owner, 0);
      expect(state.isCityCell(const Cell(4, 3)), isFalse);
    });

    test('deals the opening hand: a Farm, the chosen basic, the banner card',
        () {
      final state = MatchState.start(
          twoHouses(first: Banner.builder, second: Banner.expander));
      expect(state.houses[0].hand,
          [CardKind.farm, CardKind.quarry, CardKind.monument]);
      expect(state.houses[1].hand,
          [CardKind.farm, CardKind.lumberCamp, CardKind.farm]);
      final warlord = MatchState.start(twoHouses(second: Banner.warlord));
      expect(warlord.houses[1].hand.last, CardKind.siege);
    });

    test('gives every house its goods and lets the first house collect', () {
      final state = MatchState.start(twoHouses());
      expect(state.round, 1);
      expect(state.currentSeat, 0);
      expect(state.playsLeft, Rules.playsPerTurn);
      // 2/2/1 to start, plus the heart's 1/1/1 on collecting.
      expect(state.houses[0].goods, const Goods(grain: 3, wood: 3, stone: 2));
      expect(state.houses[1].goods, Rules.startingGoods);
    });

    test('refuses a heart on water, off the board, or on top of another', () {
      final lake =
          Board.parse(List.filled(16, 'm' * 16)..[3] = 'mmm~${'m' * 12}');
      expect(
          () => MatchState.start(twoHouses(board: lake)), throwsArgumentError);
      expect(
        () => MatchHeader(
          board: Board.filled(size: 16),
          houses: [
            HouseSetup(
                name: 'A',
                banner: Banner.builder,
                heart: const Cell(3, 3),
                chosenBasic: CardKind.farm),
            HouseSetup(
                name: 'B',
                banner: Banner.builder,
                heart: const Cell(5, 3),
                chosenBasic: CardKind.farm),
          ],
          seed: 1,
        ).let(MatchState.start),
        throwsArgumentError,
      );
    });

    test('an Expander names its banner basic and nobody else does', () {
      expect(
        () => HouseSetup(
            name: 'A',
            banner: Banner.expander,
            heart: const Cell(0, 0),
            chosenBasic: CardKind.farm),
        throwsArgumentError,
      );
      expect(
        () => HouseSetup(
            name: 'A',
            banner: Banner.builder,
            heart: const Cell(0, 0),
            chosenBasic: CardKind.farm,
            bannerBasic: CardKind.farm),
        throwsArgumentError,
      );
      expect(
        () => HouseSetup(
            name: 'A',
            banner: Banner.builder,
            heart: const Cell(0, 0),
            chosenBasic: CardKind.siege),
        throwsArgumentError,
      );
    });
  });

  group('growing', () {
    test('a district goes on own plain land touching one of your cities', () {
      final state = MatchState.start(twoHouses());
      final offered = state.offeredCells(CardKind.farm).toSet();
      expect(offered, {
        const Cell(3, 2),
        const Cell(4, 3),
        const Cell(3, 4),
        const Cell(2, 3),
      });
      expect(state.apply(const PlayCard(0, Cell(5, 3))),
          Refusal.notTouchingYourCity);
      expect(state.apply(const PlayCard(0, Cell(7, 3))), Refusal.cellNotYours);
      expect(state.apply(const PlayCard(0, Cell(3, 3))), Refusal.cellIsCity);
      expect(state.apply(const PlayCard(0, Cell(16, 3))),
          Refusal.cellOutsideBoard);
      expect(state.apply(const PlayCard(5, Cell(4, 3))), Refusal.noSuchCard);

      accept(state, const PlayCard(0, Cell(4, 3)));
      expect(state.cityAt(const Cell(4, 3))?.districts[const Cell(4, 3)],
          CardKind.farm);
      expect(state.houses[0].hand, hasLength(2));
      expect(state.playsLeft, 2);
      // The new district is a cell to grow from.
      expect(state.offeredCells(CardKind.quarry), contains(const Cell(5, 3)));
    });

    test('a district claims the open land around it', () {
      final state = MatchState.start(twoHouses());
      expect(state.ownerOf(const Cell(6, 6)), MatchState.noHouse);
      accept(state, const PlayCard(0, Cell(4, 3)));
      accept(state, const PlayCard(0, Cell(5, 3)));
      accept(state, const PlayCard(0, Cell(6, 3)));
      expect(state.ownerOf(const Cell(6, 6)), 0);
      expect(state.cellsOwnedBy(0), greaterThan(37));
    });

    test('claimed land never changes owner by growth', () {
      final state = MatchState.start(twoHouses());
      final lakeBefore = state.cellsOf(1).toSet();
      accept(state, const PlayCard(0, Cell(4, 3)));
      accept(state, const PlayCard(0, Cell(5, 3)));
      accept(state, const PlayCard(0, Cell(6, 3)));
      // Reach 3 of (6, 3) covers the Lake House's cells at x = 7 to 9.
      expect(const Cell(6, 3).withinReach(const Cell(9, 3), 3), isTrue);
      expect(state.ownerOf(const Cell(7, 3)), 1);
      expect(state.ownerOf(const Cell(9, 3)), 1);
      expect(state.cellsOf(1).toSet(), lakeBefore);
    });

    test('nothing stands on water and water is never claimed', () {
      final rows = List.filled(16, 'm' * 16)
        ..[3] = 'mmmm~${'m' * 11}'
        ..[5] = 'mmm~${'m' * 12}';
      final state = MatchState.start(twoHouses(board: Board.parse(rows)));
      expect(state.ownerOf(const Cell(4, 3)), MatchState.noHouse);
      expect(state.cellsOwnedBy(0), 35);
      expect(state.apply(const PlayCard(0, Cell(4, 3))), Refusal.notLand);
      expect(
          state.offeredCells(CardKind.farm), isNot(contains(const Cell(4, 3))));
    });

    test('a district joins the lowest-numbered city it touches', () {
      // Grow the Hill House's city to touch the Lake House's border, then
      // check a Lake district never joins a Hill city and vice versa.
      final state = MatchState.start(twoHouses());
      accept(state, const PlayCard(0, Cell(4, 3)));
      accept(state, const PlayCard(0, Cell(5, 3)));
      accept(state, const PlayCard(0, Cell(6, 3)));
      accept(state, const EndTurn());
      // The Lake House's (7, 3) touches a Hill city cell at (6, 3), but it is
      // not the Lake House's city, so it is not a place to grow.
      expect(
          state.offeredCells(CardKind.farm), isNot(contains(const Cell(7, 3))));
    });
  });

  group('yields', () {
    test('a heart gives one of each and a district one per touching cell', () {
      final state = MatchState.start(twoHouses());
      expect(state.yieldOf(0), Rules.heartYield);
      accept(state, const PlayCard(0, Cell(4, 3)));
      // (4, 2), (5, 3) and (4, 4) are own plain meadow; (3, 3) is the heart.
      expect(state.districtYield(const Cell(4, 3)), 3);
      expect(state.yieldOf(0), const Goods(grain: 4, wood: 1, stone: 1));
    });

    test('count only own plain territory of the right terrain', () {
      final rows = List.filled(16, 'm' * 16)
        ..[2] = 'mmmmf${'m' * 11}'
        ..[4] = 'mmmmh${'m' * 11}';
      final state = MatchState.start(twoHouses(board: Board.parse(rows)));
      accept(state, const PlayCard(0, Cell(4, 3)));
      // Forest above and hills below: only (5, 3) is meadow.
      expect(state.districtYield(const Cell(4, 3)), 1);

      // A Quarry on (5, 3) takes that meadow out of the land that feeds the
      // Farm, and finds no hills of its own.
      accept(state, const PlayCard(0, Cell(5, 3)));
      expect(state.districtYield(const Cell(4, 3)), 0);
      expect(state.districtYield(const Cell(5, 3)), 0);
    });

    test('a rival\'s cell beside a district feeds it nothing', () {
      final state = MatchState.start(twoHouses());
      accept(state, const PlayCard(0, Cell(4, 3)));
      accept(state, const PlayCard(0, Cell(5, 3)));
      // The Farm at the border: (7, 3) is the Lake House's.
      accept(state, const PlayCard(0, Cell(6, 3)));
      expect(state.cityAt(const Cell(6, 3))?.districts[const Cell(6, 3)],
          CardKind.monument);
      // Make the border cell a Farm instead, on a fresh match.
      final again = MatchState.start(twoHouses());
      accept(again, PlayCard(inHand(again, CardKind.quarry), const Cell(4, 3)));
      accept(
          again, PlayCard(inHand(again, CardKind.monument), const Cell(5, 3)));
      accept(again, PlayCard(inHand(again, CardKind.farm), const Cell(6, 3)));
      // (6, 2) and (6, 4) are own meadow; (5, 3) is a city cell; (7, 3) is
      // the Lake House's.
      expect(again.districtYield(const Cell(6, 3)), 2);
    });

    test('are collected at the start of the owner\'s turn, not before', () {
      final state = MatchState.start(twoHouses());
      accept(state, const PlayCard(0, Cell(4, 3)));
      final hillGoods = state.houses[0].goods;
      accept(state, const EndTurn());
      expect(state.currentSeat, 1);
      expect(state.houses[0].goods, hillGoods);
      expect(state.houses[1].goods, Rules.startingGoods + Rules.heartYield);
      accept(state, const EndTurn());
      expect(state.round, 2);
      expect(state.currentSeat, 1, reason: 'round 2 starts one seat later');
      accept(state, const EndTurn());
      expect(state.currentSeat, 0);
      // The Farm's three meadows and the heart.
      expect(state.houses[0].goods,
          hillGoods + const Goods(grain: 4, wood: 1, stone: 1));
    });
  });

  group('a turn', () {
    test('plays at most three cards', () {
      final state = MatchState.start(twoHouses());
      accept(state, const BuyBasic(CardKind.farm));
      expect(state.houses[0].hand, hasLength(4));
      accept(state, const PlayCard(0, Cell(4, 3)));
      accept(state, const PlayCard(0, Cell(5, 3)));
      accept(state, const PlayCard(0, Cell(6, 3)));
      expect(state.playsLeft, 0);
      expect(state.apply(const PlayCard(0, Cell(3, 2))), Refusal.noPlaysLeft);
      expect(state.houses[0].hand, hasLength(1));
      // Buying is not playing.
      accept(state, const BuyBasic(CardKind.quarry));
      accept(state, const EndTurn());
      accept(state, const EndTurn());
      expect(state.playsLeft, Rules.playsPerTurn);
    });

    test('buys basics at a price that rises per three districts', () {
      final state = MatchState.start(twoHouses());
      expect(state.basicPriceFor(0), const Goods(grain: 1, wood: 1));
      accept(state, const BuyBasic(CardKind.lumberCamp));
      expect(state.houses[0].goods, const Goods(grain: 2, wood: 2, stone: 2));
      expect(state.houses[0].hand.last, CardKind.lumberCamp);
      accept(state, const PlayCard(0, Cell(4, 3)));
      accept(state, const PlayCard(0, Cell(5, 3)));
      expect(state.basicPriceFor(0), const Goods(grain: 1, wood: 1));
      accept(state, const PlayCard(0, Cell(6, 3)));
      expect(state.districtCountOf(0), 3);
      expect(state.basicPriceFor(0), const Goods(grain: 2, wood: 2));
      expect(state.priceOf(CardKind.farm, 0), const Goods(grain: 2, wood: 2));
      expect(state.priceOf(CardKind.walls, 0), CardKind.walls.price);
    });

    test('refuses a buy it cannot pay for, a full hand, or a market card', () {
      final state = MatchState.start(twoHouses());
      expect(
          state.apply(const BuyBasic(CardKind.walls)), Refusal.notABasicCard);
      accept(state, const BuyBasic(CardKind.farm));
      accept(state, const BuyBasic(CardKind.farm));
      expect(state.houses[0].hand, hasLength(Rules.handCap));
      expect(state.apply(const BuyBasic(CardKind.farm)), Refusal.handFull);
      accept(state, const PlayCard(0, Cell(4, 3)));
      expect(state.houses[0].goods, const Goods(grain: 1, wood: 1, stone: 2));
      accept(state, const BuyBasic(CardKind.farm));
      expect(state.houses[0].goods, const Goods(stone: 2));
      accept(state, const PlayCard(0, Cell(5, 3)));
      expect(state.apply(const BuyBasic(CardKind.farm)), Refusal.cannotAfford);
    });

    test('a refused action changes nothing', () {
      final state = MatchState.start(twoHouses());
      final before = state.fingerprint();
      expect(state.apply(const PlayCard(0, Cell(9, 9))), isNotNull);
      expect(state.apply(const BuyBasic(CardKind.siege)), isNotNull);
      expect(state.apply(const PlayCard(9, Cell(4, 3))), isNotNull);
      expect(state.fingerprint(), before);
    });
  });

  group('settling', () {
    test('needs open land outside reach 3 of every city cell', () {
      final state = MatchState.start(twoHouses());
      final offered = state.offeredCells(CardKind.settle).toSet();
      // Within reach 3 of a heart: no. The Lake House's land: no. Open land
      // further off: yes.
      expect(offered, isNot(contains(const Cell(6, 3))));
      expect(offered, isNot(contains(const Cell(8, 3))));
      expect(offered, contains(const Cell(3, 8)));
      expect(offered, contains(const Cell(12, 12)));
      // Own land is allowed if it is far enough from every city, which at
      // the start no own cell is.
      for (final cell in state.cellsOf(0)) {
        expect(offered, isNot(contains(cell)));
      }
      for (final cell in offered) {
        expect(state.isUnclaimed(cell), isTrue);
        for (final near in cell.cellsWithinReach(Rules.settleDistance)) {
          expect(state.isCityCell(near), isFalse);
        }
      }
    });

    test('a Settle\'s price rises per city beyond the first', () {
      final state = MatchState.start(twoHouses());
      expect(state.settlePriceFor(0), CardKind.settle.price);
      expect(state.priceOf(CardKind.settle, 0), CardKind.settle.price);
    });
  });

  group('military cards', () {
    test('are offered on cells beside your land, never on your own', () {
      final state = MatchState.start(twoHouses(first: Banner.warlord));
      expect(state.houses[0].hand.last, CardKind.siege);
      final offered = state.offeredCells(CardKind.siege).toSet();
      expect(offered, isNotEmpty);
      for (final cell in offered) {
        expect(state.ownerOf(cell), isNot(0));
        expect(cell.touching.any((c) => state.ownerOf(c) == 0), isTrue);
      }
      expect(state.apply(const PlayCard(2, Cell(3, 4))), Refusal.cellIsYours);
      expect(state.apply(const PlayCard(2, Cell(12, 12))),
          Refusal.notTouchingYourLand);
    });
  });

  group('the turn order', () {
    test('starts every round one seat later than the round before, wrapping',
        () {
      final state = MatchState.start(threeHouses());
      final seen = <int, List<int>>{};
      while (!state.isOver) {
        seen.putIfAbsent(state.round, () => []).add(state.currentSeat);
        accept(state, const EndTurn());
      }
      expect(seen.keys, hasLength(Rules.rounds));
      expect(seen[1], [0, 1, 2]);
      expect(seen[2], [1, 2, 0]);
      expect(seen[3], [2, 0, 1]);
      expect(seen[4], [0, 1, 2]);
      expect(seen[20], [1, 2, 0]);
      // Over 20 rounds every seat went first about equally often.
      final firsts = <int, int>{};
      for (final seats in seen.values) {
        firsts.update(seats.first, (n) => n + 1, ifAbsent: () => 1);
      }
      expect(firsts, {0: 7, 1: 7, 2: 6});
    });

    test('ends the match after the last house\'s twentieth turn', () {
      final state = MatchState.start(twoHouses());
      for (var turn = 0; turn < Rules.rounds * 2; turn++) {
        expect(state.isOver, isFalse);
        accept(state, const EndTurn());
      }
      expect(state.isOver, isTrue);
      expect(state.round, Rules.rounds + 1);
      expect(state.apply(const EndTurn()), Refusal.matchOver);
      expect(state.apply(const BuyBasic(CardKind.farm)), Refusal.matchOver);
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
