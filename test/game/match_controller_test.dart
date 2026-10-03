import 'package:domivale/game/match_controller.dart';
import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter_test/flutter_test.dart';

MatchHeader _header() => MatchHeader(
      board: Board.filled(size: 16),
      seed: 1,
      houses: [
        HouseSetup(
          name: 'Hill House',
          banner: Banner.builder,
          heart: const Cell(3, 3),
          chosenBasic: CardKind.quarry,
        ),
        HouseSetup(
          name: 'Lake House',
          banner: Banner.warlord,
          heart: const Cell(10, 3),
          chosenBasic: CardKind.lumberCamp,
        ),
      ],
    );

void main() {
  test('an accepted action goes on the log and tells the listeners', () {
    final matches = MatchController(Match(_header()));
    var told = 0;
    matches.addListener(() => told++);
    expect(matches.apply(const PlayCard(0, Cell(4, 3))), isNull);
    expect(matches.match.log, [const PlayCard(0, Cell(4, 3))]);
    expect(told, 1);
    expect(matches.state.isCityCell(const Cell(4, 3)), isTrue);
  });

  test('a refused action changes nothing and goes nowhere', () {
    final matches = MatchController(Match(_header()));
    var told = 0;
    matches.addListener(() => told++);
    expect(matches.apply(const PlayCard(0, Cell(9, 9))), isNotNull);
    expect(matches.match.log, isEmpty);
    expect(told, 0);
  });

  test('undo forgets the last action and replays the rest', () {
    final matches = MatchController(Match(_header()));
    expect(matches.canUndo, isFalse);
    matches.apply(const BuyBasic(CardKind.farm));
    matches.apply(const PlayCard(0, Cell(4, 3)));
    final afterOne = MatchState.replay(_header(), const [
      BuyBasic(CardKind.farm),
    ]).fingerprint();
    expect(matches.canUndo, isTrue);
    expect(matches.undo(), isTrue);
    expect(matches.state.fingerprint(), afterOne);
    expect(matches.match.log, hasLength(1));
    expect(matches.undo(), isTrue);
    expect(matches.canUndo, isFalse);
    expect(matches.undo(), isFalse);
    expect(
        matches.state.fingerprint(), MatchState.start(_header()).fingerprint());
  });

  test('ending the turn commits it: nothing before it can be undone', () {
    final matches = MatchController(Match(_header()));
    matches.apply(const PlayCard(0, Cell(4, 3)));
    expect(matches.endTurn(), isTrue);
    expect(matches.canUndo, isFalse);
    expect(matches.state.currentSeat, 1);
    matches.apply(const PlayCard(0, Cell(9, 3)));
    expect(matches.canUndo, isTrue);
    matches.undo();
    expect(matches.state.currentSeat, 1);
    expect(matches.state.isCityCell(const Cell(4, 3)), isTrue);
  });
}
