import 'board.dart';
import 'move.dart';
import 'move_generator.dart';
import 'notation.dart';
import 'piece.dart';
import 'rules.dart';
import 'square.dart';

/// How a game ended.
enum GameOutcome {
  /// The game is still being played.
  inProgress,

  /// Red, who moves first, has won.
  redWin,

  /// Black has won.
  blackWin,

  /// Neither side can win, so the game is a draw.
  draw;

  /// The side this outcome favours, or `null` for a draw or a game that is
  /// still running.
  Side? get winner => switch (this) {
    GameOutcome.redWin => Side.red,
    GameOutcome.blackWin => Side.black,
    GameOutcome.inProgress || GameOutcome.draw => null,
  };
}

/// A game of checkers: a position, whose turn it is, and the rules.
///
/// A game owns the rules it is played under and enforces them for you. Legal
/// moves come from [MoveGenerator], moves are checked before they are played,
/// and undo and redo work on everything that has happened.
///
/// ```dart
/// final game = Game.standard();
/// game.applyMoveFrom(Square.parse('c3'), Square.parse('d4'));
/// print(game.render());
/// print(game.sideToMove.notationLetter); // 'B'
/// ```
///
/// The constructor is private, so start a game from one of the factories:
/// [Game.standard], [Game.position] or [Game.fromFen].
class Game {
  Game._(this._board, this._sideToMove, this.rules, this.drawRules)
    : _startingBoard = _board,
      _startingSide = _sideToMove {
    _positionKeys.add(_positionKey);
  }

  /// A new game of classic American checkers from the opening position.
  factory Game.standard({
    Rules rules = Rules.american,
    DrawRules drawRules = DrawRules.american,
  }) => Game._(Board.standardInitial(), Side.red, rules, drawRules);

  /// A new game played from [board], with [sideToMove] to play first.
  ///
  /// The game starts with no history.
  factory Game.position(
    Board board, {
    Side sideToMove = Side.red,
    Rules rules = Rules.american,
    DrawRules drawRules = DrawRules.american,
  }) => Game._(board, sideToMove, rules, drawRules);

