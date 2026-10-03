// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../player_progress/player_progress.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

/// A holding screen for the player's statistics.
///
/// Checkers has no scores, so there is nothing to rank or compare. All this
/// can report is what [PlayerProgress] knows: how many games the player has
/// won.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final progress = context.watch<PlayerProgress>();

    final won = progress.gamesWon;
    final games = won == 1 ? '1 game' : '$won games';

    return Scaffold(
      backgroundColor: palette.background4,
      body: ResponsiveScreen(
        topMessageArea: const Text(
          'Statistics',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Permanent Marker',
            fontSize: 40,
            height: 1,
          ),
        ),
        squarishMainArea: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bar_chart, size: 64, color: palette.ink),
                const SizedBox(height: 16),
                Text(
                  'You have won $games.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(height: 8),
                Text(
                  'Checkers is not a game of points, so there is nothing '
                  'else to count.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: palette.ink),
                ),
              ],
            ),
          ),
        ),
        rectangularMenuArea: MyButton(
          onPressed: () => GoRouter.of(context).pop(),
          child: const Text('Back'),
        ),
      ),
    );
  }
}
