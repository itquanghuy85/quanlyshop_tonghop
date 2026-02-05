import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/stock_entry_model.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../services/sync_orchestrator.dart';
import '../data/db_helper.dart';

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
        0,
        (total, item) => total + item.totalCost,
      );

      final newEntry = entry.copyWith(
        shopId: shopId,
        totalCost: totalCost > 0 ? totalCost : null,
        createdBy: userId,
        createdAt: DateTime.now(),
      );

      final mapData = newEntry.toMap();
      debugPrint(
        '📦 createEntry: status=${mapData['status']}, entryType=${mapData['entryType']}, shopId=$shopId',
      );
      debugPrint('📦 createEntry map: $mapData');

      final docRef = await _firestore.collection(_collection).add(mapData);

      debugPrint('✅ createEntry SUCCESS: docId=${docRef.id}');
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
        0,
        (total, item) => total + item.totalCost,
      );

      final updatedEntry = entry.copyWith(
        totalCost: totalCost > 0 ? totalCost : null,
        updatedAt: DateTime.now(),
      );

      // Dùng forUpdate: true để tránh ghi đè createdAt
      final updateMap = updatedEntry.toMap(forUpdate: true);
      debugPrint('📝 updateEntry: firestoreId=${entry.firestoreId}');
      debugPrint('📝 updateEntry map keys: ${updateMap.keys.toList()}');
      debugPrint('📝 updateEntry map: $updateMap');

      await _firestore
          .collection(_collection)
          .doc(entry.firestoreId)
          .update(updateMap);

      _showSuccess('Đã cập nhật phiếu');
      return true;
    } catch (e) {
      debugPrint('❌ updateEntry error: $e');
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
      debugPrint('📋 getPendingEntries: shopId=$shopId');
      if (shopId == null) return [];

      final query = await _firestore
          .collection(_collection)
          .where('shopId', isEqualTo: shopId)
          .where('status', isEqualTo: 'draft') // lowercase để match với toMap()
          .orderBy('createdAt', descending: true)
          .get();

      debugPrint('📋 getPendingEntries: found ${query.docs.length} docs');
      for (final doc in query.docs) {
        debugPrint(
          '   - doc ${doc.id}: status=${doc.data()['status']}, items=${(doc.data()['items'] as List?)?.length ?? 0}',
        );
      }

      return query.docs
          .map((doc) => StockEntry.fromMap(doc.data(), docId: doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ Error getting pending entries: $e');
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
          .where(
            'status',
            isEqualTo: 'confirmed',
          ); // lowercase để match với toMap()

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
          .map(
            (doc) => StockEntry.fromMap(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            ),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  // === XÁC NHẬN NHẬP KHO (ATOMIC TRANSACTION) ===

  /// Xác nhận nhập kho - PHẢI atomic
  /// Tạo products + financial_activity + supplier_debt (nếu công nợ)
  Future<bool> confirmEntry(String entryId) async {
    debugPrint('🔄 confirmEntry: START entryId=$entryId');
    try {
      final result = await _firestore.runTransaction((transaction) async {
        debugPrint('🔄 confirmEntry: Inside transaction');

        // 1. Lấy phiếu nhập
        final entryRef = _firestore.collection(_collection).doc(entryId);
        final entryDoc = await transaction.get(entryRef);

        if (!entryDoc.exists) {
          debugPrint('❌ confirmEntry: Entry not found');
          throw Exception('Không tìm thấy phiếu');
        }

        final entryData = entryDoc.data()!;
        debugPrint(
          '🔄 confirmEntry: Entry data - status=${entryData['status']}, supplierId=${entryData['supplierId']}, paymentMethod=${entryData['paymentMethod']}',
        );

        final entry = StockEntry.fromMap(entryData, docId: entryDoc.id);
        debugPrint(
          '🔄 confirmEntry: Parsed entry - status=${entry.status}, canConfirm=${entry.canConfirm}, missingInfo=${entry.missingInfo}',
        );
        debugPrint(
          '🔄 confirmEntry: shopId=${entry.shopId}, items=${entry.items.length}, totalCost=${entry.calculatedTotalCost}',
        );

        // 2. Validate
        if (entry.status != StockEntryStatus.draft) {
          debugPrint('❌ confirmEntry: Entry not draft, status=${entry.status}');
          throw Exception('Phiếu đã được xử lý');
        }

        if (!entry.canConfirm) {
          debugPrint(
            '❌ confirmEntry: Cannot confirm - ${entry.missingInfo.join(", ")}',
          );
          throw Exception('Chưa đủ thông tin: ${entry.missingInfo.join(", ")}');
        }

        // 3. Tạo products từ items
        final userId = _auth.currentUser?.uid;
        final Map<String, String> partFirestoreIds = {}; // Lưu firestoreId của linh kiện

        for (final item in entry.items) {
          // === XỬ LÝ LINH KIỆN: Lưu vào repair_parts thay vì products ===
          if (item.productType == 'LINH_KIEN') {
            final partRef = _firestore.collection('repair_parts').doc();
            partFirestoreIds[item.name] = partRef.id; // Lưu ID để dùng sau
            final now = DateTime.now().millisecondsSinceEpoch;
            final userName =
                _auth.currentUser?.email?.split('@').first.toUpperCase() ??
                'NV';

            transaction.set(partRef, {
              'partName': item.name,
              'compatibleModels': item.model ?? '',
              'cost': (item.cost ?? 0).toInt(),
              'price': (item.price ?? 0).toInt(),
              'quantity': item.quantity,
              'supplierId': entry.supplierId != null
                  ? int.tryParse(entry.supplierId!)
                  : null,
              'paymentMethod': entry.paymentMethod,
              'createdBy': userName,
              'createdAt': now,
              'updatedAt': now,
              'shopId': entry.shopId,
              'deleted': false,
              'stockEntryId': entryId,
            });
            continue; // Skip the products creation for LINH_KIEN
          }

          // === XỬ LÝ ĐIỆN THOẠI & PHỤ KIỆN: Lưu vào products ===
          // Xử lý đặc biệt cho điện thoại: nếu quantity > 1 và không có IMEI
          // → tách thành nhiều products riêng biệt
          final bool isPhoneWithBatch =
              item.productType == 'DIEN_THOAI' &&
              item.quantity > 1 &&
              (item.imei == null || item.imei!.isEmpty);

          final int productsToCreate = isPhoneWithBatch ? item.quantity : 1;
          final int quantityPerProduct = isPhoneWithBatch ? 1 : item.quantity;

          for (int i = 0; i < productsToCreate; i++) {
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

            // Tạo IMEI placeholder nếu là điện thoại batch
            String productImei = item.imei ?? '';
            if (isPhoneWithBatch) {
              // Tạo IMEI placeholder: PENDING_<timestamp>_<index>
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              productImei = 'PENDING_${timestamp}_${i + 1}';
            }

            // Thêm số thứ tự vào tên nếu là batch
            String finalProductName = productName;
            if (isPhoneWithBatch && productsToCreate > 1) {
              finalProductName = '$productName #${i + 1}';
            }

            transaction.set(productRef, {
              'name': finalProductName,
              'detail': detail,
              'type': item.productType,
              'imei': productImei,
              'brand': item.brand ?? '',
              'model': item.model ?? '',
              if (item.labelInfo != null && item.labelInfo!.isNotEmpty)
                'labelInfo': item.labelInfo,
              'cost': item.cost ?? 0,
              'price': item.price ?? 0,
              'quantity': quantityPerProduct,
              'supplier': entry.supplierName ?? '',
              'supplierId': entry.supplierId,
              'paymentMethod': entry.paymentMethod, // Phương thức thanh toán
              'status': 1, // Trong kho
              'stockEntryId': entryId,
              'shopId': entry.shopId,
              'createdAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
              'deleted': false,
              if (isPhoneWithBatch)
                'needsImeiUpdate': true, // Đánh dấu cần cập nhật IMEI
              if (isPhoneWithBatch) 'batchIndex': i + 1,
            });
          } // End for loop products
        }

        // 4. Ghi financial_activity
        final totalCost = entry.calculatedTotalCost;
        final activityRef = _firestore.collection('financial_activities').doc();

        // Xác định loại giao dịch dựa trên payment method
        String direction = 'OUT'; // Chi tiền mua hàng
        if (entry.paymentMethod == 'CÔNG NỢ') {
          direction = 'DEBT'; // Ghi nợ, không chi tiền ngay
        }

        // Lấy tên người dùng để hiển thị
        final userName =
            _auth.currentUser?.email?.split('@').first.toUpperCase() ?? 'NV';

        transaction.set(activityRef, {
          'type': 'STOCK_IN',
          'subType': 'NHAP_KHO',
          'amount': totalCost,
          'direction': direction,
          'referenceId': entryId,
          'referenceType': 'stock_entry',
          'description':
              'Nhập kho: ${entry.totalQuantity} sản phẩm từ ${entry.supplierName}',
          'paymentMethod': entry.paymentMethod,
          'supplierId': entry.supplierId,
          'supplierName': entry.supplierName,
          'shopId': entry.shopId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdBy': userName, // Tên thay vì ID
          'createdByUid': userId, // Giữ lại UID để tra cứu
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
            'createdBy': userName,
            'createdByUid': userId,
            'notes': 'Nhập kho: ${entry.totalQuantity} sản phẩm',
          });
        }

        // 5.5 Ghi lịch sử nhập hàng vào supplier_import_history
        for (final item in entry.items) {
          final importRef = _firestore
              .collection('supplier_import_history')
              .doc();
          transaction.set(importRef, {
            'supplierId': entry.supplierId,
            'supplierName': entry.supplierName,
            'productName': item.name,
            'productBrand': item.brand ?? '',
            'productModel': item.model ?? '',
            'imei': item.imei ?? '',
            'quantity': item.quantity,
            'costPrice': (item.cost ?? 0).toInt(),
            'totalAmount': item.totalCost.toInt(),
            'paymentMethod': entry.paymentMethod,
            'importDate': DateTime.now().millisecondsSinceEpoch,
            'importedBy': userName,
            'importedByUid': userId,
            'notes': entry.notes ?? '',
            'referenceId': entryId,
            'shopId': entry.shopId,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        // 6. Cập nhật trạng thái phiếu
        debugPrint('🔄 confirmEntry: Updating entry status to confirmed');
        transaction.update(entryRef, {
          'status': 'confirmed', // lowercase để match với Firestore rules
          'locked': true,
          'totalCost': totalCost,
          'confirmedAt': FieldValue.serverTimestamp(),
          'confirmedBy': userId,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        debugPrint('✅ confirmEntry: Transaction completed successfully');
        // Trả về thông tin để ghi local
        return {
          'success': true,
          'entry': entry,
          'totalCost': totalCost,
          'direction': direction,
          'userId': userId,
          'partFirestoreIds': partFirestoreIds, // Map item.name -> firestoreId
        };
      });

      // === TẠO PAYMENTINTENT VÀ DEBT CHO LOCAL DB ===
      // Đây là bước quan trọng để hiển thị trên trang "Thanh toán" và tài chính
      if (result['success'] == true) {
        final entry = result['entry'] as StockEntry;
        final totalCost = (result['totalCost'] as double).toInt();
        final direction = result['direction'] as String;
        final partFirestoreIds = result['partFirestoreIds'] as Map<String, String>;
        final userName =
            _auth.currentUser?.email?.split('@').first.toUpperCase() ?? 'NV';
        final now = DateTime.now().millisecondsSinceEpoch;

        try {
          final db = DBHelper();

          if (entry.paymentMethod == 'CÔNG NỢ') {
            // === TẠO DEBT TRONG LOCAL DB ===
            final debtFirestoreId = 'debt_stock_${entryId}_$now';
            // Normalize supplierName để đảm bảo match khi query
            final normalizedSupplierName = (entry.supplierName ?? 'NCC')
                .toUpperCase()
                .trim();

            debugPrint(
              '🔔 confirmEntry: Creating debt for supplier: $normalizedSupplierName, amount: $totalCost',
            );

            final debtData = {
              'firestoreId': debtFirestoreId,
              'type': 'SHOP_OWES', // Shop nợ NCC
              'debtType': 'SHOP_OWES', // Thêm debtType để consistency
              'personName': normalizedSupplierName,
              'phone': '',
              'totalAmount': totalCost,
              'paidAmount': 0,
              'status': 'ACTIVE', // Sử dụng ACTIVE để match với các debt khác
              'note':
                  'Nhập kho: ${entry.totalQuantity} sản phẩm từ $normalizedSupplierName',
              'linkedId': entryId,
              'linkedType': 'stock_entry',
              'createdAt': now,
              'updatedAt': now,
              'shopId': entry.shopId,
              'deleted': 0, // Thêm deleted field
              'isSynced': 0, // Đặt thành 0 để sync lên Firestore
            };

            final debtId = await db.insertDebt(debtData);
            debugPrint(
              '✅ confirmEntry: Created local DEBT id=$debtId for CÔNG NỢ: $totalCost, supplier: $normalizedSupplierName',
            );

            // Sync debt lên Firestore
            if (debtId > 0) {
              await SyncOrchestrator().enqueueDebt(
                debtId,
                firestoreId: debtFirestoreId,
                operation: SyncOperation.create,
              );
            }

            // Notify các view khác để refresh
            EventBus().emit('debts_changed');

            // KHÔNG tạo PaymentIntent cho CÔNG NỢ vì:
            // 1. Debt record đã được tạo (đây là financial record chính)
            // 2. PaymentIntentService.createIntent() chỉ chấp nhận status=pending
            // 3. Khi thanh toán công nợ, user sẽ tạo PaymentIntent mới từ trang NCC
            debugPrint('✅ confirmEntry: CÔNG NỢ debt created, no PaymentIntent needed');
          } else {
            // === TIỀN MẶT / CHUYỂN KHOẢN - Tạo EXPENSE ===
            // Ghi expense vào local DB
            await db.insertExpense({
              'firestoreId': 'exp_stock_${entryId}_$now',
              'category': 'NHẬP HÀNG',
              'title': 'Nhập kho từ ${entry.supplierName}',
              'amount': totalCost,
              'paymentMethod': entry.paymentMethod,
              'note': 'Nhập ${entry.totalQuantity} sản phẩm',
              'date': now,
              'createdBy': userName,
              'shopId': entry.shopId,
              'isSynced': 0, // Đổi thành 0 để sync lên Firestore
            });
            debugPrint(
              '✅ confirmEntry: Created local EXPENSE for ${entry.paymentMethod}: $totalCost',
            );
            
            // KHÔNG tạo PaymentIntent cho TIỀN MẶT/CK vì:
            // 1. Expense record đã được ghi (đây là financial record chính)
            // 2. PaymentIntentService.createIntent() chỉ chấp nhận status=pending
            debugPrint('✅ confirmEntry: Expense created, no PaymentIntent needed');
          }

          // === GHI LINH KIỆN VÀO LOCAL repair_parts ===
          for (final item in entry.items) {
            if (item.productType == 'LINH_KIEN') {
              final firestoreId = partFirestoreIds[item.name];
              if (firestoreId == null) {
                debugPrint('⚠️ Missing firestoreId for part: ${item.name}');
                continue;
              }
              await db.upsertRepairPart({
                'firestoreId': firestoreId,
                'partName': item.name,
                'compatibleModels': item.model ?? '',
                'cost': (item.cost ?? 0).toInt(),
                'price': (item.price ?? 0).toInt(),
                'quantity': item.quantity,
                'paymentMethod': entry.paymentMethod,
                'createdBy': userName,
                'createdAt': now,
                'updatedAt': now,
                'shopId': entry.shopId,
                'isSynced': 1,
                'deleted': 0,
              });
              debugPrint('✅ confirmEntry: Local repair_part saved for ${item.name} with firestoreId=$firestoreId');
            }
          }
        } catch (e) {
          debugPrint(
            '⚠️ confirmEntry: Failed to create local financial records: $e',
          );
          // Không fail cả flow, chỉ log warning
        }
      }

      // === GHI SUPPLIER_IMPORT_HISTORY VÀO LOCAL DB ===
      if (result['success'] == true) {
        final entry = result['entry'] as StockEntry;
        final userName =
            _auth.currentUser?.email?.split('@').first.toUpperCase() ?? 'NV';
        final now = DateTime.now().millisecondsSinceEpoch;

        try {
          final db = DBHelper();

          // Ghi supplier_import_history vào local DB
          // Lookup supplier local ID từ name hoặc firestoreId với fuzzy matching
          int? supplierLocalId;
          if (entry.supplierName != null || entry.supplierId != null) {
            final suppliers = await db.getSuppliers();
            final supplierNameUpper = entry.supplierName?.toUpperCase().trim();

            // Thử match theo nhiều cách
            final matchedSupplier = suppliers.firstWhere((s) {
              // Match by firestoreId first (most reliable)
              if (entry.supplierId != null &&
                  s['firestoreId'] == entry.supplierId) {
                return true;
              }
              // Match by exact name (uppercase)
              if (supplierNameUpper != null &&
                  s['name']?.toString().toUpperCase().trim() ==
                      supplierNameUpper) {
                return true;
              }
              // Match by name contains (fuzzy)
              if (supplierNameUpper != null &&
                  s['name']?.toString().toUpperCase().contains(
                        supplierNameUpper,
                      ) ==
                      true) {
                return true;
              }
              return false;
            }, orElse: () => {});
            supplierLocalId = matchedSupplier['id'] as int?;

            debugPrint(
              '📦 confirmEntry: Supplier lookup - name="${entry.supplierName}", fsId="${entry.supplierId}", localId=$supplierLocalId',
            );
          }

          // NOTE: Không ghi supplier_import_history vào local DB ở đây
          // Để sync_service tự đồng bộ từ Firestore để tránh duplicate records
          // (trước đây firestoreId local != firestoreId từ Firestore => duplicate)
          debugPrint('✅ confirmEntry: Local supplier_import_history synced from Firestore');
        } catch (e) {
          debugPrint('⚠️ confirmEntry: Failed to save local data: $e');
          // Không fail cả flow, chỉ log warning
        }
      }

      debugPrint('✅ confirmEntry: SUCCESS');
      _showSuccess('Đã xác nhận nhập kho');
      return result['success'] == true;
    } catch (e) {
      debugPrint('❌ confirmEntry ERROR: $e');
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
      final quickEntry = entry.copyWith(entryType: StockEntryType.quick);

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
      debugPrint(
        '📝 saveDraft: entry status=${entry.status.name}, items=${entry.items.length}',
      );
      final draftEntry = entry.copyWith(
        status: StockEntryStatus.draft,
        entryType: StockEntryType.staging,
        locked: false,
      );
      debugPrint('📝 saveDraft: draftEntry status=${draftEntry.status.name}');

      final created = await createEntry(draftEntry);
      debugPrint('📝 saveDraft: created=${created?.firestoreId}');
      if (created != null) {
        _showSuccess('Đã lưu tạm thành công');
      }
      return created;
    } catch (e) {
      debugPrint('❌ saveDraft error: $e');
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
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => StockEntry.fromMap(doc.data(), docId: doc.id))
              .toList(),
        );
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
