// Copyright 2023, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'about/about_screen.dart';
import 'history/history_screen.dart';
import 'history/replay_screen.dart';
import 'main_menu/main_menu_screen.dart';
import 'play_session/play_session_screen.dart';
import 'rules/rules_screen.dart';
import 'settings/settings_screen.dart';
import 'statistics/statistics_screen.dart';
import 'style/my_transition.dart';
import 'style/palette.dart';
import 'win_game/win_game_screen.dart';

/// Builds the router describing the game's navigational hierarchy, from the
/// main screen through settings screens all the way into a game.
///
/// This is a function rather than a shared top-level value on purpose: a
/// `GoRouter` remembers where it has navigated to, so a single global instance
/// would leak its location from one app to the next. Each call starts at the
/// main menu again.
GoRouter createRouter() => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const MainMenuScreen(key: Key('main menu')),
      routes: [
        GoRoute(
          path: 'play',
          pageBuilder: (context, state) => buildMyTransition<void>(
            key: const ValueKey('play'),
            color: context.watch<Palette>().backgroundPlaySession,
            child: const PlaySessionScreen(key: Key('play session')),
          ),
          routes: [
            GoRoute(
              path: 'won',
              pageBuilder: (context, state) => buildMyTransition<void>(
                key: const ValueKey('won'),
                color: context.watch<Palette>().backgroundPlaySession,
                child: const WinGameScreen(key: Key('win game')),
              ),
            ),
          ],
        ),
        GoRoute(
          path: 'settings',
          builder: (context, state) =>
              const SettingsScreen(key: Key('settings')),
        ),
        GoRoute(
          path: 'rules',
          pageBuilder: (context, state) => buildMyTransition<void>(
            key: const ValueKey('rules'),
            color: context.watch<Palette>().backgroundPlaySession,
            child: const RulesScreen(key: Key('rules screen')),
          ),
        ),
        GoRoute(
          path: 'statistics',
          pageBuilder: (context, state) => buildMyTransition<void>(
            key: const ValueKey('statistics'),
            color: context.watch<Palette>().background4,
            child: const StatisticsScreen(key: Key('statistics screen')),
          ),
        ),
        GoRoute(
          path: 'about',
          pageBuilder: (context, state) => buildMyTransition<void>(
            key: const ValueKey('about'),
            color: context.watch<Palette>().backgroundSettings,
            child: const AboutScreen(key: Key('about screen')),
          ),
        ),
        GoRoute(
          path: 'history',
          pageBuilder: (context, state) => buildMyTransition<void>(
            key: const ValueKey('history'),
            color: context.watch<Palette>().backgroundMain,
            child: const HistoryScreen(key: Key('history screen')),
          ),
          routes: [
            // The replay screen reads the game from the store by this id rather
            // than being handed it through the router, so going straight to a
            // replay link works and a stale id cannot leave it showing a
            // half-built game.
            GoRoute(
              path: 'replay/:id',
              pageBuilder: (context, state) => buildMyTransition<void>(
                key: const ValueKey('replay'),
                color: context.watch<Palette>().backgroundPlaySession,
                child: ReplayScreen(
                  key: const Key('replay screen'),
                  gameId: int.tryParse(state.pathParameters['id'] ?? '') ?? -1,
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
