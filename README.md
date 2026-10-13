# DomiVale

**settle · grow · rule**

A small, turn-based kingdom game where the way you grow your city is the way
you draw your border.

A valley of 22×22 to 32×32 cells, sized to its two to four houses. Each house
starts with one city of one cell. Every turn you collect goods from your land,
buy cards from a shared market, and play them: a new district on your city, a
new city somewhere else, or an army to take land from a rival. A city claims
the land within three cells of it, so every district you add pushes your
border out on the side you add it. Once land is claimed, the only way to take
it is by force. Land is the score: the house that holds the most of the valley
at the end wins.

Built with Flutter and Flame, with its terrain, theme and palette from
`vale_engine` — the small library the Vale games share — and set in the same
world as LogiVale and LumaVale. Played against
bot houses first, and designed so that a Wordfeud-style asynchronous
multiplayer mode can be added later without rewriting the rules.

## Status

**Early development: a skirmish plays from start to end.** Two to four
houses, each a person at the screen or a bot with a temperament, on a
generated valley: every house
claims the land within three cells of its heart, a card armed from the hand
shows every cell it could go to and the land it would claim or take there,
and a tap plays it. The market sells a row of five from a shared deck, two a
turn, beside the basic piles whose price rises with the house's districts,
and the bank trades three for one. Marches and Sieges take cells, raze
districts and bring whole cities over when a heart falls; a house with no
heart left is out, and a duel ends there. Anything in a turn can be undone
until it ends; a handover card between turns keeps each hand hidden. The rules live in
`packages/domivale_rules`, a pure Dart package with no Flutter in it, and
replay a match to the same state on the VM and in a browser. The bots are
the greedy ones the design was measured with. Next: the turn recap, crowns in
the HUD and the end-of-match panel. See [DESIGN.md](DESIGN.md) §18.

## Development setup

DomiVale depends on `vale_engine`, a private repository
(`github.com/robinvda/ValeEngine`), as a git dependency. You need read access
to it for `flutter pub get` to work.

**The game builds against the `vale_engine` commit `pubspec.lock` pins**,
exactly as CI and a fresh clone do. To take a pushed change to the library,
run `flutter pub upgrade vale_engine` and commit the lock with the code that
needs it.

**While developing the two together**, `pubspec.yaml` may point
`vale_engine` at a local checkout instead of the git URL:

```yaml
  vale_engine:
    path: ../vale_engine
```

Before committing here, and always before a release:

1. Commit and push the `vale_engine` changes.
2. Put the git dependency back in `pubspec.yaml`.
3. Run `flutter pub upgrade vale_engine`, and check that the `resolved-ref`
   for `vale_engine` in `pubspec.lock` is the commit just pushed.
4. Only then commit, with `pubspec.yaml` and `pubspec.lock` both on the git
   source.

A commit with the path in it builds nowhere but on this machine: CI and a
fresh clone would look for a directory that is not there.

```bash
flutter pub get
flutter run
flutter analyze
flutter test

# The rules package, on the VM and in a browser.
cd packages/domivale_rules
dart test
dart test -p chrome
```

CI runs both: `flutter analyze` and `flutter test` for the game, loading the
`VALE_ENGINE_DEPLOY_KEY` secret (a read-only deploy key on the engine
repository) before `flutter pub get`; and `dart analyze` and `dart test` for
the rules package, on the VM and in Chrome, since a web client and a server
will both run the same rules.

## Project layout

```
packages/domivale_rules/   # the rules: pure Dart, a path dependency
├── lib/board/             # cells and the reach rule, terrain kinds, the board
├── lib/cards/             # the card table, the deterministic shuffle
├── lib/match/             # header and log, state, actions, scoring
└── lib/rules.dart         # every tuned number, in one place

lib/
├── main.dart              # entry point, error capture
├── core/                  # the frame: loop, camera, profiler, gestures, targeting
├── game/                  # DomiValeGame, the match controller, input, setup
├── world/                 # the generator, BoardWorld, the renderers
├── theme/                 # the house colours, the look of each card kind
└── ui/                    # menu, setup, the game screen and its HUD
```

What comes from `vale_engine`: terrain generation and rendering, the theme
and palette, and small utilities such as `GridPos`. Everything else is
DomiVale's own: the frame the game runs in (the loop, the camera, the
gestures, grid targeting and previews) in `core/`, and what DomiVale *is* —
the rules, the board generator, the renderers for territory and cities, and
the bots — everywhere else.

## Documents

- [DESIGN.md](DESIGN.md) — the complete design document, technical
  architecture, starting numbers and the phased roadmap
- [CLAUDE.md](CLAUDE.md) — engineering rules and architecture notes

## License

MIT
