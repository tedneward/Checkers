// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Square', () {
    test('names every one of the 64 squares', () {
      expect(Square.all, hasLength(64));
      expect(Square.parse('a1').name, 'a1');
      expect(Square.parse('h8').name, 'h8');
      for (final square in Square.all) {
        expect(Square.parse(square.name), square, reason: square.name);
      }
    });

    test('parses names whatever case they are written in', () {
      expect(Square.parse('H8'), Square.parse('h8'));
      expect(Square.parse(' b4 '), Square.parse('b4'));
    });

    test('refuses names that are not squares', () {
      expect(() => Square.parse(''), throwsFormatException);
      expect(() => Square.parse('a'), throwsFormatException);
      expect(() => Square.parse('a9'), throwsFormatException);
      expect(() => Square.parse('z1'), throwsFormatException);
      expect(() => Square.parse('a10'), throwsFormatException);
      expect(Square.tryParse('z9'), isNull);
      expect(Square.tryParse('b4'), Square.parse('b4'));
    });

    test('plays on the 32 dark squares', () {
      final dark = Square.all.where((square) => square.isDark).toList();
      expect(dark, hasLength(Square.darkCount));
      expect(dark, Square.darkSquares);
      expect(dark.take(4).map((square) => square.name), [
        'a1',
        'c1',
        'e1',
        'g1',
      ]);
      expect(dark.skip(28).map((square) => square.name), [
        'b8',
        'd8',
        'f8',
        'h8',
      ]);
    });

    test('knows which squares are playable', () {
      for (final name in ['a1', 'h2', 'g3', 'f4', 'c7', 'b8']) {
        expect(Square.parse(name).isDark, isTrue, reason: name);
      }
      for (final name in ['b1', 'h1', 'a2', 'a8', 'h7']) {
        expect(Square.parse(name).isDark, isFalse, reason: name);
      }
      expect(Square.isDarkIndex(Square.parse('a1').index), isTrue);
      expect(Square.isDarkIndex(Square.parse('b1').index), isFalse);
    });

    test('numbers the playable squares in reading order', () {
      const expected = <String, int>{
        'b8': 1,
        'd8': 2,
        'f8': 3,
        'h8': 4,
        'a7': 5,
        'c7': 6,
        'e7': 7,
        'g7': 8,
        'b6': 9,
        'd6': 10,
        'f6': 11,
        'h6': 12,
        'a5': 13,
        'c5': 14,
        'e5': 15,
        'g5': 16,
        'b4': 17,
        'd4': 18,
        'f4': 19,
        'h4': 20,
        'a3': 21,
        'c3': 22,
        'e3': 23,
        'g3': 24,
        'b2': 25,
        'd2': 26,
        'f2': 27,
        'h2': 28,
        'a1': 29,
        'c1': 30,
        'e1': 31,
        'g1': 32,
      };
      expected.forEach((name, number) {
        final square = Square.parse(name);
        expect(square.number, number, reason: name);
        expect(Square.numberOf(square.index), number, reason: name);
        expect(Square.fromNumber(number).name, name);
      });
    });

    test('round trips every number from 1 to 32', () {
      final names = <String>{};
      for (var number = 1; number <= Square.darkCount; number++) {
        final square = Square.fromNumber(number);
        expect(square.number, number);
        expect(square.isDark, isTrue);
        names.add(square.name);
      }
      expect(names, hasLength(32));
    });

    test('refuses numbers outside the board', () {
      expect(() => Square.fromNumber(0), throwsRangeError);
      expect(() => Square.fromNumber(33), throwsRangeError);
    });

    test('breaks a square into a file and a rank', () {
      final h8 = Square.parse('h8');
      expect(h8.fileIndex, 7);
      expect(h8.rankIndex, 7);
      expect(h8.index, 63);
      expect(Square.fileOf(63), 7);
      expect(Square.rankOf(63), 7);
      expect(Square.indexOf(7, 7), 63);
      expect(Square.atFileRank(7, 7), h8);
      expect(Square.at(63), h8);
      expect(h8.toString(), 'h8');
    });

    test('steps diagonally without running off the board', () {
      final a1 = Square.parse('a1');
      final b2 = Square.parse('b2');
      expect(Square.step(a1.index, Square.upRight), b2.index);
      expect(Square.step(a1.index, Square.upLeft), isNull);
      expect(Square.step(a1.index, Square.downLeft), isNull);
      expect(Square.step(a1.index, Square.downRight), isNull);

      // A step off the side of the board is refused, even from a light square.
      expect(Square.step(Square.parse('h1').index, Square.upRight), isNull);
      expect(Square.step(Square.parse('a2').index, Square.upLeft), isNull);
      expect(
        Square.step(Square.parse('g1').index, Square.upRight),
        Square.parse('h2').index,
      );
      expect(
        Square.step(Square.parse('h8').index, Square.downLeft),
        Square.parse('g7').index,
      );
    });

    test('has the four diagonal steps', () {
      expect(Square.diagonals, hasLength(4));
      expect(Square.redForward, [Square.upLeft, Square.upRight]);
      expect(Square.blackForward, [Square.downLeft, Square.downRight]);
    });

    test('compares by square', () {
      expect(Square.parse('c3'), Square.atFileRank(2, 2));
      expect(Square.parse('c3').hashCode, Square.atFileRank(2, 2).hashCode);
      expect(Square.parse('c3'), isNot(Square.parse('d4')));
      // ignore: unrelated_type_equality_checks
      expect(Square.parse('c3') == Object(), isFalse);
    });

    test('is limited to the range of a board', () {
      expect(() => Square(-1), throwsA(isA<AssertionError>()));
      expect(() => Square(Square.count), throwsA(isA<AssertionError>()));
    });
  });
}
