import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';

class RepairStockService {
  static final RepairStockService _instance = RepairStockService._internal();
  factory RepairStockService() => _instance;
  RepairStockService._internal();

  final db = DBHelper();

  /// Parse chuỗi "Pin x1, Màn hình x2" thành Map {"PIN": 1, "MÀN HÌNH": 2}
  Map<String, int> parsePartsString(String partsStr) {
    final result = <String, int>{};
    if (partsStr.isEmpty) return result;
    
    final items = partsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
    
    for (final item in items) {
      final xMatch = RegExp(r'^(.+)\s+[xX](\d+)$').firstMatch(item);
      if (xMatch != null) {
        final name = xMatch.group(1)!.trim().toUpperCase();
        final qty = int.tryParse(xMatch.group(2)!) ?? 1;
        result[name] = (result[name] ?? 0) + qty;
      } else {
        result[item.toUpperCase()] = (result[item.toUpperCase()] ?? 0) + 1;
      }
    }
    return result;
  }

  /// Thực hiện trừ kho theo tên (tìm trong cả kho cũ và kho mới)
  Future<bool> deductByName(String name, int qty) async {
    final shopId = await db.database.then((_) => DBHelper().getSuppliers().then((_) async {
       // Helper để lấy shopId an toàn từ DBHelper (vì hàm getScopedShopId là private)
       // Ở đây tôi gọi gián tiếp qua db
       return null; 
    }));
    
    // Tìm linh kiện và trừ kho - Logic này sẽ gọi các hàm public của DBHelper
    final allParts = await db.getAllPartsUnified();
    final match = allParts.firstWhere(
      (p) => p['partName'].toString().toUpperCase() == name.toUpperCase(),
      orElse: () => {},
    );

    if (match.isNotEmpty) {
      return await db.deductPartQuantityUnified(
        match['id'] as int,
        match['source'] as String,
        qty,
      );
    }
    return false;
  }

  /// Thực hiện hoàn kho theo tên
  Future<bool> restoreByName(String name, int qty) async {
    return await db.restorePartQuantityByNameUnified(name, qty);
  }

  /// So sánh phụ tùng CŨ và MỚI, sau đó thực hiện cộng/trừ kho tương ứng
  Future<void> syncStockDelta(String oldPartsStr, String newPartsStr) async {
    if (oldPartsStr == newPartsStr) return;

    final oldMap = parsePartsString(oldPartsStr);
    final newMap = parsePartsString(newPartsStr);

    debugPrint('📦 [RepairStockService] Đang tính toán chênh lệch kho...');

    // 1. Phụ tùng cần trừ thêm (Có trong mới nhưng không có trong cũ, hoặc số lượng tăng lên)
    for (var entry in newMap.entries) {
      final oldQty = oldMap[entry.key] ?? 0;
      if (entry.value > oldQty) {
        final diff = entry.value - oldQty;
        final ok = await deductByName(entry.key, diff);
        if (ok) debugPrint('✅ Đã trừ kho thêm: ${entry.key} x$diff');
      }
    }

    // 2. Phụ tùng cần hoàn lại (Có trong cũ nhưng không có trong mới, hoặc số lượng giảm đi)
    for (var entry in oldMap.entries) {
      final newQty = newMap[entry.key] ?? 0;
      if (entry.value > newQty) {
        final diff = entry.value - newQty;
        final ok = await restoreByName(entry.key, diff);
        if (ok) debugPrint('✅ Đã hoàn kho: ${entry.key} x$diff');
      }
    }
  }
}
