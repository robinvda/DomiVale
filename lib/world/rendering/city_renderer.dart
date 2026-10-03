import 'dart:ui';

import 'package:domivale_rules/domivale_rules.dart';
import 'package:flame/components.dart';
import 'package:vale_engine/world/rendering/icon_atlas.dart';
import 'package:vale_engine/world/rendering/sprite_batch.dart';

import '../../game/match_controller.dart';
import '../../theme/district_look.dart';
import '../../theme/game_palette.dart';

/// Hearts and districts: a rounded square in the cell's colour, a darker
/// outline, and a pale icon in the middle of it, the way LogiVale draws its
/// buildings.
///
/// A heart wears its house's colour; a district wears its kind's. Every path
/// and paint is built once, and the icons go out as one `drawAtlas` call.
class CityRenderer extends Component {
  CityRenderer({
    required this.matches,
    required this.icons,
    required double tileSize,
    required this.visible,
  })  : _tileSize = tileSize,
        _shape = _shapeFor(tileSize),
        _districtFills = [
          for (final kind in CardKind.values)
            Paint()..color = DistrictLook.of(kind).colour,
        ],
        _districtOutlines = [
          for (final kind in CardKind.values)
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..color = DistrictLook.of(kind).outline,
        ],
        _heartFills = [
          for (var seat = 0; seat < GamePalette.houses.length; seat++)
            Paint()..color = DistrictLook.heart(seat).colour,
        ],
        _heartOutlines = [
          for (var seat = 0; seat < GamePalette.houses.length; seat++)
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..color = DistrictLook.heart(seat).outline,
        ];

  final MatchController matches;

  /// The board icons, baked once. Owned by the game, whose teardown hands
  /// the texture back.
  final IconAtlas icons;

  /// The part of the world on screen, in world units.
  final Rect Function() visible;

  final double _tileSize;

  /// The rounded square filling a cell, at the origin.
  final Path _shape;

  final List<Paint> _districtFills;
  final List<Paint> _districtOutlines;
  final List<Paint> _heartFills;
  final List<Paint> _heartOutlines;

  final SpriteBatch _iconBatch = SpriteBatch();

  /// How much of a cell the icon takes up.
  static const double _iconExtent = 0.55;

  @override
  void render(Canvas canvas) {
    if (!icons.isReady) icons.initialize();
    final view = visible();
    for (final city in matches.state.cities) {
      _drawCell(
        canvas,
        view,
        city.heart,
        _heartFills[city.owner],
        _heartOutlines[city.owner],
        DistrictLook.heartSlot,
      );
      for (final entry in city.districts.entries) {
        _drawCell(
          canvas,
          view,
          entry.key,
          _districtFills[entry.value.index],
          _districtOutlines[entry.value.index],
          DistrictLook.slotOf(entry.value),
        );
      }
    }
    _iconBatch.flush(canvas, icons.image);
  }

  void _drawCell(Canvas canvas, Rect view, Cell cell, Paint fill, Paint outline,
      int slot) {
    final left = cell.x * _tileSize;
    final top = cell.y * _tileSize;
    if (left + _tileSize < view.left ||
        left > view.right ||
        top + _tileSize < view.top ||
        top > view.bottom) {
      return;
    }
    canvas.save();
    canvas.translate(left, top);
    canvas.drawPath(_shape, fill);
    canvas.drawPath(_shape, outline);
    canvas.restore();

    final source = icons.sourceRect(slot);
    if (source != null) {
      final extent = _iconExtent * _tileSize;
      _iconBatch.add(
        source: source,
        x: left + _tileSize / 2,
        y: top + _tileSize / 2,
        scale: extent / source.width,
        tint: GamePalette.cellIcon,
      );
    }
  }

  /// Hands the batch nothing to hold. Called from the game's own teardown.
  void dispose() => _iconBatch.clear();

  static Path _shapeFor(double tileSize) => Path()
    ..addRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(2, 2, tileSize - 4, tileSize - 4),
      Radius.circular(tileSize * 0.22),
    ));
}
