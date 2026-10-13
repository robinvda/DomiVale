import 'dart:async' as async;
import 'dart:math';

import 'package:flame/components.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../ui/keyboard_modifiers.dart';
import 'package:vale_engine/utils/grid_pos.dart';

/// The camera over a bounded world: where it looks, how far in, and every way
/// a player moves it — pinch, drag, wheel, and the arrow or WASD keys.
///
/// It is handed the gestures rather than listening for them, so one widget
/// ([WorldGestures]) can decide which input belongs to the camera and which to
/// the game. Two rules here were bugs first:
///
/// - **Wheel zoom is exponential**, so a notch out and a notch back in are
///   exact inverses and a player always lands back on the zoom they started
///   from. See [wheelZoomFactor].
/// - **A zoom lock is only ever lifted deliberately**, through
///   [overrideZoom]. Player input goes through [setZoom], which a locked
///   camera ignores.
/// - **Zoom comes to rest on a crisp zoom** when the display allows one (see
///   [crispZooms]). The wheel steps from one to the next, and a pinch eases
///   onto the nearest when it ends. At any zoom in between, the ground is a
///   scaled texture, and on a desktop monitor that reads as a blurry map.
class CameraController {
  CameraController({
    required this.camera,
    this.minZoom = 0.25,
    this.maxZoom = 3.0,
    this.zoomLocked = false,
    this.worldBoundsMin,
    this.worldBoundsMax,
  }) {
    if (zoomLocked) {
      camera.viewfinder.zoom = minZoom;
    }
  }

  final CameraComponent camera;

  // Zoom constraints
  final double minZoom;
  final double maxZoom;

  /// Whether the zoom level is fixed. Pinch and scroll-wheel zoom are ignored
  /// and [setZoom] does nothing, so the view stays at [minZoom] for the whole
  /// game. Panning is unaffected. Set for browser builds, where zooming out
  /// puts more on screen than the canvas can draw smoothly.
  final bool zoomLocked;

  // World bounds (in world coordinates, i.e., pixels)
  final Vector2? worldBoundsMin;
  final Vector2? worldBoundsMax;

  /// Zoom change per unit of scroll delta. A typical wheel notch reports 100,
  /// which works out to about 10% a notch.
  static const double _wheelZoomRate = 0.001;

  /// Zoom multiplier for a wheel [scrollDelta].
  ///
  /// Exponential, so opposite deltas multiply back to exactly 1 and a player
  /// who zooms out and in again lands on the zoom they started from.
  static double wheelZoomFactor(double scrollDelta) =>
      exp(-scrollDelta * _wheelZoomRate);

  /// Scroll delta that makes one wheel step between [zoomStops]. Below a
  /// typical notch (100 on most platforms, less on some), so every notch is
  /// one step, while a smooth-scrolling wheel or a trackpad that sends many
  /// small deltas adds them up to a step instead of racing through the stops.
  static const double _wheelStepDelta = 40.0;

  /// A pause this long between wheel events starts the count for the next
  /// step from zero, so a few stray pixels of scroll never add up to a step
  /// long after the player stopped.
  static const Duration _wheelIdleReset = Duration(milliseconds: 300);

  /// Largest ratio between two neighbouring [zoomStops] outside the crisp
  /// range, where stops are only there so the wheel can reach [minZoom] and
  /// [maxZoom].
  static const double _fillStep = 1.25;

  /// Two zooms closer than this ratio count as the same stop.
  static const double _stopTolerance = 1e-4;

  /// How long a pinch takes to ease onto the nearest stop once it ends.
  static const Duration _settleDuration = Duration(milliseconds: 120);

  /// The zoom the reset control returns to: one world pixel per logical
  /// pixel, which is where the game's art is drawn at its own scale.
  static const double defaultZoom = 1.0;

  /// Zooms the camera comes to rest on, coarsest first. Empty means the zoom
  /// is free, as it is on a display where no zoom is crisp.
  @visibleForTesting
  List<double> get zoomStops => _zoomStops;
  List<double> _zoomStops = const [];

