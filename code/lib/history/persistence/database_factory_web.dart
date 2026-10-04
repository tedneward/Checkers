// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// The SQLite implementation to use on the web.
///
/// The browser has no SQLite of its own and no files to speak of, so this runs
/// SQLite compiled to WebAssembly. The in-memory database the library keeps is
/// written back to IndexedDB, which is what makes the history survive a page
/// reload.
///
/// This implementation is experimental and noticeably slower than the native
/// ones, which is why the search and writing are kept to one small row per
/// move rather than anything heavier.
DatabaseFactory resolveDatabaseFactory() => databaseFactoryFfiWeb;

/// Where the database lives, given [fileName].
///
/// A bare name, not a path. The web implementation keeps a virtual file system
/// backed by IndexedDB and resolves names against it, so a real filesystem path
/// would be meaningless — and `/`-separated absolute paths are not writable in
/// a browser anyway.
String resolveDatabasePath(String fileName) => fileName;
