import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_write_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../data/db_helper.dart';
import '../models/import_order_model.dart';
import '../models/stock_entry_model.dart';
import '../services/user_service.dart';

/// Service quản lý lịch sử phiếu nhập kho (Import Orders)
class ImportOrderService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final DBHelper _db = DBHelper();

  /// Tạo phiếu nhập kho từ StockEntry đã xác nhận
  /// Ghi vào cả Firestore và local DB
  static Future<String?> createFromStockEntry({
    required StockEntry entry,
    required String entryId,
  }) async {
    try {
      final shopId = entry.shopId;
      final userName = await UserService.getCurrentUserName();
      final userId = FirebaseAuth.instance.currentUser?.uid;
      // Use confirmedAt if available (backfill), otherwise now
      final importDateMs = entry.confirmedAt?.millisecondsSinceEpoch
          ?? entry.createdAt?.millisecondsSinceEpoch
          ?? DateTime.now().millisecondsSinceEpoch;

      // Generate order code
      final orderCode = await _db.generateNextImportOrderCode();

      // Calculate totals
      int totalQuantity = 0;
      int totalAmount = 0;
      for (final item in entry.items) {
        totalQuantity += item.quantity;
        totalAmount += item.totalCost.toInt();
      }

      // Determine payment status
      final paymentStatus =
          entry.paymentMethod == 'CÔNG NỢ' ? 'DEBT' : 'PAID';

      // 1. Create import_order doc in Firestore
      final orderRef = _firestore.collection('import_orders').doc();
      final orderFirestoreId = orderRef.id;

      final orderData = <String, dynamic>{
        'shopId': shopId,
        'orderCode': orderCode,
        'supplierId': entry.supplierId,
        'supplierName': entry.supplierName,
        'totalQuantity': totalQuantity,
        'totalAmount': totalAmount,
        'paymentMethod': entry.paymentMethod,
        'paymentStatus': paymentStatus,
        'paidAmount': paymentStatus == 'PAID' ? totalAmount : 0,
        'status': 'CONFIRMED',
        'importDate': importDateMs,
        'importedBy': userName,
        'importedByUid': userId,
        'stockEntryId': entryId,
        'notes': entry.notes ?? '',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
        'deleted': false,
      };

      await orderRef.set(orderData);

      // 2. Create import_order_items docs in Firestore
      final batch = _firestore.batch();
      final itemFirestoreIds = <String>[];

      for (final item in entry.items) {
        final itemRef = _firestore.collection('import_order_items').doc();
        itemFirestoreIds.add(itemRef.id);

        batch.set(itemRef, {
          'importOrderFirestoreId': orderFirestoreId,
          'productType': item.productType,
          'productName': item.name,
          'productBrand': item.brand ?? '',
          'productModel': item.model ?? '',
          'imei': item.imei ?? '',
          'sku': item.sku ?? '',
          'quantity': item.quantity,
          'unit': item.unit ?? '',
          'costPrice': (item.cost ?? 0).toInt(),
          'totalAmount': item.totalCost.toInt(),
          'color': item.color ?? '',
          'size': item.size ?? '',
          'capacity': item.capacity ?? '',
          'condition': item.condition ?? '',
          'notes': '',
          'shopId': shopId,
          'createdAt': FieldValue.serverTimestamp(),
          'deleted': false,
        });
      }

      await batch.commit();

      // 3. Save to local DB
      final localOrderData = {
        'firestoreId': orderFirestoreId,
        'shopId': shopId,
        'orderCode': orderCode,
        'supplierId': entry.supplierId,
        'supplierName': entry.supplierName,
        'totalQuantity': totalQuantity,
        'totalAmount': totalAmount,
        'paymentMethod': entry.paymentMethod,
        'paymentStatus': paymentStatus,
        'paidAmount': paymentStatus == 'PAID' ? totalAmount : 0,
        'status': 'CONFIRMED',
        'importDate': importDateMs,
        'importedBy': userName,
        'importedByUid': userId,
        'stockEntryId': entryId,
        'notes': entry.notes ?? '',
        'createdAt': importDateMs,
        'updatedAt': importDateMs,
        'isSynced': 1,
        'deleted': 0,
      };

      await _db.insertImportOrder(localOrderData);

      // 4. Save items to local DB
      for (int i = 0; i < entry.items.length; i++) {
        final item = entry.items[i];
        final itemData = {
          'firestoreId': itemFirestoreIds[i],
          'importOrderFirestoreId': orderFirestoreId,
          'productType': item.productType,
          'productName': item.name,
          'productBrand': item.brand ?? '',
          'productModel': item.model ?? '',
          'imei': item.imei ?? '',
          'sku': item.sku ?? '',
          'quantity': item.quantity,
          'unit': item.unit ?? '',
          'costPrice': (item.cost ?? 0).toInt(),
          'totalAmount': item.totalCost.toInt(),
          'color': item.color ?? '',
          'size': item.size ?? '',
          'capacity': item.capacity ?? '',
          'condition': item.condition ?? '',
          'notes': '',
          'shopId': shopId,
          'isSynced': 1,
          'deleted': 0,
        };
        await _db.insertImportOrderItem(itemData);
      }

      debugPrint(
        '✅ ImportOrderService: Created import order $orderCode ($orderFirestoreId) with ${entry.items.length} items',
      );
      return orderFirestoreId;
    } catch (e) {
      debugPrint('❌ ImportOrderService: Failed to create import order: $e');
      return null;
    }
  }

  /// Lấy danh sách phiếu nhập kho (từ local DB)
  static Future<List<ImportOrder>> getImportOrders({
    int? startDate,
    int? endDate,
    String? status,
  }) async {
    final shopId = await UserService.getCurrentShopId();
    final rows = await _db.getImportOrders(
      shopId: shopId,
      startDate: startDate,
      endDate: endDate,
      status: status,
    );
    return rows.map((r) => ImportOrder.fromMap(r)).toList();
  }

  /// Lấy chi tiết các item của một phiếu nhập
  static Future<List<ImportOrderItem>> getImportOrderItems(
    String importOrderFirestoreId,
  ) async {
    final rows = await _db.getImportOrderItems(importOrderFirestoreId);
    return rows.map((r) => ImportOrderItem.fromMap(r)).toList();
  }

  /// Kiểm tra đã có phiếu nhập cho stock entry chưa
  static Future<bool> hasImportOrderForEntry(String stockEntryId) async {
    final existing = await _db.getImportOrderByStockEntryId(stockEntryId);
    return existing != null;
  }

  /// Backfill import orders từ các stock_entries đã confirmed trước đó
  /// Chạy 1 lần khi mở trang lịch sử nhập kho lần đầu
  static bool _backfillDone = false;
  static Future<int> backfillFromFirestore() async {
    if (_backfillDone) return 0;
    _backfillDone = true;

    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return 0;

      // Query confirmed stock entries for this shop
      final snap = await _firestore.collection('stock_entries')
          .where('shopId', isEqualTo: shopId)
          .where('status', whereIn: ['confirmed', 'CONFIRMED'])
          .orderBy('confirmedAt', descending: true)
          .limit(200)
          .get();

      if (snap.docs.isEmpty) return 0;

      // Check which ones already have import orders (in Firestore)
      final existingOrders = await _firestore.collection('import_orders')
          .where('shopId', isEqualTo: shopId)
          .get();
      final existingEntryIds = <String>{};
      for (final doc in existingOrders.docs) {
        final sid = doc.data()['stockEntryId'] as String?;
        if (sid != null) existingEntryIds.add(sid);
      }

      int created = 0;
      for (final doc in snap.docs) {
        final entryId = doc.id;
        if (existingEntryIds.contains(entryId)) continue;

        try {
          final entry = StockEntry.fromMap(doc.data(), docId: entryId);
          if (entry.items.isEmpty) continue;

          await createFromStockEntry(entry: entry, entryId: entryId);
          created++;
        } catch (e) {
          debugPrint('⚠️ Backfill error for entry $entryId: $e');
        }
      }

      debugPrint('✅ ImportOrderService: Backfilled $created import orders from ${snap.docs.length} confirmed entries');
      return created;
    } catch (e) {
      debugPrint('❌ ImportOrderService: Backfill failed: $e');
      return 0;
    }
  }
}

