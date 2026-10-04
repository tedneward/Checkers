// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:logging/logging.dart';

import '../game_history_store.dart';
import 'in_memory_game_history_store.dart';
import 'sqlite_game_history_store.dart';

final Logger _log = Logger('HistoryStore');

/// Opens the best history store this device will allow.
///
/// A failure to open is not something to let escape. The database can be
/// unwritable because the disk is full, or unopenable because a file left by an
/// older build is not one this build understands, and neither is a good enough
/// reason to stop somebody playing checkers. When it happens the in-memory
/// store takes over: the game keeps being recorded and the replay screen keeps
/// working, the history just does not outlive the session. The history screen
/// says so, rather than quietly pretending to be saving.
Future<GameHistoryStore> openHistoryStore() async {
  final sqlite = SqliteGameHistoryStore();
  try {
    await sqlite.open();
    return sqlite;
  } catch (error, stackTrace) {
    _log.warning('Falling back to in-memory game history', error, stackTrace);
    // Closing in case the failure left a half-open file handle behind. This is
    // best-effort: if the database never opened there is nothing to close, and
    // if closing also fails the store was already unusable.
    try {
      await sqlite.close();
    } catch (_) {
      // Nothing useful to do about this, and it must not stop the fallback.
    }
    final memory = InMemoryGameHistoryStore();
    await memory.open();
    return memory;
  }
}
