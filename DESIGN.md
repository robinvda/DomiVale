# DomiVale — design and implementation plan

**A small, turn-based kingdom game where the way you grow your city is the way
you draw your border.**

Flutter / Flame, mobile-first, built on the shared `vale_engine` package. Played
against bot houses first, and designed so that a Wordfeud-style asynchronous
multiplayer mode — make your move, put the phone away, your rival answers within
a day or two — can be added later without rewriting the rules.

A 32×32 valley, two to four houses. Each house starts with one city of one cell.
Every turn you collect goods from your land, buy cards from a shared market, and
play them: a new district on your city, a new city somewhere else, or an army to
take land from a rival. A city claims the land within three cells of it, so
every district you add pushes your border out on the side you add it. Once land
is claimed, the only way to take it is by force. Land is the score: the house
that holds the most of the valley at the end wins.

---

## 1. Design pillars

1. **Where your city grows is the decision.** A district is not just a yield; it
   is a shape. Adding it on one side claims the land on that side, so every
   growth card asks "what, and which way?" Everything else in the game — goods,
   cards, war — serves that one spatial question, and the land you hold at the
   end is what you are scored on, so the question never stops mattering.
2. **You see the result before you commit.** No dice and no hidden formulas.
   An armed card shows exactly what it would do on every cell it could go to:
   what a district would yield, which cells it would claim, how much strength
   an attack needs. The only unknowns are what your rivals hold in their hands
   and what they will do next.
3. **Small and countable.** A 32×32 board, three goods, single-digit numbers,
   a fixed number of rounds. A player who has been away for two days reads the
   whole state of the match in one look.
4. **A turn is one sitting.** A turn plays at most three cards, is decided and
   undoable in one go, and is committed with one button. A turn is a few
   decisions, never a chore, however rich the house. This is what makes bot
   matches quick and asynchronous matches possible.
5. **Shared identity with the other Vale games.** Same look, same UI language,
   same world as LogiVale and LumaVale — different genre, different mechanics.
   Warm in tone even when it is about conquest.

---

## 2. The existing codebase

### `vale_engine`

- **Location:** `~/git/Github/robinvda/vale_engine`, package `vale_engine`,
  repository `git@github.com:robinvda/ValeEngine.git` (private).
- **Dependency:** git URL pinned through `pubspec.lock`. For side-by-side
  development, an untracked `pubspec_overrides.yaml` points at the sibling
  checkout.

What DomiVale takes from it:

| Area | Classes |
|---|---|
| Game mounting | `ValeGame` (loop, camera, terrain and fog layers, frame accounting, teardown), `CameraController`, `DebugController`, `RenderProfiler`, `PerformanceMonitor`, `ErrorLog` |
| World | `TerrainWorld`, `TerrainTile`, `TerrainType`, `Biome`, `NoiseGenerator`, `HeightMapGenerator` |
| Grid | `TileTargeting` (offered cells for an armed card), `TilePreviewPainter` (what a card would do to the cells under the pointer) |
| Rendering | `TerrainRenderer` + `TerrainGenerator`, `buildRadiusCellPath` (border outlines), `IconAtlas` (yield and district icons), `SpriteBatch`, `TapRippleRenderer`, viewport culling helpers |
| Input | `WorldGestures` (tap / hold / drag, camera driven internally) |
| UI | `GamePanel`, `CollapsibleSection`, `SegmentedBar`, `CelebrationBanner`, `PanelStateController`, `FadePageRoute`, `FpsCounter`, log viewers |
| Theme | `Brand` (Nunito / Nunito Sans), `EnginePalette` |
| Persistence | `SlotStore`, `SaveFileTransfer` |

**LogiVale** and **LumaVale** are the references for code style, naming and file
layout: `BoardWorld extends TerrainWorld`, `DomiValeGame extends ValeGame`,
`lib/theme/game_palette.dart` beside the engine palette, one directory per
system, renderers under `<system>/rendering/`.

`buildRadiusCellPath` matters twice. Its distance rule — a cell is within
radius `r` when `dx² + dy² <= (r + 0.5)²` — is the rule this game uses for
*every* range (§4.2), so what the rules claim and what the renderer outlines are
the same set by construction. And called with radius 0 on every owned cell, it
outlines any set of cells, which is what a territory border is.

