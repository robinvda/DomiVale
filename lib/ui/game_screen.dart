import 'package:domivale_rules/domivale_rules.dart';
import 'package:flame/game.dart' show GameWidget;
import 'package:flutter/material.dart';
import 'package:vale_engine/game/debug_controller.dart';
import 'package:vale_engine/theme/brand_theme.dart';
import 'package:vale_engine/theme/engine_palette.dart';
import 'package:vale_engine/ui/world_gestures.dart';

import '../game/domivale_game.dart';
import '../game/match_controller.dart';
import '../theme/game_palette.dart';
import 'hand_bar.dart';
import 'hud/hud_widgets.dart';
import 'hud/status_panel.dart';
import 'market_panel.dart';

/// The screen a match is played on.
///
/// **The board fills the screen and the chrome lies over it**: the panel at
/// the top, the hand along the foot, End turn in the corner opposite the
/// cards. The screen tells the game what its chrome covers, so a fit is a
/// fit of what the player can actually see.
///
/// Two structural rules, both of which cost a bug in the sibling games:
///
/// - **The shape of the subtree around the `GameWidget` never changes**,
///   since unmounting one disposes its game. Everything that appears and
///   disappears is a sibling in the stack over it.
/// - **Nothing the HUD reads may touch what `onLoad` makes.** Every control
///   is on screen before the board exists.
///
/// Hot-seat: every house is a person at this screen. Between turns a card
/// over the board names the next house, so one player's hand is never shown
/// to another.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.header});

  final MatchHeader header;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final DebugController _debugController = DebugController();
  late final MatchController _matches;
  late final DomiValeGame _game;

  /// Whether the handover card is up: the next house has not yet taken the
  /// turn. Up from the first frame, so the first house takes its turn too.
  bool _handingOver = true;

  /// Whether the market is open over the board.
  bool _marketOpen = false;

  @override
  void initState() {
    super.initState();
    _matches = MatchController(Match(widget.header));
    _game = DomiValeGame(debugController: _debugController, matches: _matches);
  }

  @override
  void dispose() {
    _debugController.dispose();
    _matches.dispose();
    super.dispose();
  }

  void _say(Refusal refusal) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(refusal.message),
        duration: const Duration(seconds: 2),
      ));
  }

  void _onTap(Offset position) {
    final cell = _game.pointAtScreen(position);
    if (cell != null) {
      final refusal = _game.tapAt(cell);
      if (refusal != null) _say(refusal);
    }
    setState(() {});
  }

  void _onHold(Offset position) {
    final cell = _game.pointAtScreen(position);
    if (cell != null) _game.inspect(cell);
    setState(() {});
  }

  void _buyBasic(CardKind kind) {
    final refusal = _game.buyBasic(kind);
    if (refusal != null) _say(refusal);
    setState(() {});
  }

  void _buyRow(int slot) {
    final refusal = _game.buyFromRow(slot);
    if (refusal != null) _say(refusal);
    setState(() {});
  }

  void _trade(Good give, Good take) {
    final refusal = _game.trade(give, take);
    if (refusal != null) _say(refusal);
    setState(() {});
  }

  void _endTurn() {
    if (_game.endTurn()) {
      _handingOver = true;
      _marketOpen = false;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    _game.devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final padding = MediaQuery.paddingOf(context);
    _game.hudInsets = EdgeInsets.fromLTRB(
      padding.left,
      padding.top + _panelHeight,
      padding.right,
      padding.bottom + _footHeight,
    );

    return Scaffold(
      backgroundColor: EnginePalette.gameBackground,
      body: Stack(
        children: [
          Positioned.fill(
            child: ValueListenableBuilder<bool>(
              valueListenable: _game.boardReady,
              builder: (context, ready, child) => WorldGestures(
                camera: ready ? _game.cameraController : null,
                enabled: !_handingOver && !_marketOpen,
                onTap: _onTap,
                onHold: _onHold,
                onHover: (position) => _game.pointAtScreen(position),
                child: child!,
              ),
              child: GameWidget(game: _game),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: ValueListenableBuilder<int>(
                valueListenable: _game.hudVersion,
                builder: (context, _, __) => _Hud(
                  game: _game,
                  onArm: (index) => setState(() => _game.arm(index)),
                  onOpenMarket: () => setState(() => _marketOpen = true),
                  onEndTurn: _endTurn,
                  onUndo: () => setState(_game.undo),
                  onWholeBoard: () => setState(_game.showWholeBoard),
                  onLeave: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ),
          // The market, over the board, while it is open.
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: _game.hudVersion,
              builder: (context, _, __) {
                if (!_marketOpen) return const SizedBox.shrink();
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _marketOpen = false),
                  child: ColoredBox(
                    color: const Color(0x66141E16),
                    child: SafeArea(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: GestureDetector(
                            onTap: () {},
                            child: SingleChildScrollView(
                              child: MarketPanel(
                                state: _matches.state,
                                onBuyRow: _buyRow,
                                onBuyBasic: _buyBasic,
                                onTrade: _trade,
                                onClose: () =>
                                    setState(() => _marketOpen = false),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // The handover between turns, over the board the next house is
          // about to play on. An empty box hit-tests as nothing.
          Positioned.fill(
            child: ValueListenableBuilder<int>(
              valueListenable: _game.hudVersion,
              builder: (context, _, __) {
                final state = _matches.state;
                if (state.isOver) {
                  return _MatchEnd(
                    state: state,
                    onLeave: () => Navigator.of(context).pop(),
                  );
                }
                if (!_handingOver) return const SizedBox.shrink();
                return _Handover(
                  state: state,
                  onTake: () => setState(() => _handingOver = false),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// What the panel at the top and the hand at the foot take of the
  /// viewport. Constants because the layout below is what sets them.
  static const double _panelHeight = 110;
  static const double _footHeight = 190;
}

class _Hud extends StatelessWidget {
  const _Hud({
    required this.game,
    required this.onArm,
    required this.onOpenMarket,
    required this.onEndTurn,
    required this.onUndo,
    required this.onWholeBoard,
    required this.onLeave,
  });

  final DomiValeGame game;
  final void Function(int index) onArm;
  final VoidCallback onOpenMarket;
  final VoidCallback onEndTurn;
  final VoidCallback onUndo;
  final VoidCallback onWholeBoard;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final state = game.state;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: StatusPanel(state: state),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              HudMenu(items: [
                HudMenuItem(
                  label: 'Whole board',
                  icon: Icons.fit_screen,
                  onTap: onWholeBoard,
                ),
                HudMenuItem(
                  label: 'Leave the valley',
                  icon: Icons.logout,
                  onTap: onLeave,
                ),
              ]),
            ],
          ),
          const SizedBox(height: 10),
          Align(alignment: Alignment.topLeft, child: _Reading(game: game)),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              HudChip(
                label: 'Undo',
                icon: Icons.undo,
                faded: !game.canUndo,
                onTap: onUndo,
              ),
              const Spacer(),
              HudButton(
                label: 'End turn',
                icon: Icons.check,
                onTap: onEndTurn,
              ),
            ],
          ),
          const SizedBox(height: 10),
          HandBar(
            state: state,
            armedIndex: game.input.armedIndex,
            onArm: onArm,
            onOpenMarket: onOpenMarket,
          ),
        ],
      ),
    );
  }
}

/// What the cell under the pointer or the held cell is: owner, terrain and
/// what stands on it. Under the panel, where the eye already goes.
class _Reading extends StatelessWidget {
  const _Reading({required this.game});

  final DomiValeGame game;

  @override
  Widget build(BuildContext context) {
    final cell = game.inspected;
    if (cell == null || !game.boardReady.value) return const SizedBox.shrink();
    final state = game.state;
    final board = state.board;
    final owner = state.ownerOf(cell);
    final city = state.cityAt(cell);
    final parts = <String>[board.terrainAt(cell).label];
    if (board.heightAt(cell) > 0) parts.add('height ${board.heightAt(cell)}');
    if (owner != MatchState.noHouse) parts.add(state.houses[owner].name);
    if (city != null) {
      final kind = city.districts[cell];
      parts.add(kind == null ? 'heart' : kind.label.toLowerCase());
      final yield = state.districtYield(cell);
      if (yield > 0) parts.add('yields $yield');
      final crowns = state.monumentCrowns(cell);
      if (crowns > 0) parts.add('$crowns crowns');
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: HudColours.panel,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        parts.join(' · '),
        style: const TextStyle(
          fontFamily: 'Nunito',
          fontWeight: FontWeight.w700,
          fontSize: 13,
          color: HudColours.text,
        ),
      ),
    );
  }
}

/// The card between turns: who plays next, and one press to take the turn.
class _Handover extends StatelessWidget {
  const _Handover({required this.state, required this.onTake});

  final MatchState state;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final house = state.currentHouse;
    return ColoredBox(
      color: const Color(0x99141E16),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: GamePalette.houses[house.seat],
                        shape: BoxShape.circle,
                        border: Border.all(color: Brand.ink, width: 2),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PaperHeading(
                        title: house.name,
                        subtitle: 'Round ${state.round} of ${Rules.rounds} · '
                            '${house.setup.banner.label}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerRight,
                  child: HudButton(
                    label: 'Take the turn',
                    icon: Icons.play_arrow,
                    onTap: onTake,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The end of the match: the standings, and the way out.
class _MatchEnd extends StatelessWidget {
  const _MatchEnd({required this.state, required this.onLeave});

  final MatchState state;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final standings = state.standings;
    final winner = state.houses[standings.first];
    return ColoredBox(
      color: const Color(0x99141E16),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: PaperCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                PaperHeading(
                  title: '${winner.name} rules the valley',
                  subtitle: 'After ${Rules.rounds} rounds.',
                ),
                const SizedBox(height: 16),
                for (final seat in standings)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: GamePalette.houses[seat],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            state.houses[seat].name,
                            style: const TextStyle(
                              fontFamily: 'Nunito',
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: Brand.ink,
                            ),
                          ),
                        ),
                        Text(
                          '${state.crownsOf(seat)} crowns · '
                          '${state.cellsOwnedBy(seat)} cells',
                          style: const TextStyle(
                            fontFamily: 'NunitoSans',
                            fontSize: 13,
                            color: Brand.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 22),
                Align(
                  alignment: Alignment.centerRight,
                  child: HudButton(
                    label: 'Leave the valley',
                    icon: Icons.logout,
                    onTap: onLeave,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
