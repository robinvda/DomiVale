import 'dart:math';
import 'dart:ui';

import 'package:domivale/theme/game_palette.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vale_engine/theme/engine_palette.dart';

void main() {
  test('there is a colour for every seat', () {
    expect(GamePalette.houses, hasLength(4));
    expect(GamePalette.houses.map((c) => c.toARGB32()).toSet(), hasLength(4));
  });

  test('no two houses are close enough to confuse at 12 px', () {
    // At fit zoom a cell is 12 px on the largest board, so the board is read
    // by colour alone. Two colours that are merely different are not enough.
    for (var a = 0; a < GamePalette.houses.length; a++) {
      for (var b = a + 1; b < GamePalette.houses.length; b++) {
        final apart = _apart(GamePalette.houses[a], GamePalette.houses[b]);
        expect(
          apart,
          greaterThan(25),
          reason: 'houses $a and $b are $apart apart',
        );
      }
    }
  });

  test('every house stands out from every terrain it is washed over', () {
    const terrains = [
      EnginePalette.terrainGrass,
      EnginePalette.terrainForest,
      EnginePalette.terrainRock,
      EnginePalette.terrainWater,
    ];
    for (var seat = 0; seat < GamePalette.houses.length; seat++) {
      for (final terrain in terrains) {
        final apart = _apart(GamePalette.houses[seat], terrain);
        expect(
          apart,
          greaterThan(25),
          reason: 'house $seat on terrain $terrain is $apart apart',
        );
      }
    }
  });
}

/// How far apart two colours look, as a CIE76 difference in L*a*b*.
///
/// Perceptual rather than a channel-by-channel comparison: two colours can be
/// far apart in RGB and the same brown to a person, which is the mistake this
/// is here to catch.
double _apart(Color a, Color b) {
  final one = _lab(a);
  final two = _lab(b);
  return sqrt(
    pow(one[0] - two[0], 2) + pow(one[1] - two[1], 2) + pow(one[2] - two[2], 2),
  );
}

List<double> _lab(Color colour) {
  double linear(double channel) => channel <= 0.04045
      ? channel / 12.92
      : pow((channel + 0.055) / 1.055, 2.4).toDouble();
  final r = linear(colour.r);
  final g = linear(colour.g);
  final b = linear(colour.b);

  // sRGB to CIE XYZ, then XYZ to L*a*b* against the D65 white point.
  final x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
  final y = r * 0.2126 + g * 0.7152 + b * 0.0722;
  final z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;
  double bend(double t) =>
      t > 0.008856 ? pow(t, 1 / 3).toDouble() : 7.787 * t + 16 / 116;
  final fx = bend(x);
  final fy = bend(y);
  final fz = bend(z);
  return [116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz)];
}
