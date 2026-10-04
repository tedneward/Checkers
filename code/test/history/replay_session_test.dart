// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:checkers/history/game_record.dart';
import 'package:checkers/history/replay_session.dart';
import 'package:test/test.dart';

/// Plays [plies] legal moves from the opening, taking the lowest-numbered legal
/// move each turn.
///
/// Real moves rather than written-out notation, so that a change to the engine
/// cannot quietly turn a valid test game into an invalid one. Deterministic,
/// because the move list is sorted by the generator, so the same game comes out
/// every run.
Game playOpening({int plies = 6}) {
  final game = Game.standard();
  for (var i = 0; i < plies && !game.isGameOver; i++) {
    final moves = game.legalMoves();
    if (moves.isEmpty) break;
    game.applyMove(moves.first);
  }
  return game;
}

/// A position with a red man on [red] and a black man on [black], red to move.
Game positionWith({required String red, required String black, Rules? rules}) =>
    Game.position(
      Board.fromPosition(
        'W:W${Square.parse(red).number}:B${Square.parse(black).number}',
      ),
      sideToMove: Side.red,
      rules: rules ?? Rules.american,
    );

/// A record of [game] as the store would hand it back after it was played.
GameRecord recordOf(
  Game game, {
  int id = 1,
  RuleVariant variant = RuleVariant.defaultVariant,
  GameOutcome outcome = GameOutcome.inProgress,
  List<String>? moves,
  String? initialFen,
}) => GameRecord(
  id: id,
  startedAt: DateTime(2026, 10, 2, 19, 34),
  finishedAt: DateTime(2026, 10, 2, 19, 51),
  variant: variant,
  outcome: outcome,
  termination: null,
  moveCount: game.ply,
  initialFen: initialFen ?? Game.standard().fen,
  moves: moves ?? [for (final move in game.history) move.notation],
);

