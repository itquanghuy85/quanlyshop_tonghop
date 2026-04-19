import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/supplier_model.dart';
import '../models/supplier_import_history_model.dart';
import '../models/supplier_product_prices_model.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../services/encryption_service.dart';
import '../services/event_bus.dart';

class SupplierService {
  final db = DBHelper();

  /// Default warehouse supplier name
  static const String khoTongName = 'KHO TỔNG';

  /// Flag to only run dedup once per session
  static bool _dedupDone = false;

  Future<void> _recoverEncryptedSupplierNames(
    List<Map<String, dynamic>> rows,
  ) async {
    for (final row in rows) {
      final rawName = row['name'];
      if (rawName is! String || rawName.isEmpty) continue;
      if (!rawName.startsWith('ENC:') && !rawName.startsWith('ENC2:')) continue;

      final recovered = EncryptionService.decrypt(rawName).trim();
      if (recovered.isEmpty || recovered == rawName) continue;

      row['name'] = recovered;
      final id = row['id'];
      if (id is int) {
        await db.updateSupplier(id, {
          'name': recovered,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        });
      }
    }
  }

  /// Ensure KHO TỔNG (central warehouse) supplier exists for the current shop.
  /// Called when supplier list is loaded or stock in view is opened.
  Future<void> ensureDefaultSuppliers() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;

      final suppliers = await db.getSuppliers();
      final hasKhoTong = suppliers.any(
        (s) =>
            s['name']?.toString().toUpperCase().trim() == khoTongName &&
            s['shopId'] == shopId &&
            (s['deleted'] != 1 && s['deleted'] != true),
      );

