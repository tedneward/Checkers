// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:logging/logging.dart';

import '../engine/checkers.dart';
import 'game_history_store.dart';
import 'game_record.dart';

final Logger _log = Logger('GameHistory');

/// Records the games being played and reads back the ones already recorded.
///
/// This sits between the play session and [GameHistoryStore] so that no screen
/// has to think about failures. History is a record of what happened, not a
/// condition for what can happen: if the database is full, corrupt, or simply
/// not there, a player must still be able to finish the game in front of them.
/// Every write therefore goes through [record], which logs and swallows, and a
/// game that cannot be written costs the player their place in the history and
/// nothing else.
///
/// Writes are also chained rather than fired off. A game's first move and its
/// row are created by the same call, but its second move can be played while the
/// first is still being written, and a store that was handed two moves for a
/// game whose identifier it has not returned yet would put one of them nowhere.
/// Reads are not chained, so opening the history never waits behind a write.
class GameHistoryController {
  /// Creates a controller writing to whichever store [store] resolves to.
  ///
  /// Takes the future rather than the store because opening is asynchronous and
  /// happens on another platform: which SQLite implementation runs, and whether
  /// the database file can be opened at all, are not known until it has been
  /// tried.
  GameHistoryController(Future<GameHistoryStore> store) : _storeFuture = store;

  final Future<GameHistoryStore> _storeFuture;

  /// The store, once it has finished opening.
  Future<GameHistoryStore> get _store => _storeFuture;

  /// The tail of the chain of writes, so that the next one waits for this one.
  Future<void> _pending = Future<void>.value();

  /// The game currently being recorded, or `null` if no game has begun.
  ///
  /// The identifier lives inside this rather than beside it, and that is the
  /// whole design. A game's row is created by its first move, which cannot
  /// happen until the store has answered, so the identifier does not exist at
  /// the moment the move is played. Every write for the same game therefore
  /// shares one [_Recording] and fills in its `id` when it gets there, and a
  /// write that was queued before the player hit Restart still points at the
  /// game the move belonged to rather than at the new one.
  _Recording? _recording;

  /// Whether games are being kept only for as long as the app runs.
  ///
  /// A future because whether the database opened is only known once it has
  /// been tried, and it is worth knowing: it is the difference between "your
  /// games are saved" and "they will be gone when you close the app".
  Future<bool> get isEphemeral async => (await _store).isEphemeral;

  /// Starts recording a new game, forgetting any game being recorded already.
  ///
  /// That earlier game stays in the history, unfinished at the last move it
  /// reached. Restarting is not the same as deleting, so nothing is removed
  /// here.
  void beginGame({required String initialFen, required RuleVariant variant}) {
    _recording = _Recording(
      startedAt: DateTime.now(),
      initialFen: initialFen,
      variant: variant,
    );
  }

  /// Records a move played in the game being recorded.
  ///
  /// The game this move belongs to is captured here rather than read inside the
  /// write, because a player can hit Restart while the write is still waiting
  /// its turn, and the move belonged to the game that was on the board.
  Future<void> recordMove(Move move) {
    final recording = _recording;
    if (recording == null) {
      // No game has begun, so there is nothing to record against.
      return Future<void>.value();
    }
    return _record((store) async {
      await recording.store(store, (id) => store.appendMove(id, move));
    });
  }

  /// Records how the game being recorded ended.
  ///
  /// Queued like any other write, so that it runs after the moves that came
  /// before it and can see the identifier they created. Reading the identifier
  /// before queueing would see `null` for a game whose last move had not been
  /// written yet, and silently record nothing.
  Future<void> completeGame({
    required GameOutcome outcome,
    String? termination,
  }) {
    final recording = _recording;
    if (recording == null) {
      return Future<void>.value();
    }
    return _record((store) async {
      // A game with no moves has no row, so there is nothing to finish.
      final id = recording.id;
      if (id == null) return;
      await store.finishGame(
        id,
        outcome: outcome,
        finishedAt: DateTime.now(),
        termination: termination,
      );
    });
  }

