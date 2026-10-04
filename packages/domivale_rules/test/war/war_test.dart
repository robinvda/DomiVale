import 'package:domivale_rules/domivale_rules.dart';
import 'package:test/test.dart';

import '../support/two_houses.dart';

/// The Hill House (seat 0, a Warlord with a Siege in hand) at (3, 3) and
/// the Lake House (seat 1, a Builder) at (10, 3), their lands meeting at
/// x = 6 | 7.
MatchHeader warHeader({Board? board}) =>
    twoHouses(board: board, first: Banner.warlord, second: Banner.builder);

/// Hearts four apart along a row: Hill (3, 3) and Lake (8, 3). Hill's land
/// reaches x = 6, so Lake's (7, 3) is a foothold and the heart is one
/// March away.
MatchHeader closeHeader({int size = 16, List<HouseSetup> more = const []}) =>
    MatchHeader(
      board: Board.filled(size: size),
      seed: 1,
      houses: [
        HouseSetup(
          name: 'Hill House',
          banner: Banner.warlord,
          heart: const Cell(3, 3),
          chosenBasic: CardKind.quarry,
        ),
        HouseSetup(
          name: 'Lake House',
          banner: Banner.builder,
          heart: const Cell(8, 3),
          chosenBasic: CardKind.lumberCamp,
        ),
        ...more,
      ],
    );

/// Ends turns until [seat] is to play. The first seat moves one on every
/// round, so "the next turn" is often the same house again.
void passTo(MatchState state, int seat) {
  var guard = 0;
  while (state.currentSeat != seat) {
    accept(state, const EndTurn());
    if (++guard > 20 || state.isOver) {
      throw StateError('seat $seat never came round');
    }
  }
}

/// Hands the current house a card, as a test shortcut past the market.
void give(MatchState state, CardKind kind) => state.currentHouse.hand.add(kind);

/// Plays the first card of [kind] in the current hand on [cell].
void play(MatchState state, CardKind kind, Cell cell) =>
    accept(state, PlayCard(inHand(state, kind), cell));

/// The Lake House grows a thin arm toward the Hill House: heart (10, 3),
/// then (9, 3), (8, 3), (7, 3). The last touches Hill land.
void lakeArm(MatchState state) {
  passTo(state, 1);
  accept(state, const PlayCard(0, Cell(9, 3)));
  accept(state, const PlayCard(0, Cell(8, 3)));
  accept(state, const PlayCard(0, Cell(7, 3)));
}

