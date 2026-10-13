import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Tracks keyboard modifier state (just Shift for now) in our own notifier
/// so readers don't have to query [HardwareKeyboard].
///
/// Querying HardwareKeyboard directly is unreliable in practice: on macOS
/// the Meta key desyncs when it's held during an OS-level shortcut (the
/// key-up goes to whichever app grabs focus, not Flutter). The debug-mode
/// assertion then fires on the next Meta KeyDown, which aborts state
/// updates and can make `logicalKeysPressed` read as stale.
///
/// Install via [install] early (e.g. from GameScreen's initState). The
/// handler sits on HardwareKeyboard and sees every key event the engine
/// dispatches; since only Meta triggers the assertion, Shift events still
/// flow through cleanly and our notifier stays in sync.
class KeyboardModifiers {
  KeyboardModifiers._();

  static bool _installed = false;

  /// True while at least one Shift key is held. Read `.value` inside a
  /// tap handler; listen to it if you need reactive UI.
  static final ValueNotifier<bool> shiftHeld = ValueNotifier<bool>(false);

  /// Install the HardwareKeyboard handler. Safe to call more than once —
  /// subsequent calls are no-ops.
  static void install() {
    if (_installed) return;
    HardwareKeyboard.instance.addHandler(_handler);
    _installed = true;
  }

  /// Uninstall the handler. Pair with [install] from the same lifecycle.
  static void uninstall() {
    if (!_installed) return;
    HardwareKeyboard.instance.removeHandler(_handler);
    _installed = false;
  }

  /// Clear tracked state. Call on app focus loss so a key that was held
  /// when the app lost focus — and therefore never got a matching key-up —
  /// doesn't stay "held" forever.
  static void reset() {
    shiftHeld.value = false;
  }

  static bool _handler(KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      if (event is KeyDownEvent) {
        shiftHeld.value = true;
      } else if (event is KeyUpEvent) {
        shiftHeld.value = false;
      }
    }
    return false; // never consume; other handlers still get to run
  }
}
