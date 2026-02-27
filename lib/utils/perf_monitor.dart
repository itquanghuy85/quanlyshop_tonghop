import 'package:flutter/foundation.dart';

/// Lightweight performance monitor for tracking operation timings.
/// Only logs in debug mode. No external dependencies.
class PerfMonitor {
  PerfMonitor._();

  static final Map<String, _PerfEntry> _entries = {};
  static final Map<String, List<int>> _history = {};
  static const int _maxHistory = 20;

  /// Start timing an operation. Returns a [Stopwatch] handle.
  static Stopwatch start(String label) {
    final sw = Stopwatch()..start();
    _entries[label] = _PerfEntry(label, sw);
    return sw;
  }

  /// Stop timing and log the result. Returns elapsed milliseconds.
  static int stop(String label) {
    final entry = _entries.remove(label);
    if (entry == null) return 0;
    entry.stopwatch.stop();
    final ms = entry.stopwatch.elapsedMilliseconds;

    // Store in rolling history
    _history.putIfAbsent(label, () => []);
    final list = _history[label]!;
    list.add(ms);
    if (list.length > _maxHistory) list.removeAt(0);

    // Only log if slow (>500ms) or in debug mode
    if (ms > 500) {
      debugPrint('⏱️ PERF [$label]: ${ms}ms (SLOW)');
    } else {
      debugPrint('⏱️ PERF [$label]: ${ms}ms');
    }
    return ms;
  }

  /// Get average time for a label (from history).
  static double getAverage(String label) {
    final list = _history[label];
    if (list == null || list.isEmpty) return 0;
    return list.reduce((a, b) => a + b) / list.length;
  }

  /// Log a summary of all tracked operations.
  static void printSummary() {
    if (_history.isEmpty) return;
    debugPrint('═══════════ PERF SUMMARY ═══════════');
    final sorted = _history.entries.toList()
      ..sort((a, b) {
        final avgA = a.value.reduce((x, y) => x + y) / a.value.length;
        final avgB = b.value.reduce((x, y) => x + y) / b.value.length;
        return avgB.compareTo(avgA); // Slowest first
      });
    for (final e in sorted) {
      final avg = e.value.reduce((a, b) => a + b) / e.value.length;
      final max = e.value.reduce((a, b) => a > b ? a : b);
      debugPrint(
        '  ${e.key}: avg=${avg.toStringAsFixed(0)}ms, '
        'max=${max}ms, samples=${e.value.length}',
      );
    }
    debugPrint('════════════════════════════════════');
  }
}

class _PerfEntry {
  final String label;
  final Stopwatch stopwatch;
  _PerfEntry(this.label, this.stopwatch);
}
