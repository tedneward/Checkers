// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The position of a game of checkers before anybody has moved.
const String openingPosition =
    'W:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12';

void main() {
  group('Board', () {
    test('starts with twelve men a side', () {
      final board = Board.standardInitial();
      expect(board.pieceCount, 24);
      expect(board.countOf(Side.red), 12);
      expect(board.countOf(Side.black), 12);
      expect(board.countOf(Side.red, kind: PieceKind.man), 12);
      expect(board.countOf(Side.red, kind: PieceKind.king), 0);
      expect(board[Square.parse('a3')], const Piece.redMan());
      expect(board[Square.parse('g1')], const Piece.redMan());
      expect(board[Square.parse('b8')], const Piece.blackMan());
      expect(board[Square.parse('h6')], const Piece.blackMan());
    });

    test('leaves the light squares empty', () {
      final board = Board.standardInitial();
      for (final square in Square.all.where((s) => !s.isDark)) {
        expect(board[square], isNull, reason: square.name);
      }
    });

    test('starts with no kings', () {
      final board = Board.standardInitial();
      expect(board.squaresOf(Side.red, kind: PieceKind.king), isEmpty);
      expect(board.squaresOf(Side.black, kind: PieceKind.king), isEmpty);
      expect(board.squaresOf(Side.red), hasLength(12));
    });

    test('is empty to begin with', () {
      final board = Board.empty();
      expect(board.isEmpty, isTrue);
      expect(board.pieceCount, 0);
      expect(board.toPosition(), 'W:W:B');
    });

    test('writes the opening position out in order', () {
      expect(Board.standardInitial().toPosition(), openingPosition);
    });

    test('lists its pieces from a1 upwards', () {
      final board = Board.fromPosition('W:W29:B32');
      expect(board.occupiedSquares.map((square) => square.name), ['a1', 'g1']);
      expect(board.squaresOf(Side.black), [Square.parse('g1')]);
      expect(board.piecesOf(Side.black), [const Piece.blackMan()]);
    });

    test('sorts kings and men by square when writing a position', () {
      // Squares are written in order whether or not they hold kings.
      final board = Board.fromPosition('W:W21K,18:B29K,2');
      expect(board.toPosition(), 'W:W18,K21:B2,K29');
    });

    test('reads a position back exactly as it was written', () {
      expect(Board.fromPosition(openingPosition), Board.standardInitial());
      expect(
        Board.fromPosition('W:W18,21:BK2,K29'),
        Board.fromPosition('W:W18,21:BK2,K29'),
      );
      for (final position in [
        openingPosition,
        'W:W18,21:BK2,K29',
        'W:W21:B1',
        'W:W:B',
      ]) {
        expect(
          Board.fromPosition(position).toPosition(),
          position,
          reason: position,
        );
      }
    });

    test('reads kings written either side of their number', () {
      final board = Board.fromPosition('W:W29K:BK5');
      expect(board[Square.parse('a1')], const Piece.redKing());
      expect(board[Square.parse('a7')], const Piece.blackKing());
      expect(board.toPosition(), 'W:WK29:BK5');
      // The side to move is written first and is not a side that has pieces.
      expect(board.toPosition(sideToMove: Side.black), 'B:WK29:BK5');
    });

    test('reads positions with no pieces at all', () {
      expect(Board.fromPosition('W::').isEmpty, isTrue);
      expect(Board.fromPosition('W:W21:').pieceCount, 1);
      // An empty board is written with empty groups, not with none at all.
      expect(Board.empty().toPosition(), 'W:W:B');
    });

    test('refuses positions that are not positions', () {
      // A position has three groups and no more.
      expect(() => Board.fromPosition('W:W21'), throwsFormatException);
      expect(() => Board.fromPosition('W:W21:B1:B2'), throwsFormatException);
      // The first group has to be the side to move.
      expect(() => Board.fromPosition('X:W21:B1'), throwsFormatException);
      // Each group has to belong to the side it sits in.
      expect(() => Board.fromPosition('W:B21:W1'), throwsFormatException);
      // Squares are written as numbers.
      expect(() => Board.fromPosition('W:Wzz:B1'), throwsFormatException);
      expect(() => Board.fromPosition('W:W21:B33'), throwsRangeError);
    });

    test('refuses a piece on a light square', () {
      expect(
        () => Board.fromSetup({Square.parse('b1'): const Piece.redMan()}),
        throwsArgumentError,
      );
    });

    test('copies itself when a piece is set or taken', () {
      final board = Board.fromPosition('W:W29:B32');
      final moved = board.withPiece(Square.parse('a1'), null);
      expect(moved[Square.parse('a1')], isNull);
      expect(board[Square.parse('a1')], const Piece.redMan());

      final promoted = board.withPiece(
        Square.parse('a1'),
        const Piece.redKing(),
      );
      expect(promoted[Square.parse('a1')], const Piece.redKing());
      expect(board[Square.parse('a1')], const Piece.redMan());

      final cleared = board.withoutPieces([Square.parse('a1')]);
      expect(cleared.countOf(Side.red), 0);
      expect(board.countOf(Side.red), 1);
    });

    test('reports what is on a square', () {
      final board = Board.fromPosition('W:W29:B32');
      expect(board.isOccupied(Square.parse('a1')), isTrue);
      expect(board.isEmptyAt(Square.parse('b4')), isTrue);
      expect(board.isOccupiedBy(Square.parse('a1'), Side.red), isTrue);
      expect(board.isOccupiedBy(Square.parse('a1'), Side.black), isFalse);
      expect(board.pieceAt(Square.parse('a1').index)?.isMan, isTrue);
      expect(board.pieceAt(Square.parse('b4').index), isNull);
    });

    test('draws the board with rank 8 at the top', () {
      final lines = Board.standardInitial().render().split('\n');
      expect(lines, hasLength(9));
      expect(lines.first.startsWith('8  '), isTrue);
      expect(lines[7].startsWith('1  '), isTrue);
      expect(lines.last, '   abcdefgh');
      // Twelve men on rank 3, drawn as characters.
      expect(
        lines[5].split('').where((c) => c.isNotEmpty).length,
        greaterThan(4),
      );
    });

    test('compares by the pieces on it', () {
      expect(Board.fromPosition('W:W21:B1'), Board.fromPosition('W:W21:B1'));
      expect(
        Board.fromPosition('W:W21:B1').hashCode,
        Board.fromPosition('W:W21:B1').hashCode,
      );
      expect(
        Board.fromPosition('W:W21:B1'),
        isNot(Board.fromPosition('W:W22:B1')),
      );
      // ignore: unrelated_type_equality_checks
      expect(Board.fromPosition('W:W21:B1') == Object(), isFalse);
    });
  });

  group('Piece', () {
    test('knows its side and kind', () {
      const man = Piece.redMan();
      expect(man.side, Side.red);
      expect(man.kind, PieceKind.man);
      expect(man.isMan, isTrue);
      expect(man.isKing, isFalse);
      expect(man.promoted, const Piece.redKing());
      expect(man.promoted.promoted, const Piece.redKing());
      expect(man.opponent, const Piece.blackMan());
    });

    test('crowns on its own far rank', () {
      expect(Side.red.crownRank, 7);
      expect(Side.black.crownRank, 0);
      expect(Side.red.startRank, 0);
      expect(Side.black.startRank, 7);
    });

    test('has an opponent and a notation letter', () {
      expect(Side.red.opponent, Side.black);
      expect(Side.black.opponent, Side.red);
      expect(Side.red.notationLetter, 'W');
      expect(Side.black.notationLetter, 'B');
      expect(Side.red.label, 'Red');
      expect(Side.black.label, 'Black');
      expect(Side.fromNotationLetter('w'), Side.red);
      expect(Side.fromNotationLetter('R'), Side.red);
      expect(Side.fromNotationLetter('b'), Side.black);
      expect(() => Side.fromNotationLetter('x'), throwsFormatException);
      expect(PieceKind.man.notationLetter, isEmpty);
      expect(PieceKind.king.notationLetter, 'K');
      expect(PieceKind.man.other, PieceKind.king);
      expect(PieceKind.king.other, PieceKind.man);
    });

    test('draws itself with a draughts character', () {
      expect(const Piece.redMan().char, '\u26C0\uFE0E');
      expect(const Piece.redKing().char, '\u26C2\uFE0E');
      expect(const Piece.blackMan().char, '\u26C1\uFE0E');
      expect(const Piece.blackKing().char, '\u26C3\uFE0E');
      expect(const Piece.redMan().toString(), 'Red man');
    });
  });
}
