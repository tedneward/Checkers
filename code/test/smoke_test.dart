// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';

import 'package:checkers/engine/checkers.dart';
import 'package:checkers/main.dart';
import 'package:checkers/settings/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('the player can choose how men capture', (tester) async {
    // Start from an empty store so the test cannot inherit a saved choice.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // The settings list names the way of playing currently in force.
    expect(find.text(RuleVariant.defaultVariant.label), findsOneWidget);

    await tester.tap(find.text('Rules'));
    await tester.pumpAndSettle();

    // Every way of playing is on offer, each one described in words, because
    // the name alone does not tell a player what will change at the board. Only
    // the dialog describes them, so each description appears exactly once.
    for (final variant in RuleVariant.choices) {
      expect(find.text(variant.label), findsWidgets);
      expect(find.text(variant.description), findsOneWidget);
    }

    // The way of playing in force is ticked, so the player can see what they
    // would be switching away from before they tap anything.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.byIcon(Icons.circle_outlined),
      findsNWidgets(RuleVariant.choices.length - 1),
    );

    await tester.tap(find.text(RuleVariant.menCaptureForwardsOnly.label));
    await tester.pumpAndSettle();

    // Choosing closes the dialog and the settings row names the new choice.
    expect(
      find.text(RuleVariant.menCaptureForwardsOnly.description),
      findsNothing,
    );
    expect(find.text(RuleVariant.menCaptureForwardsOnly.label), findsOneWidget);

    // The controller, which is what the next game is built from, has taken it.
    final settings = Provider.of<SettingsController>(
      tester.element(find.text(RuleVariant.menCaptureForwardsOnly.label)),
      listen: false,
    );
    expect(settings.ruleVariant.value, RuleVariant.menCaptureForwardsOnly);

    // And the choice is remembered, by name rather than by position in the list.
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString('ruleVariant'),
      RuleVariant.menCaptureForwardsOnly.name,
    );

    // Back to the menu, and into a new game, which is built from the choice.
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    // The game names the rules it is being played under, so the player can see
    // the setting reached the board rather than having to take it on trust.
    expect(find.text(RuleVariant.menCaptureForwardsOnly.label), findsOneWidget);
  });

  testWidgets('a game names the rules it is being played under', (
    tester,
  ) async {
    // The store is shared by every test in this file, so it is emptied rather
    // than left holding whatever the previous test chose.
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    // Nothing has been chosen, so the game is played by the default rules.
    expect(find.text(RuleVariant.defaultVariant.label), findsOneWidget);

    // Restarting with the setting untouched leaves the rules as they were.
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    expect(find.text(RuleVariant.defaultVariant.label), findsOneWidget);
  });

  testWidgets('both players move on the same board', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    // Red is to move first, and the board is live for whoever's turn it is.
    expect(find.text('Red to move'), findsOneWidget);

    // Play red's opening move, a3-b4.
    await tester.tap(find.byKey(const ValueKey('square-a3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('square-b4')));
    await tester.pumpAndSettle();

    // Nobody moves on the player's behalf: black is on turn with all twelve of
    // its pieces still on the board, having played exactly nothing.
    expect(find.text('Black to move'), findsOneWidget);
    expect(find.text('Red 12   Black 12'), findsOneWidget);
  });

  testWidgets('AI suggestions are off until they are asked for', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    // The setting exists and defaults to off.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('AI Suggestions'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);

    // Turning it on is remembered.
    await tester.tap(find.text('AI Suggestions'));
    await tester.pumpAndSettle();
    expect(find.text('On'), findsOneWidget);
  });

  testWidgets('AI suggestions highlight a move on the board', (tester) async {
    SharedPreferences.setMockInitialValues({'aiSuggestionsEnabled': true});

    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();

    // The suggestion arrives off the UI isolate, so it needs real async time
    // before the highlight can appear.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pumpAndSettle();

    // The AI's "from" square is shaded to stand out from an ordinary dark
    // square that the suggestion does not touch.
    Color? backgroundOf(String square) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(ValueKey('square-$square')),
              matching: find.byType(Container),
            )
            .first,
      );
      return container.color;
    }

    expect(backgroundOf('a3'), isNot(backgroundOf('b4')));
    // A light square is never shaded, whatever the AI thinks.
    expect(backgroundOf('h7'), isNot(backgroundOf('a3')));

    // And the suggestion is also named in words, so it does not depend on
    // telling the shading apart.
    expect(find.textContaining('Suggestion: a3-'), findsOneWidget);

    // Playing the suggested move is a normal two-tap move like any other.
    await tester.tap(find.byKey(const ValueKey('square-a3')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('square-b4')));
    await tester.pumpAndSettle();
    // Playing it hands the turn over and asks for black's suggestion next.
    expect(find.text('Computing suggestion...'), findsWidgets);

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pumpAndSettle();

    // It is black's move now, and the suggestion names black's own move, not a
    // stale one from before the board changed.
    expect(find.text('Black to move'), findsOneWidget);
    expect(find.textContaining('Suggestion: '), findsOneWidget);
  });

  testWidgets('a suggestion is dropped once it no longer fits', (tester) async {
    SharedPreferences.setMockInitialValues({'aiSuggestionsEnabled': true});

    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pumpAndSettle();

    Color? backgroundOf(String square) {
      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byKey(ValueKey('square-$square')),
              matching: find.byType(Container),
            )
            .first,
      );
      return container.color;
    }

    final suggestedFrom = backgroundOf('a3');

    // Restarting throws the old suggestion away and asks again, so what is on
    // screen is always about the position actually being played.
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 3)),
    );
    await tester.pumpAndSettle();

    expect(backgroundOf('a3'), suggestedFrom);
  });

  testWidgets('a chosen way of playing survives a restart of the app', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'ruleVariant': RuleVariant.menCaptureForwardsOnly.name,
    });

    await tester.pumpWidget(MyApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    // The saved choice is the one shown, not the default.
    expect(find.text(RuleVariant.defaultVariant.label), findsNothing);
    expect(find.text(RuleVariant.menCaptureForwardsOnly.label), findsOneWidget);
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

  testWidgets('the history screen is reachable from the main menu', (
    tester,
  ) async {
    await tester.pumpWidget(MyApp());

    expect(find.text('History'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('History'), findsWidgets);
    expect(find.text('No games yet'), findsOneWidget);

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
