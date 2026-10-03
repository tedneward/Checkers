// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:flutter_test/flutter_test.dart';

/// The moves the side to move has in [position], written out and sorted.
List<String> movesOf(String position, {Rules rules = Rules.american}) {
  final side = Side.fromNotationLetter(position.split(':').first);
  return MoveGenerator(
    Board.fromPosition(position),
    side,
    rules,
  ).generate().map((move) => move.notation).toList()..sort();
}

void main() {
  group('Rules', () {
    test('is the American rule by default', () {
      const rules = Rules();
      expect(rules, Rules.american);
      expect(rules.mustCapture, isTrue);
      expect(rules.mustCaptureMaximum, isTrue);
      expect(rules.menCaptureBackward, isTrue);
      expect(rules.longRangedKings, isTrue);
      expect(rules.promoteOnArrival, isTrue);
      expect(rules.promoteOnPassThrough, isFalse);
      expect(rules.autoDeclareMaterialEnd, isTrue);
      expect(rules.toString(), contains('menBackward: true'));
    });

    test('offers the variations it knows about', () {
      expect(Rules.british.menCaptureBackward, isFalse);
      expect(Rules.british.mustCapture, isTrue);
      expect(Rules.optionalMaximumCapture.mustCaptureMaximum, isFalse);
      expect(Rules.optionalMaximumCapture.mustCapture, isTrue);
    });

    test('compares by every rule it holds', () {
      expect(Rules(), const Rules());
      expect(Rules(), isNot(const Rules(mustCapture: false)));
      expect(Rules().hashCode, const Rules().hashCode);
      expect(const Rules(), isNot(Object()));
    });

    test('knows which rank crowns a man', () {
      const rules = Rules.american;
      expect(rules.crownsManOnArrival(Side.red, 7), isTrue);
      expect(rules.crownsManOnArrival(Side.red, 0), isFalse);
      expect(rules.crownsManOnArrival(Side.black, 0), isTrue);
      expect(rules.crownsManOnArrival(Side.black, 7), isFalse);
      // With promotion on arrival turned off, no square crowns anybody.
      const none = Rules(promoteOnArrival: false);
      expect(none.crownsManOnArrival(Side.red, 7), isFalse);
    });

    test('crowns a man that jumps back off the far rank', () {
      // The man on b8 has not been crowned, which only the rules below allow.
      const noArrival = Rules(promoteOnArrival: false);
      expect(movesOf('W:W1:B6', rules: noArrival), ['b8xd6']);
      expect(
        movesOf(
          'W:W1:B6',
          rules: const Rules(
            promoteOnArrival: false,
            promoteOnPassThrough: true,
          ),
        ),
        ['b8xd6*'],
      );
    });
  });

  group('DrawRules', () {
    test('is the American rule by default', () {
      const rules = DrawRules();
      expect(rules, DrawRules.american);
      expect(rules.repetitionLimit, 3);
      expect(rules.quietMoveLimit, 50);
      expect(DrawRules.none.repetitionLimit, 0);
      expect(DrawRules.none.quietMoveLimit, 0);
      expect(rules.toString(), contains('repetition: 3'));
    });

    test('compares by the limits it holds', () {
      expect(DrawRules(), const DrawRules());
      expect(DrawRules(), isNot(const DrawRules(repetitionLimit: 2)));
      expect(DrawRules().hashCode, const DrawRules().hashCode);
      expect(const DrawRules(), isNot(Object()));
    });
  });
}
