// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';
import 'confirm_delete.dart';
import 'game_history_controller.dart';
import 'game_record.dart';

/// The list of games played on this device, most recent first.
///
/// Selecting a game opens it for replay. Each row has its own trash icon, and
/// the heading has one that wipes every game; both ask first.
class HistoryScreen extends StatefulWidget {
  /// Creates the history list.
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  /// The games on show, or `null` while they are being read.
  List<GameSummary>? _games;

  /// Whether games are being kept only for as long as the app runs.
  ///
  /// Reads alongside the list rather than from the store directly, so that the
  /// notice about not saving is only shown once there is something to notice
  /// about.
  bool _isEphemeral = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final controller = context.read<GameHistoryController>();
    final games = await controller.games();
    final isEphemeral = await controller.isEphemeral;
    if (!mounted) return;
    setState(() {
      _games = games;
      _isEphemeral = isEphemeral;
    });
  }

  Future<void> _confirmAndDelete(GameSummary game) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Delete this game?',
      message:
          'The game played on ${formatGameTime(game.startedAt)} will be '
          'removed. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !mounted) return;

    await context.read<GameHistoryController>().deleteGame(game.id);
    await _load();
  }

  Future<void> _confirmAndDeleteAll() async {
    final games = _games;
    final count = games?.length ?? 0;
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Delete every game?',
      message: count == 0
          ? 'There are no games to delete.'
          : 'All $count recorded games will be removed. This cannot be undone.',
      confirmLabel: 'Delete all',
    );
    if (!confirmed || !mounted) return;

    await context.read<GameHistoryController>().deleteAll();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    return Scaffold(
      backgroundColor: palette.backgroundMain,
      body: ResponsiveScreen(
        topMessageArea: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Flexible so that the heading gives way to the button rather than
            // the row overflowing on a narrow screen. `topMessageArea` is only
            // a fraction of the width, and a 55pt heading is wide.
            const Flexible(
              child: Text(
                'History',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Permanent Marker',
                  fontSize: 55,
                  height: 1,
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('history delete all'),
              tooltip: 'Delete every game',
              icon: const Icon(Icons.delete_sweep),
              onPressed: _confirmAndDeleteAll,
            ),
          ],
        ),
        squarishMainArea: _HistoryList(
          games: _games,
          isEphemeral: _isEphemeral,
          onSelected: (game) => context.push('/history/replay/${game.id}'),
          onDelete: _confirmAndDelete,
          onRetry: _load,
        ),
        rectangularMenuArea: MyButton(
          onPressed: () => GoRouter.of(context).pop(),
          child: const Text('Back'),
        ),
      ),
    );
  }
}

/// The games, or the reason there are none to show.
class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.games,
    required this.isEphemeral,
    required this.onSelected,
    required this.onDelete,
    required this.onRetry,
  });

  /// The games to show, or `null` while they are being read.
  final List<GameSummary>? games;

  /// Whether games are being kept only for as long as the app runs.
  final bool isEphemeral;

  final ValueChanged<GameSummary> onSelected;
  final ValueChanged<GameSummary> onDelete;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final loaded = games;
    if (loaded == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (loaded.isEmpty) {
      return _HistoryMessage(
        title: 'No games yet',
        detail: 'Games you play are listed here so you can watch them back.',
        // An empty history is exactly when this is worth saying: the player is
        // about to play a game they will not be able to come back to, and the
        // list will keep being empty afterwards for the same reason.
        notice: isEphemeral ? _ephemeralWarning : null,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: loaded.length + (isEphemeral ? 1 : 0),
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        if (isEphemeral && index == 0) {
          return const _EphemeralNotice();
        }
        final game = loaded[index - (isEphemeral ? 1 : 0)];
        return _GameRow(game: game, onSelected: onSelected, onDelete: onDelete);
      },
    );
  }
}

/// One game in the list: when it was played, how it ended, and a way to remove
/// it.
class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.game,
    required this.onSelected,
    required this.onDelete,
  });

  final GameSummary game;
  final ValueChanged<GameSummary> onSelected;
  final ValueChanged<GameSummary> onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final turns =
        '${game.moveCount} '
        '${game.moveCount == 1 ? 'move' : 'moves'}';

    return ListTile(
      onTap: () => onSelected(game),
      title: Row(
        children: [
          Expanded(
            child: Text(
              formatGameTime(game.startedAt),
              style: const TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 22,
              ),
            ),
          ),
          Text(
            game.outcomeLabel,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          IconButton(
            key: ValueKey('history delete game ${game.id}'),
            tooltip: 'Delete this game',
            icon: const Icon(Icons.delete_outline),
            color: palette.redPen,
            onPressed: () => onDelete(game),
          ),
        ],
      ),
      subtitle: Text(
        '${game.variant.label} · $turns'
        '${game.termination == null ? '' : ' · ${game.termination}'}',
      ),
    );
  }
}

/// Said when the history is not actually being kept anywhere.
///
/// One string for both the empty list and the full one, so that the two cannot
/// drift apart into saying different things about the same fault.
const String _ephemeralWarning =
    'Games are not being saved on this device, so this list will be empty next '
    'time the app opens.';

/// The same warning, in the form the populated list shows it in.
class _EphemeralNotice extends StatelessWidget {
  const _EphemeralNotice();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        _ephemeralWarning,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}

/// The list is empty, with a note about why.
class _HistoryMessage extends StatelessWidget {
  const _HistoryMessage({
    required this.title,
    required this.detail,
    this.notice,
  });

  final String title;
  final String detail;

  /// Said underneath [detail] when there is something the player should know
  /// before they play their way into it.
  final String? notice;

  @override
  Widget build(BuildContext context) {
    final warning = notice;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 32,
              ),
            ),
            const SizedBox(height: 8),
            Text(detail, textAlign: TextAlign.center),
            if (warning != null) ...[
              const SizedBox(height: 12),
              Text(
                warning,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
