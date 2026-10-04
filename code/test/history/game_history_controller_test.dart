// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/engine/checkers.dart';
import 'package:checkers/history/game_history_controller.dart';
import 'package:checkers/history/game_history_store.dart';
import 'package:checkers/history/game_record.dart';
import 'package:checkers/history/persistence/in_memory_game_history_store.dart';
import 'package:test/test.dart';

/// A game with a few legal moves played in it.
Game playedGame({int plies = 4}) {
  final game = Game.standard();
  for (var i = 0; i < plies && !game.isGameOver; i++) {
    final moves = game.legalMoves();
    if (moves.isEmpty) break;
    game.applyMove(moves.first);
  }
  return game;
}

/// A store that records every call made to it, and can be told to fail.
///
/// Extends rather than implements the interface so that it picks up the
/// inherited `isEphemeral`, which is the default for a store that writes
/// somewhere.
class WatchfulStore extends GameHistoryStore {
  final List<String> calls = [];
  final List<String> notations = [];

  /// The operation that should throw, if any.
  String? failingCall;

  void _record(String call) {
    calls.add(call);
    if (call == failingCall) {
      throw StateError('the database is not available');
    }
  }

  int _nextId = 1;

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  Future<List<GameSummary>> listGames() async {
    _record('listGames');
    return <GameSummary>[];
  }

  @override
  Future<GameRecord?> loadGame(int id) async {
    _record('loadGame');
    return null;
  }

  @override
  Future<int> createGame({
    required DateTime startedAt,
    required String initialFen,
    required RuleVariant variant,
  }) async {
    _record('createGame');
    return _nextId++;
  }

  @override
  Future<void> appendMove(int gameId, Move move) async {
    _record('appendMove');
    notations.add(move.notation);
  }

  @override
  Future<void> finishGame(
    int gameId, {
    required GameOutcome outcome,
    required DateTime finishedAt,
    String? termination,
  }) async => _record('finishGame');

  @override
  Future<void> deleteGame(int gameId) async => _record('deleteGame');

  @override
  Future<void> deleteAll() async => _record('deleteAll');
}

GameHistoryController controllerFor(GameHistoryStore store) =>
    GameHistoryController(Future.value(store));

