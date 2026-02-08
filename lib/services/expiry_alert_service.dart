import 'package:flutter/foundation.dart';
import 'dart:ui' show Color;
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/shop_settings_model.dart';
import 'category_service.dart';
import 'user_service.dart';
import 'notification_service.dart';

/// Service quản lý cảnh báo hạn sử dụng sản phẩm
/// Phục vụ Module Thực phẩm (Food Industry)
class ExpiryAlertService {
  static final ExpiryAlertService _instance = ExpiryAlertService._internal();
  factory ExpiryAlertService() => _instance;
  ExpiryAlertService._internal();

  final DBHelper _dbHelper = DBHelper();
  final CategoryService _categoryService = CategoryService();

  // Cache
  int? _cachedWarningDays;
  DateTime? _lastAlertCheck;

  // === CONFIGURATION ===

  /// Lấy số ngày cảnh báo từ ShopSettings
  Future<int> getWarningDays() async {
    if (_cachedWarningDays != null) return _cachedWarningDays!;

    final settings = await _categoryService.getShopSettings();
    _cachedWarningDays = settings?.expiryWarningDays ?? 7;
    return _cachedWarningDays!;
  }

  /// Cập nhật số ngày cảnh báo
  Future<bool> updateWarningDays(int days) async {
    final settings = await _categoryService.getShopSettings();
    if (settings == null) return false;

    final updated = settings.copyWith(expiryWarningDays: days);
    final result = await _categoryService.saveShopSettings(updated);
    if (result) {
      _cachedWarningDays = days;
    }
    return result;
  }

  /// Kiểm tra shop có bật module expiry không
  Future<bool> isExpiryEnabled() async {
    final settings = await _categoryService.getShopSettings();
    return settings?.enableExpiry ?? false;
  }

  // === QUERY PRODUCTS ===

