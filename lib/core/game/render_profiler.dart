import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Profiles per-section timing (render and simulation) plus frame totals,
/// and logs a periodic summary.
class RenderProfiler {
  RenderProfiler._();
  static final instance = RenderProfiler._();

  /// Holds the most recent formatted log so the in-game debug panel can
  /// display it on devices without a console. Updated every log interval.
  final ValueNotifier<String?> lastLog = ValueNotifier<String?>(null);

  static const _logInterval = 5.0;

  /// When false, all profiling calls are no-ops and no log is emitted.
  /// Controlled by the debug status bar visibility.
  ///
  /// Read-only from outside: assigning it directly would skip the frame-timing
  /// hook and the window reset that [setEnabled] does either side of the
  /// change.
  bool get enabled => _enabled;
  bool _enabled = false;

  final _stopwatches = <String, Stopwatch>{};
  final _renderMicros = <String, int>{};
  final _simMicros = <String, int>{};
  int _frameCount = 0;
  double _logTimer = 0.0;

  /// Enables or disables profiling. Disabling resets accumulated state so a
  /// future enable starts from a clean window instead of dumping stale data.
  /// Also hooks/unhooks the Flutter frame-timings callback so we only pay
  /// the engine reporting cost while profiling is on.
  void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (value) {
      _frameTimingsCallback ??= _onFrameTimings;
      SchedulerBinding.instance.addTimingsCallback(_frameTimingsCallback!);
    } else {
      if (_frameTimingsCallback != null) {
        SchedulerBinding.instance.removeTimingsCallback(_frameTimingsCallback!);
      }
      _renderMicros.clear();
      _simMicros.clear();
      _totalCounts.clear();
      _visibleCounts.clear();
      _counters.clear();
      _frameTimingBuildMicros = 0;
      _frameTimingRasterMicros = 0;
      _frameTimingTotalMicros = 0;
      _frameTimingSamples = 0;
      _frameCount = 0;
      _logTimer = 0.0;
      lastLog.value = null;
    }
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!_enabled) return;
    for (final t in timings) {
      _frameTimingBuildMicros += t.buildDuration.inMicroseconds;
      _frameTimingRasterMicros += t.rasterDuration.inMicroseconds;
      _frameTimingTotalMicros += t.totalSpan.inMicroseconds;
      _frameTimingSamples++;
    }
  }

  // Context updated each frame.
  double _fps = 0;
  double _zoom = 0;
  double _cameraX = 0;
  double _cameraY = 0;
  double _viewportW = 0;
  double _viewportH = 0;

  // Frame-total timings (averages over the log interval).
  double _avgFrameTimeMs = 0;
  double _avgRenderWallMs = 0;
  double _avgFixedUpdateMs = 0;
  double _avgComponentUpdateMs = 0;

  // Total scene counts (snapshot from the last updateContext call).
  final Map<String, int> _totalCounts = {};

  // Visible counts reported by renderers (last frame's value per key).
  final Map<String, int> _visibleCounts = {};

  // Accumulating counters over the current log window.
  final Map<String, int> _counters = {};

  // Flutter FrameTiming callback bookkeeping. Delivered asynchronously in
  // batches by the engine — we accumulate and average across the log window.
  TimingsCallback? _frameTimingsCallback;
  int _frameTimingBuildMicros = 0;
  int _frameTimingRasterMicros = 0;
  int _frameTimingTotalMicros = 0;
  int _frameTimingSamples = 0;

  /// Reports how many items of [name] a renderer drew this frame.
  /// Called during render() — the last value per frame is kept.
  void setVisibleCount(String name, int value) {
    if (!_enabled) return;
    _visibleCounts[name] = value;
  }

  /// Accumulates an event counter over the current log window. Useful for
  /// "how often did X happen in the last 5s?" without wiring a full timer.
  void incrementCounter(String name, [int by = 1]) {
    if (!_enabled) return;
    _counters[name] = (_counters[name] ?? 0) + by;
  }

  /// Call at the start of a renderer's render method.
  void begin(String name) {
    if (!_enabled) return;
    final sw = _stopwatches.putIfAbsent(name, Stopwatch.new);
    sw.reset();
    sw.start();
  }

  /// Call at the end of a renderer's render method.
  void end(String name) {
    if (!_enabled) return;
    final sw = _stopwatches[name];
    if (sw == null || !sw.isRunning) return;
    sw.stop();
    _renderMicros[name] = (_renderMicros[name] ?? 0) + sw.elapsedMicroseconds;
  }

  /// Call at the start of a simulation section.
  void beginSim(String name) {
    if (!_enabled) return;
    final sw = _stopwatches.putIfAbsent('sim:$name', Stopwatch.new);
    sw.reset();
    sw.start();
  }

  /// Call at the end of a simulation section.
  void endSim(String name) {
    if (!_enabled) return;
    final sw = _stopwatches['sim:$name'];
    if (sw == null || !sw.isRunning) return;
    sw.stop();
    _simMicros[name] = (_simMicros[name] ?? 0) + sw.elapsedMicroseconds;
  }

  /// Adds raw microseconds to a render bucket directly. Use this to
  /// accumulate timing from hoisted stopwatches that wrap many small calls
  /// inside a tight render loop, where `begin`/`end` per iteration would
  /// dominate the measurement with map-lookup overhead.
  void addRenderMicros(String name, int micros) {
    if (!_enabled) return;
    if (micros <= 0) return;
    _renderMicros[name] = (_renderMicros[name] ?? 0) + micros;
  }

  /// For a hot loop that needs its own hoisted stopwatches, see
  /// `HoistedTimers` — it drains into [addRenderMicros] or [addSimMicros],
  /// with the bucket names supplied by whoever owns the loop.

  /// Adds raw microseconds to a simulation bucket directly. Use this to
  /// accumulate timing from hoisted stopwatches that wrap many small calls
  /// inside a tight loop, where `beginSim`/`endSim` per call would dominate
  /// the measurement with map-lookup overhead.
  void addSimMicros(String name, int micros) {
    if (!_enabled) return;
    if (micros <= 0) return;
    _simMicros[name] = (_simMicros[name] ?? 0) + micros;
  }

  /// Call once per frame (after all renderers have run).
  void endFrame() {
    if (!_enabled) return;
    _frameCount++;
  }

  /// Update context info and frame-total timings for the log output.
  void updateContext({
    required double fps,
    required double zoom,
    required Offset cameraPosition,
    required Size viewportSize,
    required double avgFrameTimeMs,
    required double avgRenderWallMs,
    required double avgFixedUpdateMs,
    required double avgComponentUpdateMs,
    Map<String, int>? counts,
  }) {
    if (!_enabled) return;
    _fps = fps;
    _zoom = zoom;
    _cameraX = cameraPosition.dx;
    _cameraY = cameraPosition.dy;
    _viewportW = viewportSize.width;
    _viewportH = viewportSize.height;
    _avgFrameTimeMs = avgFrameTimeMs;
    _avgRenderWallMs = avgRenderWallMs;
    _avgFixedUpdateMs = avgFixedUpdateMs;
    _avgComponentUpdateMs = avgComponentUpdateMs;
    if (counts != null) {
      _totalCounts
        ..clear()
        ..addAll(counts);
    }
  }

  /// Call every frame with delta time to trigger periodic logging.
  void update(double dt) {
    if (!_enabled) return;
    _logTimer += dt;
    if (_logTimer >= _logInterval) {
      _log();
      _logTimer = 0.0;
    }
  }

  /// Which build the numbers came out of. A debug build keeps `assert`
  /// bodies — a game's own consistency check can walk everything it owns from
  /// inside a simulation tick — and runs unoptimised JIT code, so a debug
  /// profile is not comparable with a profile-mode one and shouldn't be read
  /// as if it were.
  static String get _buildMode {
    if (kDebugMode) return 'debug build — asserts on, JIT';
    if (kProfileMode) return 'profile build';
    return 'release build';
  }

  void _log() {
    if (_frameCount == 0) return;

    final buf = StringBuffer()
      ..writeln()
      ..writeln('Performance (avg/frame, $_frameCount frames) [$_buildMode]:');
    buf.writeln('  FPS: ${_fps.toStringAsFixed(1)}  '
        'Zoom: ${_zoom.toStringAsFixed(2)}  '
        'Camera: (${_cameraX.toStringAsFixed(0)}, ${_cameraY.toStringAsFixed(0)})  '
        'Viewport: ${_viewportW.toStringAsFixed(0)}x${_viewportH.toStringAsFixed(0)}');

    if (_totalCounts.isNotEmpty) {
      final parts = _totalCounts.entries.map((e) {
        final visible = _visibleCounts[e.key];
        return visible != null
            ? '${e.value} ${e.key} ($visible visible)'
            : '${e.value} ${e.key}';
      }).join(', ');
      buf.writeln('  Scene: $parts');
    }

    // Per-frame counts a renderer reports with no world total to pair with —
    // batch sizes, pool occupancy. The Scene line above only shows keys that
    // have a total, so without this they never reach the log at all.
    final drawn = _visibleCounts.entries
        .where((e) => !_totalCounts.containsKey(e.key))
        .map((e) => '${e.value} ${e.key}')
        .join(', ');
    if (drawn.isNotEmpty) buf.writeln('  Drawn: $drawn');

    // Frame totals: frame time, render wall, fixed update, unaccounted.
    // Flutter's FrameTiming splits the frame into build (UI thread) and
    // raster (raster thread) phases. Together with totalSpan we can see
    // where the "Unaccounted" bucket really goes.
    final unaccounted = (_avgFrameTimeMs -
            _avgRenderWallMs -
            _avgFixedUpdateMs -
            _avgComponentUpdateMs)
        .clamp(0.0, double.infinity);
    buf.writeln();
    buf.writeln('  Frame totals:');
    buf.writeln(_row('Frame time', _avgFrameTimeMs));
    buf.writeln(_row('Render (wall)', _avgRenderWallMs));
    buf.writeln(_row('Fixed update', _avgFixedUpdateMs));
    buf.writeln(_row('Component update', _avgComponentUpdateMs));

    // Split the leftover into the raster thread's real work and the idle
    // stretch that follows it. Without the split, a game comfortably inside
    // its frame budget reads as if something expensive were hiding in the
    // gap: at a locked 120 Hz with 2.5 ms of work, nearly 6 ms of every
    // frame is the engine waiting for the next vsync, which is the opposite
    // of a problem.
    final rasterAvgMs = _frameTimingSamples > 0
        ? _frameTimingRasterMicros / _frameTimingSamples / 1000.0
        : 0.0;
    if (_frameTimingSamples > 0) {
      final rasterPart = rasterAvgMs < unaccounted ? rasterAvgMs : unaccounted;
      final idlePart = unaccounted - rasterPart;
      buf.writeln('${_row('Unaccounted', unaccounted).padRight(40)}  '
          '← ${rasterPart.toStringAsFixed(3)} raster + '
          '${idlePart.toStringAsFixed(3)} idle/vsync');
    } else {
      buf.writeln('${_row('Unaccounted', unaccounted).padRight(40)}'
          '  ← raster / GPU / vsync');
    }

    if (_frameTimingSamples > 0) {
      final buildMs = _frameTimingBuildMicros / _frameTimingSamples / 1000.0;
      final rasterMs = rasterAvgMs;
      final totalMs = _frameTimingTotalMicros / _frameTimingSamples / 1000.0;
      final vsyncWaitMs = (totalMs - (buildMs > rasterMs ? buildMs : rasterMs))
          .clamp(0.0, double.infinity);
      buf.writeln();
      buf.writeln('  Flutter FrameTiming ($_frameTimingSamples frames):');
      buf.writeln(_row('UI thread (build)', buildMs));
      buf.writeln(_row('Raster thread', rasterMs));
      buf.writeln(_row('Total span', totalMs));
      buf.writeln(
          '${_row('VSync wait (est.)', vsyncWaitMs).padRight(40)}  ← parallel slack');
    }

    // Render CPU section breakdown.
    if (_renderMicros.isNotEmpty) {
      final entries = _renderMicros.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      double totalMs = 0;
      buf.writeln();
      buf.writeln('  Render CPU (inside render()):');
      for (final e in entries) {
        final avgMs = (e.value / _frameCount) / 1000.0;
        // Sub-section timings ("Foo.bar") live inside a wrapping top-level
        // entry ("Foo") and would otherwise double-count into TOTAL.
        if (!e.key.contains('.')) {
          totalMs += avgMs;
        }
        buf.writeln(_row(e.key, avgMs, indent: 4));
      }
      buf.writeln('    ${'─' * 36}');
      buf.writeln(_row('TOTAL', totalMs, indent: 4));
    }

    // Event counters over the log window (e.g. snapshot rebuilds).
    if (_counters.isNotEmpty) {
      buf.writeln();
      buf.writeln('  Counters (this window):');
      final entries = _counters.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in entries) {
        buf.writeln(
            '    ${e.key.padRight(24)} ${e.value.toString().padLeft(8)}');
      }
    }

    // Simulation CPU section breakdown.
    if (_simMicros.isNotEmpty) {
      final entries = _simMicros.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      double totalMs = 0;
      buf.writeln();
      buf.writeln('  Simulation CPU (inside _fixedUpdate):');
      for (final e in entries) {
        final avgMs = (e.value / _frameCount) / 1000.0;
        // Sub-section timings ("Foo.bar") live inside a wrapping top-level
        // entry ("Foo") and would otherwise double-count into TOTAL.
        if (!e.key.contains('.')) {
          totalMs += avgMs;
        }
        buf.writeln(_row(e.key, avgMs, indent: 4));
      }
      buf.writeln('    ${'─' * 36}');
      buf.writeln(_row('TOTAL', totalMs, indent: 4));
    }

    final text = buf.toString();
    developer.log(text, name: 'RenderProfile');
    // ignore: avoid_print
    print(text);
    lastLog.value = text;

    _renderMicros.clear();
    _simMicros.clear();
    _counters.clear();
    _frameTimingBuildMicros = 0;
    _frameTimingRasterMicros = 0;
    _frameTimingTotalMicros = 0;
    _frameTimingSamples = 0;
    _frameCount = 0;
  }

  String _row(String name, double ms, {int indent = 2}) {
    final pad = ' ' * indent;
    return '$pad${name.padRight(24)} ${ms.toStringAsFixed(3).padLeft(8)} ms';
  }
}
