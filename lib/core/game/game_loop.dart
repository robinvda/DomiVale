/// A fixed-timestep simulation under a variable-rate render.
///
/// Every tick advances the world by exactly [fixedDeltaTime] whatever the
/// frame rate is doing, which is what makes a simulation reproducible: the
/// same ticks in the same order produce the same world on a phone dropping
/// frames as on a desktop at 120Hz.
///
/// The frame delta is capped before it is accumulated. Without the cap, a
/// frame the operating system took a second over asks for sixty ticks at
/// once, each of which makes the next frame later still — the spiral of death
/// a fixed timestep is otherwise prone to. Time past the cap is dropped, so a
/// stalled game comes back a little behind rather than never.
class GameLoop {
  GameLoop({
    this.tickRate = 60,
    required this.onFixedUpdate,
    this.onUpdate,
    this.minSpeedMultiplier = 0.5,
    this.maxSpeedMultiplier = 3.0,
  }) {
    fixedDeltaTime = 1.0 / tickRate;
  }

  /// Target simulation rate (ticks per second).
  final int tickRate;

  /// Fixed timestep in seconds.
  late final double fixedDeltaTime;

  /// Time that has arrived but not yet been spent on a whole tick.
  double _accumulator = 0.0;

  /// Ticks run since the last [reset].
  int _tickCount = 0;

  /// One simulation tick, always handed exactly [fixedDeltaTime].
  final void Function(double dt) onFixedUpdate;

  /// Once per frame with the real frame delta, for anything that should follow
  /// the frame rate rather than the tick rate. Called even while paused, so a
  /// paused game still animates.
  final void Function(double dt)? onUpdate;

  /// Whether the simulation is paused. Rendering carries on.
  bool isPaused = false;

  /// How fast the simulation runs relative to real time, clamped to
  /// [minSpeedMultiplier]..[maxSpeedMultiplier].
  ///
  /// The range is a constructor parameter because which speeds a game offers
  /// is its own balance decision; use [isPaused] to stop, not a multiplier of
  /// zero, so the accumulator isn't left half full.
  double get speedMultiplier => _speedMultiplier;
  double _speedMultiplier = 1.0;

  set speedMultiplier(double value) {
    _speedMultiplier = value.clamp(minSpeedMultiplier, maxSpeedMultiplier);
  }

  /// Slowest and fastest the simulation may be asked to run.
  final double minSpeedMultiplier;
  final double maxSpeedMultiplier;

  /// Advances the loop by one frame's [dt] in seconds: the variable update
  /// first, then as many whole simulation ticks as the accumulated time pays
  /// for.
  void update(double dt) {
    // Always call variable update for rendering (even when paused)
    onUpdate?.call(dt);

    // Don't process simulation when paused
    if (isPaused) return;

    // Cap dt to prevent spiral of death
    final cappedDt = dt > 0.25 ? 0.25 : dt;

    // Apply speed multiplier
    final scaledDt = cappedDt * _speedMultiplier;

    // Accumulate time
    _accumulator += scaledDt;

    // Process fixed timesteps
    while (_accumulator >= fixedDeltaTime) {
      onFixedUpdate(fixedDeltaTime);
      _accumulator -= fixedDeltaTime;
      _tickCount++;
    }
  }

  /// Ticks run since the last [reset].
  int get tickCount => _tickCount;

  /// How far the next tick already is, 0 to 1 — for a renderer interpolating
  /// between the last simulated state and the one coming.
  double get alpha => _accumulator / fixedDeltaTime;

  /// Drops the tick count and any part-spent time, for a game starting a new
  /// world.
  void reset() {
    _accumulator = 0.0;
    _tickCount = 0;
  }
}
