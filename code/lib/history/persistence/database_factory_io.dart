// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The SQLite implementation to use on this platform.
///
/// `sqflite` ships native code for Android, iOS and macOS, and is the better
/// choice where it exists. Windows and Linux have no native plugin, so they use
/// `sqflite_common_ffi`, which loads SQLite through the `sqlite3` package's FFI
/// bindings. That package builds its own copy of SQLite from source on those
/// platforms, so there is no system library to install.
DatabaseFactory resolveDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux) {
    // Loads the bundled SQLite library. Doing this more than once is harmless.
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }
  return databaseFactory;
}

/// Where the database file lives, given [fileName].
///
/// A bare name is placed in the application's documents directory, deliberately
/// rather than the database directory `sqflite` offers. The documents
/// directory is the one platform cloud backup picks up: iOS and macOS back it
/// up to iCloud, and Android includes it in Google auto-backup. A database
/// parked in the app's private cache directory would be wiped by the system
/// whenever it decided to reclaim space, which would take the player's game
/// history with it.
///
/// A name that is already a path is used as it stands. Asking the platform for
/// a directory is a platform-channel call, and a caller that has said where the
/// file should go — the tests, chiefly — should not have to answer for it.
Future<String> resolveDatabasePath(String fileName) async {
  if (p.isAbsolute(fileName)) return fileName;
  final documents = await getApplicationDocumentsDirectory();
  return p.join(documents.path, fileName);
}
