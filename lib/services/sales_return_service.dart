import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_write_helper.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/sales_return_model.dart';
import '../services/user_service.dart';
import '../services/financial_activity_service.dart';
import '../services/audit_service.dart';
import '../utils/money_utils.dart';
import '../services/encryption_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/event_bus.dart';
import '../models/sale_order_model.dart';

/// Service for processing sales returns:
/// 1. Create return record (header + items)
/// 2. Restore stock for returned products
/// 3. Log refund in financial activity (sổ quỹ)
/// 4. Sync to Firestore
class SalesReturnService {
  static final _db = DBHelper();
  static final _firestore = FirebaseFirestore.instance;
  static final Set<String> _activeReturnLocks = <String>{};

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
    final lockKey = (salesOrderFirestoreId != null && salesOrderFirestoreId.isNotEmpty)
        ? 'sale_fid_$salesOrderFirestoreId'
        : 'sale_id_$salesOrderId';
    if (_activeReturnLocks.contains(lockKey)) {
      return {
        'success': false,
        'error': 'Yêu cầu trả hàng đang được xử lý, vui lòng chờ.',
      };
    }
    _activeReturnLocks.add(lockKey);

    try {
      final shopId = UserService.getShopIdSync();
      if (shopId == null || shopId.isEmpty) {
        return {
          'success': false,
          'error': 'Không có shopId hợp lệ, vui lòng đăng nhập lại.',
        };
      }
      final userName = await UserService.getCurrentUserName();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final nowUs = DateTime.now().microsecondsSinceEpoch;
      final returnFirestoreId = 'sr_$nowUs';

      if (items.isEmpty) {
        return {
          'success': false,
          'error': 'Không có sản phẩm nào để trả.',
        };
      }

      final normalizedItems = items
          .where((i) => i.quantity > 0)
          .map((i) {
            i.productName = i.productName.trim();
            return i;
          })
          .toList();

      if (normalizedItems.isEmpty) {
        return {
          'success': false,
          'error': 'Số lượng trả không hợp lệ.',
        };
      }

      // Validate against original sold quantities: remainingQty = soldQty - returnedQty
      final soldQtyMap = await _buildSoldQtyMap(
        salesOrderId: salesOrderId,
        salesOrderFirestoreId: salesOrderFirestoreId,
      );
      if (soldQtyMap.isEmpty) {
        return {
          'success': false,
          'error': 'Không xác định được dữ liệu đơn gốc để trả hàng.',
        };
      }

      final returnedMap = await _getReturnedQtyMap(
        salesOrderId: salesOrderId,
        salesOrderFirestoreId: salesOrderFirestoreId,
      );

      final requestByKey = <String, int>{};
      for (final item in normalizedItems) {
        final key = _itemKey(item.productImei, item.productName);
        requestByKey[key] = (requestByKey[key] ?? 0) + item.quantity;
      }

      for (final entry in requestByKey.entries) {
        final soldQty = soldQtyMap[entry.key] ?? 0;
        final returnedQty = returnedMap[entry.key] ?? 0;
        final remainingQty = soldQty - returnedQty;
        if (remainingQty <= 0) {
          return {
            'success': false,
            'error': 'Sản phẩm đã được trả hết trước đó: ${entry.key}',
          };
        }
        if (entry.value > remainingQty) {
          return {
            'success': false,
            'error': 'Số lượng trả vượt quá còn lại ($remainingQty) cho ${entry.key}.',
          };
        }
      }

      // Calculate totals
      int totalReturnAmount = 0;
      int totalReturnCost = 0;
      for (final item in normalizedItems) {
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
        returnDate: nowMs,
        totalReturnAmount: totalReturnAmount,
        totalReturnCost: totalReturnCost,
        refundMethod: refundMethod,
        note: note,
        createdAt: nowMs,
        createdBy: userName,
        approvedBy: userName,
        approvedAt: nowMs,
        status: 'APPROVED',
        shopId: shopId,
      );

      final returnId = await _db.insertSalesReturn(returnHeader.toMap());
      debugPrint('✅ SalesReturn header created: id=$returnId, firestoreId=$returnFirestoreId');

      // 2. Create return items + restore stock
      for (var i = 0; i < normalizedItems.length; i++) {
        final item = normalizedItems[i];
        final suffixBase = '${item.productId ?? 0}_${item.productFirestoreId ?? ''}_${item.productImei ?? ''}_${item.productName}'.toUpperCase();
        final itemFirestoreId = '${returnFirestoreId}_item_${i + 1}_${suffixBase.hashCode.abs()}';
        item.salesReturnId = returnId;
        item.salesReturnFirestoreId = returnFirestoreId;
        item.firestoreId = itemFirestoreId;
        item.shopId = shopId;

        final insertedItemId = await _db.insertSalesReturnItem(item.toMap());
        item.id = insertedItemId;

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
          title: 'HOÀN TIỀN TRẢ HÀNG: ${normalizedItems.map((i) => i.productName).join(', ')}',
          description: 'KH: $customerName ($customerPhone). Lý do: ${note ?? "Trả hàng"}',
          customerName: customerName,
          phone: customerPhone,
          productInfo: normalizedItems.map((i) => '${i.productName} x${i.quantity}').join(', '),
          referenceType: 'sales_return',
          referenceId: returnFirestoreId,
          createdBy: userName,
        );
      } else {
        await FinancialActivityService.logCustomActivity(
          activityType: 'REFUND',
          amount: totalReturnAmount,
          direction: 'DEBT',
          paymentMethod: 'CÔNG NỢ',
          title: 'TRẢ HÀNG GIẢM NỢ: ${normalizedItems.map((i) => i.productName).join(', ')}',
          description: 'Giảm công nợ $customerName. Lý do: ${note ?? "Trả hàng"}',
          customerName: customerName,
          phone: customerPhone,
          productInfo: normalizedItems.map((i) => '${i.productName} x${i.quantity}').join(', '),
          referenceType: 'sales_return',
          referenceId: returnFirestoreId,
          createdBy: userName,
        );
      }

