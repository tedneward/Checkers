# Checkers

Classic American checkers, built with Flutter. You play red against the
computer, which plays black.

The game runs on iOS, Android, macOS, Windows, Linux and the web from a single
Flutter codebase.

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
- When a man reaches the far side of the board it is crowned and becomes a king.
- Win by taking all of the computer's pieces, or by leaving it with no legal
  move. A game is drawn after three repetitions of the same position, or after
  50 moves by each player with no capture and no promotion.

Click one of your pieces to pick it up. The squares it can reach light up. Click
one of those to move. There is no drag-and-drop; every move is two clicks.

## Project layout

```text
code
├── lib
│   ├── engine            The rules of checkers. No Flutter, no widgets.
│   ├── play_session      The board you play on, and the computer's reply
│   ├── audio             Music and sound effects
│   ├── settings          Sound and music toggles, player name, reset progress
│   ├── style             Colours, buttons, transitions, responsive layout
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

Sound effects, music and a player name are stored on the device with
`shared_preferences`. To change what is saved or how, edit the files in
`lib/settings/persistence/`. `SettingsPersistence` is the interface,
`LocalStorageSettingsPersistence` is the real implementation, and
`SettingsController` in `settings.dart` is what the UI reads.

Progress is deliberately kept in memory only, so it resets each launch.

## Troubleshooting

**CocoaPods failures after upgrading Flutter.** Delete `ios/Podfile.lock` (or
`macos/Podfile.lock`) and build again, or run `flutter clean`.

**Warnings on startup.** Deprecated API warnings come from the plugins the
template depends on. They are aimed at plugin authors, not at you, and are safe
to ignore.

**`flutter analyze` reports a missing `assets/` directory.** The asset folders
are listed in `pubspec.yaml`. If you delete one, remove its entry there too, or
the build fails.