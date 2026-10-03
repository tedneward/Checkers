// Copyright 2022, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../audio/audio_controller.dart';
import '../audio/sounds.dart';
import '../engine/checkers.dart';
import '../player_progress/player_progress.dart';
import '../settings/settings.dart';
import '../style/my_button.dart';
import '../style/palette.dart';
import '../style/responsive_screen.dart';

/// How long the computer may think about its move.
const Duration _aiTimeLimit = Duration(seconds: 2);

/// How many plies the computer looks ahead before it moves.
///
/// The search also runs under [_aiTimeLimit], so this is an upper bound: the
/// computer stops at whichever limit comes first.
const int _aiDepth = 6;

/// Plays one game of checkers against the computer.
///
/// The player is red and moves first. Tapping one of red's pieces selects it
/// and marks every square it may move to; tapping one of those squares plays
/// the move and hands the turn to the computer.
class PlaySessionScreen extends StatefulWidget {
  const PlaySessionScreen({super.key});

  @override
  State<PlaySessionScreen> createState() => _PlaySessionScreenState();
}

class _PlaySessionScreenState extends State<PlaySessionScreen> {
  late Game _game;

  /// Red's selected piece, or `null` when nothing is selected.
  Square? _selected;

  /// Whether the computer is still deciding its move.
  bool _thinking = false;

  /// Bumped for every game and every search, so that a reply which lands after
  /// the player has already restarted can be recognised as stale.
  int _searchId = 0;

  @override
  void initState() {
    super.initState();
    _startNewGame();
  }

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
    final variant = context.read<SettingsController>().ruleVariant.value;
    _game = Game.standard(rules: variant.rules);
    _selected = null;
    _thinking = false;
    _searchId++;
  }

  void _onSquareTapped(Square square) {
    if (_thinking || _game.isGameOver) {
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
    if (from == null || !_game.tryApplyMoveFrom(from, square)) {
      return;
    }

    context.read<AudioController>().playSfx(SfxType.buttonTap);
    setState(() {
      _selected = null;
      _thinking = true;
    });
    _playComputerMove();
  }

  /// Asks the engine for a reply and plays it.
  Future<void> _playComputerMove() async {
    final searchId = ++_searchId;

    final notation = await _askEngineForMove(
      fen: _game.fen,
      rules: _game.rules,
      drawRules: _game.drawRules,
      depth: _aiDepth,
    );

    // The game may have been restarted while the engine was thinking.
    if (!mounted || searchId != _searchId) {
      return;
    }
    setState(() => _thinking = false);

    if (notation != null) {
      try {
        _game.applyMove(_game.parseMove(notation));
      } on IllegalMoveException {
        // The engine offered a move this position no longer accepts, which
        // should not happen. Leave the turn where it is rather than crash.
        return;
      }
    }

    // Checked whether or not there was a reply: when the player's own move
    // finished the game the engine has nothing to suggest, and the win still
    // has to be reported.
    if (_game.isGameOver) {
      _onGameOver();
    }
  }

  /// Reports a won game to the win screen.
  void _onGameOver() {
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

  /// The line of text describing whose turn it is, or how the game ended.
  String get _status {
    if (_game.isGameOver) {
      return switch (_game.outcome) {
        GameOutcome.redWin => 'You won!',
        GameOutcome.blackWin => 'Black won',
        GameOutcome.draw => 'A draw',
        GameOutcome.inProgress => '',
      };
    }
    if (_thinking) {
      return 'Black is thinking...';
    }
    return '${_game.sideToMove.label} to move';
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
                color: _thinking ? palette.ink.withValues(alpha: 0.6) : null,
              ),
            ),
          ],
        ),
        squarishMainArea: _BoardView(
          game: _game,
          selected: _selected,
          targets: _targets,
          enabled: !_thinking && !_game.isGameOver,
          onSquareTapped: _onSquareTapped,
        ),
        rectangularMenuArea: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ButtonRow(
              firstLabel: 'Restart',
              onFirstPressed: () => setState(_startNewGame),
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
          ],
        ),
      ),
    );
  }
}

