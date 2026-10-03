import 'board.dart';
import 'move.dart';
import 'piece.dart';
import 'rules.dart';
import 'square.dart';

/// Generates every legal move for one side in one position.
///
/// A generator is a short-lived value: build one, ask it for [generate], and
/// throw it away. The result is already filtered by the rules, so a player can
/// never be offered a move that [Rules.mustCapture] or
/// [Rules.mustCaptureMaximum] forbids.
///
/// ```dart
/// final moves = MoveGenerator(game.board, game.sideToMove, game.rules)
///     .generate();
/// ```
class MoveGenerator {
  /// Creates a generator for [sideToMove] on [board].
  MoveGenerator(this.board, this.sideToMove, [this.rules = Rules.american]);

  /// The position to generate moves for.
  final Board board;

  /// The side whose moves are generated.
  final Side sideToMove;

  /// The rule variations to obey.
  final Rules rules;

  /// Every legal move for [sideToMove], in no particular order.
  ///
  /// The list is generated once and then cached, so repeated calls are cheap.
  List<Move> generate() => _moves ??= _generate();

  /// Whether [sideToMove] has at least one legal capture.
  bool get hasCapture => generate().any((move) => move.isCapture);

  /// Whether [sideToMove] has any legal move at all.
  ///
  /// A side with no legal move has lost, because a player who cannot move has
  /// no right to pass in checkers.
  bool get hasMoves => generate().isNotEmpty;

  /// Every legal move that starts on [from].
  List<Move> movesFrom(Square from) =>
      generate().where((move) => move.from == from).toList();

  /// The legal move that starts on [from] and ends on [to], if there is one.
  ///
  /// A single capture can reach the same square along more than one path. When
  /// that happens the path that takes the most pieces wins, which is the move
  /// [Rules.mustCaptureMaximum] would have forced anyway.
  Move? findMove(Square from, Square to) {
    final matches = generate()
        .where((move) => move.from == from && move.to == to)
        .toList();
    if (matches.isEmpty) return null;
    if (matches.length == 1) return matches.single;
    matches.sort((a, b) => b.capturedCount.compareTo(a.capturedCount));
    return matches.first;
  }

  List<Move>? _moves;

  List<Move> _generate() {
    final moves = <Move>[];
    for (final from in board.occupiedSquares) {
      final piece = board[from];
      if (piece == null || piece.side != sideToMove) continue;
      _explore(
        from: from,
        piece: piece,
        path: [from],
        captured: const [],
        visited: const {},
        promotes: false,
        out: moves,
      );
    }
    return _applyCaptureRules(moves);
  }

  /// Walks every jump chain that starts at [from], calling [_extend] for each
  /// link in the chain and recording the chains that cannot jump any further.
  ///
  /// Working through chains rather than ply by ply is what lets the generator
  /// hand the rules a whole capture at once, which [Rules.mustCaptureMaximum]
  /// needs in order to compare capture sizes.
  void _explore({
    required Square from,
    required Piece piece,
    required List<Square> path,
    required List<Square> captured,
    required Set<Square> visited,
    required bool promotes,
    required List<Move> out,
  }) {
    final jumps = _jumpsFrom(
      from: path.last,
      piece: piece,
      captured: captured,
      visited: visited,
    );

    if (jumps.isEmpty) {
      if (path.length == 1) {
        // Nothing was jumped, so this piece may only move quietly. Whether a
        // quiet move is allowed at all is settled later, by
        // `_applyCaptureRules`.
        for (final to in _quietMovesFrom(from: from, piece: piece)) {
          out.add(
            Move(
              from: from,
              to: to,
              path: [from, to],
              promotes:
                  piece.isMan &&
                  rules.crownsManOnArrival(piece.side, to.rankIndex),
            ),
          );
        }
      } else {
        // A capture has run its course. It has to be played out in full, so
        // this is one move rather than a choice of where to stop.
        out.add(
          Move(from: from, to: path.last, path: path, promotes: promotes),
        );
      }
      return;
    }

    for (final jump in jumps) {
      final crowned = _crowns(piece, path.last, jump.landing);
      _explore(
        from: from,
        piece: crowned ? piece.promoted : piece,
        path: [...path, Square.at(jump.jumped), Square.at(jump.landing)],
        captured: [...captured, Square.at(jump.jumped)],
        visited: {...visited, Square.at(jump.landing)},
        promotes: promotes || crowned,
        out: out,
      );
    }
  }

  /// Whether a man making this jump earns its crown.
  bool _crowns(Piece piece, Square from, int landing) {
    if (piece.isKing) return false;
    if (rules.crownsManOnArrival(piece.side, Square.rankOf(landing))) {
      return true;
    }
    if (!rules.promoteOnPassThrough) return false;
    // Either the man jumps clean over the crown rank without landing on it, or
    // it is standing on the crown rank when it jumps.
    final crownRank = piece.side.crownRank;
    final fromRank = Square.rankOf(from.index);
    final toRank = Square.rankOf(landing);
    return crownRank == fromRank ||
        crownRank > fromRank && crownRank < toRank ||
        crownRank < fromRank && crownRank > toRank;
  }

