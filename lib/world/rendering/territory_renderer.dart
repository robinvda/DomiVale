import 'dart:ui';

import 'package:flame/components.dart';
import 'package:vale_engine/utils/radius_cell_path.dart';

import '../../game/match_controller.dart';
import '../../theme/game_palette.dart';

/// Every house's land: a soft wash of its colour over the cells it owns and
/// a stronger line along the border.
///
/// The border is the engine's radius path called with radius 0 on every
/// owned cell, which outlines exactly that set with rounded corners - the
/// same path the claim previews are drawn with. Paths are rebuilt by
/// [refresh] when the match changes, never per frame.
class TerritoryRenderer extends Component {
  TerritoryRenderer({required this.matches, required double tileSize})
      : _tileSize = tileSize,
        _fills = [
          for (final colour in GamePalette.houses)
            Paint()
              ..color = colour.withValues(alpha: GamePalette.territoryWash),
        ],
        _borders = [
          for (final colour in GamePalette.houses)
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0
              ..strokeJoin = StrokeJoin.round
              ..color = colour.withValues(alpha: GamePalette.borderStrength),
        ];

  final MatchController matches;
  final double _tileSize;

  final List<Paint> _fills;
  final List<Paint> _borders;

  /// One path per seat, or null for a seat with no land.
  final List<Path?> _paths = List.filled(GamePalette.houses.length, null);

  /// Rebuilds every border from the state as it stands.
  void refresh() {
    final state = matches.state;
    for (var seat = 0; seat < _paths.length; seat++) {
      if (seat >= state.houses.length) {
        _paths[seat] = null;
        continue;
      }
      final sources = [
        for (final cell in state.cellsOf(seat))
          (x: cell.x, y: cell.y, radius: 0),
      ];
      _paths[seat] = sources.isEmpty
          ? null
          : buildRadiusCellPath(sources: sources, tileSize: _tileSize);
    }
  }

  @override
  void render(Canvas canvas) {
    for (var seat = 0; seat < _paths.length; seat++) {
      final path = _paths[seat];
      if (path == null) continue;
      canvas.drawPath(path, _fills[seat]);
      canvas.drawPath(path, _borders[seat]);
    }
  }
}
