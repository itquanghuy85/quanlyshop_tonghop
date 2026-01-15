import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/stock_entry_model.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';

/// Service quản lý phiếu nhập kho (Staging Inventory)
class StockEntryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  static const String _collection = 'stock_entries';
  
  // === HELPER METHODS ===
  void _showError(String message) {
    NotificationService.showSnackBar(message, color: Colors.red);
  }
  
  void _showSuccess(String message) {
    NotificationService.showSnackBar(message, color: Colors.green);
  }
  
  // === CRUD OPERATIONS ===
  
  /// Tạo phiếu nhập kho mới (DRAFT hoặc QUICK)
  Future<StockEntry?> createEntry(StockEntry entry) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) {
        _showError('Không tìm thấy thông tin shop');
        return null;
      }
      
      final userId = _auth.currentUser?.uid;
      
      // Tính tổng giá vốn
      final totalCost = entry.items.fold<double>(
        0, (total, item) => total + item.totalCost,
      );
      
      final newEntry = entry.copyWith(
        shopId: shopId,
        totalCost: totalCost > 0 ? totalCost : null,
        createdBy: userId,
        createdAt: DateTime.now(),
      );
      
      final docRef = await _firestore
          .collection(_collection)
          .add(newEntry.toMap());
      
      return newEntry.copyWith(firestoreId: docRef.id);
    } catch (e) {
      _showError('Lỗi tạo phiếu: $e');
      return null;
    }
  }
  
  /// Cập nhật phiếu (chỉ cho DRAFT)
  Future<bool> updateEntry(StockEntry entry) async {
    try {
      if (entry.firestoreId == null) {
        _showError('Không tìm thấy ID phiếu');
        return false;
      }
      
      if (entry.locked || entry.isConfirmed) {
        _showError('Phiếu đã khóa, không thể sửa');
        return false;
      }
      
      // Tính lại tổng giá vốn
      final totalCost = entry.items.fold<double>(
        0, (total, item) => total + item.totalCost,
      );
      
      final updatedEntry = entry.copyWith(
        totalCost: totalCost > 0 ? totalCost : null,
        updatedAt: DateTime.now(),
      );
      
      await _firestore
          .collection(_collection)
          .doc(entry.firestoreId)
          .update(updatedEntry.toMap());
      
      return true;
    } catch (e) {
      _showError('Lỗi cập nhật: $e');
      return false;
    }
  }
  
  /// Hủy phiếu (chỉ cho DRAFT)
  Future<bool> cancelEntry(String entryId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(entryId).get();
      if (!doc.exists) {
        _showError('Không tìm thấy phiếu');
        return false;
      }
      
      final entry = StockEntry.fromMap(doc.data()!, docId: doc.id);
      if (entry.locked || entry.isConfirmed) {
        _showError('Phiếu đã khóa, không thể hủy');
        return false;
      }
      
      await _firestore.collection(_collection).doc(entryId).update({
        'status': 'cancelled', // lowercase để match với toMap()
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      _showSuccess('Đã hủy phiếu');
      return true;
    } catch (e) {
      _showError('Lỗi hủy phiếu: $e');
      return false;
    }
  }
  
  /// Lấy phiếu theo ID
  Future<StockEntry?> getEntry(String entryId) async {
    try {
      final doc = await _firestore.collection(_collection).doc(entryId).get();
      if (!doc.exists) return null;
      return StockEntry.fromMap(doc.data()!, docId: doc.id);
    } catch (e) {
      return null;
    }
  }
  
  /// Lấy danh sách phiếu DRAFT (hàng chờ xác nhận)
  Future<List<StockEntry>> getPendingEntries() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];
      
      final query = await _firestore
          .collection(_collection)
          .where('shopId', isEqualTo: shopId)
          .where('status', isEqualTo: 'draft') // lowercase để match với toMap()
          .orderBy('createdAt', descending: true)
          .get();
      
      return query.docs
          .map((doc) => StockEntry.fromMap(doc.data(), docId: doc.id))
          .toList();
    } catch (e) {
      debugPrint('Error getting pending entries: $e');
      return [];
    }
  }
  
  /// Đếm số phiếu chờ xác nhận
  Future<int> getPendingCount() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return 0;
      
      final query = await _firestore
          .collection(_collection)
          .where('shopId', isEqualTo: shopId)
          .where('status', isEqualTo: 'draft') // lowercase để match với toMap()
          .count()
          .get();
      
      return query.count ?? 0;
    } catch (e) {
      return 0;
    }
  }
  
  /// Lấy danh sách phiếu đã xác nhận
  Future<List<StockEntry>> getConfirmedEntries({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 50,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];
      
      Query query = _firestore
          .collection(_collection)
          .where('shopId', isEqualTo: shopId)
          .where('status', isEqualTo: 'confirmed'); // lowercase để match với toMap()
      
      if (startDate != null) {
        query = query.where('confirmedAt', isGreaterThanOrEqualTo: startDate);
      }
      if (endDate != null) {
        query = query.where('confirmedAt', isLessThanOrEqualTo: endDate);
      }
      
      final result = await query
          .orderBy('confirmedAt', descending: true)
          .limit(limit)
          .get();
      
      return result.docs
          .map((doc) => StockEntry.fromMap(
              doc.data() as Map<String, dynamic>, docId: doc.id))
          .toList();
    } catch (e) {
      return [];
    }
  }
  
  // === XÁC NHẬN NHẬP KHO (ATOMIC TRANSACTION) ===
  
  /// Xác nhận nhập kho - PHẢI atomic
  /// Tạo products + financial_activity + supplier_debt (nếu công nợ)
  Future<bool> confirmEntry(String entryId) async {
    try {
      return await _firestore.runTransaction((transaction) async {
        // 1. Lấy phiếu nhập
        final entryRef = _firestore.collection(_collection).doc(entryId);
        final entryDoc = await transaction.get(entryRef);
        
        if (!entryDoc.exists) {
          throw Exception('Không tìm thấy phiếu');
        }
        
        final entry = StockEntry.fromMap(entryDoc.data()!, docId: entryDoc.id);
        
        // 2. Validate
        if (entry.status != StockEntryStatus.draft) {
          throw Exception('Phiếu đã được xử lý');
        }
        
        if (!entry.canConfirm) {
          throw Exception('Chưa đủ thông tin: ${entry.missingInfo.join(", ")}');
        }
        
        // 3. Tạo products từ items
        final userId = _auth.currentUser?.uid;
        
        for (final item in entry.items) {
          final productRef = _firestore.collection('products').doc();
          
          // Tạo tên sản phẩm đầy đủ
          String productName = item.name;
          if (item.productType == 'DIEN_THOAI') {
            final parts = <String>[item.name];
            if (item.capacity != null && item.capacity!.isNotEmpty) {
              parts.add(item.capacity!);
            }
            if (item.color != null && item.color!.isNotEmpty) {
              parts.add(item.color!);
            }
            productName = parts.join(' ');
          }
          
          // Tạo chi tiết
          String detail = '';
          if (item.productType == 'DIEN_THOAI') {
            final detailParts = <String>[];
            if (item.capacity != null && item.capacity!.isNotEmpty) {
              detailParts.add(item.capacity!);
            }
            if (item.color != null && item.color!.isNotEmpty) {
              detailParts.add(item.color!);
            }
            if (item.condition != null && item.condition!.isNotEmpty) {
              detailParts.add(item.condition!);
            }
            detail = detailParts.join(' - ');
          }
          
          transaction.set(productRef, {
            'name': productName,
            'detail': detail,
            'type': item.productType,
            'imei': item.imei ?? '',
            'brand': item.brand ?? '',
            'model': item.model ?? '',
            'cost': item.cost ?? 0,
            'price': item.price ?? 0,
            'quantity': item.quantity,
            'supplier': entry.supplierName ?? '',
            'supplierId': entry.supplierId,
            'status': 1, // Trong kho
            'stockEntryId': entryId,
            'shopId': entry.shopId,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'deleted': false,
          });
        }
        
        // 4. Ghi financial_activity
        final totalCost = entry.calculatedTotalCost;
        final activityRef = _firestore.collection('financial_activities').doc();
        
        // Xác định loại giao dịch dựa trên payment method
        String direction = 'OUT'; // Chi tiền mua hàng
        if (entry.paymentMethod == 'CÔNG NỢ') {
          direction = 'DEBT'; // Ghi nợ, không chi tiền ngay
        }
        
        transaction.set(activityRef, {
          'type': 'STOCK_IN',
          'subType': 'NHAP_KHO',
          'amount': totalCost,
          'direction': direction,
          'referenceId': entryId,
          'referenceType': 'stock_entry',
          'description': 'Nhập kho: ${entry.itemCount} sản phẩm từ ${entry.supplierName}',
          'paymentMethod': entry.paymentMethod,
          'supplierId': entry.supplierId,
          'supplierName': entry.supplierName,
          'shopId': entry.shopId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': userId,
        });
        
        // 5. Cập nhật công nợ NCC (nếu ghi nợ)
        if (entry.paymentMethod == 'CÔNG NỢ' && entry.supplierId != null) {
          final debtRef = _firestore.collection('supplier_debts').doc();
          transaction.set(debtRef, {
            'supplierId': entry.supplierId,
            'supplierName': entry.supplierName,
            'amount': totalCost,
            'remainingAmount': totalCost,
            'type': 'STOCK_IN',
            'referenceId': entryId,
            'status': 'PENDING',
            'shopId': entry.shopId,
            'createdAt': FieldValue.serverTimestamp(),
            'createdBy': userId,
            'notes': 'Nhập kho: ${entry.itemCount} sản phẩm',
          });
        }
        
        // 6. Cập nhật trạng thái phiếu
        transaction.update(entryRef, {
          'status': 'confirmed', // lowercase để match với Firestore rules
          'locked': true,
          'totalCost': totalCost,
          'confirmedAt': FieldValue.serverTimestamp(),
          'confirmedBy': userId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        return true;
      });
    } catch (e) {
      _showError('Lỗi xác nhận: $e');
      return false;
    }
  }
  
  /// Nhập nhanh - tạo và xác nhận ngay trong 1 bước
  Future<bool> quickStockIn(StockEntry entry) async {
    try {
      // Validate đủ thông tin
      if (!entry.canConfirm) {
        _showError('Chưa đủ thông tin: ${entry.missingInfo.join(", ")}');
        return false;
      }
      
      // Tạo entry với type = QUICK
      final quickEntry = entry.copyWith(
        entryType: StockEntryType.quick,
      );
      
      final created = await createEntry(quickEntry);
      if (created == null || created.firestoreId == null) {
        return false;
      }
      
      // Xác nhận ngay
      final confirmed = await confirmEntry(created.firestoreId!);
      if (!confirmed) {
        // Nếu confirm fail, hủy entry đã tạo
        await cancelEntry(created.firestoreId!);
        return false;
      }
      
      _showSuccess('Đã nhập kho thành công');
      return true;
    } catch (e) {
      _showError('Lỗi nhập kho: $e');
      return false;
    }
  }
  
  /// Lưu tạm - chỉ tạo DRAFT
  Future<StockEntry?> saveDraft(StockEntry entry) async {
    try {
      final draftEntry = entry.copyWith(
        status: StockEntryStatus.draft,
        entryType: StockEntryType.staging,
        locked: false,
      );
      
      final created = await createEntry(draftEntry);
      if (created != null) {
        _showSuccess('Đã lưu tạm thành công');
      }
      return created;
    } catch (e) {
      _showError('Lỗi lưu tạm: $e');
      return null;
    }
  }
  
  // === STATISTICS ===
  
  /// Thống kê hàng chờ xác nhận
  Future<Map<String, dynamic>> getPendingStats() async {
    try {
      final entries = await getPendingEntries();
      
      int totalItems = 0;
      int phoneCount = 0;
      int accessoryCount = 0;
      int partsCount = 0;
      double estimatedValue = 0;
      int oldestDays = 0;
      
      for (final entry in entries) {
        for (final item in entry.items) {
          totalItems += item.quantity;
          
          switch (item.productType) {
            case 'DIEN_THOAI':
              phoneCount += item.quantity;
              break;
            case 'PHU_KIEN':
              accessoryCount += item.quantity;
              break;
            case 'LINH_KIEN':
              partsCount += item.quantity;
              break;
          }
          
          estimatedValue += item.totalCost;
        }
        
        if (entry.daysSinceCreated > oldestDays) {
          oldestDays = entry.daysSinceCreated;
        }
      }
      
      return {
        'total': entries.length,
        'totalItems': totalItems,
        'phone': phoneCount,
        'accessory': accessoryCount,
        'part': partsCount,
        'estimatedValue': estimatedValue,
        'oldestDays': oldestDays,
      };
    } catch (e) {
      return {};
    }
  }
  
  // === STREAM (REALTIME) ===
  
  /// Stream danh sách hàng chờ
  Stream<List<StockEntry>> watchPendingEntries() async* {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      yield [];
      return;
    }
    
    yield* _firestore
        .collection(_collection)
        .where('shopId', isEqualTo: shopId)
        .where('status', isEqualTo: 'draft') // lowercase để match với toMap()
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => StockEntry.fromMap(doc.data(), docId: doc.id))
            .toList());
  }
  
  /// Stream đếm số hàng chờ
  Stream<int> watchPendingCount() async* {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      yield 0;
      return;
    }
    
    yield* _firestore
        .collection(_collection)
        .where('shopId', isEqualTo: shopId)
        .where('status', isEqualTo: 'draft') // lowercase để match với toMap()
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
}
