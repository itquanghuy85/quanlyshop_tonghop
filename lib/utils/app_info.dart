import 'package:package_info_plus/package_info_plus.dart';

/// Lấy thông tin app từ metadata (tự đồng bộ theo pubspec.yaml khi build).
class AppInfo {
  static PackageInfo? _packageInfo;

  static Future<PackageInfo> _getPackageInfo() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!;
  }

  /// Trả về version từ pubspec.yaml (VD: "10.0.12")
  static Future<String> getVersion() async {
    final info = await _getPackageInfo();
    return info.version;
  }

  /// Trả về build number từ pubspec.yaml (VD: "168")
  static Future<String> getBuildNumber() async {
    final info = await _getPackageInfo();
    return info.buildNumber;
  }

  /// Trả về tên app
  static Future<String> getAppName() async {
    final info = await _getPackageInfo();
    return info.appName;
  }

  /// Trả về package name (VD: "com.huluca.shopmanager")
  static Future<String> getPackageName() async {
    final info = await _getPackageInfo();
    return info.packageName;
  }
}