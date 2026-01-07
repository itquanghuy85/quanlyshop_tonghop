typedef StopSyncHandler = Future<void> Function();

StopSyncHandler? _stopHandler;

void registerStopSyncHandler(StopSyncHandler handler) {
  _stopHandler = handler;
}

Future<void> callStopSyncHandler() async {
  if (_stopHandler != null) {
    try {
      await _stopHandler!();
    } catch (_) {}
  }
}
