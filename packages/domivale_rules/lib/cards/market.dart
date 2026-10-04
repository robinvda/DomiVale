import '../rules.dart';
import 'card_kind.dart';
import 'prng.dart';

/// The shared market: a face-up row dealt from a shuffled deck, and the
/// discard pile the deck is rebuilt from when it runs out.
///
/// The basic piles are not here: Farms, Lumber camps and Quarries are always
/// available without limit, and buying one never touches the deck. Only
/// market cards pass through the row, so recycling the discard pile keeps
/// the deck's mix over a long match.
///
/// Every shuffle comes from one [Prng] seeded by the match, so the same seed
/// deals the same row on every platform. The row refills at the end of a
/// turn, not when a card is bought, which is what keeps undo free: nothing
/// new is revealed until the turn is committed.
class Market {
  /// A market dealt from [deck], in the order given, with [prng] carried on
  /// for every later shuffle.
  Market.deal(List<CardKind> deck, this._prng)
      : _deck = [...deck],
        _row = List<CardKind?>.filled(Rules.rowSize, null) {
    refill();
  }

  /// The base deck shuffled from [seed] and dealt.
  factory Market.start(int seed) {
    final prng = Prng(seed);
    final deck = baseDeck();
    prng.shuffle(deck);
    return Market.deal(deck, prng);
  }

  /// One copy of each card for each count in [Rules.deckMix], in card order.
  static List<CardKind> baseDeck() => [
        for (final entry in Rules.deckMix.entries)
          for (var copy = 0; copy < entry.value; copy++) entry.key,
      ];

  final Prng _prng;

  /// Cards still to be dealt, the next one last.
  final List<CardKind> _deck;

  /// The face-up row: [Rules.rowSize] slots, empty where a card was bought
  /// this turn.
  final List<CardKind?> _row;

  /// Played market cards, waiting to be shuffled into a new deck.
  final List<CardKind> _discard = [];

  List<CardKind?> get row => List.unmodifiable(_row);
  int get deckSize => _deck.length;
  int get discardSize => _discard.length;
  List<CardKind> get discardPile => List.unmodifiable(_discard);

  /// The card in [slot], or null for an empty slot or one that is not on the
  /// row.
  CardKind? at(int slot) => slot >= 0 && slot < _row.length ? _row[slot] : null;

  /// Takes the card in [slot] off the row, leaving the slot empty until the
  /// turn ends. The slot must hold a card.
  CardKind take(int slot) {
    final card = _row[slot]!;
    _row[slot] = null;
    return card;
  }

  /// Puts a played market card on the discard pile.
  void discard(CardKind kind) => _discard.add(kind);

  /// Fills every empty slot from the deck. When the deck runs out, the
  /// discard pile is shuffled into a new deck and dealing goes on; a slot
  /// stays empty only when there is nothing left anywhere.
  void refill() {
    for (var slot = 0; slot < _row.length; slot++) {
      if (_row[slot] != null) continue;
      if (_deck.isEmpty) _recycle();
      if (_deck.isEmpty) return;
      _row[slot] = _deck.removeLast();
    }
  }

  void _recycle() {
    if (_discard.isEmpty) return;
    _deck.addAll(_discard);
    _discard.clear();
    _prng.shuffle(_deck);
  }

  /// Folds the market into a fingerprint, through [fold].
  void fingerprint(void Function(int value) fold) {
    fold(_deck.length);
    for (final card in _deck) {
      fold(card.index);
    }
    for (final card in _row) {
      fold(card == null ? -1 : card.index);
    }
    fold(_discard.length);
    for (final card in _discard) {
      fold(card.index);
    }
  }
}
