import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

/// A camera that draws the world on whole physical pixels.
///
/// The camera's position is a free-floating number: panning, zooming towards
/// the cursor and an odd window width (whose centre is half a pixel) all leave
/// the world's translation between two screen pixels. Every cached texture is
/// then sampled half a pixel off, and bilinear filtering spreads each
/// one-pixel edge over two. A phone's pixels are small enough to hide that; a
/// desktop monitor at 100% shows it as a blurry map.
///
/// Only the drawn translation is rounded. The stored position is left as it
/// is, so panning keeps its precision and nothing that reads the camera
/// (tile picking, the ghost preview) sees a jump. The difference is under one
/// physical pixel either way.
class PixelSnappedCamera extends CameraComponent {
  PixelSnappedCamera();

  /// The screen's physical pixels per logical pixel, pushed in by the game
  /// that owns the camera. The snap is to this grid, not the logical one.
  double pixelRatio = 1.0;

  @override
  void renderTree(Canvas canvas) {
    final transform = viewfinder.transform;
    final offset = transform.offset;
    final x = offset.x;
    final y = offset.y;
    final zoom = transform.scale.x;
    offset.setValues(
      snapOffset(x,
          anchor: transform.position.x, zoom: zoom, ratio: pixelRatio),
      snapOffset(y,
          anchor: transform.position.y, zoom: zoom, ratio: pixelRatio),
    );
    try {
      super.renderTree(canvas);
    } finally {
      offset.setValues(x, y);
    }
  }

  /// The viewfinder offset closest to [offset] that puts the world's origin
  /// on a whole physical pixel.
  ///
  /// The viewfinder draws a world point at `anchor + (point + offset) * zoom`
  /// logical pixels, so the world's own translation is `anchor + offset *
  /// zoom`. That is rounded in physical pixels and solved back for the
  /// offset.
  @visibleForTesting
  static double snapOffset(
    double offset, {
    required double anchor,
    required double zoom,
    required double ratio,
  }) {
    if (zoom <= 0 || ratio <= 0) return offset;
    final physical = (anchor + offset * zoom) * ratio;
    return (physical.roundToDouble() / ratio - anchor) / zoom;
  }
}
