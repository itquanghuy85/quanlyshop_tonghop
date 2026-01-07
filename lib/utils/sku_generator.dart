import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';

class SKUGenerator {
  /// Tạo mã hàng (SKU) duy nhất theo format: [NHOM]-[MODEL]-[THONGTIN]-[STT]
  static Future<String> generateSKU({
    required String nhom,
    String? model,
    String? thongtin,
    required DBHelper dbHelper,
    FirestoreService? firestoreService,
  }) async {
    // 1. Validate đầu vào
    if (!['IP', 'SS', 'OP', 'RD', 'PIN', 'MH', 'PK'].contains(nhom.toUpperCase())) {
      throw ArgumentError('NHOM không hợp lệ');
    }

    // 2. Tạo chuỗi cơ sở (Base SKU)
    String baseSKU = nhom.toUpperCase();
    if (model != null && model.trim().isNotEmpty) {
      baseSKU += '-${model.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9-]'), '')}';
    }
    if (thongtin != null && thongtin.trim().isNotEmpty) {
      baseSKU += '-${thongtin.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9-]'), '')}';
    }

    // 3. Tìm số thứ tự lớn nhất hiện có
    int maxSTT = await _findMaxSTT(baseSKU, dbHelper, firestoreService);
    String sttFormatted = (maxSTT + 1).toString().padLeft(4, '0');

    return '$baseSKU-$sttFormatted';
  }

  static Future<int> _findMaxSTT(String baseSKU, DBHelper dbHelper, FirestoreService? firestoreService) async {
    int maxSTT = 0;
    final db = await dbHelper.database;

    // --- SỬA LỖI: Bảng products không có cột deleted ---
    final sqliteResults = await db.rawQuery(
      "SELECT name FROM products WHERE name LIKE ?",
      ['$baseSKU-%']
    );

    for (var row in sqliteResults) {
      String sku = row['name'] as String;
      if (sku.startsWith('$baseSKU-')) {
        String sttPart = sku.substring(baseSKU.length + 1);
        int? stt = int.tryParse(sttPart);
        if (stt != null && stt > maxSTT) maxSTT = stt;
      }
    }

    // Kiểm tra Firestore nếu có mạng
    try {
      final shopId = await UserService.getCurrentShopId();
      Query query = FirebaseFirestore.instance.collection('products');
      if (shopId != null) query = query.where('shopId', isEqualTo: shopId);
      
      query = query.where('name', isGreaterThanOrEqualTo: '$baseSKU-')
                   .where('name', isLessThan: '$baseSKU-~');

      final snapshot = await query.get();
      for (var doc in snapshot.docs) {
        String sku = doc['name'] as String;
        if (sku.startsWith('$baseSKU-')) {
          String sttPart = sku.substring(baseSKU.length + 1);
          int? stt = int.tryParse(sttPart);
          if (stt != null && stt > maxSTT) maxSTT = stt;
        }
      }
    } catch (_) {}

    return maxSTT;
  }
}