  /// Lấy sản phẩm đã hết hạn
  Future<List<Product>> getExpiredProducts() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    try {
      final db = await _dbHelper.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      final results = await db.query(
        'products',
        where: 'shopId = ? AND expiryDate IS NOT NULL AND expiryDate > 0 AND expiryDate < ? AND quantity > 0',
        whereArgs: [shopId, now],
        orderBy: 'expiryDate ASC',
      );

      return results.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error getting expired products: $e');
      return [];
    }
  }

  /// Lấy sản phẩm sắp hết hạn (trong X ngày từ settings)
  Future<List<Product>> getNearExpiryProducts({int? customDays}) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    final warningDays = customDays ?? await getWarningDays();

    try {
      final db = await _dbHelper.database;
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final futureMs = now.add(Duration(days: warningDays)).millisecondsSinceEpoch;

      final results = await db.query(
        'products',
        where: 'shopId = ? AND expiryDate IS NOT NULL AND expiryDate > 0 AND expiryDate >= ? AND expiryDate <= ? AND quantity > 0',
        whereArgs: [shopId, nowMs, futureMs],
        orderBy: 'expiryDate ASC',
      );

      return results.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error getting near expiry products: $e');
      return [];
    }
  }

  /// Lấy tất cả sản phẩm có hạn sử dụng (đã set expiryDate)
  Future<List<Product>> getAllProductsWithExpiry({bool includeExpired = true}) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    try {
      final db = await _dbHelper.database;
      final now = DateTime.now().millisecondsSinceEpoch;

      String whereClause = 'shopId = ? AND expiryDate IS NOT NULL AND expiryDate > 0 AND quantity > 0';
      List<dynamic> whereArgs = [shopId];

      if (!includeExpired) {
        whereClause += ' AND expiryDate >= ?';
        whereArgs.add(now);
      }

      final results = await db.query(
        'products',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'expiryDate ASC',
      );

      return results.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error getting products with expiry: $e');
      return [];
    }
  }

  /// Lấy sản phẩm theo số lô
  Future<List<Product>> getProductsByBatch(String batchNumber) async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    try {
      final db = await _dbHelper.database;
      final results = await db.query(
        'products',
        where: 'shopId = ? AND batchNumber = ?',
        whereArgs: [shopId, batchNumber],
        orderBy: 'expiryDate ASC',
      );

      return results.map((m) => Product.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error getting products by batch: $e');
      return [];
    }
  }

  // === STATISTICS ===

  /// Đếm số sản phẩm theo tình trạng hạn sử dụng
  Future<ExpiryStats> getExpiryStats() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return ExpiryStats.empty();

    final warningDays = await getWarningDays();

    try {
      final db = await _dbHelper.database;
      final now = DateTime.now();
      final nowMs = now.millisecondsSinceEpoch;
      final futureMs = now.add(Duration(days: warningDays)).millisecondsSinceEpoch;

      // Count expired
      final expiredResult = await db.rawQuery('''
        SELECT COUNT(*) as count FROM products 
        WHERE shopId = ? AND expiryDate IS NOT NULL AND expiryDate > 0 
        AND expiryDate < ? AND quantity > 0
      ''', [shopId, nowMs]);
      final expiredCount = expiredResult.first['count'] as int? ?? 0;

      // Count near expiry
      final nearExpiryResult = await db.rawQuery('''
        SELECT COUNT(*) as count FROM products 
        WHERE shopId = ? AND expiryDate IS NOT NULL AND expiryDate > 0 
        AND expiryDate >= ? AND expiryDate <= ? AND quantity > 0
      ''', [shopId, nowMs, futureMs]);
      final nearExpiryCount = nearExpiryResult.first['count'] as int? ?? 0;

      // Count good (beyond warning period)
      final goodResult = await db.rawQuery('''
        SELECT COUNT(*) as count FROM products 
        WHERE shopId = ? AND expiryDate IS NOT NULL AND expiryDate > 0 
        AND expiryDate > ? AND quantity > 0
      ''', [shopId, futureMs]);
      final goodCount = goodResult.first['count'] as int? ?? 0;

      // Total with expiry
      final totalResult = await db.rawQuery('''
        SELECT COUNT(*) as count FROM products 
        WHERE shopId = ? AND expiryDate IS NOT NULL AND expiryDate > 0 AND quantity > 0
      ''', [shopId]);
      final totalCount = totalResult.first['count'] as int? ?? 0;

      // Value at risk (expired + near expiry)
      final valueResult = await db.rawQuery('''
        SELECT SUM(cost * quantity) as value FROM products 
        WHERE shopId = ? AND expiryDate IS NOT NULL AND expiryDate > 0 
        AND expiryDate <= ? AND quantity > 0
      ''', [shopId, futureMs]);
      final valueAtRisk = valueResult.first['value'] as int? ?? 0;

      return ExpiryStats(
        expiredCount: expiredCount,
        nearExpiryCount: nearExpiryCount,
        goodCount: goodCount,
        totalWithExpiry: totalCount,
        valueAtRisk: valueAtRisk,
        warningDays: warningDays,
      );
    } catch (e) {
      debugPrint('Error getting expiry stats: $e');
      return ExpiryStats.empty();
    }
  }

  /// Lấy danh sách số lô với thống kê
  Future<List<BatchInfo>> getBatchList() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) return [];

    try {
      final db = await _dbHelper.database;
      final results = await db.rawQuery('''
        SELECT 
          batchNumber,
          COUNT(*) as productCount,
          SUM(quantity) as totalQuantity,
          MIN(expiryDate) as earliestExpiry,
          MAX(expiryDate) as latestExpiry,
          SUM(cost * quantity) as totalValue
        FROM products 
        WHERE shopId = ? AND batchNumber IS NOT NULL AND batchNumber != '' AND quantity > 0
        GROUP BY batchNumber
        ORDER BY earliestExpiry ASC
      ''', [shopId]);

      return results.map((m) => BatchInfo.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Error getting batch list: $e');
      return [];
    }
  }

  // === ALERTS ===

  /// Kiểm tra và gửi cảnh báo hạn sử dụng
  /// Gọi hàm này khi app khởi động hoặc vào màn hình chính
  Future<void> checkAndNotifyExpiry() async {
    // Chỉ check 1 lần mỗi giờ
    final now = DateTime.now();
    if (_lastAlertCheck != null &&
        now.difference(_lastAlertCheck!).inMinutes < 60) {
      return;
    }
    _lastAlertCheck = now;

    // Kiểm tra module có bật không
    if (!await isExpiryEnabled()) return;

    final stats = await getExpiryStats();

    if (stats.expiredCount > 0) {
      NotificationService.showSnackBar(
        '⛔ Cảnh báo: ${stats.expiredCount} sản phẩm đã HẾT HẠN',
        color: const Color(0xFFE53935), // Red
      );
    } else if (stats.nearExpiryCount > 0) {
      NotificationService.showSnackBar(
        '⚠️ ${stats.nearExpiryCount} sản phẩm sắp hết hạn trong ${stats.warningDays} ngày',
        color: const Color(0xFFFB8C00), // Orange
      );
    }
  }

  // === HELPERS ===

  /// Tính số ngày còn lại đến hạn
  int daysUntilExpiry(Product product) {
    if (product.expiryDate == null) return 999;
    final expiry = DateTime.fromMillisecondsSinceEpoch(product.expiryDate!);
    return expiry.difference(DateTime.now()).inDays;
  }

  /// Phân loại trạng thái hạn sử dụng
  ExpiryStatus getExpiryStatus(Product product, {int? warningDays}) {
    if (product.expiryDate == null) return ExpiryStatus.noExpiry;
    
    final days = daysUntilExpiry(product);
    final warning = warningDays ?? _cachedWarningDays ?? 7;

    if (days < 0) return ExpiryStatus.expired;
    if (days == 0) return ExpiryStatus.expiringToday;
    if (days <= warning) return ExpiryStatus.nearExpiry;
    return ExpiryStatus.good;
  }

  /// Format text hiển thị theo status
  String formatExpiryText(Product product, {int? warningDays}) {
    final status = getExpiryStatus(product, warningDays: warningDays);
    final days = daysUntilExpiry(product);

    switch (status) {
      case ExpiryStatus.noExpiry:
        return 'Không HSD';
      case ExpiryStatus.expired:
        return 'Hết hạn ${-days} ngày trước';
      case ExpiryStatus.expiringToday:
        return 'Hết hạn HÔM NAY';
      case ExpiryStatus.nearExpiry:
        return 'Còn $days ngày';
      case ExpiryStatus.good:
        return 'Còn $days ngày';
    }
  }

  /// Clear cache 
  void clearCache() {
    _cachedWarningDays = null;
    _lastAlertCheck = null;
  }
}

