import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter/material.dart';

import '../../theme/game_palette.dart';
import 'hud_widgets.dart';

/// The permanent panel: whose turn it is, the round, the house's goods and
/// crowns, and the plays left this turn as three slots.
///
/// It never moves and never loses a term, so a glance finds the same figure
/// in the same place every turn.
class StatusPanel extends StatelessWidget {
  const StatusPanel({super.key, required this.state});

  final MatchState state;

  @override
  Widget build(BuildContext context) {
    final house = state.currentHouse;
    final colour = GamePalette.houses[house.seat];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        color: HudColours.panel,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration:
                    BoxDecoration(color: colour, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  house.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: HudColours.text,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              HudFigure(
                icon: Icons.flag_circle,
                value: '${state.round}',
                of: '${Rules.rounds}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              GoodFigure(good: Good.grain, value: house.goods.grain),
              GoodFigure(good: Good.wood, value: house.goods.wood),
              GoodFigure(good: Good.stone, value: house.goods.stone),
              Container(width: 2, height: 14, color: HudColours.tile),
              HudFigure(
                icon: Icons.workspace_premium,
                value: '${state.crownsOf(house.seat)}',
                iconColour: GamePalette.crown,
              ),
              Container(width: 2, height: 14, color: HudColours.tile),
              PlaySlots(left: state.playsLeft),
            ],
          ),
        ],
      ),
    );
  }
}

/// A good and how much of it the house holds.
class GoodFigure extends StatelessWidget {
  const GoodFigure({super.key, required this.good, required this.value});

  final Good good;
  final int value;

  static IconData iconOf(Good good) => switch (good) {
        Good.grain => Icons.grass,
        Good.wood => Icons.park,
        Good.stone => Icons.landscape,
      };

  static Color colourOf(Good good) => switch (good) {
        Good.grain => const Color(0xFFE0C36B),
        Good.wood => const Color(0xFF9CC47A),
        Good.stone => const Color(0xFFB9BCC2),
      };

  @override
  Widget build(BuildContext context) => HudFigure(
        icon: iconOf(good),
        value: '$value',
        iconColour: colourOf(good),
      );
}

/// The plays left this turn, as three slots: filled for a play still to
/// make, hollow for one spent.
class PlaySlots extends StatelessWidget {
  const PlaySlots({super.key, required this.left});

  final int left;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var slot = 0; slot < Rules.playsPerTurn; slot++)
          Padding(
            padding: EdgeInsets.only(left: slot == 0 ? 0 : 4),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: slot < left ? HudColours.accent : HudColours.tile,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
      ],
    );
  }
}
