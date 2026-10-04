import 'package:domivale_rules/domivale_rules.dart';
import 'package:test/test.dart';

/// A valley with a lake, a forest belt and a ridge, hand-drawn so the bots
/// have something to choose between. [size] 22, 27 or 32; hearts in the
/// corners, a triangle or opposite sides.
MatchHeader arena(
    {required int houses, required int seed, List<Banner>? banners}) {
  final size = Rules.boardSize(houses);
  final rows = <String>[];
  for (var y = 0; y < size; y++) {
    final row = StringBuffer();
    for (var x = 0; x < size; x++) {
      final mid = size ~/ 2;
      final dx = x - mid;
      final dy = y - mid;
      if (dx * dx + dy * dy <= 9) {
        row.write('~');
      } else if ((x + y) % 7 == 0 || (x * 3 + y) % 11 == 0) {
        row.write('f');
      } else if ((x - y).abs() <= 1 && x > size ~/ 4 && x < 3 * size ~/ 4) {
        row.write('h');
      } else {
        row.write('m');
      }
    }
    rows.add(row.toString());
  }
  final heights = [
    for (final row in rows)
      row.split('').map((c) => c == 'h' ? '2' : '0').join(),
  ];
  final board = Board.parse(rows, heightRows: heights);
  final hearts = switch (houses) {
    2 => [Cell(4, size ~/ 2), Cell(size - 5, size ~/ 2)],
    3 => [Cell(size ~/ 2, 4), Cell(4, size - 5), Cell(size - 5, size - 5)],
    _ => [
        const Cell(4, 4),
        Cell(size - 5, 4),
        Cell(4, size - 5),
        Cell(size - 5, size - 5),
      ],
  };
  final chosen = [
    Banner.builder,
    Banner.expander,
    Banner.warlord,
    Banner.builder
  ];
  return MatchHeader(
    board: board,
    seed: seed,
    houses: [
      for (var i = 0; i < houses; i++)
        HouseSetup(
          name: 'House $i',
          banner: (banners ?? chosen)[i],
          heart: hearts[i],
          chosenBasic: CardKind.lumberCamp,
          bannerBasic: (banners ?? chosen)[i] == Banner.expander
              ? CardKind.quarry
              : null,
        ),
    ],
  );
}

/// Plays a whole match of bots and returns the log.
List<Action> playOut(MatchHeader header, {int maxActions = 20000}) {
  final state = MatchState.start(header);
  final bots = [for (final h in header.houses) Bot.forBanner(h.banner)];
  final log = <Action>[];
  while (!state.isOver) {
    final action = bots[state.currentSeat].nextAction(state);
    final refusal = state.apply(action);
    if (refusal != null) {
      throw StateError('round ${state.round}, seat ${state.currentSeat}: '
          '$action refused: ${refusal.name}');
    }
    log.add(action);
    if (log.length > maxActions) throw StateError('the match never ends');
  }
  return log;
}

/// What a two-house bot match from seed 7 ends in. Pinned: see the test.
const int botMatchFingerprint = 844812767;

void main() {
  test('a match of bots plays from start to end without a refused action', () {
    for (var houses = 2; houses <= 4; houses++) {
      for (var seed = 1; seed <= 3; seed++) {
        final header = arena(houses: houses, seed: seed);
        final log = playOut(header);
        final state = MatchState.replay(header, log);
        expect(state.isOver, isTrue);
        expect(log.whereType<EndTurn>().length,
            lessThanOrEqualTo(Rules.rounds * houses));
        // The bots did something: land is claimed and crowns are scored.
        for (var seat = 0; seat < houses; seat++) {
          if (!state.isAlive(seat)) continue;
          expect(state.cellsOwnedBy(seat), greaterThan(37),
              reason: '$houses houses, seed $seed, seat $seat grew');
        }
        expect(state.openLandCount / state.board.landCount, lessThan(0.5),
            reason: 'most of the valley is claimed by the end');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 3)), testOn: 'vm');

  test('the same seed plays the same match, here and on any other platform',
      () {
    // One two-house match: light enough for a browser, where a long
    // synchronous match would stop the other suites from loading. The
    // fingerprint is pinned so the VM and Chrome have to agree on every
    // step of a whole match of bots.
    final one = playOut(arena(houses: 2, seed: 7));
    final two = playOut(arena(houses: 2, seed: 7));
    expect(one, two);
    final state = MatchState.replay(arena(houses: 2, seed: 7), one);
    expect(state.isOver, isTrue);
    expect(state.fingerprint(), botMatchFingerprint);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('a bot never plays a card the rules would refuse, step by step', () {
    final header = arena(houses: 3, seed: 2);
    final state = MatchState.start(header);
    final bot = Bot.forBanner(Banner.warlord);
    for (var step = 0; step < 400 && !state.isOver; step++) {
      final action = bot.nextAction(state);
      expect(state.apply(action), isNull, reason: 'step $step: $action');
    }
  });

  test('temperaments show in play: the Warlord fights, the Builder builds', () {
    var warlordMilitary = 0;
    var builderMilitary = 0;
    var warlordMonuments = 0;
    var builderMonuments = 0;
    for (var seed = 1; seed <= 4; seed++) {
      final header = arena(
        houses: 2,
        seed: seed,
        banners: const [Banner.warlord, Banner.builder],
      );
      final state = MatchState.start(header);
      final bots = [for (final h in header.houses) Bot.forBanner(h.banner)];
      while (!state.isOver) {
        final seat = state.currentSeat;
        final action = bots[seat].nextAction(state);
        if (action is PlayCard) {
          final kind = state.currentHouse.hand[action.handIndex];
          if (kind.isMilitary) {
            if (seat == 0) warlordMilitary++;
            if (seat == 1) builderMilitary++;
          }
          if (kind == CardKind.monument) {
            if (seat == 0) warlordMonuments++;
            if (seat == 1) builderMonuments++;
          }
        }
        expect(state.apply(action), isNull);
      }
    }
    expect(warlordMilitary, greaterThan(builderMilitary));
    expect(builderMonuments, greaterThanOrEqualTo(warlordMonuments));
  }, timeout: const Timeout(Duration(minutes: 2)), testOn: 'vm');

  test('a bot trades its way to a card it wants', () {
    // A house holding only stone and a cheap Farm to want: the bot trades
    // stone for grain and wood before buying.
    final header = arena(houses: 2, seed: 1);
    final state = MatchState.start(header);
    state.currentHouse.goods = const Goods(stone: 9);
    state.currentHouse.hand.clear();
    final bot = Bot.forBanner(Banner.builder);
    final first = bot.nextAction(state);
    expect(first, isA<Trade>());
    expect((first as Trade).give, Good.stone);
    expect(state.apply(first), isNull);
  });
}
