import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../game/camera_controller.dart';

/// Turns raw pointer input over a game world into the four things a game
/// actually wants to know: the player tapped here, held here, dragged from
/// here to there, or moved the pointer across the world.
///
/// The camera is driven from inside — pinch, one-finger pan, the scroll wheel
/// and a right-button drag never reach the callbacks, because no game wants to
/// implement panning again.
///
/// **Why this is a widget and not a handful of callbacks in a screen.** Getting
/// it right means four recognisers racing in one arena with the device kinds
/// split between them, and every one of the rules below was a bug first:
///
/// Touch, stylus and trackpad:
/// - a quick press and release, without moving → a tap
/// - a stationary press held for [holdDuration] → a hold
/// - a press that moves past the slop → the camera pans or zooms
///
/// Mouse (the long-press and scale recognisers exclude it):
/// - a click without movement → a tap
/// - the left button dragged → a drag, at once, with no hold first
/// - the right button dragged → the camera pans; no recogniser competes for
///   the secondary button, so this runs off the raw pointer stream
/// - the wheel → zoom
///
/// Two finger positions always resolve as a scale, which cancels the tap and
/// hold recognisers by itself, so there is no manual multi-touch handling here.
///
/// **A hold answers while the button is still down**, not on release —
/// waiting for the release feels broken. Touch gets that from the long-press
/// recogniser, which excludes the mouse, so a held *click* is timed here
/// instead. And a press already dealt with as a hold must not fire a tap when
/// it comes up, which is what [onHoldSuperseded] and the internal
/// already-handled flag are between them for.
class WorldGestures extends StatefulWidget {
  const WorldGestures({
    super.key,
    required this.camera,
    required this.child,
    this.enabled = true,
    this.onPressDown,
    this.onTap,
    this.onHold,
    this.onHoldSuperseded,
    this.holdEnabled,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDragCancel,
    this.onHover,
    this.onCameraMoved,
    this.holdDuration = const Duration(milliseconds: 300),
  });

  /// The camera this drives for pans and zooms.
  ///
  /// Null means the world it would look at does not exist yet, which leaves
  /// every gesture inert — there is nothing to pan, and nothing under the
  /// pointer to report. A host builds its screen before the game has finished
  /// loading, so it has nothing to pass on the first frames and must not be
  /// made to invent one.
  final CameraController? camera;

  final Widget child;

  /// When false, every gesture is ignored and the camera is left alone — for
  /// a cutscene or any other moment the player is not in control.
  final bool enabled;

  /// Any pointer going down on the world, before the recognisers have
  /// decided what the gesture is. For closing a menu or noting where
  /// something was when the gesture began.
  final void Function(Offset localPosition)? onPressDown;

  /// A press and release with no movement, at a local position.
  final void Function(Offset localPosition)? onTap;

  /// A press held in place long enough to mean it, reported while the pointer
  /// is still down.
  final void Function(Offset localPosition)? onHold;

  /// The hold that just fired turned out to be the start of a drag after all,
  /// so whatever it did should be undone. Carries where the pointer has got
  /// to, since a game often only wants to undo once it has genuinely moved
  /// on — a wobble under the finger is not a change of mind.
  ///
  /// **Return true once the undo has happened.** Returning false means "not
  /// yet", and the offer is repeated on the next move: the long-press
  /// recogniser has no slop after it accepts, so the very first move update
  /// arrives a pixel from where the press started — well inside the same
  /// tile. A one-shot offer would always be spent on that wobble and the
  /// undo would never happen at all.
  final bool Function(Offset localPosition)? onHoldSuperseded;

  /// Whether a hold should be watched for at all at this local position. A
  /// game with a tool in hand usually wants the press to go to the tool
  /// instead; returning false also stops the tap being swallowed.
  final bool Function(Offset localPosition)? holdEnabled;

  /// A drag over the world — after a hold on touch, immediately on a mouse
  /// left-drag.
  final void Function(Offset localPosition)? onDragStart;
  final void Function(Offset localPosition)? onDragUpdate;
  final void Function(Offset localPosition)? onDragEnd;
  final VoidCallback? onDragCancel;

