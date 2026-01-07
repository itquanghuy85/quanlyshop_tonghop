import 'dart:async';
import 'dart:developer';

class EventBus {
  static final EventBus _instance = EventBus._internal();
  factory EventBus() => _instance;
  EventBus._internal();

  final _ctrl = StreamController<String>.broadcast();

  Stream<String> get stream => _ctrl.stream;
  void emit(String event) { 
    print('EventBus: Emitting event: $event');
    _ctrl.add(event); 
  }
  void dispose() { _ctrl.close(); }

  StreamSubscription<String> on(String event, void Function(String) callback) {
    return stream.where((e) => e == event).listen(callback);
  }

  void off(StreamSubscription<String> subscription) {
    subscription.cancel();
  }
}
