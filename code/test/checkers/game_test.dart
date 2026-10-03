// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The position of a game of checkers before anybody has moved.
const String openingPosition =
    'W:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12';

/// The position after red has played c3-d4, with black to move.
const String afterFirstMove =
    'B:W18,21,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12';

/// A game played from [position], with the draw rules switched off so that a
/// test only ever sees the result it is asking about.
Game gameAt(String position, {Rules rules = Rules.american}) =>
    Game.fromFen(position, rules: rules, drawRules: DrawRules.none);

Square square(String name) => Square.parse(name);

void main() {
  group('Game', () {
    test('starts from the opening position with red to move', () {
      final game = Game.standard();
      expect(game.fen, '$openingPosition W');
      expect(game.sideToMove, Side.red);
      expect(game.isRedToMove, isTrue);
      expect(game.ply, 0);
      expect(game.moveNumber, 1);
      expect(game.history, isEmpty);
      expect(game.lastMove, isNull);
      expect(game.canUndo, isFalse);
      expect(game.canRedo, isFalse);
      expect(game.outcome, GameOutcome.inProgress);
      expect(game.termination, isNull);
      expect(game.isGameOver, isFalse);
      expect(game.rules, Rules.american);
      expect(game.drawRules, DrawRules.american);
      expect(game.legalMoves(), hasLength(7));
    });

    test('plays a move and passes the turn', () {
      final game = Game.standard();
      final move = game.applyMoveFrom(square('c3'), square('d4'));
      expect(move.notation, 'c3-d4');
      expect(game.sideToMove, Side.black);
      expect(game.isRedToMove, isFalse);
      expect(game.board[square('c3')], isNull);
      expect(game.board[square('d4')], const Piece.redMan());
      expect(game.ply, 1);
      expect(game.moveNumber, 1);
      expect(game.lastMove, move);
      expect(game.history, [move]);
      expect(game.canUndo, isTrue);
      expect(game.canRedo, isFalse);
      expect(game.quietPlies, 1);
      expect(game.repetitionCount, 1);
      expect(game.fen, '$afterFirstMove B');
    });

    test('counts up the move number every other ply', () {
      final game = Game.standard();
      game
        ..applyMoveFrom(square('c3'), square('d4'))
        ..applyMoveFrom(square('b6'), square('c5'));
      expect(game.ply, 2);
      expect(game.moveNumber, 2);
      expect(game.sideToMove, Side.red);
    });

    test('takes the pieces a capture takes', () {
      final game = gameAt('W:W20,25:B15,22');
      final move = game.applyMoveFrom(square('b2'), square('f6'));
      expect(move.notation, 'b2xd4xf6');
      expect(game.capturedBy(Side.red), 2);
      expect(game.capturedBy(Side.black), 0);
      expect(game.piecesOf(Side.black), 0);
      expect(game.piecesOf(Side.red), 2);
      expect(game.board[square('c3')], isNull);
      expect(game.board[square('e5')], isNull);
      expect(game.board[square('f6')], const Piece.redMan());
      expect(game.quietPlies, 0);
      expect(game.outcome, GameOutcome.redWin);
    });

    test('refuses a quiet move when a capture has to be played', () {
      final game = gameAt('W:W20,25:B15,22');
      expect(game.hasLegalMoves, isTrue);
      expect(
        () => game.applyMoveFrom(square('h4'), square('g5')),
        throwsA(isA<IllegalMoveException>()),
      );
      expect(game.tryApplyMoveFrom(square('h4'), square('g5')), isFalse);
      expect(game.ply, 0);
      expect(game.board[square('h4')], const Piece.redMan());
      // The capture is there to be played, though.
      expect(game.tryApplyMoveFrom(square('b2'), square('f6')), isTrue);
      expect(game.ply, 1);
    });

    test('refuses moves that are not legal at all', () {
      final game = Game.standard();
      // A man may not move two squares.
      expect(
        () => game.applyMoveFrom(square('a3'), square('c5')),
        throwsA(isA<IllegalMoveException>()),
      );
      // Black's pieces may not move on red's turn.
      expect(
        () => game.applyMoveFrom(square('b8'), square('c7')),
        throwsA(isA<IllegalMoveException>()),
      );
      expect(game.findMove(square('b8'), square('c7')), isNull);
      expect(game.tryApplyMoveFrom(square('b8'), square('c7')), isFalse);
      expect(game.ply, 0);
      expect(game.outcome, GameOutcome.inProgress);
    });

    test('says no when asked to play an illegal move', () {
      final game = Game.standard();
      final illegal = Move(
        from: square('a3'),
        to: square('c5'),
        path: [square('a3'), square('c5')],
      );
      expect(game.tryApplyMove(illegal), isFalse);
      expect(game.ply, 0);
      expect(game.board[square('a3')], const Piece.redMan());

      final legal = game.findMove(square('a3'), square('b4'))!;
      expect(game.tryApplyMove(legal), isTrue);
      expect(
        game.tryApplyMove(legal),
        isFalse,
        reason: 'it is black to move now',
      );
    });

    test('takes a move back and plays it again', () {
      final game = Game.standard();
      final fen = game.fen;
      final move = game.applyMoveFrom(square('c3'), square('d4'));
      expect(game.undo()?.notation, 'c3-d4');
      expect(game.fen, fen);
      expect(game.sideToMove, Side.red);
      expect(game.ply, 0);
      expect(game.canUndo, isFalse);
      expect(game.canRedo, isTrue);

      expect(game.redo(), isTrue);
      expect(game.fen, '$afterFirstMove B');
      expect(game.lastMove, move);
      expect(game.canRedo, isFalse);
      expect(game.redo(), isFalse, reason: 'nothing left to play again');
    });

    test('has nothing to take back at the start of a game', () {
      final game = Game.standard();
      expect(game.undo(), isNull);
      expect(game.redo(), isFalse);
    });

    test('forgets a taken back move once a new one is played', () {
      final game = Game.standard();
      game
        ..applyMoveFrom(square('c3'), square('d4'))
        ..undo()
        ..applyMoveFrom(square('a3'), square('b4'));
      expect(game.canRedo, isFalse);
      expect(game.history.map((move) => move.notation), ['a3-b4']);
      expect(game.redo(), isFalse);
    });

    test('takes back a capture, putting the pieces back', () {
      final game = gameAt('W:W20,25:B15,22');
      final fen = game.fen;
      game.applyMoveFrom(square('b2'), square('f6'));
      expect(game.piecesOf(Side.black), 0);
      game.undo();
      expect(game.fen, fen);
      expect(game.piecesOf(Side.black), 2);
      expect(game.capturedBy(Side.red), 0);
      expect(game.quietPlies, 0);
      expect(game.outcome, GameOutcome.inProgress);
    });

    test('gives a history that cannot be written to', () {
      final game = Game.standard();
      game.applyMoveFrom(square('c3'), square('d4'));
      expect(() => game.history.add(game.lastMove!), throwsUnsupportedError);
    });

    test('crowns a man that reaches the far rank', () {
      final game = gameAt('W:W6:B32');
      expect(game.applyMoveFrom(square('c7'), square('b8')).promotes, isTrue);
      expect(game.board[square('b8')], const Piece.redKing());
      expect(game.fen, 'B:WK1:B32 B');
      expect(game.quietPlies, 0, reason: 'a promotion is not a quiet move');
    });

    test('writes itself out and reads itself back', () {
      final game = Game.standard();
      game
        ..applyMoveFrom(square('c3'), square('d4'))
        ..applyMoveFrom(square('b6'), square('c5'));
      final restored = Game.fromFen(game.fen);
      expect(restored.fen, game.fen);
      expect(restored.board, game.board);
      expect(restored.sideToMove, game.sideToMove);
      expect(
        restored.legalMoves().map((move) => move.notation),
        game.legalMoves().map((move) => move.notation),
      );
    });

    test('reads a position written by other tools', () {
      // A full FEN carries a move counter after the side to move, which is
      // more than this game needs.
      final game = Game.fromFen('$openingPosition W 12');
      expect(game.sideToMove, Side.red);
      expect(game.fen, '$openingPosition W');
      expect(game.legalMoves(), hasLength(7));

      // The position alone is enough; red is assumed to be to move.
      expect(Game.fromFen(openingPosition).sideToMove, Side.red);
      expect(
        Game.fromFen(openingPosition.replaceFirst('W:', 'B:')).sideToMove,
        Side.black,
      );
      expect(() => Game.fromFen('not a position'), throwsFormatException);
    });

    test('plays from a board it is given', () {
      final game = Game.position(
        Board.fromPosition('W:W32:B1'),
        sideToMove: Side.black,
      );
      expect(game.sideToMove, Side.black);
      expect(game.legalMoves().map((move) => move.notation), [
        'b8-a7',
        'b8-c7',
      ]);
    });

    test('copies itself without carrying the history along', () {
      final game = Game.standard();
      game.applyMoveFrom(square('c3'), square('d4'));
      final copy = game.copy();
      expect(copy.fen, game.fen);
      expect(copy.ply, 0);
      expect(copy.history, isEmpty);

      copy.applyMoveFrom(square('b6'), square('c5'));
      expect(copy.ply, 1);
      expect(game.ply, 1);
      expect(game.board, isNot(copy.board));
      expect(copy.rules, game.rules);
    });

    test('starts again when it is reset', () {
      final game = Game.standard();
      game
        ..applyMoveFrom(square('c3'), square('d4'))
        ..applyMoveFrom(square('b6'), square('c5'));
      game.reset();
      expect(game.fen, '$openingPosition W');
      expect(game.ply, 0);
      expect(game.outcome, GameOutcome.inProgress);
      expect(game.canUndo, isFalse);
      expect(game.canRedo, isFalse);
      expect(game.history, isEmpty);
      expect(game.quietPlies, 0);

      // A game that started from a position goes back to that position, not to
      // the opening one.
      final puzzle = gameAt('W:W6:B1,2');
      expect(puzzle.isGameOver, isTrue);
      puzzle.reset();
      expect(puzzle.fen, 'W:W6:B1,2 W');
      expect(puzzle.isGameOver, isTrue, reason: 'red is still shut in');
    });

    test('draws the board with the rank numbers and whose turn it is', () {
      final game = Game.standard();
      expect(game.render(), contains('Red to move'));
      expect(game.render(), contains('abcdefgh'));
      game.applyMoveFrom(square('c3'), square('d4'));
      expect(game.render(), contains('Black to move'));
    });

    test('gives up when a side resigns', () {
      final game = Game.standard();
      game.resign(Side.red);
      expect(game.outcome, GameOutcome.blackWin);
      expect(game.winner, Side.black);
      expect(game.termination, 'Resignation');
      expect(game.isGameOver, isTrue);
      expect(game.isDraw, isFalse);
      expect(
        () => game.applyMoveFrom(square('c3'), square('d4')),
        throwsStateError,
      );
      expect(
        () => game.resign(Side.black),
        throwsStateError,
        reason: 'the game is already over',
      );
    });

    test('wins by taking every piece of a side', () {
      final game = gameAt('W:W18:B22');
      expect(game.isGameOver, isFalse);
      game.applyMoveFrom(square('d4'), square('b2'));
      expect(game.piecesOf(Side.black), 0);
      expect(game.outcome, GameOutcome.redWin);
      expect(game.winner, Side.red);
      expect(game.termination, 'Black has no pieces left');
      expect(game.render(), contains('Red wins'));
    });

    test('wins by leaving the other side with no move', () {
      // c7 is shut in by black on b8 and d8.
      final game = gameAt('W:W6:B1,2');
      expect(game.hasLegalMoves, isFalse);
      expect(game.outcome, GameOutcome.blackWin);
      expect(game.winner, Side.black);
      expect(game.termination, 'No legal moves');
      expect(game.render(), contains('Black wins'));

      final reversed = gameAt('B:W23:B29');
      expect(reversed.outcome, GameOutcome.redWin);
      expect(reversed.termination, 'No legal moves');
    });

    test('calls a side with only kings the winner', () {
      final game = gameAt('W:W21,22:BK1');
      expect(game.outcome, GameOutcome.blackWin);
      expect(game.termination, 'Insufficient material');
      // With the rule turned off the game carries on instead.
      final played = gameAt(
        'W:W21,22:BK1',
        rules: const Rules(autoDeclareMaterialEnd: false),
      );
      expect(played.outcome, GameOutcome.inProgress);
      expect(played.legalMoves(), hasLength(3));
    });

    test('draws a game where both sides have only kings', () {
      final game = gameAt('W:WK29:BK5');
      expect(game.outcome, GameOutcome.draw);
      expect(game.winner, isNull);
      expect(game.isDraw, isTrue);
      expect(game.termination, 'Insufficient material');
      expect(game.render(), contains('Draw'));
    });

    test('draws a game where nobody has any pieces', () {
      final game = gameAt('W::');
      expect(game.outcome, GameOutcome.draw);
      expect(game.termination, 'No pieces left');
    });

    test('draws a game that repeats itself', () {
      final game = Game.fromFen(
        'W:WK29:BK5',
        rules: const Rules(autoDeclareMaterialEnd: false),
        drawRules: const DrawRules(repetitionLimit: 2),
      );
      expect(game.repetitionCount, 1);
      game
        ..applyMoveFrom(square('a1'), square('b2'))
        ..applyMoveFrom(square('a7'), square('b6'))
        ..applyMoveFrom(square('b2'), square('a1'))
        ..applyMoveFrom(square('b6'), square('a7'));
      expect(game.repetitionCount, 2);
      expect(game.outcome, GameOutcome.draw);
      expect(game.termination, 'Repetition');
      // The kings can still move, but the game has been drawn.
      expect(game.hasLegalMoves, isTrue);
      expect(game.isGameOver, isTrue);
      expect(game.tryApplyMove(game.legalMoves().first), isFalse);
    });

    test('draws a game that runs out of captures', () {
      final game = Game.fromFen(
        'W:WK29:BK5',
        rules: const Rules(autoDeclareMaterialEnd: false),
        drawRules: const DrawRules(repetitionLimit: 0, quietMoveLimit: 4),
      );
      game
        ..applyMoveFrom(square('a1'), square('b2'))
        ..applyMoveFrom(square('a7'), square('b6'))
        ..applyMoveFrom(square('b2'), square('a1'))
        ..applyMoveFrom(square('b6'), square('a7'));
      expect(game.quietPlies, 4);
      expect(game.outcome, GameOutcome.draw);
      expect(game.termination, 'No capture or promotion');
    });

    test('never calls a draw when the draw rules are off', () {
      final game = Game.fromFen(
        'W:WK29:BK5',
        rules: const Rules(autoDeclareMaterialEnd: false),
        drawRules: DrawRules.none,
      );
      game
        ..applyMoveFrom(square('a1'), square('b2'))
        ..applyMoveFrom(square('a7'), square('b6'))
        ..applyMoveFrom(square('b2'), square('a1'))
        ..applyMoveFrom(square('b6'), square('a7'));
      expect(game.repetitionCount, 2);
      expect(game.quietPlies, 4);
      expect(game.outcome, GameOutcome.inProgress);
    });

    test('cashes in a quiet-move counter on a capture', () {
      final game = gameAt('W:W18,25:B22');
      game.applyMoveFrom(square('d4'), square('c5'));
      expect(game.quietPlies, 1);
      // Black has to jump red's man on b2, which starts the count again.
      game.applyMoveFrom(square('c3'), square('a1'));
      expect(game.capturedBy(Side.black), 1);
      expect(game.quietPlies, 0);
    });

    test('says what a game is', () {
      final game = gameAt('W:W6:B1,2');
      expect(game.toString(), 'Game(${game.fen})');
      expect(GameOutcome.redWin.winner, Side.red);
      expect(GameOutcome.blackWin.winner, Side.black);
      expect(GameOutcome.draw.winner, isNull);
      expect(GameOutcome.inProgress.winner, isNull);
    });
  });
}
