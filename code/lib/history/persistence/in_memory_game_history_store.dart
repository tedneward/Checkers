// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../engine/checkers.dart';
import '../game_history_store.dart';
import '../game_record.dart';

/// A [GameHistoryStore] that keeps games in memory for as long as the app runs.
///
/// This is what the app falls back to when the database cannot be opened, so
/// that a player whose device cannot write a file can still play, and still get
/// a history screen, rather than the app refusing to start over a problem it
/// could work around. Games recorded here are lost when the app closes; the
/// history screen says as much when this is the store in use.
///
/// It is also what the tests use, because it has no platform channels and
/// nothing to clean up between cases.
class InMemoryGameHistoryStore extends GameHistoryStore {
  /// Creates an empty store.
  InMemoryGameHistoryStore();

  final List<_StoredGame> _games = [];

  /// The identifier the next created game will get.
  ///
  /// Handed out from here rather than by the list length so that deleting a
  /// game does not make the next one reuse its identifier, which would let a
  /// replay screen still on the stack quietly start showing a different game.
  int _nextId = 1;

  @override
  Future<void> open() async {}

  @override
  Future<void> close() async {}

  @override
  bool get isEphemeral => true;

  @override
  Future<List<GameSummary>> listGames() async {
    final games = [..._games]
      ..sort((a, b) {
        final byTime = b.finishedAt.compareTo(a.finishedAt);
        return byTime != 0 ? byTime : b.id.compareTo(a.id);
      });
    return [for (final game in games) game.summary];
  }

  @override
  Future<GameRecord?> loadGame(int id) async {
    for (final game in _games) {
      if (game.id == id) return game.toRecord();
    }
    return null;
  }

  @override
  Future<int> createGame({
    required DateTime startedAt,
    required String initialFen,
    required RuleVariant variant,
  }) async {
    final game = _StoredGame(
      id: _nextId++,
      startedAt: startedAt,
      finishedAt: startedAt,
      variant: variant,
      outcome: GameOutcome.inProgress,
      termination: null,
      initialFen: initialFen,
    );
    _games.add(game);
    return game.id;
  }

  @override
  Future<void> appendMove(int gameId, Move move) async {
    final game = _find(gameId);
    if (game == null) return;
    game.moves.add(move.notation);
    game.finishedAt = DateTime.now();
  }

  @override
  Future<void> finishGame(
    int gameId, {
    required GameOutcome outcome,
    required DateTime finishedAt,
    String? termination,
  }) async {
    final game = _find(gameId);
    if (game == null) return;
    game
      ..outcome = outcome
      ..termination = termination
      ..finishedAt = finishedAt;
  }

  @override
  Future<void> deleteGame(int gameId) async =>
      _games.removeWhere((game) => game.id == gameId);

  @override
  Future<void> deleteAll() async => _games.clear();

  _StoredGame? _find(int id) {
    for (final game in _games) {
      if (game.id == id) return game;
    }
    return null;
  }
}

/// One game being kept in memory.
class _StoredGame {
  _StoredGame({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    required this.variant,
    required this.outcome,
    required this.termination,
    required this.initialFen,
  });

  final int id;
  final DateTime startedAt;
  DateTime finishedAt;
  final RuleVariant variant;
  GameOutcome outcome;
  String? termination;
  final String initialFen;
  final List<String> moves = [];

  GameSummary get summary => GameSummary(
    id: id,
    startedAt: startedAt,
    finishedAt: finishedAt,
    variant: variant,
    outcome: outcome,
    termination: termination,
    moveCount: moves.length,
  );

  GameRecord toRecord() => GameRecord(
    id: id,
    startedAt: startedAt,
    finishedAt: finishedAt,
    variant: variant,
    outcome: outcome,
    termination: termination,
    moveCount: moves.length,
    initialFen: initialFen,
    moves: moves,
  );
}
