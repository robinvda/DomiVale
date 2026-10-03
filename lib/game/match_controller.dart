import 'package:domivale_rules/domivale_rules.dart';
import 'package:flutter/foundation.dart';

/// Holds the match the player is in: its header and log, and the state the
/// log leads to.
///
/// Every change goes through the rules. The controller sends an action,
/// appends it to the log when the rules accept it, and tells its listeners.
/// Undo is forgetting the end of the log and replaying - no state is unwound
/// by hand, so what the player sees after an undo is exactly what the rules
/// say.
class MatchController extends ChangeNotifier {
  MatchController(this.match)
      : state = match.replay(),
        _turnStart = match.log.length;

  final Match match;

  /// The state the log leads to. Replaced on undo, so hold the controller
  /// rather than this.
  MatchState state;

  /// How long the log was when the current turn began. Nothing before it can
  /// be undone: a turn is committed when it ends.
  int _turnStart;

  /// Sends [action] to the rules. Null when it was done, or why it was not.
  Refusal? apply(Action action) {
    final refusal = state.apply(action);
    if (refusal != null) return refusal;
    match.append(action);
    if (action is EndTurn) _turnStart = match.log.length;
    notifyListeners();
    return null;
  }

  /// Whether anything in this turn can be taken back.
  bool get canUndo => match.log.length > _turnStart;

  /// Takes the last action of this turn back.
  bool undo() {
    if (!canUndo) return false;
    match.truncate(1);
    state = match.replay();
    notifyListeners();
    return true;
  }

  /// Ends the turn, after which nothing in it can be undone.
  bool endTurn() => apply(const EndTurn()) == null;
}
