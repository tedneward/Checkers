// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The position of a game of checkers before anybody has moved.
const String openingPosition =
    'W:W21,22,23,24,25,26,27,28,29,30,31,32:B1,2,3,4,5,6,7,8,9,10,11,12';

/// The moves the side to move has in [position], written out and sorted.
List<String> movesOf(String position, {Rules rules = Rules.american}) {
  final groups = position.split(':');
  final side = Side.fromNotationLetter(groups.first);
  return MoveGenerator(
    Board.fromPosition(position),
    side,
    rules,
  ).generate().map((move) => move.notation).toList()..sort();
}

/// The one move the side to move has in [position].
Move onlyMoveOf(String position, {Rules rules = Rules.american}) {
  final side = Side.fromNotationLetter(position.split(':').first);
  final moves = MoveGenerator(
    Board.fromPosition(position),
    side,
    rules,
  ).generate();
  expect(moves, hasLength(1), reason: position);
  return moves.single;
}

void main() {
  group('MoveGenerator', () {
    test('opens the game with seven moves', () {
      expect(movesOf(openingPosition), [
        'a3-b4',
        'c3-b4',
        'c3-d4',
        'e3-d4',
        'e3-f4',
        'g3-f4',
        'g3-h4',
      ]);
      // Black answers with the same seven moves, played off his own back rank.
      expect(movesOf(openingPosition.replaceFirst('W:', 'B:')), [
        'b6-a5',
        'b6-c5',
        'd6-c5',
        'd6-e5',
        'f6-e5',
        'f6-g5',
        'h6-g5',
      ]);
    });

    test('only moves men forward to an empty square', () {
      expect(movesOf('W:W32:B1'), ['g1-f2', 'g1-h2']);
      expect(movesOf('B:W32:B1'), ['b8-a7', 'b8-c7']);
      // h4 has g3 behind it, but men do not move backwards.
      expect(movesOf('W:W20:B'), ['h4-g5']);
      // The man on a1 is shut in by red's own man on b2.
      final generator = MoveGenerator(
        Board.fromPosition('W:W29,25:B'),
        Side.red,
      );
      expect(generator.movesFrom(Square.parse('a1')), isEmpty);
      expect(generator.movesFrom(Square.parse('b2')).map((m) => m.notation), [
        'b2-a3',
        'b2-c3',
      ]);
    });

    test('says whether there is anything to do', () {
      final blocked = MoveGenerator(Board.fromPosition('W:W6:B1,2'), Side.red);
      expect(blocked.hasMoves, isFalse);
      expect(blocked.hasCapture, isFalse);
      expect(blocked.generate(), isEmpty);

      final opening = MoveGenerator(Board.standardInitial(), Side.red);
      expect(opening.hasMoves, isTrue);
      expect(opening.hasCapture, isFalse);
      expect(opening.generate(), hasLength(7));
      // The list is generated once and then reused.
      expect(opening.generate(), same(opening.generate()));
    });

    test('lists the moves that start on one square', () {
      final generator = MoveGenerator(Board.standardInitial(), Side.red);
      expect(
        generator.movesFrom(Square.parse('c3')).map((move) => move.notation),
        ['c3-b4', 'c3-d4'],
      );
      expect(generator.movesFrom(Square.parse('b8')), isEmpty);
    });

    test('finds a move by the squares it starts and ends on', () {
      final generator = MoveGenerator(Board.standardInitial(), Side.red);
      expect(
        generator.findMove(Square.parse('c3'), Square.parse('d4'))?.notation,
        'c3-d4',
      );
      // A man only moves one square, so this is not a move at all.
      expect(
        generator.findMove(Square.parse('c3'), Square.parse('c4')),
        isNull,
      );
      expect(
        generator.findMove(Square.parse('a3'), Square.parse('a4')),
        isNull,
      );
      expect(
        generator.findMove(Square.parse('b8'), Square.parse('a7')),
        isNull,
      );
    });

    test('forces a capture when one is on offer', () {
      // h4 could creep to g5, but the men on c3 and e5 have to be taken first.
      expect(movesOf('W:W20,25:B15,22'), ['b2xd4xf6']);
      // With captures left off, the quiet move is offered as well.
      expect(
        movesOf('W:W20,25:B15,22', rules: const Rules(mustCapture: false)),
        ['b2xd4xf6', 'h4-g5'],
      );
    });

    test('takes the biggest capture when there is a choice', () {
      // Under American rules men also capture backwards, which makes the chain
      // from h4 two captures long as well.
      expect(movesOf('W:W20,25:B15,16,22'), ['b2xd4xf6', 'h4xf6xd4']);
      // Without backward captures only b2 takes two pieces, so having to take
      // the biggest capture makes a difference.
      const noBackward = Rules(menCaptureBackward: false);
      expect(movesOf('W:W20,25:B15,16,22', rules: noBackward), ['b2xd4xf6']);
      expect(
        movesOf(
          'W:W20,25:B15,16,22',
          rules: const Rules(
            menCaptureBackward: false,
            mustCaptureMaximum: false,
          ),
        ),
        ['b2xd4xf6', 'h4xf6'],
      );
    });

    test('lets men capture backwards under American rules', () {
      expect(movesOf('W:W18:B22'), ['d4xb2']);
      expect(movesOf('W:W18:B22', rules: Rules.british), ['d4-c5', 'd4-e5']);
    });

    test('plays a capture out to the end of the chain', () {
      final move = onlyMoveOf('W:W20,25:B15,22');
      expect(move.from, Square.parse('b2'));
      expect(move.to, Square.parse('f6'));
      expect(move.path.map((square) => square.name), [
        'b2',
        'c3',
        'd4',
        'e5',
        'f6',
      ]);
      expect(move.capturedSquares.map((square) => square.name), ['c3', 'e5']);
      expect(move.capturedCount, 2);
      expect(move.isCapture, isTrue);
      expect(move.isMultiJump, isTrue);
      expect(move.notationSquares.map((square) => square.name), [
        'b2',
        'd4',
        'f6',
      ]);
      expect(move.toString(), 'b2xf6');
    });

    test('will not jump a piece of its own, or land on one', () {
      // c3 is a black man, but b2 is red's own, so there is no capture here.
      expect(movesOf('W:W18,25:B22'), ['b2-a3', 'd4-c5', 'd4-e5']);
      // Same again with the landing square blocked instead of the victim.
      expect(movesOf('W:W25,18:B22'), ['b2-a3', 'd4-c5', 'd4-e5']);
    });

    test('slides a king any distance along a diagonal', () {
      expect(movesOf('W:WK22:B'), [
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

    test('stops a king at the first piece in the way', () {
      // With flying kings off, the man on e5 cannot be jumped, so it also
      // blocks the king from sliding any further up that diagonal.
      expect(
        movesOf('W:WK22:B15,8', rules: const Rules(longRangedKings: false)),
        ['c3-a1', 'c3-a5', 'c3-b2', 'c3-b4', 'c3-d2', 'c3-d4', 'c3-e1'],
      );
    });

    test('jumps with a king from a distance', () {
      expect(movesOf('W:K29,32:B18'), ['a1xe5']);
      expect(
        movesOf('W:K29,32:B18', rules: const Rules(longRangedKings: false)),
        ['a1-b2', 'a1-c3', 'g1-f2', 'g1-h2'],
      );
      // A short ranged king still jumps the piece right next to it.
      expect(
        movesOf('W:WK22:B18', rules: const Rules(longRangedKings: false)),
        ['c3xe5'],
      );
    });

    test('carries a king along a chain of captures', () {
      final moves = MoveGenerator(
        Board.fromPosition('W:WK22:B15,8'),
        Side.red,
      ).generate();
      expect(moves.map((move) => move.notation), ['c3xf6xh8', 'c3xh8xd4']);
      expect(moves.first.capturedCount, 2);
      expect(moves.first.path.map((square) => square.name), [
        'c3',
        'e5',
        'f6',
        'g7',
        'h8',
      ]);
      expect(moves.last.capturedSquares.map((square) => square.name), [
        'g7',
        'e5',
      ]);
      // The king never takes one of its own pieces, even the square it set out
      // from.
      for (final move in moves) {
        expect(move.capturedSquares, isNot(contains(Square.parse('c3'))));
        expect(
          move.capturedSquares.every(
            (square) =>
                Square.fromNumber(15) == square ||
                Square.fromNumber(8) == square,
          ),
          isTrue,
        );
      }
    });

    test('does not take the same piece twice in one chain', () {
      // h4 can reach d4 over c3 and e5, but only by taking each man once.
      final moves = MoveGenerator(
        Board.fromPosition('W:W20,25:B15,16,22'),
        Side.red,
      ).generate();
      for (final move in moves) {
        expect(move.capturedSquares.toSet(), hasLength(move.capturedCount));
        expect(
          move.capturedSquares.every((square) => square != Square.parse('b2')),
          isTrue,
        );
      }
    });

    test('crowns a man that reaches the far rank', () {
      final moves = MoveGenerator(
        Board.fromPosition('W:W6:B32'),
        Side.red,
      ).generate();
      expect(moves.map((move) => move.notation), ['c7-b8*', 'c7-d8*']);
      expect(moves.every((move) => move.promotes), isTrue);
    });

    test('crowns a man in the middle of a capture', () {
      // b6 jumps c7 onto d8, is crowned there, and carries on over e7.
      final move = onlyMoveOf('W:W9:B6,7');
      expect(move.notation, 'b6xd8xf6*');
      expect(move.promotes, isTrue);
      expect(move.capturedCount, 2);
      expect(move.path.map((square) => square.name), [
        'b6',
        'c7',
        'd8',
        'e7',
        'f6',
      ]);
    });

    test('stops a crowned chain when there is nothing left to jump', () {
      // d6 jumps c7 onto b8 and is crowned, but a king on b8 has nowhere to
      // jump to, so the capture ends there.
      final move = onlyMoveOf('W:W10:B5,6');
      expect(move.notation, 'd6xb8*');
      expect(move.promotes, isTrue);
      expect(move.capturedCount, 1);
    });

    test('leaves an uncrowned man uncrowned when the rules say so', () {
      final moves = MoveGenerator(
        Board.fromPosition('W:W6:B32'),
        Side.red,
        const Rules(promoteOnArrival: false),
      ).generate();
      expect(moves.map((move) => move.notation), ['c7-b8', 'c7-d8']);
      expect(moves.every((move) => !move.promotes), isTrue);
    });
  });
}
