import 'dart:ui';

/// The colours DomiVale itself is made of: the four houses and the crown.
///
/// The shared look lives elsewhere: terrain, cliffs, the offered-cell
/// highlight and the panel surfaces come from the engine's `EnginePalette`,
/// and the brand neutrals and fonts from `Brand`. What is here is only what
/// this game has and the other Vale games do not.
abstract final class GamePalette {
  // ── Houses ───────────────────────────────────────────────────────────────

  /// The house colours carry the board, so they are the palette's first job:
  /// four colours that stay apart at 12 px, on meadow, forest and hills, for
  /// colour-blind players too. None of them is a green, because the ground
  /// is. Their distance is tested in L*a*b*, against each other and against
  /// the terrain.
  ///
  /// Indexed by seat.
  static const List<Color> houses = [crimson, cobalt, amber, plum];

  /// The first seat: a warm red.
  static const crimson = Color(0xFFC94C4C);

  /// The second: a clear blue.
  static const cobalt = Color(0xFF4A78C2);

  /// The third: a golden yellow.
  static const amber = Color(0xFFE0B04A);

  /// The fourth: a violet.
  static const plum = Color(0xFF9A5BB5);

  /// How much of a house's colour washes over its territory. Soft, so the
  /// terrain still reads under it; the border carries the stronger line.
  static const double territoryWash = 0.30;

  /// How strong the line along a territory's border is.
  static const double borderStrength = 0.85;

  /// How much of a house's colour the land an armed card would claim is
  /// washed with, on top of the territory it joins.
  static const double claimPreviewWash = 0.35;

  /// The icon in the middle of a city cell. Not quite white, so it sits on
  /// its cell rather than glaring off it.
  static const cellIcon = Color(0xE6FFFFFF);

  /// The yield glyph on a plain cell, faint enough to read as texture.
  static const yieldIcon = Color(0x66FFFFFF);

  /// The number on a previewed cell: what a district there would yield, or
  /// what an army brings against the target.
  static const previewText = Color(0xFFFAF8F3);
  static const previewTextShadow = Color(0xCC1A1A1E);

  /// The same figure when the attack would not yet take the cell: strength
  /// still to come.
  static const previewWarn = Color(0xFFE8A33D);

  /// The ring on a district an attack would cut off from its heart. Loss,
  /// in a colour nothing else on the board wears.
  static const abandonedMark = Color(0xFFC0563F);

  /// The ring around a cell the player is reading.
  static const inspectRing = Color(0xFFFFD166);

  // ── Crowns ───────────────────────────────────────────────────────────────

  /// The primary accent: crowns, the score, the thing the game is about.
  static const crown = Color(0xFFE8C765);

  /// The lighter core of it, for the title.
  static const crownLt = Color(0xFFF5E3A0);
}
