// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../audio/audio_controller.dart';
import '../audio/sounds.dart';
import '../engine/checkers.dart';
import '../history/game_history_controller.dart';
import '../player_progress/player_progress.dart';
import '../settings/settings.dart';
import '../style/board_view.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';
import 'player_names.dart';

/// How long the AI may spend thinking about a suggestion.
const Duration _aiTimeLimit = Duration(seconds: 2);

/// How many plies the AI looks ahead when suggesting a move.
///
/// The search also runs under [_aiTimeLimit], so this is an upper bound: the
/// search stops at whichever limit comes first.
const int _aiDepth = 6;

/// Plays one game of checkers against another player.
///
/// Players take turns moving on the same board. If AI suggestions are enabled in
/// Settings, the AI marks the best move for the player whose turn it is.
class PlaySessionScreen extends StatefulWidget {
  const PlaySessionScreen({super.key});

  @override
  State<PlaySessionScreen> createState() => _PlaySessionScreenState();
}

class _PlaySessionScreenState extends State<PlaySessionScreen> {
  late Game _game;
  late String _redName;
  late String _blackName;

  /// Red's selected piece, or `null` when nothing is selected.
  Square? _selected;

  /// Whether the AI is computing a suggested move for the side to move.
  bool _thinkingSuggestion = false;

  /// Bumped for every suggestion search, so a reply which lands late can be
  /// recognised as stale.
  int _suggestionSearchId = 0;

  /// The move the AI suggests for the side to move, or `null` if none.
  Move? _suggestedMove;

  @override
  void initState() {
    super.initState();
    _startNewGame();
    _maybeFetchSuggestion();
  }

  /// The rules this game is being played under.
  ///
  /// The setting is read once per game rather than watched. A player cannot
  /// reach Settings mid-game without leaving the board, so there is nothing to
  /// watch for, and reading on every build would only risk rebuilding around a
  /// half-finished suggestion search.
  RuleVariant get _variant =>
      context.read<SettingsController>().ruleVariant.value;

  void _startNewGame() {
    // Read, not watch: the variant chosen in Settings is only consulted when a
    // game begins, so a change made while one is under way cannot reach back
    // and alter a game already in progress. Restarting does pick it up, because
    // restarting is starting a new game.
    //
    // Settings load asynchronously, so on the very first game after launch this
    // may still be reading the default. That matches how the audio settings
    // behave at startup, and by the time the player has found the Settings
    // screen their choice has long since landed.
    final variant = _variant;
    _game = Game.standard(rules: variant.rules);
    _selected = null;
    _suggestedMove = null;
    _thinkingSuggestion = false;
    _suggestionSearchId++;

    final settings = context.read<SettingsController>();
    final extra = GoRouterState.of(context).extra;
    bool randomize = false;
    String? redName;
    String? blackName;
    if (extra is Map) {
      randomize = extra['randomizePlayers'] as bool? ?? false;
      redName = extra['redPlayerName'] as String?;
      blackName = extra['blackPlayerName'] as String?;
    }
    final names = getAssignedNames(
      redName ?? settings.redPlayerName.value,
      blackName ?? settings.blackPlayerName.value,
      randomize,
    );
    _redName = names.red;
    _blackName = names.black;

    // The history is told about a new game here, which forgets whatever game was
    // being recorded. That game stays in the history, unfinished at the last
    // move it reached; hitting Restart is not the same as deleting it.
    context.read<GameHistoryController>().beginGame(
      initialFen: _game.fen,
      variant: variant,
      redPlayerName: _redName,
      blackPlayerName: _blackName,
    );
  }

  @override
  void dispose() {
    // Bumping the id makes any search still running recognise that its answer
    // is no longer wanted, so it cannot call setState on a disposed screen. The
    // search itself is not cancelled, because an isolate mid-search cannot be
    // interrupted; its reply channel is closed by `_askEngineForMove` instead.
    _suggestionSearchId++;
    super.dispose();
  }

