import 'dart:async';
import 'package:flutter/foundation.dart';

class EventBus {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final _ctrl = StreamController<String>.broadcast();
  final Map<String, int> _lastEmitAtMs = <String, int>{};
  static const Duration _dedupeWindow = Duration(milliseconds: 120);

  Stream<String> get stream => _ctrl.stream;

  void emit(String event) {
    final normalized = event.trim();
    if (normalized.isEmpty) return;

    _emitOne(normalized);

    // Bridge financial events for backward compatibility while migrating
    // listeners to EventBus.financialChanged.
    if (normalized == financialChanged) {
      _emitOne(financialActivityChanged);
    } else if (normalized == financialActivityChanged) {
      _emitOne(financialChanged);
    }
  }

  void emitRepairsChanged({bool financialImpact = false}) {
    emit(repairsChanged);
    if (financialImpact) {
      emit(financialChanged);
    }
  }

  void emitFinancialChanged() {
    emit(financialChanged);
  }

  void _emitOne(String event) {
    if (_ctrl.isClosed) return;

    if (_shouldDedupe(event)) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final last = _lastEmitAtMs[event];
      if (last != null && (now - last) < _dedupeWindow.inMilliseconds) {
        return;
      }
      _lastEmitAtMs[event] = now;
    }

    debugPrint('EventBus: Emitting event: $event');
    _ctrl.add(event);
  }

  bool _shouldDedupe(String event) {
    return event == repairsChanged ||
        event == financialChanged ||
        event == financialActivityChanged;
  }

  void dispose() { _ctrl.close(); }

  StreamSubscription<String> on(String event, void Function(String) callback) {
    return stream.where((e) => e == event).listen(callback);
  }

  void off(StreamSubscription<String> subscription) {
    subscription.cancel();
  }

  // ===== Event Constants =====
  static const String shopChanged = 'SHOP_CHANGED';
  static const String dataRefresh = 'DATA_REFRESH';
  static const String syncComplete = 'SYNC_COMPLETE';
  static const String repairsChanged = 'repairs_changed';
  static const String financialChanged = 'financial_changed';
  static const String financialActivityChanged = 'financial_activity_changed';
}