void main() {
  group('a recorded game', () {
    final played = playOpening();
    final record = recordOf(played);

    test('starts at the position it was played from', () {
      final session = ReplaySession(record);

      expect(session.ply, 0);
      expect(session.isAtStart, isTrue);
      expect(session.isAtEnd, isFalse);
      expect(session.board, Game.standard().board);
      expect(session.lastMove, isNull);
    });

    test('steps forwards a move at a time', () {
      final session = ReplaySession(record);

      for (var expected = 1; expected <= record.moves.length; expected++) {
        expect(session.forward(), isTrue, reason: 'move $expected');
        expect(session.ply, expected);
      }

      expect(session.isAtEnd, isTrue);
      expect(session.canGoForward, isFalse);
    });

    test('reaches the position the game finished in', () {
      final session = ReplaySession(record);
      session.goTo(record.moves.length);

      // The point of replaying through the engine rather than rebuilding from
      // move text: what is shown is the position the rules produce.
      expect(session.board.toPosition(), played.board.toPosition());
      expect(session.sideToMove, played.sideToMove);
    });

    test('steps backwards a move at a time', () {
      final session = ReplaySession(record);
      session.goTo(record.moves.length);

      for (var expected = record.moves.length - 1; expected >= 0; expected--) {
        expect(session.back(), isTrue, reason: 'back to ply $expected');
        expect(session.ply, expected);
      }

      expect(session.isAtStart, isTrue);
      expect(session.canGoBack, isFalse);
      expect(session.lastMove, isNull);
    });

    test('returns to the same position when stepped away and back', () {
      final session = ReplaySession(record);

      session.goTo(4);
      final midway = session.board.toPosition();
      session.goTo(1);
      session.goTo(4);

      expect(session.board.toPosition(), midway);
    });

    test('jumps to an arbitrary ply', () {
      final session = ReplaySession(record);

      session.goTo(3);

      expect(session.ply, 3);
      expect(session.canGoBack, isTrue);
      expect(session.canGoForward, isTrue);
    });

    test('stops at the end when asked to go past it', () {
      final session = ReplaySession(record);

      session.goTo(record.moves.length + 5);

      expect(session.ply, record.moves.length);
    });

    test('stops at the start when asked to go before it', () {
      final session = ReplaySession(record);
      session.goTo(3);

      session.goTo(-4);

      expect(session.ply, 0);
    });

    test('marks the move currently on the board', () {
      final session = ReplaySession(record);
      session.goTo(2);

      expect(session.isCurrentPly(1), isTrue);
      expect(session.isCurrentPly(0), isFalse);
      expect(session.isCurrentPly(2), isFalse);
    });

    test('names the move that led to the position on the board', () {
      final session = ReplaySession(record);
      session.goTo(2);

      expect(session.lastMove?.notation, record.moves[1]);
    });

    test('hands back the notation of every recorded move', () {
      final session = ReplaySession(record);

      for (var i = 0; i < record.moves.length; i++) {
        expect(session.moveNotationAt(i), record.moves[i]);
      }
      expect(session.moveNotationAt(-1), isNull);
      expect(session.moveNotationAt(record.moves.length), isNull);
    });

    test('is not truncated when every move replays', () {
      final session = ReplaySession(record);
      session.goTo(record.moves.length);

      expect(session.isTruncated, isFalse);
    });

    test('replays the same way every time it is started', () {
      final first = ReplaySession(record)..goTo(3);
      final second = ReplaySession(record)..goTo(3);

      expect(second.board.toPosition(), first.board.toPosition());
    });
  });

  group('a game with no moves', () {
    final record = recordOf(Game.standard());

    test('cannot be stepped in either direction', () {
      final session = ReplaySession(record);

      expect(session.canGoForward, isFalse);
      expect(session.canGoBack, isFalse);
      expect(session.forward(), isFalse);
      expect(session.back(), isFalse);
    });

    test('shows the opening position', () {
      expect(ReplaySession(record).board, Game.standard().board);
    });
  });

  group('a stored move that is not a move', () {
    // Text that never came from the engine, which is what a corrupted database
    // looks like. Replaying it must not throw out of the screen.
    final played = playOpening();
    final record = recordOf(
      played,
      moves: [...played.history.map((m) => m.notation).take(2), 'not a move'],
    );

    test('stops at the unreadable move', () {
      final session = ReplaySession(record);

      expect(session.forward(), isTrue);
      expect(session.forward(), isTrue);
      expect(session.forward(), isFalse);

      expect(session.ply, 2);
    });

    test('says it could not be replayed in full', () {
      final session = ReplaySession(record)..goTo(3);

      expect(session.isTruncated, isTrue);
    });
  });

  group('a stored move the rules no longer accept', () {
    // Well-formed notation naming a move that is illegal in that position,
    // which is what a game recorded under different rules looks like. `h8` is
    // empty, so black has no piece that could move from it.
    final played = playOpening();
    final legal = played.history.map((m) => m.notation).toList();
    const bogus = 'h8-g7';
    final record = recordOf(
      played,
      moves: [legal[0], legal[1], bogus, legal[3]],
    );

    // Where the game really was after the moves that do work, which is what the
    // replay should be showing once it reaches the bad one.
    final expected = Game.standard();
    expected.applyMove(expected.parseMove(legal[0]));
    expected.applyMove(expected.parseMove(legal[1]));

    test('the replacement really is a move that cannot be played', () {
      // Guards the tests below. If `h8-g7` ever became legal they would pass
      // for the wrong reason, quietly testing nothing.
      expect(
        () => expected.parseMove(bogus),
        throwsA(isA<IllegalMoveException>()),
      );
      expect(legal, isNot(contains(bogus)));
    });

    test('stops at the illegal move', () {
      final session = ReplaySession(record);

      expect(session.forward(), isTrue);
      expect(session.forward(), isTrue);
      expect(session.forward(), isFalse);

      expect(session.ply, 2);
    });

    test('says how much of the game could be replayed', () {
      final session = ReplaySession(record)..goTo(4);

      expect(session.isTruncated, isTrue);
      expect(session.playablePlies, 2);
      expect(session.ply, 2);
    });

    test('leaves the moves before the illegal one viewable', () {
      final session = ReplaySession(record)..goTo(2);

      expect(session.board.toPosition(), expected.board.toPosition());
    });

    test('refuses to move on once the illegal move has been found', () {
      final session = ReplaySession(record)..goTo(4);

      expect(session.forward(), isFalse);
      expect(session.ply, 2);
    });

    test('can still be taken back from the illegal move', () {
      final session = ReplaySession(record)..goTo(4);
      session.goTo(1);

      expect(session.ply, 1);
    });
  });

  group('a game recorded under a rule variant', () {
    // Red man on c5, black man on b4. Jumping b4 lands on a3, which is
    // backwards, so the move exists under American rules and not under the
    // variant where men only jump forwards.
    final american = positionWith(red: 'c5', black: 'b4');
    final openingFen = american.fen;
    final capture = american.legalMoves().firstWhere((m) => m.isCapture);
    american.applyMove(capture);

    test('the position offers exactly the backwards jump being tested', () {
      // Guards the two tests below: if the engine's rules ever changed such
      // that this capture stopped existing, they would pass for the wrong
      // reason.
      expect(american.history, hasLength(1));
      expect(capture.isCapture, isTrue);
      expect(capture.to.rankIndex, lessThan(capture.from.rankIndex));
    });

    test('replays under the variant it was played under', () {
      final record = recordOf(
        american,
        variant: RuleVariant.menCaptureAnyDirection,
        initialFen: openingFen,
      );

      final session = ReplaySession(record)..goTo(1);

      expect(session.isTruncated, isFalse);
      expect(session.board.toPosition(), american.board.toPosition());
    });

    test('refuses a move the recorded variant does not allow', () {
      final record = recordOf(
        american,
        variant: RuleVariant.menCaptureForwardsOnly,
        initialFen: openingFen,
      );

      final session = ReplaySession(record);

      expect(session.forward(), isFalse);
      expect(session.isTruncated, isTrue);
    });
  });
}