  void _onSquareTapped(Square square) {
    if (_thinkingSuggestion || _game.isGameOver) {
      return;
    }

    // Tapping one of the side to move's own pieces selects it, and tapping the
    // selected piece again puts it back down.
    if (_game.board.isOccupiedBy(square, _game.sideToMove)) {
      setState(() => _selected = _selected == square ? null : square);
      return;
    }

    // Otherwise this had better be a square the selected piece can reach. If
    // it isn't, leave the selection where it is so the player can try again.
    final from = _selected;
    if (from == null) {
      return;
    }
    // The move is looked up before it is played rather than letting
    // `tryApplyMoveFrom` find it again, because the move itself is what gets
    // written to the history and the two calls must not be able to disagree
    // about which move was played.
    final move = _game.findMove(from, square);
    if (move == null || !_game.tryApplyMove(move)) {
      return;
    }

    // Not awaited: a player who has just moved should not wait on a disk write
    // before the board updates. The controller logs and carries on if it fails.
    unawaited(context.read<GameHistoryController>().recordMove(move));

    context.read<AudioController>().playSfx(SfxType.buttonTap);
    setState(() {
      _selected = null;
      _suggestedMove = null;
    });
    _maybeFetchSuggestion();

    // The other player moves next, so a suggestion may be wanted immediately.
    // A finished game has nobody to suggest for.
    if (_game.isGameOver) {
      _onGameOver();
    }
  }

  void _maybeFetchSuggestion() {
    if (!_game.isGameOver) {
      _fetchSuggestion();
    }
  }

  /// Fetches an AI suggestion for the side to move if suggestions are enabled.
  Future<void> _fetchSuggestion() async {
    final settings = context.read<SettingsController>();
    if (!settings.aiSuggestionsEnabled.value) {
      if (mounted && (_suggestedMove != null || _thinkingSuggestion)) {
        setState(() {
          _suggestedMove = null;
          _thinkingSuggestion = false;
        });
      }
      return;
    }
    final searchId = ++_suggestionSearchId;
    setState(() => _thinkingSuggestion = true);

    // Read the position before awaiting, so a Restart that lands while the
    // search is in flight cannot change what is being asked about.
    final fen = _game.fen;
    final rules = _game.rules;
    final drawRules = _game.drawRules;

    final notation = await _askEngineForMove(
      fen: fen,
      rules: rules,
      drawRules: drawRules,
      depth: _aiDepth,
    );
    if (!mounted || searchId != _suggestionSearchId) {
      return;
    }
    setState(() => _thinkingSuggestion = false);
    if (notation == null) {
      setState(() => _suggestedMove = null);
      return;
    }
    try {
      setState(() => _suggestedMove = _game.parseMove(notation));
    } on IllegalMoveException {
      setState(() => _suggestedMove = null);
    }
  }

  /// Reports a won game to the win screen.
  void _onGameOver() {
    // Whatever the outcome, the history needs it. This happens before the
    // red-won-only branch below, so a drawn or lost game is recorded as such
    // rather than being left sitting in the history reading "Unfinished".
    unawaited(
      context.read<GameHistoryController>().completeGame(
        outcome: _game.outcome,
        termination: _game.termination,
      ),
    );

    if (_game.outcome != GameOutcome.redWin) {
      // Lost or drawn. Nothing to record, so the result stays on the board.
      return;
    }

    context.read<PlayerProgress>().recordWin();

    if (!mounted) {
      return;
    }
    context.go('/play/won');
  }

  /// The squares the selected piece may move to.
  Set<Square> get _targets {
    final from = _selected;
    if (from == null) {
      return const {};
    }
    return {for (final move in _game.legalMovesFrom(from)) move.to};
  }

  Set<Square> get _suggestedTargets {
    final move = _suggestedMove;
    if (move == null || _selected != null) {
      return const {};
    }
    final path = move.path;
    if (path.length < 2) {
      return const {};
    }
    return {path.last};
  }

  Square? get _suggestedFrom {
    // Hidden while a piece is in hand. The player is mid-decision at that
    // point, and the dot markers already say what that piece can do. Leaving
    // the suggestion up as well would put two incompatible answers on screen at
    // once, and a target dot is far easier to mistake for the suggestion.
    if (_selected != null) {
      return null;
    }
    return _suggestedMove?.from;
  }

