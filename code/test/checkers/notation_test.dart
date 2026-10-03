// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The quiet move written as [text], such as `b2-b4`.
Move quietMove(String text) {
  final parsed = Notation.parse(text);
  return Move(from: parsed.from, to: parsed.to, path: parsed.path);
}

/// The capture in which the piece on [from] jumps [jumped] and lands on [to].
Move captureMove(String from, String jumped, String to) => Move(
  from: Square.parse(from),
  to: Square.parse(to),
  path: [Square.parse(from), Square.parse(jumped), Square.parse(to)],
);

void main() {
  group('Notation', () {
    test('writes a quiet move with a dash', () {
      expect(Notation.format(quietMove('b2-b4')), 'b2-b4');
    });

    test('writes a capture with an x', () {
      expect(
        Notation.format(
          Move(
            from: Square.parse('b2'),
            to: Square.parse('a4'),
            path: [Square.parse('b2'), Square.parse('c4'), Square.parse('a4')],
          ),
        ),
        'b2xa4',
      );
    });

    test('writes the squares a piece lands on, not the ones it jumps', () {
      // b2xc3xc5 would be read as one jump over two pieces; the chain is
      // written out square by square instead.
      final move = Move(
        from: Square.parse('b2'),
        to: Square.parse('f6'),
        path: [
          for (final name in ['b2', 'c3', 'd4', 'e5', 'f6']) Square.parse(name),
        ],
      );
      expect(move.capturedSquares.map((square) => square.name), ['c3', 'e5']);
      expect(move.notationSquares.map((square) => square.name), [
        'b2',
        'd4',
        'f6',
      ]);
      expect(move.notation, 'b2xd4xf6');
    });

    test('marks a move that crowns a piece', () {
      expect(
        Notation.format(
          Move(
            from: Square.parse('c7'),
            to: Square.parse('b8'),
            path: [Square.parse('c7'), Square.parse('b8')],
            promotes: true,
          ),
        ),
        'c7-b8*',
      );
      expect(quietMove('c7-b8*').withoutPromotion.notation, 'c7-b8');
      expect(
        quietMove('c7-b8').withPromotion(promotes: true).notation,
        'c7-b8*',
      );
    });

    test('reads the separators or does without them', () {
      for (final text in ['b2-b4', 'b2b4', 'B2-B4', 'B2B4', ' b2b4 ']) {
        final parsed = Notation.parse(text);
        expect(parsed.from, Square.parse('b2'), reason: text);
        expect(parsed.to, Square.parse('b4'), reason: text);
        expect(parsed.promotes, isFalse, reason: text);
        expect(parsed.isCapture, isFalse, reason: text);
        expect(parsed.path, hasLength(2), reason: text);
      }
      for (final text in ['b2xd4xf6', 'b2Xd4Xf6', 'b2d4f6', 'B2-D4-F6']) {
        final parsed = Notation.parse(text);
        expect(parsed.from, Square.parse('b2'), reason: text);
        expect(parsed.to, Square.parse('f6'), reason: text);
        expect(parsed.isCapture, isTrue, reason: text);
        expect(parsed.path.map((square) => square.name), [
          'b2',
          'd4',
          'f6',
        ], reason: text);
      }
    });

    test('reads the promotion marker', () {
      final parsed = Notation.parse('c7-b8*');
      expect(parsed.promotes, isTrue);
      expect(parsed.to, Square.parse('b8'));
      expect(Notation.parse('c7-b8').promotes, isFalse);
    });

    test('refuses text that is not a move', () {
      expect(() => Notation.parse('b2'), throwsFormatException);
      expect(() => Notation.parse(''), throwsFormatException);
      expect(() => Notation.parse('b2-'), throwsFormatException);
      expect(() => Notation.parse('b2-b4!'), throwsFormatException);
      expect(() => Notation.parse('b2-z9'), throwsFormatException);
    });
  });

  group('Game.parseMove', () {
    test('finds the move a piece can make', () {
      final game = Game.standard();
      final move = game.parseMove('c3-d4');
      expect(game.legalMoves(), contains(move));
      expect(move.from, Square.parse('c3'));
      expect(move.to, Square.parse('d4'));
      expect(game.parseMove('C3d4'), move);
    });

    test('finds a capture written out or in shorthand', () {
      final game = Game.fromFen('W:W20,25:B15,22');
      final spelled = game.parseMove('b2xd4xf6');
      expect(spelled.notation, 'b2xd4xf6');
      expect(spelled.capturedCount, 2);
      // Naming only the squares the piece starts and finishes on finds the same
      // move, which is the one that takes the most pieces.
      expect(game.parseMove('b2xf6'), spelled);
      expect(game.parseMove('b2-f6'), spelled);
    });

    test('refuses a move that is not legal here', () {
      final game = Game.standard();
      expect(
        () => game.parseMove('a3-c5'),
        throwsA(isA<IllegalMoveException>()),
      );
      // Legal shape, but the wrong side is to move.
      expect(
        () => game.parseMove('b8-a7'),
        throwsA(
          isA<IllegalMoveException>().having(
            (error) => error.message,
            'message',
            contains('Red'),
          ),
        ),
      );
      expect(() => game.parseMove('nonsense'), throwsFormatException);
    });

    test('honours a promotion marker', () {
      final game = Game.fromFen('W:W6:B32');
      expect(game.parseMove('c7-b8').promotes, isTrue);
      expect(game.parseMove('c7-d8').promotes, isTrue);
    });

    test('round trips every move of a game', () {
      for (final position in [
        'W:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12',
        'W:W20,25:B15,16,22',
        'W:W9:B6,7',
        'W:WK22:B15,8',
      ]) {
        final side = Side.fromNotationLetter(position.split(':').first);
        final game = Game.fromFen(position);
        final moves = MoveGenerator(game.board, side, game.rules).generate();
        for (final move in moves) {
          final text = move.notation;
          final parsed = Notation.parse(text);
          expect(parsed.from, move.from, reason: text);
          expect(parsed.to, move.to, reason: text);
          expect(parsed.promotes, move.promotes, reason: text);
          expect(parsed.isCapture, move.isCapture, reason: text);
          expect(Notation.format(move), text, reason: text);
          expect(game.parseMove(text), move, reason: text);
        }
      }
    });
  });

  group('Move', () {
    test('describes a quiet move', () {
      final move = quietMove('b2-b4');
      expect(move.path.map((square) => square.name), ['b2', 'b4']);
      expect(move.capturedCount, 0);
      expect(move.capturedSquares, isEmpty);
      expect(move.isCapture, isFalse);
      expect(move.isMultiJump, isFalse);
      expect(move.notationSquares.map((square) => square.name), ['b2', 'b4']);
    });

    test('describes a capture', () {
      final move = Move(
        from: Square.parse('b2'),
        to: Square.parse('a4'),
        path: [Square.parse('b2'), Square.parse('c4'), Square.parse('a4')],
      );
      expect(move.path, hasLength(3));
      expect(move.capturedSquares, [Square.parse('c4')]);
      expect(move.capturedCount, 1);
      expect(move.isCapture, isTrue);
      expect(move.isMultiJump, isFalse);
    });

    test('compares by the squares it touches', () {
      final one = captureMove('b2', 'c4', 'a4');
      final same = captureMove('b2', 'c4', 'a4');
      expect(one, same);
      expect(one.hashCode, same.hashCode);
      expect(one, isNot(captureMove('b2', 'c4', 'a6')));
      expect(one, isNot(same.withPromotion(promotes: true)));
      // ignore: unrelated_type_equality_checks
      expect(one == Object(), isFalse);
    });

    test('explains itself when it is thrown', () {
      const error = IllegalMoveException('no such move');
      expect(error.toString(), contains('no such move'));
      expect(error.message, 'no such move');
    });
  });
}
