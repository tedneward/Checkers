// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/checkers.dart';
import 'settings.dart';

/// Shows the player the rule variations they can pick between.
///
/// Each option carries a description of what actually changes in play, because
/// the names alone ("forwards only" against "any direction") do not tell a
/// player what they will see at the board.
void showRuleVariantDialog(BuildContext context) {
  showGeneralDialog(
    context: context,
    pageBuilder: (context, animation, secondaryAnimation) =>
        RuleVariantDialog(animation: animation),
  );
}

class RuleVariantDialog extends StatelessWidget {
  final Animation<double> animation;

  const RuleVariantDialog({required this.animation, super.key});

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<SettingsController>().ruleVariant.value;

    return ScaleTransition(
      scale: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
      child: SimpleDialog(
        title: const Text('How men capture'),
        children: [
          // The options are laid out as full-width rows rather than as a radio
          // group, because the description is the part that decides the choice
          // and a radio button leaves no room for it.
          for (final variant in RuleVariant.choices)
            _RuleVariantOption(variant: variant, selected: variant == selected),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _RuleVariantOption extends StatelessWidget {
  final RuleVariant variant;

  final bool selected;

  const _RuleVariantOption({required this.variant, required this.selected});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        context.read<SettingsController>().setRuleVariant(variant);
        Navigator.pop(context);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    variant.label,
                    style: TextStyle(
                      fontFamily: 'Permanent Marker',
                      fontSize: 22,
                      fontWeight: selected ? FontWeight.bold : null,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    variant.description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            // A check against the option in force, so the player can see what
            // they are switching away from before they tap.
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
