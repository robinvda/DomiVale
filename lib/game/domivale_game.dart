import 'dart:math';
import 'dart:ui';

import 'package:domivale_rules/domivale_rules.dart';
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:vale_engine/utils/viewport_utils.dart';
import 'package:vale_engine/world/rendering/icon_atlas.dart';
import 'package:vale_engine/world/rendering/terrain_generator.dart';
import 'package:vale_engine/world/rendering/terrain_renderer.dart';

import '../core/game/camera_controller.dart';
import '../core/game/debug_controller.dart';
import '../core/game/error_log.dart';
import '../core/game/game_loop.dart';
import '../core/game/performance_monitor.dart';
import '../core/game/pixel_snapped_camera.dart';
import '../core/game/render_profiler.dart';
import '../core/world/rendering/profiled_terrain_renderer.dart';
import '../core/world/rendering/tap_ripple_renderer.dart';
import '../theme/district_look.dart';
import '../world/board_world.dart';
import '../world/rendering/board_bounds_renderer.dart';
import '../world/rendering/city_renderer.dart';
import '../world/rendering/preview_renderer.dart';
import '../world/rendering/territory_renderer.dart';
import 'input_controller.dart';
import 'match_controller.dart';

/// Side of one cell in world units. Shared with the other Vale games, so the
/// terrain art `vale_engine` draws reads at the same scale in all of them.
const double kTileSize = 32.0;

/// DomiVale's Flame game: the board drawn, and what the player is pointing
/// at. The match itself lives in [matches]; this only reads it and sends it
/// actions.
///
/// Around that it keeps the frame the board is drawn in: a fixed-timestep
/// loop under a variable-rate render, a pannable camera over the board, the
/// ground drawn from cached chunks, the frame accounting, and releasing the
/// cached textures on teardown.
class DomiValeGame extends FlameGame {
  DomiValeGame({required this.debugController, required this.matches})
      : super(camera: PixelSnappedCamera()) {
    input = InputController(matches);
    matches.addListener(_matchChanged);
  }

  /// Side of one cell, in world units.
  final double tileSize = kTileSize;

  final DebugController debugController;

  late final PerformanceMonitor performanceMonitor =
      PerformanceMonitor(sampleSize: 60);

  late final GameLoop gameLoop = GameLoop(
    tickRate: 60,
    onFixedUpdate: _runFixedUpdate,
  );

  /// The camera and the ground under the board. None of these exist until
  /// [onLoad] has built the board, because each needs its size; the screen's
  /// first frames come and go without them, and [boardReady] is what to
  /// listen to.
  late final CameraController cameraController;
  late final TerrainGenerator terrainGenerator;
  late final TerrainRenderer terrainRenderer;

  /// The ring a press leaves on the ground. Deliberately small: a ring drawn
  /// to the true reach of whatever a press affects swamps the cell the
  /// player actually pressed.
  late final TapRippleRenderer tapRippleRenderer = TapRippleRenderer(
    maxRadiusTiles: 1.2,
    tileSize: tileSize,
  );

  /// The display's pixel ratio, pushed in from the widget tree by the screen.
  ///
  /// Every cached bitmap is rasterized in logical pixels, so on a display
  /// that isn't 1:1 they are all upscaled onto the surface and look soft. It
  /// also decides the physical-pixel grid the camera draws on and the zooms
  /// it comes to rest on (see [TerrainRenderer.crispZooms]).
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio = 1.0;

  set devicePixelRatio(double value) {
    if (value <= 0 || (value - _devicePixelRatio).abs() < 0.01) return;
    _devicePixelRatio = value;
    (camera as PixelSnappedCamera).pixelRatio = value;
    // The screen reads this from its own `build`, which can land part-way
    // through `onLoad`; the renderer and the camera pick the stored value up
    // themselves when they are built.
    if (!_groundReady) return;
    terrainRenderer.devicePixelRatio = value;
    cameraController.crispZooms = TerrainRenderer.crispZooms(value);
  }

  /// Whether the camera and the ground exist. Set in [onLoad] once they are
  /// built, and what teardown asks before reaching for them.
  bool _groundReady = false;

  final MatchController matches;

  /// What is armed and what a tap plays. Exists before `onLoad`, so the hand
  /// can be pressed from the first frame.
  late final InputController input;

  late final BoardWorld boardWorld;

  late final TerritoryRenderer territoryRenderer;
  late final CityRenderer cityRenderer;
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
  /// HUD over it; a floor of 0.25 would show part of it.
  static const double _minZoom = 0.2;
  static const double _maxZoom = 3.0;

  bool _cameraPlaced = false;

  MatchState get state => matches.state;

  @override
  Future<void> onLoad() async {
    await super.onLoad();

    boardWorld =
        BoardWorld(board: state.board, seed: matches.match.header.seed);
    _mountGround();

    world.add(BoardBoundsRenderer(size: state.board.size, tileSize: tileSize));

    territoryRenderer = TerritoryRenderer(matches: matches, tileSize: tileSize);
    world.add(territoryRenderer);

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

    // The press ring draws over everything added before it.
    world.add(tapRippleRenderer);
    _refreshAll();
    boardReady.value = true;
  }

