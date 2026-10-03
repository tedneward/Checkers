// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The moves the side owning [square] has from it in [position].
///
/// This deliberately ignores whose turn it is, so that a single piece can be
/// looked at without having to invent an opponent to take turns with.
List<String> movesFrom(String position, String square) {
  final board = Board.fromPosition(position);
  return MoveGenerator(
      board,
      board[Square.parse(square)]!.side,
    ).movesFrom(Square.parse(square)).map((move) => move.notation).toList()
    ..sort();
}

/// The moves the side to move has out of [square] in [position].
List<String> movesForSideToMove(
  String position,
  String square, {
  Rules rules = Rules.american,
}) {
  final side = Side.fromNotationLetter(position.split(':').first);
  return MoveGenerator(
      Board.fromPosition(position),
      side,
      rules,
    ).movesFrom(Square.parse(square)).map((move) => move.notation).toList()
    ..sort();
}

/// The piece standing on [square] in [position].
Piece pieceAt(String position, String square) =>
    Board.fromPosition(position)[Square.parse(square)]!;

void main() {
  group('a man moves', () {
    test('a red man has only the two squares diagonally ahead of it', () {
      // 22 is c3. Red advances towards rank 8, so b4 and d4 and nothing else.
      expect(movesFrom('W:W22:B', 'c3'), ['c3-b4', 'c3-d4']);
    });

    test('a black man has only the two squares diagonally ahead of it', () {
      // 14 is c5. Black advances towards rank 1, so b4 and d4 and nothing else.
      expect(movesFrom('B:W:B14', 'c5'), ['c5-b4', 'c5-d4']);
    });

    test('a man never slides past the square in front of it', () {
      // The king on c3 has the long a5-a1 and a3-a5 style diagonals open to it.
      // The man on the same square reaches only one step along each of them.
      expect(movesFrom('W:W22:B', 'c3'), ['c3-b4', 'c3-d4']);
      expect(movesFrom('W:WK22:B', 'c3'), [
        'c3-a1',
        'c3-a5',
        'c3-b2',
        'c3-b4',
        'c3-d2',
        'c3-d4',
        'c3-e1',
        'c3-e5',
        'c3-f6',
        'c3-g7',
        'c3-h8',
      ]);
    });

    test('a man shut in by its own side has no move at all', () {
      // The man on a1 can only ever reach b2, which a red man already holds.
      expect(movesFrom('W:W29,25:B', 'a1'), isEmpty);
    });
  });

  group('a king moves', () {
    test('a red king moves along all four diagonals', () {
      expect(movesFrom('W:WK22:B', 'c3'), [
        'c3-a1',
        'c3-a5',
        'c3-b2',
        'c3-b4',
        'c3-d2',
        'c3-d4',
        'c3-e1',
        'c3-e5',
        'c3-f6',
        'c3-g7',
        'c3-h8',
      ]);
    });

    test('a black king moves along all four diagonals', () {
      expect(movesFrom('B:W:BK14', 'c5'), [
        'c5-a3',
        'c5-a7',
        'c5-b4',
        'c5-b6',
        'c5-d4',
        'c5-d6',
        'c5-e3',
        'c5-e7',
        'c5-f2',
        'c5-f8',
        'c5-g1',
      ]);
    });

    test('a king may walk backwards, which is what crowning buys it', () {
      // A red king on its own crown row has nowhere forward to go, so every
      // move it has carries it back down towards rank 1.
      expect(movesFrom('W:WK1:B25', 'b8'), [
        'b8-a7',
        'b8-c7',
        'b8-d6',
        'b8-e5',
        'b8-f4',
        'b8-g3',
        'b8-h2',
      ]);
      // And a king that has wandered back into red's own half keeps the ability
      // to keep retreating all the way to rank 1.
      expect(movesFrom('W:WK18:B', 'd4'), contains('d4-a1'));
      expect(movesFrom('W:WK18:B', 'd4'), contains('d4-h8'));
    });
  });

  group('a man is not mistaken for a king', () {
    test('a man cannot take a piece that is more than one square away', () {
      // 21 is a3 and 14 is c5, two diagonal steps apart, so the man on a3 has
      // to jump over something sitting on b4 to reach c5. There is nothing on
      // b4, so it has no capture at all and can only creep to b2.
      expect(movesFrom('B:W14:B21', 'a3'), ['a3-b2']);
    });

    test('a king on that same square does take the distant piece', () {
      // Same position, same red piece on c5, but now the piece on a3 is a king.
      // It reads along the diagonal and takes c5, landing on d6.
      expect(movesFrom('B:W14:BK21', 'a3'), ['a3xd6']);
    });

    test('the two kinds are told apart by what they can reach', () {
      final man = movesFrom('B:W:B14', 'c5');
      final king = movesFrom('B:W:BK14', 'c5');

      // The man's square is the same square in both cases, so anything the man
      // can reach the king can reach too. The difference is everything else.
      expect(king, containsAll(man));
      expect(king.length, greaterThan(man.length));

      // b6 and a7 are behind a man, which is exactly the reach a crown adds.
      expect(man, isNot(contains('c5-b6')));
      expect(king, contains('c5-b6'));
      expect(man, isNot(contains('c5-a7')));
      expect(king, contains('c5-a7'));
    });

    test('a man may not be jumped over its own king', () {
      // 21 is a3 and 5 is a7. A red king on a7 sits two steps away up the
      // diagonal, and a black man on a3 must not treat it as a capture.
      expect(movesFrom('W:WK5:B21', 'a3'), isNot(contains('a3xa7')));
    });
  });

  group('crowning', () {
    test('a man that reaches the far rank becomes a king', () {
      // 6 is c7 and 1 is b8, the row red crowns on.
      final game = Game.fromFen('W:W6:B25');
      expect(pieceAt('W:W6:B25', 'c7').isMan, isTrue);

      game.applyMove(game.parseMove('c7-b8'));

      expect(game.board[Square.parse('b8')], const Piece.redKing());
      expect(game.lastMove?.promotes, isTrue);
      // And the crowning survives being written out and read back in.
      expect(game.fen, 'B:WK1:B25 B');
    });

    test('black is crowned on rank 1 rather than rank 8', () {
      // 25 is b2, and its two steps ahead are a1 and c1, both on rank 1.
      expect(movesFrom('B:W4:B25', 'b2'), ['b2-a1*', 'b2-c1*']);

      final game = Game.fromFen('B:W4:B25');
      game.applyMove(game.parseMove('b2-a1'));
      expect(game.board[Square.parse('a1')], const Piece.blackKing());
    });

    test('the moves that crown are marked as such', () {
      // A man on c7 is one step from the crown row, and both of its moves get
      // it there, so both carry the crowning marker.
      expect(movesFrom('W:W6:B25', 'c7'), ['c7-b8*', 'c7-d8*']);
      // A man in the middle of the board crowns nothing.
      expect(movesFrom('W:W22:B', 'c3'), ['c3-b4', 'c3-d4']);
    });

    test('a crowned piece stays a king when it walks back', () {
      // Crowning leaves red holding only kings against black's men, which the
      // material rule would otherwise end there and then, so it is set aside for
      // this test. Turns still have to alternate, so black shuffles its man
      // between red's two steps: red crowns on b8, then walks back to a7.
      final game = Game.fromFen(
        'W:W6:B25',
        rules: const Rules(autoDeclareMaterialEnd: false),
      );
      game.applyMove(game.parseMove('c7-b8'));
      game.applyMove(game.parseMove('b2-a1'));
      game.applyMove(game.parseMove('b8-a7'));

      expect(game.board[Square.parse('a7')], const Piece.redKing());
      // Back on red's own ground it must still be able to retreat to rank 1.
      expect(
        MoveGenerator(
          game.board,
          Side.red,
        ).movesFrom(Square.parse('a7')).map((move) => move.notation),
        contains('a7-b6'),
      );
    });

    test('a man is not crowned simply by being near the far rank', () {
      expect(pieceAt('W:W6:B25', 'c7').isMan, isTrue);
      expect(pieceAt('W:W22:B', 'c3').isMan, isTrue);
      expect(pieceAt('B:W4:B25', 'b2').isMan, isTrue);
    });
  });

  group('men capture only where the rules allow', () {
    test('a black man may not capture backwards when the rules forbid it', () {
      // 14 is c5, 9 is b6 and 5 is a7. Jumping b6 carries the man towards rank
      // 8, which is backwards for black, so under these rules it is not a move.
      expect(movesForSideToMove('B:W9:B14', 'c5', rules: Rules.british), [
        'c5-b4',
        'c5-d4',
      ]);
    });

    test('the same man may creep forward when the backward jump is refused', () {
      // With no capture available the man still has its two quiet steps, which
      // are forwards for black.
      expect(movesForSideToMove('B:W9:B14', 'c5', rules: Rules.british), [
        'c5-b4',
        'c5-d4',
      ]);
    });

    test(
      'a crowned man jumps either way because crowning is what allows it',
      () {
        // The king on c5 reaches a7 over b6, because a king is not restricted to
        // the forward diagonals no matter which rule set is in play.
        expect(movesForSideToMove('B:W9:BK14', 'c5'), ['c5xa7']);
        expect(movesForSideToMove('B:W9:BK14', 'c5', rules: Rules.british), [
          'c5xa7',
        ]);
      },
    );
  });
}
