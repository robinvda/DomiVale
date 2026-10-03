import 'dart:math';
import 'dart:ui';

import 'package:domivale_rules/domivale_rules.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:vale_engine/game/vale_game.dart';
import 'package:vale_engine/utils/viewport_utils.dart';
import 'package:vale_engine/world/rendering/icon_atlas.dart';
import 'package:vale_engine/world/terrain_world.dart';

import '../theme/district_look.dart';
import '../world/board_world.dart';
import '../world/rendering/board_bounds_renderer.dart';
import '../world/rendering/city_renderer.dart';
import '../world/rendering/preview_renderer.dart';
import '../world/rendering/territory_renderer.dart';
import '../world/rendering/yield_renderer.dart';
import 'input_controller.dart';
import 'match_controller.dart';

/// Side of one cell in world units. Shared with the other Vale games, so the
/// engine's terrain art reads at the same scale in all of them.
const double kTileSize = 32.0;

/// DomiVale's Flame game: the board drawn, and what the player is pointing
/// at. The match itself lives in [matches]; this only reads it and sends it
/// actions.
class DomiValeGame extends ValeGame {
  DomiValeGame({required super.debugController, required this.matches})
      : super(tileSize: kTileSize) {
    input = InputController(matches);
    matches.addListener(_matchChanged);
  }

  final MatchController matches;

  /// What is armed and what a tap plays. Exists before `onLoad`, so the hand
  /// can be pressed from the first frame.
  late final InputController input;

  late final BoardWorld boardWorld;

  @override
  TerrainWorld get terrainWorld => boardWorld;

  late final TerritoryRenderer territoryRenderer;
  late final CityRenderer cityRenderer;
  late final YieldRenderer yieldRenderer;
  late final PreviewRenderer previewRenderer;

  /// The board icons, baked once. Held by the game because it is the game's
  /// teardown that hands the texture back.
  late final IconAtlas boardIcons = IconAtlas(icons: DistrictLook.icons);

  /// Flips once the board and its renderers exist. A host builds its widget
  /// tree before Flame has run `onLoad`, so its first frames come and go
  /// with no camera to point at.
  final ValueNotifier<bool> boardReady = ValueNotifier(false);

  /// Bumped whenever something the HUD shows moves.
  final ValueNotifier<int> hudVersion = ValueNotifier(0);

  /// What the HUD covers of the viewport, in logical pixels. The screen sets
  /// this as it lays its chrome out, so a fit is a fit of the free part.
  EdgeInsets hudInsets = EdgeInsets.zero;

  /// Low enough that the largest board fits a narrow portrait screen with a
  /// HUD over it; the engine's default floor would show part of it.
  static const double _minZoom = 0.2;
  static const double _maxZoom = 3.0;

  bool _cameraPlaced = false;

  MatchState get state => matches.state;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    boardWorld =
        BoardWorld(board: state.board, seed: matches.match.header.seed);
    await mountGround(minZoom: _minZoom, maxZoom: _maxZoom);

    // The whole board is visible to everyone, always: it is a board game.
    explorationManager.disable();

    world.add(BoardBoundsRenderer(size: state.board.size, tileSize: tileSize));

    territoryRenderer = TerritoryRenderer(matches: matches, tileSize: tileSize);
    world.add(territoryRenderer);

    yieldRenderer = YieldRenderer(
      matches: matches,
      icons: boardIcons,
      tileSize: tileSize,
      visible: _visibleRect,
      zoom: () => cameraController.zoom,
      offered: () => input.offeredCells,
    );
    world.add(yieldRenderer);

    cityRenderer = CityRenderer(
      matches: matches,
      icons: boardIcons,
      tileSize: tileSize,
      visible: _visibleRect,
    );
    world.add(cityRenderer);

    // Over the board, because a preview is something the player is doing
    // rather than something the valley is.
    previewRenderer = PreviewRenderer(input: input, tileSize: tileSize);
    world.add(previewRenderer);

