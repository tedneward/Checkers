// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../engine/checkers.dart';
import 'game_record.dart';

/// Steps through a recorded game a move at a time.
///
/// This rebuilds the position with the engine rather than replaying it in the
/// screen, so that what a player sees in replay is exactly what the rules
/// produced when the game was played. The recorded moves are checked against
/// the rules as they are applied, which means a game written by an older build
/// that no longer parses stops cleanly instead of showing a board that never
/// happened.
///
/// Stepping backwards uses the engine's own undo rather than an inverse move.
/// Checkers has no inverse move: taking a piece back and putting it elsewhere
/// is not the same as undoing a jump, because the piece that moved is no longer
/// identifiable afterwards. The engine already knows how to undo a move
/// exactly, so this defers to it rather than trying to be cleverer.
class ReplaySession {
  /// Starts a replay of [record] from the beginning.
  ReplaySession(this.record) : _game = _opening(record);

  /// The game being replayed.
  final GameRecord record;

  final Game _game;

  /// How many moves have been played, so that the position shown is the one
  /// after [ply] of the game's moves.
  int _ply = 0;

  /// The ply at which a recorded move stopped working, or `null` while every
  /// move tried so far has worked.
  ///
  /// Moves are only checked as they are stepped onto the board, so this is a
  /// running answer rather than something worked out up front. The first
  /// failure is the one that counts: going back over it and trying again will
  /// fail the same way, so the answer does not change.
  int? _failedAt;

  /// The position at the current point in the replay.
  Board get board => _game.board;

  /// Whose turn it is in the position being shown.
  Side get sideToMove => _game.sideToMove;

  /// The move that led to the position being shown, or `null` before the first
  /// one has been played.
  Move? get lastMove => _game.lastMove;

  /// How many moves have been played in this replay.
  int get ply => _ply;

  /// How many moves the recorded game has.
  int get totalPlies => record.moves.length;

  /// Whether there is a move still to step onto the board.
  ///
  /// True even when a later move is known not to replay: finding out is the
  /// replay's job, and refusing to try would mean a game whose middle move is
  /// corrupt could never be watched up to that point by pressing "next".
  bool get canGoForward => _ply < totalPlies;

  /// Whether there is a move to take back off the board.
  bool get canGoBack => _ply > 0;

  /// Whether the game is shown from its very first position.
  bool get isAtStart => _ply == 0;

  /// Whether the game is shown from its very last position.
  bool get isAtEnd => _ply == totalPlies;

  /// Whether some of the recorded moves could not be replayed.
  ///
  /// This means the stored game cannot be shown in full. The moves that did
  /// work are still worth showing, so the replay stops at the last one that
  /// did rather than refusing to start.
  bool get isTruncated => _failedAt != null;

  /// How many of the recorded moves can be replayed.
  ///
  /// Every move there is until one is found that does not work, which is only
  /// found out by trying it.
  int get playablePlies => _failedAt ?? totalPlies;

  /// The move recorded at [index], counting from zero.
  String? moveNotationAt(int index) =>
      index >= 0 && index < totalPlies ? record.moves[index] : null;

  /// Whether [index] is the move currently on the board.
  bool isCurrentPly(int index) => index == _ply - 1;

  /// Takes back the move before the position being shown.
  ///
  /// Returns whether a move was taken back.
  bool back() {
    if (!canGoBack) return false;
    _game.undo();
    _ply--;
    return true;
  }

  /// Plays the next recorded move onto the board.
  ///
  /// Returns whether a move was played. A stored move that no longer parses, or
  /// that the rules no longer accept, stops the replay rather than throwing,
  /// because a history that has gone stale is not a reason to make the screen
  /// unusable. Both failures happen for real: text that is not a move at all
  /// comes from a corrupted database, and text that is a move but not a legal
  /// one comes from a build whose rules have since changed.
  bool forward() {
    if (!canGoForward) return false;
    final notation = record.moves[_ply];
    try {
      final move = _game.parseMove(notation);
      if (!_game.tryApplyMove(move)) {
        _failedAt ??= _ply;
        return false;
      }
    } on FormatException {
      // Not a move at all, which is what a corrupted database holds.
      _failedAt ??= _ply;
      return false;
    } on IllegalMoveException {
      // A move, but not a legal one here, which is what a game recorded under
      // different rules holds.
      _failedAt ??= _ply;
      return false;
    }
    _ply++;
    return true;
  }

  /// Jumps to the position after [ply] moves.
  ///
  /// Steps one at a time, so that this and repeated calls to [forward] and
  /// [back] behave identically however the player got there.
  void goTo(int ply) {
    final target = ply.clamp(0, totalPlies);
    while (_ply < target) {
      if (!forward()) break;
    }
    while (_ply > target) {
      back();
    }
  }

  static Game _opening(GameRecord record) =>
      Game.fromFen(record.initialFen, rules: record.variant.rules);
}
