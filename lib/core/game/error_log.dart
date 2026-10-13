import 'package:flutter/foundation.dart';

/// One captured runtime error, with a repeat count so a fault that throws on
/// every frame collapses into a single entry instead of flooding the list.
class CapturedError {
  CapturedError({
    required this.label,
    required this.signature,
    required this.message,
    required this.stack,
    required this.firstSeen,
  });

  /// Sub-system tag the error was recorded under (e.g. `fixedUpdate`,
  /// `render`, `flutter`, `platform`).
  final String label;

  /// Coalescing key: same label + message + stack head counts as a repeat.
  final String signature;

  /// `error.toString()` of the most recent occurrence.
  String message;

  /// Full stack trace string (empty when none was supplied).
  final String stack;

  /// Wall-clock time of the first occurrence, formatted `HH:MM:SS`.
  final String firstSeen;

  /// Number of times this signature has fired.
  int count = 1;
}

/// In-app sink for runtime errors so they can be read on a device with no
/// console attached (the Debug Tools → Errors dialog renders [entries]).
///
/// Wired up in `main()` (global Flutter / platform handlers) and around the
/// game's per-frame `_fixedUpdate` / `render` (which also swallow the throw so
/// a single faulty sub-system degrades to a logged glitch instead of freezing
/// the whole canvas). Mirrors the [ValueListenable] shape of
/// `RenderProfiler.lastLog` so the dialog can listen the same way.
class ErrorLog {
  ErrorLog._();

  /// Singleton instance.
  static final ErrorLog instance = ErrorLog._();

  /// Keep at most this many distinct signatures; oldest are dropped.
  static const int _maxEntries = 40;

  /// Newest-first list of captured errors. Reassigned (never mutated in
  /// place) so [ValueListenable] notifies its listeners.
  final ValueNotifier<List<CapturedError>> entries =
      ValueNotifier<List<CapturedError>>(<CapturedError>[]);

  /// Total errors recorded since launch (including coalesced repeats).
  int get totalCount => entries.value.fold(0, (sum, e) => sum + e.count);

  /// Records an error under [label]. Consecutive identical faults (same label,
  /// message, and stack head) are coalesced into one entry with an incremented
  /// [CapturedError.count]; new signatures are inserted at the front.
  void record(String label, Object error, StackTrace? stack) {
    final message = error.toString();
    final stackStr = stack?.toString() ?? '';
    final signature = '$label|$message|${_stackHead(stackStr)}';

    final current = entries.value;
    for (final e in current) {
      if (e.signature == signature) {
        e.count++;
        e.message = message;
        entries.value = List<CapturedError>.of(current);
        return;
      }
    }

    final entry = CapturedError(
      label: label,
      signature: signature,
      message: message,
      stack: stackStr,
      firstSeen: _timestamp(),
    );
    final next = <CapturedError>[entry, ...current];
    if (next.length > _maxEntries) {
      next.removeRange(_maxEntries, next.length);
    }
    entries.value = next;
  }

  /// Drops every recorded error.
  void clear() {
    if (entries.value.isNotEmpty) {
      entries.value = <CapturedError>[];
    }
  }

  /// One copy-paste blob of every entry — used by the dialog's copy button.
  String formatAll() {
    final buffer = StringBuffer();
    for (final e in entries.value) {
      buffer.writeln('[${e.label}] x${e.count}  (first ${e.firstSeen})');
      buffer.writeln(e.message);
      if (e.stack.isNotEmpty) {
        buffer.writeln(e.stack.trimRight());
      }
      buffer.writeln('----------------------------------------');
    }
    return buffer.toString();
  }

  /// First few stack frames — enough to distinguish faults without making the
  /// coalescing key depend on volatile late-frame detail.
  static String _stackHead(String stack) {
    if (stack.isEmpty) return '';
    return stack.split('\n').take(3).join('\n');
  }

  static String _timestamp() {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }
}
