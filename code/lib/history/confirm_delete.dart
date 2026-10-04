// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../style/palette.dart';

/// Asks the player to confirm something that cannot be undone, and reports
/// whether they said yes.
///
/// Both kinds of deletion in the history go through here. There is no undo and
/// no backup: the games are only in the database, and a mis-tap on a trash icon
/// next to a list of rows is otherwise indistinguishable from an intended
/// delete.
///
/// The confirming button is styled as destructive and, on a wide screen, the
/// cancelling button is the one that gets focus. The safe answer is what a
/// player who has stopped reading and hit return should get.
Future<bool> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final palette = context.read<Palette>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: palette.backgroundSettings,
      shape: const RoundedRectangleBorder(),
      title: Text(
        title,
        style: const TextStyle(fontFamily: 'Permanent Marker', fontSize: 26),
      ),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('No'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: palette.redPen,
            foregroundColor: palette.trueWhite,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
