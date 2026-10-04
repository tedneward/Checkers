// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../engine/checkers.dart';
import '../style/board_view.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import 'game_history_controller.dart';
import 'replay_session.dart';

/// How tall one row of the move list is.
///
/// Fixed so that the list can be scrolled straight to the move on the board:
/// with a fixed row height its offset is known without measuring anything.
const double _moveRowExtent = 44;

/// Watches a recorded game move by move.
///
/// The board shows the position at the current point in the game and the list
/// below shows every move, with the one on the board marked. Stepping forwards
/// and backwards plays the recorded moves through the engine, so the position
/// shown is the one the rules actually produce rather than an approximation
/// rebuilt from the move list.
class ReplayScreen extends StatefulWidget {
  /// Creates a replay of the game with [gameId].
  const ReplayScreen({super.key, required this.gameId});

  /// The game to replay, as handed out by the history store.
  final int gameId;

  @override
  State<ReplayScreen> createState() => _ReplayScreenState();
}

class _ReplayScreenState extends State<ReplayScreen> {
  final ScrollController _moveScroll = ScrollController();

  ReplaySession? _session;

  /// True when the game could not be read at all, as opposed to being absent.
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _moveScroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final record = await context.read<GameHistoryController>().game(
      widget.gameId,
    );
    if (!mounted) return;
    setState(() {
      _session = record == null ? null : ReplaySession(record);
      _missing = record == null;
    });
    // Open on the last move. A finished game is nearly always what someone
    // opening it wants to see, and stepping back from there is the natural
    // thing to do next. An unfinished one is already at the end for the same
    // reason.
    if (record != null && record.moves.isNotEmpty) {
      _goTo(record.moves.length);
    }
  }

  void _goTo(int ply) {
    final session = _session;
    if (session == null) return;
    setState(() => session.goTo(ply));
    _scrollToCurrent(session);
  }

  void _scrollToCurrent(ReplaySession session) {
    if (!_moveScroll.hasClients) return;
    final index = session.ply - 1;
    if (index < 0) {
      _moveScroll.jumpTo(0);
      return;
    }
    final target = (index * _moveRowExtent).clamp(
      0.0,
      _moveScroll.position.maxScrollExtent,
    );
    _moveScroll.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final session = _session;

    return Scaffold(
      backgroundColor: palette.backgroundPlaySession,
      body: SafeArea(
        child: session == null
            ? _MissingGame(isMissing: _missing, onRetry: _load)
            : Column(
                children: [
                  Expanded(flex: 3, child: _boardArea(session)),
                  Divider(height: 1, color: palette.ink.withValues(alpha: 0.2)),
                  Expanded(flex: 4, child: _moveArea(session)),
                ],
              ),
      ),
    );
  }

  Widget _boardArea(ReplaySession session) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '${session.record.outcomeLabel} · '
                  '${session.record.variant.label}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: 'Permanent Marker',
                    fontSize: 18,
                  ),
                ),
              ),
              Text(
                session.isAtStart
                    ? 'Start'
                    : 'Move ${session.ply} of ${session.totalPlies}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: BoardView(
            board: session.board,
            lastMove: session.lastMove,
            // A replay is a picture of a finished game. Tapping it does
            // nothing, so no taps are taken and no dots are drawn.
            enabled: false,
          ),
        ),
      ],
    );
  }

  Widget _moveArea(ReplaySession session) {
    return Column(
      children: [
        if (session.isTruncated)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'This game could only be replayed ${session.playablePlies} of '
              '${session.totalPlies} moves.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        Expanded(
          child: session.totalPlies == 0
              ? const Center(child: Text('No moves were played in this game.'))
              : ListView.builder(
                  controller: _moveScroll,
                  itemExtent: _moveRowExtent,
                  itemCount: session.totalPlies,
                  itemBuilder: (context, index) {
                    final notation = session.moveNotationAt(index) ?? '';
                    final isCurrent = session.isCurrentPly(index);
                    // Even indices are red's moves and odd are black's, because
                    // the record is one entry per ply and red moves first.
                    final side = index.isEven ? Side.red : Side.black;
                    return ListTile(
                      dense: true,
                      selected: isCurrent,
                      selectedTileColor: context
                          .watch<Palette>()
                          .backgroundMain
                          .withValues(alpha: 0.6),
                      leading: SizedBox(
                        width: 28,
                        child: Text(
                          '${index + 1}',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      title: Text(
                        notation,
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: side.isRed
                              ? context.watch<Palette>().redPen
                              : null,
                        ),
                      ),
                      onTap: () => _goTo(index + 1),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton.filled(
                key: const ValueKey('replay back'),
                tooltip: 'Back to the history',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => GoRouter.of(context).pop(),
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                key: const ValueKey('replay previous'),
                tooltip: 'Previous move',
                icon: const Icon(Icons.chevron_left),
                onPressed: session.canGoBack
                    ? () => _goTo(session.ply - 1)
                    : null,
              ),
              const SizedBox(width: 12),
              IconButton.filled(
                key: const ValueKey('replay next'),
                tooltip: 'Next move',
                icon: const Icon(Icons.chevron_right),
                onPressed: session.canGoForward
                    ? () => _goTo(session.ply + 1)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The game could not be shown, with a way back out.
class _MissingGame extends StatelessWidget {
  const _MissingGame({required this.isMissing, required this.onRetry});

  /// True when the store has no such game, as opposed to failing to answer.
  final bool isMissing;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isMissing ? 'That game is gone' : 'That game could not be read',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 28,
              ),
            ),
            const SizedBox(height: 16),
            if (!isMissing)
              MyButton(onPressed: onRetry, child: const Text('Try again')),
            const SizedBox(height: 8),
            MyButton(
              onPressed: () => GoRouter.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
