import 'dart:ui';

import 'package:vale_engine/world/rendering/terrain_renderer.dart';

import '../../game/render_profiler.dart';

/// The terrain as `vale_engine` draws it, timed and counted by the profiler.
///
/// The frame's terrain time shows as its own row, and every chunk rasterized
/// is counted as `terrain.chunkRasterized`: a chunk should be rasterized once
/// and then blitted for as long as it stays in view, so a steady count means
/// the cache is evicting chunks the next frame needs.
class ProfiledTerrainRenderer extends TerrainRenderer {
  ProfiledTerrainRenderer({
    required super.generator,
    required super.tileSize,
    super.isChunkHidden,
  }) : super(onChunkRasterized: _countRasterized);

  static void _countRasterized() =>
      RenderProfiler.instance.incrementCounter('terrain.chunkRasterized');

  @override
  void render(Canvas canvas) {
    RenderProfiler.instance.begin('Terrain');
    try {
      super.render(canvas);
    } finally {
      RenderProfiler.instance.end('Terrain');
    }
  }
}
