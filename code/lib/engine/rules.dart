import 'piece.dart';

/// The rule variations the engine knows about.
///
/// [Rules.american] describes the classic game of English draughts, which is
/// the default everywhere in this library.
class Rules {
  /// Creates a rule set. Every parameter defaults to the American rule.
  const Rules({
    this.mustCapture = true,
    this.mustCaptureMaximum = true,
    this.menCaptureBackward = true,
    this.longRangedKings = true,
    this.promoteOnArrival = true,
    this.promoteOnPassThrough = false,
    this.autoDeclareMaterialEnd = true,
  });

  /// Classic American checkers: captures are compulsory, the biggest capture
  /// must be taken when several are on offer, men capture in every direction,
  /// kings move and capture any distance, and landing on the far rank crowns
  /// a man at once.
  static const Rules american = Rules();

  /// British draughts: as [Rules.american], except that men can only capture
  /// forwards.
  static const Rules british = Rules(menCaptureBackward: false);

  /// As [Rules.american], except that a player may choose any capture rather
  /// than being forced into the biggest one.
  static const Rules optionalMaximumCapture = Rules(mustCaptureMaximum: false);

  /// Whether a player has to capture at all when a capture is available.
  final bool mustCapture;

  /// Whether a player who has several captures available must play the one
  /// that takes the most pieces.
  final bool mustCaptureMaximum;

  /// Whether men capture backwards as well as forwards.
  final bool menCaptureBackward;

  /// Whether kings capture pieces that are not directly next to them, as
  /// opposed to only jumping an adjacent piece.
  final bool longRangedKings;

  /// Whether a man is crowned as soon as it reaches the far rank, even in the
  /// middle of a capture.
  final bool promoteOnArrival;

  /// Whether a man that leaves the far rank in the middle of a capture is
  /// crowned, even though it is not landing on the far rank.
  ///
  /// This only matters under rulesets that leave a man uncrowned when it
  /// arrives. On an 8x8 board a man can never cross the far rank by jumping
  /// over it, because there is nowhere beyond it to land, so this is what
  /// crowns a man that reaches the far rank and then jumps back off it.
  final bool promoteOnPassThrough;

  /// Whether a side that has been reduced to kings alone is finished at once.
  ///
  /// When true (the default) a side holding only kings wins against a side
  /// that still has men, and two sides holding only kings draw. Some rule sets
  /// only let a player *claim* that result; set this to false to keep playing
  /// out such positions.
  final bool autoDeclareMaterialEnd;

  /// Whether men of [side] crowned by moving to [rank] are promoted, given
  /// the zero-based [rank] they land on.
  bool crownsManOnArrival(Side side, int rank) =>
      promoteOnArrival && rank == side.crownRank;

  @override
  bool operator ==(Object other) =>
      other is Rules &&
      other.mustCapture == mustCapture &&
      other.mustCaptureMaximum == mustCaptureMaximum &&
      other.menCaptureBackward == menCaptureBackward &&
      other.longRangedKings == longRangedKings &&
      other.promoteOnArrival == promoteOnArrival &&
      other.promoteOnPassThrough == promoteOnPassThrough &&
      other.autoDeclareMaterialEnd == autoDeclareMaterialEnd;

  @override
  int get hashCode => Object.hash(
    mustCapture,
    mustCaptureMaximum,
    menCaptureBackward,
    longRangedKings,
    promoteOnArrival,
    promoteOnPassThrough,
    autoDeclareMaterialEnd,
  );

  @override
  String toString() =>
      'Rules(capture: $mustCapture, maxCapture: $mustCaptureMaximum, '
      'menBackward: $menCaptureBackward, flyingKings: $longRangedKings)';
}

/// A rule variation a player can pick between in the app.
///
/// Each variant is a named bundle of [Rules] flags, so that a screen only ever
/// offers one choice instead of a wall of independent toggles. Anything added
/// here has to be a whole way of playing, not a single flag, because the player
/// is choosing between descriptions of how the game behaves.
///
/// The engine does not decide which variant is the right one to play. Callers
/// pass the one they want to [Game.standard] and the rest of the library goes
/// along with it.
enum RuleVariant {
  /// Men jump backwards as readily as forwards.
  ///
  /// A man that has not yet been crowned may jump an enemy piece in any of the
  /// four diagonal directions, so it can take a piece sitting behind it.
  menCaptureAnyDirection(
    label: 'Men capture backwards',
    description:
        'A man that has not been crowned jumps forwards and backwards. '
        'Kings jump either way as well.',
    rules: Rules.american,
  ),

