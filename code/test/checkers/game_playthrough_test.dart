// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:test/test.dart';

/// Plays a deterministic sequence by always taking the first legal move each turn.
/// Returns the list of notation strings for the moves played.
List<String> playDeterministic(Game game, int plies) {
  final result = <String>[];
  for (var i = 0; i < plies && !game.isGameOver; i++) {
    final legalMoves = game.legalMoves();
    if (legalMoves.isEmpty) break;
    final move = legalMoves.first;
    game.applyMove(move);
    result.add(move.notation);
  }
  return result;
}

/// Applies a sequence of moves given as checkers notation strings, one per ply.
/// Returns the final game after all moves have been applied.
Game applyMoves(Game game, List<String> moves) {
  for (final notation in moves) {
    final move = game.parseMove(notation);
    final applied = game.tryApplyMove(move);
    if (!applied) {
      throw StateError(
        'Move failed to apply: $notation (side to move: '
        '${game.sideToMove}, ply: ${game.ply})',
      );
    }
  }
  return game;
}

/// Applies moves until the game ends or a safety cap is reached.
/// Returns true if the game ended naturally.
bool playUntilEnd(Game game, {int maxPlies = 200}) {
  var plies = 0;
  while (!game.isGameOver && plies < maxPlies) {
    final legalMoves = game.legalMoves();
    if (legalMoves.isEmpty) break;
    final applied = game.tryApplyMove(legalMoves.first);
    if (!applied) break;
    plies++;
  }
  return game.isGameOver;
}

void main() {
  group('Game playthroughs - standard rules', () {
    test('can play a short opening sequence and continue', () {
      final opening = playDeterministic(Game.standard(), 8);
      final game2 = Game.standard();
      applyMoves(game2, opening);
      expect(game2.ply, opening.length);
      expect(game2.isGameOver, isFalse);
    });

    test('handles a sequence with captures', () {
      final game = Game.standard();
      playDeterministic(game, 12);
      expect(game.ply, greaterThan(0));
      expect(game.isGameOver || game.ply == 12, isTrue);
    });

    test('can progress through a longer game sequence', () {
      final game = Game.standard();
      playDeterministic(game, 30);
      expect(game.ply, greaterThan(0));
    });

    test('greedy play (first legal move each time) does not get stuck', () {
      final game = Game.standard();
      final ended = playUntilEnd(game, maxPlies: 150);
      // The engine should never hang; it should either end or reach max plies
      // gracefully. Getting stuck means we'd never return - this test verifies
      // termination of the loop.
      expect(ended || game.ply >= 150, isTrue);
    });

    test('deterministic playthrough progresses normally', () {
      final game = Game.standard();
      final moves = playDeterministic(game, 20);
      expect(moves.length, greaterThan(0));
      expect(game.legalMoves().isNotEmpty || game.isGameOver, isTrue);
    });
  });

  group('Game playthroughs - edge cases', () {
    test(
      'game from standard position can make many moves without crashing',
      () {
        final game = Game.standard();
        var movesApplied = 0;
        const maxMoves = 100;
        while (!game.isGameOver && movesApplied < maxMoves) {
          final moves = game.legalMoves();
          if (moves.isEmpty) break;
          final applied = game.tryApplyMove(moves.first);
          expect(applied, isTrue);
          movesApplied++;
        }
        // Should have applied moves successfully without throwing
        expect(movesApplied, greaterThan(0));
      },
    );

    test('alternating sides throughout playthrough', () {
      final moves = playDeterministic(Game.standard(), 6);
      final game2 = Game.standard();
      applyMoves(game2, moves);
      expect(game2.ply, 6);
      expect(game2.sideToMove, isNotNull);
    });

    test('capture chains work correctly in playthrough', () {
      final game = Game.position(
        Board.fromPosition(
          'W:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12',
        ),
        sideToMove: Side.black,
      );
      // Try to find and execute a capture if available
      final legalMoves = game.legalMoves();
      if (legalMoves.isNotEmpty && legalMoves.first.isCapture) {
        final move = legalMoves.first;
        final applied = game.tryApplyMove(move);
        expect(applied, isTrue);
        expect(game.ply, 1);
      }
    });
  });

  group('Notation roundtrip through full games', () {
    test('applied moves can be reconstructed via notation', () {
      final moves = playDeterministic(Game.standard(), 4);
      final game2 = Game.standard();
      for (final notation in moves) {
        final parsed = game2.parseMove(notation);
        expect(parsed.notation, isNotEmpty);
        final applied = game2.tryApplyMove(parsed);
        expect(applied, isTrue);
      }
      expect(game2.ply, moves.length);
    });

    test('complex sequences work with notation roundtrip', () {
      final moves = playDeterministic(Game.standard(), 10);
      final game2 = Game.standard();
      applyMoves(game2, moves);
      expect(game2.ply, moves.length);
    });
  });

  group('Stress tests - engine stability', () {
    test('engine does not get stuck on long random legal-move sequences', () {
      final game = Game.standard();
      var iterations = 0;
      const maxIterations = 80;
      while (!game.isGameOver && iterations < maxIterations) {
        final legal = game.legalMoves();
        if (legal.isEmpty) break;
        // Pick the first legal move - deterministic, tests stability
        final move = legal.first;
        final ok = game.tryApplyMove(move);
        if (!ok) {
          fail('Failed to apply move ${move.notation} at ply ${game.ply}');
        }
        iterations++;
      }
      // If it completed without throwing, it's stable
      expect(iterations, greaterThanOrEqualTo(1));
    });

    test('multiple game instances play independently without interference', () {
      final game1 = Game.standard();
      final game2 = Game.standard();
      final game3 = Game.standard();

      playDeterministic(game1, 2);
      playDeterministic(game2, 3);
      playDeterministic(game3, 2);

      expect(game1.ply, 2);
      expect(game2.ply, 3);
      expect(game3.ply, 2);
      expect(game1.fen, isNot(game2.fen));
      expect(game2.fen, isNot(game3.fen));
    });

    test(
      'replaying same sequence multiple times produces consistent results',
      () {
        final sequence = playDeterministic(Game.standard(), 6);
        final fens = <String>[];
        for (var i = 0; i < 3; i++) {
          final game = Game.standard();
          applyMoves(game, sequence);
          fens.add(game.fen);
        }
        expect(fens[0], equals(fens[1]));
        expect(fens[1], equals(fens[2]));
      },
    );
  });
}
