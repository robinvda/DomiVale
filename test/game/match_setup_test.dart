import 'package:domivale/game/match_setup.dart';
import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a skirmish is a board for its houses with seats dealt by the seed', () {
    final setup = buildMatch(
      houses: const [
        HouseChoice(name: 'Hill House', banner: Banner.builder),
        HouseChoice(name: 'Lake House', banner: Banner.expander, isBot: true),
        HouseChoice(name: 'Wood House', banner: Banner.warlord, isBot: true),
      ],
      seed: 11,
    );
    final header = setup.header;
    expect(header.board.size, Rules.boardSize(3));
    // The bots take the seats their houses were dealt.
    expect(setup.botSeats, hasLength(2));
    for (final seat in setup.botSeats) {
      expect(header.houses[seat].name, isNot('Hill House'));
    }
    expect(header.houses, hasLength(3));
    expect(header.houses.map((h) => h.name).toSet(),
        {'Hill House', 'Lake House', 'Wood House'});
    for (final house in header.houses) {
      expect(house.chosenBasic.isBasic, isTrue);
      expect(house.chosenBasic, isNot(CardKind.farm),
          reason: 'the hand already has a Farm');
      if (house.banner == Banner.expander) {
        expect(house.bannerBasic, isNotNull);
        expect(house.bannerBasic, isNot(house.chosenBasic));
      }
    }
    // The rules take it as it is, and the first house has collected.
    final state = MatchState.start(header);
    expect(state.houses[0].hand, hasLength(3));
    expect(state.houses[0].goods, Rules.startingGoods + Rules.heartYield);

    final again = buildMatch(
      houses: const [
        HouseChoice(name: 'Hill House', banner: Banner.builder),
        HouseChoice(name: 'Lake House', banner: Banner.expander),
        HouseChoice(name: 'Wood House', banner: Banner.warlord),
      ],
      seed: 11,
    ).header;
    expect(again.houses.map((h) => h.name).toList(),
        header.houses.map((h) => h.name).toList());
  });
}
