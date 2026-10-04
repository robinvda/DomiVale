import 'package:domivale/game/match_setup.dart';
import 'package:domivale/ui/game_screen.dart';
import 'package:domivale/ui/hand_bar.dart';
import 'package:domivale/ui/hud/status_panel.dart';
import 'package:domivale/ui/market_panel.dart';
import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter/material.dart' hide Banner;
import 'package:flutter_test/flutter_test.dart';

MatchHeader _header() => buildMatch(
      houses: const [
        HouseChoice(name: 'Hill House', banner: Banner.builder),
        HouseChoice(name: 'Lake House', banner: Banner.warlord),
      ],
      seed: 3,
    );

void main() {
  // The HUD is on screen from the first frame, and on that frame the board
  // has not been drawn: Flame runs `onLoad` after the host has built its
  // widget tree. Nothing the HUD reads may reach for what `onLoad` makes.
  testWidgets('the screen builds before the board is ready', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(header: _header())));
    expect(tester.takeException(), isNull);
    expect(find.byType(StatusPanel), findsOneWidget);
    expect(find.text('Take the turn'), findsOneWidget);
    expect(find.text('End turn'), findsOneWidget);
    // The opening hand is along the foot before there is a board to play
    // it on.
    expect(find.byType(HandCardView), findsNWidgets(3));
  });

  testWidgets('and survives the board becoming ready under it', (tester) async {
    await tester.pumpWidget(MaterialApp(home: GameScreen(header: _header())));
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull, reason: 'frame $frame');
    }
    await tester.tap(find.text('Take the turn'));
    await tester.pump();
    expect(find.text('Take the turn'), findsNothing);

    // A card is armed with a tap and disarmed with another.
    await tester.tap(find.byType(HandCardView).first);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(HandCardView).first);
    await tester.pump();
    expect(tester.takeException(), isNull);

    // The market opens over the board with the row of five and the piles;
    // buying from a pile puts a card in the hand.
    await tester.tap(find.text('Market'));
    await tester.pump();
    expect(find.byType(MarketPanel), findsOneWidget);
    expect(find.byType(RowSlot), findsNWidgets(5));
    await tester.tap(find.byType(PileChip).first);
    await tester.pump();
    expect(find.byType(HandCardView), findsNWidgets(4));
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.byType(MarketPanel), findsNothing);

    // Ending the turn hands over to the next house.
    await tester.tap(find.text('End turn'));
    await tester.pump();
    expect(find.text('Take the turn'), findsOneWidget);
  });
}