  /// The mouse moved across the world without any button down.
  final void Function(Offset localPosition)? onHover;

  /// The camera moved of its own accord — for a game that wants to follow it,
  /// usually to keep a placement preview under the pointer.
  final void Function(Offset localPosition)? onCameraMoved;

  /// How long a stationary press has to last to count as a hold.
  final Duration holdDuration;

  @override
  State<WorldGestures> createState() => _WorldGesturesState();
}

/// Device kinds the touch-style recognisers handle. The mouse is deliberately
/// excluded: it gets an immediate drag on the left button and a camera pan on
/// the right, neither of which should wait for a hold.
const Set<PointerDeviceKind> _touchLikeDevices = {
  PointerDeviceKind.touch,
  PointerDeviceKind.stylus,
  PointerDeviceKind.invertedStylus,
  PointerDeviceKind.trackpad,
};

class _WorldGesturesState extends State<WorldGestures> {
  /// Where an active right-button camera drag last was.
  Offset? _rightDragLast;

  /// A mouse press on its way to becoming a hold.
  Timer? _mouseHoldTimer;
  Offset? _mouseHoldOrigin;

  /// Set once a press has been dealt with as a hold, so its release is not
  /// handled a second time as a tap.
  bool _holdHandled = false;

  /// Whether a hold has fired that a developing drag should undo.
  bool _holdPending = false;

  @override
  void dispose() {
    _cancelMouseHold();
    super.dispose();
  }

  bool _holdWanted(Offset at) => widget.holdEnabled?.call(at) ?? true;

