import 'square.dart';

/// Thrown when a move is not legal in the position it is played in.
class IllegalMoveException implements Exception {
  /// Creates an exception explaining that [message] went wrong.
  const IllegalMoveException(this.message);

  /// A human readable explanation of what went wrong.
  final String message;

  @override
  String toString() => 'IllegalMoveException: $message';
}

/// A single move or capture by one piece.
///
/// The [path] holds every square the piece touches, in order: the square it
/// starts on, then a captured square, then the square it lands on, and so on
/// until the square it finishes on. That makes [from] and [to] the first and
/// last entries, and the captured squares the odd-numbered ones in between.
///
/// A simple move has a two-square path such as `[b2, b4]`. A capture such as
/// `b2xa4` has `[b2, c4, a4]`, and a two-piece capture such as `b2xa4xc6`
/// has `[b2, c4, a4, b6, c6]`.
class Move {
  /// Creates a move along [path], which must start at [from] and end at [to].
  ///
  /// Set [promotes] when playing this move crowns a man.
  Move({
    required this.from,
    required this.to,
    required List<Square> path,
    this.promotes = false,
  }) : path = List<Square>.unmodifiable(path),
       assert(path.length >= 2, 'A move needs a start and an end square'),
       assert(
         path.first == from,
         'The path must start at the square the piece moves from',
       ),
       assert(
         path.last == to,
         'The path must end at the square the piece lands on',
       );

  /// The square the moving piece starts on.
  final Square from;

  /// The square the moving piece finishes on.
  final Square to;

  /// Every square the piece touches, in order.
  ///
  /// The first entry is [from] and the last entry is [to]. The entries in
  /// between are captured pieces and landing squares, alternating.
  final List<Square> path;

  /// Whether this move crowns a man when it is played.
  final bool promotes;

  /// Whether this move takes at least one piece.
  bool get isCapture => path.length > 2;

  /// Whether this move takes two or more pieces.
  bool get isMultiJump => path.length > 4;

  /// The squares of the pieces taken by this move, in the order they are
  /// jumped.
  List<Square> get capturedSquares => [
    for (var i = 1; i + 1 < path.length; i += 2) path[i],
  ];

  /// How many pieces this move takes.
  int get capturedCount => (path.length - 1) ~/ 2;

  /// The squares written down when this move is written in checkers notation:
  /// the square the piece leaves from, then every square it lands on.
  ///
  /// The path of a capture alternates between jumped and landed squares, so
  /// every other entry is one the piece actually stands on. For the capture
  /// `b2xa4xc6` that is `[b2, a4, c6]`.
  List<Square> get notationSquares => isCapture
      ? [for (var i = 0; i < path.length; i += 2) path[i]]
      : [from, to];

  /// This move, with its promotion flag set to [promotes].
  Move withPromotion({required bool promotes}) =>
      Move(from: from, to: to, path: path, promotes: promotes);

  /// This move with the promotion flag cleared.
  Move get withoutPromotion => withPromotion(promotes: false);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Move) return false;
    if (other.from != from || other.to != to) return false;
    if (other.promotes != promotes) return false;
    if (other.path.length != path.length) return false;
    for (var i = 0; i < path.length; i++) {
      if (other.path[i] != path[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(from, to, promotes, Object.hashAll(path));

  @override
  String toString() => '$from${isCapture ? 'x' : '-'}$to${promotes ? '*' : ''}';
}
