// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:checkers/engine/checkers.dart';
import 'package:checkers/history/game_history_controller.dart';
import 'package:checkers/history/persistence/in_memory_game_history_store.dart';
import 'package:checkers/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A game with [plies] legal moves played in it, and the identifier it was
/// recorded under.
Future<int> recordGame(
  InMemoryGameHistoryStore store, {
  required int plies,
  DateTime? at,
  GameOutcome outcome = GameOutcome.inProgress,
  RuleVariant variant = RuleVariant.defaultVariant,
}) async {
  final game = Game.standard();
  for (var i = 0; i < plies && !game.isGameOver; i++) {
    final moves = game.legalMoves();
    if (moves.isEmpty) break;
    game.applyMove(moves.first);
  }

  final when = at ?? DateTime(2026, 10, 2, 19, 34);
  final id = await store.createGame(
    startedAt: when,
    initialFen: Game.standard().fen,
    variant: variant,
  );
  for (final move in game.history) {
    await store.appendMove(id, move);
  }
  await store.finishGame(id, outcome: outcome, finishedAt: when);
  return id;
}

/// Builds the real app over [store], so that these tests go through the same
/// router and providers the player does.
Widget appOver(InMemoryGameHistoryStore store) =>
    MyApp(historyController: GameHistoryController(Future.value(store)));

/// Opens the history screen from the main menu.
Future<void> openHistory(WidgetTester tester) async {
  await tester.tap(find.text('History'));
  await tester.pumpAndSettle();
}

/// Answers the platform plugins the app reaches for as it starts.
void stubAppPlugins() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void stub(String name, Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(MethodChannel(name), handler);
  }

  stub('plugins.flutter.io/path_provider', (call) async {
    if (call.method == 'getTemporaryDirectory') {
      return Directory.systemTemp.path;
    }
    return null;
  });
  stub('xyz.luan/audioplayers.global', (call) async => null);
  stub('xyz.luan/audioplayers', (call) async => null);
  stub('xyz.luan/audioplayers.global/events', (call) async => null);
  stub('xyz.luan/audioplayers/events/musicPlayer', (call) async => null);
  stub('xyz.luan/audioplayers/events/sfxPlayer#0', (call) async => null);
  stub('xyz.luan/audioplayers/events/sfxPlayer#1', (call) async => null);
}