  /// Sets the zooms at which the ground is drawn without resampling, from
  /// `TerrainRenderer.crispZooms`.
  ///
  /// The ones inside [minZoom]..[maxZoom] become [zoomStops]. Steps of at
  /// most [_fillStep] are added beyond them, so the wheel still reaches both
  /// ends of the range. Those extra stops are not crisp.
  set crispZooms(List<double> zooms) {
    final inside = [
      for (final zoom in zooms)
        if (zoom >= minZoom * (1 - _stopTolerance) &&
            zoom <= maxZoom * (1 + _stopTolerance))
          zoom,
    ];
    if (inside.isEmpty) {
      _zoomStops = const [];
      return;
    }
    final below = <double>[];
    for (var zoom = inside.first; zoom / minZoom > 1 + _fillStepSlack;) {
      zoom = max(zoom / _fillStep, minZoom);
      below.add(zoom);
    }
    final above = <double>[];
    for (var zoom = inside.last; maxZoom / zoom > 1 + _fillStepSlack;) {
      zoom = min(zoom * _fillStep, maxZoom);
      above.add(zoom);
    }
    _zoomStops = [...below.reversed, ...inside, ...above];
  }

  /// A gap to [minZoom] or [maxZoom] narrower than this, as a ratio above 1,
  /// gets no stop of its own: the last stop is close enough to the end.
  static const double _fillStepSlack = 0.05;

  // Scale gesture state (handles both pan and zoom)
  double _baseZoom = 1.0;
  Vector2? _lastFocalPoint;

  /// Whether the current pinch changed the zoom, so its end should settle it.
  bool _zoomedThisGesture = false;

  /// Scroll delta counted towards the next wheel step. See [_wheelStepDelta].
  double _wheelAccumulated = 0.0;
  Duration? _lastWheelTime;

  /// The ease onto a stop after a pinch, while it runs.
  async.Timer? _settleTimer;

  void onScaleStart(ScaleStartDetails details) {
    _cancelSettle();
    _zoomedThisGesture = false;
    _baseZoom = camera.viewfinder.zoom;
    _lastFocalPoint = Vector2(details.focalPoint.dx, details.focalPoint.dy);
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    final focalPoint = Vector2(details.focalPoint.dx, details.focalPoint.dy);
    final viewportSize = camera.viewport.size;

    // Guard against invalid viewport size
    if (viewportSize.x <= 0 || viewportSize.y <= 0) return;

    final currentZoom = camera.viewfinder.zoom;
    if (currentZoom <= 0) return;

    // Handle zoom (when scale != 1.0)
    if (!zoomLocked && details.scale != 1.0) {
      _zoomAbout(
          focalPoint, (_baseZoom * details.scale).clamp(minZoom, maxZoom));
      _zoomedThisGesture = true;
    }

    // Handle pan (movement of focal point)
    if (_lastFocalPoint != null) {
      final delta = focalPoint - _lastFocalPoint!;
      camera.viewfinder.position -= delta / currentZoom;
    }

    _lastFocalPoint = focalPoint;
    _clampToBounds();
  }

  void onScaleEnd(ScaleEndDetails details) {
    final focalPoint = _lastFocalPoint;
    _lastFocalPoint = null;
    if (_zoomedThisGesture && focalPoint != null) _settleZoom(focalPoint);
    _zoomedThisGesture = false;
  }

  void onPointerSignal(PointerSignalEvent event) {
    if (zoomLocked) return;
    if (event is PointerScrollEvent) {
      final viewportSize = camera.viewport.size;
      final currentZoom = camera.viewfinder.zoom;

      // Guard against invalid viewport size or zoom
      if (viewportSize.x <= 0 || viewportSize.y <= 0 || currentZoom <= 0) {
        return;
      }
      _cancelSettle();

      final scrollDelta = event.scrollDelta.dy;
      final double newZoom;
      if (_zoomStops.isEmpty) {
        // Mouse wheel zoom. The factor is exponential so a notch out and a
        // notch back in are exact inverses: `1 - delta * k` is not, and a
        // player who zoomed out and back in landed 1% lower every round
        // trip, drifting off the zoom they started at and never able to
        // return to it.
        newZoom = (currentZoom * wheelZoomFactor(scrollDelta))
            .clamp(minZoom, maxZoom);
      } else {
        final step = _wheelStep(scrollDelta, event.timeStamp);
        if (step == 0) return;
        final next = _nextStop(currentZoom, zoomIn: step > 0);
        if (next == null) return;
        newZoom = next;
      }

      // Zoom towards mouse position
      _zoomAbout(Vector2(event.position.dx, event.position.dy), newZoom);
      _clampToBounds();
    }
  }

