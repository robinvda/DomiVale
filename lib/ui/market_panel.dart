import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter/material.dart';
import 'package:vale_engine/theme/brand_theme.dart';

import '../theme/district_look.dart';
import 'hand_bar.dart';
import 'hud/hud_widgets.dart';
import 'hud/status_panel.dart';

/// The market: the row of five, the three basic piles, and the bank.
///
/// Opened from the hand bar and laid over the board. Every price shown is
/// the price this house pays right now, so a card the house cannot afford is
/// faded but still pressable: a tap says why.
class MarketPanel extends StatelessWidget {
  const MarketPanel({
    super.key,
    required this.state,
    required this.onBuyRow,
    required this.onBuyBasic,
    required this.onTrade,
    required this.onClose,
  });

  final MatchState state;
  final void Function(int slot) onBuyRow;
  final void Function(CardKind kind) onBuyBasic;
  final void Function(Good give, Good take) onTrade;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final house = state.currentHouse;
    final full = house.hand.length >= Rules.handCap;
    final basicPrice = state.basicPriceFor(house.seat);
    final rate = state.tradeRateFor(house.seat);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: HudColours.panel,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'The market',
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: HudColours.text,
                  ),
                ),
              ),
              RowBuySlots(left: state.rowBuysLeft),
              const SizedBox(width: 10),
              IconButton(
                onPressed: onClose,
                icon: const Icon(Icons.close, color: HudColours.text),
                tooltip: 'Close',
              ),
            ],
          ),
          const SizedBox(height: 4),
          const HudLabel(text: 'The row · two a turn'),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var slot = 0; slot < Rules.rowSize; slot++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: RowSlot(
                      kind: state.market.at(slot),
                      price: state.market.at(slot) == null
                          ? null
                          : state.priceOf(state.market.at(slot)!, house.seat),
                      faded: state.market.at(slot) == null ||
                          full ||
                          state.rowBuysLeft == 0 ||
                          !house.goods.covers(state.priceOf(
                              state.market.at(slot)!, house.seat)),
                      onTap: () => onBuyRow(slot),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const HudLabel(text: 'The piles · always'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final kind in CardKind.basics)
                PileChip(
                  kind: kind,
                  price: basicPrice,
                  faded: full || !house.goods.covers(basicPrice),
                  onTap: () => onBuyBasic(kind),
                ),
            ],
          ),
          const SizedBox(height: 12),
          HudLabel(
            text: rate == Rules.marketTrade
                ? 'Trade · $rate for 1, your Market\'s rate'
                : 'Trade · $rate for 1 with the bank',
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final give in Good.values)
                for (final take in Good.values)
                  if (give != take)
                    TradeChip(
                      give: give,
                      take: take,
                      rate: rate,
                      faded: house.goods.of(give) < rate,
                      onTap: () => onTrade(give, take),
                    ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The row buys left this turn, as two slots.
class RowBuySlots extends StatelessWidget {
  const RowBuySlots({super.key, required this.left});

  final int left;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.storefront, size: 14, color: HudColours.softText),
        const SizedBox(width: 5),
        for (var slot = 0; slot < Rules.rowBuysPerTurn; slot++)
          Padding(
            padding: EdgeInsets.only(left: slot == 0 ? 0 : 4),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: slot < left ? HudColours.accent : HudColours.tile,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

/// One slot of the row: a card with its price, or the gap a bought card
/// left until the turn ends.
class RowSlot extends StatelessWidget {
  const RowSlot({
    super.key,
    required this.kind,
    required this.price,
    required this.onTap,
    this.faded = false,
  });

  final CardKind? kind;
  final Goods? price;
  final VoidCallback onTap;
  final bool faded;

  static const double width = 92;
  static const double height = 124;

  @override
  Widget build(BuildContext context) {
    final card = kind;
    if (card == null) {
      return SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _GapPainter()),
      );
    }
    final look = DistrictLook.of(card);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: faded ? 0.5 : 1.0,
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Brand.cream,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Brand.ink, width: 2.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: CardTile(look: look, size: 36)),
              const SizedBox(height: 6),
              Text(
                card.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  color: Brand.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                HandCardView.cardLine(card),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'NunitoSans',
                  fontSize: 8.5,
                  height: 1.2,
                  color: Brand.inkSoft,
                ),
              ),
              const Spacer(),
              // Shrunk rather than overflowing: a three-good price is wider
              // than the card.
              if (price != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: PriceLine(price: price!, dark: true),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A price as the goods it is made of.
class PriceLine extends StatelessWidget {
  const PriceLine({super.key, required this.price, this.dark = false});

  final Goods price;

  /// On cream rather than on ink.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final good in Good.values)
          if (price.of(good) > 0) ...[
            Icon(GoodFigure.iconOf(good),
                size: 12, color: GoodFigure.colourOf(good)),
            const SizedBox(width: 1),
            Text(
              '${price.of(good)}',
              style: TextStyle(
                fontFamily: 'Nunito',
                fontWeight: FontWeight.w800,
                fontSize: 11,
                color: dark ? Brand.ink : Brand.paper,
              ),
            ),
            const SizedBox(width: 5),
          ],
      ],
    );
  }
}

/// One trade: give [rate] of one good for one of another.
class TradeChip extends StatelessWidget {
  const TradeChip({
    super.key,
    required this.give,
    required this.take,
    required this.rate,
    required this.onTap,
    this.faded = false,
  });

  final Good give;
  final Good take;
  final int rate;
  final VoidCallback onTap;
  final bool faded;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: faded ? 0.5 : 1.0,
      child: Material(
        color: HudColours.tile,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$rate',
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Brand.paper,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(GoodFigure.iconOf(give),
                    size: 13, color: GoodFigure.colourOf(give)),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward,
                    size: 11, color: HudColours.softText),
                const SizedBox(width: 4),
                Icon(GoodFigure.iconOf(take),
                    size: 13, color: GoodFigure.colourOf(take)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dashed outline of a slot whose card was bought this turn.
class _GapPainter extends CustomPainter {
  final Paint _dash = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..color = Brand.paper.withValues(alpha: 0.35);

  @override
  void paint(Canvas canvas, Size size) {
    final outline = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(14),
    );
    final path = Path()..addRRect(outline);
    for (final metric in path.computeMetrics()) {
      var at = 0.0;
      while (at < metric.length) {
        final end = (at + 7).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(at, end), _dash);
        at = end + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_GapPainter old) => false;
}