      // Always attempt debt reduction for the linked sale.
      // If no debt exists, _reduceDebt will no-op safely.
      await _reduceDebt(salesOrderFirestoreId, totalReturnAmount);

      // 4. Sync to Firestore
      await _syncReturnToFirestore(returnHeader, normalizedItems, returnId);

      // 5. Ghi nhật ký hệ thống
      await AuditService.logAction(
        action: 'sales_return',
        entityType: 'sales_return',
        entityId: returnFirestoreId,
        summary: 'Trả hàng: ${normalizedItems.map((i) => '${i.productName} x${i.quantity}').join(', ')} | KH: $customerName | ${MoneyUtils.formatVND(totalReturnAmount)} | $refundMethod',
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
    } finally {
      _activeReturnLocks.remove(lockKey);
    }
  }

  static String _itemKey(String? productImei, String productName) {
    final imei = (productImei ?? '').trim().toUpperCase();
    final isPhone = imei.isNotEmpty && !imei.startsWith('PKX') && imei != 'NO_IMEI';
    return isPhone ? imei : productName.trim().toUpperCase();
  }

  static Future<Map<String, int>> _buildSoldQtyMap({
    required int salesOrderId,
    required String? salesOrderFirestoreId,
  }) async {
    try {
      SaleOrder? sale;
      if (salesOrderFirestoreId != null && salesOrderFirestoreId.isNotEmpty) {
        sale = await _db.getSaleByFirestoreId(salesOrderFirestoreId);
      }

      if (sale == null && salesOrderId > 0) {
        final database = await _db.database;
        final rows = await database.query(
          'sales',
          where: 'id = ?',
          whereArgs: [salesOrderId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          sale = SaleOrder.fromMap(rows.first);
        }
      }

      if (sale == null) return <String, int>{};

      final names = sale.productNames.split(RegExp(r',\s*'));
      final imeis = sale.productImeis.split(RegExp(r',\s*'));
      final result = <String, int>{};
      for (var i = 0; i < names.length; i++) {
        final rawName = names[i].trim();
        if (rawName.isEmpty) continue;
        final rawImei = i < imeis.length ? imeis[i].trim() : '';

        var qty = 1;
        var cleanName = rawName;
        final qtyMatch = RegExp(r'^(.+?)\s+[xX](\d+)').firstMatch(rawName);
        if (qtyMatch != null) {
          cleanName = qtyMatch.group(1)!.trim();
          qty = int.tryParse(qtyMatch.group(2)!) ?? 1;
        }
        if (rawImei.toUpperCase().startsWith('PKX')) {
          qty = int.tryParse(rawImei.toUpperCase().replaceAll('PKX', '')) ?? qty;
        }

        final key = _itemKey(rawImei, cleanName);
        result[key] = (result[key] ?? 0) + qty;
      }
      return result;
    } catch (e) {
      debugPrint('❌ _buildSoldQtyMap error: $e');
      return <String, int>{};
    }
  }

  static Future<Map<String, int>> _getReturnedQtyMap({
    required int salesOrderId,
    required String? salesOrderFirestoreId,
  }) async {
    try {
      if (salesOrderId > 0) {
        return await _db.getReturnedQuantitiesForSale(salesOrderId);
      }
      if (salesOrderFirestoreId == null || salesOrderFirestoreId.isEmpty) {
        return <String, int>{};
      }
      final database = await _db.database;
      final rows = await database.rawQuery(
        '''
        SELECT
          CASE
            WHEN sri.productImei IS NOT NULL
                 AND TRIM(sri.productImei) != ''
                 AND UPPER(TRIM(sri.productImei)) != 'NO_IMEI'
                 AND UPPER(TRIM(sri.productImei)) NOT LIKE 'PKX%'
            THEN UPPER(TRIM(sri.productImei))
            ELSE UPPER(TRIM(sri.productName))
          END AS returnKey,
          SUM(sri.quantity) as totalQty
        FROM sales_return_items sri
        INNER JOIN sales_returns sr ON sr.id = sri.salesReturnId
        WHERE sr.salesOrderFirestoreId = ? AND sr.status != 'CANCELLED'
        GROUP BY returnKey
      ''',
        [salesOrderFirestoreId],
      );
      final map = <String, int>{};
      for (final row in rows) {
        final key = (row['returnKey'] as String?)?.trim().toUpperCase() ?? '';
        if (key.isEmpty) continue;
        map[key] = (map[key] ?? 0) + ((row['totalQty'] as num?)?.toInt() ?? 0);
      }
      return map;
    } catch (e) {
      debugPrint('❌ _getReturnedQtyMap error: $e');
      return <String, int>{};
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

      if (product == null && item.productId != null && item.productId! > 0) {
        final database = await _db.database;
        final rows = await database.query(
          'products',
          where: 'id = ?',
          whereArgs: [item.productId],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          product = Product.fromMap(rows.first);
        }
      }

      if (product == null && item.productFirestoreId != null) {
        product = await _db.getProductByFirestoreId(item.productFirestoreId!);
      }

      if (product == null) {
        product = await _db.getProductByName(item.productName);
      }
      product ??= await _db.getProductByNameFlexible(item.productName);

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
        throw Exception('Không tìm thấy sản phẩm để hoàn kho: ${item.productName}');
      }
    } catch (e) {
      debugPrint('❌ _restoreStock error: $e');
      rethrow;
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
            entityId: item.id ?? item.salesReturnId!,
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

