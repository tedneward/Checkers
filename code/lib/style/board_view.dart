// Copyright 2026, the Flutter project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/checkers.dart';
import 'palette.dart';

/// The 8x8 board, drawn with rank 8 at the top.
///
/// Shared by the play session and the replay screen so that a game being
/// replayed is drawn exactly as it was when it was played. Two copies of a
/// board would drift, and the replay would then quietly stop being a faithful
/// picture of the stored game.
///
/// Light squares are inert; tapping a dark square tells [onSquareTapped]. The
/// screen chooses whether taps do anything by passing [enabled].
class BoardView extends StatelessWidget {
  /// Creates a board showing [board].
  const BoardView({
    super.key,
    required this.board,
    this.selected,
    this.targets = const {},
    this.suggestedFrom,
    this.lastMove,
    this.enabled = false,
    this.onSquareTapped,
  });

  /// The position to draw.
  final Board board;

  /// The square the player has picked up, if any.
  final Square? selected;

  /// The squares a piece may move to, drawn with a dot.
  final Set<Square> targets;

  /// The square the AI suggests moving from, if it has a suggestion.
  final Square? suggestedFrom;

  /// The move to shade, drawn under [selected] and [suggestedFrom].
  final Move? lastMove;

  /// Whether the board accepts taps at the moment.
  ///
  /// A replay board is a picture of the past, so it passes `false` and has no
  /// callback at all.
  final bool enabled;

  /// Called with the dark square that was tapped.
  final ValueChanged<Square>? onSquareTapped;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

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
                  // Read into a local so that the null check promotes, which it
                  // cannot do for a field of the enclosing widget.
                  final move = lastMove;
                  return SquareTile(
                    square: square,
                    size: size,
                    piece: board[square],
                    isSelected: square == selected,
                    isTarget: targets.contains(square),
                    isSuggested: square == suggestedFrom,
                    isLastMove:
                        move != null &&
                        (square == move.from || square == move.to),
                    enabled: enabled,
                    onTapped: onSquareTapped ?? _ignoreTaps,
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  static void _ignoreTaps(Square _) {}
}

/// One square of the board, with whatever piece is standing on it.
class SquareTile extends StatelessWidget {
  /// Creates one square, [size] wide and high.
  const SquareTile({
    super.key,
    required this.square,
    required this.size,
    required this.piece,
    required this.isSelected,
    required this.isTarget,
    required this.isSuggested,
    required this.isLastMove,
    required this.enabled,
    required this.onTapped,
  });

  /// The square this tile draws.
  final Square square;

  /// How wide and high the tile is, in logical pixels.
  final double size;

  /// The piece standing on [square], or `null` if it is empty.
  final Piece? piece;

  /// Whether [square] holds the piece the player has picked up.
  final bool isSelected;

  /// Whether a selected piece may move here.
  final bool isTarget;

  /// Whether the AI suggests moving from here.
  final bool isSuggested;

  /// Whether [square] is part of the move shaded under everything else.
  final bool isLastMove;

  /// Whether tapping this square does anything.
  final bool enabled;

  /// Called when this square is tapped.
  final ValueChanged<Square> onTapped;

  @override
  Widget build(BuildContext context) {
    final palette = context.watch<Palette>();

    // Light squares carry no pieces, so they are just background.
    final background = switch ((
      square.isDark,
      isSelected,
      isSuggested,
      isLastMove,
    )) {
      (false, _, _, _) => palette.trueWhite,
      (_, true, _, _) => palette.background4,
      (_, _, true, _) => palette.backgroundMain.withValues(alpha: 0.4),
      (_, _, _, true) => palette.backgroundMain,
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
            : PieceView(piece: piece!, size: size),
      ),
    );
  }
}

/// A man or a king, drawn as a disc.
class PieceView extends StatelessWidget {
  /// Creates a picture of [piece] [size] pixels across.
  const PieceView({super.key, required this.piece, required this.size});

  /// The man or king to draw.
  final Piece piece;

  /// The size of the square the piece is standing on.
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
