/// The rules of DomiVale as pure Dart: the board, a match as header plus log,
/// the actions a house can take, the cards, and the scoring.
///
/// Imports nothing from Flutter, Flame or the engine, so the same code runs
/// in the game, in the bots, in tests and on a server.
library;

export 'board/board.dart';
export 'board/cell.dart';
export 'board/terrain_kind.dart';
export 'cards/card_kind.dart';
export 'cards/prng.dart';
export 'match/action.dart';
export 'match/banner.dart';
export 'match/city.dart';
export 'match/goods.dart';
export 'match/house.dart';
export 'match/house_setup.dart';
export 'match/match.dart';
export 'match/match_state.dart';
export 'match/scoring.dart';
export 'rules.dart';