  /// Adds [scrollDelta] to the count towards the next wheel step and returns
  /// the step it completes: 1 to zoom in, -1 to zoom out, 0 for none yet.
  ///
  /// Scrolling up (a negative delta) zooms in, as it does without stops.
  int _wheelStep(double scrollDelta, Duration timeStamp) {
    final last = _lastWheelTime;
    _lastWheelTime = timeStamp;
    if (last == null ||
        timeStamp - last > _wheelIdleReset ||
        scrollDelta.sign != _wheelAccumulated.sign) {
      _wheelAccumulated = 0.0;
    }
    _wheelAccumulated += scrollDelta;
    if (_wheelAccumulated.abs() < _wheelStepDelta) return 0;
    final step = _wheelAccumulated < 0 ? 1 : -1;
    _wheelAccumulated = 0.0;
    return step;
  }

  /// The first stop past [zoom] in the direction asked for, or null at the
  /// end of the range. A zoom between two stops goes to the neighbour on
  /// that side, so the first step after a free zoom lands it on a stop.
  double? _nextStop(double zoom, {required bool zoomIn}) {
    if (zoomIn) {
      for (final stop in _zoomStops) {
        if (stop > zoom * (1 + _stopTolerance)) return stop;
      }
    } else {
      for (final stop in _zoomStops.reversed) {
        if (stop < zoom * (1 - _stopTolerance)) return stop;
      }
    }
    return null;
  }

