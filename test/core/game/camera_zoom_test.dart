/// Wheel zoom has to be reversible: a player who zooms out and back in should
/// land on the zoom they started from. The old `1 - delta * k` factor gave
/// 0.9 out and 1.1 in, so every round trip lost 1% and the view drifted away
/// from the zoom the art is drawn at, with no way back to it.
library;

import 'package:flame/camera.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:domivale/core/game/camera_controller.dart';
import 'package:vale_engine/world/rendering/terrain_renderer.dart';

void main() {
  group('wheel zoom', () {
    test('opposite notches are exact inverses', () {
      const notch = 100.0;
      final out = CameraController.wheelZoomFactor(notch);
      final back = CameraController.wheelZoomFactor(-notch);
      expect(out * back, closeTo(1.0, 1e-12));
    });

    test('a long round trip returns to the starting zoom', () {
      var zoom = 1.0;
      for (var i = 0; i < 12; i++) {
        zoom *= CameraController.wheelZoomFactor(120.0);
      }
      for (var i = 0; i < 12; i++) {
        zoom *= CameraController.wheelZoomFactor(-120.0);
      }
      expect(zoom, closeTo(1.0, 1e-9));
    });

    test('scrolling down zooms out and up zooms in', () {
      expect(CameraController.wheelZoomFactor(100.0), lessThan(1.0));
      expect(CameraController.wheelZoomFactor(-100.0), greaterThan(1.0));
    });

    test('a notch is a gentle step, not a jump', () {
      final factor = CameraController.wheelZoomFactor(-100.0);
      expect(factor, greaterThan(1.05));
      expect(factor, lessThan(1.2));
    });
  });
  group('zoom stops', () {
    const centre = Offset(400, 300);

    CameraController controller({double pixelRatio = 1.0}) => CameraController(
          camera: CameraComponent(
            world: World(),
            viewport: FixedSizeViewport(800, 600),
          ),
        )..crispZooms = TerrainRenderer.crispZooms(pixelRatio);

    var clock = Duration.zero;
    void scroll(CameraController camera, double delta,
        {Duration after = const Duration(milliseconds: 50)}) {
      clock += after;
      camera.onPointerSignal(PointerScrollEvent(
        position: centre,
        scrollDelta: Offset(0, delta),
        timeStamp: clock,
      ));
    }

    test('reach both ends of the zoom range', () {
      for (final ratio in [1.0, 1.25, 1.5]) {
        final stops = controller(pixelRatio: ratio).zoomStops;
        expect(stops.first, closeTo(0.25, 1e-9), reason: 'ratio $ratio');
        expect(stops.last, closeTo(3.0, 1e-9), reason: 'ratio $ratio');
        for (var i = 1; i < stops.length; i++) {
          expect(stops[i] / stops[i - 1], inInclusiveRange(1.05, 1.5),
              reason: 'ratio $ratio between ${stops[i - 1]} and ${stops[i]}');
        }
      }
    });

    test('include every crisp zoom inside the range', () {
      final stops = controller(pixelRatio: 1.25).zoomStops;
      for (final crisp in TerrainRenderer.crispZooms(1.25)) {
        if (crisp < 0.25 || crisp > 3.0) continue;
        expect(stops, contains(closeTo(crisp, 1e-9)));
      }
    });

    test('a wheel notch steps to the next stop, and back again', () {
      final camera = controller();
      expect(camera.zoom, 1.0);
      scroll(camera, -100);
      expect(camera.zoom, closeTo(1.25, 1e-6));
      scroll(camera, 100);
      expect(camera.zoom, closeTo(1.0, 1e-6));
      scroll(camera, 100);
      expect(camera.zoom, closeTo(0.875, 1e-6));
    });

    test('small deltas add up to one step instead of one step each', () {
      final camera = controller();
      for (var i = 0; i < 3; i++) {
        scroll(camera, -10, after: const Duration(milliseconds: 10));
      }
      expect(camera.zoom, 1.0, reason: '30 is less than a step');
      scroll(camera, -10, after: const Duration(milliseconds: 10));
      expect(camera.zoom, closeTo(1.25, 1e-6));
    });

    test('a pause forgets a part-counted step', () {
      final camera = controller();
      scroll(camera, -30);
      scroll(camera, -30, after: const Duration(seconds: 1));
      expect(camera.zoom, 1.0);
    });

    test('the first step from a free zoom lands on a stop', () {
      final camera = controller()..setZoom(1.1);
      scroll(camera, 100);
      expect(camera.zoom, closeTo(1.0, 1e-6));
    });

    test('the wheel stays put at the end of the range', () {
      final camera = controller()..setZoom(3.0);
      scroll(camera, -100);
      expect(camera.zoom, closeTo(3.0, 1e-6));
    });

    test('with no stops the wheel zooms freely, as before', () {
      final camera = controller(pixelRatio: 3.0);
      expect(camera.zoomStops, isEmpty);
      scroll(camera, -100);
      expect(
          camera.zoom, closeTo(CameraController.wheelZoomFactor(-100), 1e-6));
    });

    testWidgets('a pinch eases onto the nearest stop when it ends',
        (tester) async {
      final camera = controller();
      addTearDown(camera.dispose);
      camera.onScaleStart(ScaleStartDetails(focalPoint: centre));
      camera.onScaleUpdate(ScaleUpdateDetails(focalPoint: centre, scale: 1.2));
      camera.onScaleEnd(ScaleEndDetails());
      expect(camera.zoom, closeTo(1.2, 1e-6), reason: 'not snapped at once');

      await tester.pump(const Duration(milliseconds: 500));
      expect(camera.zoom, 1.25, reason: 'exactly on the stop');
    });

    testWidgets('a pinch that only pans leaves the zoom alone', (tester) async {
      final camera = controller()..setZoom(1.1);
      addTearDown(camera.dispose);
      camera.onScaleStart(ScaleStartDetails(focalPoint: centre));
      camera.onScaleUpdate(
          ScaleUpdateDetails(focalPoint: centre + const Offset(20, 0)));
      camera.onScaleEnd(ScaleEndDetails());

      await tester.pump(const Duration(milliseconds: 500));
      expect(camera.zoom, closeTo(1.1, 1e-6));
    });

    testWidgets('a new pinch stops the ease of the last one', (tester) async {
      final camera = controller();
      addTearDown(camera.dispose);
      camera.onScaleStart(ScaleStartDetails(focalPoint: centre));
      camera.onScaleUpdate(ScaleUpdateDetails(focalPoint: centre, scale: 1.2));
      camera.onScaleEnd(ScaleEndDetails());
      await tester.pump(const Duration(milliseconds: 32));
      camera.onScaleStart(ScaleStartDetails(focalPoint: centre));
      final held = camera.zoom;

      await tester.pump(const Duration(milliseconds: 500));
      expect(camera.zoom, held);
    });
  });
}
