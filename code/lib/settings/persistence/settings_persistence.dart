// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../../engine/checkers.dart';

/// An interface of persistence stores for settings.
///
/// Implementations can range from simple in-memory storage through
/// local preferences to cloud-based solutions.
abstract class SettingsPersistence {
  Future<bool> getAudioOn({required bool defaultValue});

  Future<bool> getMusicOn({required bool defaultValue});

  Future<String> getPlayerName();

  /// The rule variation the player last chose, or [RuleVariant.defaultVariant]
  /// if nothing has been stored or the stored name is not one this build knows.
  Future<RuleVariant> getRuleVariant();

  /// Whether AI move suggestions are shown on the board.
  Future<bool> getAiSuggestionsEnabled({required bool defaultValue});

  Future<bool> getSoundsOn({required bool defaultValue});

  Future<void> saveAudioOn(bool value);

  Future<void> saveMusicOn(bool value);

  Future<void> savePlayerName(String value);

  /// Stores [value] by name, which is enough to read it back on any later
  /// version that still offers that variant.
  Future<void> saveRuleVariant(RuleVariant value);

  Future<void> saveAiSuggestionsEnabled(bool value);

  Future<void> saveSoundsOn(bool value);
}
