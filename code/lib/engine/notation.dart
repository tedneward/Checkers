import 'move.dart';
import 'square.dart';

/// A move written down in checkers notation.
///
/// See [Notation.format] for the accepted syntax.
class ParsedNotation {
  /// Creates a parse result from the squares that were written down.
  const ParsedNotation({
    required this.from,
    required this.to,
    required this.path,
    required this.promotes,
  });

  /// The square the move starts on.
  final Square from;

  /// The square the move ends on.
  final Square to;

  /// Every square that was written down, starting at [from] and ending at
  /// [to]. Empty squares in the middle are landing squares that [Game] is
  /// free to fill in with a different route.
  final List<Square> path;

  /// Whether the notation carried a promotion marker.
  final bool promotes;

  /// Whether the notation described a capture.
  bool get isCapture => path.length > 2;
}

/// Reads and writes the classic notation used to score checkers games.
///
/// A quiet move is written as `b2-b4`, a capture as `b2xa4`, a capture of
/// several pieces as `b2xa4xc6`, and a move that crowns a man carries a
/// trailing `*`, as in `e2-e4*`. The `-`, `x` and `X` separators are all
/// optional, so `b2b4` and `B2b4` read the same way.
class Notation {
  const Notation._();

  /// Writes [move] in checkers notation.
  ///
  /// The squares written are the square the piece leaves from and every square
  /// it lands on, which is how checkers games are written down. A capture of
  /// two pieces therefore reads `b2xa4xc6` rather than `b2xc6`. Promotions
  /// are marked with a trailing `*`.
  static String format(Move move) {
    final squares = move.notationSquares;
    final buffer = StringBuffer(squares.first.name);
    for (var i = 1; i < squares.length; i++) {
      buffer
        ..write(move.isCapture ? 'x' : '-')
        ..write(squares[i].name);
    }
    if (move.promotes) buffer.write('*');
    return buffer.toString();
  }

  /// Reads [text] as checkers notation.
  ///
  /// Throws a [FormatException] when [text] is not a move. Note that this only
  /// reads the squares; use `Game.parseMove` to turn the text into a move that
  /// is legal in a given position.
  static ParsedNotation parse(String text) {
    final trimmed = text.trim();
    var body = trimmed;
    final promotes = body.endsWith('*');
    if (promotes) body = body.substring(0, body.length - 1);

    final squares = <Square>[];
    final buffer = StringBuffer();
    for (final rune in body.runes) {
      final char = String.fromCharCode(rune);
      if (Square.fileLetters.contains(char.toLowerCase()) || _isDigit(char)) {
        buffer.write(char);
        if (buffer.length == 2) {
          squares.add(Square.parse(buffer.toString()));
          buffer.clear();
        }
      } else if (char == '-' || char == 'x' || char == 'X') {
        // Separators are for the reader's benefit; the squares carry all the
        // information.
        if (buffer.isNotEmpty) {
          throw FormatException('Stray text in move', text);
        }
      } else {
        throw FormatException('Not a checkers move', text);
      }
    }
    if (buffer.isNotEmpty) throw FormatException('Incomplete square', text);
    if (squares.length < 2) {
      throw FormatException('A move needs at least two squares', text);
    }

    return ParsedNotation(
      from: squares.first,
      to: squares.last,
      path: squares,
      promotes: promotes,
    );
  }

  static bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}

/// Moves written as `b2xa4`.
///
/// This reads better at a call site that is dealing in text, such as an undo
/// stack or a network protocol.
extension MoveNotation on Move {
  /// This move in checkers notation, such as `b2xa4*`.
  String get notation => Notation.format(this);
}
