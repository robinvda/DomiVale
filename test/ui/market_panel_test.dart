import 'package:domivale/ui/hand_bar.dart';
import 'package:domivale/ui/market_panel.dart';
import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter/material.dart' hide Banner;
import 'package:flutter_test/flutter_test.dart';

MatchState _state() => MatchState.start(MatchHeader(
      board: Board.filled(size: 16),
      seed: 1,
      deck: const [
        CardKind.siege,
        CardKind.monument,
        CardKind.barracks,
        CardKind.march,
        CardKind.march,
        CardKind.walls,
        CardKind.market,
        CardKind.settle,
      ],
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
    ));

void main() {
  testWidgets('shows the row, the piles and the trades, and reports taps',
      (tester) async {
    final state = _state();
    int? boughtSlot;
    CardKind? boughtBasic;
    (Good, Good)? traded;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarketPanel(
            state: state,
            onBuyRow: (slot) => boughtSlot = slot,
            onBuyBasic: (kind) => boughtBasic = kind,
            onTrade: (give, take) => traded = (give, take),
            onClose: () {},
          ),
        ),
      ),
    ));
    expect(find.byType(RowSlot), findsNWidgets(Rules.rowSize));
    expect(find.text('Settle'), findsOneWidget);
    expect(find.byType(PileChip), findsNWidgets(3));
    // Three goods, every ordered pair.
    expect(find.byType(TradeChip), findsNWidgets(6));
    expect(find.textContaining('3 for 1'), findsOneWidget);

    await tester.tap(find.text('Settle'));
    expect(boughtSlot, state.market.row.indexOf(CardKind.settle));
    await tester.tap(find.byType(PileChip).first);
    expect(boughtBasic, CardKind.farm);
    await tester.tap(find.byType(TradeChip).first);
    expect(traded, (Good.grain, Good.wood));
  });

  testWidgets('a bought slot is drawn as a gap', (tester) async {
    final state = _state();
    final slot = state.market.row.indexOf(CardKind.march);
    expect(state.apply(BuyFromRow(slot)), isNull);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: MarketPanel(
            state: state,
            onBuyRow: (_) {},
            onBuyBasic: (_) {},
            onTrade: (_, __) {},
            onClose: () {},
          ),
        ),
      ),
    ));
    expect(find.byType(RowSlot), findsNWidgets(Rules.rowSize));
    expect(find.text('March'), findsOneWidget,
        reason: 'one March was bought, one is still on the row');
  });
}
