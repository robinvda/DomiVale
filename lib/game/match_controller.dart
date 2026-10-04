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
  MatchController(this.match, {this.botSeats = const {}})
      : state = match.replay(),
        _turnStart = match.log.length;

  final Match match;

  /// The seats played by bots. Every other seat is a person at the screen.
  final Set<int> botSeats;

  /// Whether the house whose turn it is is a bot.
  bool get isBotTurn => !state.isOver && botSeats.contains(state.currentSeat);

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

  /// Plays the current bot's whole turn, one action at a time through the
  /// rules, and ends it. Answers how many actions it took, or 0 when it is
  /// not a bot's turn.
  ///
  /// Listeners are told once at the end rather than per action: a bot turn
  /// is one move to the player, and the recap is what shows it in steps.
  int playBotTurn() {
    if (!isBotTurn) return 0;
    final bot = Bot.forBanner(state.currentHouse.setup.banner);
    var count = 0;
    while (true) {
      final action = bot.nextAction(state);
      final refusal = state.apply(action);
      if (refusal != null) {
        throw StateError('the bot asked for $action and was refused: '
            '${refusal.name}');
      }
      match.append(action);
      count++;
      if (action is EndTurn || state.isOver) break;
    }
    _turnStart = match.log.length;
    notifyListeners();
    return count;
  }

  /// Plays every bot turn until a person is to play or the match is over.
  void playBotTurns() {
    while (isBotTurn) {
      playBotTurn();
    }
  }
}
