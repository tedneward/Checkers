// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:sqflite/sqflite.dart';

import '../../engine/checkers.dart';
import '../game_history_store.dart';
import '../game_record.dart';
import 'database_factory.dart';

/// The name of the database file inside the app's documents directory.
const String historyDatabaseFileName = 'checkers_history.db';

/// A [GameHistoryStore] backed by a SQLite database.
///
/// One table per thing rather than a single table with the moves packed into a
/// string. A game can run to a hundred moves, and the history list shows every
/// game the player has ever played; reading all of those move lists to draw a
/// list of dates would make the screen slower the more they played, which is
/// exactly backwards.
class SqliteGameHistoryStore extends GameHistoryStore {
  /// Creates a store reading and writing the history database.
  ///
  /// [fileName] and [factory] exist so that tests can point a real SQLite
  /// database at a temporary file instead of the player's actual history.
  SqliteGameHistoryStore({
    this.fileName = historyDatabaseFileName,
    this.factoryOverride,
  });

  /// The name of the database file to open.
  final String fileName;

  /// The SQLite implementation to use, or `null` to pick the right one for the
  /// platform the app is running on.
  final DatabaseFactory? factoryOverride;

  Database? _database;

  /// The memo for the in-flight open, so that two callers racing to open the
  /// history share one attempt rather than opening the file twice.
  Future<Database>? _opening;

  /// The schema version. Bump this, and add a branch to [_migrate], whenever the
  /// tables below change.
  static const int _schemaVersion = 1;

  @override
  Future<void> open() async {
    if (_database != null) return;
    _opening ??= _openDatabase();
    try {
      _database = await _opening;
    } finally {
      // Whether it opened or threw, the next attempt should try again rather
      // than re-await a settled failure forever.
      _opening = null;
    }
  }

  @override
  Future<void> close() async {
    final database = _database;
    _database = null;
    await database?.close();
  }

