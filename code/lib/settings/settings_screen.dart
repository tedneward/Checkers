// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../engine/checkers.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';
import 'rule_variant_dialog.dart';
import 'settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _gap = SizedBox(height: 60);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final palette = context.watch<Palette>();

    return Scaffold(
      backgroundColor: palette.backgroundSettings,
      body: ResponsiveScreen(
        squarishMainArea: ListView(
          children: [
            _gap,
            const Text(
              'Settings',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 55,
                height: 1,
              ),
            ),
            _gap,
            ValueListenableBuilder<bool>(
              valueListenable: settings.soundsOn,
              builder: (context, soundsOn, child) => _SettingsLine(
                'Sound FX',
                Icon(soundsOn ? Icons.graphic_eq : Icons.volume_off),
                onSelected: settings.toggleSoundsOn,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: settings.musicOn,
              builder: (context, musicOn, child) => _SettingsLine(
                'Music',
                Icon(musicOn ? Icons.music_note : Icons.music_off),
                onSelected: settings.toggleMusicOn,
              ),
            ),
            ValueListenableBuilder<RuleVariant>(
              valueListenable: settings.ruleVariant,
              builder: (context, variant, child) => _SettingsLine(
                'Rules',
                Icon(Icons.balance),
                onSelected: () => showRuleVariantDialog(context),
                caption: variant.label,
              ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: settings.aiSuggestionsEnabled,
              builder: (context, enabled, child) => _SettingsLine(
                'AI Suggestions',
                Icon(enabled ? Icons.lightbulb : Icons.lightbulb_outline),
                onSelected: settings.toggleAiSuggestions,
                caption: enabled ? 'On' : 'Off',
              ),
            ),
            _gap,
          ],
        ),
        rectangularMenuArea: MyButton(
          onPressed: () {
            GoRouter.of(context).pop();
          },
          child: const Text('Back'),
        ),
      ),
    );
  }
}

class _SettingsLine extends StatelessWidget {
  final String title;

  final Widget icon;

  final VoidCallback? onSelected;

  /// A short note shown under [title], naming whatever the setting is currently
  /// set to. Lines that are just on or off do not need one.
  final String? caption;

  const _SettingsLine(this.title, this.icon, {this.onSelected, this.caption});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      highlightShape: BoxShape.rectangle,
      onTap: onSelected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Permanent Marker',
                      fontSize: 30,
                    ),
                  ),
                  if (caption != null)
                    Text(
                      caption!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
            icon,
          ],
        ),
      ),
    );
  }
}