  /// Every game in the history, most recently played first.
  ///
  /// A store that cannot answer gives an empty history. The history screen has
  /// to draw something either way, and "no games" is something it can draw.
  Future<List<GameSummary>> games() =>
      _read((store) => store.listGames(), fallback: const <GameSummary>[]);

  /// The game with [id] and its moves, or `null` if there is no such game, or if
  /// the store cannot say.
  Future<GameRecord?> game(int id) =>
      _read((store) => store.loadGame(id), fallback: null);

  /// Removes the game with [id] and its moves.
  Future<void> deleteGame(int id) => _record((store) => store.deleteGame(id));

  /// Removes every game and every move.
  Future<void> deleteAll() => _record((store) => store.deleteAll());

  /// Runs [action] with the store, once it has finished opening.
  Future<T> _with<T>(Future<T> Function(GameHistoryStore store) action) async {
    final store = await _store;
    return action(store);
  }

  /// Runs [action], logging and swallowing anything it throws.
  ///
  /// Every write is a `Future<void>`, for which there is no sensible value to
  /// stand in for the write, so a failed write simply reports that it did
  /// nothing.
  Future<T> _record<T>(Future<T> Function(GameHistoryStore store) action) {
    final result = _pending.then((_) => _swallow(() => _with(action)));
    _pending = result;
    return result;
  }

  /// Runs [action], logging and swallowing anything it throws.
  ///
  /// Reads do not go through the write chain, so they are not ordered against
  /// writes. That is deliberate: the history screen reading while a move is
  /// being written should show the move already written rather than make the
  /// player wait for a write that has nothing to do with their question.
  ///
  /// [fallback] is what a failed read answers with. It has to be said out
  /// loud, because no single value suits every caller, and returning the wrong
  /// one throws out of the `catch` and defeats the point of having one.
  Future<T> _read<T>(
    Future<T> Function(GameHistoryStore store) action, {
    required T fallback,
  }) => _swallow(() => _with(action), fallback: fallback);

  static Future<T> _swallow<T>(
    Future<T> Function() action, {
    T? fallback,
  }) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      _log.warning('Game history operation failed', error, stackTrace);
      // Returned as a value rather than thrown: a store that has failed should
      // leave the app working, and every caller here has a sensible answer for
      // a missing game or an empty list.
      return fallback as T;
    }
  }
}

/// One game in the middle of being recorded.
///
/// Holds the details the row is created from, and the row's identifier once the
/// store has handed it out.
///
/// Private to this library: a recording is a bookkeeping detail of writing
/// games out, and nothing outside this file has any business holding one.
class _Recording {
  _Recording({
    required this.startedAt,
    required this.initialFen,
    required this.variant,
  });

  /// When the game began, which is not when it was first written: a game opened
  /// and sat there for a minute was begun a minute before its first move.
  final DateTime startedAt;

  /// The position it was begun from.
  final String initialFen;

  /// The way of playing it was under.
  final RuleVariant variant;

  /// The store's identifier for the game, once a move has caused it to exist.
  ///
  /// `null` for as long as the player has not moved, which is deliberate: a
  /// game that is opened and immediately restarted has happened, but recording
  /// it would fill the history with rows reading "Unfinished, 0 moves".
  int? id;

  /// Runs [write] against this game's row, creating the row first if this is
  /// the game's first write.
  ///
  /// Only ever called from the controller's write chain, so two calls for the
  /// same game cannot both find [id] missing and create the row twice.
  Future<void> store(
    GameHistoryStore store,
    Future<void> Function(int id) write,
  ) async {
    final existing = id;
    if (existing != null) return write(existing);
    final created = await store.createGame(
      startedAt: startedAt,
      initialFen: initialFen,
      variant: variant,
    );
    id = created;
    return write(created);
  }
}
