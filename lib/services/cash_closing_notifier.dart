import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import 'user_service.dart';
import 'notification_service.dart';
import 'event_bus.dart';

/// Service quản lý realtime sync cho trạng thái chốt quỹ
/// 
/// Khi admin chốt quỹ trên thiết bị A, tất cả thiết bị khác sẽ:
/// 1. Nhận notification realtime
/// 2. Block các giao dịch cho ngày đã chốt
/// 3. Cập nhật UI tương ứng
class CashClosingNotifier {
  static CashClosingNotifier? _instance;
  static CashClosingNotifier get instance => _instance ??= CashClosingNotifier._();
  
  CashClosingNotifier._();
  
  StreamSubscription<QuerySnapshot>? _subscription;
  final _db = FirebaseFirestore.instance;
  final _localDb = DBHelper();
  
  /// Trạng thái chốt quỹ hiện tại
  bool _isTodayLocked = false;
  bool get isTodayLocked => _isTodayLocked;
  
  String? _lockedBy;
  String? get lockedBy => _lockedBy;
  
  DateTime? _lockedAt;
  DateTime? get lockedAt => _lockedAt;
  
  /// Callback khi trạng thái thay đổi
  final List<VoidCallback> _listeners = [];
  
  /// Khởi tạo realtime listener
  Future<void> init() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      debugPrint('CashClosingNotifier: No shopId, skipping init');
      return;
    }
    
    // Cancel existing subscription
    await _subscription?.cancel();
    
    // Listen to cash_closings collection for this shop
    _subscription = _db
        .collection('cash_closings')
        .where('shopId', isEqualTo: shopId)
        .orderBy('createdAt', descending: true)
        .limit(7) // Last 7 days
        .snapshots()
        .listen(_onClosingChanged, onError: (e) {
      debugPrint('CashClosingNotifier error: $e');
    });
    
    debugPrint('CashClosingNotifier: Initialized for shop $shopId');
  }
  
  /// Xử lý khi có thay đổi từ Firestore
  void _onClosingChanged(QuerySnapshot snapshot) async {
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    for (var change in snapshot.docChanges) {
      final data = change.doc.data() as Map<String, dynamic>?;
      if (data == null) continue;
      
      final dateKey = data['dateKey'] as String?;
      final isLocked = data['isLocked'] == true || data['isLocked'] == 1;
      final lockedBy = data['lockedBy'] as String?;
      final lockedAtRaw = data['lockedAt'];
      
      // Parse lockedAt
      DateTime? lockedAt;
      if (lockedAtRaw is Timestamp) {
        lockedAt = lockedAtRaw.toDate();
      } else if (lockedAtRaw is int) {
        lockedAt = DateTime.fromMillisecondsSinceEpoch(lockedAtRaw);
      }
      
      // Chỉ notify khi là ngày hôm nay
      if (dateKey == todayKey) {
        final wasLocked = _isTodayLocked;
        _isTodayLocked = isLocked;
        _lockedBy = lockedBy;
        _lockedAt = lockedAt;
        
        // Sync to local DB
        await _syncToLocalDb(dateKey ?? '', data);
        
        // Notify nếu trạng thái thay đổi
        if (wasLocked != isLocked) {
          _notifyListeners();
          _showNotification(isLocked, lockedBy);
          EventBus().emit('cash_closing_changed');
        }
      } else if (change.type == DocumentChangeType.added || change.type == DocumentChangeType.modified) {
        // Sync các ngày khác vào local DB
        if (dateKey != null) {
          await _syncToLocalDb(dateKey, data);
        }
      }
    }
  }
  
  /// Sync dữ liệu từ cloud vào local DB
  Future<void> _syncToLocalDb(String dateKey, Map<String, dynamic> data) async {
    try {
      final dbRaw = await _localDb.database;
      
      // Check if exists
      final existing = await dbRaw.query(
        'cash_closings',
        where: 'dateKey = ?',
        whereArgs: [dateKey],
      );
      
      final updateData = {
        'dateKey': dateKey,
        'isLocked': data['isLocked'] == true || data['isLocked'] == 1 ? 1 : 0,
        'lockedBy': data['lockedBy'],
        'lockedAt': data['lockedAt'] is Timestamp 
            ? (data['lockedAt'] as Timestamp).millisecondsSinceEpoch 
            : data['lockedAt'],
        'unlockedBy': data['unlockedBy'],
        'unlockedAt': data['unlockedAt'] is Timestamp 
            ? (data['unlockedAt'] as Timestamp).millisecondsSinceEpoch 
            : data['unlockedAt'],
        'cashStart': data['cashStart'] ?? 0,
        'bankStart': data['bankStart'] ?? 0,
        'cashEnd': data['cashEnd'] ?? 0,
        'bankEnd': data['bankEnd'] ?? 0,
        'expectedCashDelta': data['expectedCashDelta'] ?? 0,
        'expectedBankDelta': data['expectedBankDelta'] ?? 0,
        'note': data['note'],
      };
      
      if (existing.isEmpty) {
        updateData['createdAt'] = DateTime.now().millisecondsSinceEpoch;
        await dbRaw.insert('cash_closings', updateData);
      } else {
        await dbRaw.update(
          'cash_closings',
          updateData,
          where: 'dateKey = ?',
          whereArgs: [dateKey],
        );
      }
    } catch (e) {
      debugPrint('CashClosingNotifier sync error: $e');
    }
  }
  
  /// Hiển thị notification
  void _showNotification(bool isLocked, String? lockedBy) {
    if (isLocked) {
      NotificationService.showSnackBar(
        "🔒 QUỸ ĐÃ ĐƯỢC CHỐT!\n${lockedBy ?? 'Admin'} vừa chốt quỹ hôm nay. Không thể thêm giao dịch mới.",
        color: Colors.red,
      );
    } else {
      NotificationService.showSnackBar(
        "🔓 Quỹ đã được mở khóa!\nBạn có thể tiếp tục giao dịch.",
        color: Colors.green,
      );
    }
  }
  
  /// Đăng ký listener
  void addListener(VoidCallback callback) {
    _listeners.add(callback);
  }
  
  /// Hủy đăng ký listener
  void removeListener(VoidCallback callback) {
    _listeners.remove(callback);
  }
  
  /// Notify tất cả listeners
  void _notifyListeners() {
    for (var listener in _listeners) {
      listener();
    }
  }
  
  /// Kiểm tra xem một ngày có bị chốt không
  Future<bool> isDateLocked(DateTime date) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(date);
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // Fast path cho ngày hôm nay
    if (dateKey == todayKey) {
      return _isTodayLocked;
    }
    
    // Query local DB
    try {
      final dbRaw = await _localDb.database;
      final result = await dbRaw.query(
        'cash_closings',
        columns: ['isLocked'],
        where: 'dateKey = ?',
        whereArgs: [dateKey],
      );
      
      if (result.isNotEmpty) {
        return result.first['isLocked'] == 1;
      }
    } catch (e) {
      debugPrint('isDateLocked error: $e');
    }
    
    return false;
  }
  
  /// Kiểm tra và hiển thị cảnh báo nếu ngày hôm nay đã chốt quỹ
  /// Trả về true nếu được phép thực hiện giao dịch, false nếu bị block
  Future<bool> canPerformTransaction({
    required BuildContext context,
    String? customMessage,
  }) async {
    if (!_isTodayLocked) return true;
    
    // Hiển thị dialog cảnh báo
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.lock, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text("ĐÃ CHỐT QUỸ", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              customMessage ?? "Ngày hôm nay đã được chốt quỹ bởi $_lockedBy.",
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "⚠️ Giao dịch sẽ được ghi nhận vào NGÀY MAI",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Hoặc liên hệ quản lý để MỞ KHÓA ngày hôm nay.",
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text("TIẾP TỤC (GHI NGÀY MAI)"),
          ),
        ],
      ),
    );
    
    return result == true;
  }
  
  /// Lấy ngày giao dịch thực tế (nếu hôm nay đã chốt → dùng ngày mai)
  DateTime getEffectiveTransactionDate() {
    if (_isTodayLocked) {
      return DateTime.now().add(const Duration(days: 1));
    }
    return DateTime.now();
  }
  
  /// Cleanup
  void dispose() {
    _subscription?.cancel();
    _listeners.clear();
  }
}
