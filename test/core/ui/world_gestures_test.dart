import 'package:flame/components.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domivale/core/game/camera_controller.dart';
import 'package:domivale/core/ui/world_gestures.dart';

/// The gesture rules, which are the sort of thing that reads fine and behaves
/// wrong. Each of these was a bug in the game this came out of: a hold that
/// waited for the release, a hold whose release also counted as a tap, a hold
/// that stuck after the press turned into a drag.
void main() {
  late List<String> events;
  late CameraController camera;

  /// Whether the game claims to have undone the hold. False makes it say "not
  /// yet", which the layer has to keep asking about.
  late bool undoTakes;

  setUp(() {
    events = [];
    undoTakes = true;
    camera = CameraController(
      camera: CameraComponent(),
      worldBoundsMin: Vector2.zero(),
      worldBoundsMax: Vector2(1000, 1000),
    );
  });

  /// Mounts the layer with every callback recording its name.
  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    bool holdEnabled = true,
    bool hasCamera = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: WorldGestures(
          camera: hasCamera ? camera : null,
          enabled: enabled,
          holdEnabled: (_) => holdEnabled,
          onPressDown: (_) => events.add('down'),
          onTap: (_) => events.add('tap'),
          onHold: (_) => events.add('hold'),
          onHoldSuperseded: (_) {
            events.add('undo');
            return undoTakes;
          },
          onDragStart: (_) => events.add('dragStart'),
          onDragUpdate: (_) => events.add('dragUpdate'),
          onDragEnd: (_) => events.add('dragEnd'),
          onHover: (_) => events.add('hover'),
          onCameraMoved: (_) => events.add('cameraMoved'),
          onDragCancel: () => events.add('dragCancel'),
          // Something that paints, so it takes a hit — the real child is
          // a GameWidget, which does.
          child: const ColoredBox(color: Color(0xFF000000)),
        ),
      ),
    );
  }

  const middle = Offset(400, 300);

  testWidgets('a quick press and release is a tap', (tester) async {
    await pump(tester);
    await tester.tapAt(middle);
    expect(events, ['down', 'tap']);
  });

  testWidgets('a press held in place fires while it is still down',
      (tester) async {
    await pump(tester);
    final touch = await tester.startGesture(middle);
    await tester.pump(const Duration(milliseconds: 400));

    expect(events, contains('hold'),
        reason: 'waiting for the release feels broken');
    await touch.up();
  });

  testWidgets('a hold does not also count as a tap when it comes up',
      (tester) async {
    await pump(tester);
    final touch = await tester.startGesture(middle);
    await tester.pump(const Duration(milliseconds: 400));
    await touch.up();
    await tester.pumpAndSettle();

    expect(events, isNot(contains('tap')),
        reason: 'the release would undo whatever the hold just did');
  });

  testWidgets('a hold opens a drag, and moving on undoes the hold',
      (tester) async {
    await pump(tester);
    final touch = await tester.startGesture(middle);
    await tester.pump(const Duration(milliseconds: 400));
    expect(events, contains('dragStart'));

    await touch.moveBy(const Offset(60, 0));
    await tester.pump();

    expect(events, contains('undo'),
        reason: 'the press turned out to be a drag after all');
    await touch.up();
    expect(events, contains('dragEnd'));
  });

  testWidgets('once the game has undone the hold it is not asked again',
      (tester) async {
    await pump(tester);
    final touch = await tester.startGesture(middle);
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 4; i++) {
      await touch.moveBy(const Offset(30, 0));
      await tester.pump();
    }
    await touch.up();

    expect(events.where((e) => e == 'undo'), hasLength(1));
  });

  testWidgets('a game that says "not yet" keeps being asked', (tester) async {
    // The rule that matters: the first move update lands a pixel from the
    // press, so a game waiting to leave the tile it started on has not had a
    // real chance yet. A one-shot offer would be spent on that wobble.
    await pump(tester);
    undoTakes = false;
    final touch = await tester.startGesture(middle);
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 3; i++) {
      await touch.moveBy(const Offset(1, 0));
      await tester.pump();
    }
    await touch.up();

    expect(events.where((e) => e == 'undo'), hasLength(3),
        reason: 'asked on every move until the game takes it');
  });

  testWidgets('a game with a tool in hand gets the drag but no hold',
      (tester) async {
    await pump(tester, holdEnabled: false);
    final touch = await tester.startGesture(middle);
    await tester.pump(const Duration(milliseconds: 400));

    expect(events, contains('dragStart'));
    expect(events, isNot(contains('hold')));
    await touch.up();
  });

  testWidgets('with a tool in hand the release is still a tap', (tester) async {
    // The counterpart of the rule above: nothing was handled as a hold, so
    // the tap must come through.
    await pump(tester, holdEnabled: false);
    await tester.tapAt(middle);
    expect(events, contains('tap'));
  });

  testWidgets('a touch that moves without waiting pans, it does not drag',
      (tester) async {
    // The counterpart of the mouse rule, and the one that decides whether a
    // finger dragged across the world moves the camera or the world's
    // contents. Scale wins the arena, so nothing reaches the drag callbacks.
    await pump(tester);
    final touch = await tester.startGesture(middle);
    await touch.moveBy(const Offset(90, 60));
    await tester.pump();
    await touch.moveBy(const Offset(30, 20));
    await tester.pump();
    await touch.up();

    expect(events, isNot(contains('dragStart')),
        reason: 'a finger dragged without holding is a camera pan');
    expect(events, isNot(contains('hold')));
    expect(events, contains('cameraMoved'),
        reason: 'the game hears where the camera went, to aim a preview');
  });

  testWidgets('a mouse held still does not open a drag of its own',
      (tester) async {
    // If the mouse were handled by the touch recognisers, a held click would
    // open a drag as well as firing the hold.
    await pump(tester);
    final mouse =
        await tester.startGesture(middle, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));

    expect(events, contains('hold'));
    expect(events, isNot(contains('dragStart')));
    await mouse.up();
  });

  testWidgets('a mouse click is a tap and a mouse drag is a drag',
      (tester) async {
    await pump(tester);
    final mouse =
        await tester.startGesture(middle, kind: PointerDeviceKind.mouse);
    // The first move is what the recogniser accepts on, so it arrives as the
    // drag's start; the second is the first update.
    await mouse.moveBy(const Offset(80, 40));
    await tester.pump();
    await mouse.moveBy(const Offset(20, 10));
    await tester.pump();
    await mouse.up();

    expect(events, contains('dragStart'),
        reason: 'a mouse drags at once, with no hold first');
    expect(events, contains('dragUpdate'));
    expect(events, contains('dragEnd'));
    expect(events, isNot(contains('hold')));
  });

  testWidgets('a mouse held still fires a hold of its own', (tester) async {
    // The long-press recogniser excludes the mouse, so this is timed by hand
    // — and it must fire with the button still down.
    await pump(tester);
    final mouse =
        await tester.startGesture(middle, kind: PointerDeviceKind.mouse);
    await tester.pump(const Duration(milliseconds: 400));

    expect(events, contains('hold'));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(events, isNot(contains('tap')));
  });

  testWidgets('a mouse that moves off the spot never becomes a hold',
      (tester) async {
    await pump(tester);
    final mouse =
        await tester.startGesture(middle, kind: PointerDeviceKind.mouse);
    await mouse.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 400));

    expect(events, isNot(contains('hold')));
    await mouse.up();
  });

  testWidgets('a right-button drag pans the camera and reaches no callback',
      (tester) async {
    await pump(tester);
    camera.moveTo(500, 500);
    final before = camera.position.clone();

    final mouse = await tester.startGesture(
      middle,
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.moveBy(const Offset(-60, -40));
    await tester.pump();
    await mouse.up();

    expect(camera.position, isNot(before),
        reason: 'the camera should have moved');
    expect(events, isNot(contains('dragStart')),
        reason: 'panning is not a world drag');
  });

  testWidgets('a hover reaches the game, a hover from a finger does not',
      (tester) async {
    await pump(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(middle);
    await tester.pump();

    expect(events, contains('hover'));
  });

  group('before there is a world to touch', () {
    // A host builds its screen before the game has finished loading, so the
    // camera does not exist yet on the first frames. Asking for it there threw
    // and took the whole screen down with it, which is what a null camera
    // now means instead.
    testWidgets('a layer with no camera mounts and answers nothing',
        (tester) async {
      await pump(tester, hasCamera: false);
      await tester.tapAt(middle);
      final touch = await tester.startGesture(middle);
      await tester.pump(const Duration(milliseconds: 400));
      await touch.up();
      await tester.pumpAndSettle();

      expect(events, isEmpty);
    });

    testWidgets('the camera arriving on a later build brings it to life',
        (tester) async {
      await pump(tester, hasCamera: false);
      await pump(tester, hasCamera: true);
      await tester.tapAt(middle);

      expect(events, ['down', 'tap']);
    });
  });

  testWidgets('while disabled nothing reaches the game at all', (tester) async {
    await pump(tester, enabled: false);
    await tester.tapAt(middle);
    final touch = await tester.startGesture(middle);
    await tester.pump(const Duration(milliseconds: 400));
    await touch.up();

    expect(events, isEmpty);
  });
}
