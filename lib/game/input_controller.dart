import 'package:domivale_rules/domivale_rules.dart';

import 'match_controller.dart';

/// What the player can do with a turn on the board: arm a card, tap a cell,
/// take it back.
///
/// **Armed then tap, with no confirm step.** A tap on an offered cell plays
/// the card at once, because a confirm step on every play is two taps for
/// the whole game and a turn is made of three of them. Undo is what makes the
/// missing confirm fair: nothing is revealed until the turn ends.
class InputController {
  InputController(this.matches);

  final MatchController matches;

  MatchState get state => matches.state;

  /// The position in the current hand of the card a tap would play, or null
  /// when nothing is armed.
  int? get armedIndex => _armedIndex;
  int? _armedIndex;

  /// What that card is.
  CardKind? get armedKind {
    final index = _armedIndex;
    if (index == null) return null;
    final hand = state.currentHouse.hand;
    return index < hand.length ? hand[index] : null;
  }

  /// Arms the card at [index] in the hand, or disarms with null. Arming the
  /// armed card again disarms it.
  void arm(int? index) {
    if (index != null && index >= state.currentHouse.hand.length) return;
    _armedIndex = index == _armedIndex ? null : index;
    _offered = null;
  }

  void disarm() {
    _armedIndex = null;
    _offered = null;
  }

  /// Cells the armed card may go on, or empty when nothing is armed. Kept
  /// between changes: it is a walk over the whole board.
  List<Cell> get offeredCells {
    final kind = armedKind;
    if (kind == null) return const [];
    return _offered ??= state.offeredCells(kind).toList();
  }

  List<Cell>? _offered;

  /// Plays the armed card on [cell]. Null when it was played, or why not.
  /// Nothing is armed afterwards: the next tap is a fresh decision out of a
  /// hand that is one card lighter.
  Refusal? playAt(Cell cell) {
    final index = _armedIndex;
    if (index == null) return Refusal.noSuchCard;
    final refusal = matches.apply(PlayCard(index, cell));
    if (refusal == null) disarm();
    return refusal;
  }

  /// The match changed under the controller - a play, a buy, an undo or a
  /// new turn - so the offered cells are asked again and a card that is no
  /// longer in the hand is no longer armed.
  void matchChanged() {
    _offered = null;
    final index = _armedIndex;
    if (index != null && index >= state.currentHouse.hand.length) {
      _armedIndex = null;
    }
  }
}