void main() {
  group('defence', () {
    test('is what stands there, plus the ground it stands on', () {
      final rows = List.filled(16, 'm' * 16)
        ..[2] = 'mmmmmmmf${'m' * 8}'
        ..[4] = 'mmmmmmmh${'m' * 8}';
      final state = MatchState.start(warHeader(board: Board.parse(rows)));
      // Lake territory: 1. On forest or hills: 2. Open land: 0. A heart: 5.
      expect(state.defenceOf(const Cell(7, 3), 0), 1);
      expect(state.defenceOf(const Cell(7, 2), 0), 2);
      expect(state.defenceOf(const Cell(7, 4), 0), 2);
      expect(state.defenceOf(const Cell(8, 8), 0), 0);
      expect(state.defenceOf(const Cell(10, 3), 0), 5);
      lakeArm(state);
      expect(state.defenceOf(const Cell(7, 3), 0), 3, reason: 'a district');
    });

    test('rises by one for a target above every attacking cell beside it', () {
      final heights = List.filled(16, '0' * 16)..[3] = '0000000111000000';
      final board = Board.parse(List.filled(16, 'm' * 16), heightRows: heights);
      final state = MatchState.start(warHeader(board: board));
      // (7, 3) at height 1 touches only Hill's (6, 3) at height 0: uphill.
      expect(state.defenceOf(const Cell(7, 3), 0), 2);
      // From the Lake side, (6, 3) at height 0 is downhill of (7, 3).
      expect(state.defenceOf(const Cell(6, 3), 1), 1);
    });

    test('Walls add two within reach 1', () {
      final state = MatchState.start(warHeader());
      passTo(state, 1);
      give(state, CardKind.walls);
      play(state, CardKind.walls, const Cell(9, 3));
      passTo(state, 0);
      // Reach 1 of (9, 3) covers (8, 3) and the heart; not (7, 3).
      expect(state.defenceOf(const Cell(8, 3), 0), 1 + Rules.wallsBonus);
      expect(state.defenceOf(const Cell(10, 3), 0), 5 + Rules.wallsBonus);
      expect(state.defenceOf(const Cell(7, 3), 0), 1);
    });
  });

  group('taking cells', () {
    test('a March takes territory beside your land and earns no renown', () {
      final state = MatchState.start(warHeader());
      give(state, CardKind.march);
      final outcome = state.attackOutcome(CardKind.march, const Cell(7, 3))!;
      expect(outcome.defence, 1);
      expect(outcome.strength, 2);
      expect(outcome.takes, isTrue);
      play(state, CardKind.march, const Cell(7, 3));
      expect(state.ownerOf(const Cell(7, 3)), 0);
      expect(state.houses[0].renown, 0);
      expect(state.market.discardPile, [CardKind.march]);
    });

    test('a March takes open land too, at no defence', () {
      final state = MatchState.start(warHeader());
      give(state, CardKind.march);
      // (3, 7) is just past Hill's land: open, touching (3, 6).
      expect(state.isUnclaimed(const Cell(3, 7)), isTrue);
      expect(state.attackOutcome(CardKind.march, const Cell(3, 7))!.defence, 0);
      play(state, CardKind.march, const Cell(3, 7));
      expect(state.ownerOf(const Cell(3, 7)), 0);
    });

    test('a March cannot touch a city cell', () {
      final state = MatchState.start(warHeader());
      lakeArm(state);
      passTo(state, 0);
      give(state, CardKind.march);
      expect(
          state
              .apply(PlayCard(inHand(state, CardKind.march), const Cell(7, 3))),
          Refusal.marchOnCity);
    });

    test('a Siege razes a district into your plain land and earns renown', () {
      final state = MatchState.start(warHeader());
      lakeArm(state);
      passTo(state, 0);
      final outcome = state.attackOutcome(CardKind.siege, const Cell(7, 3))!;
      expect(outcome.defence, 3);
      expect(outcome.strength, 4);
      expect(outcome.takes, isTrue);
      expect(outcome.abandoned, isEmpty);
      play(state, CardKind.siege, const Cell(7, 3));
      expect(state.ownerOf(const Cell(7, 3)), 0);
      expect(state.isCityCell(const Cell(7, 3)), isFalse);
      expect(state.houses[0].renown, 1);
      expect(state.citiesOf(1).first.districtCount, 2);
      expect(state.market.discardPile, contains(CardKind.siege));
    });

    test('a city cell that became reachable this turn is not offered', () {
      final state = MatchState.start(warHeader());
      passTo(state, 1);
      accept(state, const PlayCard(0, Cell(9, 3)));
      accept(state, const PlayCard(0, Cell(8, 3)));
      passTo(state, 0);
      // Hill takes the foothold (7, 3)...
      give(state, CardKind.march);
      play(state, CardKind.march, const Cell(7, 3));
      expect(state.ownerOf(const Cell(7, 3)), 0);
      // ...and the district behind it now touches Hill land, but did not
      // when the turn began.
      expect(state.attackOutcome(CardKind.siege, const Cell(8, 3)), isNull);
      expect(
        state.apply(PlayCard(inHand(state, CardKind.siege), const Cell(8, 3))),
        Refusal.cityNotReachableAtTurnStart,
      );
      expect(state.offeredCells(CardKind.siege),
          isNot(contains(const Cell(8, 3))));
      // Next turn it is.
      accept(state, const EndTurn());
      passTo(state, 0);
      expect(state.offeredCells(CardKind.siege), contains(const Cell(8, 3)));
    });

    test('renown stays after the cell is lost again', () {
      final state = MatchState.start(warHeader());
      lakeArm(state);
      passTo(state, 0);
      play(state, CardKind.siege, const Cell(7, 3));
      expect(state.houses[0].renown, 1);
      passTo(state, 1);
      give(state, CardKind.march);
      play(state, CardKind.march, const Cell(7, 3));
      expect(state.ownerOf(const Cell(7, 3)), 1);
      expect(state.houses[0].renown, 1);
      expect(state.crownsOf(0), state.cellsOwnedBy(0) ~/ 3 + 1 + 1);
    });
  });

  group('stacking', () {
    test('a Siege with a Barracks in reach does not take a bare heart; two do',
        () {
      final state = MatchState.start(closeHeader());
      // Turn 1: a Farm at (4, 3), a Barracks at (5, 3) - within reach 3 of
      // the Lake heart at (8, 3) - and a March onto the foothold (7, 3).
      give(state, CardKind.barracks);
      give(state, CardKind.march);
      play(state, CardKind.farm, const Cell(4, 3));
      play(state, CardKind.barracks, const Cell(5, 3));
      play(state, CardKind.march, const Cell(7, 3));
      accept(state, const EndTurn());
      passTo(state, 0);

      expect(state.barracksBonus(const Cell(8, 3), 0), 1);
      final one = state.attackOutcome(CardKind.siege, const Cell(8, 3))!;
      expect(one.defence, 5);
      expect(one.strength, 5);
      expect(one.takes, isFalse, reason: 'a tie goes to the defender');
      expect(one.shortfall, 1);
      // One Siege in hand cannot finish it, so the heart is not offered.
      expect(state.offeredCells(CardKind.siege),
          isNot(contains(const Cell(8, 3))));
      expect(
        state.apply(PlayCard(inHand(state, CardKind.siege), const Cell(8, 3))),
        Refusal.notEnoughStrength,
      );

      // With a second Siege it is: the first presses, the second takes.
      give(state, CardKind.siege);
      expect(state.offeredCells(CardKind.siege), contains(const Cell(8, 3)));
      play(state, CardKind.siege, const Cell(8, 3));
      expect(state.pressureOn(const Cell(8, 3)), 4);
      expect(state.cityAt(const Cell(8, 3))?.owner, 1, reason: 'pressed');
      final two = state.attackOutcome(CardKind.siege, const Cell(8, 3))!;
      expect(two.strength, 9);
      expect(two.takes, isTrue);
      play(state, CardKind.siege, const Cell(8, 3));
      expect(state.cityAt(const Cell(8, 3))?.owner, 0);
      expect(state.houses[0].renown, 1);
    });

    test('pressure that does not take the cell is gone when the turn ends', () {
      final state = MatchState.start(closeHeader());
      give(state, CardKind.march);
      play(state, CardKind.march, const Cell(7, 3));
      accept(state, const EndTurn());
      passTo(state, 0);
      give(state, CardKind.siege);
      play(state, CardKind.siege, const Cell(8, 3));
      expect(state.pressureOn(const Cell(8, 3)), 4);
      accept(state, const EndTurn());
      passTo(state, 0);
      expect(state.pressureOn(const Cell(8, 3)), 0);
      expect(state.cityAt(const Cell(8, 3))?.owner, 1);
    });
  });

  group('abandonment', () {
    test('razing the base of a thin arm abandons the arm; the land stays', () {
      final state = MatchState.start(warHeader());
      lakeArm(state);
      passTo(state, 0);
      // Hill marches onto (7, 2) and (8, 2), Lake land beside the arm, so
      // the arm's middle (8, 3) touches Hill land from the next turn.
      give(state, CardKind.march);
      give(state, CardKind.march);
      play(state, CardKind.march, const Cell(7, 2));
      play(state, CardKind.march, const Cell(8, 2));
      accept(state, const EndTurn());
      passTo(state, 0);
      final outcome = state.attackOutcome(CardKind.siege, const Cell(8, 3))!;
      expect(outcome.abandoned, [const Cell(7, 3)]);
      play(state, CardKind.siege, const Cell(8, 3));
      // The razed cell is Hill's; the cut-off tip is Lake's plain land.
      expect(state.ownerOf(const Cell(8, 3)), 0);
      expect(state.ownerOf(const Cell(7, 3)), 1);
      expect(state.isCityCell(const Cell(7, 3)), isFalse);
      expect(state.isCityCell(const Cell(9, 3)), isTrue);
      expect(state.houses[0].renown, 1, reason: 'none for the abandoned one');
      expect(state.citiesOf(1).first.districtCount, 1);
    });

    test('a razed district in a compact city abandons nothing', () {
      final state = MatchState.start(warHeader());
      passTo(state, 1);
      // A block: heart (10, 3), districts (9, 3), (9, 4), (10, 4).
      accept(state, const PlayCard(0, Cell(9, 3)));
      accept(state, const PlayCard(0, Cell(9, 4)));
      accept(state, const PlayCard(0, Cell(10, 4)));
      passTo(state, 0);
      give(state, CardKind.march);
      give(state, CardKind.march);
      play(state, CardKind.march, const Cell(7, 3));
      play(state, CardKind.march, const Cell(8, 3));
      accept(state, const EndTurn());
      passTo(state, 0);
      final outcome = state.attackOutcome(CardKind.siege, const Cell(9, 3))!;
      expect(outcome.abandoned, isEmpty,
          reason: '(9, 4) still reaches the heart through (10, 4)');
      play(state, CardKind.siege, const Cell(9, 3));
      expect(state.isCityCell(const Cell(9, 4)), isTrue);
      expect(state.isCityCell(const Cell(10, 4)), isTrue);
      expect(state.citiesOf(1).first.districtCount, 2);
    });
  });

  group('a heart falling', () {
    test('brings the city and the land around it over, and ends a duel', () {
      final state = MatchState.start(closeHeader());
      give(state, CardKind.march);
      play(state, CardKind.march, const Cell(7, 3));
      passTo(state, 1);
      accept(state, const PlayCard(0, Cell(9, 3)));
      passTo(state, 0);
      give(state, CardKind.siege);
      play(state, CardKind.siege, const Cell(8, 3));
      play(state, CardKind.siege, const Cell(8, 3));
      expect(state.cityAt(const Cell(8, 3))?.owner, 0);
      expect(state.cityAt(const Cell(9, 3))?.owner, 0,
          reason: 'the district comes with the heart');
      expect(state.ownerOf(const Cell(11, 3)), 0,
          reason: 'plain land within reach 3 of the city follows it');
      expect(state.cityCountOf(1), 0);
      expect(state.isAlive(1), isFalse);
      expect(state.houses[0].renown, 1);
      expect(state.houses[1].hand, isEmpty);
      expect(state.isOver, isTrue, reason: 'one heart left');
      expect(state.winner, 0);
      expect(state.crownsOf(1), 0);
    });

    test('a fallen house is skipped, and its far land is fallen land', () {
      // Three houses, so a fall does not end the match.
      final state = MatchState.start(twoHouses(
        board: Board.filled(size: 20),
        first: Banner.warlord,
        second: Banner.builder,
      ).let((h) => MatchHeader(
            board: h.board,
            seed: h.seed,
            houses: [
              ...h.houses,
              HouseSetup(
                name: 'Wood House',
                banner: Banner.builder,
                heart: const Cell(10, 15),
                chosenBasic: CardKind.farm,
              ),
            ],
          )));
      // Lake's arm reaches (7, 3), which claims (6, 0): within reach 3 of
      // (7, 3) and of no other Lake city cell.
      lakeArm(state);
      expect(state.ownerOf(const Cell(6, 0)), 1);
      // Hill razes the arm cell by cell, then takes the heart.
      passTo(state, 0);
      play(state, CardKind.siege, const Cell(7, 3));
      accept(state, const EndTurn());
      passTo(state, 0);
      give(state, CardKind.siege);
      play(state, CardKind.siege, const Cell(8, 3));
      accept(state, const EndTurn());
      passTo(state, 0);
      give(state, CardKind.siege);
      play(state, CardKind.siege, const Cell(9, 3));
      accept(state, const EndTurn());
      passTo(state, 0);
      give(state, CardKind.siege);
      give(state, CardKind.siege);
      play(state, CardKind.siege, const Cell(10, 3));
      play(state, CardKind.siege, const Cell(10, 3));
      expect(state.isAlive(1), isFalse);
      expect(state.isOver, isFalse, reason: 'two houses still stand');
      expect(state.aliveCount, 2);
      // The land near the city came over; (6, 0) did not, and is fallen.
      expect(state.ownerOf(const Cell(10, 4)), 0);
      expect(state.ownerOf(const Cell(6, 0)), 1);
      expect(state.isFallenLand(const Cell(6, 0)), isTrue);
      expect(state.isUnclaimed(const Cell(6, 0)), isFalse,
          reason: 'growth never claims fallen land');
      expect(state.defenceOf(const Cell(6, 0), 0), Rules.territoryDefence);
      expect(state.crownsOf(1), 0);
      expect(state.standings.last, 1);
      // The fallen house is skipped in the turn order from here on.
      final seen = <int>[];
      for (var i = 0; i < 6; i++) {
        accept(state, const EndTurn());
        seen.add(state.currentSeat);
      }
      expect(seen, isNot(contains(1)));
      expect(seen.toSet(), {0, 2});
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
