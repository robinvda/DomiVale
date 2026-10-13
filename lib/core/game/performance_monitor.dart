import 'dart:collection';

/// Tracks performance metrics for adaptive quality and UI display.
class PerformanceMonitor {
  PerformanceMonitor({this.sampleSize = 60});

  /// Number of samples to keep for rolling averages.
  final int sampleSize;

  // Frame time tracking
  final Queue<double> _frameTimes = Queue();
  double _frameTimeAccumulator = 0.0;

  // Render time tracking
  final Queue<double> _renderTimes = Queue();
  double _renderTimeAccumulator = 0.0;

  // Fixed update tracking. Samples are per-frame totals so they compare
  // apples-to-apples with frame time and render time. A single frame may
  // contain 0-N fixed ticks; each tick accumulates into [_pendingFrameMs]
  // and the accumulated value is committed once per frame via [commitFrame].
  final Queue<double> _fixedUpdateTimes = Queue();
  double _fixedUpdateAccumulator = 0.0;
  double _pendingFrameFixedUpdateMs = 0.0;

  // Flame component update tracking — the `super.update` pass over every
  // component, which is neither render nor fixed-update work and so used to
  // land in the "Unaccounted" bucket alongside raster and vsync. Separated so
  // that bucket means what its label says.
  final Queue<double> _componentUpdateTimes = Queue();
  double _componentUpdateAccumulator = 0.0;

  // Stopwatch for timing operations
  final Stopwatch _stopwatch = Stopwatch();

  /// Its own stopwatch: the component pass encloses no render or fixed-update
  /// timing, but sharing one instance would still have them reset it.
  final Stopwatch _componentStopwatch = Stopwatch();

  /// Call before Flame's component update pass.
  void beginComponentUpdate() {
    _componentStopwatch.reset();
    _componentStopwatch.start();
  }

  /// Call after Flame's component update pass.
  void endComponentUpdate() {
    _componentStopwatch.stop();
    _componentUpdateAccumulator = _addSample(
      _componentUpdateTimes,
      _componentStopwatch.elapsedMicroseconds / 1000.0,
      _componentUpdateAccumulator,
    );
  }

  /// Records the actual frame time from the game loop's delta time.
  void recordFrameTime(double dt) {
    final frameTimeMs = dt * 1000.0;
    _frameTimeAccumulator =
        _addSample(_frameTimes, frameTimeMs, _frameTimeAccumulator);
  }

  /// Call before render starts.
  void beginRender() {
    _stopwatch.reset();
    _stopwatch.start();
  }

  /// Call after render completes.
  void endRender() {
    _stopwatch.stop();
    final renderTime = _stopwatch.elapsedMicroseconds / 1000.0;
    _renderTimeAccumulator =
        _addSample(_renderTimes, renderTime, _renderTimeAccumulator);
  }

  /// Call before fixed update starts.
  void beginFixedUpdate() {
    _stopwatch.reset();
    _stopwatch.start();
  }

  /// Call after fixed update completes. Accumulates into the current
  /// frame's pending total; call [commitFrame] once per frame to sample it.
  void endFixedUpdate() {
    _stopwatch.stop();
    _pendingFrameFixedUpdateMs += _stopwatch.elapsedMicroseconds / 1000.0;
  }

  /// Flushes the per-frame fixed-update total into the rolling sample set.
  /// Must be called once per frame (even when 0 ticks ran) so the average
  /// reflects ms-per-frame rather than ms-per-tick.
  void commitFrame() {
    _fixedUpdateAccumulator = _addSample(
        _fixedUpdateTimes, _pendingFrameFixedUpdateMs, _fixedUpdateAccumulator);
    _pendingFrameFixedUpdateMs = 0.0;
  }

  double _addSample(Queue<double> queue, double value, double accumulator) {
    var acc = accumulator + value;
    queue.addLast(value);
    if (queue.length > sampleSize) {
      acc -= queue.removeFirst();
    }
    return acc;
  }

  double _average(Queue<double> queue, double accumulator) {
    if (queue.isEmpty) return 0.0;
    return accumulator / queue.length;
  }

  /// Get current metrics (for UI display and adaptive quality).
  Map<String, dynamic> get currentMetrics {
    final avgFrameTime = _average(_frameTimes, _frameTimeAccumulator);
    return {
      'fps': avgFrameTime > 0 ? 1000.0 / avgFrameTime : 0.0,
      'avgFrameTime': avgFrameTime,
      'avgRenderTime': _average(_renderTimes, _renderTimeAccumulator),
      'avgFixedUpdateTime':
          _average(_fixedUpdateTimes, _fixedUpdateAccumulator),
      'avgComponentUpdateTime':
          _average(_componentUpdateTimes, _componentUpdateAccumulator),
    };
  }
}
