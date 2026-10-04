import '../board/cell.dart';
import '../cards/card_kind.dart';
import 'goods.dart';

/// One thing the house whose turn it is asks the rules to do.
///
/// Actions are the whole vocabulary of a match: a match is its header plus an
/// ordered list of these, and the state is what applying them gives. They are
/// value-equal so a log can be compared and replayed.
sealed class Action {
  const Action();
}

/// Buy a card from one of the three basic piles into the hand.
class BuyBasic extends Action {
  const BuyBasic(this.kind);

  final CardKind kind;

  @override
  bool operator ==(Object other) => other is BuyBasic && kind == other.kind;

  @override
  int get hashCode => Object.hash(BuyBasic, kind);

  @override
  String toString() => 'BuyBasic(${kind.label})';
}

/// Buy the card in [slot] of the market row into the hand.
class BuyFromRow extends Action {
  const BuyFromRow(this.slot);

  final int slot;

  @override
  bool operator ==(Object other) => other is BuyFromRow && slot == other.slot;

  @override
  int get hashCode => Object.hash(BuyFromRow, slot);

  @override
  String toString() => 'BuyFromRow($slot)';
}

/// Trade some of [give] for one [take]: three for one at the bank, two for
/// one with a Market.
class Trade extends Action {
  const Trade({required this.give, required this.take});

  final Good give;
  final Good take;

  @override
  bool operator ==(Object other) =>
      other is Trade && give == other.give && take == other.take;

  @override
  int get hashCode => Object.hash(Trade, give, take);

  @override
  String toString() => 'Trade(${give.label} for ${take.label})';
}

/// Play the card at [handIndex] on [cell].
class PlayCard extends Action {
  const PlayCard(this.handIndex, this.cell);

  final int handIndex;
  final Cell cell;

  @override
  bool operator ==(Object other) =>
      other is PlayCard && handIndex == other.handIndex && cell == other.cell;

  @override
  int get hashCode => Object.hash(PlayCard, handIndex, cell);

  @override
  String toString() => 'PlayCard($handIndex, $cell)';
}

/// End the turn: the next house plays.
class EndTurn extends Action {
  const EndTurn();

  @override
  bool operator ==(Object other) => other is EndTurn;

  @override
  int get hashCode => (EndTurn).hashCode;

  @override
  String toString() => 'EndTurn()';
}

/// Why the rules would not do what an action asked. Each carries the line
/// the game shows for it.
enum Refusal {
  matchOver('The match is over.'),
  notABasicCard('Only Farms, Lumber camps and Quarries come from the piles.'),
  rowSlotEmpty('That card has already been taken this turn.'),
  noRowBuysLeft('Two cards from the row is all one turn can buy.'),
  sameGood('Trading a good for itself changes nothing.'),
  handFull('Your hand is full.'),
  cannotAfford('You cannot pay for that yet.'),
  noSuchCard('That card is not in your hand.'),
  noPlaysLeft('Three cards is all one turn can play.'),
  cellOutsideBoard('That is beyond the valley.'),
  notLand('Nothing can stand on water.'),
  cellNotYours('That land is not yours.'),
  cellIsCity('A city already stands there.'),
  notTouchingYourCity('A district has to touch one of your cities.'),
  tooCloseToACity('A new city needs open land, away from every city.'),
  notATarget('That is not a cell this card can take.');

  const Refusal(this.message);

  final String message;
}
