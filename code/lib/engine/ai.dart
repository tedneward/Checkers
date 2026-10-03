import 'board.dart';
import 'game.dart';
import 'move.dart';
import 'notation.dart';
import 'piece.dart';
import 'square.dart';

/// A small, deterministic checkers AI.
///
/// The search is a plain negamax with alpha-beta pruning, run under iterative
/// deepening so that it can stop early when it runs out of time. There is no
/// randomness anywhere: the same position and the same search options always
/// produce the same move, which makes the AI easy to test and perfectly
/// repeatable to play against.
class CheckersAI {
  /// Creates an engine that will think about [game].
  CheckersAI(this.game);

  /// The game to play. The search runs on a copy, so thinking about a game
  /// never disturbs it.
  final Game game;

  /// The score of a completely won game.
  static const int mateScore = 1 << 20;

  /// Roughly the biggest score an ordinary position can reach, used as an
  /// infinity when searching.
  static const int infinity = 2 * mateScore;

  /// What an uncrowned man is worth.
  static const int manValue = 100;

  /// What a king is worth, a little more than a man because a king is far
  /// harder to run down.
  static const int kingValue = 175;

  /// How many nodes to look at between checks of the clock.
  static const int _nodesPerTimeCheck = 512;

  int _nodes = 0;

  /// Searches for the best move and reports what it found.
  ///
  /// Pass [depth] to fix how far ahead to look, or [timeLimit] to search as
  /// deep as it can within a budget. With both, the search stops at whichever
  /// limit comes first and still returns the best move found so far.
  ///
  /// Returns [SearchResult.none] when the game is already over.
  SearchResult findBestMove({int depth = 4, Duration? timeLimit}) {
    if (game.isGameOver) return SearchResult.none;

    _nodes = 0;
    final clock = Stopwatch()..start();
    final work = game.copy();
    var best = SearchResult.none;
    for (var reached = 1; reached <= depth; reached++) {
      final attempt = _searchRoot(work, reached, timeLimit, clock);
      if (attempt == null) break; // Out of time; keep the last full depth.
      best = attempt;
      if (timeLimit != null && clock.elapsed >= timeLimit) break;
    }
    return best;
  }

  /// Scores [position] from the point of view of the side to move.
  ///
  /// Higher is better for whoever is to move. The score is a heuristic in
  /// hundredths of a man, not a prediction of the final result.
  static int evaluate(Game position) {
    final board = position.board;
    var score = 0;
    for (final square in board.occupiedSquares) {
      final piece = board[square]!;
      final value = _valueOf(piece, square);
      score += piece.side.isRed == position.sideToMove.isRed ? value : -value;
    }
    return score;
  }

  /// The material and positional worth of [piece] standing on [square].
  static int _valueOf(Piece piece, Square square) {
    if (piece.isKing) {
      // A king is worth most near the middle of the board, where it has more
      // room to manoeuvre.
      const centreBonus = 6;
      final isCentral = square.fileIndex >= 2 && square.fileIndex <= 5;
      return kingValue + (isCentral ? centreBonus : 0);
    }

    // A man gains a little every rank it advances, which is how it survives to
    // be crowned. A man still sitting on its own back row is safer than most,
    // because an uncrowned man can only be jumped by a king.
    const advanceBonus = 4;
    const backRowBonus = 5;
    final advance = _ranksAdvanced(piece.side, square.rankIndex);
    final onBackRow = square.rankIndex == piece.side.startRank;
    return manValue + advance * advanceBonus + (onBackRow ? backRowBonus : 0);
  }

  /// How many ranks [side] has carried a man forward from its own back row.
  static int _ranksAdvanced(Side side, int rankIndex) =>
      side.isRed ? rankIndex - side.startRank : side.startRank - rankIndex;

  /// Looks at every root move of [position] to [depth], or returns `null` when
  /// the time limit has passed.
  SearchResult? _searchRoot(
    Game position,
    int depth,
    Duration? timeLimit,
    Stopwatch clock,
  ) {
    final moves = _ordered(position.legalMoves(), position.board);
    var best = SearchResult.none;
    var bestScore = -infinity;
    var timedOut = false;

    for (final move in moves) {
      final line = <Move>[move];
      position.applyMove(move);
      final score = _negamax(
        position,
        depth - 1,
        -infinity,
        infinity,
        line,
        timeLimit,
        clock,
      );
      position.undo();

      if (score == null) {
        timedOut = true;
        break;
      }
      // The search is written from the point of view of the side to move, so
      // a good reply for the opponent is a bad score here.
      final negated = -score;
      if (negated > bestScore) {
        bestScore = negated;
        best = SearchResult(
          move: move,
          score: negated,
          depthReached: depth,
          nodes: _nodes,
          elapsed: clock.elapsed,
          principalVariation: List<Move>.unmodifiable(line),
        );
      }
    }

    // Nothing at all was finished, so this depth is no better than none.
    if (best.move == null && timedOut) return null;
    return best;
  }

