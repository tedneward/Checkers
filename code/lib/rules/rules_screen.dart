// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';
import 'rules_document.dart';

/// Shows the rules for the game, read from the HTML page in `assets/html`.
///
/// The page is loaded once when the screen appears and then drawn with ordinary
/// widgets, so the rules stay a plain HTML file that can be edited and read
/// without Flutter.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  late final Future<List<RulesBlock>> _blocks = _loadRules();

  Future<List<RulesBlock>> _loadRules() async {
    final html = await rootBundle.loadString(kRulesAssetPath);
    return parseRulesDocument(html);
  }

  void _reload() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    return Scaffold(
      backgroundColor: palette.backgroundPlaySession,
      body: ResponsiveScreen(
        topMessageArea: const Text(
          'How to play',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Permanent Marker',
            fontSize: 36,
            height: 1,
          ),
        ),
        squarishMainArea: FutureBuilder<List<RulesBlock>>(
          future: _blocks,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _RulesMessage(
                icon: Icons.error_outline,
                text: 'The rules could not be read from $kRulesAssetPath.',
                onRetry: _reload,
              );
            }

            final blocks = snapshot.data;
            if (blocks == null) {
              return const Center(child: CircularProgressIndicator());
            }
            if (blocks.isEmpty) {
              return _RulesMessage(
                icon: Icons.article_outlined,
                text: 'There are no rules to show yet.',
                onRetry: _reload,
              );
            }

            return _RulesBody(blocks: blocks);
          },
        ),
        rectangularMenuArea: MyButton(
          onPressed: () => GoRouter.of(context).pop(),
          child: const Text('Back'),
        ),
      ),
    );
  }
}

/// The scrollable list of rule blocks.
class _RulesBody extends StatelessWidget {
  const _RulesBody({required this.blocks});

  final List<RulesBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: blocks.length,
      itemBuilder: (context, index) =>
          _RuleBlockView(block: blocks[index], palette: palette),
    );
  }
}

/// Draws one block of the rules page.
class _RuleBlockView extends StatelessWidget {
  const _RuleBlockView({required this.block, required this.palette});

  final RulesBlock block;
  final Palette palette;

  @override
  Widget build(BuildContext context) {
    switch (block.kind) {
      case RulesBlockKind.heading:
        return Padding(
          padding: EdgeInsets.fromLTRB(20, block.level == 1 ? 4 : 20, 20, 8),
          child: Text(
            block.plainText,
            style: TextStyle(
              fontFamily: 'Permanent Marker',
              fontSize: block.level == 1 ? 28 : 20,
              height: 1.1,
              color: palette.ink,
            ),
          ),
        );

      case RulesBlockKind.paragraph:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text.rich(
            TextSpan(
              children: _textSpans(
                block,
                palette.ink,
                const TextStyle(fontSize: 16),
              ),
            ),
          ),
        );

      case RulesBlockKind.listItem:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 10, top: 2),
                child: Text(
                  '•',
                  style: TextStyle(fontSize: 18, color: palette.ink),
                ),
              ),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: _textSpans(
                      block,
                      palette.ink,
                      const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
    }
  }

  List<TextSpan> _textSpans(RulesBlock block, Color color, TextStyle style) {
    return [
      for (final span in block.spans)
        TextSpan(
          text: span.text,
          style: style.copyWith(
            color: color,
            fontWeight: span.bold ? FontWeight.bold : null,
            fontStyle: span.italic ? FontStyle.italic : null,
          ),
        ),
    ];
  }
}

/// What to show when the rules are missing or unreadable.
class _RulesMessage extends StatelessWidget {
  const _RulesMessage({
    required this.icon,
    required this.text,
    required this.onRetry,
  });

  final IconData icon;
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: palette.ink),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: palette.ink),
            ),
            const SizedBox(height: 12),
            MyButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
