/// One of the 64 squares of a standard 8x8 checkers board.
///
/// Checkers is played on the 32 dark squares of the board, which carry the
/// classic algebraic names `a1` through `h8`.
///
/// The board is oriented from [Side.red]'s point of view, with file `a` on the
/// left and rank `1` nearest to red — the side that moves first.
///
/// Internally a square is a plain `int` in `[0, 64)`, laid out in rows of
/// eight starting at `a1`:
///
/// ```text
/// 63 62 61 60 59 58 57 56   rank 8
/// 55 54 53 52 51 50 49 48   rank 7
/// ...
///  7  6  5  4  3  2  1  0   rank 1
///  a  b  c  d  e  f  g  h
/// ```
///
/// Because `a1` is a playable dark square, a square is playable exactly when
/// its file and rank agree on being even or on being odd, which makes
/// [isDarkIndex] a cheap parity test.
class Square {
  /// Creates the square with the given row-major [index].
  const Square(this.index)
    : assert(index >= 0 && index < count, 'index out of range');

  /// The row-major index of this square, in `[0, 64)`.
  final int index;

  /// The width and height of the board, in squares.
  static const int boardSize = 8;

  /// The total number of squares on the board, dark and light alike.
  static const int count = boardSize * boardSize;

  /// The number of playable (dark) squares.
  static const int darkCount = count ~/ 2;

  /// The letters used for the eight files, from left to right.
  static const String fileLetters = 'abcdefgh';

  /// A diagonal step of one file left and one rank up, as used by red.
  static const (int, int) upLeft = (-1, 1);

  /// A diagonal step of one file right and one rank up, as used by red.
  static const (int, int) upRight = (1, 1);

  /// A diagonal step of one file left and one rank down, as used by black.
  static const (int, int) downLeft = (-1, -1);

  /// A diagonal step of one file right and one rank down, as used by black.
  static const (int, int) downRight = (1, -1);

  /// All four diagonal steps.
  static const List<(int, int)> diagonals = [
    upLeft,
    upRight,
    downLeft,
    downRight,
  ];

  /// The two diagonal steps that lead away from the red back rank.
  static const List<(int, int)> redForward = [upLeft, upRight];

  /// The two diagonal steps that lead away from the black back rank.
  static const List<(int, int)> blackForward = [downLeft, downRight];

  /// Every square on the board, in row-major order starting at `a1`.
  static final List<Square> all = List<Square>.unmodifiable([
    for (var i = 0; i < count; i++) Square(i),
  ]);

  /// The 32 playable (dark) squares, in row-major order starting at `a1`.
  static final List<Square> darkSquares = List<Square>.unmodifiable([
    for (var i = 0; i < count; i++)
      if (isDarkIndex(i)) Square(i),
  ]);

  /// The zero-based file of this square, where `0` is the `a` file.
  int get fileIndex => index % boardSize;

  /// The zero-based rank of this square, where `0` is rank 1.
  int get rankIndex => index ~/ boardSize;

  /// Whether this is one of the 32 playable dark squares.
  bool get isDark => isDarkIndex(index);

  /// The classic algebraic name of this square, such as `a1` or `h8`.
  String get name => nameOf(index);

  /// The 1-based square number used by the standard checkers position
  /// notation (FEN), where 1 is `b8` and 32 is `g1`.
  int get number => numberOf(index);

  /// The square with the given row-major [index].
  ///
  /// The index is only range-checked, so callers that accept untrusted input
  /// should use [Square.parse] instead.
  static Square at(int index) => Square(index);

  /// The square at the given zero-based [file] and [rank].
  static Square atFileRank(int file, int rank) => Square(indexOf(file, rank));

  /// The row-major index of the square at [file], [rank], both zero-based.
  static int indexOf(int file, int rank) => rank * boardSize + file;

  /// The zero-based file of [index].
  static int fileOf(int index) => index % boardSize;

  /// The zero-based rank of [index].
  static int rankOf(int index) => index ~/ boardSize;

  /// Whether [index] is a playable (dark) square.
  ///
  /// `a1` is playable, and so is `b8`, which means a square is playable when
  /// its file and its rank agree on being even or on being odd.
  static bool isDarkIndex(int index) =>
      index.isEven == (index ~/ boardSize).isEven;

  /// The classic algebraic name of the square at [index].
  static String nameOf(int index) =>
      '${fileLetters[fileOf(index)]}${rankOf(index) + 1}';

  /// The checkers notation number of the square at [index], from 1 to 32.
  ///
  /// Numbers run in reading order from the top left of the board as red sees
  /// it, four to a rank, so `b8` is 1, `h8` is 4, `a7` is 5, and `g1` is 32.
  static int numberOf(int index) {
    assert(
      isDarkIndex(index),
      'Only playable squares have a checkers number: $index',
    );
    return (boardSize - 1 - rankOf(index)) * (boardSize ~/ 2) +
        fileOf(index) ~/ 2 +
        1;
  }

  /// The square with the given checkers notation [number], from 1 to 32.
  static Square fromNumber(int number) {
    if (number < 1 || number > darkCount) {
      throw RangeError.range(number, 1, darkCount, 'number');
    }
    final row = (number - 1) ~/ (boardSize ~/ 2);
    final column = (number - 1) % (boardSize ~/ 2);
    // Playable files are the even ones on even ranks and the odd ones on odd
    // ranks, so which file a column stands for depends on the rank.
    final rank = boardSize - 1 - row;
    final file = column * 2 + (rank.isEven ? 0 : 1);
    return atFileRank(file, rank);
  }

  /// Parses a classic algebraic square name such as `a1` or `H8`.
  ///
  /// Surrounding whitespace is ignored and the file letter is
  /// case-insensitive.
  static Square parse(String name) {
    final trimmed = name.trim().toLowerCase();
    if (trimmed.length != 2) {
      throw FormatException('Not a square name', name);
    }
    final file = fileLetters.indexOf(trimmed[0]);
    final rank = int.tryParse(trimmed[1]);
    if (file < 0 || rank == null || rank < 1 || rank > boardSize) {
      throw FormatException('Not a square name', name);
    }
    return atFileRank(file, rank - 1);
  }

  /// Parses a square name, returning `null` instead of throwing.
  static Square? tryParse(String name) {
    try {
      return parse(name);
    } on FormatException {
      return null;
    }
  }

  /// The index one diagonal [delta] away from [from], or `null` when that
  /// would leave the board.
  ///
  /// Unlike simple arithmetic on [index], this refuses to wrap around the edge
  /// of the board, so it always yields a genuine neighbour.
  static int? step(int from, (int, int) delta) {
    final (fileStep, rankStep) = delta;
    final file = fileOf(from) + fileStep;
    final rank = rankOf(from) + rankStep;
    if (file < 0 || file >= boardSize || rank < 0 || rank >= boardSize) {
      return null;
    }
    return indexOf(file, rank);
  }

  @override
  bool operator ==(Object other) => other is Square && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => name;
}
