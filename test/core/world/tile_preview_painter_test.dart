import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vale_engine/theme/engine_palette.dart';
import 'package:vale_engine/utils/grid_pos.dart';
import 'package:domivale/core/world/grid/tile_targeting.dart';
import 'package:domivale/core/world/rendering/tile_preview_painter.dart';

/// What a preview actually puts on the canvas. Worth pinning because the
/// numbers are the whole behaviour: a fill four times too opaque or a stroke
/// half a pixel out changes what the player sees while nothing looks wrong in
/// the code, and that is exactly how the offered-cell contrast was lost once.
void main() {
  const tileSize = 32.0;
  late TilePreviewPainter painter;
  late _RecordingCanvas canvas;

  setUp(() {
    painter = TilePreviewPainter(tileSize: tileSize);
    canvas = _RecordingCanvas();
  });

  group('one tile', () {
    test('covers exactly its own square', () {
      painter.drawTile(canvas, const GridPos(2, 3), TileTint.valid);
      expect(canvas.rects.first, const Rect.fromLTWH(64, 96, 32, 32));
      expect(painter.rectOf(const GridPos(2, 3)),
          const Rect.fromLTWH(64, 96, 32, 32));
    });

    test('is filled and then outlined', () {
      painter.drawTile(canvas, const GridPos(0, 0), TileTint.valid);
      expect(canvas.styles, [PaintingStyle.fill, PaintingStyle.stroke],
          reason: 'an outline drawn first would be painted over');
    });

    test('can be drawn without an outline', () {
      painter.drawTile(canvas, const GridPos(0, 0), TileTint.valid,
          border: false);
      expect(canvas.rects, hasLength(1));
      expect(canvas.styles, [PaintingStyle.fill]);
    });

    test('each tint has its own colours', () {
      final seen = <TileTint, List<int>>{};
      for (final tint in TileTint.values) {
        canvas = _RecordingCanvas();
        painter.drawTile(canvas, const GridPos(0, 0), tint);
        seen[tint] = [canvas.colors[0], canvas.colors[1]];
      }
      expect(seen[TileTint.valid], [
        EnginePalette.ghostValidFill.toARGB32(),
        EnginePalette.ghostValidBorder.toARGB32(),
      ]);
      expect(seen[TileTint.warning], [
        EnginePalette.ghostWarningFill.toARGB32(),
        EnginePalette.ghostWarningBorder.toARGB32(),
      ]);
      expect(seen[TileTint.invalid], [
        EnginePalette.ghostInvalidFill.toARGB32(),
        EnginePalette.ghostInvalidBorder.toARGB32(),
      ]);
      expect(seen[TileTint.offered], [
        EnginePalette.tileOfferedFill.toARGB32(),
        EnginePalette.tileOfferedBorder.toARGB32(),
      ]);
      expect(seen.values.map((c) => c.join(',')).toSet(),
          hasLength(TileTint.values.length),
          reason: 'no two tints may look the same');
    });
  });

  group('offered cells', () {
    test('the one under the pointer is far brighter than the rest', () {
      // The point of the tint: a whole ring is shown at once, so the tile
      // about to be taken has to stand out by brightness and not only by hue.
      painter.drawOffered(
        canvas,
        const [GridPos(0, 0), GridPos(1, 0)],
        pointingAt: const GridPos(1, 0),
      );

      final quiet = canvas.colors[0] >>> 24;
      final bright = canvas.colors[2] >>> 24;
      expect(bright, greaterThan(quiet * 3),
          reason: 'lose this gap and the ring reads as one flat field');
    });

    test('the quiet ones are outlined more thinly', () {
      painter.drawOffered(
        canvas,
        const [GridPos(0, 0), GridPos(1, 0)],
        pointingAt: const GridPos(1, 0),
      );
      expect(canvas.strokeWidths[1], lessThan(canvas.strokeWidths[3]));
    });

    test('with nothing pointed at they are all drawn quietly', () {
      painter.drawOffered(canvas, const [GridPos(0, 0), GridPos(1, 0)]);
      expect(canvas.colors[0], EnginePalette.tileOfferedFill.toARGB32());
      expect(canvas.colors[2], EnginePalette.tileOfferedFill.toARGB32());
    });

    test('every offered cell is drawn', () {
      painter.drawOffered(
        canvas,
        const [GridPos(0, 0), GridPos(1, 0), GridPos(2, 0)],
      );
      expect(canvas.rects, hasLength(6), reason: 'a fill and an outline each');
    });
  });

  group('a sweep', () {
    test('is one rectangle over the whole span, not a tile each', () {
      painter.drawSweep(canvas, const GridPos(0, 0), const GridPos(2, 1));
      expect(canvas.rects, hasLength(2), reason: 'one fill, one outline');
      expect(canvas.rects.first, const Rect.fromLTRB(0, 0, 96, 64),
          reason: 'reaching the outside of the far tile');
    });

    test('uses the selection colours', () {
      painter.drawSweep(canvas, const GridPos(0, 0), const GridPos(1, 1));
      expect(canvas.colors[0], EnginePalette.selectionRectFill.toARGB32());
      expect(canvas.colors[1], EnginePalette.selectionRectBorder.toARGB32());
    });

    test('its outline is full width, not the offered cells\' thin one', () {
      painter.drawTile(canvas, const GridPos(0, 0), TileTint.offered);
      final thin = canvas.strokeWidths[1];
      painter.drawSweep(canvas, const GridPos(0, 0), const GridPos(1, 1));
      expect(canvas.strokeWidths.last, greaterThan(thin));
    });
  });

  test('a whole drag is drawn tile by tile in its own answer', () {
    final targeting = TileTargeting()
      ..beginDrag(const GridPos(0, 0))
      ..updateDrag(const GridPos(1, 0), isValid: (tile) => tile.x == 0);

    for (var i = 0; i < targeting.draggedTiles.length; i++) {
      painter.drawTile(
        canvas,
        targeting.draggedTiles[i],
        targeting.draggedValidity[i] ? TileTint.valid : TileTint.invalid,
      );
    }

    expect(canvas.colors[0], EnginePalette.ghostValidFill.toARGB32());
    expect(canvas.colors[2], EnginePalette.ghostInvalidFill.toARGB32());
  });

  test('drawing many tiles allocates no paints of its own', () {
    // The rule the class exists to keep: a preview redraws every frame while
    // a tool is in hand.
    painter.drawTiles(
      canvas,
      [for (var i = 0; i < 50; i++) GridPos(i, 0)],
      TileTint.valid,
    );
    expect(canvas.distinctPaints, hasLength(2),
        reason: 'one fill paint and one stroke paint, reused');
  });
}

/// A canvas that remembers the rectangles it was asked to draw and the paint
/// each was drawn with.
class _RecordingCanvas implements Canvas {
  final rects = <Rect>[];

  /// Colours as packed ARGB. A `Paint` round-trips its colour through
  /// floating point, so two Colours that print the same are not always
  /// `==` — comparing the packed value is the reliable test.
  final colors = <int>[];
  final styles = <PaintingStyle>[];
  final strokeWidths = <double>[];
  final _paints = <Paint>{};

  /// The paint objects used, by identity — two means the painter reused its
  /// own fields rather than making new ones.
  Set<Paint> get distinctPaints => _paints;

  @override
  void drawRect(Rect rect, Paint paint) {
    rects.add(rect);
    colors.add(paint.color.toARGB32());
    styles.add(paint.style);
    strokeWidths.add(paint.strokeWidth);
    _paints.add(paint);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