  /// The squares [piece] may quietly move to, ignoring captures entirely.
  List<Square> _quietMovesFrom({required Square from, required Piece piece}) {
    final destinations = <Square>[];

    if (piece.isKing) {
      for (final delta in Square.diagonals) {
        var probe = from.index;
        while (true) {
          final next = Square.step(probe, delta);
          if (next == null) break;
          probe = next;
          if (board.pieceAt(next) != null) break;
          destinations.add(Square.at(next));
        }
      }
      return destinations;
    }

    // A man only ever moves one square, and only forwards.
    final deltas = piece.side.isRed ? Square.redForward : Square.blackForward;
    for (final delta in deltas) {
      final next = Square.step(from.index, delta);
      if (next == null) continue;
      if (board.pieceAt(next) != null) continue;
      destinations.add(Square.at(next));
    }
    return destinations;
  }

  /// Every piece that [piece] can jump, starting from [from].
  List<_Jump> _jumpsFrom({
    required Square from,
    required Piece piece,
    required List<Square> captured,
    required Set<Square> visited,
  }) => piece.isKing
      ? _kingJumps(from, piece, captured, visited)
      : _manJumps(from, piece, captured, visited);

  /// The jumps available to a man: one square diagonally, over one enemy
  /// piece, onto an empty square.
  List<_Jump> _manJumps(
    Square from,
    Piece piece,
    List<Square> captured,
    Set<Square> visited,
  ) {
    final jumps = <_Jump>[];
    final deltas = rules.menCaptureBackward
        ? Square.diagonals
        : (piece.side.isRed ? Square.redForward : Square.blackForward);
    for (final delta in deltas) {
      final middle = Square.step(from.index, delta);
      if (middle == null) continue;
      final landing = Square.step(middle, delta);
      if (landing == null) continue;
      // A man may not jump its own men, may not take the same piece twice in
      // one chain, and may not land twice on the same square.
      final victim = board.pieceAt(middle);
      if (victim == null || victim.side == piece.side) continue;
      if (captured.contains(Square.at(middle))) continue;
      if (board.pieceAt(landing) != null) continue;
      if (visited.contains(Square.at(landing))) continue;
      jumps.add(_Jump(middle, landing));
    }
    return jumps;
  }

  /// The jumps available to a king, which slides along a diagonal and may
  /// either take the next piece it meets or, under [Rules.longRangedKings],
  /// any further piece down the diagonal.
  List<_Jump> _kingJumps(
    Square from,
    Piece piece,
    List<Square> captured,
    Set<Square> visited,
  ) {
    final jumps = <_Jump>[];
    for (final delta in Square.diagonals) {
      var probe = from.index;
      var distance = 0;
      while (true) {
        final next = Square.step(probe, delta);
        if (next == null) break;
        distance++;
        probe = next;
        final occupant = board.pieceAt(next);
        if (occupant == null) continue;
        // A king never takes one of its own pieces, and never passes it either.
        final isEnemy = occupant.side != piece.side;

        final inReach = rules.longRangedKings || distance == 1;
        final alreadyTaken = captured.contains(Square.at(next));
        if (isEnemy && inReach && !alreadyTaken) {
          final landing = Square.step(next, delta);
          final free = landing != null && board.pieceAt(landing) == null;
          final fresh =
              landing != null && !visited.contains(Square.at(landing));
          if (free && fresh) {
            jumps.add(_Jump(next, landing));
          }
        }

        // A king cannot pass one of its own pieces. It does keep looking past
        // an enemy piece, since a flying king may carry on along the diagonal
        // after a jump, and the square behind that piece is now empty.
        if (!isEnemy) break;
      }
    }
    return jumps;
  }

  /// Drops quiet moves when captures exist, and small captures when a bigger
  /// one is on offer.
  List<Move> _applyCaptureRules(List<Move> moves) {
    if (!rules.mustCapture) return moves;
    final captures = <Move>[];
    for (final move in moves) {
      if (move.isCapture) captures.add(move);
    }
    if (captures.isEmpty) return moves;
    if (!rules.mustCaptureMaximum) return captures;

    var best = 0;
    for (final move in captures) {
      if (move.capturedCount > best) best = move.capturedCount;
    }
    return [
      for (final move in captures)
        if (move.capturedCount == best) move,
    ];
  }
}

/// One jump in a capture chain: the square of the piece taken, and the square
/// landed on afterwards.
class _Jump {
  const _Jump(this.jumped, this.landing);

  /// The row-major index of the piece being taken.
  final int jumped;

  /// The row-major index of the square landed on.
  final int landing;
}
