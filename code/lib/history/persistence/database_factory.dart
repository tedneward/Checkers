// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:sqflite/sqflite.dart';

// Resolves to the native implementations everywhere except in the browser,
// where `dart:io` does not exist and SQLite has to run as WebAssembly. The two
// files agree on the shape of `resolveDatabaseFactory` and
// `resolveDatabasePath`, so only the one that can actually compile is picked.
import 'database_factory_io.dart'
    if (dart.library.js_interop) 'database_factory_web.dart'
    as platform;

/// The SQLite implementation for the platform the app is running on.
DatabaseFactory databaseFactoryForPlatform() =>
    platform.resolveDatabaseFactory();

/// Where to put the history database, given [fileName].
///
/// Always await this, whichever platform answered: the native implementations
/// have to ask the platform for a directory and the web one does not.
Future<String> databasePathForPlatform(String fileName) async =>
    platform.resolveDatabasePath(fileName);