  /// The line of text describing whose turn it is, or how the game ended.
  String get _status {
    if (_game.isGameOver) {
      return switch (_game.outcome) {
        GameOutcome.redWin => '$_redName won!',
        GameOutcome.blackWin => '$_blackName won',
        GameOutcome.draw => 'A draw',
        GameOutcome.inProgress => '',
      };
    }
    if (_thinkingSuggestion) {
      return 'Computing suggestion...';
    }
    final name = _game.sideToMove.isRed ? _redName : _blackName;
    return '$name to move';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    return Scaffold(
      backgroundColor: palette.backgroundPlaySession,
      body: ResponsiveScreen(
        topMessageArea: Column(
          children: [
            const Text(
              'Checkers',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 30,
                height: 1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _status,
              style: TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 20,
                color: _thinkingSuggestion
                    ? palette.ink.withValues(alpha: 0.6)
                    : null,
              ),
            ),
          ],
        ),
        squarishMainArea: BoardView(
          board: _game.board,
          lastMove: _game.lastMove,
          selected: _selected,
          targets: _targets.union(_suggestedTargets),
          suggestedFrom: _suggestedFrom,
          enabled: !_thinkingSuggestion && !_game.isGameOver,
          onSquareTapped: _onSquareTapped,
        ),
        rectangularMenuArea: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ButtonRow(
              firstLabel: 'Restart',
              onFirstPressed: () {
                setState(_startNewGame);
                _maybeFetchSuggestion();
              },
              secondLabel: 'Back',
              // `/play` is this screen, so Back goes to the main menu.
              onSecondPressed: () => GoRouter.of(context).go('/'),
            ),
            const SizedBox(height: 10),
            Text(
              'Red ${_game.piecesOf(Side.red)}   '
              'Black ${_game.piecesOf(Side.black)}',
              style: const TextStyle(
                fontFamily: 'Permanent Marker',
                fontSize: 18,
              ),
            ),
            // Names the rules this game is actually being played under, so that
            // a player who just changed the setting can see it took effect. It
            // is read back off the game's own rules rather than off the setting
            // it was built from, so the two cannot drift apart and leave the
            // game playing by something other than what is written here.
            if (RuleVariant.find(_game.rules) case final variant?) ...[
              const SizedBox(height: 2),
              Text(
                variant.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            // Names the suggestion in words as well as shading it on the board,
            // so a player who cannot pick the shading out still gets told which
            // square the AI has in mind.
            if (context
                .watch<SettingsController>()
                .aiSuggestionsEnabled
                .value) ...[
              const SizedBox(height: 2),
              Text(
                _thinkingSuggestion
                    ? 'Computing suggestion...'
                    : switch (_suggestedMove) {
                        final move? =>
                          'Suggestion: '
                              '${move.from.name}-${move.to.name}',
                        null => 'No suggestion',
                      },
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Searches for the best move in a separate isolate and returns its notation.
///
/// This has to be a top-level function rather than a closure. An isolate
/// message carries the entry point itself, and a closure would bring its
/// enclosing [Zone] along with it, which cannot be sent between isolates. A
/// top-level function captures nothing, so only [request] crosses over, and
/// that holds nothing but plain data.
///
/// [request] is `[sendPort, fen, rules, drawRules, depth]`. The isolate ends
/// as soon as it has sent its answer.
void _searchForMove(List<Object?> request) {
  final sendPort = request[0] as SendPort;
  final position = Game.fromFen(
    request[1]! as String,
    rules: request[2]! as Rules,
    drawRules: request[3]! as DrawRules,
  );
  final depth = request[4]! as int;

  sendPort.send(
    CheckersAI(
      position,
    ).findBestMove(depth: depth, timeLimit: _aiTimeLimit).move?.notation,
  );
}

/// Searches [fen] for the best move, off the UI isolate.
///
/// The answer comes back as move notation rather than as a [Move], because a
/// [Move] cannot be sent between isolates but a string can.
Future<String?> _askEngineForMove({
  required String fen,
  required Rules rules,
  required DrawRules drawRules,
  required int depth,
}) async {
  final receive = ReceivePort();
  try {
    await Isolate.spawn(_searchForMove, [
      receive.sendPort,
      fen,
      rules,
      drawRules,
      depth,
    ]);
    return await receive.first as String?;
  } finally {
    receive.close();
  }
}

/// Two buttons side by side, used for the play session's menu area.
class _ButtonRow extends StatelessWidget {
  const _ButtonRow({
    required this.firstLabel,
    required this.onFirstPressed,
    required this.secondLabel,
    required this.onSecondPressed,
  });

  final String firstLabel;
  final VoidCallback? onFirstPressed;
  final String secondLabel;
  final VoidCallback? onSecondPressed;

  @override
  Widget build(BuildContext context) {
    // The menu area is narrow in landscape and on small screens, so the pair of
    // buttons is allowed to shrink rather than overflow.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          MyButton(onPressed: onFirstPressed, child: Text(firstLabel)),
          const SizedBox(width: 12),
          MyButton(onPressed: onSecondPressed, child: Text(secondLabel)),
        ],
      ),
    );
  }
}
