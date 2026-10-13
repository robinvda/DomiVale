/// The camera draws the world on whole physical pixels, whatever its stored
/// position. Between two pixels, every cached texture is sampled half a pixel
/// off and bilinear filtering blurs it.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:domivale/core/game/pixel_snapped_camera.dart';

void main() {
  group('snapping the offset', () {
    test('puts the world on a whole physical pixel', () {
      for (final ratio in [1.0, 1.25, 1.5, 2.0]) {
        for (final zoom in [0.25, 0.8, 1.0, 1.7, 3.0]) {
          // An odd window width puts the anchor on a half pixel.
          for (final anchor in [400.0, 400.5]) {
            for (final offset in [-1234.37, -512.0, -0.3]) {
              final snapped = PixelSnappedCamera.snapOffset(offset,
                  anchor: anchor, zoom: zoom, ratio: ratio);
              final physical = (anchor + snapped * zoom) * ratio;
              expect(physical, closeTo(physical.roundToDouble(), 1e-6),
                  reason: 'ratio $ratio zoom $zoom anchor $anchor');
              // And never moves the world by more than half a pixel.
              final unsnapped = (anchor + offset * zoom) * ratio;
              expect((physical - unsnapped).abs(), lessThanOrEqualTo(0.5));
            }
          }
        }
      }
    });

    test('leaves the offset alone without a zoom or ratio to snap to', () {
      expect(
        PixelSnappedCamera.snapOffset(-3.3, anchor: 1, zoom: 0, ratio: 1),
        -3.3,
      );
      expect(
        PixelSnappedCamera.snapOffset(-3.3, anchor: 1, zoom: 1, ratio: 0),
        -3.3,
      );
    });
  });
}
