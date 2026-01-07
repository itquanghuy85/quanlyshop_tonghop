import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../services/user_service.dart';
import 'sync_service.dart';

class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  static ConnectivityService get instance => _instance;

  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  List<ConnectivityResult> _currentStatus = [];
  bool _isOnline = false;

  /// Khởi tạo theo dõi kết nối
  Future<void> initialize() async {
    // Kiểm tra trạng thái ban đầu
    _currentStatus = await _connectivity.checkConnectivity();
    _updateOnlineStatus(_currentStatus);

    // Lắng nghe thay đổi kết nối
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (error) {
        debugPrint('Lỗi theo dõi kết nối: $error');
      },
    );

    debugPrint('ConnectivityService initialized. Current status: $_currentStatus');
  }

  /// Hủy theo dõi kết nối
  Future<void> dispose() async {
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  /// Kiểm tra trạng thái online
  bool get isOnline => _isOnline;

  /// Lấy trạng thái kết nối hiện tại
  List<ConnectivityResult> get currentStatus => _currentStatus;

  /// Xử lý khi trạng thái kết nối thay đổi
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    debugPrint('Connectivity changed: $_currentStatus -> $results');
    _currentStatus = results;
    _updateOnlineStatus(results);

    if (_isOnline) {
      // Có mạng trở lại, thực hiện sync
      _onNetworkRestored();
    } else {
      // Mất mạng
      _onNetworkLost();
    }
  }

  /// Cập nhật trạng thái online
  void _updateOnlineStatus(List<ConnectivityResult> results) {
    final wasOnline = _isOnline;
    _isOnline = !results.contains(ConnectivityResult.none);

    if (wasOnline != _isOnline) {
      debugPrint('Online status changed: $_isOnline');
    }
  }

  /// Xử lý khi có mạng trở lại
  Future<void> _onNetworkRestored() async {
    debugPrint('Mạng đã được khôi phục, bắt đầu đồng bộ...');

    try {
      // Đợi một chút để đảm bảo kết nối ổn định
      await Future.delayed(const Duration(seconds: 2));

      // Kiểm tra user đã đăng nhập
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('Không có user đăng nhập, bỏ qua sync');
        return;
      }

      // Kiểm tra shopId
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) {
        debugPrint('Không có shopId, bỏ qua sync');
        return;
      }

      // Thực hiện đồng bộ dữ liệu
      await SyncService.syncAllToCloud();
      await SyncService.downloadAllFromCloud();

      debugPrint('Đồng bộ sau khi khôi phục mạng hoàn thành');
    } catch (e) {
      debugPrint('Lỗi đồng bộ sau khi khôi phục mạng: $e');
    }
  }

  /// Xử lý khi mất mạng
  void _onNetworkLost() {
    debugPrint('Mất kết nối mạng, chuyển sang chế độ offline');
    // Có thể hiển thị thông báo cho user hoặc lưu trạng thái
  }

  /// Thực hiện đồng bộ thủ công (khi user yêu cầu)
  Future<void> manualSync() async {
    if (!_isOnline) {
      throw Exception('Không có kết nối mạng. Vui lòng kiểm tra kết nối internet.');
    }

    try {
      debugPrint('Bắt đầu đồng bộ thủ công...');
      await SyncService.syncAllToCloud();
      await SyncService.downloadAllFromCloud();
      debugPrint('Đồng bộ thủ công hoàn thành');
    } catch (e) {
      debugPrint('Lỗi đồng bộ thủ công: $e');
      rethrow;
    }
  }

  /// Kiểm tra kết nối và thử kết nối lại
  Future<bool> testConnection() async {
    if (_currentStatus.contains(ConnectivityResult.none)) {
      return false;
    }

    try {
      // Thử ping Firebase để kiểm tra kết nối thực sự
      await SyncService.syncAllToCloud();
      return true;
    } catch (e) {
      debugPrint('Kết nối mạng không ổn định: $e');
      return false;
    }
  }
}
