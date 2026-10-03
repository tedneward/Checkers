// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:flutter_test/flutter_test.dart';

Game gameAt(String position) =>
    Game.fromFen(position, drawRules: DrawRules.none);

void main() {
  group('CheckersAI', () {
    test('opens the game by pushing a man forward', () {
      final game = Game.standard();
      final result = CheckersAI(game).findBestMove(depth: 4);
      expect(result.move, isNotNull);
      expect(result.move!.notation, 'a3-b4');
      expect(game.legalMoves(), contains(result.move));
      expect(result.depthReached, 4);
      expect(result.nodes, greaterThan(0));
      expect(result.elapsed, greaterThan(Duration.zero));
      expect(result.toString(), contains('a3-b4'));
    });

    test('plays the same move every time', () {
      final first = CheckersAI(Game.standard()).findBestMove(depth: 4);
      final second = CheckersAI(Game.standard()).findBestMove(depth: 4);
      expect(first.move, second.move);
      expect(first.score, second.score);
      expect(
        first.principalVariation.map((move) => move.notation),
        second.principalVariation.map((move) => move.notation),
      );
    });

    test('leaves the game it thinks about alone', () {
      final game = Game.standard();
      final fen = game.fen;
      CheckersAI(game).findBestMove(depth: 5);
      expect(game.fen, fen);
      expect(game.ply, 0);
      expect(game.sideToMove, Side.red);
    });

    test('follows a line of play it says is legal', () {
      final game = Game.standard();
      final result = CheckersAI(game).findBestMove(depth: 4);
      expect(result.principalVariation, hasLength(4));
      expect(result.principalVariation.first, result.move);
      for (final move in result.principalVariation) {
        expect(game.legalMoves(), contains(move), reason: move.notation);
        game.applyMove(move);
      }
      expect(game.ply, 4);
    });

    test('takes a man that is hanging', () {
      // Black's man on c3 can be jumped over, and taking it wins the game.
      final game = gameAt('W:W18:B22,31');
      final result = CheckersAI(game).findBestMove(depth: 4);
      expect(result.move!.notation, 'd4xb2');
      expect(result.isWin, isTrue);
      expect(result.score.abs(), greaterThan(CheckersAI.mateScore - 1000));
      game.applyMove(result.move!);
      expect(game.outcome, GameOutcome.redWin);
    });

    test('takes a capture when it is not forced to', () {
      // h4 could creep to g5, but the two-capture is worth far more.
      final game = Game.fromFen(
        'W:W20,25:B15,22',
        rules: const Rules(mustCapture: false),
        drawRules: DrawRules.none,
      );
      final result = CheckersAI(game).findBestMove(depth: 4);
      expect(result.move!.notation, 'b2xd4xf6');
      expect(result.move!.capturedCount, 2);
    });

    test('gives up a man to make nothing of it', () {
      // Red is a man down with no way back, so it plays on regardless.
      final game = gameAt('W:W18:B15,22');
      final result = CheckersAI(game).findBestMove(depth: 3);
      expect(game.legalMoves(), contains(result.move));
    });

    test('stops when the game is already over', () {
      final game = gameAt('W:W18:B22');
      game.applyMoveFrom(Square.parse('d4'), Square.parse('b2'));
      expect(game.isGameOver, isTrue);
      final result = CheckersAI(game).findBestMove(depth: 4);
      expect(result.move, isNull);
      expect(result.score, 0);
      expect(result.depthReached, 0);
      expect(result.nodes, 0);
      expect(result.principalVariation, isEmpty);
      expect(result.isWin, isFalse);
      expect(SearchResult.none.move, isNull);
      expect(result.toString(), contains('no move'));
    });

    test('stops when the clock runs out', () {
      final game = Game.standard();
      final clock = Stopwatch()..start();
      final result = CheckersAI(
        game,
      ).findBestMove(depth: 30, timeLimit: const Duration(milliseconds: 200));
      clock.stop();
      expect(result.move, isNotNull);
      expect(game.legalMoves(), contains(result.move));
      expect(result.depthReached, greaterThanOrEqualTo(1));
      expect(result.principalVariation, isNotEmpty);
      // It stops searching when it is told to, not a good while afterwards.
      expect(clock.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('plays a whole game against itself', () {
      final game = Game.standard();
      final clock = Stopwatch()..start();
      var plies = 0;
      while (!game.isGameOver && plies < 60) {
        final result = CheckersAI(game).findBestMove(depth: 4);
        final move = result.move;
        expect(move, isNotNull, reason: 'no move offered on ply $plies');
        expect(game.legalMoves(), contains(move));
        game.applyMove(move!);
        plies++;
      }
      clock.stop();
      expect(plies, 60);
      // Every piece that was taken came off the board, so the counts add up.
      expect(
        game.piecesOf(Side.red) + game.piecesOf(Side.black),
        24 - game.capturedBy(Side.red) - game.capturedBy(Side.black),
      );
      expect(
        clock.elapsed,
        lessThan(const Duration(seconds: 60)),
        reason: 'the search should not drag',
      );
    });

    test('sends a king after a man', () {
      // The king on a1 has to take the man on b2, and then carries on over d4.
      final game = Game.fromFen(
        'W:WK29:B18,25',
        rules: const Rules(autoDeclareMaterialEnd: false),
        drawRules: DrawRules.none,
      );
      final result = CheckersAI(game).findBestMove(depth: 2);
      expect(result.move!.notation, 'a1xc3xe5');
      expect(result.move!.capturedCount, 2);
      expect(result.isWin, isTrue);
      game.applyMove(result.move!);
      expect(game.piecesOf(Side.black), 0);
      expect(game.outcome, GameOutcome.redWin);
    });

    group('evaluate', () {
      test('is worth nothing in a level position', () {
        expect(CheckersAI.evaluate(Game.standard()), 0);
      });

      test('likes a man more than nothing', () {
        final even = CheckersAI.evaluate(gameAt('W:W18,21:B23'));
        final up = CheckersAI.evaluate(gameAt('W:W18,21,29:B23'));
        expect(up, greaterThan(even));
      });

      test('sees a king as worth more than a man', () {
        final man = CheckersAI.evaluate(gameAt('W:W18:B22'));
        final king = CheckersAI.evaluate(gameAt('W:WK18:B22'));
        expect(king, greaterThan(man));
      });

      test('is measured from the side to move', () {
        final red = gameAt('W:W18,21,22,23:B24,25,26');
        final black = Game.fromFen(
          'B:W18,21,22,23:B24,25,26',
          drawRules: DrawRules.none,
        );
        expect(CheckersAI.evaluate(red), greaterThan(0));
        expect(CheckersAI.evaluate(black), lessThan(0));
      });
    });
  });
}