void main() {
  group('a game being played', () {
    late InMemoryGameHistoryStore store;
    late GameHistoryController controller;

    setUp(() {
      store = InMemoryGameHistoryStore();
      controller = controllerFor(store);
    });

    test('is not written to until a move is played', () async {
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );

      // Somebody who opens a game and immediately restarts has played nothing.
      // Recording it would fill the history with rows reading "Unfinished,
      // 0 moves".
      expect(await store.listGames(), isEmpty);
    });

    test('records its moves', () async {
      final game = playedGame();
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );

      for (final move in game.history) {
        await controller.recordMove(move);
      }

      final games = await store.listGames();
      expect(games, hasLength(1));
      expect((await store.loadGame(games.single.id))!.moves, [
        for (final move in game.history) move.notation,
      ]);
    });

    test('records the moves in the order they were played', () async {
      final game = playedGame();
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      // Fired off without awaiting, the way the play session does it.
      for (final move in game.history) {
        controller.recordMove(move);
      }
      await controller.completeGame(outcome: GameOutcome.inProgress);

      final games = await store.listGames();
      expect((await store.loadGame(games.single.id))!.moves, [
        for (final move in game.history) move.notation,
      ]);
    });

    test('starts from the position it was begun at', () async {
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.menCaptureForwardsOnly,
      );

      await controller.recordMove(playedGame().history.first);

      final games = await store.listGames();
      final record = await store.loadGame(games.single.id);
      expect(record!.initialFen, Game.standard().fen);
      expect(record.variant, RuleVariant.menCaptureForwardsOnly);
    });

    test('records nothing if no game was begun', () async {
      await controller.recordMove(playedGame().history.first);

      expect(await store.listGames(), isEmpty);
    });

    test('is finished with how it ended', () async {
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await controller.recordMove(playedGame().history.first);

      await controller.completeGame(
        outcome: GameOutcome.blackWin,
        termination: 'Black captured all of red',
      );

      final summary = (await store.listGames()).single;
      expect(summary.outcome, GameOutcome.blackWin);
      expect(summary.outcomeLabel, 'Black won');
      expect(summary.termination, 'Black captured all of red');
    });

    test('has nothing to finish if no move was played', () async {
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );

      await controller.completeGame(outcome: GameOutcome.redWin);

      expect(await store.listGames(), isEmpty);
    });

    test('leaves the previous game in the history when restarted', () async {
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await controller.recordMove(playedGame().history.first);
      await controller.recordMove(playedGame().history.first);

      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await controller.recordMove(playedGame().history.first);

      final games = await store.listGames();
      expect(games, hasLength(2));
      // The abandoned game is left where it got to, not deleted: restarting is
      // not the same as throwing the game away.
      expect(games.map((g) => g.moveCount), [1, 2]);
      expect(
        games.every((g) => g.outcome == GameOutcome.inProgress),
        isTrue,
        reason: 'neither game was played out',
      );
    });

    test("keeps a restarted game's moves out of the abandoned one", () async {
      final game = playedGame(plies: 4);
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await controller.recordMove(game.history.first);

      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      for (final move in game.history.skip(1)) {
        await controller.recordMove(move);
      }

      final games = await store.listGames();
      final abandoned = games.firstWhere((g) => g.moveCount == 1);
      final current = games.firstWhere((g) => g.moveCount == game.ply - 1);
      expect((await store.loadGame(abandoned.id))!.moves, hasLength(1));
      expect((await store.loadGame(current.id))!.moves, hasLength(3));
    });
  });

  group('a store that is not working', () {
    late WatchfulStore store;
    late GameHistoryController controller;

    setUp(() {
      store = WatchfulStore();
      controller = controllerFor(store);
    });

    test('does not stop a move from being recorded', () async {
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      store.failingCall = 'createGame';

      await expectLater(
        controller.recordMove(playedGame().history.first),
        completes,
      );
    });

    test('does not stop the next move from being recorded either', () async {
      final move = playedGame().history.first;
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await controller.recordMove(move);

      store.failingCall = 'appendMove';
      await controller.recordMove(move);
      store.failingCall = null;
      await controller.recordMove(move);

      // The middle move is lost, but the third still got through: one failed
      // write does not wedge the chain of writes shut.
      expect(store.notations, [move.notation, move.notation]);
    });

    test('does not stop the game from being finished', () async {
      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await controller.recordMove(playedGame().history.first);
      store.failingCall = 'finishGame';

      await expectLater(
        controller.completeGame(outcome: GameOutcome.redWin),
        completes,
      );
    });

    test('answers an unreadable list with no games', () async {
      store.failingCall = 'listGames';

      // Not null: the history screen has to draw something either way, and
      // "no games" is something it can draw.
      expect(await controller.games(), isEmpty);
    });

    test('answers an unreadable game with nothing to replay', () async {
      store.failingCall = 'loadGame';

      expect(await controller.game(1), isNull);
    });

    test('lets a deletion fail without taking the screen down', () async {
      store.failingCall = 'deleteGame';

      await expectLater(controller.deleteGame(1), completes);
    });
  });

  group('a store that answers no reads', () {
    test('says it is not keeping anything', () async {
      final store = InMemoryGameHistoryStore();

      expect(await controllerFor(store).isEphemeral, isTrue);
    });

    test('a store that writes to disk says it is keeping them', () async {
      expect(await controllerFor(WatchfulStore()).isEphemeral, isFalse);
    });
  });

  group('writes', () {
    test('wait for the one before them', () async {
      final store = WatchfulStore();
      final controller = controllerFor(store);
      final game = playedGame();

      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      // Fired without awaiting, exactly as the play session does when a player
      // taps two squares in quick succession.
      for (final move in game.history) {
        controller.recordMove(move);
      }
      await controller.completeGame(outcome: GameOutcome.inProgress);

      // The row has to be created before the move that goes into it, or the
      // move has nowhere to land.
      expect(store.calls, [
        'createGame',
        for (var i = 0; i < game.ply; i++) 'appendMove',
        'finishGame',
      ]);
    });

    test('read back in the order the game was played', () async {
      final store = WatchfulStore();
      final controller = controllerFor(store);
      final game = playedGame();

      controller.beginGame(
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      for (final move in game.history) {
        controller.recordMove(move);
      }
      await controller.completeGame(outcome: GameOutcome.inProgress);

      expect(store.notations, [for (final move in game.history) move.notation]);
    });
  });
}
