import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/product_model.dart';
import '../models/sale_order_model.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../models/attendance_model.dart';
import '../models/customer_model.dart';
import '../models/quick_input_code_model.dart';
import '../models/supplier_model.dart';
import '../models/repair_partner_model.dart';
import 'storage_service.dart';
import 'user_service.dart';
import 'encryption_service.dart';

class SyncService {
  static final _db = FirebaseFirestore.instance;
  static final List<StreamSubscription> _subscriptions = [];

  /// Khởi tạo đồng bộ thời gian thực
  static Future<void> initRealTimeSync(VoidCallback onDataChanged) async {
    debugPrint("Khởi tạo real-time sync...");
    // Hủy các subscription cũ nếu có để tránh rò rỉ bộ nhớ hoặc lặp sự kiện
    await cancelAllSubscriptions();

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("initRealTimeSync: Không có user, bỏ qua");
      return;
    }

    final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();
    // Super admin cũng cần shopId nếu đã chọn shop
    final String? shopId = await UserService.getCurrentShopId();

    // LOG QUAN TRỌNG: Hiển thị shopId được sử dụng để filter
    debugPrint(
      "⚡ initRealTimeSync: user=${user.uid}, email=${user.email}, shopId=$shopId, isSuperAdmin=$isSuperAdmin",
    );

    // Super admin phải chọn shop trước khi init real-time sync
    if (shopId == null) {
      if (isSuperAdmin) {
        debugPrint("⚠️ initRealTimeSync: Super admin chưa chọn shop, bỏ qua");
      } else {
        debugPrint("⚠️ initRealTimeSync: Không có shopId, bỏ qua");
      }
      return;
    }

    // 1. Đồng bộ REPAIRS
    _subscribeToCollection(
      collection: 'repairs',
      shopId: shopId,
      onChanged: (data, docId) async {
        try {
          debugPrint(
            "SYNC_TRACE: Received repair data from Firestore - docId: $docId, status: ${data['status']}, price: ${data['price']}, totalCost: ${data['totalCost']}, createdAt: ${data['createdAt']}, deliveredAt: ${data['deliveredAt']}, deleted: ${data['deleted']}",
          );
          final db = DBHelper();
          if (data['deleted'] == true) {
            await db.deleteRepairByFirestoreId(docId);
            debugPrint(
              "SYNC_TRACE: Deleted repair $docId from local DB (deleted=true in Firestore)",
            );
          } else {
            data['firestoreId'] = docId;
            data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
            await db.upsertRepair(Repair.fromMap(data));
            debugPrint(
              "SYNC_TRACE: Upserted repair $docId to local DB SUCCESSFULLY",
            );
          }
        } catch (e) {
          debugPrint("SYNC_TRACE: Error syncing repair $docId: $e");
        }
      },
      onBatchDone: onDataChanged,
    );

    // 2. Đồng bộ SALES
    _subscribeToCollection(
      collection: 'sales',
      shopId: shopId,
      onChanged: (data, docId) async {
        try {
          debugPrint(
            "SYNC_TRACE: Received sale data from Firestore - docId: $docId, totalPrice: ${data['totalPrice']}, totalCost: ${data['totalCost']}, soldAt: ${data['soldAt']}, customerName: ${data['customerName']}, deleted: ${data['deleted']}",
          );
          final db = DBHelper();
          if (data['deleted'] == true) {
            await db.deleteSaleByFirestoreId(docId);
            debugPrint(
              "SYNC_TRACE: Deleted sale $docId from local DB (deleted=true in Firestore)",
            );
          } else {
            data['firestoreId'] = docId;
            data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
            await db.upsertSale(SaleOrder.fromMap(data));
            debugPrint(
              "SYNC_TRACE: Upserted sale $docId to local DB SUCCESSFULLY",
            );
          }
        } catch (e) {
          debugPrint("SYNC_TRACE: Error syncing sale $docId: $e");
        }
      },
      onBatchDone: onDataChanged,
    );

    // 3. Đồng bộ PRODUCTS
    _subscribeToCollection(
      collection: 'products',
      shopId: shopId,
      onChanged: (data, docId) async {
        try {
          final db = DBHelper();
          if (data['deleted'] == true) {
            await db.deleteProductByFirestoreId(docId);
          } else {
            data['firestoreId'] = docId;
            data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
            await db.upsertProduct(Product.fromMap(data));
          }
        } catch (e) {
          debugPrint("Lỗi sync product $docId: $e");
        }
      },
      onBatchDone: onDataChanged,
    );

