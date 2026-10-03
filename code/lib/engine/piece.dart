/// The two sides that play a game of checkers.
enum Side {
  /// Red moves first, towards rank 8. Also called "White" in draughts
  /// position notation, and "black" in some European rule sets.
  red,

  /// Black moves second, towards rank 1.
  black;

  /// The other side.
  Side get opponent => this == Side.red ? Side.black : Side.red;

  /// Whether this is [Side.red].
  bool get isRed => this == Side.red;

  /// The zero-based rank on which this side's men are crowned as kings.
  ///
  /// Red crowns on rank 8, black on rank 1.
  int get crownRank => isRed ? 7 : 0;

  /// The zero-based rank on which this side's men start out.
  int get startRank => isRed ? 0 : 7;

  /// The letter used for this side in checkers position notation.
  String get notationLetter => isRed ? 'W' : 'B';

  /// The name used for this side when explaining a game.
  String get label => isRed ? 'Red' : 'Black';

  /// Parses a side from the letters used in position notation.
  static Side fromNotationLetter(String letter) {
    return switch (letter.toUpperCase()) {
      'W' || 'R' => Side.red,
      'B' => Side.black,
      _ => throw FormatException('Not a side letter', letter),
    };
  }
}

/// Whether a piece is an ordinary man or a crowned king.
enum PieceKind {
  /// An uncrowned piece, which moves one square diagonally forward and jumps
  /// over enemy pieces.
  man,

  /// A crowned piece, which slides any distance along a diagonal and jumps
  /// over enemy pieces from a distance.
  king;

  /// The other kind.
  PieceKind get other => this == PieceKind.man ? PieceKind.king : PieceKind.man;

  /// The letter used for this kind in checkers position notation.
  ///
  /// Men have no letter; kings are written `K`.
  String get notationLetter => this == PieceKind.king ? 'K' : '';
}

/// A single piece on the board: a [side] and a [kind].
///
/// Pieces are immutable values, so copies can be shared freely.
class Piece {
  /// Creates a piece of [side] and [kind].
  const Piece(this.side, this.kind);

  /// Creates an uncrowned red man.
  const Piece.redMan() : this(Side.red, PieceKind.man);

  /// Creates a crowned red king.
  const Piece.redKing() : this(Side.red, PieceKind.king);

  /// Creates an uncrowned black man.
  const Piece.blackMan() : this(Side.black, PieceKind.man);

  /// Creates a crowned black king.
  const Piece.blackKing() : this(Side.black, PieceKind.king);

  /// The side this piece belongs to.
  final Side side;

  /// Whether this piece is a man or a king.
  final PieceKind kind;

  /// Whether this piece has been crowned.
  bool get isKing => kind == PieceKind.king;

  /// Whether this piece is an uncrowned man.
  bool get isMan => kind == PieceKind.man;

  /// This piece, crowned. Kings are returned unchanged.
  Piece get promoted => isKing ? this : Piece(side, PieceKind.king);

  /// A piece of the same [kind] belonging to the other side.
  Piece get opponent => Piece(side.opponent, kind);

  /// The Unicode draughts character used to draw this piece.
  ///
  /// A variation selector is appended so that terminals and browsers render
  /// the character as text rather than as an emoji.
  String get char {
    final base = switch ((side, kind)) {
      (Side.red, PieceKind.man) => '\u26C0',
      (Side.red, PieceKind.king) => '\u26C2',
      (Side.black, PieceKind.man) => '\u26C1',
      (Side.black, PieceKind.king) => '\u26C3',
    };
    // Variation selector 15 asks for the text, rather than emoji, glyph.
    return '$base\uFE0E';
  }

  @override
  bool operator ==(Object other) =>
      other is Piece && other.side == side && other.kind == kind;

  @override
  int get hashCode => Object.hash(side, kind);

  @override
  String toString() => '${side.label} ${kind.name}';
}
