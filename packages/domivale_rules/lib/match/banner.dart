import '../cards/card_kind.dart';

/// The three ways a house plays. A bot's banner is its temperament; the
/// player picks one at setup. Each adds one card to the opening hand.
enum Banner {
  /// Values yield and crowns; opens with a Monument.
  builder(label: 'Builder', card: CardKind.monument),

  /// Values claimed land and new cities; opens with one more basic card of
  /// its choice, named in the house's setup.
  expander(label: 'Expander', card: null),

  /// Values captures and renown; opens with a Siege.
  warlord(label: 'Warlord', card: CardKind.siege);

  const Banner({required this.label, required this.card});

  final String label;

  /// The fixed banner card, or null for the Expander, whose card is chosen.
  final CardKind? card;
}
