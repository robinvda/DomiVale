import 'dart:ui';

import 'package:domivale_rules/domivale_rules.dart';
import 'package:flame/components.dart';
import 'package:vale_engine/world/rendering/icon_atlas.dart';
import 'package:vale_engine/world/rendering/sprite_batch.dart';

import '../../game/match_controller.dart';
import '../../theme/district_look.dart';
import '../../theme/game_palette.dart';

/// The good each plain land cell yields, as a faint glyph on the cell.
///
/// At fit zoom the board is read by colour and shape, so the glyphs are
/// drawn only once the camera is close enough for them to be more than
/// noise, or on the cells an armed card offers, where the player is about to
/// count them.
class YieldRenderer extends Component {
  YieldRenderer({
    required this.matches,
    required this.icons,
    required double tileSize,
    required this.visible,
    required this.zoom,
    required this.offered,
  }) : _tileSize = tileSize;

  final MatchController matches;
  final IconAtlas icons;
  final Rect Function() visible;
  final double Function() zoom;

  /// The cells an armed card offers, or empty.
  final List<Cell> Function() offered;

  final double _tileSize;
  final SpriteBatch _batch = SpriteBatch();

  /// Logical pixels per cell at which the glyphs appear everywhere.
  static const double showAtPixelsPerCell = 26.0;

  /// How much of a cell the glyph takes up.
  static const double _extent = 0.42;

  @override
  void render(Canvas canvas) {
    if (!icons.isReady) icons.initialize();
    final everywhere = zoom() * _tileSize >= showAtPixelsPerCell;
    final cells = offered();
    if (!everywhere && cells.isEmpty) return;

    final state = matches.state;
    final board = state.board;
    if (everywhere) {
      final view = visible();
      final left = (view.left / _tileSize).floor().clamp(0, board.size - 1);
      final right = (view.right / _tileSize).ceil().clamp(0, board.size - 1);
      final top = (view.top / _tileSize).floor().clamp(0, board.size - 1);
      final bottom = (view.bottom / _tileSize).ceil().clamp(0, board.size - 1);
      for (var y = top; y <= bottom; y++) {
        for (var x = left; x <= right; x++) {
          _add(state, Cell(x, y));
        }
      }
    } else {
      for (final cell in cells) {
        _add(state, cell);
      }
    }
    _batch.flush(canvas, icons.image);
  }

  void _add(MatchState state, Cell cell) {
    final good = state.board.terrainAt(cell).yields;
    if (good == null || state.isCityCell(cell)) return;
    final source = icons.sourceRect(DistrictLook.goodSlot(good));
    if (source == null) return;
    _batch.add(
      source: source,
      x: (cell.x + 0.5) * _tileSize,
      y: (cell.y + 0.5) * _tileSize,
      scale: _extent * _tileSize / source.width,
      tint: GamePalette.yieldIcon,
    );
  }

  void dispose() => _batch.clear();
}
