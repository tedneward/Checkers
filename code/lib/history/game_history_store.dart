// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../engine/checkers.dart';
import 'game_record.dart';

/// Where played games are kept.
///
/// This is an interface so that the screens do not care whether games live in
/// SQLite, in memory, or somewhere else entirely, and so that tests can hand
/// them a store they control. The SQLite implementation lives in
/// `persistence/`.
///
/// A game is written in three steps, rather than saved all at once at the end:
/// [createGame] when it begins, [appendMove] for each move as it is played, and
/// [finishGame] when it is over. Writing as the game goes means a game the
/// player abandons, or that is lost to the app being killed, is still in the
/// history up to the last move actually played.
abstract class GameHistoryStore {
  /// Prepares the store for use.
  ///
  /// Safe to call more than once. Opening may fail, for instance when the
  /// database file cannot be written; what happens then is up to the
  /// implementation, and callers are expected to cope with a store that is
  /// usable but empty rather than one that is broken.
  Future<void> open();

  /// Releases anything the store is holding open.
  Future<void> close();

  /// Every game in the history, most recently played first.
  Future<List<GameSummary>> listGames();

  /// The game with [id] and all of its moves, or `null` if there is no such
  /// game.
  Future<GameRecord?> loadGame(int id);

  /// Starts recording a game and returns its identifier.
  ///
  /// [initialFen] is the position the game starts from, which replay reads back
  /// rather than assuming the standard opening.
  Future<int> createGame({
    required DateTime startedAt,
    required String initialFen,
    required RuleVariant variant,
  });

  /// Adds [move] to the game with [gameId].
  Future<void> appendMove(int gameId, Move move);

  /// Records how the game with [gameId] ended.
  ///
  /// Calling this more than once for the same game is allowed and keeps the
  /// latest result, so a game that is finished and then restarted does not have
  /// to be deleted and reinserted.
  Future<void> finishGame(
    int gameId, {
    required GameOutcome outcome,
    required DateTime finishedAt,
    String? termination,
  });

  /// Removes the game with [gameId] and all of its moves.
  ///
  /// Does nothing when there is no such game.
  Future<void> deleteGame(int gameId);

  /// Removes every game and every move.
  Future<void> deleteAll();

  /// Whether games recorded here are lost when the app closes.
  ///
  /// False for a store that writes to disk. A store that cannot write is still
  /// worth playing on, so the history screen says plainly that it is not
  /// keeping anything rather than quietly behaving like it is.
  bool get isEphemeral => false;
}
