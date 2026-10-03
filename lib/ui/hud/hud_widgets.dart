import 'package:flutter/material.dart';
import 'package:vale_engine/theme/brand_theme.dart';

import '../../theme/game_palette.dart';

/// The chrome's colours: ink panels with the crown as the one accent.
abstract final class HudColours {
  static const panel = Brand.ink;
  static const tile = Color(0xFF3D4F3F);
  static const accent = GamePalette.crown;
  static const text = Brand.paper;
  static const softText = Color(0xFFA8B8A8);
}

/// A label: the smallest thing the HUD says in words. It names the figure
/// beside it and stops.
class HudLabel extends StatelessWidget {
  const HudLabel({super.key, required this.text, this.colour});

  final String text;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontFamily: 'Nunito',
        fontWeight: FontWeight.w700,
        fontSize: 11,
        letterSpacing: 0.44,
        color: colour ?? HudColours.softText,
      ),
    );
  }
}

/// One figure: a glyph and a number, with at most a quieter number after it.
class HudFigure extends StatelessWidget {
  const HudFigure({
    super.key,
    required this.icon,
    required this.value,
    this.of,
    this.iconColour,
    this.size = 15,
  });

  final IconData icon;
  final String value;

  /// What it is out of, drawn quieter and joined to it: `7/20`.
  final String? of;

  final Color? iconColour;
  final double size;

  @override
  Widget build(BuildContext context) {
    final rest = of;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size + 2, color: iconColour ?? HudColours.text),
        const SizedBox(width: 5),
        Text.rich(
          TextSpan(
            text: value,
            children: rest == null
                ? null
                : [
                    TextSpan(
                      text: '/$rest',
                      style: const TextStyle(color: HudColours.softText),
                    ),
                  ],
          ),
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w800,
            fontSize: size,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: HudColours.text,
          ),
        ),
      ],
    );
  }
}

/// The one press a moment is about: ending the turn, taking the next one.
class HudButton extends StatelessWidget {
  const HudButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.fontSize = 18,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HudColours.accent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: fontSize * 1.3,
            vertical: fontSize * 0.75,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Brand.ink, width: 2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: fontSize + 2, color: Brand.ink),
                SizedBox(width: fontSize * 0.55),
              ],
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Nunito',
                  fontWeight: FontWeight.w800,
                  fontSize: fontSize,
                  color: Brand.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pressable pill: the controls that are not the moment's one
/// press. It stays where it is and fades when it has nothing to do, because
/// a control that comes and goes is one the player has to look for.
class HudChip extends StatelessWidget {
  const HudChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.faded = false,
    this.colour,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool faded;

  /// A colour of its own, for a chip that is about one thing: a house, a
  /// card.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: faded ? 0.4 : 1.0,
      child: Material(
        color: colour ?? HudColours.panel,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 14, color: HudColours.text),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: HudColours.text,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A round button with a menu behind it: everything the player can reach
/// that is not about this turn.
class HudMenu extends StatelessWidget {
  const HudMenu({super.key, required this.items});

  final List<HudMenuItem> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<int>(
      tooltip: 'Menu',
      position: PopupMenuPosition.under,
      color: HudColours.panel,
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (index) => items[index].onTap(),
      itemBuilder: (context) => [
        for (var index = 0; index < items.length; index++)
          PopupMenuItem<int>(
            value: index,
            height: 42,
            child: Row(
              children: [
                Icon(items[index].icon, size: 16, color: HudColours.softText),
                const SizedBox(width: 8),
                Text(
                  items[index].label,
                  style: const TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: HudColours.text,
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: HudColours.panel,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.menu, size: 20, color: HudColours.text),
      ),
    );
  }
}

class HudMenuItem {
  const HudMenuItem({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// The paper a moment is printed on: the handover between turns and the
/// end of the match. It sits over the board rather than instead of it.
class PaperCard extends StatelessWidget {
  const PaperCard({super.key, required this.child, this.maxWidth = 440});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: const Color(0xFFDED5BD),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Brand.ink, width: 2),
          boxShadow: const [
            BoxShadow(color: Color(0x59141C16), offset: Offset(0, 14)),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// The heading of a [PaperCard].
class PaperHeading extends StatelessWidget {
  const PaperHeading({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w800,
            fontSize: 30,
            height: 1.1,
            letterSpacing: -0.6,
            color: Brand.ink,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: const TextStyle(
              fontFamily: 'NunitoSans',
              fontSize: 12,
              height: 1.4,
              color: Color(0xFF445A46),
            ),
          ),
        ],
      ],
    );
  }
}
