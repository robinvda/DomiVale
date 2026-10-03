import 'package:domivale_rules/domivale_rules.dart';
import 'package:test/test.dart';

import '../support/two_houses.dart';

/// A scripted opening: both houses grow, buy and end a few turns.
const List<Action> script = [
  // Round 1: the Hill House, then the Lake House.
  BuyBasic(CardKind.farm),
  PlayCard(0, Cell(4, 3)),
  PlayCard(0, Cell(5, 3)),
  PlayCard(0, Cell(6, 3)),
  EndTurn(),
  PlayCard(0, Cell(9, 3)),
  PlayCard(0, Cell(10, 4)),
  BuyBasic(CardKind.quarry),
  EndTurn(),
  // Round 2 starts one seat later: the Lake House, then the Hill House.
  PlayCard(1, Cell(10, 5)),
  EndTurn(),
  PlayCard(0, Cell(3, 2)),
  EndTurn(),
  // Round 3: Hill, Lake.
  BuyBasic(CardKind.lumberCamp),
  PlayCard(0, Cell(3, 4)),
  EndTurn(),
  EndTurn(),
  // Round 4: Lake, and the Hill House is next.
  BuyBasic(CardKind.farm),
  PlayCard(1, Cell(10, 6)),
  EndTurn(),
];

/// What the script leads to. The same value must come out on the VM and in
/// a browser: this file runs under both.
const int scriptFingerprint = 526030203;

void main() {
  test('a match is its header plus its log', () {
    final match = Match(twoHouses());
    final live = MatchState.start(match.header);
    for (final action in script) {
      accept(live, action);
      match.append(action);
    }
    expect(match.log, script);
    expect(match.replay().fingerprint(), live.fingerprint());
  });

  test('replaying the log gives the same state everywhere', () {
    final state = MatchState.replay(twoHouses(), script);
    expect(state.round, 4);
    expect(state.currentSeat, 0);
    expect(state.fingerprint(), scriptFingerprint);
  });

  test('a log with a refused action is an error, not a state', () {
    expect(
      () => MatchState.replay(twoHouses(), const [PlayCard(0, Cell(9, 9))]),
      throwsStateError,
    );
  });

  test('undoing is forgetting the end of the log', () {
    final match = Match(twoHouses(), script);
    final before = match.replay().fingerprint();
    match.append(const BuyBasic(CardKind.farm));
    expect(match.replay().fingerprint(), isNot(before));
    match.truncate(1);
    expect(match.log, script);
    expect(match.replay().fingerprint(), before);
  });

  test('the fingerprint moves with every change of state', () {
    final state = MatchState.start(twoHouses());
    final seen = <int>{state.fingerprint()};
    for (final action in script) {
      accept(state, action);
      expect(seen.add(state.fingerprint()), isTrue, reason: '$action');
    }
  });
}
