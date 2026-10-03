/// A complete engine for the classic game of checkers.
///
/// The engine is pure Dart with no dependency on Flutter, so it runs anywhere
/// and can be tested on its own. Start with [Game], which holds a position and
/// makes the rules for you:
///
/// ```dart
/// final game = Game.standard();
/// game.applyMoveFrom(Square.parse('c3'), Square.parse('d4'));
/// print(game.render());
///
/// // Where can the piece on c3 go?
/// print(game.legalMovesFrom(Square.parse('c3')));
///
/// // Play it back.
/// game.undo();
/// game.redo();
/// ```
///
/// Positions and moves can be written down and read back:
///
/// ```dart
/// final game = Game.fromFen('W:W20,25:B15,22 W');
/// game.applyMove(game.parseMove('b2xf6')); // b2xd4xf6
/// print(game.fen); // 'B:W20,25,26:B22 W'
/// ```
///
/// And [CheckersAI] will play against you, deterministically.
library;

export 'ai.dart' show CheckersAI, SearchResult;
export 'board.dart' show Board;
export 'game.dart' show Game, GameOutcome;
export 'move.dart' show IllegalMoveException, Move;
export 'move_generator.dart' show MoveGenerator;
export 'notation.dart' show MoveNotation, Notation, ParsedNotation;
export 'piece.dart' show Piece, PieceKind, Side;
export 'rules.dart' show DrawRules, RuleVariant, Rules;
export 'square.dart' show Square;
