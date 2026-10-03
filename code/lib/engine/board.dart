import 'piece.dart';
import 'square.dart';

/// An immutable 8x8 checkers position.
///
/// A board holds at most one [Piece] per square, and only on the 32 playable
/// dark squares. Because boards are values, positions can be shared and copied
/// cheaply enough to be used as search nodes by an AI.
class Board {
  Board._(List<Piece?> squares) : _squares = List<Piece?>.unmodifiable(squares);

  /// A board with no pieces on it.
  factory Board.empty() =>
      Board._(List<Piece?>.filled(Square.count, null, growable: false));

  /// A board with the given [pieces] placed on it.
  ///
  /// Throws an [ArgumentError] when a piece would sit on a light square.
  factory Board.fromSetup(Map<Square, Piece> pieces) {
    for (final square in pieces.keys) {
      if (!square.isDark) {
        throw ArgumentError.value(
          square,
          'pieces',
          'Pieces can only sit on playable (dark) squares',
        );
      }
    }
    final squares = List<Piece?>.filled(Square.count, null, growable: false);
    for (final MapEntry(:key, :value) in pieces.entries) {
      squares[key.index] = value;
    }
    return Board._(squares);
  }

  /// The standard opening position: twelve red men on ranks 1 to 3, facing
  /// twelve black men on ranks 6 to 8.
  factory Board.standardInitial() {
    final pieces = <Square, Piece>{};
    for (final square in Square.darkSquares) {
      final rank = square.rankIndex;
      if (rank <= 2) {
        pieces[square] = const Piece.redMan();
      } else if (rank >= 5) {
        pieces[square] = const Piece.blackMan();
      }
    }
    return Board.fromSetup(pieces);
  }

  /// Reads a board from a position in checkers position notation, for
  /// example `W:W21,22,K29:B1,K2`.
  ///
  /// The three groups are the side to move, red's pieces and black's pieces.
  /// An empty group is written as nothing at all, so a board with no black
  /// pieces reads `W:W21,22:`.
  factory Board.fromPosition(String position) {
    final groups = position.split(':');
    if (groups.length != 3) {
      throw FormatException(
        'A position reads "<side to move>:<red>:<black>"',
        position,
      );
    }
    // Validates the side letter, which tells us who is to move.
    Side.fromNotationLetter(groups[0]);
    final pieces = <Square, Piece>{};
    for (var i = 1; i < 3; i++) {
      final side = i == 1 ? Side.red : Side.black;
      // Each group is prefixed with its side letter, as in `W21,22`, but the
      // prefix is optional.
      var group = groups[i];
      if (group.isNotEmpty && group[0] != 'K') {
        if (Side.fromNotationLetter(group[0]) != side) {
          throw FormatException('Wrong side for this group', groups[i]);
        }
        group = group.substring(1);
      }
      for (final entry in group.split(',')) {
        if (entry.isEmpty) continue;
        // Kings may be written as `K29` or as `29K`; accept both.
        final isKing = entry.startsWith('K') || entry.endsWith('K');
        final digits = entry.replaceAll('K', '');
        final number = int.tryParse(digits);
        if (number == null) {
          throw FormatException('Not a square number', entry);
        }
        pieces[Square.fromNumber(number)] = Piece(
          side,
          isKing ? PieceKind.king : PieceKind.man,
        );
      }
    }
    return Board.fromSetup(pieces);
  }

  final List<Piece?> _squares;

  /// The piece on [square], or `null` if the square is empty.
  Piece? operator [](Square square) => _squares[square.index];

  /// The piece on the square at [index], or `null`.
  Piece? pieceAt(int index) => _squares[index];

  /// Whether [square] is free of pieces.
  bool isEmptyAt(Square square) => _squares[square.index] == null;

  /// Whether [square] is occupied.
  bool isOccupied(Square square) => _squares[square.index] != null;

  /// Whether [square] is occupied by a piece of [side].
  bool isOccupiedBy(Square square, Side side) =>
      _squares[square.index]?.side == side;

  /// A copy of this board with [piece] on [square]; a `null` [piece] clears
  /// the square.
  Board withPiece(Square square, Piece? piece) {
    final squares = List<Piece?>.of(_squares, growable: false);
    squares[square.index] = piece;
    return Board._(squares);
  }

  /// A copy of this board with the pieces on [squares] removed.
  Board withoutPieces(Iterable<Square> squares) {
    final next = List<Piece?>.of(_squares, growable: false);
    for (final square in squares) {
      next[square.index] = null;
    }
    return Board._(next);
  }

  /// Every occupied square, in row-major order from `a1`.
  Iterable<Square> get occupiedSquares => Square.darkSquares.where(isOccupied);

  /// The pieces belonging to [side], in row-major order from `a1`.
  List<Piece> piecesOf(Side side, {PieceKind? kind}) => [
    for (final square in occupiedSquares)
      if (this[square]!.side == side &&
          (kind == null || this[square]!.kind == kind))
        this[square]!,
  ];

  /// The squares holding a piece of [side], optionally of a given [kind].
  List<Square> squaresOf(Side side, {PieceKind? kind}) => [
    for (final square in occupiedSquares)
      if (this[square]!.side == side &&
          (kind == null || this[square]!.kind == kind))
        square,
  ];

  /// How many pieces [side] still has, optionally counting only [kind].
  int countOf(Side side, {PieceKind? kind}) {
    var count = 0;
    for (final square in occupiedSquares) {
      final piece = this[square]!;
      if (piece.side == side && (kind == null || piece.kind == kind)) {
        count++;
      }
    }
    return count;
  }

  /// The total number of pieces on the board.
  int get pieceCount => occupiedSquares.length;

  /// Whether the board has no pieces at all.
  bool get isEmpty => _squares.every((piece) => piece == null);

  /// This board as a position in checkers position notation.
  ///
  /// The position reads as three groups: the side to move, then red's pieces,
  /// then black's pieces, so a board with no black pieces reads `W:W21,22:`.
  /// Each group is prefixed with the letter of the side it belongs to and its
  /// kings are written `K`, as in `W:W21,22,K29:B1,K2`.
  String toPosition({Side sideToMove = Side.red}) =>
      '${sideToMove.notationLetter}:W${_groupOf(Side.red)}:'
      'B${_groupOf(Side.black)}';

  /// The pieces of [side] written as `21,22,K29`, ordered by square.
  String _groupOf(Side side) {
    final squares = Square.darkSquares.toList()
      ..sort((a, b) => a.number.compareTo(b.number));
    return squares
        .where((square) => isOccupiedBy(square, side))
        .map((square) => '${this[square]!.kind.notationLetter}${square.number}')
        .join(',');
  }

  /// A readable drawing of the board, with rank 8 at the top.
  String render() {
    final buffer = StringBuffer();
    for (var rank = Square.boardSize - 1; rank >= 0; rank--) {
      buffer.write('${rank + 1}  ');
      for (var file = 0; file < Square.boardSize; file++) {
        final square = Square.atFileRank(file, rank);
        final piece = this[square];
        if (piece != null) {
          buffer.write(piece.char);
        } else if (square.isDark) {
          buffer.write('\u00B7');
        } else {
          buffer.write(' ');
        }
      }
      buffer.writeln();
    }
    buffer.write('   abcdefgh');
    return buffer.toString();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Board) return false;
    for (var i = 0; i < Square.count; i++) {
      if (_squares[i] != other._squares[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_squares);

  @override
  String toString() => render();
}
