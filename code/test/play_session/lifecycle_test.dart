import 'package:checkers/audio/audio_controller.dart';
import 'package:checkers/history/game_history_controller.dart';
import 'package:checkers/history/persistence/in_memory_game_history_store.dart';
import 'package:checkers/main.dart';
import 'package:checkers/play_session/play_session_screen.dart';
import 'package:checkers/player_progress/player_progress.dart';
import 'package:checkers/settings/settings.dart';
import 'package:checkers/style/board_view.dart';
import 'package:checkers/style/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../smoke_test.dart';

void main() {
  setUpAll(stubAppPlugins);

  testWidgets('PlaySessionScreen has a game on its very first frame', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = InMemoryGameHistoryStore();
    final history = GameHistoryController(Future.value(store));

    await tester.pumpWidget(
      _PlaySessionHarness(history: history, palette: Palette()),
    );
    await tester.pump();

    // `didChangeDependencies` runs before the first build, so the board is
    // already populated. Nothing may read `_game` before that point, which is
    // what used to crash with a LateInitializationError.
    expect(find.byType(BoardView), findsOneWidget);
    expect(find.byKey(const ValueKey('square-a1')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(find.byType(BoardView), findsOneWidget);
    expect(find.byKey(const ValueKey('square-a1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('New Game flow does not crash with dialog timing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    expect(find.text('Start'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(BoardView), findsOneWidget);
    expect(find.byKey(const ValueKey('square-a1')), findsOneWidget);
  });

  testWidgets('a game in progress survives a dependency change', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = InMemoryGameHistoryStore();
    final history = GameHistoryController(Future.value(store));

    await tester.pumpWidget(
      _PlaySessionHarness(history: history, palette: _TestPalette()),
    );
    await tester.pumpAndSettle();

    // Play red's opening move, a3-b4, so the position is distinguishable from
    // the starting one.
    await tester.tap(find.byKey(const ValueKey('square-a3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('square-b4')));
    await tester.pumpAndSettle();

    // A square tile exists whether or not it holds a piece, so the piece itself
    // is what proves the move stuck.
    expect(_pieceOn(tester, 'square-a3'), findsNothing);
    expect(_pieceOn(tester, 'square-b4'), findsOneWidget);

    // Handing the screen a new palette makes it rebuild, which runs
    // `didChangeDependencies` again. If that restarted the game, the move above
    // would be undone.
    await tester.pumpWidget(
      _PlaySessionHarness(
        history: history,
        palette: _TestPalette(background: Colors.indigo),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(BoardView), findsOneWidget);
    expect(_pieceOn(tester, 'square-a3'), findsNothing);
    expect(_pieceOn(tester, 'square-b4'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// The piece standing on [squareName], if any.
Finder _pieceOn(WidgetTester tester, String squareName) => find.descendant(
  of: find.byKey(ValueKey(squareName)),
  matching: find.byType(PieceView),
);

/// A palette whose only job is to be swappable, so a test can hand the screen
/// a different one and force the dependency change it cares about.
class _TestPalette extends Palette {
  _TestPalette({this.background = Colors.transparent});

  final Color background;

  @override
  Color get backgroundPlaySession => background;
}

/// Hosts [PlaySessionScreen] under a real router, which the screen reads when
/// it starts a game to pick up the player names the setup dialog collected.
///
/// The router is held across rebuilds on purpose: building a second one would
/// replace the navigator and remount the screen, resetting the game for reasons
/// that have nothing to do with the dependency change under test.
class _PlaySessionHarness extends StatefulWidget {
  const _PlaySessionHarness({required this.history, required this.palette});

  final GameHistoryController history;
  final Palette palette;

  @override
  State<_PlaySessionHarness> createState() => _PlaySessionHarnessState();
}

class _PlaySessionHarnessState extends State<_PlaySessionHarness> {
  late final GoRouter _router = GoRouter(
    initialLocation: '/play',
    routes: [
      GoRoute(
        path: '/play',
        builder: (context, state) =>
            const PlaySessionScreen(key: Key('play session')),
      ),
    ],
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SettingsController>(create: (_) => SettingsController()),
        Provider<Palette>.value(value: widget.palette),
        ChangeNotifierProvider(create: (_) => PlayerProgress()),
        Provider<GameHistoryController>.value(value: widget.history),
        Provider(create: (_) => AudioController()),
      ],
      child: MaterialApp.router(routerConfig: _router),
    );
  }
}
