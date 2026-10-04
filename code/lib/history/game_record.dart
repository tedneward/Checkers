// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../engine/checkers.dart';

/// One game in the history, described without its moves.
///
/// The history list shows a row per game and never wants the move list, which
/// for a long game is the bulk of the data. Splitting the summary out means the
/// list query never has to read the moves to answer "what was played, when, and
/// who won".
class GameSummary {
  /// Creates a summary of a recorded game.
  const GameSummary({
    required this.id,
    required this.startedAt,
    required this.finishedAt,
    required this.variant,
    required this.outcome,
    required this.moveCount,
    this.termination,
    this.redPlayerName,
    this.blackPlayerName,
  });

  /// The database's identifier for this game.
  ///
  /// Assigned by the store when the game is first recorded, so it is only
  /// meaningful to whoever handed it out. It is how the replay screen finds the
  /// game again.
  final int id;

  /// When the game began.
  final DateTime startedAt;

  /// When the game was last written to.
  ///
  /// For a game that was played out this is when it ended. For one the player
  /// walked away from it is when they last moved, and [outcome] is
  /// [GameOutcome.inProgress].
  final DateTime finishedAt;

  /// The way of playing the game was under.
  final RuleVariant variant;

  /// How the game ended, or [GameOutcome.inProgress] if it never did.
  final GameOutcome outcome;

  /// Why the game ended, in the engine's own words, or `null` while it is
  /// still being played.
  final String? termination;

  /// How many moves have been played so far, counting each side's turn as one.
  final int moveCount;

  /// Name of the player using red pieces, or null if not recorded.
  final String? redPlayerName;

  /// Name of the player using black pieces, or null if not recorded.
  final String? blackPlayerName;

  String get redName => redPlayerName ?? 'Red';

  String get blackName => blackPlayerName ?? 'Black';

  /// The side that won, or `null` for a draw or a game that never finished.
  Side? get winner => outcome.winner;

  /// A one-line description of how the game ended, for the history list.
  ///
  /// An unfinished game is described as such rather than being left blank,
  /// because a list of rows all reading "Red won" gives no way to tell a
  /// finished game from an abandoned one.
  String get outcomeLabel => switch (outcome) {
    GameOutcome.inProgress => 'Unfinished',
    GameOutcome.redWin => '$redName won',
    GameOutcome.blackWin => '$blackName won',
    GameOutcome.draw => 'Draw',
  };

  @override
  String toString() => 'GameSummary($id, $outcomeLabel, $moveCount moves)';
}

/// A recorded game together with every move played in it.
///
/// This is what the replay screen is built from.
class GameRecord extends GameSummary {
  /// Creates a record of a game and the moves played in it.
  GameRecord({
    required super.id,
    required super.startedAt,
    required super.finishedAt,
    required super.variant,
    required super.outcome,
    required super.moveCount,
    required this.initialFen,
    required List<String> moves,
    super.termination,
    super.redPlayerName,
    super.blackPlayerName,
  }) : moves = List<String>.unmodifiable(moves);

  /// Every move played, in checkers notation, oldest first.
  ///
  /// One entry per ply, so both sides' turns are interleaved and the list is
  /// exactly as long as the game's history. Notation rather than raw squares
  /// because it is compact, is what a player would recognise, and round-trips
  /// back through `Game.parseMove`.
  final List<String> moves;

  /// The position the game started from, as a FEN.
  ///
  /// Replay does not assume this is the standard opening. A game could have
  /// been started from a position, and replaying from the opening would then
  /// show a completely different game from the one that was stored.
  final String initialFen;

  @override
  String toString() =>
      'GameRecord($id, $outcomeLabel, ${moves.length} moves: $moves)';
}

/// Writes [when] as `2026-10-02 19:34`.
///
/// Deliberately not localised. These are the player's own games, most of them
/// minutes old, and the only thing that has to be unambiguous is the order the
/// rows are in, which the store already sorts by.
String formatGameTime(DateTime when) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${when.year}-${two(when.month)}-${two(when.day)} '
      '${two(when.hour)}:${two(when.minute)}';
}