  Future<Database> _openDatabase() async {
    final path = await databasePathForPlatform(fileName);
    return (await (factoryOverride ?? databaseFactoryForPlatform())
        .openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: _schemaVersion,
            onConfigure: _configure,
            onCreate: (db, version) async => _createSchema(db),
            onUpgrade: (db, from, to) async => _migrate(db, from, to),
          ),
        ));
  }

  /// Turns on the foreign keys that make deleting a game delete its moves.
  ///
  /// SQLite has these off by default because they cost a little on every write,
  /// and they are off in each new connection. Without this, deleting a game
  /// would leave its moves behind forever, invisible but taking up space.
  static Future<void> _configure(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _createSchema(Database db) async {
    await db.execute('''
      CREATE TABLE games (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        finished_at INTEGER NOT NULL,
        variant TEXT NOT NULL,
        outcome TEXT NOT NULL,
        termination TEXT,
        initial_fen TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE moves (
        game_id INTEGER NOT NULL,
        ply INTEGER NOT NULL,
        notation TEXT NOT NULL,
        PRIMARY KEY (game_id, ply),
        FOREIGN KEY (game_id) REFERENCES games(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX games_by_finished_at '
      'ON games (finished_at DESC)',
    );
  }

  /// Brings an older database up to [_schemaVersion].
  ///
  /// There is only version 1 so far, so there is nothing to migrate from. The
  /// branch is written out anyway because the next schema change will need one,
  /// and an empty `else` here would look like a bug rather than a placeholder.
  static Future<void> _migrate(Database db, int from, int to) async {
    if (from < 1) {
      // Nothing precedes version 1, so this only happens for a database that
      // claims to be older than the first schema this build knows how to read,
      // which is not a real case. Rebuilding it is the safe answer.
      await db.execute('DROP TABLE IF EXISTS moves');
      await db.execute('DROP TABLE IF EXISTS games');
      await _createSchema(db);
    }
    // Later migrations step from here, one version at a time.
  }

  /// The open database, opening it first if that has not happened yet.
  Future<Database> get _db async {
    if (_database == null) await open();
    return _database!;
  }

  @override
  Future<List<GameSummary>> listGames() async {
    final db = await _db;
    final rows = await db.rawQuery('''
      SELECT g.id, g.started_at, g.finished_at, g.variant, g.outcome,
             g.termination,
             (SELECT COUNT(*) FROM moves m WHERE m.game_id = g.id) AS move_count
      FROM games g
      ORDER BY g.finished_at DESC, g.id DESC
    ''');
    return [for (final row in rows) _summaryFrom(row)];
  }

  @override
  Future<GameRecord?> loadGame(int id) async {
    final db = await _db;
    final rows = await db.query(
      'games',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final moveRows = await db.query(
      'moves',
      where: 'game_id = ?',
      whereArgs: [id],
      orderBy: 'ply ASC',
    );

    final row = rows.first;
    final moves = [for (final move in moveRows) move['notation']! as String];
    return GameRecord(
      id: row['id']! as int,
      startedAt: _dateFrom(row['started_at']),
      finishedAt: _dateFrom(row['finished_at']),
      variant: RuleVariant.fromName(row['variant'] as String?),
      outcome: _outcomeFrom(row['outcome']),
      termination: row['termination'] as String?,
      moveCount: moves.length,
      initialFen: row['initial_fen']! as String,
      moves: moves,
    );
  }

  @override
  Future<int> createGame({
    required DateTime startedAt,
    required String initialFen,
    required RuleVariant variant,
    String? redPlayerName,
    String? blackPlayerName,
  }) async {
    final db = await _db;
    return db.insert('games', {
      'started_at': startedAt.millisecondsSinceEpoch,
      'finished_at': startedAt.millisecondsSinceEpoch,
      // By name, like the saved rule variant, so that a database written by a
      // build offering different variants still reads back correctly.
      'variant': variant.name,
      'outcome': GameOutcome.inProgress.name,
      'termination': null,
      'initial_fen': initialFen,
    });
  }

  @override
  Future<void> appendMove(int gameId, Move move) async {
    final db = await _db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      // The ply is worked out by the database rather than kept in Dart, so
      // that it cannot disagree with what is actually in the table. The move
      // and the game's last-played time move together, because the history list
      // is ordered by when a game was last touched, and a game someone is
      // halfway through is one they are most likely to come back to.
      await txn.rawInsert(
        '''
          INSERT INTO moves (game_id, ply, notation)
          SELECT ?, COALESCE(MAX(ply) + 1, 0), ? FROM moves WHERE game_id = ?
        ''',
        [gameId, move.notation, gameId],
      );
      await txn.update(
        'games',
        {'finished_at': now},
        where: 'id = ?',
        whereArgs: [gameId],
      );
    });
  }

  @override
  Future<void> finishGame(
    int gameId, {
    required GameOutcome outcome,
    required DateTime finishedAt,
    String? termination,
  }) async {
    final db = await _db;
    await db.update(
      'games',
      {
        'outcome': outcome.name,
        'termination': termination,
        'finished_at': finishedAt.millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [gameId],
    );
  }

  @override
  Future<void> deleteGame(int gameId) async {
    final db = await _db;
    // The moves go too. `PRAGMA foreign_keys` is on, so the cascade does it, and
    // doing it by hand as well would just be a second chance to be wrong.
    await db.delete('games', where: 'id = ?', whereArgs: [gameId]);
  }

  @override
  Future<void> deleteAll() async {
    final db = await _db;
    // `deleteAll` is offered as wiping the whole database, so this empties both
    // tables rather than dropping them. A player who cancels has not lost the
    // table definitions, and the next game records as normal.
    await db.transaction((txn) async {
      await txn.delete('moves');
      await txn.delete('games');
    });
  }

  static GameSummary _summaryFrom(Map<String, Object?> row) => GameSummary(
    id: row['id']! as int,
    startedAt: _dateFrom(row['started_at']),
    finishedAt: _dateFrom(row['finished_at']),
    variant: RuleVariant.fromName(row['variant'] as String?),
    outcome: _outcomeFrom(row['outcome']),
    termination: row['termination'] as String?,
    moveCount: row['move_count']! as int,
  );

  static DateTime _dateFrom(Object? millis) =>
      DateTime.fromMillisecondsSinceEpoch(millis! as int);

  /// The outcome named [name], or [GameOutcome.inProgress] if it is not one
  /// this build knows.
  ///
  /// A stored database outlives the build that wrote it, so an outcome this
  /// version has never heard of is read as an unfinished game rather than
  /// crashing the history screen on open.
  static GameOutcome _outcomeFrom(Object? name) {
    for (final outcome in GameOutcome.values) {
      if (outcome.name == name) return outcome;
    }
    return GameOutcome.inProgress;
  }
}