  /// The stop nearest [zoom], measured as a ratio so a step in means the
  /// same as a step out.
  double _nearestStop(double zoom) {
    var nearest = _zoomStops.first;
    var nearestDistance = double.infinity;
    for (final stop in _zoomStops) {
      final distance = log(stop / zoom).abs();
      if (distance < nearestDistance) {
        nearest = stop;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  /// Eases the zoom onto the nearest stop, keeping [focalPoint] still on the
  /// screen, the way the pinch that just ended was zooming.
  void _settleZoom(Vector2 focalPoint) {
    if (_zoomStops.isEmpty || zoomLocked) return;
    final start = camera.viewfinder.zoom;
    if (start <= 0) return;
    final target = _nearestStop(start);
    if ((target / start - 1).abs() < _stopTolerance) {
      // Close is not enough: the ground only takes its 1:1 level on the
      // stop itself.
      _zoomAbout(focalPoint, target);
      _clampToBounds();
      return;
    }

    const frameInterval = Duration(milliseconds: 16);
    final totalMs = _settleDuration.inMilliseconds;
    // Counted in timer ticks rather than read off the wall clock, for the
    // same reason as [animateTo].
    var elapsed = 0;
    _settleTimer = async.Timer.periodic(frameInterval, (timer) {
      elapsed += frameInterval.inMilliseconds;
      final t = (elapsed / totalMs).clamp(0.0, 1.0);
      final eased = 1 - pow(1 - t, 3);
      // Interpolated as a ratio, so the ease reads the same zooming in as
      // zooming out. The last tick sets the stop exactly.
      final zoom = t >= 1.0 ? target : start * pow(target / start, eased);
      _zoomAbout(focalPoint, zoom.toDouble());
      _clampToBounds();
      if (t >= 1.0) _cancelSettle();
    });
  }

  void _cancelSettle() {
    _settleTimer?.cancel();
    _settleTimer = null;
  }

  /// Changes the zoom to [newZoom] while the world point under [screenPoint]
  /// stays under it. Leaves the bounds to the caller, which may still be
  /// moving the camera.
  void _zoomAbout(Vector2 screenPoint, double newZoom) {
    final viewportSize = camera.viewport.size;
    final currentZoom = camera.viewfinder.zoom;
    if (viewportSize.x <= 0 || viewportSize.y <= 0 || currentZoom <= 0) {
      return;
    }

    final worldPosBefore = camera.viewfinder.position +
        (screenPoint - viewportSize / 2) / currentZoom;

    camera.viewfinder.zoom = newZoom;

    final worldPosAfter =
        camera.viewfinder.position + (screenPoint - viewportSize / 2) / newZoom;

    camera.viewfinder.position -= worldPosAfter - worldPosBefore;
  }

  /// Keeps the camera's centre inside the world, when bounds were given.
  /// The view can still show ground beyond the edge; what it cannot do is
  /// drift off the world entirely.
  void _clampToBounds() {
    if (worldBoundsMin == null || worldBoundsMax == null) return;

    final pos = camera.viewfinder.position;
    camera.viewfinder.position = Vector2(
      pos.x.clamp(worldBoundsMin!.x, worldBoundsMax!.x),
      pos.y.clamp(worldBoundsMin!.y, worldBoundsMax!.y),
    );
  }

  /// Puts the camera on a world position at once, with no animation.
  void moveTo(double x, double y) {
    camera.viewfinder.position = Vector2(x, y);
    _clampToBounds();
  }

  /// Sets the zoom level. Ignored while [zoomLocked] is set, so restoring a
  /// save can't strand the player at a zoom they have no way to undo.
  void setZoom(double zoom) {
    if (zoomLocked) return;
    _cancelSettle();
    camera.viewfinder.zoom = zoom.clamp(minZoom, maxZoom);
  }

  /// Returns the view to [defaultZoom], keeping the camera where it is.
  /// Ignored while [zoomLocked] is set, where there is only one zoom anyway.
  void resetZoom() {
    if (zoomLocked) return;
    _cancelSettle();
    camera.viewfinder.zoom = defaultZoom.clamp(minZoom, maxZoom);
  }

  /// Sets the zoom level even while [zoomLocked] is set.
  ///
  /// Only for a view that drives the camera itself and hands the zoom back
  /// afterwards — a scripted fly-over, say. Anything reacting to player input
  /// belongs in [setZoom] instead, so a locked view stays locked. Skips the
  /// [minZoom]/[maxZoom] clamp while locked, since those collapse to the
  /// single fixed level.
  void overrideZoom(double zoom) {
    _cancelSettle();
    camera.viewfinder.zoom = zoomLocked ? zoom : zoom.clamp(minZoom, maxZoom);
  }

  /// Where a point on the screen falls in the world.
  ///
  /// Every game that lets a player point at the ground needs this, and it is
  /// easy to get subtly wrong: the offset is from the *centre* of the
  /// viewport, not its corner, and it is divided by zoom rather than
  /// multiplied.
  Vector2 screenToWorld(Offset screenPoint) {
    final viewport = camera.viewport.size;
    final point = Vector2(screenPoint.dx, screenPoint.dy);
    return position + (point - viewport / 2) / zoom;
  }

  /// Which tile a point on the screen falls on.
  GridPos screenToTile(Offset screenPoint, {required double tileSize}) {
    final world = screenToWorld(screenPoint);
    return GridPos.fromWorld(world.x, world.y, tileSize: tileSize);
  }

  /// Where the camera is looking, in world coordinates.
  Vector2 get position => camera.viewfinder.position;

  /// World pixels per logical pixel: above 1 is zoomed in.
  double get zoom => camera.viewfinder.zoom;

  /// Currently running smooth-pan animation, if any. Cancelled when a new
  /// animation starts so panning targets don't collide.
  async.Timer? _animationTimer;

  /// Smoothly pans the camera to [targetX], [targetY] in world pixel
  /// coordinates over [duration]. Cancels any in-flight animation.
  void animateTo(
    double targetX,
    double targetY, {
    Duration duration = const Duration(milliseconds: 500),
  }) {
    _animationTimer?.cancel();

    final startX = camera.viewfinder.position.x;
    final startY = camera.viewfinder.position.y;
    final totalMs = duration.inMilliseconds;
    if (totalMs <= 0) {
      moveTo(targetX, targetY);
      return;
    }

    const frameInterval = Duration(milliseconds: 16);
    // Time is counted in ticks of the timer rather than read off the wall
    // clock. The two agree in an app, and only the tick count agrees with a
    // test's own clock — an animation timed by `DateTime.now()` never
    // progresses under a fake one, so nothing about this could be tested.
    var elapsed = 0.0;

    _animationTimer = async.Timer.periodic(frameInterval, (timer) {
      elapsed += frameInterval.inMilliseconds;
      final t = (elapsed / totalMs).clamp(0.0, 1.0);
      // Smooth ease-in-out curve
      final eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2;
      final x = startX + (targetX - startX) * eased;
      final y = startY + (targetY - startY) * eased;
      moveTo(x, y);

      if (t >= 1.0) {
        timer.cancel();
        _animationTimer = null;
      }
    });
  }

  // Keyboard pan
  /// Speed in world pixels per second at zoom 1.0.
  static const double _keyPanSpeed = 400.0;

  /// Speed multiplier while Shift is held.
  static const double _keyPanFastMultiplier = 2.5;

  /// Polls [HardwareKeyboard] for arrow keys and WASD and pans accordingly.
  /// Call every frame with [dt] in seconds.
  void updateKeyboardPan(double dt) {
    final kb = HardwareKeyboard.instance;

    var dx = 0.0;
    var dy = 0.0;

    if (kb.isLogicalKeyPressed(LogicalKeyboardKey.arrowLeft) ||
        kb.isLogicalKeyPressed(LogicalKeyboardKey.keyA)) {
      dx -= 1.0;
    }
    if (kb.isLogicalKeyPressed(LogicalKeyboardKey.arrowRight) ||
        kb.isLogicalKeyPressed(LogicalKeyboardKey.keyD)) {
      dx += 1.0;
    }
    if (kb.isLogicalKeyPressed(LogicalKeyboardKey.arrowUp) ||
        kb.isLogicalKeyPressed(LogicalKeyboardKey.keyW)) {
      dy -= 1.0;
    }
    if (kb.isLogicalKeyPressed(LogicalKeyboardKey.arrowDown) ||
        kb.isLogicalKeyPressed(LogicalKeyboardKey.keyS)) {
      dy += 1.0;
    }

    if (dx == 0.0 && dy == 0.0) return;

    // Normalised, or holding two keys would pan diagonally at √2 the speed of
    // either one on its own.
    if (dx != 0.0 && dy != 0.0) {
      const invRoot2 = 0.7071067811865476;
      dx *= invRoot2;
      dy *= invRoot2;
    }

    // Don't pan while the player is typing in a text field (save names,
    // map labels) — those keystrokes belong to the field, not the camera.
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null) {
      return;
    }

    // Move faster when zoomed out so it feels consistent, and faster still
    // while Shift is held. Shift comes from KeyboardModifiers rather than a
    // direct HardwareKeyboard poll — see its doc for why polling modifiers
    // is unreliable.
    var speed = _keyPanSpeed / camera.viewfinder.zoom;
    if (KeyboardModifiers.shiftHeld.value) {
      speed *= _keyPanFastMultiplier;
    }
    camera.viewfinder.position += Vector2(dx * speed * dt, dy * speed * dt);
    _clampToBounds();
  }

  /// Stops anything this controller has running. Called by `DomiValeGame` on
  /// teardown: an [animateTo] in flight otherwise keeps moving a camera whose
  /// screen has already gone, for the rest of the animation's duration.
  void dispose() {
    _animationTimer?.cancel();
    _animationTimer = null;
    _cancelSettle();
  }

  /// Pans the camera by a screen-space delta (e.g. from a right-mouse drag),
  /// converting to world units at the current zoom.
  void panByScreenDelta(double dx, double dy) {
    final currentZoom = camera.viewfinder.zoom;
    if (currentZoom <= 0) return;
    camera.viewfinder.position -= Vector2(dx, dy) / currentZoom;
    _clampToBounds();
  }
}