      if (!hasKhoTong) {
        debugPrint('SupplierService: Creating default KHO TỔNG supplier');
        final now = DateTime.now().millisecondsSinceEpoch;
        final supplierMap = {
          'name': khoTongName,
          'phone': '',
          'address': '',
          'note': 'Kho tổng - Nhà cung cấp mặc định của cửa hàng',
          'active': 1,
          'favorite': 1,
          'type': 'warehouse',
          'shopId': shopId,
          'createdAt': now,
          'updatedAt': now,
          'isSynced': 0,
        };
        final id = await db.insertSupplier(supplierMap);
        if (id > 0) {
          // Sync to Firestore
          try {
            final firestoreId = await FirestoreService.addSupplier({
              ...supplierMap,
              'id': id,
            });
            if (firestoreId != null) {
              await db.updateSupplier(id, {
                'firestoreId': firestoreId,
                'isSynced': 1,
              });
            }
          } catch (e) {
            debugPrint(
              'SupplierService: Failed to sync KHO TỔNG to Firestore: $e',
            );
          }
        }
        debugPrint('SupplierService: KHO TỔNG created with id=$id');
      }
    } catch (e) {
      debugPrint('SupplierService.ensureDefaultSuppliers error: $e');
    }
  }

  // Supplier CRUD
  Future<List<Supplier>> getSuppliers() async {
    // Ensure KHO TỔNG exists before listing
    await ensureDefaultSuppliers();

    // Dọn dẹp NCC trùng lặp (chỉ chạy 1 lần mỗi session)
    if (!_dedupDone) {
      _dedupDone = true;
      await db.deduplicateSuppliers();
    }

    final shopId = await UserService.getCurrentShopId();
    debugPrint('SupplierService.getSuppliers: shopId=$shopId');

    final data = await db.getSuppliers();
    await _recoverEncryptedSupplierNames(data);
    debugPrint('SupplierService.getSuppliers: local data count=${data.length}');
    final List<Supplier> suppliers = [];

    // Super admin: return all suppliers without filtering, nhưng loại bỏ deleted
    if (shopId == null) {
      debugPrint(
        'SupplierService.getSuppliers: super admin mode, returning all',
      );
      return data
          .where((s) => s['deleted'] != 1 && s['deleted'] != true)
          .map((s) => Supplier.fromMap({...s, 'shopId': s['shopId'] ?? ''}))
          .toList();
    }

    for (final s in data) {
      // Bỏ qua các supplier đã bị xóa (soft delete)
      if (s['deleted'] == 1 || s['deleted'] == true) {
        continue;
      }

      String? supplierShopId = s['shopId'] as String?;
      final firestoreId = (s['firestoreId'] as String?)?.trim();
      final hasFirestoreId = firestoreId != null && firestoreId.isNotEmpty;
      debugPrint(
        'SupplierService.getSuppliers: checking supplier ${s['name']}, shopId=$supplierShopId',
      );

      // Chỉ normalize local-only records; bản có firestoreId mà thiếu shopId có thể là rác legacy/cross-shop.
      if (supplierShopId == null || supplierShopId.isEmpty) {
        final id = s['id'] as int?;
        if (id != null && !hasFirestoreId) {
          await db.updateSupplier(id, {'shopId': shopId});
          supplierShopId = shopId;
          debugPrint(
            'SupplierService.getSuppliers: normalized shopId for ${s['name']}',
          );
        } else {
          debugPrint(
            'SupplierService.getSuppliers: skip supplier missing shopId but has firestoreId=${s['firestoreId']}',
          );
          continue;
        }
      }

      // Include supplier if shopId matches OR if we just normalized it
      if (supplierShopId == shopId) {
        suppliers.add(Supplier.fromMap({...s, 'shopId': supplierShopId}));
      }
    }
    debugPrint(
      'SupplierService.getSuppliers: after filter count=${suppliers.length}',
    );

    // Fallback: if local DB is empty, pull from Firestore and cache locally
    if (suppliers.isEmpty) {
      try {
        Query<Map<String, dynamic>> query = FirebaseFirestore.instance
            .collection('suppliers');
        query = query.where('shopId', isEqualTo: shopId);
        final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          var data = doc.data();
          data = EncryptionService.decryptMap(data);
          if (data['deleted'] == true || data['deleted'] == 1) {
            continue;
          }

          String resolvedName = (data['name'] ?? '').toString();
          if (resolvedName.startsWith('ENC:') ||
              resolvedName.startsWith('ENC2:')) {
            final recovered = EncryptionService.decrypt(resolvedName);
            if (recovered.isNotEmpty && recovered != resolvedName) {
              resolvedName = recovered;
            }
          }

          final mapped = {
            ...data,
            'name': resolvedName,
            'firestoreId': doc.id,
            'shopId': data['shopId'] ?? shopId ?? '',
            'active': (data['active'] == 1 || data['active'] == true) ? 1 : 0,
            'favorite': (data['favorite'] == 1 || data['favorite'] == true)
                ? 1
                : 0,
            'createdAt':
                data['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
            'updatedAt':
                data['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
          };
          // Remove null id to let DB auto-generate
          mapped.remove('id');
          // Cache locally for offline use — use upsert to avoid duplicates
          await db.upsertSupplier(mapped);
          final cached = await db.getSuppliers();
          final local = cached.firstWhere(
            (s) => s['firestoreId'] == doc.id,
            orElse: () => mapped,
          );
          suppliers.add(Supplier.fromMap({...local, 'shopId': shopId!}));
        }
        debugPrint(
          'SupplierService.getSuppliers: Firestore fallback found ${snapshot.docs.length} suppliers',
        );
      } catch (e) {
        debugPrint(
          'SupplierService.getSuppliers: Firestore fallback error: $e',
        );
      }
    }

    return suppliers;
  }

  Future<Supplier?> addSupplier(Supplier supplier) async {
    final shopId = await UserService.getCurrentShopId();
    debugPrint(
      'SupplierService.addSupplier: shopId=$shopId, name=${supplier.name}',
    );

    // Kiểm tra NCC trùng tên trước khi thêm
    final existingSuppliers = await db.getSuppliers();
    final duplicate = existingSuppliers
        .where(
          (s) =>
              (s['name'] as String?)?.toUpperCase() ==
                  supplier.name.toUpperCase() &&
              s['shopId'] == shopId &&
              (s['deleted'] != 1 && s['deleted'] != true),
        )
        .toList();
    if (duplicate.isNotEmpty) {
      debugPrint(
        'SupplierService.addSupplier: duplicate found for "${supplier.name}", returning existing',
      );
      return Supplier.fromMap({...duplicate.first, 'shopId': shopId ?? ''});
    }

    final supplierMap = supplier.toMap();
    supplierMap['shopId'] = shopId ?? '';
    supplierMap['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    supplierMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    supplierMap['favorite'] = supplier.favorite ? 1 : 0;
    supplierMap['active'] = supplier.active ? 1 : 0;
    // Remove null id to let DB auto-generate
    supplierMap.remove('id');

    final id = await db.insertSupplier(supplierMap);
    debugPrint('SupplierService.addSupplier: local insert id=$id');

    if (id > 0) {
      // Try Firestore but don't fail if it doesn't work
      try {
        final firestoreId = await FirestoreService.addSupplier({
          ...supplierMap,
          'id': id,
        });
        if (firestoreId != null) {
          await db.updateSupplier(id, {'firestoreId': firestoreId});
          EventBus().emit('suppliers_changed');
          debugPrint('SupplierService.addSupplier: firestoreId=$firestoreId');
          return supplier.copyWith(
            id: id,
            firestoreId: firestoreId,
            shopId: shopId ?? '',
          );
        }
      } catch (e) {
        debugPrint('SupplierService.addSupplier: Firestore error $e');
      }
      // Return supplier even if Firestore fails
      EventBus().emit('suppliers_changed');
      return supplier.copyWith(id: id, shopId: shopId ?? '');
    }
    return null;
  }

  Future<bool> updateSupplier(Supplier supplier) async {
    final supplierMap = supplier.toMap();
    supplierMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    supplierMap['favorite'] = supplier.favorite ? 1 : 0;
    if (supplier.firestoreId != null) {
      supplierMap['firestoreId'] = supplier.firestoreId;
    }

    final result = await db.updateSupplier(supplier.id!, supplierMap);
    if (result > 0) {
      await FirestoreService.updateSupplier(supplierMap);
      EventBus().emit('suppliers_changed');
      return true;
    }
    return false;
  }

  Future<bool> deleteSupplier(
    int? supplierId, {
    String? firestoreId,
    String? supplierName,
  }) async {
    // Lấy firestoreId nếu chưa có
    String? fsId = firestoreId?.trim();
    String? resolvedName = supplierName?.trim();

    if ((fsId == null || fsId.isEmpty) ||
        (resolvedName == null || resolvedName.isEmpty)) {
      final suppliers = await db.getSuppliers();
      Map<String, dynamic> supplier = {};
      if (supplierId != null) {
        supplier = suppliers.firstWhere(
          (s) => s['id'] == supplierId,
          orElse: () => {},
        );
      }
      if (supplier.isEmpty && fsId != null && fsId.isNotEmpty) {
        supplier = suppliers.firstWhere(
          (s) => (s['firestoreId'] as String?) == fsId,
          orElse: () => {},
        );
      }
      fsId = fsId ?? supplier['firestoreId'] as String?;
      resolvedName = resolvedName ?? (supplier['name'] as String?);
      supplierId = supplierId ?? supplier['id'] as int?;
    }

    // HARD DELETE local với fallback nhiều khóa để xử lý dữ liệu legacy lỗi id.
    final localDb = await db.database;
    int result = 0;
    if (supplierId != null) {
      result = await localDb.delete(
        'suppliers',
        where: 'id = ?',
        whereArgs: [supplierId],
      );
    }
    if (result == 0 && fsId != null && fsId.isNotEmpty) {
      result = await localDb.delete(
        'suppliers',
        where: 'firestoreId = ?',
        whereArgs: [fsId],
      );
    }
    if (result == 0 && resolvedName != null && resolvedName.isNotEmpty) {
      final shopId = await UserService.getCurrentShopId();
      if (shopId != null && shopId.isNotEmpty) {
        result = await localDb.delete(
          'suppliers',
          where: 'name = ? AND shopId = ?',
          whereArgs: [resolvedName, shopId],
        );
      }
    }
    debugPrint(
      'SupplierService.deleteSupplier: deleted $result rows for id=$supplierId fsId=$fsId name=$resolvedName',
    );

    if (result > 0) {
      // Xóa trên Firestore nếu có firestoreId
      if (fsId != null && fsId.isNotEmpty) {
        await FirestoreService.deleteSupplier(fsId);
        debugPrint(
          'SupplierService.deleteSupplier: deleted from Firestore fsId=$fsId',
        );
      }
      EventBus().emit('suppliers_changed');
      return true;
    }
    return false;
  }

  // Supplier Import History
  Future<List<SupplierImportHistory>> getSupplierImportHistory(
    String supplierId, {
    String? supplierName,
  }) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getSupplierImportHistory(
      int.parse(supplierId),
      supplierName: supplierName,
    );
    return data
        .where((h) => h['shopId'] == shopId)
        .map((h) => SupplierImportHistory.fromMap(h))
        .toList();
  }

  Future<SupplierImportHistory?> addSupplierImportHistory(
    SupplierImportHistory history,
  ) async {
    final historyMap = history.toMap();
    historyMap['shopId'] = await UserService.getCurrentShopId();
    historyMap['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    historyMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insertSupplierImportHistory(historyMap);
    if (id > 0) {
      final firestoreId = await FirestoreService.addSupplierImportHistory(
        historyMap,
      );
      if (firestoreId != null) {
        await db.updateSupplierImportHistory(id, {'firestoreId': firestoreId});
        return history.copyWith(id: id);
      }
    }
    return null;
  }

  // Supplier Product Prices
  Future<List<SupplierProductPrices>> getSupplierProductPrices(
    String supplierId,
  ) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getSupplierProductPrices(int.parse(supplierId));
    return data
        .where((p) => p['shopId'] == shopId)
        .map((p) => SupplierProductPrices.fromMap(p))
        .toList();
  }

  Future<SupplierProductPrices?> addSupplierProductPrices(
    SupplierProductPrices prices,
  ) async {
    final pricesMap = prices.toMap();
    pricesMap['shopId'] = await UserService.getCurrentShopId();
    pricesMap['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    pricesMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insertSupplierProductPrices(pricesMap);
    if (id > 0) {
      final firestoreId = await FirestoreService.addSupplierProductPrices(
        pricesMap,
      );
      if (firestoreId != null) {
        await db.updateSupplierProductPrices(id, {'firestoreId': firestoreId});
        return prices.copyWith(id: id);
      }
    }
    return null;
  }

  // Statistics
  Future<Map<String, dynamic>> getSupplierStatistics(
    String supplierId, {
    String? supplierName,
  }) async {
    final shopId = await UserService.getCurrentShopId();

    double totalPaid = 0;
    double totalOwed = 0;
    int totalImports = 0;
    double totalImportValue = 0;

    // Calculate from payments
    final payments = await db.getSupplierPayments(int.parse(supplierId));
    for (var payment in payments.where((p) => p['shopId'] == shopId)) {
      totalPaid += payment['amount'] ?? 0;
    }

    // Calculate from import history - truyền cả supplierName để tìm theo tên nếu supplierId không khớp
    final imports = await db.getSupplierImportHistory(
      int.parse(supplierId),
      supplierName: supplierName,
    );
    for (var import in imports.where((i) => i['shopId'] == shopId)) {
      totalImports++;
      // FIX: Field name is 'totalAmount', not 'totalCost'
      totalImportValue += import['totalAmount'] ?? import['totalCost'] ?? 0;
    }

    totalOwed = totalImportValue - totalPaid;

    return {
      'totalPaid': totalPaid,
      'totalOwed': totalOwed,
      'totalImports': totalImports,
      'totalImportValue': totalImportValue,
    };
  }
}
