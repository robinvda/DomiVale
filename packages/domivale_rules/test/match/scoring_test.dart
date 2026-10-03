import 'package:domivale_rules/domivale_rules.dart';
import 'package:test/test.dart';

import '../support/two_houses.dart';

void main() {
  test('crowns count owned cells, one per three, and a heart', () {
    final state = MatchState.start(twoHouses());
    expect(state.cellsOwnedBy(0), 37);
    expect(state.crownsOf(0), 37 ~/ 3 + 1);
    expect(state.crownsOf(1), 37 ~/ 3 + 1);
    accept(state, const PlayCard(0, Cell(4, 3)));
    expect(state.crownsOf(0), state.cellsOwnedBy(0) ~/ 3 + 1);
    // A district is worth what it claims, not what it is.
    final cellsBefore = state.cellsOwnedBy(0);
    accept(state, PlayCard(inHand(state, CardKind.quarry), const Cell(3, 2)));
    expect(state.cellsOwnedBy(0), greaterThan(cellsBefore));
    expect(state.crownsOf(0), state.cellsOwnedBy(0) ~/ 3 + 1);
  });

  test('a Market is a crown', () {
    final header = MatchHeader(
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
            heart: const Cell(10, 3),
            chosenBasic: CardKind.farm),
      ],
      seed: 1,
    );
    final state = MatchState.start(header);
    // No Market can be bought in these rules yet, so the count is checked
    // through the city directly.
    state.cities[0].placeDistrict(const Cell(4, 3), CardKind.market);
    expect(state.districtsOfKind(0, CardKind.market), 1);
    expect(state.crownsOf(0), 37 ~/ 3 + 1 + 1);
  });

  group('a Monument', () {
    test('scores one per touching own plain cell, not the city cell', () {
      final state = MatchState.start(twoHouses());
      accept(
          state, PlayCard(inHand(state, CardKind.monument), const Cell(4, 3)));
      // (4, 2), (5, 3), (4, 4) are plain own land; (3, 3) is the heart.
      expect(state.monumentCrowns(const Cell(4, 3)), 3);
      expect(state.crownsOf(0), state.cellsOwnedBy(0) ~/ 3 + 1 + 3);
    });

    test('loses a crown for every side another district takes', () {
      final state = MatchState.start(twoHouses());
      accept(
          state, PlayCard(inHand(state, CardKind.monument), const Cell(4, 3)));
      accept(state, PlayCard(inHand(state, CardKind.farm), const Cell(5, 3)));
      expect(state.monumentCrowns(const Cell(4, 3)), 2);
      accept(state, PlayCard(inHand(state, CardKind.quarry), const Cell(4, 2)));
      expect(state.monumentCrowns(const Cell(4, 3)), 1);
    });

    test('counts no rival cell and no water', () {
      final rows = List.filled(16, 'm' * 16)..[4] = 'mmmmmm~${'m' * 9}';
      final state = MatchState.start(twoHouses(board: Board.parse(rows)));
      accept(state, PlayCard(inHand(state, CardKind.farm), const Cell(4, 3)));
      accept(state, PlayCard(inHand(state, CardKind.quarry), const Cell(5, 3)));
      accept(
          state, PlayCard(inHand(state, CardKind.monument), const Cell(6, 3)));
      // (6, 2) is own plain land; (7, 3) is the Lake House's; (6, 4) is water;
      // (5, 3) is a city cell.
      expect(state.monumentCrowns(const Cell(6, 3)), 1);
    });

    test('is nothing on a cell without one', () {
      final state = MatchState.start(twoHouses());
      expect(state.monumentCrowns(const Cell(3, 3)), 0);
      expect(state.monumentCrowns(const Cell(4, 3)), 0);
      accept(state, PlayCard(inHand(state, CardKind.farm), const Cell(4, 3)));
      expect(state.monumentCrowns(const Cell(4, 3)), 0);
    });
  });

  group('standings', () {
    test('rank by crowns', () {
      final state = MatchState.start(twoHouses());
      accept(state, const PlayCard(0, Cell(4, 3)));
      expect(state.crownsOf(0), greaterThan(state.crownsOf(1)));
      expect(state.standings, [0, 1]);
      expect(state.winner, isNull, reason: 'the match is still being played');
    });

    test('break a tie by the later turn in the final round', () {
      final state = MatchState.start(twoHouses());
      while (!state.isOver) {
        accept(state, const EndTurn());
      }
      expect(state.crownsOf(0), state.crownsOf(1));
      expect(state.cityCountOf(0), state.cityCountOf(1));
      // Round 20 of two houses starts with seat 1, so seat 0 plays later.
      expect(state.standings, [0, 1]);
      expect(state.winner, 0);
    });
  });
}
