import 'dart:math';

import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter/material.dart' hide Banner;
import 'package:vale_engine/theme/brand_theme.dart';
import 'package:vale_engine/ui/fade_page_route.dart';

import '../game/match_setup.dart';
import '../theme/game_palette.dart';
import 'game_screen.dart';
import 'hud/hud_widgets.dart';

/// Setting up a skirmish: how many houses, and each one's banner.
///
/// Every house is played by hand at this screen for now; the bots come
/// later and will take the seats the player does not.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _houses = 2;
  final List<Banner> _banners = [
    Banner.builder,
    Banner.warlord,
    Banner.expander,
    Banner.builder,
  ];

  /// Which houses a bot plays. The first is the player's by default; a
  /// house with nobody at the screen is a bot.
  final List<bool> _bots = [false, true, true, true];

  void _start() {
    final setup = buildMatch(
      houses: [
        for (var i = 0; i < _houses; i++)
          HouseChoice(
            name: houseNames[i],
            banner: _banners[i],
            isBot: _bots[i],
          ),
      ],
      seed: Random().nextInt(1 << 30),
    );
    Navigator.of(context).pushReplacement(
      FadePageRoute<void>(child: GameScreen(setup: setup)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PaperHeading(
                    title: 'A skirmish',
                    subtitle: 'You against the bots, or friends at one screen.',
                  ),
                  const SizedBox(height: 18),
                  const _SectionLabel('Houses'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (var n = Rules.minHouses; n <= Rules.maxHouses; n++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _Choice(
                            label: '$n',
                            selected: _houses == n,
                            onTap: () => setState(() => _houses = n),
                          ),
                        ),
                      const Spacer(),
                      Text(
                        '${Rules.boardSize(_houses)}×${Rules.boardSize(_houses)}',
                        style: const TextStyle(
                          fontFamily: 'NunitoSans',
                          fontSize: 12,
                          color: Brand.inkSoft,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (var i = 0; i < _houses; i++) ...[
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: GamePalette.houses[i],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _SectionLabel(houseNames[i]),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        for (final banner in Banner.values)
                          _Choice(
                            label: banner.label,
                            selected: _banners[i] == banner,
                            onTap: () => setState(() => _banners[i] = banner),
                          ),
                        _Choice(
                          label: _bots[i] ? 'Bot' : 'You',
                          selected: !_bots[i],
                          onTap: () => setState(() => _bots[i] = !_bots[i]),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Back',
                          style: TextStyle(
                            fontFamily: 'Nunito',
                            fontWeight: FontWeight.w700,
                            color: Brand.inkSoft,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Shrunk rather than overflowing on the narrowest
                      // phones.
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: HudButton(
                              label: 'Into the valley',
                              icon: Icons.play_arrow,
                              onTap: _start,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: Brand.ink,
        ),
      );
}

/// One of a row of choices, filled when chosen.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Brand.ink : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: Brand.ink, width: 2),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Nunito',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: selected ? Brand.paper : Brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}