void main() {
  setUpAll(stubAppPlugins);

  late InMemoryGameHistoryStore store;

  setUp(() {
    store = InMemoryGameHistoryStore();
  });

  group('the history screen', () {
    testWidgets('is reachable from the main menu', (tester) async {
      await tester.pumpWidget(appOver(store));

      expect(find.text('History'), findsOneWidget);

      await openHistory(tester);

      expect(find.text('History'), findsWidgets);
      expect(find.text('No games yet'), findsOneWidget);
    });

    testWidgets('says so when nothing has been played', (tester) async {
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      expect(find.text('No games yet'), findsOneWidget);
      expect(find.textContaining('watch them back'), findsOneWidget);
    });

    testWidgets('lists a game that has been played', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      expect(find.text('No games yet'), findsNothing);
      expect(find.text('2026-10-02 19:34'), findsOneWidget);
      expect(find.text('Unfinished'), findsOneWidget);
      // The move count shares a line with the rule variant rather than getting
      // a row of its own, so it is a substring rather than the whole line.
      expect(find.textContaining('4 moves'), findsOneWidget);
      expect(
        find.textContaining(RuleVariant.defaultVariant.label),
        findsOneWidget,
      );
    });

    testWidgets('names the winner of a finished game', (tester) async {
      await recordGame(
        store,
        plies: 4,
        outcome: GameOutcome.redWin,
        at: DateTime(2026, 10, 1, 8),
      );
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      expect(find.text('Red won'), findsOneWidget);
      expect(find.text('2026-10-01 08:00'), findsOneWidget);
    });

    testWidgets('lists the most recently played game first', (tester) async {
      await recordGame(store, plies: 2, at: DateTime(2026, 10, 1, 8));
      await recordGame(store, plies: 6, at: DateTime(2026, 10, 3, 20));
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      final rows = tester
          .widgetList<ListTile>(find.byType(ListTile))
          .map((tile) => '${(tile.subtitle as Text?)?.data}')
          .toList();
      expect(rows.first, contains('6 moves'));
      expect(rows.last, contains('2 moves'));
    });

    testWidgets('warns that games are not being kept', (tester) async {
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      // The store in these tests is the in-memory one, which is the same thing
      // the app falls back to when the database cannot be opened. Saying so is
      // the difference between "your games are saved" and a list that empties
      // itself for no stated reason.
      expect(find.textContaining('not being saved'), findsOneWidget);
    });

    testWidgets('goes back to the main menu', (tester) async {
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('New Game'), findsOneWidget);
    });
  });

  group('deleting one game', () {
    testWidgets('asks before deleting', (tester) async {
      final id = await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.byKey(ValueKey('history delete game $id')));
      await tester.pumpAndSettle();

      expect(find.text('Delete this game?'), findsOneWidget);
      expect(store.listGames, isNotNull);
      expect(await store.listGames(), hasLength(1));
    });

    testWidgets('keeps the game when the answer is no', (tester) async {
      final id = await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.byKey(ValueKey('history delete game $id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(await store.listGames(), hasLength(1));
      expect(find.text('2026-10-02 19:34'), findsOneWidget);
    });

    testWidgets('removes the game when the answer is yes', (tester) async {
      final id = await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.byKey(ValueKey('history delete game $id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(await store.listGames(), isEmpty);
      expect(find.text('2026-10-02 19:34'), findsNothing);
      expect(find.text('No games yet'), findsOneWidget);
    });

    testWidgets('leaves the other games alone', (tester) async {
      final doomed = await recordGame(
        store,
        plies: 4,
        at: DateTime(2026, 10, 1, 8),
      );
      await recordGame(store, plies: 6, at: DateTime(2026, 10, 3, 20));
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.byKey(ValueKey('history delete game $doomed')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      final remaining = await store.listGames();
      expect(remaining, hasLength(1));
      expect(remaining.single.moveCount, 6);
      expect(find.text('2026-10-01 08:00'), findsNothing);
      expect(find.text('2026-10-03 20:00'), findsOneWidget);
    });
  });

  group('deleting every game', () {
    testWidgets('asks before deleting', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.byKey(const ValueKey('history delete all')));
      await tester.pumpAndSettle();

      expect(find.text('Delete every game?'), findsOneWidget);
      expect(await store.listGames(), hasLength(1));
    });

    testWidgets('names how many games would go', (tester) async {
      await recordGame(store, plies: 4, at: DateTime(2026, 10, 1, 8));
      await recordGame(store, plies: 6, at: DateTime(2026, 10, 3, 20));
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.byKey(const ValueKey('history delete all')));
      await tester.pumpAndSettle();

      expect(find.textContaining('All 2 recorded games'), findsOneWidget);
    });

    testWidgets('keeps every game when the answer is no', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.byKey(const ValueKey('history delete all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();

      expect(await store.listGames(), hasLength(1));
      expect(find.text('2026-10-02 19:34'), findsOneWidget);
    });

    testWidgets('removes every game when the answer is yes', (tester) async {
      await recordGame(store, plies: 4, at: DateTime(2026, 10, 1, 8));
      await recordGame(store, plies: 6, at: DateTime(2026, 10, 3, 20));
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.byKey(const ValueKey('history delete all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete all'));
      await tester.pumpAndSettle();

      expect(await store.listGames(), isEmpty);
      expect(find.text('No games yet'), findsOneWidget);
    });
  });

  group('the replay screen', () {
    testWidgets('opens a game from the list', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      await tester.tap(find.text('2026-10-02 19:34'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('replay next')), findsOneWidget);
      expect(find.byKey(const ValueKey('replay previous')), findsOneWidget);
      // Opens on the last move, so all four recorded moves are listed.
      expect(find.text('Move 4 of 4'), findsOneWidget);
    });

    testWidgets('shows the board', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);
      await tester.tap(find.text('2026-10-02 19:34'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('square-a1')), findsOneWidget);
      expect(find.byKey(const ValueKey('square-h8')), findsOneWidget);
    });

    testWidgets('lists every move', (tester) async {
      final game = Game.standard();
      for (var i = 0; i < 4; i++) {
        game.applyMove(game.legalMoves().first);
      }
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);
      await tester.tap(find.text('2026-10-02 19:34'));
      await tester.pumpAndSettle();

      for (final move in game.history) {
        expect(find.text(move.notation), findsOneWidget, reason: move.notation);
      }
    });

    testWidgets('takes a move back off the board', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);
      await tester.tap(find.text('2026-10-02 19:34'));
      await tester.pumpAndSettle();
      expect(find.text('Move 4 of 4'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('replay previous')));
      await tester.pumpAndSettle();

      expect(find.text('Move 3 of 4'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('replay previous')));
      await tester.pumpAndSettle();

      expect(find.text('Move 2 of 4'), findsOneWidget);
    });

    testWidgets('puts a move back on the board', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);
      await tester.tap(find.text('2026-10-02 19:34'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('replay previous')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('replay previous')));
      await tester.pumpAndSettle();
      expect(find.text('Move 2 of 4'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('replay next')));
      await tester.pumpAndSettle();

      expect(find.text('Move 3 of 4'), findsOneWidget);
    });

    testWidgets('walks back to the opening and forward again', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);
      await tester.tap(find.text('2026-10-02 19:34'));
      await tester.pumpAndSettle();

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('replay previous')));
        await tester.pumpAndSettle();
      }
      expect(find.text('Start'), findsOneWidget);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('replay next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('Move 4 of 4'), findsOneWidget);
    });

    testWidgets('jumps to a move when it is tapped in the list', (
      tester,
    ) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);
      await tester.tap(find.text('2026-10-02 19:34'));
      await tester.pumpAndSettle();
      expect(find.text('Move 4 of 4'), findsOneWidget);

      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();

      expect(find.text('Move 1 of 4'), findsOneWidget);
    });

    testWidgets('does not let the board be played', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);
      await tester.tap(find.text('2026-10-02 19:34'));
      await tester.pumpAndSettle();
      expect(find.text('Move 4 of 4'), findsOneWidget);

      // A replay is a picture of a game that already happened. Tapping the
      // board must not be a way of playing it.
      await tester.tap(find.byKey(const ValueKey('square-a1')));
      await tester.tap(find.byKey(const ValueKey('square-b2')));
      await tester.pumpAndSettle();

      expect(find.text('Move 4 of 4'), findsOneWidget);
    });

    testWidgets('goes back to the history', (tester) async {
      await recordGame(store, plies: 4);
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);
      await tester.tap(find.text('2026-10-02 19:34'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('replay back')));
      await tester.pumpAndSettle();

      expect(find.text('2026-10-02 19:34'), findsOneWidget);
    });

    testWidgets('says when the game is no longer there', (tester) async {
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      // Straight to a replay of a game that was never recorded, which is what a
      // stale history link amounts to. The screen has to say so rather than
      // show an empty board that looks like a real game.
      final context = tester.element(find.text('History'));
      GoRouter.of(context).push('/history/replay/999');
      await tester.pumpAndSettle();

      expect(find.text('That game is gone'), findsOneWidget);
    });

    testWidgets('offers a way back from a game that is gone', (tester) async {
      await tester.pumpWidget(appOver(store));
      await openHistory(tester);

      final context = tester.element(find.text('History'));
      GoRouter.of(context).push('/history/replay/999');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('No games yet'), findsOneWidget);
    });
  });
}
