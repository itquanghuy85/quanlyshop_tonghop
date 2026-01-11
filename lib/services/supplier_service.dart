import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/supplier_model.dart';
import '../models/supplier_import_history_model.dart';
import '../models/supplier_product_prices_model.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';

class SupplierService {
  final db = DBHelper();

  // Supplier CRUD
  Future<List<Supplier>> getSuppliers() async {
    final shopId = await UserService.getCurrentShopId();
    debugPrint('SupplierService.getSuppliers: shopId=$shopId');

    final data = await db.getSuppliers();
    debugPrint('SupplierService.getSuppliers: local data count=${data.length}');
    final List<Supplier> suppliers = [];

    // Super admin: return all suppliers without filtering, nhưng loại bỏ deleted
    if (shopId == null) {
      debugPrint('SupplierService.getSuppliers: super admin mode, returning all');
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
      debugPrint('SupplierService.getSuppliers: checking supplier ${s['name']}, shopId=$supplierShopId');

      // Normalize empty or missing shopId to current shop
      if (supplierShopId == null || supplierShopId.isEmpty) {
        final id = s['id'] as int?;
        if (id != null) {
          await db.updateSupplier(id, {'shopId': shopId});
          supplierShopId = shopId;
          debugPrint('SupplierService.getSuppliers: normalized shopId for ${s['name']}');
        }
      }

      // Include supplier if shopId matches OR if we just normalized it
      if (supplierShopId == shopId) {
        suppliers.add(Supplier.fromMap({...s, 'shopId': supplierShopId}));
      }
    }
    debugPrint('SupplierService.getSuppliers: after filter count=${suppliers.length}');

    // Fallback: if local DB is empty, pull from Firestore and cache locally
    if (suppliers.isEmpty) {
      try {
        Query<Map<String, dynamic>> query = FirebaseFirestore.instance.collection('suppliers');
        query = query.where('shopId', isEqualTo: shopId);
              final snapshot = await query.get();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final mapped = {
            ...data,
            'firestoreId': doc.id,
            'shopId': data['shopId'] ?? shopId ?? '',
            'active': (data['active'] == 1 || data['active'] == true) ? 1 : 0,
            'favorite': (data['favorite'] == 1 || data['favorite'] == true) ? 1 : 0,
            'createdAt': data['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
            'updatedAt': data['updatedAt'] ?? DateTime.now().millisecondsSinceEpoch,
          };
          // Remove null id to let DB auto-generate
          mapped.remove('id');
          // Cache locally for offline use and get the local ID
          final localId = await db.insertSupplier(mapped);
          suppliers.add(Supplier.fromMap({...mapped, 'id': localId}));
        }
      } catch (_) {}
    }

    return suppliers;
  }

  Future<Supplier?> addSupplier(Supplier supplier) async {
    final shopId = await UserService.getCurrentShopId();
    debugPrint('SupplierService.addSupplier: shopId=$shopId, name=${supplier.name}');
    
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
        final firestoreId = await FirestoreService.addSupplier({...supplierMap, 'id': id});
        if (firestoreId != null) {
          await db.updateSupplier(id, {'firestoreId': firestoreId});
          debugPrint('SupplierService.addSupplier: firestoreId=$firestoreId');
          return supplier.copyWith(id: id, firestoreId: firestoreId, shopId: shopId ?? '');
        }
      } catch (e) {
        debugPrint('SupplierService.addSupplier: Firestore error $e');
      }
      // Return supplier even if Firestore fails
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
      return true;
    }
    return false;
  }

  Future<bool> deleteSupplier(int supplierId, {String? firestoreId}) async {
    // Lấy firestoreId nếu chưa có
    String? fsId = firestoreId;
    if (fsId == null) {
      final suppliers = await db.getSuppliers();
      final supplier = suppliers.firstWhere(
        (s) => s['id'] == supplierId,
        orElse: () => {},
      );
      fsId = supplier['firestoreId'] as String?;
    }
    
    // HARD DELETE local: xóa hoàn toàn khỏi local DB
    final localDb = await db.database;
    final result = await localDb.delete(
      'suppliers',
      where: 'id = ?',
      whereArgs: [supplierId],
    );
    debugPrint('SupplierService.deleteSupplier: deleted $result rows for id=$supplierId');
    
    if (result > 0) {
      // Xóa trên Firestore nếu có firestoreId
      if (fsId != null && fsId.isNotEmpty) {
        await FirestoreService.deleteSupplier(fsId);
        debugPrint('SupplierService.deleteSupplier: deleted from Firestore fsId=$fsId');
      }
      return true;
    }
    return false;
  }

  // Supplier Import History
  Future<List<SupplierImportHistory>> getSupplierImportHistory(String supplierId) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getSupplierImportHistory(int.parse(supplierId));
    return data
        .where((h) => h['shopId'] == shopId)
        .map((h) => SupplierImportHistory.fromMap(h))
        .toList();
  }

  Future<SupplierImportHistory?> addSupplierImportHistory(SupplierImportHistory history) async {
    final historyMap = history.toMap();
    historyMap['shopId'] = await UserService.getCurrentShopId();
    historyMap['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    historyMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insertSupplierImportHistory(historyMap);
    if (id > 0) {
      final firestoreId = await FirestoreService.addSupplierImportHistory(historyMap);
      if (firestoreId != null) {
        await db.updateSupplierImportHistory(id, {'firestoreId': firestoreId});
        return history.copyWith(id: id);
      }
    }
    return null;
  }

  // Supplier Product Prices
  Future<List<SupplierProductPrices>> getSupplierProductPrices(String supplierId) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getSupplierProductPrices(int.parse(supplierId));
    return data
        .where((p) => p['shopId'] == shopId)
        .map((p) => SupplierProductPrices.fromMap(p))
        .toList();
  }

  Future<SupplierProductPrices?> addSupplierProductPrices(SupplierProductPrices prices) async {
    final pricesMap = prices.toMap();
    pricesMap['shopId'] = await UserService.getCurrentShopId();
    pricesMap['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    pricesMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insertSupplierProductPrices(pricesMap);
    if (id > 0) {
      final firestoreId = await FirestoreService.addSupplierProductPrices(pricesMap);
      if (firestoreId != null) {
        await db.updateSupplierProductPrices(id, {'firestoreId': firestoreId});
        return prices.copyWith(id: id);
      }
    }
    return null;
  }

  // Statistics
  Future<Map<String, dynamic>> getSupplierStatistics(String supplierId) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getSupplierStatistics(supplierId, shopId!);

    double totalPaid = 0;
    double totalOwed = 0;
    int totalImports = 0;
    double totalImportValue = 0;

    // Calculate from payments
    final payments = await db.getSupplierPayments(int.parse(supplierId));
    for (var payment in payments.where((p) => p['shopId'] == shopId)) {
      totalPaid += payment['amount'] ?? 0;
    }

    // Calculate from import history
    final imports = await db.getSupplierImportHistory(int.parse(supplierId));
    for (var import in imports.where((i) => i['shopId'] == shopId)) {
      totalImports++;
      totalImportValue += import['totalCost'] ?? 0;
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