import 'package:flutter/foundation.dart';

/// Things a game can be asked to draw or do while it is being debugged.
///
/// Deliberately named for what they show rather than for what a particular
/// game shows: [groundFeatures] is whatever that game puts on the ground.
enum DebugMode {
  none,
  height,
  biome,

  /// Whatever the game scatters on the ground, drawn over the terrain.
  groundFeatures,
  chunkBorders,
  showFps,
  showStatusBar,
  godMode,

  /// Player actions complete the moment they are ordered.
  instantActions,
}

/// Controller for debug visualization state.
class DebugController extends ChangeNotifier {
  final Set<DebugMode> _activeModes = {};

  /// Gets all active debug modes.
  Set<DebugMode> get activeModes => Set.unmodifiable(_activeModes);

  /// Checks if a specific debug mode is active.
  bool isActive(DebugMode mode) => _activeModes.contains(mode);

  /// Toggles a debug mode on/off.
  void toggle(DebugMode mode) {
    if (_activeModes.contains(mode)) {
      _activeModes.remove(mode);
    } else {
      _activeModes.add(mode);
    }
    notifyListeners();
  }

  /// Enables a debug mode.
  void enable(DebugMode mode) {
    if (!_activeModes.contains(mode)) {
      _activeModes.add(mode);
      notifyListeners();
    }
  }

  /// Disables a debug mode.
  void disable(DebugMode mode) {
    if (_activeModes.contains(mode)) {
      _activeModes.remove(mode);
      notifyListeners();
    }
  }

  /// Clears all debug modes.
  void clear() {
    if (_activeModes.isNotEmpty) {
      _activeModes.clear();
      notifyListeners();
    }
  }
}
