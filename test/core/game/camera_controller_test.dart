import 'package:flame/components.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domivale/core/game/camera_controller.dart';

/// The camera as a game drives it: keyboard panning, and letting go of it.
void main() {
  CameraController controller() => CameraController(
        camera: CameraComponent(world: World()),
      );

  group('keyboard panning', () {
    testWidgets('one key pans at the plain speed', (tester) async {
      final camera = controller();
      final start = camera.position.clone();

      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      addTearDown(() => simulateKeyUpEvent(LogicalKeyboardKey.arrowRight));
      camera.updateKeyboardPan(1.0);

      expect(camera.position.x - start.x, greaterThan(0));
      expect(camera.position.y, start.y);
    });

    testWidgets('two keys pan diagonally at the same speed, not faster',
        (tester) async {
      final straight = controller();
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowRight);
      straight.updateKeyboardPan(1.0);
      final oneKey = straight.position.length;

      final diagonal = controller();
      await simulateKeyDownEvent(LogicalKeyboardKey.arrowDown);
      diagonal.updateKeyboardPan(1.0);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await simulateKeyUpEvent(LogicalKeyboardKey.arrowDown);

      // Unnormalised, holding both would cover √2 times the ground of either
      // on its own, and the camera would visibly hurry along a diagonal.
      // Loose to a float's precision: a Flame Vector2 holds 32-bit floats.
      expect(diagonal.position.length, closeTo(oneKey, 1e-3));
    });
  });

  group('letting go', () {
    testWidgets('teardown stops a pan already in flight', (tester) async {
      final camera = controller();
      camera.animateTo(1000, 1000, duration: const Duration(seconds: 1));

      await tester.pump(const Duration(milliseconds: 200));
      final partWay = camera.position.clone();
      expect(partWay.x, greaterThan(0), reason: 'the pan should have started');
      expect(partWay.x, lessThan(1000), reason: 'and not have finished');

      camera.dispose();
      await tester.pump(const Duration(seconds: 2));

      // Nothing moved after teardown — and a timer left running would fail
      // this test on its own, which is the point: the screen is gone.
      expect(camera.position.x, partWay.x);
      expect(camera.position.y, partWay.y);
    });

    testWidgets('teardown is safe with nothing running', (tester) async {
      final camera = controller();
      expect(camera.dispose, returnsNormally);
      expect(camera.dispose, returnsNormally);
    });

    testWidgets('a new pan replaces the one before it', (tester) async {
      final camera = controller();
      camera.animateTo(1000, 0, duration: const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      camera.animateTo(0, 1000, duration: const Duration(milliseconds: 200));

      await tester.pump(const Duration(milliseconds: 400));
      addTearDown(camera.dispose);

      expect(camera.position.y, closeTo(1000, 1e-6));
      expect(camera.position.x, closeTo(0, 1e-6),
          reason: 'the first pan was dropped rather than fighting the second');
    });
  });
}