  /// A new game read from [fen], the position followed by the side to
  /// move, such as `W:W21,22,K29:B1,2 W`.
  ///
  /// The position names the side to move in its first group, so that letter is
  /// enough on its own; a letter written after the position wins, since that
  /// is where the standard notation puts it. Any further groups in [fen] are
  /// ignored, so a move counter written by other tools still loads.
  factory Game.fromFen(
    String fen, {
    Rules rules = Rules.american,
    DrawRules drawRules = DrawRules.american,
  }) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    final groups = parts.first.split(':');
    final sideToMove = Side.fromNotationLetter(
      parts.length > 1 ? parts[1] : groups.first,
    );
    return Game.position(
      Board.fromPosition(parts.first),
      sideToMove: sideToMove,
      rules: rules,
      drawRules: drawRules,
    );
  }

  /// The rule variations this game is played under.
  final Rules rules;

  /// The draw conditions this game is played under.
  final DrawRules drawRules;

  Board _board;
  Side _sideToMove;
  final Board _startingBoard;
  final Side _startingSide;
  final List<Move> _history = <Move>[];
  final List<_UndoEntry> _undoStack = <_UndoEntry>[];
  final List<_UndoEntry> _redoStack = <_UndoEntry>[];
  final List<String> _positionKeys = <String>[];
  final Map<Side, int> _capturedBy = {Side.red: 0, Side.black: 0};
  int _quietPlies = 0;
  Side? _resignedBy;
  MoveGenerator? _generatorCache;
  ({GameOutcome outcome, String? termination})? _result;

  /// The current position.
  Board get board => _board;

  /// The side to play.
  Side get sideToMove => _sideToMove;

  /// Whether it is red's turn.
  bool get isRedToMove => _sideToMove.isRed;

  /// Every legal move for the side to play, in no particular order.
  List<Move> legalMoves() => _generator.generate();

  /// Whether the side to play has at least one legal move.
  ///
  /// A side with no legal move has lost.
  bool get hasLegalMoves => _generator.hasMoves;

  /// Every legal move that starts on [from].
  List<Move> legalMovesFrom(Square from) => _generator.movesFrom(from);

  /// The legal move that starts on [from] and ends on [to], or `null` if
  /// there is none.
  ///
  /// When a capture can reach [to] along more than one path, the one that
  /// takes the most pieces is returned.
  Move? findMove(Square from, Square to) => _generator.findMove(from, to);

  /// Reads a move such as `b2xa4` and returns the legal move it names.
  ///
  /// Throws an [IllegalMoveException] when no legal move in this position
  /// matches the text.
  Move parseMove(String text) {
    final parsed = Notation.parse(text);
    final candidates = _generator
        .generate()
        .where((move) => move.from == parsed.from && move.to == parsed.to)
        .toList();
    if (candidates.isEmpty) {
      throw IllegalMoveException(
        'No legal move from ${parsed.from.name} to ${parsed.to.name} for '
        '${_sideToMove.label}',
      );
    }
    // A capture of several pieces is written out square by square. Honour that
    // route when it is spelled out, but still accept the shorthand of naming
    // only the start and end squares.
    if (parsed.path.length > 2) {
      final exact = candidates
          .where((move) => _samePath(move.notationSquares, parsed.path))
          .toList();
      if (exact.isNotEmpty) {
        candidates
          ..clear()
          ..addAll(exact);
      }
    }
    if (parsed.promotes) {
      candidates.removeWhere((move) => !move.promotes);
    }
    if (candidates.isEmpty) {
      throw IllegalMoveException('"$text" does not describe a legal move');
    }
    candidates.sort((a, b) => b.capturedCount.compareTo(a.capturedCount));
    return candidates.first;
  }

  /// Plays [move], which must be legal in this position.
  ///
  /// Throws a [StateError] when the game is already over, and an
  /// [IllegalMoveException] when the move is not legal here.
  void applyMove(Move move) {
    if (!tryApplyMove(move)) {
      if (isGameOver) {
        throw StateError(
          'The game is over (${outcome.name}), so $move cannot be played',
        );
      }
      throw IllegalMoveException(
        '${_sideToMove.label} cannot play $move in this position',
      );
    }
  }

  /// Plays [move] if it is legal, and reports whether it was.
  ///
  /// Nothing changes when the move is rejected.
  bool tryApplyMove(Move move) {
    if (isGameOver) return false;
    if (!_generator.generate().contains(move)) return false;
    final before = _snapshot();
    _performMove(move);
    _history.add(move);
    _undoStack.add(_UndoEntry(move, before));
    _redoStack.clear();
    return true;
  }

  /// Plays the legal move that starts at [from] and ends at [to], and returns
  /// the move that was played.
  ///
  /// Throws an [IllegalMoveException] when there is no such move.
  Move applyMoveFrom(Square from, Square to) {
    final move = findMove(from, to);
    if (move == null) {
      throw IllegalMoveException(
        'No legal move from ${from.name} to ${to.name} for ${_sideToMove.label}',
      );
    }
    applyMove(move);
    return move;
  }

  /// Plays the legal move that starts on [from] and ends on [to], if there is
  /// one, and reports whether it was played.
  ///
  /// Nothing changes when there is no such move.
  bool tryApplyMoveFrom(Square from, Square to) {
    final move = findMove(from, to);
    return move != null && tryApplyMove(move);
  }

  /// Takes back the last move and returns it, or returns `null` when there is
  /// nothing to take back.
  Move? undo() {
    if (_undoStack.isEmpty) return null;
    final entry = _undoStack.removeLast();
    _restore(entry.snapshot);
    _history.removeLast();
    _positionKeys.removeLast();
    _redoStack.add(entry);
    return entry.move;
  }

  /// Plays the move taken back by [undo] again, and reports whether there was
  /// one to play.
  bool redo() {
    if (_redoStack.isEmpty) return false;
    final entry = _redoStack.removeLast();
    final before = _snapshot();
    _performMove(entry.move);
    _history.add(entry.move);
    _undoStack.add(_UndoEntry(entry.move, before));
    return true;
  }

  /// Whether a move can be taken back.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether a move taken back can be played again.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Every move played so far, oldest first.
  List<Move> get history => List<Move>.unmodifiable(_history);

  /// The number of moves played so far.
  int get ply => _history.length;

  /// The number of the move being played, counting from one.
  int get moveNumber => _history.length ~/ 2 + 1;

  /// The move played most recently, or `null` at the start of a game.
  Move? get lastMove => _history.isEmpty ? null : _history.last;

  /// How many pieces [side] has taken.
  int capturedBy(Side side) => _capturedBy[side] ?? 0;

  /// How many pieces [side] has left.
  int piecesOf(Side side) => _board.countOf(side);

  /// How many plies have passed with neither a capture nor a promotion.
  int get quietPlies => _quietPlies;

  /// How many times the current position has come up, including now.
  int get repetitionCount {
    final key = _positionKey;
    var count = 0;
    for (final seen in _positionKeys) {
      if (seen == key) count++;
    }
    return count;
  }

  /// How the game ended, or [GameOutcome.inProgress] while it is being played.
  GameOutcome get outcome => _computeResult().outcome;

  /// A short description of how the game ended, or `null` while it is being
  /// played.
  String? get termination => _computeResult().termination;

  /// Whether the game is over, whoever won or drew it.
  bool get isGameOver => outcome != GameOutcome.inProgress;

  /// The side that won, or `null` for a draw or an unfinished game.
  Side? get winner => outcome.winner;

  /// Whether the game ended in a draw.
  bool get isDraw => outcome == GameOutcome.draw;

  /// Gives up the game on behalf of [side].
  void resign(Side side) {
    if (isGameOver) {
      throw StateError('The game is already over (${outcome.name})');
    }
    _resignedBy = side;
    _invalidate();
  }

  /// Puts the game back to the position it started from, keeping the same
  /// rules.
  ///
  /// For [Game.standard] that is the opening position; for a game read from a
  /// position it is that position.
  void reset() {
    _board = _startingBoard;
    _sideToMove = _startingSide;
    _history.clear();
    _undoStack.clear();
    _redoStack.clear();
    _capturedBy[Side.red] = 0;
    _capturedBy[Side.black] = 0;
    _quietPlies = 0;
    _resignedBy = null;
    _positionKeys
      ..clear()
      ..add(_positionKey);
    _invalidate();
  }

  /// An independent copy of this game, carrying the position and the rules but
  /// not the history.
  ///
  /// This is what the AI searches on, so that searching cannot disturb the
  /// game it was asked about.
  Game copy() => Game.position(
    _board,
    sideToMove: _sideToMove,
    rules: rules,
    drawRules: drawRules,
  );

  /// This game as a position in checkers position notation, with the side to
  /// move appended, such as `W:W21,22,K29:B1,2 W`.
  ///
  /// This is what [Game.fromFen] reads, so a game can be written down and
  /// picked up again later.
  String get fen =>
      '${_board.toPosition(sideToMove: _sideToMove)} '
      '${_sideToMove.notationLetter}';

  /// A readable drawing of the board, with rank 8 at the top and a note of
  /// whose turn it is.
  String render() {
    final buffer = StringBuffer(_board.render());
    buffer.writeln();
    if (isGameOver) {
      final winner = this.winner;
      buffer.write(winner == null ? 'Draw' : '${winner.label} wins');
      if (termination != null) buffer.write(' by $termination');
    } else {
      buffer.write('${_sideToMove.label} to move');
    }
    return buffer.toString();
  }

  @override
  String toString() => 'Game($fen)';

  MoveGenerator get _generator =>
      _generatorCache ??= MoveGenerator(_board, _sideToMove, rules);

  ({GameOutcome outcome, String? termination}) _computeResult() =>
      _result ??= _judge();

  ({GameOutcome outcome, String? termination}) _judge() {
    final red = _board.countOf(Side.red);
    final black = _board.countOf(Side.black);

    if (red == 0 && black == 0) {
      return (outcome: GameOutcome.draw, termination: 'No pieces left');
    }
    if (red == 0) {
      return (
        outcome: GameOutcome.blackWin,
        termination: 'Red has no pieces left',
      );
    }
    if (black == 0) {
      return (
        outcome: GameOutcome.redWin,
        termination: 'Black has no pieces left',
      );
    }
    if (_resignedBy case final side?) {
      return (
        outcome: side.isRed ? GameOutcome.blackWin : GameOutcome.redWin,
        termination: 'Resignation',
      );
    }
    if (drawRules.repetitionLimit > 0 &&
        repetitionCount >= drawRules.repetitionLimit) {
      return (outcome: GameOutcome.draw, termination: 'Repetition');
    }
    if (drawRules.quietMoveLimit > 0 &&
        _quietPlies >= drawRules.quietMoveLimit) {
      return (
        outcome: GameOutcome.draw,
        termination: 'No capture or promotion',
      );
    }
    if (rules.autoDeclareMaterialEnd) {
      final redMen = _board.countOf(Side.red, kind: PieceKind.man);
      final blackMen = _board.countOf(Side.black, kind: PieceKind.man);
      if (redMen == 0 && blackMen == 0) {
        return (
          outcome: GameOutcome.draw,
          termination: 'Insufficient material',
        );
      }
      if (redMen == 0 || blackMen == 0) {
        // The side that has been reduced to kings cannot lose, and with no
        // men left anywhere on the board, it cannot be caught either.
        final kingsOnly = redMen > 0 ? Side.black : Side.red;
        return (
          outcome: kingsOnly.isRed ? GameOutcome.redWin : GameOutcome.blackWin,
          termination: 'Insufficient material',
        );
      }
    }
    // A player with no legal move has lost: there is no passing in checkers.
    if (_generator.generate().isEmpty) {
      return (
        outcome: _sideToMove.isRed ? GameOutcome.blackWin : GameOutcome.redWin,
        termination: 'No legal moves',
      );
    }
    return (outcome: GameOutcome.inProgress, termination: null);
  }

  void _performMove(Move move) {
    final piece = _board[move.from];
    final captured = move.capturedSquares;
    final crownsMan = move.promotes && piece != null && piece.isMan;

    var next = _board.withPiece(move.from, null);
    if (captured.isNotEmpty) next = next.withoutPieces(captured);
    _board = next.withPiece(move.to, crownsMan ? piece.promoted : piece);

    _capturedBy[_sideToMove] =
        (_capturedBy[_sideToMove] ?? 0) + captured.length;
    _quietPlies = captured.isEmpty && !crownsMan ? _quietPlies + 1 : 0;
    _sideToMove = _sideToMove.opponent;
    _positionKeys.add(_positionKey);
    _invalidate();
  }

  _Snapshot _snapshot() => _Snapshot(
    _board,
    _sideToMove,
    capturedBy(Side.red),
    capturedBy(Side.black),
    _quietPlies,
  );

  void _restore(_Snapshot snapshot) {
    _board = snapshot.board;
    _sideToMove = snapshot.sideToMove;
    _capturedBy[Side.red] = snapshot.capturedByRed;
    _capturedBy[Side.black] = snapshot.capturedByBlack;
    _quietPlies = snapshot.quietPlies;
    _invalidate();
  }

  void _invalidate() {
    _generatorCache = null;
    _result = null;
  }

  String get _positionKey => _board.toPosition(sideToMove: _sideToMove);

  static bool _samePath(List<Square> a, List<Square> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A move together with the position it was played from.
class _UndoEntry {
  const _UndoEntry(this.move, this.snapshot);

  /// The move that was played.
  final Move move;

  /// Where the game stood just before the move was played.
  final _Snapshot snapshot;
}

/// Everything about a game that a move can change.
class _Snapshot {
  const _Snapshot(
    this.board,
    this.sideToMove,
    this.capturedByRed,
    this.capturedByBlack,
    this.quietPlies,
  );

  /// The position before the move.
  final Board board;

  /// Whose turn it was.
  final Side sideToMove;

  /// How many pieces red had taken.
  final int capturedByRed;

  /// How many pieces black had taken.
  final int capturedByBlack;

  /// How many plies had passed without a capture or promotion.
  final int quietPlies;
}