/// Searches for black's reply in a separate isolate and returns its notation.
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

/// The 8x8 board, drawn with rank 8 at the top.
///
/// Light squares are inert; tapping a dark square tells [onSquareTapped].
class _BoardView extends StatelessWidget {
  const _BoardView({
    required this.game,
    required this.selected,
    required this.targets,
    required this.enabled,
    required this.onSquareTapped,
  });

  final Game game;

  /// The square the player has picked up, if any.
  final Square? selected;

  /// The squares that piece may move to.
  final Set<Square> targets;

  /// Whether the board accepts taps at the moment.
  final bool enabled;

  final ValueChanged<Square> onSquareTapped;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final lastMove = game.lastMove;

    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: palette.ink, width: 3),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = constraints.biggest.width / Square.boardSize;
              return GridView.builder(
                // Without this, a `GridView` whose `padding` is null wraps its
                // sliver in a `SliverPadding` built from `MediaQuery.padding`
                // along the scroll axis. `ResponsiveScreen` deliberately leaves
                // the top and bottom insets unconsumed, so the notch and the
                // home indicator would be added to the board's height here and
                // then clipped away, taking the bottom row of pieces with them.
                // The screen above already handled the safe area.
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Square.boardSize,
                ),
                itemCount: Square.count,
                itemBuilder: (context, index) {
                  // The grid starts at the top left, but squares are numbered
                  // from a1 in the bottom left, so walk the ranks downwards.
                  final rankIndex =
                      Square.boardSize - 1 - index ~/ Square.boardSize;
                  final square = Square.atFileRank(
                    index % Square.boardSize,
                    rankIndex,
                  );
                  return _SquareTile(
                    square: square,
                    size: size,
                    piece: game.board[square],
                    isSelected: square == selected,
                    isTarget: targets.contains(square),
                    isLastMove:
                        lastMove != null &&
                        (square == lastMove.from || square == lastMove.to),
                    enabled: enabled,
                    onTapped: onSquareTapped,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

/// One square of the board, with whatever piece is standing on it.
class _SquareTile extends StatelessWidget {
  const _SquareTile({
    required this.square,
    required this.size,
    required this.piece,
    required this.isSelected,
    required this.isTarget,
    required this.isLastMove,
    required this.enabled,
    required this.onTapped,
  });

  final Square square;
  final double size;
  final Piece? piece;
  final bool isSelected;
  final bool isTarget;
  final bool isLastMove;
  final bool enabled;
  final ValueChanged<Square> onTapped;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    // Light squares carry no pieces, so they are just background.
    final background = switch ((square.isDark, isSelected, isLastMove)) {
      (false, _, _) => palette.trueWhite,
      (_, true, _) => palette.background4,
      (_, _, true) => palette.backgroundMain,
      _ => palette.backgroundSettings,
    };

    return GestureDetector(
      key: ValueKey('square-${square.name}'),
      onTap: enabled && square.isDark ? () => onTapped(square) : null,
      child: Container(
        color: background,
        alignment: Alignment.center,
        child: piece == null
            // An empty square the piece may move to gets a dot.
            ? (isTarget
                  ? Container(
                      width: size * 0.25,
                      height: size * 0.25,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.ink.withValues(alpha: 0.35),
                      ),
                    )
                  : null)
            : _PieceView(piece: piece!, size: size),
      ),
    );
  }
}

/// A man or a king, drawn as a disc.
class _PieceView extends StatelessWidget {
  const _PieceView({required this.piece, required this.size});

  final Piece piece;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();
    final diameter = size * 0.8;

    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: piece.side.isRed ? palette.redPen : palette.inkFullOpacity,
        // A king is marked by a ring, so the two kinds read apart at a glance.
        border: piece.isKing
            ? Border.all(color: palette.trueWhite, width: size * 0.08)
            : null,
      ),
    );
  }
}
