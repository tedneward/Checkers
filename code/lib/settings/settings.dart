// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import '../engine/checkers.dart';
import 'persistence/local_storage_settings_persistence.dart';
import 'persistence/settings_persistence.dart';

/// An class that holds settings like [playerName] or [musicOn],
/// and saves them to an injected persistence store.
class SettingsController {
  static final _log = Logger('SettingsController');

  /// The persistence store that is used to save settings.
  final SettingsPersistence _store;

  /// Whether or not the audio is on at all. This overrides both music
  /// and sounds (sfx).
  ///
  /// This is an important feature especially on mobile, where players
  /// expect to be able to quickly mute all the audio. Having this as
  /// a separate flag (as opposed to some kind of {off, sound, everything}
  /// enum) means that the player will not lose their [soundsOn] and
  /// [musicOn] preferences when they temporarily mute the game.
  ValueNotifier<bool> audioOn = ValueNotifier(true);

  /// The player's name. Kept for player-facing screens that greet the player.
  ValueNotifier<String> playerName = ValueNotifier('Player');

  /// Name of the player using the red pieces.
  ValueNotifier<String> redPlayerName = ValueNotifier('Red');

  /// Name of the player using the black pieces.
  ValueNotifier<String> blackPlayerName = ValueNotifier('Black');

  /// Whether or not the sound effects (sfx) are on.
  ValueNotifier<bool> soundsOn = ValueNotifier(true);

  /// Whether or not the music is on.
  ValueNotifier<bool> musicOn = ValueNotifier(true);

  /// Whether or not AI move suggestions are shown on the board.
  ValueNotifier<bool> aiSuggestionsEnabled = ValueNotifier(false);

  /// Which way of playing the game the player has chosen.
  ///
  /// This is a whole [RuleVariant] rather than a single boolean because the
  /// variants bundle several rules together and the player is choosing between
  /// descriptions of how the game plays, not flipping flags one at a time.
  ///
  /// A game that is already under way keeps the rules it started with; this
  /// only decides the rules the next game is created with.
  ValueNotifier<RuleVariant> ruleVariant = ValueNotifier(
    RuleVariant.defaultVariant,
  );

  /// Creates a new instance of [SettingsController] backed by [store].
  ///
  /// By default, settings are persisted using [LocalStorageSettingsPersistence]
  /// (i.e. NSUserDefaults on iOS, SharedPreferences on Android or
  /// local storage on the web).
  SettingsController({SettingsPersistence? store})
    : _store = store ?? LocalStorageSettingsPersistence() {
    _loadStateFromPersistence();
  }

  void setPlayerName(String name) {
    playerName.value = name;
    _store.savePlayerName(playerName.value);
  }

  void setRedPlayerName(String name) {
    redPlayerName.value = name;
    _store.saveRedPlayerName(name);
  }

  void setBlackPlayerName(String name) {
    blackPlayerName.value = name;
    _store.saveBlackPlayerName(name);
  }

  void toggleAudioOn() {
    audioOn.value = !audioOn.value;
    _store.saveAudioOn(audioOn.value);
  }

  void toggleMusicOn() {
    musicOn.value = !musicOn.value;
    _store.saveMusicOn(musicOn.value);
  }

  void toggleSoundsOn() {
    soundsOn.value = !soundsOn.value;
    _store.saveSoundsOn(soundsOn.value);
  }

  void toggleAiSuggestions() {
    aiSuggestionsEnabled.value = !aiSuggestionsEnabled.value;
    _store.saveAiSuggestionsEnabled(aiSuggestionsEnabled.value);
  }

  /// Remembers the [variant] the player picked for the next game.
  void setRuleVariant(RuleVariant variant) {
    ruleVariant.value = variant;
    _store.saveRuleVariant(variant);
  }

  /// Asynchronously loads values from the injected persistence store.
  Future<void> _loadStateFromPersistence() async {
    final loadedValues = await Future.wait([
      _store.getAudioOn(defaultValue: true).then((value) {
        if (kIsWeb) {
          // On the web, sound can only start after user interaction, so
          // we start muted there on every game start.
          return audioOn.value = false;
        }
        // On other platforms, we can use the persisted value.
        return audioOn.value = value;
      }),
      _store
          .getSoundsOn(defaultValue: true)
          .then((value) => soundsOn.value = value),
      _store
          .getMusicOn(defaultValue: true)
          .then((value) => musicOn.value = value),
      _store.getPlayerName().then((value) => playerName.value = value),
      _store.getRedPlayerName().then((value) => redPlayerName.value = value),
      _store.getBlackPlayerName().then(
        (value) => blackPlayerName.value = value,
      ),
      _store.getRuleVariant().then((value) => ruleVariant.value = value),
      _store
          .getAiSuggestionsEnabled(defaultValue: false)
          .then((value) => aiSuggestionsEnabled.value = value),
    ]);

    _log.fine(() => 'Loaded settings: $loadedValues');
  }
}
