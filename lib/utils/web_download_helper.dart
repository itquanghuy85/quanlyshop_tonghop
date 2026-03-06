/// Web download helper - stub for non-web platforms.
/// On web, the real implementation is in web_download_helper_web.dart.
Future<void> downloadFileWeb(List<int> bytes, String fileName) async {
  // No-op on non-web platforms
  throw UnsupportedError('downloadFileWeb is only supported on web');
}
