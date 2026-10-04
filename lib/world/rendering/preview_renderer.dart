import 'package:domivale_rules/domivale_rules.dart';
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'package:vale_engine/utils/grid_pos.dart';
import 'package:vale_engine/utils/radius_cell_path.dart';
import 'package:vale_engine/world/rendering/tile_preview_painter.dart';

import '../../game/input_controller.dart';
import '../../theme/game_palette.dart';

/// What the armed card would do: every cell it could go to, and on the cell
/// under the pointer the land it would claim and what it would yield.
///
/// Also the ring around a cell the player is holding to read. Nothing here
/// is built during a frame: [refresh] rebuilds the paths and the text when
/// the pointer, the card or the match changes.
class PreviewRenderer extends Component {
  PreviewRenderer({required this.input, required double tileSize})
      : _tileSize = tileSize,
        _painter = TilePreviewPainter(tileSize: tileSize);

  final InputController input;
  final double _tileSize;
  final TilePreviewPainter _painter;

  /// The offered cells as the engine's painter wants them.
  List<GridPos> _offered = const [];

  /// The cell under the pointer, or null.
  GridPos? _pointed;

  /// The land a card on the pointed cell would claim, outlined, or null.
  Path? _claim;
  final Paint _claimFill = Paint();
  final Paint _claimLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  /// What a district on the pointed cell would yield, or for an army what
  /// it brings against the target's defence; null when nothing is worth
  /// saying.
  TextPainter? _yield;

  /// The districts a capture on the pointed cell would cut off from their
  /// heart, each marked.
  final List<RRect> _abandoned = [];
  final Paint _abandonedLine = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..color = GamePalette.abandonedMark;

  /// The ring around the cell the player is reading, or null.
  RRect? _inspected;
  final Paint _inspectRing = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.4
    ..color = GamePalette.inspectRing;

  /// The armed card or the match changed.
  void refresh({Cell? pointed, Cell? inspected}) {
    _inspected = inspected == null
        ? null
        : RRect.fromRectAndRadius(
            Rect.fromLTWH(
              inspected.x * _tileSize - 1.5,
              inspected.y * _tileSize - 1.5,
              _tileSize + 3,
              _tileSize + 3,
            ),
            Radius.circular(_tileSize * 0.22 + 1.5),
          );
    _offered = [for (final c in input.offeredCells) GridPos(c.x, c.y)];
    _pointed = pointed == null ? null : GridPos(pointed.x, pointed.y);
    _claim = null;
    _yield?.dispose();
    _yield = null;
    _abandoned.clear();

    final kind = input.armedKind;
    if (pointed == null || kind == null) return;
    if (!input.offeredCells.contains(pointed)) return;

    final state = input.state;
    final seat = state.currentSeat;
    final colour = GamePalette.houses[seat];

    if (kind.isMilitary) {
      final outcome = state.attackOutcome(kind, pointed);
      if (outcome == null) return;
      _yield = _text(
        outcome.takes
            ? '${outcome.strength} › ${outcome.defence}'
            : '${outcome.strength} / ${outcome.defence}',
        outcome.takes ? GamePalette.previewText : GamePalette.previewWarn,
      );
      for (final cell in outcome.abandoned) {
        _abandoned.add(RRect.fromRectAndRadius(
          Rect.fromLTWH(
            cell.x * _tileSize + 2,
            cell.y * _tileSize + 2,
            _tileSize - 4,
            _tileSize - 4,
          ),
          Radius.circular(_tileSize * 0.22),
        ));
      }
      return;
    }
    final claimed = [
      for (final near in pointed.cellsWithinReach(Rules.claimReach))
        if (state.isUnclaimed(near)) (x: near.x, y: near.y, radius: 0),
    ];
    if (claimed.isNotEmpty) {
      _claim = buildRadiusCellPath(sources: claimed, tileSize: _tileSize);
      _claimFill.color = colour.withValues(alpha: GamePalette.claimPreviewWash);
      _claimLine.color = colour;
    }

    final good = kind.gathers;
    if (good != null) {
      var count = 0;
      for (final beside in pointed.touching) {
        if (!state.board.contains(beside)) continue;
        if (state.board.terrainAt(beside).yields != good) continue;
        if (state.isPlainTerritoryOf(beside, seat)) count++;
      }
      _yield = _text('+$count', GamePalette.previewText);
    }
  }

  TextPainter _text(String text, Color colour) => TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w800,
            fontSize: _tileSize * 0.38,
            color: colour,
            shadows: const [
              Shadow(color: GamePalette.previewTextShadow, blurRadius: 3),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

  @override
  void render(Canvas canvas) {
    final claim = _claim;
    if (claim != null) {
      canvas.drawPath(claim, _claimFill);
      canvas.drawPath(claim, _claimLine);
    }
    if (_offered.isNotEmpty) {
      _painter.drawOffered(canvas, _offered, pointingAt: _pointed);
    }
    final pointed = _pointed;
    final text = _yield;
    if (pointed != null && text != null) {
      text.paint(
        canvas,
        Offset(
          (pointed.x + 0.5) * _tileSize - text.width / 2,
          (pointed.y + 0.5) * _tileSize - text.height / 2,
        ),
      );
    }
    for (final mark in _abandoned) {
      canvas.drawRRect(mark, _abandonedLine);
    }
    final inspected = _inspected;
    if (inspected != null) canvas.drawRRect(inspected, _inspectRing);
  }

  void dispose() {
    _yield?.dispose();
    _yield = null;
  }
}
