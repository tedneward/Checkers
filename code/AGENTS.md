# AGENTS.md

Guidance for AI agents working in this repository. Written for an agent that
has to make changes safely without a human watching every step.

## What this project is

A Flutter implementation of classic American checkers. The player is red and
moves first; the computer is black. It started as the [Flutter basic game
template](https://flutter.dev/games) and has been converted.

The single most important structural fact:

> **`lib/engine/` must never import Flutter.** It is plain Dart, deliberately.

This is load-bearing, not stylistic. The engine can then be tested in
milliseconds, reasoned about without a widget tree, and lifted into another
project or a bot. A `package:flutter` import in `lib/engine/` is a regression.
`flutter analyze` will not catch it, so check by hand.

All game logic belongs in `lib/engine/`. Anything else — a rule, a position, an
outcome — that lands in `lib/` outside the engine is misplaced.

## Commands

```shell
flutter pub get          # after changing pubspec.yaml
flutter analyze          # must be clean
flutter test             # 260 tests, must all pass
flutter test test/checkers/    # engine only, use this while iterating
flutter run -d macos     # fastest way to actually see the game
flutter build macos --debug    # confirms the whole app compiles
```

Run `flutter test test/checkers/` while working on the engine. It is roughly
fifty times faster than the full suite. Run the full suite plus a build before
you consider a change done.

## Layout

```text
lib/engine/       Rules of checkers. Pure Dart. No Flutter, no widgets.
lib/play_session/ The board, tapping, and the computer's reply in an isolate
lib/router.dart   go_router configuration; /play is the game
lib/audio/        audioplayers wrapper. Kept intact and ready for more sounds.
lib/settings/     Toggles, player name, rule variant, AI suggestions
lib/history/      Recording games, the history list, replay, SQLite storage
lib/style/        Palette, buttons, page transitions, responsive layout shell,
                  and BoardView, the board that play and replay share
lib/rules/        Renders assets/html/rules.html with real widgets
lib/player_progress/  In-memory win counter
lib/main.dart     Entry point, MultiProvider wiring, ThemeData
test/checkers/    One test file per engine module
test/history/     Replay, the SQLite store, the controller, the screens
test/smoke_test.dart  End-to-end checks through the real app
```

## Conventions to follow

### Match the existing engine style

The engine is written in a consistent voice. Read `lib/engine/game.dart` before
adding to it and follow what you find:

- **Doc comments on every public member**, starting with a one-line summary in
  the third person ("The side to play.", not "Gets the side"). Use `///` and
  backtick identifiers. Explain *why*, not just *what*.
- `final` everywhere a field never changes. Immutable values, generously.
- Constructor bodies kept short; factory constructors for named variants
  (`Game.standard`, `Board.fromPosition`, `Game.fromFen`).
- Named parameters for anything a caller might reasonably want to change.
- Private helpers with leading underscore (`_explore`, `_applyCaptureRules`).

### Show settings the way the board shows moves

A setting that changes how the game plays should be visible while playing, not
just in the list. `RuleVariant.find(_game.rules)` reads the variant back off the
game's own rules for exactly this reason: a separate copy of the choice can
drift from what is actually being played. Do the same for anything else that
describes the current game.

### Rule variants are named bundles

When offering players a choice of how the game behaves, do not expose a
seven-toggle mess. Instead put a whole way of playing into
`RuleVariant` in `lib/engine/rules.dart`. Each variant carries:

- `label` — short, one line, used in the Settings list
- `description` — a sentence or two explaining what changes in play
- `rules` — the exact `Rules` bundle it means

Then:
- `RuleVariant.defaultVariant` must preserve the current engine defaults (and
  thus existing tests). Changing it is a product decision with blast radius.
- `RuleVariant.fromName` and `RuleVariant.find` must be tolerant of unknown
  values (fall back to default / return null) because persisted storage outlives
  the build that wrote it.
- `Game.standard(rules: variant.rules)` is how callers actually use it; the
  UI should display the variant by reading `RuleVariant.find(_game.rules)`, not
  by keeping a separate copy that can drift.
- Add exports for new types in `lib/engine/checkers.dart`.

### Add exports in `lib/engine/checkers.dart`

That file is the engine's public API surface. It uses explicit `show` clauses:

```dart
export 'game.dart' show Game, GameOutcome;
```

Anything new that callers outside the engine need must be exported there
explicitly. Do not use a bare `export 'foo.dart';`.

### Prefer named booleans to positional flags

`applyCaptureRules` reads `mustCapture` / `mustCaptureMaximum`, not two bare
bools. Keep that.

## Engine reference

Read these before changing the engine; they are the whole domain model.

| File | Responsibility |
|---|---|
| `square.dart` | 64 squares. Algebraic `a1`-`h8` and checkers numbering 1-32. Diagonal step vectors. `isDarkIndex` is a parity test. |
| `piece.dart` | `Side` (red/black), `PieceKind` (man/king), `Piece`. In notation red is `W`. |
| `board.dart` | Immutable position. Reads/writes `W:W21,22,K29:B1,2`. |
| `move.dart` | A move as an explicit `path`; captured squares are the odd entries. |
| `move_generator.dart` | Legal moves. Walks whole jump chains, not one jump at a time — that is what makes maximum-capture enforceable. |
| `rules.dart` | `Rules` (7 flags), `DrawRules`, and `RuleVariant` (named bundles of rules). |
| `notation.dart` | `b2xa4xc6` in and out. Separators optional. |
| `game.dart` | Public face. Undo/redo, `parseMove`, FEN round-trip, outcome judging. |
| `ai.dart` | Negamax + alpha-beta + iterative deepening. Fully deterministic. |

Key invariants you should not break:

- A `Move` path alternates start, captured, landing, captured, landing. `from`
  and `to` are the ends; captured squares are at odd indices.
- `Game` validates every move before applying it, and maintains undo/redo,
  repetition keys and the quiet-ply counter together. If you change how a move
  is applied, check `_performMove`, `_snapshot` and `_restore` still agree.
- `MoveGenerator` produces *already-filtered* moves. The player must never be
  offered something the rules forbid.
- Board orientation: `a1` is bottom-left from red's view, red starts on ranks
  1-3 and moves toward rank 8. `a1` is playable, so a square is dark when file
  and rank parity agree.

## Rules of the house

These are product decisions. Do not reintroduce the concepts they rule out.

**The AI never plays a side.** This is a two-player game. Both players move on
the same board in `lib/play_session/play_session_screen.dart`, and nothing is
played for the player. `CheckersAI` in `lib/engine/ai.dart` exists only to
*advise*: with the **AI Suggestions** setting on, it marks the best move for
whoever is on turn. Do not reintroduce an AI opponent, an automatic reply, a
"computer moves" turn, or a difficulty/strength choice — the strength of the
adviser is the `_aiDepth` / `_aiTimeLimit` pair at the top of
`play_session_screen.dart` and is not a player-facing option.

Advice and play must stay separate. A suggestion is drawn as a highlight on the
"from" square and named under the board; it is never applied to the game, and it
is recomputed after every move so it cannot describe a stale position. Move
legality for a human is still shown as dots, and the suggestion highlight is
hidden while a piece is in hand so the two sets of markers never compete.

**There are no scores.** Checkers has no points system. No `Score` class, no
high scores, no `_pointsPerCapture`, no score fields on any screen. The
`game_internals/` directory from the original template is gone and must not come
back; anything like it belongs in `lib/engine/`.

There is one thing that looks like a score and must stay: **the AI's search
evaluation** in `lib/engine/ai.dart` (`evaluate`, `SearchResult.score`,
`mateScore`). That is the standard minimax term for evaluating a position. It
has nothing to do with player-facing scoring. Do not rename it, and do not
"remove scoring" from the AI.

**There are no levels.** The player picks no difficulty and sees no level list.
The adviser's search depth is the `_aiDepth` / `_aiTimeLimit` pair at the top of
`lib/play_session/play_session_screen.dart`, not a player setting.
`lib/level_selection/` is deleted.

**There is no `assets/images/`.** All icons are Material `Icons`. The launcher
icons live in `assets/icons/` and are generated by
`dart run flutter_launcher_icons:main`.

**There is one board, not two.** `BoardView` in `lib/style/board_view.dart` is
the only thing that draws a board. Play and replay both use it. Do not copy a
board into a screen: a fix to how the board looks has to apply to both, and a
replay board is a `BoardView` with `enabled: false` rather than a separate
widget. The `ValueKey('square-a3')` keys in it are part of the test contract.

**History must never break play.** `GameHistoryController` logs and swallows
every store error, and `openHistoryStore()` falls back to
`InMemoryGameHistoryStore` when SQLite will not open. Keep it that way. History is
a record of what happened, not a condition for what can happen: a full disk, a
corrupt file, or a locked database must cost the player their place in the
history and nothing else. A screen that only reads history can treat a failed
read as an empty result.

## Non-negotiable rules for edits

1. **Do not add a Flutter import to `lib/engine/`.**
2. **`flutter analyze` must report `No issues found!`**
3. **`flutter test` must pass completely.** Do not delete or skip a test to get
   green. If a test is genuinely obsolete, say so and explain, rather than
   quietly removing it.
4. **Keep the engine's public API exported through
   `lib/engine/checkers.dart`.**
5. **Preserve the isolate contract in `play_session_screen.dart`.** The engine
   entry point must stay a top-level function. A closure would drag its `Zone`
   across the isolate boundary and fail. Position crosses as a FEN string,
   result comes back as notation text, because `Move` is not sendable. There is
   a `_suggestionSearchId` guard against a reply landing after the player moved,
   hit Restart, or left the screen — it is bumped in `dispose` too. Keep all of
   it.
6. **If you delete an `assets/` subdirectory, remove its entry from
   `pubspec.yaml` too**, or the build fails.
7. **Do not re-add audio plumbing as dead code.** It is intact and deliberately
   unused for now; the player intends to add sound.

## Testing expectations

Engine tests are pure Dart: no `testWidgets`, no mocks, no plugin stubs. They
build positions from FEN strings rather than through the UI.

`test/smoke_test.dart` boots the real `MyApp` and navigates it. It calls
`stubAppPlugins()` in `setUpAll` to stand in for `audioplayers`, `path_provider`
and `package_info_plus`, none of which exist under `flutter test`. **Any test
that builds the real app needs those stubs**, or it fails on missing platform
channels.

Reading an asset or asking the platform for a version is real async work.
`testWidgets` only lets it through inside `tester.runAsync(...)`, followed by
`pumpAndSettle()`. The existing tests show the pattern; copy it. The same applies
to the AI suggestion search, which crosses into a real isolate: a test that waits
for a suggestion needs `runAsync` and a delay of a second or more, not just
`pumpAndSettle`.

`SharedPreferences` is one store shared by every test in a file, so a test that
cares about a saved setting must call `SharedPreferences.setMockInitialValues({})`
first, or it inherits whatever the previous test left behind.

Board squares are found by `ValueKey('square-a3')`, which is what
`play_session_board_test.dart` uses. The `_SquareTile` background is the thing to
assert on for highlight behaviour, read via the first descendant `Container`.

When you change navigation, update `smoke_test.dart`. It asserts on visible
text, so renaming a button or a screen breaks it.

## Writing tests

- One file per engine module, named after it: `game_test.dart`,
  `board_test.dart`, and so on.
- Cover the rules, not the implementation. The existing tests are good models:
  they check that a man cannot be crowned twice in one chain, that a king
  cannot land on a square it has already visited, that the maximum-capture rule
  is enforced, that the AI leaves the game it is thinking about untouched.
- Describe behaviour in plain language. `test('a man cannot jump the same piece
  twice in one chain', ...)` not `test('captured contains middle', ...)`.
- Assert on the public API. If a test needs a private member to pass, the
  design is probably wrong.
- Check that a test can actually fail. Temporarily break the behaviour and
  confirm the test goes red, then put it back. A test that passes either way is
  worse than no test, because it reads as coverage. This is worth doing for
  anything where the wiring is easy to get subtly wrong — a value computed in
  one place and displayed from another, for instance.

## Conventions that are not negotiable either

**Formatting.** Dart's standard formatter. Run `dart format .` before
committing. Do not reformat code you did not otherwise touch.

**Comments.** Comment the reasoning, especially around non-obvious rules (why
a king keeps looking down a diagonal past an enemy piece; why the search
manipulates the `line` list by index). Do not narrate what the next line
obviously does. Do not add banner comments to files that lack them.

**No placeholder stubs.** Do not leave `TODO`, an empty method body, or a
function that returns a constant, unless you were asked for it.

**Match the surrounding vocabulary.** This codebase says "man" and "king" (not
"pawn" or "piece type"), "position" (not "board state"), "capture" (not
"take"), and "red"/"black" for the sides while writing `W`/`B` in notation.