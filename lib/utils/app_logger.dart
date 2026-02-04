// Production-safe logging utility
// Only logs in debug mode, completely silent in release builds
//
// Usage: Replace debugPrint() with AppLogger.d() for production builds
// AppLogger automatically strips logs in release mode

import 'package:flutter/foundation.dart';

/// Production-safe logger that only logs in debug mode
class AppLogger {
  static bool _enabled = !kReleaseMode;

  /// Enable/disable logging (useful for debugging production issues)
  static void setEnabled(bool enabled) {
    _enabled = enabled && !kReleaseMode;
  }

  /// Debug log - only in debug mode
  static void d(String message, {String? tag}) {
    if (_enabled) {
      final prefix = tag != null ? '[$tag] ' : '';
      debugPrint('$prefix$message');
    }
  }

  /// Info log - only in debug mode
  static void i(String message, {String? tag}) {
    if (_enabled) {
      final prefix = tag != null ? '[$tag] ' : '';
      debugPrint('ℹ️ $prefix$message');
    }
  }

  /// Warning log - only in debug mode
  static void w(String message, {String? tag}) {
    if (_enabled) {
      final prefix = tag != null ? '[$tag] ' : '';
      debugPrint('⚠️ $prefix$message');
    }
  }

  /// Error log - always logged (for crash reporting)
  static void e(String message, {String? tag, Object? error, StackTrace? stackTrace}) {
    final prefix = tag != null ? '[$tag] ' : '';
    // Always log errors, even in release (for crash reporting services)
    debugPrint('❌ $prefix$message');
    if (error != null) {
      debugPrint('Error: $error');
    }
    if (stackTrace != null && !kReleaseMode) {
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Performance marker - only in debug mode
  static void perf(String operation, Duration duration, {String? tag}) {
    if (_enabled) {
      final prefix = tag != null ? '[$tag] ' : '';
      final ms = duration.inMilliseconds;
      final emoji = ms > 1000 ? '🐢' : ms > 500 ? '🐇' : '⚡';
      debugPrint('$emoji $prefix$operation: ${ms}ms');
    }
  }

  /// Sync log - only in debug mode
  static void sync(String message) {
    d(message, tag: 'SYNC');
  }

  /// Database log - only in debug mode
  static void db(String message) {
    d(message, tag: 'DB');
  }

  /// Network log - only in debug mode
  static void net(String message) {
    d(message, tag: 'NET');
  }

  /// UI log - only in debug mode
  static void ui(String message) {
    d(message, tag: 'UI');
  }
}

/// Extension to measure execution time
extension PerformanceExtension<T> on Future<T> {
  Future<T> logPerformance(String operation, {String? tag}) async {
    if (kReleaseMode) return this;
    
    final stopwatch = Stopwatch()..start();
    try {
      final result = await this;
      stopwatch.stop();
      AppLogger.perf(operation, stopwatch.elapsed, tag: tag);
      return result;
    } catch (e) {
      stopwatch.stop();
      AppLogger.e('$operation failed after ${stopwatch.elapsedMilliseconds}ms', 
        tag: tag, error: e);
      rethrow;
    }
  }
}