  void _cancelMouseHold() {
    _mouseHoldTimer?.cancel();
    _mouseHoldTimer = null;
    _mouseHoldOrigin = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    widget.onPressDown?.call(event.localPosition);
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kSecondaryMouseButton) != 0) {
      _rightDragLast = event.localPosition;
      return;
    }

    _holdHandled = false;
    _holdPending = false;
    _cancelMouseHold();
    if (!_holdWanted(event.localPosition)) return;

    // Only the mouse needs its own timer; touch has the long-press
    // recogniser.
    if (event.kind == PointerDeviceKind.mouse) {
      _mouseHoldOrigin = event.localPosition;
      _mouseHoldTimer = Timer(widget.holdDuration, _onMouseHeld);
    }
  }

  void _onMouseHeld() {
    final origin = _mouseHoldOrigin;
    _cancelMouseHold();
    if (!mounted || origin == null || !_holdWanted(origin)) return;
    _holdHandled = true;
    _holdPending = true;
    widget.onHold?.call(origin);
  }

  void _onPointerMove(PointerMoveEvent event) {
    // Moving off the spot means this is a drag, not a hold.
    final holdOrigin = _mouseHoldOrigin;
    if (holdOrigin != null &&
        (event.localPosition - holdOrigin).distance > kTouchSlop) {
      _cancelMouseHold();
    }

    final last = _rightDragLast;
    if (last == null) return;
    if ((event.buttons & kSecondaryMouseButton) == 0) {
      _rightDragLast = null;
      return;
    }
    final delta = event.localPosition - last;
    _rightDragLast = event.localPosition;
    widget.camera?.panByScreenDelta(delta.dx, delta.dy);
    widget.onCameraMoved?.call(event.localPosition);
  }

  void _onPointerUpOrCancel(PointerEvent event) {
    _rightDragLast = null;
    _cancelMouseHold();
  }

  void _onPointerHover(PointerHoverEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    widget.onHover?.call(event.localPosition);
  }

  void _onTapUp(TapUpDetails details) {
    _cancelMouseHold();
    // A press already answered as a hold is finished; letting it tap too
    // would undo what the hold just did.
    if (_holdHandled) {
      _holdHandled = false;
      return;
    }
    widget.onTap?.call(details.localPosition);
  }

  void _onTapCancel() => _cancelMouseHold();

  void _onLongPressStart(LongPressStartDetails details) {
    // The question is asked before the drag opens, because opening it may
    // change whatever the game would have answered from.
    final wanted = _holdWanted(details.localPosition);
    // A hold on touch also opens a drag: if the finger then travels, the game
    // hears about it through onDragUpdate and can drop what the hold did.
    widget.onDragStart?.call(details.localPosition);
    if (!wanted) return;
    _holdHandled = true;
    _holdPending = true;
    widget.onHold?.call(details.localPosition);
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    _offerHoldUndo(details.localPosition);
    widget.onDragUpdate?.call(details.localPosition);
  }

  /// Offers the game the chance to undo what the hold did, and keeps offering
  /// until it says it has.
  void _offerHoldUndo(Offset at) {
    if (!_holdPending) return;
    final undo = widget.onHoldSuperseded;
    if (undo == null) {
      _holdPending = false;
      return;
    }
    if (undo(at)) _holdPending = false;
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _holdPending = false;
    widget.onDragEnd?.call(details.localPosition);
  }

  void _onLongPressCancel() {
    // Nothing to undo or end: this only fires when the recogniser gives up
    // *before* accepting, so onLongPressStart never ran and no drag opened.
    // A camera pan winning the arena arrives here on every touch pan.
    _holdPending = false;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    widget.camera?.onScaleUpdate(details);
    // A one-finger pan is also a way of aiming: the game hears where the
    // camera went so it can keep a preview under the finger.
    widget.onCameraMoved?.call(details.localFocalPoint);
  }

  void _onMousePanStart(DragStartDetails details) {
    _cancelMouseHold();
    widget.onDragStart?.call(details.localPosition);
  }

  void _onMousePanUpdate(DragUpdateDetails details) {
    _offerHoldUndo(details.localPosition);
    widget.onDragUpdate?.call(details.localPosition);
  }

  void _onMousePanEnd(DragEndDetails details) => widget.onDragEnd?.call(
        details.localPosition,
      );

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera;
    // No camera is the same answer as not enabled: the world is not there to
    // be touched.
    final on = widget.enabled && camera != null;
    return Listener(
      onPointerSignal: on ? camera.onPointerSignal : null,
      onPointerDown: on ? _onPointerDown : null,
      onPointerMove: on ? _onPointerMove : null,
      onPointerUp: on ? _onPointerUpOrCancel : null,
      onPointerCancel: on ? _onPointerUpOrCancel : null,
      onPointerHover: on ? _onPointerHover : null,
      child: RawGestureDetector(
        gestures: on
            ? <Type, GestureRecognizerFactory>{
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  TapGestureRecognizer.new,
                  (instance) => instance
                    ..onTapUp = _onTapUp
                    ..onTapCancel = _onTapCancel,
                ),
                LongPressGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        LongPressGestureRecognizer>(
                  () => LongPressGestureRecognizer(
                    duration: widget.holdDuration,
                    supportedDevices: _touchLikeDevices,
                  ),
                  (instance) => instance
                    ..onLongPressStart = _onLongPressStart
                    ..onLongPressMoveUpdate = _onLongPressMoveUpdate
                    ..onLongPressEnd = _onLongPressEnd
                    ..onLongPressCancel = _onLongPressCancel,
                ),
                ScaleGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                    ScaleGestureRecognizer>(
                  () => ScaleGestureRecognizer(
                      supportedDevices: _touchLikeDevices),
                  (instance) => instance
                    ..onStart = camera.onScaleStart
                    ..onUpdate = _onScaleUpdate
                    ..onEnd = camera.onScaleEnd,
                ),
                // Mouse only: a left-drag starts the same drag a hold does on
                // touch, with no delay. The default button filter accepts the
                // primary button, so a right-drag never reaches here.
                PanGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
                  () => PanGestureRecognizer(
                    supportedDevices: const {PointerDeviceKind.mouse},
                  ),
                  (instance) => instance
                    ..onStart = _onMousePanStart
                    ..onUpdate = _onMousePanUpdate
                    ..onEnd = _onMousePanEnd
                    ..onCancel = () => widget.onDragCancel?.call(),
                ),
              }
            : const <Type, GestureRecognizerFactory>{},
        child: widget.child,
      ),
    );
  }
}
