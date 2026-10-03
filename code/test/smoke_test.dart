// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:checkers/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Answers the platform plugins the app reaches for as it starts.
///
/// `AudioController` preloads its sound effects through `audioplayers` and
/// `path_provider` as soon as it is built, and neither plugin exists under
/// `flutter test`. Answering the channels keeps that preloading quiet.
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

  // `package_info_plus` is answered once per test run, so give it something to
  // report rather than letting the About screen fall back to "unknown".
  stub('dev.fluttercommunity.plus/package_info', (call) async {
    return <String, dynamic>{
      'appName': 'Classic Checkers',
      'packageName': 'com.example.checkers',
      'version': '1.2.3',
      'buildNumber': '45',
      'buildSignature': '',
      'installerStore': 'unknown',
    };
  });
}

void main() {
  setUpAll(stubAppPlugins);

  testWidgets('smoke test', (tester) async {
    // Build our game and trigger a frame.
    await tester.pumpWidget(MyApp());

    // Verify that the 'New Game' button is shown.
    expect(find.text('New Game'), findsOneWidget);

    // Verify that the 'Settings' button is shown.
    expect(find.text('Settings'), findsOneWidget);

    // Go to 'Settings'.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Music'), findsOneWidget);

    // Go back to main menu.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    // Tap 'New Game'. That goes straight into a game.
    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    // The game is on show, and it is red's turn to move the first piece.
    expect(find.text('Checkers'), findsOneWidget);
    expect(find.text('Red to move'), findsOneWidget);

    // Both sides start with twelve pieces.
    expect(find.text('Red 12   Black 12'), findsOneWidget);

    // And 'Back' returns to the main menu.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('New Game'), findsOneWidget);
  });

  testWidgets('the rules are reachable from the main menu', (tester) async {
    await tester.pumpWidget(MyApp());

    expect(find.text('Rules'), findsOneWidget);
    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();

    // The rules are read out of the asset in `assets/html`.
    expect(find.text('How to play'), findsOneWidget);

    // Reading an asset is real async work, which `testWidgets` only lets
    // through while it is inside `runAsync`.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Classic Checkers'), findsOneWidget);

    // And the Back button returns to the menu.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('New Game'), findsOneWidget);
  });

  testWidgets('the statistics screen is reachable from the main menu', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp());

    expect(find.text('Statistics'), findsOneWidget);
    await tester.tap(find.text('Statistics'));
    await tester.pumpAndSettle();

    expect(find.text('Statistics'), findsWidgets);
    // A fresh launch has no recorded wins, and checkers has no scores.
    expect(find.text('You have won 0 games.'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('New Game'), findsOneWidget);
  });

  testWidgets('the about screen is reachable from the main menu', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp());

    expect(find.text('About'), findsOneWidget);
    await tester.tap(find.text('About'));
    await tester.pumpAndSettle();

    expect(find.text('Classic Checkers'), findsOneWidget);
    expect(
      find.text('Copyright (c) 2026 Neward & Associates, LLC'),
      findsOneWidget,
    );

    // Reading the version is real async work from the platform channel.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Version 1.2.3 (45)'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('New Game'), findsOneWidget);
  });
}