    // 4. Đồng bộ EXPENSES
    _subscribeToCollection(
      collection: 'expenses',
      shopId: shopId,
      onChanged: (data, docId) async {
        try {
          final db = DBHelper();
          if (data['deleted'] == true) {
            await db.deleteExpenseByFirestoreId(docId);
          } else {
            data['firestoreId'] = docId;
            data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
            await db.upsertExpense(Expense.fromMap(data));
          }
        } catch (e) {
          debugPrint("Lỗi sync expense $docId: $e");
        }
      },
      onBatchDone: onDataChanged,
    );

    // 5. Đồng bộ DEBTS
    _subscribeToCollection(
      collection: 'debts',
      shopId: shopId,
      onChanged: (data, docId) async {
        try {
          final db = DBHelper();
          if (data['deleted'] == true) {
            await db.deleteDebtByFirestoreId(docId);
          } else {
            data['firestoreId'] = docId;
            data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
            await db.upsertDebt(Debt.fromMap(data));
          }
        } catch (e) {
          debugPrint("Lỗi sync debt $docId: $e");
        }
      },
      onBatchDone: onDataChanged,
    );

    // 6. Đồng bộ USERS (cập nhật cache khi có thay đổi)
    _subscribeToCollection(
      collection: 'users',
      shopId: shopId,
      onChanged: (data, docId) async {
        try {
          // Nếu là user hiện tại, cập nhật cache shopId
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null && docId == currentUser.uid) {
            UserService.updateCachedShopId(data['shopId']);
            debugPrint("Updated cached shopId: ${data['shopId']}");
          }
        } catch (e) {
          debugPrint("Lỗi sync user $docId: $e");
        }
      },
      onBatchDone: onDataChanged,
    );

    // 7. Đồng bộ SHOPS (cập nhật cache khi có thay đổi)
    _subscribeToCollection(
      collection: 'shops',
      shopId: shopId,
      onChanged: (data, docId) async {
        try {
          // Shop data changed, có thể trigger UI update nếu cần
          debugPrint("Shop data changed: $docId");
        } catch (e) {
          debugPrint("Lỗi sync shop $docId: $e");
        }
      },
      onBatchDone: onDataChanged,
    );

    // 8. Đồng bộ ATTENDANCE
    try {
      _subscribeToCollection(
        collection: 'attendance',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteAttendanceByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertAttendance(Attendance.fromMap(data));
            }
          } catch (e) {
            debugPrint("Lỗi sync attendance $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo attendance sync: $e");
    }

    // 9. Đồng bộ QUICK INPUT CODES
    try {
      _subscribeToCollection(
        collection: 'quick_input_codes',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteQuickInputCodeByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertQuickInputCode(QuickInputCode.fromMap(data));
            }
          } catch (e) {
            debugPrint("Lỗi sync quick_input_code $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo quick_input_codes sync: $e");
    }

    // 10. Đồng bộ SUPPLIER PAYMENTS
    try {
      _subscribeToCollection(
        collection: 'supplier_payments',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteSupplierPaymentByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertSupplierPayment(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync supplier_payment $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo supplier_payments sync: $e");
    }

    // 11. Đồng bộ REPAIR PARTNER PAYMENTS
    try {
      _subscribeToCollection(
        collection: 'repair_partner_payments',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteRepairPartnerPaymentByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertRepairPartnerPayment(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync repair_partner_payment $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo repair_partner_payments sync: $e");
    }

    // 12. Đồng bộ CUSTOMERS
    try {
      _subscribeToCollection(
        collection: 'customers',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteCustomerByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertCustomer(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync customer $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo customers sync: $e");
    }

    // 13. Đồng bộ SUPPLIERS
    try {
      _subscribeToCollection(
        collection: 'suppliers',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteSupplierByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertSupplier(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync supplier $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo suppliers sync: $e");
    }

    // 14. Đồng bộ REPAIR PARTNERS
    try {
      _subscribeToCollection(
        collection: 'repair_partners',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteRepairPartnerByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertRepairPartner(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync repair_partner $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo repair_partners sync: $e");
    }

    // 15. Đồng bộ AUDIT LOGS
    try {
      _subscribeToCollection(
        collection: 'audit_logs',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteAuditLogByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertAuditLog(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync audit_log $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo audit_logs sync: $e");
    }

    debugPrint(
      "Đã khởi tạo real-time sync cho ${isSuperAdmin ? 'super admin' : 'shop: $shopId'}",
    );
  }

  /// Hàm helper để quản lý subscription an toàn
  static void _subscribeToCollection({
    required String collection,
    String? shopId,
    required Future<void> Function(Map<String, dynamic> data, String docId)
    onChanged,
    required VoidCallback onBatchDone,
  }) {
    Query<Map<String, dynamic>> query = _db.collection(collection);
    if (shopId != null) {
      query = query.where('shopId', isEqualTo: shopId);
      debugPrint("📡 Subscribing to $collection with shopId filter: $shopId");
    } else {
      debugPrint(
        "⚠️ Subscribing to $collection WITHOUT shopId filter (super admin mode)",
      );
    }

    final sub = query.snapshots().listen((snapshot) async {
      for (var change in snapshot.docChanges) {
        var data = change.doc.data();
        if (data == null) continue;

        // Giải mã dữ liệu nếu được mã hóa
        data = EncryptionService.decryptMap(data);

        debugPrint(
          "Real-time change in $collection: ${change.doc.id}, type: ${change.type}",
        );
        await onChanged(data, change.doc.id);
      }
      onBatchDone();
    }, onError: (e) => debugPrint("Sync error in $collection: $e"));

    _subscriptions.add(sub);
  }

  static Future<void> cancelAllSubscriptions() async {
    for (var sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
  }

  /// Đẩy dữ liệu từ Local lên Cloud (Dùng khi có mạng trở lại)
  static Future<void> syncAllToCloud() async {
    debugPrint("Bắt đầu syncAllToCloud...");
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint("Không có user, bỏ qua syncAllToCloud");
        return;
      }

      final String? shopId = await UserService.getCurrentShopId();
      final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();

      // LOG QUAN TRỌNG: Hiển thị shopId được sử dụng
      debugPrint(
        "⚡ syncAllToCloud: user=${user.uid}, email=${user.email}, shopId=$shopId, isSuperAdmin=$isSuperAdmin",
      );

      // Cần có shopId để upload (super admin chỉ xem, không tạo/sửa data)
      if (shopId == null) {
        if (isSuperAdmin) {
          debugPrint(
            "⚠️ Super admin chưa chọn shop hoặc chỉ được xem, bỏ qua syncAllToCloud",
          );
        } else {
          debugPrint("Không có shopId, bỏ qua syncAllToCloud");
        }
        return;
      }

      // Super admin chỉ được xem, không được upload data
      if (isSuperAdmin) {
        debugPrint("⚠️ Super admin chỉ được xem, không được upload data");
        return;
      }

      final dbHelper = DBHelper();

      // Chỉ đẩy những đơn hàng CHƯA đồng bộ hoặc CÓ thay đổi hình ảnh
      final repairs = await dbHelper.getAllRepairs();
      debugPrint("syncAllToCloud: có ${repairs.length} repairs cần sync");
      final WriteBatch repairBatch = _db.batch();
      for (var r in repairs) {
        if (r.isSynced && !(r.imagePath?.contains('cache') ?? false)) continue;

        try {
          Map<String, dynamic> data = r.toMap();
          data['shopId'] = shopId;
          data.remove('id');

          // Xử lý upload ảnh nếu là ảnh local với timeout
          if (r.imagePath != null &&
              r.imagePath!.isNotEmpty &&
              !r.imagePath!.startsWith('http')) {
            List<String> urls =
                await StorageService.uploadMultipleImages(
                  r.imagePath!
                      .split(',')
                      .where((path) => !path.startsWith('http'))
                      .toList(),
                  'repairs/${r.createdAt}',
                ).timeout(
                  const Duration(seconds: 30),
                  onTimeout: () {
                    debugPrint(
                      "Upload ảnh repair ${r.id} quá thời gian, bỏ qua",
                    );
                    return <String>[];
                  },
                );
            // Giữ lại các ảnh cũ là URL và thêm ảnh mới
            List<String> allUrls = r.imagePath!
                .split(',')
                .where((path) => path.startsWith('http'))
                .toList();
            allUrls.addAll(urls);
            data['imagePath'] = allUrls.join(',');
          }

          final docId =
              r.firestoreId ?? "repair_${r.createdAt}_${r.phone}_${r.id ?? 0}";
          repairBatch.set(
            _db.collection('repairs').doc(docId),
            data,
            SetOptions(merge: true),
          );

          r.isSynced = true;
          r.firestoreId = docId;
          r.imagePath = data['imagePath'];
          await dbHelper.updateRepair(r);
        } catch (e) {
          debugPrint("Lỗi sync repair ${r.id}: $e");
          // Tiếp tục với repair tiếp theo thay vì dừng toàn bộ
        }
      }
      await repairBatch.commit();

      // Sync SALES
      final sales = await dbHelper.getAllSales();
      debugPrint("syncAllToCloud: có ${sales.length} sales cần sync");
      final WriteBatch saleBatch = _db.batch();
      for (var s in sales) {
        if (s.isSynced) continue;

        try {
          Map<String, dynamic> data = s.toMap();
          data['shopId'] = shopId;
          data.remove('id');

          final docId =
              s.firestoreId ?? "sale_${s.soldAt}_${s.phone}_${s.id ?? 0}";
          saleBatch.set(
            _db.collection('sales').doc(docId),
            data,
            SetOptions(merge: true),
          );

          s.isSynced = true;
          s.firestoreId = docId;
          await dbHelper.updateSale(s);
        } catch (e) {
          debugPrint("Lỗi sync sale ${s.id}: $e");
          // Tiếp tục với sale tiếp theo
        }
      }
      await saleBatch.commit();

      // Sync EXPENSES (Chi phí)
      try {
        final expenses = await dbHelper.getAllExpensesForSync();
        debugPrint(
          "syncAllToCloud: có ${expenses.length} expenses cần kiểm tra sync",
        );
        if (expenses.isNotEmpty) {
          final WriteBatch expenseBatch = _db.batch();
          for (var expense in expenses) {
            // Skip nếu đã có firestoreId và đã sync
            final firestoreId = expense.firestoreId;
            if (firestoreId != null &&
                firestoreId.isNotEmpty &&
                expense.isSynced)
              continue;

            try {
              Map<String, dynamic> data = expense.toMap();
              data['shopId'] = shopId;
              data.remove('id');

              final docId =
                  firestoreId ??
                  "exp_${expense.date}_${expense.title.hashCode}";
              expenseBatch.set(
                _db.collection('expenses').doc(docId),
                data,
                SetOptions(merge: true),
              );

              // Update local với firestoreId và isSynced
              expense.firestoreId = docId;
              expense.isSynced = true;
              await dbHelper.updateExpense(expense);
            } catch (e) {
              debugPrint("Lỗi sync expense ${expense.id}: $e");
            }
          }
          await expenseBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync expenses collection: $e");
      }

      // Sync PRODUCTS
      final products = await dbHelper.getAllProducts();
      debugPrint("syncAllToCloud: có ${products.length} products cần sync");
      final WriteBatch productBatch = _db.batch();
      for (var p in products) {
        if (p.isSynced) continue;

        try {
          Map<String, dynamic> data = p.toMap();
          data['shopId'] = shopId;
          data.remove('id');

          // Xử lý upload ảnh nếu là ảnh local với timeout
          if (p.images != null &&
              p.images!.isNotEmpty &&
              !p.images!.startsWith('http')) {
            List<String> urls =
                await StorageService.uploadMultipleImages(
                  p.images!
                      .split(',')
                      .where((path) => !path.startsWith('http'))
                      .toList(),
                  'products/${p.createdAt}',
                ).timeout(
                  const Duration(seconds: 30),
                  onTimeout: () {
                    debugPrint(
                      "Upload ảnh product ${p.id} quá thời gian, bỏ qua",
                    );
                    return <String>[];
                  },
                );
            data['images'] = urls.join(',');
          }

          final docId =
              p.firestoreId ??
              "product_${p.createdAt}_${p.imei ?? 'noimei'}_${p.id ?? 0}";
          productBatch.set(
            _db.collection('products').doc(docId),
            data,
            SetOptions(merge: true),
          );

          p.isSynced = true;
          p.firestoreId = docId;
          p.images = data['images'];
          await dbHelper.updateProduct(p);
        } catch (e) {
          debugPrint("Lỗi sync product ${p.id}: $e");
          // Tiếp tục với product tiếp theo
        }
      }
      await productBatch.commit();

      // Sync ATTENDANCE
      try {
        final attendance = await dbHelper.getAllAttendance();
        debugPrint(
          "syncAllToCloud: có ${attendance.length} attendance cần sync",
        );
        final WriteBatch attendanceBatch = _db.batch();
        for (var a in attendance) {
          if (a.firestoreId != null && a.firestoreId!.isNotEmpty)
            continue; // Đã sync rồi

          try {
            Map<String, dynamic> data = a.toMap();
            data['shopId'] = shopId;
            data.remove('id');

            // Xử lý upload ảnh check-in/out nếu là ảnh local
            if (a.photoIn != null &&
                a.photoIn!.isNotEmpty &&
                !a.photoIn!.startsWith('http')) {
              List<String> urls =
                  await StorageService.uploadMultipleImages([
                    a.photoIn!,
                  ], 'attendance/${a.dateKey}_${a.userId}_in').timeout(
                    const Duration(seconds: 30),
                    onTimeout: () {
                      debugPrint(
                        "Upload ảnh check-in ${a.id} quá thời gian, bỏ qua",
                      );
                      return <String>[];
                    },
                  );
              if (urls.isNotEmpty) data['photoIn'] = urls.first;
            }

            if (a.photoOut != null &&
                a.photoOut!.isNotEmpty &&
                !a.photoOut!.startsWith('http')) {
              List<String> urls =
                  await StorageService.uploadMultipleImages([
                    a.photoOut!,
                  ], 'attendance/${a.dateKey}_${a.userId}_out').timeout(
                    const Duration(seconds: 30),
                    onTimeout: () {
                      debugPrint(
                        "Upload ảnh check-out ${a.id} quá thời gian, bỏ qua",
                      );
                      return <String>[];
                    },
                  );
              if (urls.isNotEmpty) data['photoOut'] = urls.first;
            }

            final docId =
                a.firestoreId ?? "attendance_${a.userId}_${a.dateKey}";
            attendanceBatch.set(
              _db.collection('attendance').doc(docId),
              data,
              SetOptions(merge: true),
            );

            a.firestoreId = docId;
            a.photoIn = data['photoIn'];
            a.photoOut = data['photoOut'];
            await dbHelper.updateAttendance(a);
          } catch (e) {
            debugPrint("Lỗi sync attendance ${a.id}: $e");
            // Tiếp tục với attendance tiếp theo
          }
        }
        await attendanceBatch.commit();
      } catch (e) {
        debugPrint("Lỗi sync attendance collection: $e");
      }

      // Đồng bộ Quick Input Codes
      try {
        final quickInputCodes = await dbHelper.getQuickInputCodes();
        debugPrint(
          "syncAllToCloud: có ${quickInputCodes.length} quick input codes cần sync",
        );
        if (quickInputCodes.isNotEmpty) {
          final WriteBatch quickInputBatch = _db.batch();
          for (var code in quickInputCodes) {
            if (code.isSynced) continue;

            try {
              Map<String, dynamic> data = code.toMap();
              data['shopId'] = shopId;
              data.remove('id');

              final docId =
                  code.firestoreId ??
                  "qic_${code.createdAt}_${code.name.replaceAll(' ', '_')}";
              quickInputBatch.set(
                _db.collection('quick_input_codes').doc(docId),
                data,
                SetOptions(merge: true),
              );

              code.firestoreId = docId;
              code.shopId = shopId;
              code.isSynced = true;
              await dbHelper.updateQuickInputCode(code);
            } catch (e) {
              debugPrint("Lỗi sync quick input code ${code.id}: $e");
            }
          }
          await quickInputBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync quick input codes collection: $e");
      }

      // Đồng bộ Suppliers
      try {
        final suppliers = await dbHelper.getSuppliers();
        debugPrint(
          "syncAllToCloud: có ${suppliers.length} suppliers cần kiểm tra sync",
        );
        if (suppliers.isNotEmpty) {
          final WriteBatch supplierBatch = _db.batch();
          for (var supplierMap in suppliers) {
            // Skip nếu đã có firestoreId (đã sync)
            if (supplierMap['firestoreId'] != null &&
                supplierMap['firestoreId'].toString().isNotEmpty)
              continue;

            try {
              Map<String, dynamic> data = Map<String, dynamic>.from(
                supplierMap,
              );
              data['shopId'] = shopId;
              data.remove('id');

              final docId =
                  "supplier_${data['createdAt']}_${data['name'].toString().replaceAll(' ', '_')}";
              supplierBatch.set(
                _db.collection('suppliers').doc(docId),
                data,
                SetOptions(merge: true),
              );

              // Update local với firestoreId
              supplierMap['firestoreId'] = docId;
              await dbHelper.upsertSupplier(supplierMap);
            } catch (e) {
              debugPrint("Lỗi sync supplier ${supplierMap['id']}: $e");
            }
          }
          await supplierBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync suppliers collection: $e");
      }

      // Đồng bộ Repair Partners
      try {
        final partners = await dbHelper.getRepairPartners();
        debugPrint(
          "syncAllToCloud: có ${partners.length} repair partners cần kiểm tra sync",
        );
        if (partners.isNotEmpty) {
          final WriteBatch partnerBatch = _db.batch();
          for (var partnerMap in partners) {
            // Skip nếu đã có firestoreId (đã sync)
            if (partnerMap['firestoreId'] != null &&
                partnerMap['firestoreId'].toString().isNotEmpty)
              continue;

            try {
              Map<String, dynamic> data = Map<String, dynamic>.from(partnerMap);
              data['shopId'] = shopId;
              data.remove('id');

              final docId =
                  "rp_${data['createdAt']}_${data['name'].toString().replaceAll(' ', '_')}";
              partnerBatch.set(
                _db.collection('repair_partners').doc(docId),
                data,
                SetOptions(merge: true),
              );

              // Update local với firestoreId
              partnerMap['firestoreId'] = docId;
              await dbHelper.upsertRepairPartner(partnerMap);
            } catch (e) {
              debugPrint("Lỗi sync repair partner ${partnerMap['id']}: $e");
            }
          }
          await partnerBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync repair partners collection: $e");
      }

      // Đồng bộ Debts (Công nợ)
      try {
        final debts = await dbHelper.getAllDebts();
        debugPrint(
          "syncAllToCloud: có ${debts.length} debts cần kiểm tra sync",
        );
        if (debts.isNotEmpty) {
          final WriteBatch debtBatch = _db.batch();
          for (var debtMap in debts) {
            // Skip nếu đã có firestoreId và đã sync
            final firestoreId = debtMap['firestoreId'];
            final isSynced =
                debtMap['isSynced'] == 1 || debtMap['isSynced'] == true;
            if (firestoreId != null &&
                firestoreId.toString().isNotEmpty &&
                isSynced)
              continue;

            try {
              Map<String, dynamic> data = Map<String, dynamic>.from(debtMap);
              data['shopId'] = shopId;
              data.remove('id');

              final docId =
                  firestoreId ??
                  "debt_${data['createdAt']}_${data['phone'] ?? 'ncc'}";
              debtBatch.set(
                _db.collection('debts').doc(docId),
                data,
                SetOptions(merge: true),
              );

              // Update local với firestoreId và isSynced
              await dbHelper.updateDebtSynced(debtMap['id'], docId);
            } catch (e) {
              debugPrint("Lỗi sync debt ${debtMap['id']}: $e");
            }
          }
          await debtBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync debts collection: $e");
      }

      // Đồng bộ Debt Payments (Lịch sử thanh toán công nợ)
      try {
        final debtPayments = await dbHelper.getAllDebtPaymentsForSync();
        debugPrint(
          "syncAllToCloud: có ${debtPayments.length} debt payments cần kiểm tra sync",
        );
        if (debtPayments.isNotEmpty) {
          final WriteBatch paymentBatch = _db.batch();
          for (var paymentMap in debtPayments) {
            // Skip nếu đã có firestoreId và đã sync
            final firestoreId = paymentMap['firestoreId'];
            final isSynced =
                paymentMap['isSynced'] == 1 || paymentMap['isSynced'] == true;
            if (firestoreId != null &&
                firestoreId.toString().isNotEmpty &&
                isSynced)
              continue;

            try {
              Map<String, dynamic> data = Map<String, dynamic>.from(paymentMap);
              data['shopId'] = shopId;
              data.remove('id');

              final docId =
                  firestoreId ??
                  "pay_${data['paidAt']}_${data['debtId'] ?? 'debt'}";
              paymentBatch.set(
                _db.collection('debt_payments').doc(docId),
                data,
                SetOptions(merge: true),
              );

              // Update local với firestoreId và isSynced
              await dbHelper.updateDebtPaymentSynced(paymentMap['id'], docId);
            } catch (e) {
              debugPrint("Lỗi sync debt payment ${paymentMap['id']}: $e");
            }
          }
          await paymentBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync debt payments collection: $e");
      }

      // Đồng bộ Audit Logs (Nhật ký hoạt động)
      try {
        final auditLogs = await dbHelper.getUnsyncedAuditLogs();
        debugPrint(
          "syncAllToCloud: có ${auditLogs.length} audit logs cần sync",
        );
        if (auditLogs.isNotEmpty) {
          final WriteBatch auditBatch = _db.batch();
          for (var logMap in auditLogs) {
            try {
              Map<String, dynamic> data = Map<String, dynamic>.from(logMap);
              data['shopId'] = shopId;
              data.remove('id');

              final docId =
                  logMap['firestoreId'] ??
                  "log_${data['createdAt']}_${data['userId']}";
              auditBatch.set(
                _db.collection('audit_logs').doc(docId),
                data,
                SetOptions(merge: true),
              );

              // Update local với isSynced
              await dbHelper.updateAuditLogSynced(docId);
            } catch (e) {
              debugPrint("Lỗi sync audit log ${logMap['id']}: $e");
            }
          }
          await auditBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync audit logs collection: $e");
      }

      debugPrint("Đã hoàn thành đồng bộ toàn bộ dữ liệu lên Cloud.");
    } catch (e) {
      debugPrint("Lỗi syncAllToCloud: $e");
    }
  }

  /// Tải toàn bộ dữ liệu từ Cloud về (Dùng khi cài lại app hoặc đổi máy)
  static Future<void> downloadAllFromCloud() async {
    debugPrint("Bắt đầu downloadAllFromCloud...");
    try {
      final db = DBHelper();
      final user = FirebaseAuth.instance.currentUser;
      final String? shopId = await UserService.getCurrentShopId();
      final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();

      // LOG QUAN TRỌNG: Hiển thị shopId được sử dụng
      debugPrint(
        "⚡ downloadAllFromCloud: user=${user?.uid}, email=${user?.email}, shopId=$shopId, isSuperAdmin=$isSuperAdmin",
      );

      // Cần có shopId để sync (super admin phải chọn shop trước)
      if (shopId == null) {
        if (isSuperAdmin) {
          debugPrint(
            "⚠️ Super admin chưa chọn shop, bỏ qua downloadAllFromCloud",
          );
        } else {
          debugPrint("Không có shopId, bỏ qua downloadAllFromCloud");
        }
        return;
      }

      // Log local data counts before sync
      final localRepairs = await db.getAllRepairs();
      final localProducts = await db.getInStockProducts();
      final localSales = await db.getAllSales();
      final localAttendance = await db.getAllAttendance();
      debugPrint(
        "LOCAL DATA BEFORE SYNC: repairs=${localRepairs.length}, products=${localProducts.length}, sales=${localSales.length}, attendance=${localAttendance.length}",
      );

      // Chỉ tải các collection có shopId - đảm bảo chỉ lấy dữ liệu của shop hiện tại
      final collections = [
        'repairs',
        'products',
        'sales',
        'expenses',
        'debts',
        'debt_payments',
        'attendance',
        'quick_input_codes',
        'supplier_payments',
        'repair_partner_payments',
        'customers',
        'suppliers',
        'repair_partners',
      ];
      // Lưu ý: 'users' và 'shops' không có shopId field nên không tải ở đây
      // 'supplier_import_history' và 'supplier_product_prices' quản lý locally

      for (var col in collections) {
        try {
          debugPrint("Downloading collection: $col...");
          // Luôn filter theo shopId (super admin đã chọn shop nên cũng có shopId)
          final snap = await _db
              .collection(col)
              .where('shopId', isEqualTo: shopId)
              .get();
          debugPrint("  -> Found ${snap.docs.length} documents in $col");

          int successCount = 0;
          int skipCount = 0;
          int errorCount = 0;

          for (var doc in snap.docs) {
            try {
              var data = doc.data();
              if (data['deleted'] == true) {
                skipCount++;
                continue; // Skip soft-deleted documents
              }

              // Giải mã dữ liệu nếu được mã hóa
              data = EncryptionService.decryptMap(data);
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1; // QUAN TRỌNG: Đánh dấu đã sync từ cloud

              if (col == 'repairs') {
                await db.upsertRepair(Repair.fromMap(data));
              } else if (col == 'products') {
                await db.upsertProduct(Product.fromMap(data));
              } else if (col == 'sales') {
                await db.upsertSale(SaleOrder.fromMap(data));
              } else if (col == 'expenses') {
                await db.upsertExpense(Expense.fromMap(data));
              } else if (col == 'debts') {
                await db.upsertDebt(Debt.fromMap(data));
              } else if (col == 'debt_payments') {
                await db.upsertDebtPayment(data);
              } else if (col == 'attendance') {
                await db.upsertAttendance(Attendance.fromMap(data));
              } else if (col == 'quick_input_codes') {
                await db.upsertQuickInputCode(QuickInputCode.fromMap(data));
              } else if (col == 'supplier_payments') {
                await db.upsertSupplierPayment(data);
              } else if (col == 'repair_partner_payments') {
                await db.upsertRepairPartnerPayment(data);
              } else if (col == 'customers') {
                await db.upsertCustomer(data);
              } else if (col == 'suppliers') {
                await db.upsertSupplier(data);
              } else if (col == 'repair_partners') {
                await db.upsertRepairPartner(data);
              }
              successCount++;
            } catch (e) {
              errorCount++;
              debugPrint("  -> Error processing document ${doc.id}: $e");
            }
          }
          debugPrint(
            "  -> $col: success=$successCount, skipped=$skipCount, errors=$errorCount",
          );
        } catch (e) {
          debugPrint("Lỗi tải collection $col: $e");
        }
      }

      // Log local data counts after sync
      final localRepairsAfter = await db.getAllRepairs();
      final localProductsAfter = await db.getInStockProducts();
      final localSalesAfter = await db.getAllSales();
      final localAttendanceAfter = await db.getAllAttendance();
      final localExpenses = await db.getAllExpensesForSync();
      final localDebts = await db.getAllDebts();
      debugPrint(
        "LOCAL DATA AFTER SYNC: repairs=${localRepairsAfter.length}, products=${localProductsAfter.length}, sales=${localSalesAfter.length}, attendance=${localAttendanceAfter.length}, expenses=${localExpenses.length}, debts=${localDebts.length}",
      );

      debugPrint("Đã hoàn thành downloadAllFromCloud.");
    } catch (e) {
      debugPrint("Lỗi downloadAllFromCloud: $e");
    }
  }

  /// Đồng bộ Quick Input Codes lên Cloud
  static Future<void> syncQuickInputCodesToCloud() async {
    debugPrint("Bắt đầu syncQuickInputCodesToCloud...");
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint("Không có user, bỏ qua syncQuickInputCodesToCloud");
        return;
      }

      final String? shopId = await UserService.getCurrentShopId();
      final dbHelper = DBHelper();

      // Đồng bộ Quick Input Codes
      final quickInputCodes = await dbHelper.getUnsyncedQuickInputCodes();
      debugPrint(
        "syncQuickInputCodesToCloud: có ${quickInputCodes.length} quick input codes cần sync",
      );

      if (quickInputCodes.isNotEmpty) {
        final WriteBatch quickInputBatch = _db.batch();
        for (var code in quickInputCodes) {
          try {
            Map<String, dynamic> data = code.toMap();
            data['shopId'] = shopId;
            data.remove('id');

            final docId =
                code.firestoreId ??
                "qic_${code.createdAt}_${code.name.replaceAll(' ', '_')}";
            quickInputBatch.set(
              _db.collection('quick_input_codes').doc(docId),
              data,
              SetOptions(merge: true),
            );

            code.firestoreId = docId;
            code.shopId = shopId;
            code.isSynced = true;
            await dbHelper.updateQuickInputCode(code);
          } catch (e) {
            debugPrint("Lỗi sync quick input code ${code.id}: $e");
          }
        }
        await quickInputBatch.commit();
        debugPrint(
          "Đã đồng bộ thành công ${quickInputCodes.length} mã nhập nhanh lên Cloud",
        );
      } else {
        debugPrint("Không có mã nhập nhanh nào cần đồng bộ");
      }
    } catch (e) {
      debugPrint("Lỗi syncQuickInputCodesToCloud: $e");
      rethrow;
    }
  }

  /// Đồng bộ customers từ Cloud xuống local DB
  static Future<void> syncCustomersFromCloud() async {
    debugPrint("Bắt đầu syncCustomersFromCloud...");
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint("syncCustomersFromCloud: Không có user, bỏ qua");
        return;
      }

      final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();
      final String? shopId = isSuperAdmin
          ? null
          : await UserService.getCurrentShopId();
      debugPrint(
        "syncCustomersFromCloud: shopId = $shopId, isSuperAdmin = $isSuperAdmin",
      );

      final dbHelper = DBHelper();

      // Query customers từ Firestore
      Query query = _db.collection('customers');
      if (!isSuperAdmin && shopId != null) {
        query = query.where('shopId', isEqualTo: shopId);
      }

      final querySnapshot = await query.get();
      debugPrint(
        "syncCustomersFromCloud: Tìm thấy ${querySnapshot.docs.length} customers từ cloud",
      );

      // Upsert từng customer vào local DB
      for (var doc in querySnapshot.docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          data['firestoreId'] = doc.id;
          data['isSynced'] = true; // Đánh dấu đã sync

          // Chuyển đổi thành Customer model và upsert
          final customer = Customer.fromMap(data);
          await dbHelper.upsertCustomer(customer.toMap());
          debugPrint(
            "syncCustomersFromCloud: Đã upsert customer ${customer.name} (${doc.id})",
          );
        } catch (e) {
          debugPrint(
            "syncCustomersFromCloud: Lỗi upsert customer ${doc.id}: $e",
          );
        }
      }

      debugPrint(
        "syncCustomersFromCloud: Hoàn thành, đã sync ${querySnapshot.docs.length} customers",
      );
    } catch (e) {
      debugPrint("syncCustomersFromCloud: Lỗi: $e");
      rethrow;
    }
  }
}
