// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:checkers/engine/checkers.dart';
import 'package:checkers/history/persistence/sqlite_game_history_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

/// A game with [plies] legal moves played in it.
Game playedGame({int plies = 4}) {
  final game = Game.standard();
  for (var i = 0; i < plies && !game.isGameOver; i++) {
    final moves = game.legalMoves();
    if (moves.isEmpty) break;
    game.applyMove(moves.first);
  }
  return game;
}

/// A fresh store backed by a real SQLite database in a temporary directory.
///
/// Not a fake: the schema, the foreign keys, the cascade and the ordering are
/// all the thing under test, and none of that is in Dart.
Future<(SqliteGameHistoryStore, Directory)> openStore() async {
  final directory = await Directory.systemTemp.createTemp('checkers_history');
  final store = SqliteGameHistoryStore(
    factoryOverride: databaseFactoryFfi,
    fileName: '${directory.path}/history.db',
  );
  await store.open();
  return (store, directory);
}

/// Counts the rows in [table] by opening a second connection to the file.
///
/// A second handle is the only honest way to check the cascade: the store does
/// not expose its database, and the point of the test is what is on disk.
///
/// `singleInstance: false` matters. Left at its default, the FFI factory hands
/// back the store's own open database for a second open of the same path, and
/// closing this "separate" handle would close the store out from under it.
Future<int> countRows(Directory directory, String table) async {
  final db = await openSecondHandle(directory);
  try {
    final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM $table');
    return rows.first['n']! as int;
  } finally {
    await db.close();
  }
}

/// Opens a second connection to the file, for a test that has to write a row the
/// store would never write itself.
Future<Database> openSecondHandle(Directory directory) =>
    databaseFactoryFfi.openDatabase(
      '${directory.path}/history.db',
      options: OpenDatabaseOptions(singleInstance: false),
    );

