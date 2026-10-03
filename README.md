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

Built with Flutter and Flame on `vale_engine`, the shared engine behind the
Vale games, and set in the same world as LogiVale and LumaVale. Played against
bot houses first, and designed so that a Wordfeud-style asynchronous
multiplayer mode can be added later without rewriting the rules.

## Status

**Early development: the board on screen.** A skirmish of two to four
houses is played hot-seat on a generated valley: every house claims the land
within three cells of its heart, a card armed from the hand shows every cell
it could go to and the land it would claim there, and a tap plays it. The
basic piles sell Farms, Lumber camps and Quarries at a price that rises with
the house's districts; anything in a turn can be undone until it ends; a
handover card between turns keeps each hand hidden. The rules live in
`packages/domivale_rules`, a pure Dart package with no Flutter in it, and
replay a match to the same state on the VM and in a browser. The market row,
war and bots are the next phases. See [DESIGN.md](DESIGN.md) §18.

## Development setup

DomiVale depends on `vale_engine`, a private repository
(`github.com/robinvda/ValeEngine`), as a git dependency. You need read access
to it for `flutter pub get` to work. To work on the engine and the game side
by side, check the engine out and add an untracked `pubspec_overrides.yaml`
here pointing at it. This repository does not sit next to the engine, so the
path is:

```yaml
dependency_overrides:
  vale_engine:
    path: ../robinvda/vale_engine
```

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
├── game/                  # DomiValeGame, the match controller, input, setup
├── world/                 # the generator, BoardWorld, the renderers
├── theme/                 # the house colours, the look of each card kind
└── ui/                    # menu, setup, the game screen and its HUD
```

What comes from the engine: the game loop, camera, terrain grid and
rendering, grid targeting and previews, gesture handling, the shared panels
and theme, and save slots. What stays here is what DomiVale *is*: the rules,
the board generator, the renderers for territory and cities, and the bots.

## Documents

- [DESIGN.md](DESIGN.md) — the complete design document, technical
  architecture, starting numbers and the phased roadmap
- [CLAUDE.md](CLAUDE.md) — engineering rules and architecture notes

## License

MIT
