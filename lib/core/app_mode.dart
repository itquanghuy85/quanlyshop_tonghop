import 'package:shared_preferences/shared_preferences.dart';

/// Quản lý chế độ hoạt động của ứng dụng: Offline (miễn phí) hoặc Online (trả phí).
class AppMode {
  static const String _offlineKey = 'app_mode_offline';
  static const String _chosenKey = 'app_mode_chosen';

  /// [true] = chế độ offline (miễn phí), [false] = chế độ online (trả phí).
  static bool isOfflineMode = false;

  /// ShopId ảo dùng cho người dùng offline.
  static const String offlineShopId = 'offline_local';

  /// UserId ảo dùng cho người dùng offline.
  static const String offlineUserId = 'offline_user';

  /// Tải trạng thái đã lưu từ SharedPreferences khi khởi động app.
  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    isOfflineMode = prefs.getBool(_offlineKey) ?? false;
  }

  /// Kiểm tra người dùng đã chọn chế độ chưa (dùng để quyết định có hiển thị
  /// màn hình chọn chế độ hay không).
  static Future<bool> hasChosen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_chosenKey) ?? false;
  }

  /// Lưu lựa chọn chế độ offline.
  static Future<void> setOfflineMode(bool value) async {
    isOfflineMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineKey, value);
    await prefs.setBool(_chosenKey, true);
  }

  /// Nâng cấp từ offline lên online: xóa cờ offline và chuyển sang chế độ online.
  static Future<void> upgradeToOnline() async {
    isOfflineMode = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_offlineKey, false);
    await prefs.setBool(_chosenKey, true);
  }
}
