// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/foundation.dart';

/// What the player has done across all of their games.
///
/// Checkers has no scores, so nothing is ranked or compared here. All this
/// class does is count finished games, which is what the statistics screen
/// reports and what "Reset progress" in the settings screen clears.
///
/// The progress lives in memory only, so it starts fresh on every launch.
///
/// This is published with `ChangeNotifierProvider` in `main.dart`, so read it
/// with `context.watch<PlayerProgress>()` and change it with
/// `context.read<PlayerProgress>()`.
class PlayerProgress extends ChangeNotifier {
  int _gamesWon = 0;

  /// How many games the player has won so far.
  int get gamesWon => _gamesWon;

  /// Records that the player has just won a game.
  ///
  /// A game is only recorded once, when it ends, so callers decide whether a
  /// finished game counts: only a win is recorded.
  void recordWin() {
    _gamesWon++;
    notifyListeners();
  }

  /// Forgets everything.
  ///
  /// Called from the settings screen's "Reset progress" line.
  void reset() {
    _gamesWon = 0;
    notifyListeners();
  }
}