void main() {
  setUpAll(sqfliteFfiInit);

  group('a game that has been recorded', () {
    late SqliteGameHistoryStore store;
    late Directory directory;

    setUp(() async {
      (store, directory) = await openStore();
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    test('is listed as unfinished with no moves', () async {
      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2, 19, 34),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );

      final games = await store.listGames();

      expect(games, hasLength(1));
      expect(games.single.id, id);
      expect(games.single.outcome, GameOutcome.inProgress);
      expect(games.single.outcomeLabel, 'Unfinished');
      expect(games.single.moveCount, 0);
      expect(games.single.termination, isNull);
    });

    test('remembers when it began', () async {
      final startedAt = DateTime(2026, 10, 2, 19, 34);

      await store.createGame(
        startedAt: startedAt,
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );

      expect((await store.listGames()).single.startedAt, startedAt);
    });

    test('records every move in the order it was played', () async {
      final game = playedGame();
      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      for (final move in game.history) {
        await store.appendMove(id, move);
      }

      final record = await store.loadGame(id);

      expect(record!.moves, [for (final move in game.history) move.notation]);
      expect(record.moveCount, game.history.length);
      // The position it is replayed from has to be the opening, not wherever
      // the game happened to finish.
      expect(record.initialFen, Game.standard().fen);
    });

    test('is finished by recording how it ended', () async {
      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );

      await store.finishGame(
        id,
        outcome: GameOutcome.redWin,
        finishedAt: DateTime(2026, 10, 2, 19, 51),
        termination: 'Red captured all of black',
      );

      final summary = (await store.listGames()).single;
      expect(summary.outcome, GameOutcome.redWin);
      expect(summary.outcomeLabel, 'Red won');
      expect(summary.winner, Side.red);
      expect(summary.termination, 'Red captured all of black');
      expect(summary.finishedAt, DateTime(2026, 10, 2, 19, 51));
    });

    test('names the winner of a drawn game as nobody', () async {
      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await store.finishGame(
        id,
        outcome: GameOutcome.draw,
        finishedAt: DateTime(2026, 10, 2),
      );

      final summary = (await store.listGames()).single;
      expect(summary.outcomeLabel, 'Draw');
      expect(summary.winner, isNull);
    });

    test('can be finished twice, keeping the latest result', () async {
      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );

      await store.finishGame(
        id,
        outcome: GameOutcome.inProgress,
        finishedAt: DateTime(2026, 10, 2),
      );
      await store.finishGame(
        id,
        outcome: GameOutcome.blackWin,
        finishedAt: DateTime(2026, 10, 3),
      );

      expect((await store.listGames()).single.outcome, GameOutcome.blackWin);
    });

    test('remembers the rule variant it was played under', () async {
      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.menCaptureForwardsOnly,
      );

      expect(
        (await store.loadGame(id))!.variant,
        RuleVariant.menCaptureForwardsOnly,
      );
    });

    test('is not found by an identifier it never had', () async {
      expect(await store.loadGame(404), isNull);
    });

    test('keeps games apart by identifier', () async {
      final game = playedGame();
      final first = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      final second = await store.createGame(
        startedAt: DateTime(2026, 10, 3),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await store.appendMove(second, game.history.first);

      expect((await store.loadGame(first))!.moves, isEmpty);
      expect((await store.loadGame(second))!.moves, hasLength(1));
    });
  });

  group('the list of recorded games', () {
    late SqliteGameHistoryStore store;
    late Directory directory;

    setUp(() async {
      (store, directory) = await openStore();
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    Future<int> recordAt(DateTime when) async {
      final id = await store.createGame(
        startedAt: when,
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await store.finishGame(
        id,
        outcome: GameOutcome.inProgress,
        finishedAt: when,
      );
      return id;
    }

    test('is empty to begin with', () async {
      expect(await store.listGames(), isEmpty);
    });

    test('puts the most recently played game first', () async {
      await recordAt(DateTime(2026, 10, 1, 9));
      await recordAt(DateTime(2026, 10, 3, 9));
      await recordAt(DateTime(2026, 10, 2, 9));

      final times = [for (final g in await store.listGames()) g.startedAt];

      expect(times, [
        DateTime(2026, 10, 3, 9),
        DateTime(2026, 10, 2, 9),
        DateTime(2026, 10, 1, 9),
      ]);
    });

    test('counts the moves of each game', () async {
      final game = playedGame();
      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      for (final move in game.history) {
        await store.appendMove(id, move);
      }
      await recordAt(DateTime(2026, 10, 3));

      final games = await store.listGames();

      // Most recently touched comes first.
      expect(games.first.moveCount, game.history.length);
      expect(games.last.moveCount, 0);
    });

    test('moves a game to the top as it is played', () async {
      // Somebody part-way through a game is the one most likely to come back to
      // it, so the list is ordered by when a game was last touched rather than
      // when it began. Times are relative to now because recording a move
      // stamps the game with the current clock, and a test written with fixed
      // dates would start failing on a machine whose clock had passed them.
      final now = DateTime.now();
      final older = await recordAt(now.subtract(const Duration(hours: 2)));
      await recordAt(now.subtract(const Duration(hours: 1)));
      expect((await store.listGames()).first.id, isNot(older));

      await store.appendMove(older, playedGame().history.first);

      expect((await store.listGames()).first.id, older);
    });
  });

  group('deleting', () {
    late SqliteGameHistoryStore store;
    late Directory directory;

    setUp(() async {
      (store, directory) = await openStore();
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    Future<int> recordGameWithMoves() async {
      final game = playedGame();
      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      for (final move in game.history) {
        await store.appendMove(id, move);
      }
      return id;
    }

    test('removes one game and leaves the others', () async {
      final doomed = await recordGameWithMoves();
      await recordGameWithMoves();

      await store.deleteGame(doomed);

      final games = await store.listGames();
      expect(games, hasLength(1));
      expect(games.single.id, isNot(doomed));
    });

    test('takes the moves of the deleted game with it', () async {
      // The rows would sit there forever otherwise, invisible and unread, if
      // the foreign key cascade were not working.
      final id = await recordGameWithMoves();
      expect(await countRows(directory, 'moves'), greaterThan(0));

      await store.deleteGame(id);

      expect(await countRows(directory, 'moves'), 0);
    });

    test('does nothing for a game that is not there', () async {
      await recordGameWithMoves();

      await store.deleteGame(9999);

      expect(await store.listGames(), hasLength(1));
    });

    test('removes every game and every move', () async {
      await recordGameWithMoves();
      await recordGameWithMoves();

      await store.deleteAll();

      expect(await store.listGames(), isEmpty);
      expect(await countRows(directory, 'games'), 0);
      expect(await countRows(directory, 'moves'), 0);
    });

    test('leaves the history usable afterwards', () async {
      await recordGameWithMoves();

      await store.deleteAll();
      await recordGameWithMoves();

      expect(await store.listGames(), hasLength(1));
      expect(await countRows(directory, 'moves'), greaterThan(0));
    });

    test(
      'does not hand a deleted game its identifier to the next one',
      () async {
        // Otherwise a replay screen still on the stack, holding an identifier,
        // could quietly start showing somebody else's game.
        final first = await recordGameWithMoves();
        await store.deleteGame(first);

        final second = await recordGameWithMoves();

        expect(second, isNot(first));
      },
    );
  });

  group('a database written by a build that knew more', () {
    late SqliteGameHistoryStore store;
    late Directory directory;

    setUp(() async {
      (store, directory) = await openStore();
    });

    tearDown(() async {
      await store.close();
      await directory.delete(recursive: true);
    });

    test('reads an outcome it has not heard of as unfinished', () async {
      final db = await openSecondHandle(directory);
      await db.insert('games', {
        'id': 1,
        'started_at': DateTime(2026, 10, 2).millisecondsSinceEpoch,
        'finished_at': DateTime(2026, 10, 2).millisecondsSinceEpoch,
        'variant': 'aVariantFromTheFuture',
        'outcome': 'resignedByNobody',
        'termination': null,
        'initial_fen': Game.standard().fen,
      });
      await db.close();

      final summary = (await store.listGames()).single;

      // A stored database outlives the build that wrote it. A name this
      // version does not know must not take the history screen down with it.
      expect(summary.outcome, GameOutcome.inProgress);
      expect(summary.variant, RuleVariant.defaultVariant);
    });
  });

  group('opening', () {
    test('can be opened more than once', () async {
      final (store, directory) = await openStore();
      addTearDown(() async {
        await store.close();
        await directory.delete(recursive: true);
      });

      await store.open();
      await store.open();

      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );

      expect(await store.loadGame(id), isNotNull);
    });

    test('finds games left by a previous session', () async {
      final (store, directory) = await openStore();
      final id = await store.createGame(
        startedAt: DateTime(2026, 10, 2),
        initialFen: Game.standard().fen,
        variant: RuleVariant.defaultVariant,
      );
      await store.appendMove(id, playedGame().history.first);
      await store.close();

      final reopened = SqliteGameHistoryStore(
        factoryOverride: databaseFactoryFfi,
        fileName: '${directory.path}/history.db',
      );
      await reopened.open();
      addTearDown(() async {
        await reopened.close();
        await directory.delete(recursive: true);
      });

      final record = await reopened.loadGame(id);
      expect(record!.moves, hasLength(1));
    });
  });
}
