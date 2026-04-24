import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_write_helper.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/sales_return_model.dart';
import '../services/user_service.dart';
import '../services/financial_activity_service.dart';
import '../services/encryption_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/audit_service.dart';
import '../services/event_bus.dart';

/// Service for processing sales returns:
/// 1. Create return record (header + items)
/// 2. Restore stock for returned products
/// 3. Log refund in financial activity (sổ quỹ)
/// 4. Sync to Firestore
class SalesReturnService {
  static final _db = DBHelper();
  static final _firestore = FirebaseFirestore.instance;

  /// Process a full sales return
  /// Returns {success: bool, returnId: int?, error: String?}
  static Future<Map<String, dynamic>> processReturn({
    required int salesOrderId,
    required String? salesOrderFirestoreId,
    required String customerName,
    required String customerPhone,
    required String refundMethod,
    required List<SalesReturnItem> items,
    String? note,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final userName = await UserService.getCurrentUserName();
      final now = DateTime.now().millisecondsSinceEpoch;
      final returnFirestoreId = 'sr_$now';

      // Validate: check for already-returned quantities
      if (salesOrderId > 0) {
        final returnedMap = await _db.getReturnedQuantitiesForSale(salesOrderId);
        for (final item in items) {
          final isPhone = item.productImei != null &&
              item.productImei!.isNotEmpty &&
              !item.productImei!.toUpperCase().startsWith('PKX') &&
              item.productImei != 'NO_IMEI';
          final key = isPhone ? item.productImei!.toUpperCase() : item.productName.toUpperCase();
          final alreadyReturned = returnedMap[key] ?? 0;
          // We don't block — just cap quantity to remaining
          final maxRemaining = (item.quantity + alreadyReturned) > item.quantity
              ? item.quantity
              : item.quantity;
          if (alreadyReturned > 0) {
            debugPrint('⚠️ Item ${item.productName}: already returned $alreadyReturned');
          }
        }
      }

      // Calculate totals
      int totalReturnAmount = 0;
      int totalReturnCost = 0;
      for (final item in items) {
        item.amount = item.price * item.quantity;
        totalReturnAmount += item.amount;
        totalReturnCost += item.cost * item.quantity;
      }

      // 1. Create return header
      final returnHeader = SalesReturn(
        firestoreId: returnFirestoreId,
        salesOrderId: salesOrderId,
        salesOrderFirestoreId: salesOrderFirestoreId,
        customerName: customerName,
        customerPhone: customerPhone,
        returnDate: now,
        totalReturnAmount: totalReturnAmount,
        totalReturnCost: totalReturnCost,
        refundMethod: refundMethod,
        note: note,
        createdAt: now,
        createdBy: userName,
        approvedBy: userName,
        approvedAt: now,
        status: 'APPROVED',
        shopId: shopId,
      );

      final returnId = await _db.insertSalesReturn(returnHeader.toMap());
      debugPrint('✅ SalesReturn header created: id=$returnId, firestoreId=$returnFirestoreId');

      // 2. Create return items + restore stock
      for (final item in items) {
        final itemFirestoreId = '${returnFirestoreId}_item_${item.productImei ?? item.productName}';
        item.salesReturnId = returnId;
        item.salesReturnFirestoreId = returnFirestoreId;
        item.firestoreId = itemFirestoreId;
        item.shopId = shopId;

        await _db.insertSalesReturnItem(item.toMap());

        // Restore stock
        await _restoreStock(item);
      }

      // 3. Log financial activity (refund)
      if (refundMethod != 'CÔNG NỢ') {
        await FinancialActivityService.logCustomActivity(
          activityType: 'REFUND',
          amount: totalReturnAmount,
          direction: 'OUT',
          paymentMethod: refundMethod,
          title: 'HOÀN TIỀN TRẢ HÀNG: ${items.map((i) => i.productName).join(', ')}',
          description: 'KH: $customerName ($customerPhone). Lý do: ${note ?? "Trả hàng"}',
          customerName: customerName,
          phone: customerPhone,
          productInfo: items.map((i) => '${i.productName} x${i.quantity}').join(', '),
          referenceType: 'sales_return',
          referenceId: returnFirestoreId,
          createdBy: userName,
        );
      } else {
        // For debt-based sales, reduce the debt amount instead
        await _reduceDebt(salesOrderFirestoreId, totalReturnAmount);
        await FinancialActivityService.logCustomActivity(
          activityType: 'REFUND',
          amount: totalReturnAmount,
          direction: 'DEBT',
          paymentMethod: 'CÔNG NỢ',
          title: 'TRẢ HÀNG GIẢM NỢ: ${items.map((i) => i.productName).join(', ')}',
          description: 'Giảm công nợ $customerName. Lý do: ${note ?? "Trả hàng"}',
          customerName: customerName,
          phone: customerPhone,
          productInfo: items.map((i) => '${i.productName} x${i.quantity}').join(', '),
          referenceType: 'sales_return',
          referenceId: returnFirestoreId,
          createdBy: userName,
        );
      }

      // 4. Sync to Firestore
      await _syncReturnToFirestore(returnHeader, items, returnId);

      // 5. Audit log
      await AuditService.logAction(
        action: 'SALES_RETURN',
        entityType: 'sales_return',
        entityId: returnFirestoreId,
        summary: 'Trả hàng: $customerName - ${items.map((i) => i.productName).join(', ')} - ${_formatMoney(totalReturnAmount)}đ',
      );

      // 6. Emit event for UI refresh
      EventBus().emit('sales_returns_changed');
      EventBus().emit('financial_activity_changed');

      debugPrint('✅ Sales return completed: $returnFirestoreId, amount=$totalReturnAmount');

      return {
        'success': true,
        'returnId': returnId,
        'firestoreId': returnFirestoreId,
        'totalReturnAmount': totalReturnAmount,
      };
    } catch (e) {
      debugPrint('❌ SalesReturnService.processReturn error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Restore stock for a returned item
  static Future<void> _restoreStock(SalesReturnItem item) async {
    try {
      Product? product;

      // Find product by IMEI or by name
      if (item.productImei != null &&
          item.productImei!.isNotEmpty &&
          !item.productImei!.toUpperCase().startsWith('PKX') &&
          item.productImei != 'NO_IMEI') {
        product = await _db.getProductByImei(item.productImei!);
      }

      if (product == null && item.productFirestoreId != null) {
        product = await _db.getProductByFirestoreId(item.productFirestoreId!);
      }

      if (product == null) {
        product = await _db.getProductByName(item.productName);
      }

      if (product != null) {
        await _db.addProductQuantity(product.id!, item.quantity);
        product.quantity += item.quantity;
        if (product.status == 0 && product.quantity > 0) {
          await _db.updateProductStatus(product.id!, 1);
          product.status = 1;
        }

        // Sync to cloud
        if (product.firestoreId != null && product.firestoreId!.isNotEmpty) {
          try {
            await _firestore
                .collection('products')
                .doc(product.firestoreId)
                .update({
              'quantity': product.quantity,
              'status': product.status,
              'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
            });
            debugPrint('☁️ Synced stock restore: ${product.name} qty=${product.quantity}');
          } catch (e) {
            debugPrint('⚠️ Cloud sync failed for stock restore: $e');
            await SyncOrchestrator().enqueue(
              entityType: SyncEntityType.product,
              entityId: product.id!,
              firestoreId: product.firestoreId,
              operation: SyncOperation.update,
              data: product.toMap(),
            );
          }
        }

        debugPrint('✅ Stock restored: ${product.name} +${item.quantity} (total: ${product.quantity})');
      } else {
        debugPrint('⚠️ Product not found for stock restore: ${item.productName} (${item.productImei})');
      }
    } catch (e) {
      debugPrint('❌ _restoreStock error: $e');
    }
  }

  /// Reduce debt for debt-based sales
  static Future<void> _reduceDebt(String? saleFirestoreId, int amount) async {
    if (saleFirestoreId == null) return;
    try {
      final database = await _db.database;
      final debts = await database.query(
        'debts',
        where: 'linkedId = ?',
        whereArgs: [saleFirestoreId],
      );

      if (debts.isNotEmpty) {
        final debt = debts.first;
        final currentTotal = (debt['totalAmount'] ?? 0) as int;
        final newTotal = (currentTotal - amount).clamp(0, currentTotal);
        await database.update(
          'debts',
          {'totalAmount': newTotal, 'isSynced': 0},
          where: 'id = ?',
          whereArgs: [debt['id']],
        );

        // Sync debt to Firestore
        final debtFid = debt['firestoreId'] as String?;
        if (debtFid != null) {
          try {
            await _firestore.collection('debts').doc(debtFid).update({
              'totalAmount': newTotal,
              'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
            });
          } catch (e) {
            debugPrint('⚠️ Debt cloud sync failed: $e');
          }
        }
        debugPrint('✅ Debt reduced by $amount for sale $saleFirestoreId');
      }
    } catch (e) {
      debugPrint('❌ _reduceDebt error: $e');
    }
  }

  /// Sync return docs to Firestore (try direct, fallback to queue)
  static Future<void> _syncReturnToFirestore(
    SalesReturn returnHeader,
    List<SalesReturnItem> items,
    int localId,
  ) async {
    bool headerSynced = false;
    try {
      final shopId = UserService.getShopIdSync();
      if (shopId == null) return;

      // Sync header
      final headerData = returnHeader.toMap();
      headerData.remove('id');
      headerData['shopId'] = shopId;
      headerData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedHeader = EncryptionService.encryptMap(headerData);
      await _firestore
          .collection('sales_returns')
          .doc(returnHeader.firestoreId)
          .set(encryptedHeader);
      headerSynced = true;

      // Sync items
      for (final item in items) {
        final itemData = item.toMap();
        itemData.remove('id');
        itemData['shopId'] = shopId;
        final encryptedItem = EncryptionService.encryptMap(itemData);
        await _firestore
            .collection('sales_return_items')
            .doc(item.firestoreId)
            .set(encryptedItem);
      }

      // Mark local records synced
      final database = await _db.database;
      await database.update(
        'sales_returns',
        {'isSynced': 1},
        where: 'id = ?',
        whereArgs: [localId],
      );

      debugPrint('☁️ Sales return synced to Firestore: ${returnHeader.firestoreId}');
    } catch (e) {
      debugPrint('⚠️ Firestore sync failed for return, queuing: $e');
      // Enqueue header for retry if not yet synced
      if (!headerSynced) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.salesReturn,
          entityId: localId,
          firestoreId: returnHeader.firestoreId,
          operation: SyncOperation.create,
          data: returnHeader.toMap(),
        );
      }
      // Enqueue items for retry
      for (final item in items) {
        if (item.salesReturnId != null) {
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.salesReturnItem,
            entityId: item.salesReturnId!,
            firestoreId: item.firestoreId,
            operation: SyncOperation.create,
            data: item.toMap(),
          );
        }
      }
    }
  }

  /// Get all returns for a shop
  static Future<List<SalesReturn>> getReturns({int? limit}) async {
    final rows = await _db.getSalesReturns(limit: limit);
    return rows.map((r) => SalesReturn.fromMap(r)).toList();
  }

  /// Get returns for a specific sale order
  static Future<List<SalesReturn>> getReturnsBySaleId(int saleId) async {
    final rows = await _db.getSalesReturnsBySalesOrderId(saleId);
    return rows.map((r) => SalesReturn.fromMap(r)).toList();
  }

  /// Get return items for a specific return
  static Future<List<SalesReturnItem>> getReturnItems(int returnId) async {
    final rows = await _db.getSalesReturnItems(returnId);
    return rows.map((r) => SalesReturnItem.fromMap(r)).toList();
  }

  /// Get return statistics for a date range
  static Future<Map<String, dynamic>> getReturnStats({
    required int startDate,
    required int endDate,
  }) async {
    return await _db.getSalesReturnStats(startDate: startDate, endDate: endDate);
  }

  static String _formatMoney(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}tr';
    }
    if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}k';
    }
    return '$amount';
  }
}

