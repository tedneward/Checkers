// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:shared_preferences/shared_preferences.dart';

import '../../engine/checkers.dart';
import 'settings_persistence.dart';

/// An implementation of [SettingsPersistence] that uses
/// `package:shared_preferences`.
class LocalStorageSettingsPersistence extends SettingsPersistence {
  final Future<SharedPreferences> instanceFuture =
      SharedPreferences.getInstance();

  @override
  Future<bool> getAudioOn({required bool defaultValue}) async {
    final prefs = await instanceFuture;
    return prefs.getBool('audioOn') ?? defaultValue;
  }

  @override
  Future<bool> getMusicOn({required bool defaultValue}) async {
    final prefs = await instanceFuture;
    return prefs.getBool('musicOn') ?? defaultValue;
  }

  @override
  Future<String> getPlayerName() async {
    final prefs = await instanceFuture;
    return prefs.getString('playerName') ?? 'Player';
  }

  @override
  Future<String> getRedPlayerName() async {
    final prefs = await instanceFuture;
    return prefs.getString('redPlayerName') ?? 'Red';
  }

  @override
  Future<String> getBlackPlayerName() async {
    final prefs = await instanceFuture;
    return prefs.getString('blackPlayerName') ?? 'Black';
  }

  @override
  Future<bool> getSoundsOn({required bool defaultValue}) async {
    final prefs = await instanceFuture;
    return prefs.getBool('soundsOn') ?? defaultValue;
  }

  @override
  Future<RuleVariant> getRuleVariant() async {
    final prefs = await instanceFuture;
    // The name is resolved by the engine rather than here, so that a value
    // written by a build which offered different variants falls back to the
    // default instead of taking the app down on startup.
    return RuleVariant.fromName(prefs.getString('ruleVariant'));
  }

  @override
  Future<bool> getAiSuggestionsEnabled({required bool defaultValue}) async {
    final prefs = await instanceFuture;
    return prefs.getBool('aiSuggestionsEnabled') ?? defaultValue;
  }

  @override
  Future<void> saveAudioOn(bool value) async {
    final prefs = await instanceFuture;
    await prefs.setBool('audioOn', value);
  }

  @override
  Future<void> saveMusicOn(bool value) async {
    final prefs = await instanceFuture;
    await prefs.setBool('musicOn', value);
  }

  @override
  Future<void> savePlayerName(String value) async {
    final prefs = await instanceFuture;
    await prefs.setString('playerName', value);
  }

  @override
  Future<void> saveRedPlayerName(String value) async {
    final prefs = await instanceFuture;
    await prefs.setString('redPlayerName', value);
  }

  @override
  Future<void> saveBlackPlayerName(String value) async {
    final prefs = await instanceFuture;
    await prefs.setString('blackPlayerName', value);
  }

  @override
  Future<void> saveRuleVariant(RuleVariant value) async {
    final prefs = await instanceFuture;
    // Stored by name rather than by index, so that adding a variant later does
    // not silently repoint everybody's saved choice at a different one.
    await prefs.setString('ruleVariant', value.name);
  }

  @override
  Future<void> saveAiSuggestionsEnabled(bool value) async {
    final prefs = await instanceFuture;
    await prefs.setBool('aiSuggestionsEnabled', value);
  }

  @override
  Future<void> saveSoundsOn(bool value) async {
    final prefs = await instanceFuture;
    await prefs.setBool('soundsOn', value);
  }
}