### What DomiVale deliberately does *not* use

- **`Pathfinder`, `PathfindingService`, `PathfindingWorker`.** Nothing walks a
  route. Armies are cards, not units on the map.
- **`ExplorationManager` / `FogRenderer`.** The whole board is visible to
  everyone, always — it is a board game. Exploration is disabled in `onLoad`.
- **`TerrainPass` / `WorldGenConfig`.** Their noise is tuned for 256×256; a
  32-cell board samples a sliver of one landmass. DomiVale writes its own
  generator on the engine's `NoiseGenerator`, as LumaVale does.
- **Pawns, for now.** A cosmetic layer of little folk (banner carriers walking
  to a captured cell, a crowd at a market) is a polish item for later, using
  the engine's pawn sprites and trails. Nothing in the rules depends on it.

---

## 3. Technical architecture

### 3.1 The rules are a separate, pure Dart package

The single most important structural decision, because of the multiplayer plan:

```
┌─────────────────────────────────────────────┐
│ Flutter widgets — menus, HUD, hand, market  │
├─────────────────────────────────────────────┤
│ DomiValeGame (ValeGame) — rendering, input  │
├─────────────────────────────────────────────┤
│ BoardWorld (TerrainWorld) — the board drawn │
├─────────────────────────────────────────────┤
│ vale_engine                                 │
└─────────────────────────────────────────────┘
          │ reads state, sends actions
          ▼
┌─────────────────────────────────────────────┐
│ packages/domivale_rules — pure Dart         │
│ board, match state, actions, cards, bots    │
└─────────────────────────────────────────────┘
```

`packages/domivale_rules` lives in this repository and is a path dependency of
the game. It imports nothing from Flutter, Flame or `vale_engine`. That is what
lets the exact same code run:

- in the game, as the match the player is in;
- in the bots, which search over the same actions a player has;
- in tests, headless;
- later on a server, which validates every move of an asynchronous match by
  running it through the same rules.

Rules that follow from that:

- **A match is data plus a log.** A `Match` is a header (rules version, board,
  houses, seed) and an ordered list of `Action`s. The current `MatchState` is
  what you get by applying the log to the starting state, and that function is
  pure: same header, same log, same state, on every platform.
