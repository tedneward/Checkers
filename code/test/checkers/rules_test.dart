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

  group('RuleVariant', () {
    test('plays the American rule unless the player picks otherwise', () {
      // A player who never opens Settings must get exactly the game they got
      // before the variant existed, so the default has to be the default rules.
      expect(RuleVariant.defaultVariant.rules, Rules.american);
      expect(RuleVariant.defaultVariant, RuleVariant.values.first);
    });

    test('offers at least two ways of playing', () {
      expect(RuleVariant.choices, RuleVariant.values);
      expect(RuleVariant.choices.length, greaterThanOrEqualTo(2));
      // The variants have to actually differ, or the choice is a decoration.
      expect(
        RuleVariant.choices.map((variant) => variant.rules).toSet().length,
        RuleVariant.choices.length,
      );
    });

    test('holds a man to the forwards diagonals in one of them', () {
      const forwardsOnly = RuleVariant.menCaptureForwardsOnly;
      expect(forwardsOnly.rules.menCaptureBackward, isFalse);
      // 14 is c5 and 9 is b6, so jumping b6 carries a black man towards rank 8.
      expect(movesOf('B:W9:B14', rules: forwardsOnly.rules), [
        'c5-b4',
        'c5-d4',
      ]);
      // And in the other it is that jump which the man is allowed.
      expect(movesOf('B:W9:B14', rules: RuleVariant.defaultVariant.rules), [
        'c5xa7',
      ]);
    });

    test('lets a crowned king jump backwards whichever way of playing', () {
      // Crowning, not the variant, is what buys a piece the backwards jump.
      for (final variant in RuleVariant.choices) {
        expect(movesOf('B:W9:BK14', rules: variant.rules), [
          'c5xa7',
        ], reason: 'the king should jump backwards under $variant');
      }
    });

    test('describes each choice in words a player can act on', () {
      for (final variant in RuleVariant.choices) {
        expect(variant.label, isNotEmpty, reason: '$variant needs a label');
        expect(
          variant.description,
          isNotEmpty,
          reason: '$variant needs a description',
        );
        // The label is what lands in the settings list, so it has to be short
        // enough to sit on one line next to an icon.
        expect(variant.label.length, lessThanOrEqualTo(40));
      }
      // Two different names, or the settings row could not tell them apart.
      final labels = RuleVariant.choices
          .map((variant) => variant.label)
          .toSet();
      expect(labels.length, RuleVariant.choices.length);
    });

    test('is handed straight to a game', () {
      // The app builds its game with a variant's rules, and the game has to
      // keep them. If it only borrowed them for move generation and judged the
      // finish under different rules, the two halves of the engine would
      // disagree about the same game.
      for (final variant in RuleVariant.choices) {
        expect(Game.standard(rules: variant.rules).rules, variant.rules);
      }
    });

    test('names a game by the rules it is being played under', () {
      for (final variant in RuleVariant.choices) {
        expect(RuleVariant.find(variant.rules), variant);
      }
      // A game can also be created with rules no variant describes, and then
      // there is no honest name for it, which is better than the wrong one.
      expect(RuleVariant.find(const Rules(mustCapture: false)), isNull);
      expect(RuleVariant.find(Rules.optionalMaximumCapture), isNull);
    });

    test('reads a stored name back as the same variant', () {
      for (final variant in RuleVariant.choices) {
        expect(RuleVariant.fromName(variant.name), variant);
      }
    });

    test('falls back to the default for a name it does not recognise', () {
      // Storage outlives the build that wrote it, so a variant that has been
      // renamed or removed, or a value that was never one, must not throw.
      expect(RuleVariant.fromName('kingTakesAges'), RuleVariant.defaultVariant);
      expect(RuleVariant.fromName(''), RuleVariant.defaultVariant);
      expect(RuleVariant.fromName(null), RuleVariant.defaultVariant);
    });

    test('reads as its label when printed', () {
      for (final variant in RuleVariant.choices) {
        expect(variant.toString(), variant.label);
      }
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
