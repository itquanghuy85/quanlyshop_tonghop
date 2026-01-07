class LoggingService {
  static void log(String message) {
    print("[LOG] $message");
  }

  static void logError(String message, dynamic error) {
    print("[ERROR] $message: $error");
  }
}