- **The board is data in the match, not generated by the rules.** The generator
  lives in the game (it uses the engine's noise) and its output — 1024 cells of
  terrain and height — is stored in the match header. The rules never need to
  reproduce a generator, so a server never needs one, and generation can change
  between versions without breaking old matches.
- **Integer arithmetic only, and own random numbers.** On the web a Dart `int`
  is a JavaScript double, so the rules keep every value small and use no
  bitwise tricks beyond 32 bits. The market shuffle uses a small PRNG written in
  the rules package, not `dart:math` `Random`, so that a seed shuffles the same
  deck on the VM and in the browser.
- **Every action is validated by the rules**, not by the UI. The UI asks the
  rules what is legal (to highlight cells) and sends an action; the rules accept
  or refuse it. The UI never changes state on its own.
- **Derived values are never stored.** Yields, defence, crowns and reach are
  computed from the state; nothing caches them in a way that has to be kept in
  step.

The game layer follows the rules inherited from LogiVale: rendering never
mutates simulation state, nothing allocates in `render()` or `update()`, and
every renderer culls to the visible rect.

### 3.2 Project structure

```
packages/domivale_rules/
├── lib/
│   ├── board/
│   │   ├── board.dart            # 32×32 cells: terrain kind and height, immutable
│   │   ├── cell.dart             # a coordinate, and the reach rule (§4.2)
│   │   └── terrain_kind.dart     # meadow, forest, hills, water → what it yields
│   ├── match/
│   │   ├── match.dart            # header + action log
│   │   ├── match_state.dart      # houses, cities, ownership, goods, hands, market, round
│   │   ├── house.dart            # one player or bot: colour, goods, hand, seat
│   │   ├── city.dart             # a heart and its districts
│   │   ├── action.dart           # buy, play, trade, end turn — the whole vocabulary
│   │   ├── apply.dart            # state + action → state, or a refusal
│   │   └── scoring.dart          # crowns
│   ├── cards/
│   │   ├── card_kind.dart        # the table in §6
│   │   ├── market.dart           # the row, the basic piles, the deck and its refill
│   │   └── prng.dart             # the deterministic shuffle
│   ├── war/
│   │   └── defence.dart          # what a cell needs to be taken (§5)
│   └── bots/
│       ├── bot.dart              # chooses a turn's actions
│       └── temperament.dart      # builder, expander, warlord weights
└── test/

lib/
├── main.dart
├── app_info.dart
├── game/
│   ├── domivale_game.dart        # DomiValeGame extends ValeGame
│   ├── match_controller.dart     # holds the Match, applies actions, runs bot turns
│   ├── turn_recap.dart           # replays what rivals did since your last turn
│   └── input_controller.dart     # armed card → offered cells → tap to play, undo
├── world/
│   ├── board_world.dart          # BoardWorld extends TerrainWorld, from a Board
│   ├── board_generator.dart      # noise → terrain, heights, start positions
│   └── rendering/
│       ├── territory_renderer.dart   # house colour fills and borders
│       ├── city_renderer.dart        # hearts and districts
│       ├── yield_renderer.dart       # yield icons on cells (zoomed, or while armed)
│       └── preview_renderer.dart     # what the armed card would do here
├── ui/
│   ├── hud.dart                  # goods, crowns, round
│   ├── hand_bar.dart             # the hand along the foot
│   ├── market_panel.dart         # the row and the basic piles
│   └── match_end_panel.dart
├── persistence/
└── theme/
    └── game_palette.dart         # house colours, district colours
```

---

## 4. The board, cities and territory

### 4.1 The board

- **32×32 cells**, square grid. Fit zoom on a portrait phone is about 12 px a
  cell, so at fit zoom the board is read by colour and shape; icons appear when
  zoomed in, or on the cells an armed card offers.
- **Four terrain kinds**, each yielding one good:

  | Terrain | Engine biome | Yields | Defence |
  |---|---|---|---|
  | Meadow | `grassland` | grain | — |
  | Forest | `forest` | wood | +1 |
  | Hills | `rocky` | stone | +1 |
  | Water | `water` | nothing | can't be owned |

- **Height** in a few integer levels (0–3), drawn with the engine's cliff
  shading. Height does one thing: attacking uphill costs more (§5).
- **No fog.** Everybody sees everything except each other's hands.

### 4.2 Reach

One distance rule for every range in the game, the same one the engine's
`buildRadiusCellPath` uses: a cell is within reach `r` of another when
`dx² + dy² <= (r + 0.5)²`. Reach 3 covers 37 cells in a rounded shape; reach 1
is the 3×3 square around a cell.

"Touching" means the four orthogonal neighbours, and only those.

### 4.3 Cities

- A **city** is a **heart** (the cell it was founded on) plus its **districts**.
- A house starts the match with one heart, placed by the generator.
- A **district** is placed on an own territory cell that touches a cell of one of
  your cities, and becomes part of that city. Which kind of district it is
  depends on the card (§6).
- A new city is founded with a **Settle** card on a land cell that no other
  house owns and that is outside reach 3 of every city cell of every house. In
  practice that is open land: your own territory is within reach 3 of your
  cities by definition, so the only own cells that qualify are ones taken by
  war far from your cities.
- City cells never sit on water.

### 4.4 Claiming land

**When a heart or district is placed, every unclaimed land cell within reach 3
of it becomes yours.** That is the whole claiming rule.

- **Claimed land stays claimed.** A district placed near a rival's border never
  takes their cells; it only takes what nobody owns. The only way a claimed cell
  changes hands is war (§5).
- Turns are sequential, so there are no ties: whoever grows toward a cell first
  claims it.
- The board fills up. With three cards a turn (§7.2) and the rising price of
  growth (§6.1), four houses use up the open land over most of a match, and the
  last rounds are a contest over borders: land then changes hands only by war,
  and a house grows upward — more districts on land it already holds. That arc,
  a race for open land and then a fight over it, is intended. With two houses
  the race may last the whole match.

### 4.5 Yields

At the start of your turn every city produces:

- **A heart** gives 1 grain, 1 wood and 1 stone.
- **A gathering district** (Farm, Lumber camp, Quarry) gives 1 of its good for
  each cell of its terrain that **touches it and is your plain territory** — not
  a city cell, not water, not a rival's. At most 3, usually 1–2, since one of
  the four touching cells is always the city cell it grew from.
- A cell can feed every district that touches it. Two farms on either side of a
  meadow cell both count it.

This is the puzzle of placement: a farm surrounded by meadow is a good farm, and
every district placed takes a cell out of the land that feeds the others. A
rival who takes the meadow next to your farm takes its yield with it.

---

## 5. War

### 5.1 Taking a cell

Military cards take cells. A target must be a cell that is not yours and that
touches a cell you own.

- **Strength:** the card's strength, plus 1 if one of your Barracks is within
  reach 3 of the target. Several military cards played on the same target in
  the same turn add up, within the three cards a turn allows (§7.2). A March
  cannot be played on a city cell, so only Sieges add up against a district or
  a heart: a bare heart needs two Sieges, or one Siege with a Barracks in reach.
- **Defence:** what the target needs, shown on the cell while a military card is
  armed:

  | Target | Base defence |
  |---|---|
  | Unclaimed cell | 0 |
  | Territory cell | 1 |
  | District | 3 |
  | Heart | 5 |

  plus 1 on forest or hills, plus 1 if the target stands higher than every cell
  of yours that touches it, plus 2 if one of the owner's Walls is within reach 1.

- **Strength must be higher than defence.** A tie goes to the defender, as every
  tie in the game does. A card cannot be played on a target it cannot take, and
  the cell says how much more it needs — so an attack never fails. It either
  happens or it is not offered.

There is no damage, no partial result and no dice. The tension is in the turn
after: your rival sees what you took and answers.

### 5.2 What a capture does

- **A territory cell** becomes yours.
- **A district** is razed and becomes your plain territory cell. Its city loses
  it.
- **A heart** brings its whole city over: the heart, every district of that
  city, and every cell the old owner holds that is within reach 3 of that city
  and of no other city of theirs. It is the big swing of the game and it is
  meant to be expensive.

Districts belong to their city by identity, not by being connected to the
heart, so a razed district in the middle never splits a city.

A house with no hearts left is out of the match. Its remaining cells stay in
its colour as **fallen land**: they yield nothing and score for nobody, no
district can be placed on them, and growth never claims them. They are taken
by war like any territory cell, at defence 1. So a fallen house's land is
divided by whoever spends the cards, not handed to whoever happens to play
next.

---

## 6. Cards and the market

### 6.1 How cards work

- **Goods buy cards; cards cost nothing to play.** A card bought goes into your
  hand. A hand holds at most 5 cards.
- A hand is hidden from rivals; how many cards it holds is not. A Siege kept in
  hand is a threat a rival has to respect without seeing it.
- **Basic piles** — Farm, Lumber camp and Quarry — are always available,
  without limit. Growth is never blocked by a bad market.
- **Growth gets dearer.** A basic card costs 1 grain and 1 wood, plus 1 grain
  and 1 wood for every 5 districts the house already has. A house with 12
  districts pays 3 grain and 3 wood for its next Farm. Market cards keep their
  printed price, so as a house grows, a Settle, a Monument or a Siege becomes
  the cheaper buy, and the match turns from growing to settling and fighting on
  its own.
- **The market row** holds 5 face-up cards from a shared, shuffled deck. Rivals
  see what you take, and sometimes the right buy is the card a rival needs.
- **The row refills at the end of your turn**, not when a card is bought. That
  keeps undo free for the whole turn: nothing new is revealed until you commit.
- **Trading:** during your own turn you can trade 3 of one good for 1 of another
  with the bank, or 2 for 1 if you own a Market.

### 6.2 The base set

| Card | Kind | Price | Effect |
|---|---|---|---|
| Farm | basic district | 1 grain, 1 wood, rising (§6.1) | 1 grain per touching meadow |
| Lumber camp | basic district | 1 grain, 1 wood, rising (§6.1) | 1 wood per touching forest |
| Quarry | basic district | 1 grain, 1 wood, rising (§6.1) | 1 stone per touching hills |
| Market | district | 2 grain, 2 wood | +1 crown; trade 2 for 1 |
| Walls | district | 3 stone | +2 defence to your cells within reach 1 |
| Barracks | district | 2 grain, 1 wood, 1 stone | +1 strength for your attacks within reach 3 |
| Monument | district | 2 wood, 3 stone | +3 crowns |
| Settle | new city | 2 grain, 2 wood, 1 stone | found a city (§4.3) |
| March | military | 1 grain, 1 wood | strength 2; not on city cells |
| Siege | military | 2 grain, 2 stone | strength 4; any target |

Every district, whatever its kind, claims land when placed (§4.4), and claimed
land is what scores (§7.3). A Walls card is still a way to grow.

The deck's mix — how many of each market card — is the main tuning lever, along
with prices. See §13 for starting numbers.

### 6.3 Later content

New cards are new rules on the same vocabulary, so content is cheap: a Harbour
that yields from water, a Road that lets a district be placed one cell further,
a Watchtower that raises defence along a line, a Festival that scores crowns per
market, a Truce that forbids attacks on you for a round. None of it belongs in
the first release; the base set is tuned first.

---

## 7. A match

### 7.1 Setup

- 2 to 4 houses, one of them the player, the others bots.
- The generator places one heart per house, spread over the board, each with a
  fair share of meadow, forest and hills within reach 3 (§9).
- Each house has a **banner** — Builder, Expander or Warlord. A bot's banner is
  its temperament (§11); the player picks one at setup. The banner adds one
  card to the opening hand: a Builder starts with a Market, an Expander with a
  Settle, a Warlord with a March. From the first round each house plays
  differently, and a rival's banner tells you what to expect from it.
- Each house claims its starting land and starts with an **opening hand** of one
  Farm, one Lumber camp, one Quarry and its banner card, and **2 grain, 2 wood,
  1 stone**.
- Seats later in the turn order get +1 grain per seat, to balance going later.

### 7.2 A turn

1. **Collect.** Your cities produce (§4.5).
2. **Act**, in any order: buy cards, trade, play cards. Buying and trading are
   limited only by your goods and the hand cap. **Playing is limited to 3 cards
   a turn.** The HUD shows the plays left as three slots.
3. **End turn.** The market row refills, and the next house plays.

Everything in step 2 can be undone until you end the turn.

The play cap is what keeps a turn a turn. Without it a rich house places a
dozen districts in a sitting, income doubles every two rounds, and the valley is
full by round six. With it, a turn is three decisions, goods pile up faster
than they can be spent, and the question becomes which three cards to play and
where — not how many.

### 7.3 Ending and crowns

A match lasts **20 rounds** (every house plays 20 turns), or ends early when only
one house has a heart left.

Crowns, shown live in the HUD:

- 1 per 3 cells you own, city cells included,
- +1 per heart,
- +1 per Market, +3 per Monument.

Most crowns wins. A tie goes to the house with more hearts, then to the house
later in the turn order.

Land is the score on purpose. A district is worth what it claims, not what it
is, so once the open land is gone the only ways to gain are a Monument, a
Market, a new city, or taking cells from a rival — and every cell taken counts
twice, once for you and once against them. The border you drew in the first
half is what you defend in the second.

### 7.4 The turn recap

When your turn begins, the game shows what every rival did since your last
turn: a short, skippable replay with the camera moving to each change — cells
claimed, cards taken from the row, cells captured. Against bots it explains a
round that otherwise happens in a blink. In an asynchronous match it is what
makes a move from two days ago readable, and it is the first thing that matters
when a player opens the app.

---

## 8. Input and UI

Portrait-first, one thumb.

- **HUD (top):** grain, wood and stone; crowns; round "7 / 20"; whose turn;
  the three play slots for this turn.
- **Board (middle):** pinch and drag to move, as in every Vale game; the camera
  starts at fit zoom.
- **Hand (bottom):** the cards in hand as a fan, as LumaVale shows them. A
  button beside it opens the **market panel** with the row and the basic piles.
- **End turn** button, always in the same place.

Playing a card:

1. Tap a card in hand to **arm** it. Every cell it could go to is offered
   (`TileTargeting`).
2. Each offered cell shows its **preview** (`TilePreviewPainter`): for a
   district, the yield it would give and the outline of the land it would claim;
   for a military card, the target's defence against your strength.
3. Tap a cell to play. Tap the card again to disarm.

**Hold** any cell for what it is: owner, terrain, yield, defence and why.

The LumaVale rule applies: anything with a range is drawn while it is relevant
(armed card, selected district) and never otherwise, so the board does not
fill up with rings.

---

## 9. The board generator

- Built on the engine's `NoiseGenerator`, tuned for 32 cells: one or two
  features (a river, a lake, a ridge of hills, a forest belt) rather than
  continents.
- **Start positions:** spread by distance (corners for 4 houses, opposite sides
  for 2), and then checked for fairness: within reach 3 of each start, the count
  of meadow, forest and hills each falls inside a band, and the start is on
  height 0 or 1. A board that fails is regenerated from the next seed.
- Seeded and repeatable: the same seed gives the same board, which is what a
  daily board (§10) needs. The board is then stored in the match (§3.1), so a
  match never depends on the generator again.

---

## 10. Modes

- **Skirmish:** you against 1–3 bots, a random board, 20 rounds. Around 10–15
  minutes.
- **Daily board:** the same seed for everyone each day, against the same bots,
  with your crowns as the score.
- **Campaign:** hand-made boards and starting positions with a goal (hold 3
  cities, reach 30 crowns by round 15, take the Lake House's heart). Later.
- **Asynchronous multiplayer:** §12. Later.

---

## 11. Bots

- A bot plays by the same rules and sees what a player sees: the board, the
  market row, its own hand. It does not see hands or the deck order.
- **Turn search:** generate candidate actions (buys, plays, trades), build a
  handful of whole turns by greedy expansion, score the resulting state, keep
  the best. Turn-based play makes this cheap; it runs off the UI thread if a
  phone ever shows it.
- **Temperaments** are weights on that score, and each bot house has one,
  visible from its name and banner, and from the banner card it opens with
  (§7.1):
  - **Builder** — values yield and crowns; rarely attacks, invests in Walls.
    Opens with a Market.
  - **Expander** — values claimed land and new cities; races for open ground.
    Opens with a Settle.
  - **Warlord** — values captures; keeps military cards in hand, goes for weak
    borders. Opens with a March.
- Difficulty comes from search depth and from how much a bot plans for the next
  turn — never from extra goods.

A player should be able to tell after a few rounds what each rival is like, so a
loss reads as "I let the Warlord next to my farms", not as chance.

---

## 12. Asynchronous multiplayer (later)

Wordfeud-style: a player makes a whole turn, ends it, and puts the phone away.
The next player gets a notification and has a fixed time (one or two days) to
answer. A player can have several matches running at once.

What the design already does for it:

- **The turn is the unit.** A turn is a batch of actions committed at once
  (§7.2), so one move is one upload.
- **Twenty rounds** keep a 1v1 match to about three weeks at one move a day.
  Longer and people give up.
- **The rules package runs on the server** (§3.1), which replays every turn and
  refuses an illegal one. A client cannot cheat on the rules.
- **The turn recap** (§7.4) is the screen a returning player sees.

What it still needs, decided when this phase starts:

- **A backend of our own.** Google Play Games no longer offers turn-based
  multiplayer, and Game Center's turn-based matches are iOS-only, so a
  cross-platform match needs accounts, a match list, move storage and push
  notifications. A Dart server could depend on `domivale_rules` directly.
- **Hidden information.** In a bot match the client holds the deck seed; in a
  multiplayer match it must not, or the market can be read ahead. The server
  holds the deck and sends each refill as part of the turn result.
- **1v1 first.** With four players taking turns in order, one round can take
  four days. Larger matches need either shorter time limits or a different turn
  structure.
- **Timeouts:** what happens when a player does not answer in time (skip the
  turn and only collect, a bot plays it, or the match is lost).
- **Rules versions:** a match records the rules version it started on, and the
  server keeps every version that still has matches running.

---

## 13. Starting numbers

To be tuned by playing. Collected here so they are tuned in one place.

| Number | Value |
|---|---|
| Board | 32×32 |
| Houses | 2–4 |
| Rounds | 20 |
| Claim reach | 3 (37 cells) |
| Settle distance | outside reach 3 of every city cell |
| Plays per turn | 3 |
| Hand cap | 5 |
| Market row | 5 |
| Bank trade | 3 for 1 (Market: 2 for 1) |
| Basic card price | 1 grain, 1 wood, +1 of each per 5 districts owned |
| Opening hand | Farm, Lumber camp, Quarry, banner card |
| Starting goods | 2 grain, 2 wood, 1 stone (+1 grain per later seat) |
| Heart yield | 1 of each good |
| Defence: unclaimed / territory / district / heart | 0 / 1 / 3 / 5 |
| Terrain and height bonus | +1 each |
| Walls bonus | +2 within reach 1 |
| Barracks bonus | +1 within reach 3 |
| March / Siege strength | 2 / 4 |
| Crowns | 1 per 3 cells owned, heart +1, Market +1, Monument +3 |
| Fallen land defence | 1 |

A first market deck of 40 cards: Settle ×6, March ×10, Siege ×6, Market ×5,
Walls ×5, Barracks ×4, Monument ×4. When the deck runs out, the discarded row
cards are shuffled back in.

A rough first turn: collect 1/1/1 to reach 3 grain, 3 wood, 2 stone; place the
opening Farm, Lumber camp and Quarry, and hold the banner card. From turn two
a house collects about 8 goods; 30–40 by the middle of a match and 50 or more
near the end, by which time a house has 25–50 districts, a basic card costs
10–20 goods, and most turns play a market card or two. Growth is then bounded
by goods rather than by the play cap: a house places one or two districts a
turn, and about a quarter of the valley is still open at round 20 before
Settles and war are counted. These figures come from a growth-only simulation
of the rules (basic districts only, no war, no market cards) and are the
baseline that playtesting corrects. Two things to watch in that data: the seat
bonus compounds, so the last seat may end up well ahead rather than level, and
if growth feels slow the first lever is the price step (every 5 districts),
not the play cap.

---

## 14. Brand and visual identity

- **Name:** `DomiVale` — one word, capital D and V. Never `Domivale`,
  `DOMIVALE` or `Domi Vale`. From *domus* (home) and *dominion*.
- **Tagline (working):** **settle · grow · rule** — lowercase, middot-separated,
  the three beats of a match in order, as `build · connect · prosper` and
  `build · glow · defend` are for the other games.
- **House colours** carry the board, so they are the palette's first job: four
  colours that stay apart at 12 px, on every terrain, for colour-blind players
  too. Like LumaVale's building colours, their distance is tested in L\*a\*b\*,
  not RGB. Territory is a soft wash of the house colour with a stronger border;
  city cells are drawn the way LogiVale draws buildings — a rounded square in
  the district's colour, a darker outline, a white Material icon.
- **Voice:** warm and low-pressure, as the other Vale games. Conquest is told
  plainly and without blood: "The Lake House took your mill by the river." No
  "Warning" or "Error" in player-facing text.

---

## 15. Rejected — do not reintroduce

- **Real-time, large-scale territory play** (territorial.io, openfront.io). The
  appeal is hundreds of live players on a huge map; the Vale games are small and
  offline-first. The love of fronts and conquest survives in §5.
- **Border pushing.** An earlier idea let a growing city take a rival's cells by
  being nearer to them. Claimed land changes hands only by war, so a border is
  something you defend, not something that drifts.
- **Simultaneous orders.** Everybody committing at once and revealing together
  was considered. Sequential turns read better, suit a Civilization-style game,
  and are what Wordfeud-style play is built on.
- **Hexes.** They suit "within 3 cells" better, but the engine is built on square
  tiles, and the Euclidean reach rule (§4.2) already gives round shapes.
- **Dice and attack odds.** An attack is offered only when it succeeds. Luck
  lives in the market row and nowhere else.
- **A currency-free draft** like LumaVale's. Goods and a shared market give the
  players something to compete over besides land, and keep the two games apart.
- **Many goods.** Three, each with one job: grain to grow, wood to build, stone
  to fortify and besiege.
- **Units on the map.** Armies as pieces that walk, need supply and stack are
  the road to a wargame nobody can learn on a phone. An army is a card played
  on a cell.
- **Crowns per city cell.** Scoring every district as a crown makes the best
  last rounds a paving exercise — cover every owned cell with districts — and
  makes taking a cell worth a fraction of building one, so nobody attacks. Land
  scores; districts are how you get land.
- **Unlimited plays per turn.** A basic district pays for itself in one round,
  so without a cap income doubles every two rounds, the valley is full by round
  six and a late turn is fifty taps. Three plays a turn.

---

## 16. Deferred decisions

- **A card that waits gets cheaper.** Market row cards losing 1 of their price
  for every round they stay unbought — a common board-game catch-up rule.
  Revisit once there is play data on runaway leaders.
- **Cut-off land.** Whether territory cells cut off from all of their owner's
  cities should do anything (yield nothing, defend at 0). Simple for now: no.
- **Per-city growth price.** The rising basic price (§6.1) counts a house's
  districts, because the price is paid when the card is bought and a basic card
  is not yet tied to a city. A price per city would push harder toward founding
  new cities; revisit if play shows one blob city is always best.
- **Water.** Whether water cells should be ownable (for a Harbour card) or stay
  outside every border.
- **Pricing.** Premium and offline like LumaVale, or free with a paid unlock once
  multiplayer exists. Decided before release, not now.
- **Cosmetic folk** walking out to captured cells and crowding markets (§2).

---

## 17. Risks

- **Runaway leader.** Land gives goods gives cards gives land. Fixed rounds,
  three plays a turn, the rising basic price and the seat bonus are the first
  answers; play data decides whether more is needed (§16).
- **A dull end.** Once the board is full, war is the main way to gain crowns.
  If Walls and terrain make every border too dear to attack, the last rounds
  are only Monuments. March and Siege must stay priced so that a border with no
  Walls is always worth taking.
- **Goods that mean nothing.** With three plays a turn a rich house may hold
  more goods than it can ever spend. The rising basic price soaks some up;
  if goods still pile up, add sinks (a card that costs goods to hold, or a
  Monument whose price rises) before touching the cap.
- **Bots that read as random.** Temperaments must be visible in play, or a
  capture feels like bad luck rather than a rival's character.
- **Readability at 12 px.** Four house colours over four terrains on a phone
  screen. Tested on a real phone in Phase 2, before anything else is built on
  top.
- **Analysis paralysis.** Many legal plays per card on a full board. The preview
  must make good cells obvious, and bots must not take long.

---

## 18. Roadmap

Each phase ends with something that can be played or tested, and ships its own
tests.

### Phase 0 — Project setup
- `flutter create` for android, ios, web, macos, windows, linux; portrait-first.
- `vale_engine` as a git dependency; untracked `pubspec_overrides.yaml`.
- `packages/domivale_rules` as a pure Dart package and a path dependency.
- `analysis_options.yaml` from LogiVale; Nunito fonts; `game_palette.dart`.
- CI: `flutter analyze` + `flutter test` for the game, `dart test` for the rules
  package on the VM *and* in a browser, since determinism on the web is a rule.

**Done when:** the app boots to a main menu and CI is green.

### Phase 1 — The rules core
- `Board`, reach, claiming, cities, districts, yields, turns, the play cap,
  end turn, crowns.
- A match as header + log, with replay.
- Tests: the reach rule matches `buildRadiusCellPath`; claimed land never changes
  owner by growth; yields count only own plain territory; a fourth play in a
  turn is refused; crowns count owned cells; replaying a log gives the same
  state on the VM and in a browser.

### Phase 2 — The board on screen
- Board generator with fair starts; `BoardWorld`; territory, city and yield
  renderers.
- Play the opening hand and basic piles by hand, hot-seat, no bots.
- Readability check on a real phone.

### Phase 3 — Market and cards
- The row, the deck, the PRNG, refill at end of turn, trading, the hand cap,
  the rising basic price, banner cards.
- The hand bar and the market panel; arming, offered cells and previews.

### Phase 4 — War
- March and Siege, defence, Walls and Barracks, captures, heart capture,
  elimination and fallen land.

### Phase 5 — Bots
- Turn search and the three temperaments; bot turns off the UI thread if
  needed.
- **Done when:** a skirmish against three bots plays from start to end.

### Phase 6 — A whole match
- Crowns in the HUD, the end of match panel, the turn recap.

### Phase 7 — Persistence
- Save slots through `SlotStore`: the match header and log, plus a snapshot of
  the state for quick loading.

### Phase 8 — Modes
- Daily board; first campaign boards.

### Phase 9 — Feel and polish
- Sounds, capture animations, banners, cosmetic folk, tutorial.

### Phase 10 — Asynchronous multiplayer
- Backend, accounts, match list, push notifications, server-side validation with
  `domivale_rules`, the server-held deck (§12).

### Phase 11 — Release
- Store listings, icons and branding assets, release builds for every platform.
