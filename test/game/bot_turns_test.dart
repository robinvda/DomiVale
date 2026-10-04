import 'package:domivale/game/match_controller.dart';
import 'package:domivale/game/match_setup.dart';
import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bots play their turns through the controller until a person is up', () {
    final setup = buildMatch(
      houses: const [
        HouseChoice(name: 'Hill House', banner: Banner.builder),
        HouseChoice(name: 'Lake House', banner: Banner.warlord, isBot: true),
        HouseChoice(name: 'Wood House', banner: Banner.expander, isBot: true),
      ],
      seed: 5,
    );
    final matches =
        MatchController(Match(setup.header), botSeats: setup.botSeats);
    var told = 0;
    matches.addListener(() => told++);
    final human = setup.header.houses.indexWhere((h) => h.name == 'Hill House');

    matches.playBotTurns();
    expect(matches.state.currentSeat, human);
    expect(matches.isBotTurn, isFalse);
    // Round 1 starts with seat 0, so the bots seated before the person have
    // played, each telling the listeners once at the end of its turn.
    final before = matches.match.log.length;
    expect(told, human);
    expect(matches.match.log.whereType<EndTurn>().length, human);

    // The person ends their turn; the bots play until the person is up
    // again, and nothing of theirs can be undone.
    matches.endTurn();
    matches.playBotTurns();
    expect(matches.state.currentSeat, human);
    expect(matches.match.log.length, greaterThan(before + 1));
    expect(matches.canUndo, isFalse);
  });

  test('a skirmish against three bots plays from start to end', () {
    final setup = buildMatch(
      houses: const [
        HouseChoice(name: 'Hill House', banner: Banner.builder),
        HouseChoice(name: 'Lake House', banner: Banner.warlord, isBot: true),
        HouseChoice(name: 'Wood House', banner: Banner.expander, isBot: true),
        HouseChoice(name: 'Stone House', banner: Banner.builder, isBot: true),
      ],
      seed: 9,
    );
    final matches =
        MatchController(Match(setup.header), botSeats: setup.botSeats);
    // The person only ever ends the turn.
    var turns = 0;
    while (!matches.state.isOver) {
      matches.playBotTurns();
      if (matches.state.isOver) break;
      expect(matches.endTurn(), isTrue);
      if (++turns > Rules.rounds) break;
    }
    expect(matches.state.isOver, isTrue);
    expect(matches.state.winner, isNotNull);
    // Replaying the log gives the same state.
    expect(matches.match.replay().fingerprint(), matches.state.fingerprint());
  }, timeout: const Timeout(Duration(minutes: 3)));
}
