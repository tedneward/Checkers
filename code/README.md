# Checkers

Classic checkers, built with Flutter. Two players take turns on the same board,
red moving first.

The game runs on iOS, Android, macOS, Windows, Linux and the web from a single
Flutter codebase. An AI is available as an optional move adviser, but it never
plays a side.

## Getting started

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install). On a
Mac, `brew install flutter` is enough; follow the linked guide for other
platforms. Then:

```shell
cd code
flutter pub get
flutter run
```

To play on your Mac without a simulator, run `flutter run -d macos` and you get
the same UI in a desktop window. That is the fastest way to work on the game.

## How to play

Open **Rules** from the main menu for the full rules. The short version:

- Red moves first. Each player moves one piece per turn.
- Men move one square diagonally forwards. Kings move any distance along a
  diagonal.
- You **must** capture when you can. If several captures are available you must
  play the one that takes the most pieces.
- Whether an uncrowned man may capture backwards is a setting. See
  [Choosing how men capture](#choosing-how-men-capture).
- When a man reaches the far side of the board it is crowned and becomes a king.
- Win by taking all of the computer's pieces, or by leaving it with no legal
  move. A game is drawn after three repetitions of the same position, or after
  50 moves by each player with no capture and no promotion.

Click one of your pieces to pick it up. The squares it can reach light up with a
dot. Click one of those to move. There is no drag-and-drop; every move is two
clicks.

Both players move on the same board; nothing is played for you. When a move is
played the screen names who is on turn, and the last move stays shaded.

### AI suggestions

**Settings > AI Suggestions** turns on an adviser. With it on, the AI works out
the best move for whoever is on turn and:

- shades the square the move starts from,
- names it in words under the board, as `Suggestion: a3-b4`.

It is only advice. Nobody's move is made for you, and you are free to play
something else. The suggestion is worked out again after every move, so it
always refers to the position actually on the board. While a piece is in hand
the shading is hidden, because the dots already say what that piece can do and
two competing sets of markers would only be confusing.

The search runs in an isolate so the board stays responsive while it thinks, and
its strength is the `_aiDepth` / `_aiTimeLimit` pair at the top of
`lib/play_session/play_session_screen.dart`. It is advice only, so the two are
tuned for a quick reply rather than for an unbeatable opponent.

## History and replay

Every game you play is recorded move by move. **History** on the main menu lists
them, most recent first, with the date and time it started, how it ended, the
rules it was played under, and how many moves it lasted. Selecting one opens it
for replay.

The replay screen puts the board on top and the move list underneath. The board
opens on the last move; step back with the left arrow and forward with the right,
or tap any move in the list to jump straight to it. The board is a picture of a
game that has already happened, so tapping it does nothing.

Replay works by feeding the recorded moves back through the same engine that
played them, rather than rebuilding the position from the move list. If a stored
move no longer parses, or is no longer legal under the rules in this build, the
replay stops at it and says how much of the game it managed to show rather than
failing or inventing a position that never happened.

Two trash-can icons delete games. The one in each row deletes that game; the one
by the heading wipes every recorded game. Both ask first.

### Where games are stored

A SQLite database, `history.db`, in the platform's application documents
directory. That is deliberately the documents directory and not the database
directory `sqflite` offers, because it is the one platforms back up:

| Platform | Storage |
|---|---|
| iOS | Documents directory, backed up to iCloud Drive and visible in the Files app |
| Android | Documents directory, included in Google auto-backup |
| macOS | Documents directory inside the app sandbox container |
| Windows, Linux | Documents directory, local only |
| Web | IndexedDB via `sqlite3.wasm`, local to the browser profile |

iOS and macOS have `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace`
set in their `Info.plist`, which is what puts that directory in Files and Finder.

macOS is not actually synced to iCloud Drive, only made visible in Finder.
Real sync there needs an iCloud container entitlement, which has to be
provisioned for the app id before it can be added to
`macos/Runner/DebugProfile.entitlements`:

```xml
<key>com.apple.developer.ubiquity-container-identifiers</key>
<array>
    <string>iCloud.com.example.checkers</string>
</array>
```

If the database cannot be opened at all, the app falls back to keeping games in
memory for the session and the history screen says so. Losing history is not a
reason to stop somebody playing checkers.

### Rebuilding the web SQLite binaries

`web/sqlite3.wasm` and `web/sqflite_sw.js` are checked in so a web build needs no
extra step. If the `sqlite3` dependency version changes, regenerate them with:

```shell
dart run sqflite_common_ffi_web:setup
```

The setup tool pins its own copy of `sqlite3.wasm`, which does not have to match
the version `pubspec.lock` resolved — it is currently hardcoded to 3.6.0 while
the app resolves 3.7.0, so the checked-in `.wasm` is the 3.7.0 one from the
[sqlite3.dart releases][sqlite3-releases]. The mismatch does not show up at build
time, so when the version changes, fetch the matching release and compare:

```shell
curl -sLO https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-<version>/sqlite3.wasm
shasum -a 256 sqlite3.wasm web/sqlite3.wasm
```

[sqlite3-releases]: https://github.com/simolus3/sqlite3.dart/releases

## Project layout

```text
code
├── lib
│   ├── engine            The rules of checkers. No Flutter, no widgets.
│   ├── play_session      The board you play on, and the computer's reply
│   ├── history           Recording games, the history list, and replay
│   ├── audio             Music and sound effects
│   ├── settings          Sound, music, name, rules, AI suggestions, reset
│   ├── style             Colours, buttons, transitions, responsive layout,
│   │                     and the BoardView that play and replay share
│   ├── rules             The how-to-play screen
│   ├── statistics        How many games you have won
│   ├── about             Name, copyright, version
│   ├── main_menu         The first screen
│   ├── win_game          Shown when you win
│   ├── player_progress   Counts your wins
│   ├── app_lifecycle     Lets audio pause when the app goes away
│   ├── main.dart         Entry point and dependency wiring
│   └── router.dart       Navigation between screens
│
├── assets
│   ├── html/rules.html   The text of the rules screen, as plain HTML
│   ├── sfx               Sound effects
│   ├── music             Background music
│   ├── icons             Launcher icon source images
│   └── fonts             Permanent Marker, used for all headings
│
└── test
    ├── checkers          Engine tests, one file per part
    ├── history           Replay, the SQLite store, the controller, the screens
    └── smoke_test.dart   A few end-to-end checks through the real app
```

The split that matters most: **`lib/engine/` knows nothing about Flutter.** It
is plain Dart, so the rules can be tested quickly and could be lifted into
another project, a server, or a bot without dragging any UI along. Everything
that draws or taps lives outside it.

## Development

Run the tests:

```shell
flutter test
```

Run the linter, which is configured in `analysis_options.yaml`:

```shell
flutter analyze
```

Both should be clean before you commit.

### Working on the engine

The engine is where the interesting logic lives, and it is fast to test:

```shell
flutter test test/checkers/
```

A few things worth knowing if you change it:

- `Game` is the front door. Create one with `Game.standard()`, play moves with
  `applyMove`, and ask it for legal moves with `legalMovesFrom`. It owns the
  rules and will refuse an illegal move.
- `MoveGenerator` produces moves for one position and is thrown away after.
  It walks whole jump chains rather than one jump at a time, which is what lets
  it enforce the maximum-capture rule.
- `Rules` holds the rule variations. `Rules.american` is the default;
  `Rules.british` and `Rules.optionalMaximumCapture` are the alternates. Adding
  a variation means adding a flag and honouring it, not branching in the UI.
- `RuleVariant` is what the player picks between in Settings: a named bundle of
  `Rules` flags with a label and a description. Prefer adding one of these over
  exposing raw flags.
- Positions round-trip through a text form, `W:W21,22,K29:B1,2 W`, via
  `game.fen` and `Game.fromFen`. Tests use this constantly; it is the easiest
  way to set up a specific position.

### Working on the board

`play_session_screen.dart` owns the current game and the computer's reply. The
computer runs in a background isolate so a long search cannot freeze the
interface. You pass the position across as a FEN string and get back a move as
notation text, because a `Move` cannot be sent between isolates.

Difficulty is two constants at the top of that file: `_aiDepth` and
`_aiTimeLimit`. Raise the depth for a harder opponent, but leave the time limit
in place so the game never feels like it has hung.

### Working on the history

Four things, in the order they matter.

- `BoardView` in `lib/style/board_view.dart` draws the board. Play and replay
  both use it, so a fix to how the board looks applies to both at once. Do not
  draw a second board in a screen; pass `enabled: false` if it is not
  interactive.
- `GameHistoryController` records games and reads them back. Every write is
  chained rather than fired off, and every operation is logged and swallowed on
  failure: history is a record of what happened, not a condition for what can
  happen, so a full disk must never stop somebody finishing a game.
- `GameHistoryStore` is the interface; `SqliteGameHistoryStore` and
  `InMemoryGameHistoryStore` are the two implementations. The in-memory one is
  what the app falls back to when the database will not open, and what the
  screen tests use.
- `ReplaySession` steps through one recorded game. It applies moves with the
  engine and undoes them with `Game.undo`, because checkers has no inverse
  move: putting a piece back and moving it elsewhere is not undoing a jump.

The schema is two tables, `games` and `moves`, with `ON DELETE CASCADE` from the
second to the first. That is what makes deleting one game take its moves with it
without either delete having to know about the other.

## Building for release

```shell
# iOS, then open Xcode to sign and upload
flutter build ipa && open build/ios/archive/Runner.xcarchive

# Android, then open the folder containing the bundle
flutter build appbundle && open build/app/outputs/bundle/release

# macOS
flutter build macos
```

For a web build that you can push to GitHub Pages:

```shell
flutter pub global run peanut \
  --web-renderer canvaskit \
  --extra-args "--base-href=/your_repo_name/" \
  && git push origin --set-upstream gh-pages
```

Note that audio is disabled automatically on the web: browsers block autoplay
until the player interacts with the page.

## Sound

Audio is wired up and working; only one sound is used at the moment, a tap when
you place a piece. To add more:

- Drop the file into `assets/sfx/`.
- Add an entry to the `SfxType` enum and a line to its filename list in
  `lib/audio/sounds.dart`. Pick from several filenames and one is chosen at
  random, which is how you avoid machine-gun repetition of one sample.
- Call `context.read<AudioController>().playSfx(SfxType.yourSound)` from
  wherever it belongs. The play session screen is the obvious spot.

`SfxType` still carries several entries inherited from the Flutter game
template that this game does not use (`huhsh`, `wssh`, `erase`, `swishSwish`).
They are harmless, and every one of them is loaded at startup, so delete the
unused ones if you want to trim startup work. You can also replace the
placeholder music in `assets/music/`, which is Creative Commons music by
[Mr Smith][mr-smith] included with permission.

[mr-smith]: https://freemusicarchive.org/music/mr-smith

## Settings

Sound effects, music, a player name, the chosen way of playing and whether AI
suggestions are on are stored on the device with `shared_preferences`. To change
what is saved or how, edit the files in `lib/settings/persistence/`.
`SettingsPersistence` is the interface,
`LocalStorageSettingsPersistence` is the real implementation, and
`SettingsController` in `settings.dart` is what the UI reads.

Progress is deliberately kept in memory only, so it resets each launch.

Game history is the exception to the last point. Recorded games go to SQLite so
they survive a restart, unlike wins, which are only a count of games you have
won and have no history worth keeping.

### Choosing how men capture

**Settings > Rules** picks between the ways of playing the engine knows about.
Currently that is one choice:

| Option | What it means |
|---|---|
| Men capture backwards | An uncrowned man jumps forwards and backwards. Kings jump either way as well. |
| Men capture forwards only | Only a crowned king jumps backwards. Until it reaches the far row a man jumps forwards only. |

Each option carries a one-line description of what changes in play, and the
play screen names the rules the game in front of you is actually being played
under, so you can see the choice took effect.

The setting applies to the **next** game, never to one already in progress. The
game keeps the rules it started with, and `Restart` re-reads the setting because
restarting is starting a new game.

The choice lives in the engine as `RuleVariant`, a named bundle of `Rules`
flags, so the screens offer one choice with a description rather than a wall of
independent toggles. To add a variation:

1. Add a value to `RuleVariant` in `lib/engine/rules.dart` with its `label`,
   `description` and `rules`.
2. Give it a test in `test/checkers/rules_test.dart`.

It appears in the Settings dialog automatically — there is nothing to wire up.
The variant is stored by `name`, so renaming or removing one falls back to the
default on a player's next launch instead of breaking startup.

### Variable rules worth considering

`Rules` has seven flags. One (`menCaptureBackward`) is player-selectable today.
The rest are fixed, and each is a real variation that draughts players argue
about, so they are the obvious next candidates. Note that two of them also
differ from the historical American game, which is worth settling before either
is exposed:

| Flag | Default | The variation it controls |
|---|---|---|
| `menCaptureBackward` | `true` | **Player-selectable.** Whether an uncrowned man may jump backwards. |
| `longRangedKings` | `true` | "Flying kings", which may move and capture any distance along a diagonal. Historical American checkers uses **short** kings, moving one square at a time; flying kings are the international rule. |
| `mustCaptureMaximum` | `true` | Whether the biggest capture must be taken when several are on offer. American checkers lets a player choose any sequence, as long as every capture in it is made. |
| `mustCapture` | `true` | Whether capturing is compulsory at all. Rarely varied in practice. |
| `promoteOnArrival` | `true` | Whether a man is crowned the instant it reaches the far row. Turning this off lets it jump back off that row as a man; `promoteOnPassThrough` then decides whether a man merely passing through is crowned. |
| `autoDeclareMaterialEnd` | `true` | Whether holding only kings against a side that still has men ends the game immediately. |
| `repetitionLimit`, `quietMoveLimit` (`DrawRules`) | `3`, `50` | Draw handling. These live on `DrawRules` rather than `Rules`. |

Worth deciding first: which of these should a player ever be offered, and which
are simply wrong for the game as advertised. Exposing a flag that disagrees with
the rules screen is worse than not offering it.

## Troubleshooting

**CocoaPods failures after upgrading Flutter.** Delete `ios/Podfile.lock` (or
`macos/Podfile.lock`) and build again, or run `flutter clean`.

**Warnings on startup.** Deprecated API warnings come from the plugins the
template depends on. They are aimed at plugin authors, not at you, and are safe
to ignore.

**`flutter analyze` reports a missing `assets/` directory.** The asset folders
are listed in `pubspec.yaml`. If you delete one, remove its entry there too, or
the build fails.