import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter/material.dart';

import 'game_palette.dart';

/// What one kind of card looks like on the board and in the hand: its colour
/// and the icon in the middle of it.
///
/// Kept out of the rules package, which may not import Flutter: the card
/// table says what a card *is*, and this says what it looks like, indexed by
/// the same enum.
///
/// The look is plain, as LogiVale draws its buildings: one flat colour, one
/// darker outline, one pale icon. A city cell is around 32 px zoomed in and
/// 12 px at fit zoom on the largest board, where only the colour is left, so
/// no two district colours are close and none is a house colour.
class DistrictLook {
  const DistrictLook({required this.colour, required this.icon});

  final Color colour;
  final IconData icon;

  /// The line around the cell: the colour taken down. One rule, so a card in
  /// the hand and the district it places are outlined alike.
  Color get outline {
    final hsl = HSLColor.fromColor(colour);
    return hsl.withLightness((hsl.lightness - 0.22).clamp(0.0, 1.0)).toColor();
  }

  /// The look of [kind].
  static DistrictLook of(CardKind kind) => _looks[kind.index];

  /// A heart is drawn in its house's colour, so whose city it is reads from
  /// the cell itself.
  static DistrictLook heart(int seat) =>
      DistrictLook(colour: GamePalette.houses[seat], icon: heartIcon);

  static const IconData heartIcon = Icons.castle;

  /// The glyph for each good, drawn on the land that yields it.
  static IconData goodIcon(Good good) => switch (good) {
        Good.grain => Icons.grass,
        Good.wood => Icons.park,
        Good.stone => Icons.landscape,
      };

  /// Every icon the board atlas bakes, in slot order: one per card kind, then
  /// the heart, then one per good. [slotOf], [heartSlot] and [goodSlot]
  /// address them.
  static List<IconData> get icons => [
        for (final kind in CardKind.values) of(kind).icon,
        heartIcon,
        for (final good in Good.values) goodIcon(good),
      ];

  static int slotOf(CardKind kind) => kind.index;
  static int get heartSlot => CardKind.values.length;
  static int goodSlot(Good good) => CardKind.values.length + 1 + good.index;

  static const List<DistrictLook> _looks = [
    // Farm: straw, and a tractor.
    DistrictLook(colour: Color(0xFFB8A24A), icon: Icons.agriculture),
    // Lumber camp: cut timber.
    DistrictLook(colour: Color(0xFF8B6B47), icon: Icons.forest),
    // Quarry: worked stone.
    DistrictLook(colour: Color(0xFF8A8F96), icon: Icons.terrain),
    // Market: an awning.
    DistrictLook(colour: Color(0xFFC97A52), icon: Icons.storefront),
    // Walls: dark stone and a shield.
    DistrictLook(colour: Color(0xFF6E6A75), icon: Icons.shield),
    // Barracks: a banner.
    DistrictLook(colour: Color(0xFF7A4F4F), icon: Icons.flag),
    // Monument: pale marble and columns.
    DistrictLook(colour: Color(0xFFE8E0C8), icon: Icons.account_balance),
    // Settle: a new home. Not a district; the colour is for the card.
    DistrictLook(colour: Color(0xFF6FA8A0), icon: Icons.add_home),
    // March: soldiers on the road.
    DistrictLook(colour: Color(0xFF9C6B6B), icon: Icons.directions_walk),
    // Siege: fire at the gate.
    DistrictLook(colour: Color(0xFF6B4A4A), icon: Icons.whatshot),
  ];
}
