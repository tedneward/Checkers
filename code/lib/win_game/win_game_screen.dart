// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../style/confetti.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

/// Celebrates a game the player has won.
///
/// There is nothing to report beyond the win itself: checkers is not a game
/// of points.
class WinGameScreen extends StatelessWidget {
  const WinGameScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    const gap = SizedBox(height: 10);

    return Scaffold(
      backgroundColor: palette.backgroundPlaySession,
      body: Stack(
        children: [
          const Positioned.fill(
            child: Confetti(
              colors: [
                Color(0xffd10841),
                Color(0xff1d75fb),
                Color(0xFF0050bc),
                Color(0xffa2dcc7),
              ],
            ),
          ),
          ResponsiveScreen(
            squarishMainArea: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                gap,
                const Center(
                  child: Text(
                    'You won!',
                    style: TextStyle(
                      fontFamily: 'Permanent Marker',
                      fontSize: 50,
                    ),
                  ),
                ),
                gap,
                Center(
                  child: Text(
                    'All of black’s pieces are gone.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Permanent Marker',
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            rectangularMenuArea: MyButton(
              onPressed: () {
                GoRouter.of(context).go('/play');
              },
              child: const Text('Continue'),
            ),
          ),
        ],
      ),
    );
  }
}
