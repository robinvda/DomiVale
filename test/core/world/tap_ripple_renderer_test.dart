/// Lifecycle tests for the press ripple.
///
/// The ring is transient feedback, so the only thing that can really go wrong
/// is rings piling up: they have to expire on their own and rapid pressing
/// must not grow the list without bound.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:domivale/core/world/rendering/tap_ripple_renderer.dart';

TapRippleRenderer _renderer() =>
    TapRippleRenderer(maxRadiusTiles: 4.0, tileSize: 32.0);

void main() {
  test('a ring fades out on its own', () {
    final renderer = _renderer()..spawn(10, 10);
    expect(renderer.activeRipples, 1);

    // Well past any sensible ring lifetime.
    for (var i = 0; i < 120; i++) {
      renderer.update(1 / 60);
    }

    expect(renderer.activeRipples, 0);
  });

  test('rapid pressing does not pile rings up', () {
    final renderer = _renderer();
    for (var i = 0; i < 200; i++) {
      renderer.spawn(i.toDouble(), i.toDouble());
    }
    expect(renderer.activeRipples, lessThanOrEqualTo(8));
  });

  test('updating with no rings is harmless', () {
    final renderer = _renderer();
    renderer.update(1 / 60);
    expect(renderer.activeRipples, 0);
  });
}