  Rect _visibleRect() => getVisibleWorldRect(this, tileSize, padding: 1);

  /// The camera and the ground, in the order they have to happen: the camera
  /// once the board's extent is known, opening on its middle, then the
  /// terrain at the bottom of the world. The whole board is visible to
  /// everyone, always — it is a board game — so no chunk of the ground is
  /// ever skipped.
  void _mountGround() {
    final extent = boardWorld.width * tileSize;
    cameraController = CameraController(
      camera: camera,
      minZoom: _minZoom,
      maxZoom: _maxZoom,
      worldBoundsMin: Vector2.zero(),
      worldBoundsMax: Vector2(extent, boardWorld.height * tileSize),
    )..crispZooms = TerrainRenderer.crispZooms(_devicePixelRatio);
    cameraController.moveTo(extent / 2, boardWorld.height * tileSize / 2);

    terrainGenerator = TerrainGenerator(
      boundedWorld: boardWorld,
      tileSize: tileSize,
    );
    terrainRenderer = ProfiledTerrainRenderer(
      generator: terrainGenerator,
      tileSize: tileSize,
    )..devicePixelRatio = _devicePixelRatio;
    world.add(terrainRenderer);
    _groundReady = true;
  }

  @override
  void update(double dt) {
    // Actual frame time, vsync and GPU included.
    performanceMonitor.recordFrameTime(dt);

    RenderProfiler.instance
        .setEnabled(debugController.isActive(DebugMode.showStatusBar));

    performanceMonitor.beginComponentUpdate();
    super.update(dt);
    performanceMonitor.endComponentUpdate();

    if (_groundReady) cameraController.updateKeyboardPan(dt);
    gameLoop.update(dt);

    // Commit the frame's fixed-update total so the average reads in
    // ms/frame, matching the frame and render averages.
    performanceMonitor.commitFrame();

    final metrics = performanceMonitor.currentMetrics;
    RenderProfiler.instance.endFrame();
    RenderProfiler.instance.updateContext(
      fps: metrics['fps'] as double,
      zoom: camera.viewfinder.zoom,
      cameraPosition: Offset(
        camera.viewfinder.position.x,
        camera.viewfinder.position.y,
      ),
      viewportSize: Size(camera.viewport.size.x, camera.viewport.size.y),
      avgFrameTimeMs: metrics['avgFrameTime'] as double,
      avgRenderWallMs: metrics['avgRenderTime'] as double,
      avgFixedUpdateMs: metrics['avgFixedUpdateTime'] as double,
      avgComponentUpdateMs: metrics['avgComponentUpdateTime'] as double,
      counts: boardReady.value ? _profilerCounts : const {},
    );
    RenderProfiler.instance.update(dt);
  }

  @override
  void render(Canvas canvas) {
    performanceMonitor.beginRender();
    try {
      super.render(canvas);
    } catch (error, stack) {
      // A throw inside any component's render() would otherwise unwind the
      // whole paint pass and freeze the canvas. Log it and let the next frame
      // try again, so one faulty renderer degrades to a glitch rather than a
      // frozen screen.
      ErrorLog.instance.record('render', error, stack);
    } finally {
      performanceMonitor.endRender();
    }
  }

  void _runFixedUpdate(double dt) {
    performanceMonitor.beginFixedUpdate();
    try {
      fixedUpdate(dt);
    } catch (error, stack) {
      // Same bargain as render(): one bad tick is a hiccup, an unwound loop
      // is a frozen game.
      ErrorLog.instance.record('fixedUpdate', error, stack);
    } finally {
      performanceMonitor.endFixedUpdate();
    }
  }

  @override
  void onDispose() {
    // Unconditional: a screen closed while `onLoad` is still building the
    // board still has to let go of what it had already made.
    releaseResources();
    // Chunk textures have to be released here. Flame's GameWidget teardown
    // never propagates onRemove to children, so a renderer's own onRemove
    // never fires, and the cached images would be left to the native
    // finaliser. Guarded on the ground rather than on `isLoaded`, since the
    // ground is built part-way through `onLoad`.
    if (_groundReady) {
      // A camera pan animation outlives the screen otherwise.
      cameraController.dispose();
      terrainRenderer.invalidateAllCaches();
    }
    super.onDispose();
  }

  /// Lets go of everything the game holds that will not be collected on its
  /// own. Called from [onDispose] whether or not loading finished, so
  /// nothing here may assume `onLoad` got as far as its own fields.
  void releaseResources() {
    matches.removeListener(_matchChanged);
    boardIcons.dispose();
    boardReady.dispose();
    hudVersion.dispose();
  }

  /// One simulation tick, run at a fixed rate by [gameLoop].
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
    if (!boardReady.value) return;
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

  /// Buys the card in [slot] of the row into the hand.
  Refusal? buyFromRow(int slot) => matches.apply(BuyFromRow(slot));

  /// Trades some of [give] for one [take], at the house's rate.
  Refusal? trade(Good give, Good take) =>
      matches.apply(Trade(give: give, take: take));

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

  /// What the profiler's periodic log counts.
  Map<String, int> get _profilerCounts => {
        'cells': state.board.cellCount,
        'cities': state.cities.length,
        'open': state.openLandCount,
      };
}
