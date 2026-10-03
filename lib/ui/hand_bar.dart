import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter/material.dart';
import 'package:vale_engine/theme/brand_theme.dart';

import '../theme/district_look.dart';
import '../theme/game_palette.dart';
import 'hud/status_panel.dart';

/// The hand along the foot of the screen, and the three basic piles beside
/// it.
///
/// Tapping a card arms it; the armed card is lifted and ringed. A pile shows
/// what a basic card costs this house right now, and buying one puts it in
/// the hand.
class HandBar extends StatelessWidget {
  const HandBar({
    super.key,
    required this.state,
    required this.armedIndex,
    required this.onArm,
    required this.onBuy,
  });

  final MatchState state;
  final int? armedIndex;
  final void Function(int index) onArm;
  final void Function(CardKind kind) onBuy;

  @override
  Widget build(BuildContext context) {
    final house = state.currentHouse;
    final price = state.basicPriceFor(house.seat);
    final full = house.hand.length >= Rules.handCap;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final kind in CardKind.basics)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: PileChip(
                    kind: kind,
                    price: price,
                    faded: full || !house.goods.covers(price),
                    onTap: () => onBuy(kind),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: HandCardView.height + HandCardView.lift,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < house.hand.length; index++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: 8,
                      bottom: index == armedIndex ? HandCardView.lift : 0,
                    ),
                    child: HandCardView(
                      kind: house.hand[index],
                      armed: index == armedIndex,
                      faded: state.playsLeft == 0,
                      onTap: () => onArm(index),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One card in the hand: its tile, its name and its one line.
class HandCardView extends StatelessWidget {
  const HandCardView({
    super.key,
    required this.kind,
    required this.onTap,
    this.armed = false,
    this.faded = false,
  });

  final CardKind kind;
  final VoidCallback onTap;
  final bool armed;
  final bool faded;

  static const double width = 92;
  static const double height = 112;
  static const double lift = 14;

  @override
  Widget build(BuildContext context) {
    final look = DistrictLook.of(kind);
    final card = Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Brand.cream,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Brand.ink, width: 2.5),
        boxShadow: armed
            ? const [
                BoxShadow(
                  color: GamePalette.inspectRing,
                  spreadRadius: 3,
                  blurRadius: 0,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: CardTile(look: look, size: 40)),
          const Spacer(),
          Text(
            kind.label,
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
            cardLine(kind),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'NunitoSans',
              fontSize: 9,
              height: 1.2,
              color: Brand.inkSoft,
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(opacity: faded && !armed ? 0.5 : 1.0, child: card),
    );
  }

  /// The one line a card says about itself, in the words a player would use.
  static String cardLine(CardKind kind) => switch (kind) {
        CardKind.farm => '+1 grain per meadow beside it',
        CardKind.lumberCamp => '+1 wood per forest beside it',
        CardKind.quarry => '+1 stone per hills beside it',
        CardKind.market => '+1 crown; trade 2 for 1',
        CardKind.walls => '+2 defence within reach 1',
        CardKind.barracks => '+1 strength within reach 3',
        CardKind.monument => '+1 crown per open cell beside it',
        CardKind.settle => 'Found a city on open land',
        CardKind.march => 'Strength ${kind.strength}; not on cities',
        CardKind.siege => 'Strength ${kind.strength}; any target',
      };
}

/// A card's tile in miniature: its colour, its outline and its icon.
class CardTile extends StatelessWidget {
  const CardTile({super.key, required this.look, this.size = 40});

  final DistrictLook look;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: look.colour,
        borderRadius: BorderRadius.circular(size * 0.26),
        border: Border.all(color: look.outline, width: size * 0.07),
      ),
      child: Icon(look.icon, size: size * 0.56, color: Brand.paper),
    );
  }
}

/// One basic pile: the card and what it costs this house now.
class PileChip extends StatelessWidget {
  const PileChip({
    super.key,
    required this.kind,
    required this.price,
    required this.onTap,
    this.faded = false,
  });

  final CardKind kind;
  final Goods price;
  final VoidCallback onTap;

  /// Drawn as not affordable or not fitting in the hand. Still pressable,
  /// so a tap says why rather than doing nothing.
  final bool faded;

  @override
  Widget build(BuildContext context) {
    final look = DistrictLook.of(kind);
    return Opacity(
      opacity: faded ? 0.5 : 1.0,
      child: Material(
        color: Brand.ink,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CardTile(look: look, size: 22),
                const SizedBox(width: 7),
                for (final good in Good.values)
                  if (price.of(good) > 0) ...[
                    Icon(
                      GoodFigure.iconOf(good),
                      size: 13,
                      color: GoodFigure.colourOf(good),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${price.of(good)}',
                      style: const TextStyle(
                        fontFamily: 'Nunito',
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: Brand.paper,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
