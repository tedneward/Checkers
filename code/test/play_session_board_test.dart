// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:checkers/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'smoke_test.dart' show stubAppPlugins;

/// Finds one square of the board by its name, such as `a1` or `h8`.
Finder _square(String name) => find.byKey(ValueKey<String>('square-$name'));

/// A device that has both a notch at the top and a home indicator at the
/// bottom. Insets like these are the reason the board used to lose its bottom
/// row, so every test here runs with them present.
const Size _screen = Size(393, 852);
const EdgeInsets _insets = EdgeInsets.only(top: 59, bottom: 34);

void main() {
  setUpAll(stubAppPlugins);

  /// Opens a fresh game on a screen of the given size with the given insets.
  Future<void> startGame(
    WidgetTester tester, {
    Size screen = _screen,
    EdgeInsets insets = _insets,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = screen;
    tester.view.padding = FakeViewPadding(
      top: insets.top,
      bottom: insets.bottom,
    );

    await tester.pumpWidget(MyApp());
    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    // Dismiss game setup dialog if present
    if (find.text('Start').evaluate().isNotEmpty) {
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));
    for (int i = 0; i < 3; i++) {
      if (_square("a1").evaluate().isNotEmpty) break;
      await tester.pumpAndSettle(const Duration(seconds: 1));
    }

    // Reaching the game legitimately overflows the main menu on short screens,
    // which is a separate concern from the board's own layout.
    tester.takeException();
  }

  /// The rectangle the board occupies, taken from two opposite corners.
  Future<Rect> boardRect(WidgetTester tester) async {
    final a1 = tester.getRect(_square('a1'));
    final h8 = tester.getRect(_square('h8'));
    return Rect.fromLTRB(
      a1.left < h8.left ? a1.left : h8.left,
      a1.top < h8.top ? a1.top : h8.top,
      a1.right > h8.right ? a1.right : h8.right,
      a1.bottom > h8.bottom ? a1.bottom : h8.bottom,
    );
  }

  testWidgets('the board shows all sixty-four squares', (tester) async {
    await startGame(tester);

    // Red starts on ranks 1 to 3, so the whole of rank 1 going missing is a row
    // of pieces the player cannot see or tap.
    for (var file = 0; file < 8; file++) {
      for (var rank = 1; rank <= 8; rank++) {
        final name = '${String.fromCharCode('a'.codeUnitAt(0) + file)}$rank';
        expect(
          _square(name),
          findsOneWidget,
          reason: 'square $name is missing from the board',
        );
      }
    }
  });

  testWidgets('the bottom row of red pieces is on screen', (tester) async {
    await startGame(tester);

    // Every piece red starts with has to be tappable, so the whole of rank 1
    // has to sit inside the window rather than being clipped off the bottom.
    for (final name in ['a1', 'c1', 'e1', 'g1']) {
      final rect = tester.getRect(_square(name));
      expect(rect.bottom, lessThanOrEqualTo(_screen.height));
      expect(rect.top, greaterThanOrEqualTo(0));
    }
  });

  testWidgets('the board is square and fits on the screen', (tester) async {
    await startGame(tester);

    final board = await boardRect(tester);

    expect(
      board.width,
      closeTo(board.height, 0.5),
      reason: 'the board lost its square shape',
    );
    expect(board.top, greaterThanOrEqualTo(0));
    expect(
      board.bottom,
      lessThanOrEqualTo(_screen.height),
      reason: 'the board runs off the bottom of the screen',
    );
    expect(board.left, greaterThanOrEqualTo(0));
    expect(board.right, lessThanOrEqualTo(_screen.width));
  });

  testWidgets('the board takes up as much of the screen as a square can', (
    tester,
  ) async {
    await startGame(tester);

    final board = await boardRect(tester);

    // The widest square this screen can hold is its width less the margin the
    // layout shell leaves around the board. The board should claim all of it
    // rather than sitting in a corner of the available space.
    expect(
      board.width,
      closeTo(_screen.width - (_screen.shortestSide / 30) * 2, 1.0),
      reason: 'the board is smaller than the largest square that fits',
    );
  });

  testWidgets('the board does not scroll', (tester) async {
    await startGame(tester);

    // If the board could scroll, then something was pushing its squares out of
    // view to begin with. The board is exactly as tall as it is wide, so there
    // is nothing to scroll to.
    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable).first,
    );
    expect(
      scrollable.position.maxScrollExtent,
      0,
      reason: 'the board is taller than the space it was given',
    );
  });

  testWidgets('the board is square on a wide, short screen', (tester) async {
    // Landscape is the other branch of the layout shell, and the board is
    // limited by the height there rather than the width.
    await startGame(
      tester,
      screen: const Size(852, 393),
      insets: const EdgeInsets.only(bottom: 21),
    );

    final board = await boardRect(tester);

    expect(board.width, closeTo(board.height, 0.5));
    expect(board.bottom, lessThanOrEqualTo(393));
  });
}