  /// Men jump forwards only, and only a king may jump backwards.
  ///
  /// This is the more common rule for the 8x8 game: a man takes the same two
  /// diagonals it moves along, and the ability to jump backwards is one of the
  /// things crowning buys a piece.
  menCaptureForwardsOnly(
    label: 'Men capture forwards only',
    description:
        'Only a crowned king jumps backwards. Until it reaches the far row a '
        'man jumps forwards only.',
    rules: Rules.british,
  );

  const RuleVariant({
    required this.label,
    required this.description,
    required this.rules,
  });

  /// The variant played when nothing has been chosen, and the one a stored
  /// value falls back to when it cannot be recognised.
  ///
  /// This is the first value in the enum, and the one [Rules.american] spells
  /// out, so a player who never opens Settings plays this.
  static const RuleVariant defaultVariant = RuleVariant.menCaptureAnyDirection;

  /// The short name of this variant, as shown in a settings list.
  final String label;

  /// A sentence or two explaining what a player will actually notice changing.
  ///
  /// It goes next to [label] in the app so that the choice can be made without
  /// knowing the game's vocabulary for it.
  final String description;

  /// The rules this variant plays by.
  final Rules rules;

  /// The variant named [name], or [defaultVariant] when [name] is not one of
  /// them.
  ///
  /// Settings are restored from storage that may have been written by an older
  /// or newer build, or may simply be corrupt, so an unrecognised name falls
  /// back to [defaultVariant] rather than throwing on startup.
  static RuleVariant fromName(String? name) {
    for (final variant in values) {
      if (variant.name == name) {
        return variant;
      }
    }
    return defaultVariant;
  }

  /// Every variant with its label and description, ready to drop into a list.
  static List<RuleVariant> get choices => values;

  /// The variant that plays by [rules], or `null` if none of them do.
  ///
  /// This is how a game names the rules it is actually being played under. A
  /// game can also be created with rules that no variant describes, such as a
  /// preset from an older build or a caller's own set, and then there is no
  /// honest label to show and saying so is better than naming the wrong one.
  static RuleVariant? find(Rules rules) {
    for (final variant in values) {
      if (variant.rules == rules) {
        return variant;
      }
    }
    return null;
  }

  @override
  String toString() => label;
}

/// The conditions under which a game is called a draw.
///
/// A side that has lost all of its pieces, or that has no legal move left, is
/// not drawing: it has lost. These settings only cover the ways a game can
/// otherwise run out of steam.
class DrawRules {
  /// Creates a draw rule set. Every parameter defaults to the American rule.
  const DrawRules({this.repetitionLimit = 3, this.quietMoveLimit = 50});

  /// The classic American draw rules: threefold repetition, or fifty plies
  /// without a capture or a promotion.
  static const DrawRules american = DrawRules();

  /// Never call a draw, so that a game only ends when someone wins.
  static const DrawRules none = DrawRules(
    repetitionLimit: 0,
    quietMoveLimit: 0,
  );

  /// How many times the same position, with the same side to move, may appear
  /// before the game is drawn. Zero disables the rule.
  final int repetitionLimit;

  /// How many plies may pass with neither a capture nor a promotion before the
  /// game is drawn.
  ///
  /// Fifty plies is twenty-five moves by each player, the American limit.
  /// Zero disables the rule.
  final int quietMoveLimit;

  @override
  bool operator ==(Object other) =>
      other is DrawRules &&
      other.repetitionLimit == repetitionLimit &&
      other.quietMoveLimit == quietMoveLimit;

  @override
  int get hashCode => Object.hash(repetitionLimit, quietMoveLimit);

  @override
  String toString() =>
      'DrawRules(repetition: $repetitionLimit, quietPlies: $quietMoveLimit)';
}