    mountOverlays();
    markRenderersReady();
    _refreshAll();
    boardReady.value = true;
  }

  Rect _visibleRect() => getVisibleWorldRect(this, tileSize, padding: 1);

  @override
  void releaseResources() {
    // Called whether or not loading finished, so nothing here may assume
    // `onLoad` got as far as its own fields.
    matches.removeListener(_matchChanged);
    boardIcons.dispose();
    boardReady.dispose();
    hudVersion.dispose();
  }

  @override
  void fixedUpdate(double dt) {
    // Turn-based: nothing moves between actions.
  }

  // ── Camera ─────────────────────────────────────────────────────────────

  /// Zoom at which the whole board fits the part of the viewport the HUD
  /// leaves. Recomputed because it depends on the viewport.
  double get fitZoom {
    if (!hasLayout) return 1.0;
    final viewport = camera.viewport.size;
    final freeX = viewport.x - hudInsets.horizontal;
    final freeY = viewport.y - hudInsets.vertical;
    if (freeX <= 0 || freeY <= 0) return 1.0;
    final extent = state.board.size * tileSize;
    return min(freeX / extent, freeY / extent).clamp(_minZoom, _maxZoom);
  }

  /// Shows the whole board. The camera starts here and this is the one
  /// control that moves it for the player.
  void showWholeBoard() {
    if (!boardReady.value) return;
    _frameBoard();
  }

  /// Sets the fit zoom and puts the middle of the board in the middle of the
  /// *free* part of the viewport, which is not its middle: the HUD takes
  /// more off one end than the other.
  void _frameBoard() {
    cameraController.setZoom(fitZoom);
    final applied = cameraController.zoom;
    final middle = state.board.size * tileSize / 2;
    cameraController.moveTo(
      middle + (hudInsets.right - hudInsets.left) / 2 / applied,
      middle + (hudInsets.bottom - hudInsets.top) / 2 / applied,
    );
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (!renderersReady) return;
    // The first resize is where the camera is placed at all, since `onLoad`
    // has no viewport to derive a zoom from. After that it is the player's.
    if (!_cameraPlaced) {
      _cameraPlaced = true;
      _frameBoard();
    }
  }

  // ── Pointing and playing ───────────────────────────────────────────────

  /// The cell under the pointer, or null off the board.
  Cell? get pointedAt => _pointedAt;
  Cell? _pointedAt;

  /// The cell the player is holding to read, or null.
  Cell? get inspected => _inspected;
  Cell? _inspected;

  /// Points at the cell under a screen position. Null off the board, so a
  /// press outside it reads as pointing at nothing.
  Cell? pointAtScreen(Offset screenPoint) {
    if (!boardReady.value) return null;
    final tile = cameraController.screenToTile(screenPoint, tileSize: tileSize);
    final cell = Cell(tile.x, tile.y);
    final at = state.board.contains(cell) ? cell : null;
    if (at != _pointedAt) {
      _pointedAt = at;
      _refreshPreview();
      hudVersion.value++;
    }
    return at;
  }

  void clearPointer() {
    if (_pointedAt == null) return;
    _pointedAt = null;
    if (boardReady.value) _refreshPreview();
    hudVersion.value++;
  }

  /// Arms the card at [index] in the hand, or disarms with null; arming the
  /// armed card disarms it. Reading a cell stops when a card is armed.
  void arm(int? index) {
    input.arm(index);
    _inspected = null;
    if (boardReady.value) _refreshPreview();
    hudVersion.value++;
  }

  /// Plays the armed card on [cell], or reads the cell when nothing is
  /// armed. Null when the tap did what it meant to, or why it did not.
  Refusal? tapAt(Cell cell) {
    if (!boardReady.value) return Refusal.cellOutsideBoard;
    if (input.armedKind == null) {
      inspect(_inspected == cell ? null : cell);
      return null;
    }
    final refusal = input.playAt(cell);
    if (refusal != null) return refusal;
    _refreshPreview();
    return null;
  }

  /// Reads [cell]: the HUD says what it is and the board rings it. Null
  /// clears the reading.
  void inspect(Cell? cell) {
    _inspected = cell;
    if (boardReady.value) _refreshPreview();
    hudVersion.value++;
  }

  /// Buys a basic card into the hand.
  Refusal? buyBasic(CardKind kind) => matches.apply(BuyBasic(kind));

  bool get canUndo => matches.canUndo;

  bool undo() => matches.undo();

  /// Ends the turn. Nothing is armed or read afterwards: the next house
  /// starts clean.
  bool endTurn() {
    if (!matches.endTurn()) return false;
    input.disarm();
    _inspected = null;
    if (boardReady.value) _refreshPreview();
    hudVersion.value++;
    return true;
  }

  /// The match changed: a play, a buy, an undo or a new turn. Everything
  /// derived from it is brought back into line on one path.
  void _matchChanged() {
    input.matchChanged();
    if (boardReady.value) _refreshAll();
    hudVersion.value++;
  }

  void _refreshAll() {
    territoryRenderer.refresh();
    _refreshPreview();
  }

  void _refreshPreview() {
    previewRenderer.refresh(pointed: _pointedAt, inspected: _inspected);
  }

  @override
  Map<String, int> get profilerCounts => {
        'cells': state.board.cellCount,
        'cities': state.cities.length,
        'open': state.openLandCount,
      };
}