  /// The heart of the search: score [position] for the side to move, or
  /// return `null` when the time limit has passed.
  ///
  /// [line] collects the moves of the best line found so far; it is
  /// overwritten with the line through this node.
  int? _negamax(
    Game position,
    int depth,
    int alpha,
    int beta,
    List<Move> line,
    Duration? timeLimit,
    Stopwatch clock,
  ) {
    // The moves already chosen above this node, which this call must leave
    // alone and only ever append to.
    final prefixLength = line.length;
    _nodes++;

    if (position.isGameOver) {
      final score = _terminalScore(position, line.length);
      line.removeRange(prefixLength, line.length);
      return score;
    }
    if (depth <= 0) {
      final score = evaluate(position);
      line.removeRange(prefixLength, line.length);
      return score;
    }
    if (_outOfTime(timeLimit, clock)) {
      line.removeRange(prefixLength, line.length);
      return null;
    }

    var best = -infinity;
    var bestLine = const <Move>[];

    for (final move in _ordered(position.legalMoves(), position.board)) {
      line.length = prefixLength;
      line.add(move);
      position.applyMove(move);
      final score = _negamax(
        position,
        depth - 1,
        -beta,
        -alpha,
        line,
        timeLimit,
        clock,
      );
      position.undo();
      if (score == null) {
        line.removeRange(prefixLength, line.length);
        return null;
      }
      final negated = -score;
      if (negated > best) {
        best = negated;
        // Only the line from this node down, without the moves already chosen
        // above it.
        bestLine = line.sublist(prefixLength);
      }
      if (negated > alpha) alpha = negated;
      if (alpha >= beta) break; // The opponent would rather have this reply.
    }

    line
      ..length = prefixLength
      ..addAll(bestLine);
    return best;
  }

  /// Scores a finished game, preferring the quickest win and the slowest loss.
  int _terminalScore(Game position, int plies) {
    final outcome = position.outcome;
    // Fewer plies on the clock make a win more valuable and a loss less
    // painful, which keeps the search from shuffling in a won position.
    final distance = mateScore - plies;
    return switch (outcome) {
      GameOutcome.inProgress || GameOutcome.draw => 0,
      GameOutcome.redWin || GameOutcome.blackWin =>
        outcome.winner!.isRed == position.sideToMove.isRed
            ? distance
            : -distance,
    };
  }

  bool _outOfTime(Duration? timeLimit, Stopwatch clock) {
    if (timeLimit == null) return false;
    // Checking the clock on every node costs more than it saves, so only look
    // now and then.
    if (_nodes % _nodesPerTimeCheck != 0) return false;
    return clock.elapsed > timeLimit;
  }

  /// Orders moves so that the most promising are searched first, which is
  /// what makes alpha-beta pruning pay off.
  List<Move> _ordered(List<Move> moves, Board board) {
    final ordered = List<Move>.of(moves);
    ordered.sort((a, b) => _priority(b, board).compareTo(_priority(a, board)));
    return ordered;
  }

  int _priority(Move move, Board board) {
    var priority = move.capturedCount * 1000;
    if (move.promotes) priority += 500;
    if (move.isCapture) {
      // Taking a king is worth more than taking a man.
      final victim = board.pieceAt(move.path[1].index);
      if (victim?.isKing ?? false) priority += 100;
    }
    return priority;
  }
}

/// What the AI found when it searched.
class SearchResult {
  const SearchResult({
    required this.move,
    required this.score,
    required this.depthReached,
    required this.nodes,
    required this.elapsed,
    required this.principalVariation,
  });

  /// The result of a search that found nothing, because the game is over.
  static const none = SearchResult(
    move: null,
    score: 0,
    depthReached: 0,
    nodes: 0,
    elapsed: Duration.zero,
    principalVariation: [],
  );

  /// The best move found, or `null` if the game is already over.
  final Move? move;

  /// The score of [move] in hundredths of a man, from the point of view of the
  /// side that was to move. A very large score means a forced win.
  final int score;

  /// How many plies ahead the search actually managed to look.
  final int depthReached;

  /// How many nodes were examined.
  final int nodes;

  /// How long the search took.
  final Duration elapsed;

  /// The main line of play: the best move, followed by the best reply to it,
  /// and so on.
  ///
  /// The line is as long as the search managed to look, one move per ply.
  final List<Move> principalVariation;

  /// Whether the score is a forced win.
  bool get isWin => score.abs() >= CheckersAI.mateScore - 1000;

  @override
  String toString() =>
      'SearchResult(${move?.notation ?? 'no move'}, score: $score, '
      'depth: $depthReached, nodes: $nodes)';
}