/// Enum trạng thái hạn sử dụng
enum ExpiryStatus {
  noExpiry,      // Không có HSD
  expired,       // Đã hết hạn
  expiringToday, // Hết hạn hôm nay
  nearExpiry,    // Sắp hết hạn (trong warning days)
  good,          // Còn hạn tốt
}

/// Model thống kê hạn sử dụng
class ExpiryStats {
  final int expiredCount;
  final int nearExpiryCount;
  final int goodCount;
  final int totalWithExpiry;
  final int valueAtRisk;
  final int warningDays;

  ExpiryStats({
    required this.expiredCount,
    required this.nearExpiryCount,
    required this.goodCount,
    required this.totalWithExpiry,
    required this.valueAtRisk,
    required this.warningDays,
  });

  factory ExpiryStats.empty() => ExpiryStats(
    expiredCount: 0,
    nearExpiryCount: 0,
    goodCount: 0,
    totalWithExpiry: 0,
    valueAtRisk: 0,
    warningDays: 7,
  );

  int get atRiskCount => expiredCount + nearExpiryCount;
  bool get hasAlerts => expiredCount > 0 || nearExpiryCount > 0;
}

/// Model thông tin lô hàng
class BatchInfo {
  final String batchNumber;
  final int productCount;
  final int totalQuantity;
  final DateTime? earliestExpiry;
  final DateTime? latestExpiry;
  final int totalValue;

  BatchInfo({
    required this.batchNumber,
    required this.productCount,
    required this.totalQuantity,
    this.earliestExpiry,
    this.latestExpiry,
    required this.totalValue,
  });

  factory BatchInfo.fromMap(Map<String, dynamic> map) {
    return BatchInfo(
      batchNumber: map['batchNumber'] ?? '',
      productCount: map['productCount'] ?? 0,
      totalQuantity: map['totalQuantity'] ?? 0,
      earliestExpiry: map['earliestExpiry'] != null && map['earliestExpiry'] > 0
          ? DateTime.fromMillisecondsSinceEpoch(map['earliestExpiry'])
          : null,
      latestExpiry: map['latestExpiry'] != null && map['latestExpiry'] > 0
          ? DateTime.fromMillisecondsSinceEpoch(map['latestExpiry'])
          : null,
      totalValue: map['totalValue'] ?? 0,
    );
  }

  bool get hasExpired {
    if (earliestExpiry == null) return false;
    return earliestExpiry!.isBefore(DateTime.now());
  }

  bool get isNearExpiry {
    if (earliestExpiry == null) return false;
    final now = DateTime.now();
    return earliestExpiry!.isAfter(now) &&
        earliestExpiry!.difference(now).inDays <= 7;
  }
}
