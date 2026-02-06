import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/product_model.dart';
import '../models/sale_order_model.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../models/attendance_model.dart';
import '../models/customer_model.dart';
import '../models/quick_input_code_model.dart';
import 'storage_service.dart';
import 'user_service.dart';
import 'encryption_service.dart';
import 'sync_orchestrator.dart';
import 'event_bus.dart';
import 'claims_service.dart';

class SyncService {
  static final _db = FirebaseFirestore.instance;
  static final List<StreamSubscription> _subscriptions = [];

  // Track active subscriptions and their status for debugging
  static final Map<String, bool> _subscriptionStatus = {};
  static VoidCallback? _onDataChangedCallback;
  static String? _currentShopId;
  static bool _isInitialized = false;

  /// Check if real-time sync is initialized and active
  static bool get isRealTimeSyncActive =>
      _isInitialized && _subscriptions.isNotEmpty;

  /// Get subscription status for debugging
  static Map<String, bool> get subscriptionStatus =>
      Map.unmodifiable(_subscriptionStatus);

  /// Helper: Lấy timestamp từ data (hỗ trợ cả Timestamp và int)
  static int _getTimestamp(dynamic value) {
    if (value == null) return 0;
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is int) return value;
    return 0;
  }

  /// Helper: Chuyển đổi tất cả Timestamp fields trong map sang milliseconds
  /// Để lưu vào SQLite (không hỗ trợ Firestore Timestamp)
  static void _convertTimestampFields(Map<String, dynamic> data) {
    final timestampFields = [
      'createdAt',
      'updatedAt',
      'checkInAt',
      'checkOutAt',
      'approvedAt',
      'startedAt',
      'finishedAt',
      'deliveredAt',
      'lastCaredAt',
      'soldAt',
      'paidAt',
      'lastVisitAt',
      'settlementPlannedAt',
      'settlementReceivedAt',
    ];
    for (final field in timestampFields) {
      if (data[field] is Timestamp) {
        data[field] = (data[field] as Timestamp).millisecondsSinceEpoch;
      }
    }
  }

  /// Helper: So sánh updatedAt để quyết định có ghi đè local hay không
  /// Returns: true nếu cloud data mới hơn hoặc bằng, false nếu local mới hơn
  static Future<bool> _shouldAcceptCloudData({
    required String collection,
    required String firestoreId,
    required Map<String, dynamic> cloudData,
  }) async {
    final db = DBHelper();
    final cloudUpdatedAt = _getTimestamp(cloudData['updatedAt']);

    // Nếu cloud không có updatedAt, dùng createdAt
    final cloudTime = cloudUpdatedAt > 0
        ? cloudUpdatedAt
        : _getTimestamp(cloudData['createdAt']);

    int localUpdatedAt = 0;
    bool localIsSynced = true;

    try {
      switch (collection) {
        case 'repairs':
          final local = await db.getRepairByFirestoreId(firestoreId);
          if (local != null) {
            // Repair model doesn't have updatedAt, use lastCaredAt or createdAt
            localUpdatedAt = local.lastCaredAt ?? local.createdAt;
            localIsSynced = local.isSynced;
          }
          break;
        case 'sales':
          final local = await db.getSaleByFirestoreId(firestoreId);
          if (local != null) {
            // SaleOrder model doesn't have updatedAt, use soldAt
            localUpdatedAt = local.soldAt;
            localIsSynced = local.isSynced;
          }
          break;
        case 'products':
          final local = await db.getProductByFirestoreId(firestoreId);
          if (local != null) {
            localUpdatedAt = local.updatedAt ?? local.createdAt;
            localIsSynced = local.isSynced;
          }
          break;
        case 'expenses':
          final local = await db.getExpenseByFirestoreId(firestoreId);
          if (local != null) {
            // Expense model không có updatedAt, dùng date làm thời gian tham chiếu
            localUpdatedAt = local.date;
            localIsSynced = local.isSynced;
          }
          break;
        case 'debts':
          final local = await db.getDebtByFirestoreId(firestoreId);
          if (local != null) {
            localUpdatedAt =
                local['updatedAt'] as int? ?? local['createdAt'] as int? ?? 0;
            localIsSynced = (local['isSynced'] as int?) == 1;
          }
          break;
        default:
          // Các collection khác: luôn accept cloud data
          return true;
      }
    } catch (e) {
      debugPrint('⚠️ Conflict check error for $collection/$firestoreId: $e');
      return true; // Nếu lỗi, accept cloud data
    }

    // Nếu local chưa tồn tại → accept cloud
    if (localUpdatedAt == 0) {
      debugPrint(
        '✅ SYNC: $collection/$firestoreId - Local không tồn tại, accept cloud',
      );
      return true;
    }

    // Nếu local đã sync (không có thay đổi pending) → accept cloud
    if (localIsSynced) {
      debugPrint(
        '✅ SYNC: $collection/$firestoreId - Local đã sync, accept cloud',
      );
      return true;
    }

    // Local có thay đổi chưa sync → so sánh timestamp
    if (cloudTime >= localUpdatedAt) {
      debugPrint(
        '✅ SYNC: $collection/$firestoreId - Cloud mới hơn (cloud: $cloudTime >= local: $localUpdatedAt), accept cloud',
      );
      return true;
    } else {
      debugPrint(
        '🔒 SYNC: $collection/$firestoreId - Local mới hơn (local: $localUpdatedAt > cloud: $cloudTime), SKIP cloud, enqueue local',
      );
      // Enqueue local data để push lên cloud
      await _enqueueLocalForSync(collection, firestoreId);
      return false;
    }
  }

  /// Helper: Enqueue local data để push lên cloud khi local mới hơn
  static Future<void> _enqueueLocalForSync(
    String collection,
    String firestoreId,
  ) async {
    final db = DBHelper();
    final orchestrator = SyncOrchestrator();

    try {
      switch (collection) {
        case 'repairs':
          final local = await db.getRepairByFirestoreId(firestoreId);
          if (local != null && local.id != null) {
            await orchestrator.enqueue(
              entityType: SyncEntityType.repair,
              entityId: local.id!,
              firestoreId: firestoreId,
              operation: SyncOperation.update,
              data: local.toMap(),
            );
          }
          break;
        case 'sales':
          final local = await db.getSaleByFirestoreId(firestoreId);
          if (local != null && local.id != null) {
            await orchestrator.enqueue(
              entityType: SyncEntityType.sale,
              entityId: local.id!,
              firestoreId: firestoreId,
              operation: SyncOperation.update,
              data: local.toMap(),
            );
          }
          break;
        case 'products':
          final local = await db.getProductByFirestoreId(firestoreId);
          if (local != null && local.id != null) {
            await orchestrator.enqueue(
              entityType: SyncEntityType.product,
              entityId: local.id!,
              firestoreId: firestoreId,
              operation: SyncOperation.update,
              data: local.toMap(),
            );
          }
          break;
        case 'expenses':
          final local = await db.getExpenseByFirestoreId(firestoreId);
          if (local != null && local.id != null) {
            await orchestrator.enqueue(
              entityType: SyncEntityType.expense,
              entityId: local.id!,
              firestoreId: firestoreId,
              operation: SyncOperation.update,
              data: local.toMap(),
            );
          }
          break;
        case 'debts':
          final local = await db.getDebtByFirestoreId(firestoreId);
          if (local != null && local['id'] != null) {
            await orchestrator.enqueue(
              entityType: SyncEntityType.debt,
              entityId: local['id'] as int,
              firestoreId: firestoreId,
              operation: SyncOperation.update,
              data: local,
            );
          }
          break;
      }
    } catch (e) {
      debugPrint('⚠️ Failed to enqueue local $collection/$firestoreId: $e');
    }

    // Best-effort: nếu đã enqueue thì cố gắng đẩy ngay lên cloud (tránh tình trạng "lúc được lúc không")
    // ignore: unawaited_futures
    orchestrator.syncAll();
  }

  /// Khởi tạo đồng bộ thời gian thực
  static Future<void> initRealTimeSync(VoidCallback onDataChanged) async {
    debugPrint("Khởi tạo real-time sync...");
    // Hủy các subscription cũ nếu có để tránh rò rỉ bộ nhớ hoặc lặp sự kiện
    await cancelAllSubscriptions();

    // Store callback for potential reinitialization
    _onDataChangedCallback = onDataChanged;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("initRealTimeSync: Không có user, bỏ qua");
      return;
    }

    final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();
    // Super admin cũng cần shopId nếu đã chọn shop
    final String? shopId = await UserService.getCurrentShopId();

    // Store shopId for later reference
    _currentShopId = shopId;

    // LOG QUAN TRỌNG: Hiển thị shopId được sử dụng để filter
    debugPrint(
      "⚡ initRealTimeSync: user=${user.uid}, email=${user.email}, shopId=$shopId, isSuperAdmin=$isSuperAdmin",
    );

    // ═══════════════════════════════════════════════════════════════════════
    // QUAN TRỌNG: Kiểm tra và refresh Custom Claims nếu cần
    // Firestore Rules yêu cầu token phải có shopId claim để truy cập data
    // ═══════════════════════════════════════════════════════════════════════
    if (!isSuperAdmin && shopId != null) {
      try {
        // Lấy claims từ token để kiểm tra
        final claims = await ClaimsService().getClaimsFromToken(
          forceRefresh: true,
        );
        final tokenShopId = claims?['shopId'];

        debugPrint(
          "🔑 Token claims: shopId=$tokenShopId, role=${claims?['role']}",
        );

        // Nếu shopId trong token không khớp với shopId từ Firestore, refresh claims
        if (tokenShopId != shopId) {
          debugPrint(
            "⚠️ Token shopId ($tokenShopId) != Firestore shopId ($shopId), refreshing claims...",
          );

          // Gọi Cloud Function để refresh claims
          final result = await ClaimsService().refreshMyClaims();
          debugPrint("🔄 refreshMyClaims result: $result");

          // Chờ và refresh token lại
          await Future.delayed(const Duration(seconds: 1));
          await user.getIdToken(true);

          // Kiểm tra lại claims sau khi refresh
          final newClaims = await ClaimsService().getClaimsFromToken(
            forceRefresh: true,
          );
          debugPrint(
            "✅ New token claims after refresh: shopId=${newClaims?['shopId']}, role=${newClaims?['role']}",
          );
        }
      } catch (e) {
        debugPrint("⚠️ Error checking/refreshing claims: $e");
      }
    }

    // Super admin phải chọn shop trước khi init real-time sync
    if (shopId == null) {
      if (isSuperAdmin) {
        debugPrint("⚠️ initRealTimeSync: Super admin chưa chọn shop, bỏ qua");
      } else {
        debugPrint("⚠️ initRealTimeSync: Không có shopId, bỏ qua");
      }
      return;
    }

    // AUTO-CLEANUP: Xóa orphan repair_parts bị stuck (không có firestoreId)
    // và force mark các records có firestoreId là đã sync
    try {
      final dbHelper = DBHelper();
      final orphansCleaned = await dbHelper.cleanupOrphanRepairParts();
      final forceMarked = await dbHelper.forceMarkRepairPartsSynced();
      if (orphansCleaned > 0 || forceMarked > 0) {
        debugPrint("🧹 Auto-cleanup: removed $orphansCleaned orphans, force-marked $forceMarked synced");
      }
    } catch (e) {
      debugPrint("⚠️ Auto-cleanup failed: $e");
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
            // CONFLICT RESOLUTION: So sánh updatedAt
            final shouldAccept = await _shouldAcceptCloudData(
              collection: 'repairs',
              firestoreId: docId,
              cloudData: data,
            );

            if (shouldAccept) {
              _convertTimestampFields(data);
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertRepair(Repair.fromMap(data));
              debugPrint(
                "SYNC_TRACE: Upserted repair $docId to local DB SUCCESSFULLY",
              );
            }
          }
        } catch (e) {
          debugPrint("SYNC_TRACE: Error syncing repair $docId: $e");
        }
      },
      onBatchDone: () {
        onDataChanged();
        // Emit event để cập nhật UI sửa chữa
        EventBus().emit('repairs_changed');
      },
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
            // CONFLICT RESOLUTION: So sánh updatedAt
            final shouldAccept = await _shouldAcceptCloudData(
              collection: 'sales',
              firestoreId: docId,
              cloudData: data,
            );

            if (shouldAccept) {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertSale(SaleOrder.fromMap(data));
              debugPrint(
                "SYNC_TRACE: Upserted sale $docId to local DB SUCCESSFULLY",
              );
            }
          }
        } catch (e) {
          debugPrint("SYNC_TRACE: Error syncing sale $docId: $e");
        }
      },
      onBatchDone: () {
        onDataChanged();
        // Emit event để cập nhật UI bán hàng
        EventBus().emit('sales_changed');
      },
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
            // CONFLICT RESOLUTION: So sánh updatedAt
            final shouldAccept = await _shouldAcceptCloudData(
              collection: 'products',
              firestoreId: docId,
              cloudData: data,
            );

            if (shouldAccept) {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud

              // Chuyển đổi Timestamp sang milliseconds cho SQLite
              if (data['createdAt'] is Timestamp) {
                data['createdAt'] =
                    (data['createdAt'] as Timestamp).millisecondsSinceEpoch;
              }
              if (data['updatedAt'] is Timestamp) {
                data['updatedAt'] =
                    (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
              }

              // BẢO TOÀN isPending và pendingSupplier từ local nếu cloud không có
              // (để tránh mất trạng thái Kho Tạm khi sync)
              final existingProduct = await db.getProductByFirestoreId(docId);
              if (existingProduct != null) {
                // Nếu local có isPending = true và cloud không có trường này
                // thì giữ nguyên giá trị local
                if (existingProduct.isPending && data['isPending'] == null) {
                  data['isPending'] = 1;
                  data['pendingSupplier'] = existingProduct.pendingSupplier;
                }
              }

              await db.upsertProduct(Product.fromMap(data));
            }
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
            // CONFLICT RESOLUTION: So sánh updatedAt
            final shouldAccept = await _shouldAcceptCloudData(
              collection: 'expenses',
              firestoreId: docId,
              cloudData: data,
            );

            if (shouldAccept) {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertExpense(Expense.fromMap(data));
            }
          }
        } catch (e) {
          debugPrint("Lỗi sync expense $docId: $e");
        }
      },
      onBatchDone: () {
        onDataChanged();
        // Emit event để cập nhật UI chi phí
        EventBus().emit('expenses_changed');
      },
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
            // CONFLICT RESOLUTION: So sánh updatedAt
            final shouldAccept = await _shouldAcceptCloudData(
              collection: 'debts',
              firestoreId: docId,
              cloudData: data,
            );

            if (shouldAccept) {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              await db.upsertDebt(Debt.fromMap(data));
            }
          }
        } catch (e) {
          debugPrint("Lỗi sync debt $docId: $e");
        }
      },
      onBatchDone: () {
        onDataChanged();
        // Emit event để cập nhật UI công nợ
        EventBus().emit('debts_changed');
      },
    );

    // 5b. Đồng bộ DEBT PAYMENTS (thanh toán công nợ)
    // FIX: Thêm real-time listener cho debt_payments - trước đây bị thiếu
    _subscribeToCollection(
      collection: 'debt_payments',
      shopId: shopId,
      onChanged: (data, docId) async {
        try {
          final db = DBHelper();
          if (data['deleted'] == true) {
            await db.deleteDebtPaymentByFirestoreId(docId);
          } else {
            data['firestoreId'] = docId;
            data['isSynced'] = 1;
            _convertTimestampFields(data);
            await db.upsertDebtPayment(data);
          }
        } catch (e) {
          debugPrint("Lỗi sync debt_payment $docId: $e");
        }
      },
      onBatchDone: () {
        onDataChanged();
        EventBus().emit(
          'debts_changed',
        ); // Debt payments cũng ảnh hưởng debt view
      },
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

    // 7. Đồng bộ SHOPS (subscribe trực tiếp vào document, không query by shopId)
    // Collection 'shops' sử dụng document ID = shopId, không có field 'shopId'
    final shopSub = _db.collection('shops').doc(shopId).snapshots().listen((
      snapshot,
    ) async {
      if (!snapshot.exists) return;
      final data = snapshot.data();
      if (data == null) return;

      try {
        debugPrint("📡 Shop data changed for shopId: $shopId");

        // Cập nhật SharedPreferences để các màn hình khác có thể đọc
        final prefs = await SharedPreferences.getInstance();
        final shopName = data['name']?.toString() ?? '';
        final shopAddress = data['address']?.toString() ?? '';
        final shopPhone = data['phone']?.toString() ?? '';

        await prefs.setString('shop_name', shopName);
        await prefs.setString('shop_address', shopAddress);
        await prefs.setString('shop_phone', shopPhone);

        debugPrint(
          "✅ Synced shop info to SharedPreferences: $shopName, $shopAddress, $shopPhone",
        );

        // Trigger UI update
        onDataChanged();
      } catch (e) {
        debugPrint("Lỗi sync shop $shopId: $e");
      }
    }, onError: (e) => debugPrint("Sync error in shops/$shopId: $e"));
    _subscriptions.add(shopSub);
  
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
              // Chuyển đổi Timestamp sang milliseconds cho SQLite
              if (data['checkInAt'] is Timestamp) {
                data['checkInAt'] =
                    (data['checkInAt'] as Timestamp).millisecondsSinceEpoch;
              }
              if (data['checkOutAt'] is Timestamp) {
                data['checkOutAt'] =
                    (data['checkOutAt'] as Timestamp).millisecondsSinceEpoch;
              }
              if (data['createdAt'] is Timestamp) {
                data['createdAt'] =
                    (data['createdAt'] as Timestamp).millisecondsSinceEpoch;
              }
              if (data['updatedAt'] is Timestamp) {
                data['updatedAt'] =
                    (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
              }
              if (data['approvedAt'] is Timestamp) {
                data['approvedAt'] =
                    (data['approvedAt'] as Timestamp).millisecondsSinceEpoch;
              }
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
        onBatchDone: () {
          onDataChanged();
          // Emit event để cập nhật UI quick_input_codes
          EventBus().emit('quick_input_codes_changed');
        },
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
              // Chuyển đổi Timestamp sang milliseconds cho SQLite
              if (data['createdAt'] is Timestamp) {
                data['createdAt'] =
                    (data['createdAt'] as Timestamp).millisecondsSinceEpoch;
              }
              // Map userName từ cloud
              data['userName'] =
                  data['userName'] ??
                  data['email']?.toString().split('@').first.toUpperCase() ??
                  'SYSTEM';
              // Map description từ summary
              data['description'] =
                  data['summary'] ?? data['description'] ?? '';
              // Map targetType và targetId từ entityType và entityId
              data['targetType'] =
                  data['targetType'] ?? data['entityType'] ?? '';
              data['targetId'] = data['targetId'] ?? data['entityId'] ?? '';
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

    // 16. Đồng bộ REPAIR PARTS (Kho linh kiện)
    try {
      _subscribeToCollection(
        collection: 'repair_parts',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteRepairPartByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1; // Đánh dấu đã sync từ cloud
              // Chuyển đổi Timestamp sang milliseconds cho SQLite
              if (data['createdAt'] is Timestamp) {
                data['createdAt'] =
                    (data['createdAt'] as Timestamp).millisecondsSinceEpoch;
              }
              if (data['updatedAt'] is Timestamp) {
                data['updatedAt'] =
                    (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
              }
              await db.upsertRepairPart(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync repair_part $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo repair_parts sync: $e");
    }

    // 17. Đồng bộ SUPPLIER IMPORT HISTORY (Lịch sử nhập hàng)
    // FIX BUG-001: Thêm real-time sync cho supplier_import_history
    try {
      _subscribeToCollection(
        collection: 'supplier_import_history',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteSupplierImportHistoryByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1;
              _convertTimestampFields(data);
              await db.upsertSupplierImportHistory(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync supplier_import_history $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo supplier_import_history sync: $e");
    }

    // 18. Đồng bộ SUPPLIER PRODUCT PRICES (Giá NCC)
    try {
      _subscribeToCollection(
        collection: 'supplier_product_prices',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteSupplierProductPriceByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1;
              _convertTimestampFields(data);
              await db.upsertSupplierProductPrice(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync supplier_product_price $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo supplier_product_prices sync: $e");
    }

    // 19. FIX BUG-CC-002: Đồng bộ CASH CLOSINGS (Chốt quỹ)
    // Để đảm bảo khi máy A chốt quỹ, máy B sẽ nhận được update ngay lập tức
    try {
      _subscribeToCollection(
        collection: 'cash_closings',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteCashClosingByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1;
              _convertTimestampFields(data);
              await db.upsertCashClosing(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync cash_closing $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo cash_closings sync: $e");
    }

    // 20. Đồng bộ ADJUSTMENT ENTRIES (Bút toán điều chỉnh)
    try {
      _subscribeToCollection(
        collection: 'adjustment_entries',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteAdjustmentEntryByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1;
              _convertTimestampFields(data);
              await db.upsertAdjustmentEntry(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync adjustment_entry $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo adjustment_entries sync: $e");
    }

    // 21. Đồng bộ PURCHASE ORDERS (Đơn đặt hàng NCC)
    try {
      _subscribeToCollection(
        collection: 'purchase_orders',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deletePurchaseOrderByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1;
              _convertTimestampFields(data);
              await db.upsertPurchaseOrder(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync purchase_order $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo purchase_orders sync: $e");
    }

    // 22. Đồng bộ PAYMENT INTENTS (Yêu cầu thanh toán)
    // FIX: Thêm real-time sync cho payment_intents để 2 máy cùng thấy các giao dịch chờ thanh toán
    try {
      _subscribeToCollection(
        collection: 'payment_intents',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deletePaymentIntentByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1;
              _convertTimestampFields(data);
              await db.upsertPaymentIntent(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync payment_intent $docId: $e");
          }
        },
        onBatchDone: () {
          onDataChanged();
          // Emit event để PaymentIntentService reload data
          EventBus().emit('payment_intents_changed');
        },
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo payment_intents sync: $e");
    }

    // Mark as initialized
    _isInitialized = true;

    debugPrint(
      "✅ Đã khởi tạo real-time sync cho ${isSuperAdmin ? 'super admin' : 'shop: $shopId'} với ${_subscriptions.length} subscriptions",
    );
    debugPrint("📊 Subscription status: $_subscriptionStatus");
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

    // Track subscription status
    _subscriptionStatus[collection] = true;

    final sub = query.snapshots().listen(
      (snapshot) async {
        // Log initial sync or updates
        debugPrint(
          "📥 Real-time snapshot for $collection: ${snapshot.docChanges.length} changes, total docs: ${snapshot.docs.length}",
        );

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
      },
      onError: (e) {
        final errorStr = e.toString();
        debugPrint("❌ Sync error in $collection: $errorStr");
        _subscriptionStatus[collection] = false;

        // Don't retry for permission-denied errors - this is a rules issue, not temporary
        if (errorStr.contains('permission-denied')) {
          debugPrint(
            "⚠️ Permission denied for $collection - skipping re-subscribe (check Firestore rules)",
          );
          return;
        }

        // Try to re-subscribe after error for other error types
        _scheduleResubscribe(collection, shopId, onChanged, onBatchDone);
      },
    );

    _subscriptions.add(sub);
  }

  /// Helper để xóa record local theo firestoreId khi cloud record đã bị soft-delete
  static Future<void> _deleteLocalByFirestoreId(
    DBHelper db,
    String collection,
    String firestoreId,
  ) async {
    try {
      switch (collection) {
        case 'repairs':
          await db.deleteRepairByFirestoreId(firestoreId);
          break;
        case 'products':
          await db.deleteProductByFirestoreId(firestoreId);
          break;
        case 'sales':
          await db.deleteSaleByFirestoreId(firestoreId);
          break;
        case 'expenses':
          await db.deleteExpenseByFirestoreId(firestoreId);
          break;
        case 'debts':
          await db.deleteDebtByFirestoreId(firestoreId);
          break;
        case 'debt_payments':
          await db.deleteDebtPaymentByFirestoreId(firestoreId);
          break;
        case 'attendance':
          await db.deleteAttendanceByFirestoreId(firestoreId);
          break;
        case 'quick_input_codes':
          await db.deleteQuickInputCodeByFirestoreId(firestoreId);
          break;
        case 'supplier_payments':
          await db.deleteSupplierPaymentByFirestoreId(firestoreId);
          break;
        case 'repair_partner_payments':
          await db.deleteRepairPartnerPaymentByFirestoreId(firestoreId);
          break;
        case 'customers':
          await db.deleteCustomerByFirestoreId(firestoreId);
          break;
        case 'suppliers':
          await db.deleteSupplierByFirestoreId(firestoreId);
          break;
        case 'repair_partners':
          await db.deleteRepairPartnerByFirestoreId(firestoreId);
          break;
        case 'repair_parts':
          await db.deleteRepairPartByFirestoreId(firestoreId);
          break;
        case 'payment_intents':
          await db.deletePaymentIntentByFirestoreId(firestoreId);
          break;
      }
      debugPrint(
        "  -> Deleted local $collection record: $firestoreId (soft-deleted on cloud)",
      );
    } catch (e) {
      debugPrint("  -> Error deleting local $collection $firestoreId: $e");
    }
  }

  static Future<void> cancelAllSubscriptions() async {
    debugPrint('🔴 Canceling all ${_subscriptions.length} subscriptions...');
    for (var sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    _subscriptionStatus.clear();
    _isInitialized = false;
    _currentShopId = null;
    debugPrint('✅ All subscriptions cancelled');
  }

  /// Schedule re-subscribe after an error with exponential backoff
  static void _scheduleResubscribe(
    String collection,
    String? shopId,
    Future<void> Function(Map<String, dynamic> data, String docId) onChanged,
    VoidCallback onBatchDone,
  ) {
    // Delay 5 seconds before resubscribing to avoid rapid reconnection loops
    Future.delayed(const Duration(seconds: 5), () {
      if (_subscriptionStatus[collection] == false) {
        debugPrint(
          '🔄 Attempting to re-subscribe to $collection after error...',
        );
        _subscribeToCollection(
          collection: collection,
          shopId: shopId,
          onChanged: onChanged,
          onBatchDone: onBatchDone,
        );
      }
    });
  }

  /// Force reinitialize real-time sync (useful when sync appears broken)
  static Future<void> forceReinitializeSync() async {
    debugPrint('🔄 Force reinitializing real-time sync...');
    await cancelAllSubscriptions();

    if (_onDataChangedCallback != null) {
      await initRealTimeSync(_onDataChangedCallback!);
    } else {
      debugPrint('⚠️ No callback stored, cannot reinitialize');
    }
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
                expense.isSynced) {
              continue;
            }

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
          if (a.firestoreId != null && a.firestoreId!.isNotEmpty) {
            continue; // Đã sync rồi
          }

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
                supplierMap['firestoreId'].toString().isNotEmpty) {
              continue;
            }

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

              // Update local với firestoreId (tạo map mới vì supplierMap là read-only)
              final updateData = Map<String, dynamic>.from(supplierMap);
              updateData['firestoreId'] = docId;
              await dbHelper.upsertSupplier(updateData);
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
                partnerMap['firestoreId'].toString().isNotEmpty) {
              continue;
            }

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

              // Update local với firestoreId (tạo map mới vì partnerMap là read-only)
              final updateData = Map<String, dynamic>.from(partnerMap);
              updateData['firestoreId'] = docId;
              await dbHelper.upsertRepairPartner(updateData);
            } catch (e) {
              debugPrint("Lỗi sync repair partner ${partnerMap['id']}: $e");
            }
          }
          await partnerBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync repair partners collection: $e");
      }

      // Đồng bộ Supplier Payments
      try {
        final supplierPayments = await dbHelper.getSupplierPaymentsForSync();
        debugPrint(
          "syncAllToCloud: có ${supplierPayments.length} supplier payments cần kiểm tra sync",
        );
        if (supplierPayments.isNotEmpty) {
          final WriteBatch supplierPaymentBatch = _db.batch();
          for (var paymentMap in supplierPayments) {
            final firestoreId = paymentMap['firestoreId'];
            final isSynced =
                paymentMap['isSynced'] == 1 || paymentMap['isSynced'] == true;
            if (firestoreId != null &&
                firestoreId.toString().isNotEmpty &&
                isSynced) {
              continue;
            }

            try {
              final data = Map<String, dynamic>.from(paymentMap);
              data['shopId'] = shopId;
              data['deleted'] = data['deleted'] == 1 || data['deleted'] == true;
              data.remove('id');

              final docId = firestoreId ??
                  "sup_pay_${data['paidAt']}_${data['supplierId'] ?? 'sup'}";
              supplierPaymentBatch.set(
                _db.collection('supplier_payments').doc(docId),
                data,
                SetOptions(merge: true),
              );

              await dbHelper.updateSupplierPayment(
                paymentMap['id'],
                {'firestoreId': docId, 'isSynced': 1},
              );
            } catch (e) {
              debugPrint("Lỗi sync supplier payment ${paymentMap['id']}: $e");
            }
          }
          await supplierPaymentBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync supplier payments collection: $e");
      }

      // Đồng bộ Repair Partner Payments
      try {
        final partnerPayments = await dbHelper.getRepairPartnerPaymentsForSync();
        debugPrint(
          "syncAllToCloud: có ${partnerPayments.length} repair partner payments cần kiểm tra sync",
        );
        if (partnerPayments.isNotEmpty) {
          final WriteBatch partnerPaymentBatch = _db.batch();
          for (var paymentMap in partnerPayments) {
            final firestoreId = paymentMap['firestoreId'];
            final isSynced =
                paymentMap['isSynced'] == 1 || paymentMap['isSynced'] == true;
            if (firestoreId != null &&
                firestoreId.toString().isNotEmpty &&
                isSynced) {
              continue;
            }

            try {
              final data = Map<String, dynamic>.from(paymentMap);
              data['shopId'] = shopId;
              data['deleted'] = data['deleted'] == 1 || data['deleted'] == true;
              data.remove('id');

              final docId = firestoreId ??
                  "part_pay_${data['paidAt']}_${data['partnerId'] ?? 'partner'}";
              partnerPaymentBatch.set(
                _db.collection('repair_partner_payments').doc(docId),
                data,
                SetOptions(merge: true),
              );

              await dbHelper.updateRepairPartnerPayment(
                paymentMap['id'],
                {'firestoreId': docId, 'isSynced': 1},
              );
            } catch (e) {
              debugPrint(
                "Lỗi sync repair partner payment ${paymentMap['id']}: $e",
              );
            }
          }
          await partnerPaymentBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync repair partner payments collection: $e");
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
                isSynced) {
              continue;
            }

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
                isSynced) {
              continue;
            }

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

      // Đồng bộ Repair Parts (Kho linh kiện)
      try {
        final repairParts = await dbHelper.getUnsyncedRepairParts();
        debugPrint(
          "syncAllToCloud: có ${repairParts.length} repair parts cần sync",
        );
        if (repairParts.isNotEmpty) {
          final WriteBatch partsBatch = _db.batch();
          for (var partMap in repairParts) {
            try {
              Map<String, dynamic> data = Map<String, dynamic>.from(partMap);
              data['shopId'] = shopId;
              final localId = data['id'];
              data.remove('id');

              final docId =
                  partMap['firestoreId'] ??
                  "part_${data['createdAt']}_${data['partName'].toString().replaceAll(' ', '_')}";
              partsBatch.set(
                _db.collection('repair_parts').doc(docId),
                data,
                SetOptions(merge: true),
              );

              // Update local với firestoreId và isSynced
              await dbHelper.updateRepairPartSynced(localId, docId);
            } catch (e) {
              debugPrint("Lỗi sync repair part ${partMap['id']}: $e");
            }
          }
          await partsBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync repair parts collection: $e");
      }

      // Đồng bộ Payment Intents (Yêu cầu thanh toán)
      // FIX: Thêm sync cho payment_intents để 2 máy cùng thấy các giao dịch chờ thanh toán
      try {
        final paymentIntents = await dbHelper.getPaymentIntentsForSync();
        debugPrint(
          "syncAllToCloud: có ${paymentIntents.length} payment intents cần sync",
        );
        if (paymentIntents.isNotEmpty) {
          final WriteBatch intentBatch = _db.batch();
          for (var intentMap in paymentIntents) {
            final firestoreId = intentMap['firestoreId'];
            final isSynced =
                intentMap['isSynced'] == 1 || intentMap['isSynced'] == true;
            if (firestoreId != null &&
                firestoreId.toString().isNotEmpty &&
                isSynced) {
              continue;
            }

            try {
              final data = Map<String, dynamic>.from(intentMap);
              data['shopId'] = shopId;
              data['deleted'] = data['deleted'] == 1 || data['deleted'] == true;
              final localId = data['id'];
              data.remove('id');

              final docId = firestoreId ??
                  "pi_${data['intentId'] ?? data['createdAt']}_${data['type'] ?? 'unknown'}";
              intentBatch.set(
                _db.collection('payment_intents').doc(docId),
                data,
                SetOptions(merge: true),
              );

              await dbHelper.updatePaymentIntentSynced(localId, docId);
            } catch (e) {
              debugPrint("Lỗi sync payment intent ${intentMap['id']}: $e");
            }
          }
          await intentBatch.commit();
        }
      } catch (e) {
        debugPrint("Lỗi sync payment intents collection: $e");
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
      if (user == null) {
        debugPrint("downloadAllFromCloud: Không có user, bỏ qua");
        return;
      }

      final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();
      String? shopId = await UserService.getCurrentShopId();

      // LOG QUAN TRỌNG: Hiển thị shopId được sử dụng
      debugPrint(
        "⚡ downloadAllFromCloud: user=${user.uid}, email=${user.email}, shopId=$shopId, isSuperAdmin=$isSuperAdmin",
      );

      // Retry lấy shopId nếu chưa có (claims có thể chưa sync)
      if (shopId == null && !isSuperAdmin) {
        debugPrint("⚠️ shopId null, thử refresh claims...");
        for (int retry = 0; retry < 3; retry++) {
          await Future.delayed(const Duration(seconds: 2));
          try {
            await user.getIdToken(true);
            await ClaimsService().forceRefresh();
            shopId = await UserService.getCurrentShopId();
            if (shopId != null) {
              debugPrint("✅ Lấy được shopId sau retry ${retry + 1}: $shopId");
              break;
            }
          } catch (e) {
            debugPrint("Retry ${retry + 1}/3 lấy shopId: $e");
          }
        }
      }

      // Cần có shopId để sync (super admin phải chọn shop trước)
      if (shopId == null) {
        if (isSuperAdmin) {
          debugPrint(
            "⚠️ Super admin chưa chọn shop, bỏ qua downloadAllFromCloud",
          );
        } else {
          debugPrint(
            "⚠️ Không có shopId sau 3 retry, bỏ qua downloadAllFromCloud",
          );
        }
        return;
      }

      // Log local data counts before sync
      final localRepairs = await db.getAllRepairs();
      final localProducts = await db.getAllProducts();
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
        'repair_parts',
        'supplier_import_history',
        'supplier_product_prices',
        'audit_logs', // FIX: Thêm để device mới download được lịch sử thao tác
        'payment_intents', // FIX: Thêm để đồng bộ các yêu cầu thanh toán giữa các máy
      ];
      // Lưu ý: 'users' và 'shops' không có shopId field nên không tải ở đây

      for (var col in collections) {
        // Yield to UI thread between collections to prevent ANR/frame drops
        await Future.delayed(Duration.zero);

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

          // Process in batches of 50 to avoid blocking main thread
          final docs = snap.docs;
          for (int i = 0; i < docs.length; i++) {
            // Yield every 50 documents to prevent frame drops
            if (i > 0 && i % 50 == 0) {
              await Future.delayed(Duration.zero);
            }

            final doc = docs[i];
            try {
              var data = doc.data();
              if (data['deleted'] == true) {
                // Xóa record local nếu đã bị soft-delete trên cloud
                await _deleteLocalByFirestoreId(db, col, doc.id);
                skipCount++;
                continue; // Skip soft-deleted documents
              }

              // Giải mã dữ liệu nếu được mã hóa
              data = EncryptionService.decryptMap(data);
              data['firestoreId'] = doc.id;
              data['isSynced'] = 1; // QUAN TRỌNG: Đánh dấu đã sync từ cloud

              // Chuyển đổi tất cả Timestamp fields sang milliseconds cho SQLite
              _convertTimestampFields(data);

              if (col == 'repairs') {
                await db.upsertRepair(Repair.fromMap(data));
              } else if (col == 'products') {
                // BẢO TOÀN isPending và pendingSupplier từ local nếu cloud không có
                final existingProduct = await db.getProductByFirestoreId(
                  doc.id,
                );
                if (existingProduct != null) {
                  if (existingProduct.isPending && data['isPending'] == null) {
                    data['isPending'] = 1;
                    data['pendingSupplier'] = existingProduct.pendingSupplier;
                  }
                }
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
              } else if (col == 'repair_parts') {
                await db.upsertRepairPart(data);
              } else if (col == 'supplier_import_history') {
                await db.upsertSupplierImportHistory(data);
              } else if (col == 'supplier_product_prices') {
                await db.upsertSupplierProductPrice(data);
              } else if (col == 'audit_logs') {
                // Map fields cho audit_logs
                data['userName'] =
                    data['userName'] ??
                    data['email']?.toString().split('@').first.toUpperCase() ??
                    'SYSTEM';
                data['description'] =
                    data['summary'] ?? data['description'] ?? '';
                data['targetType'] =
                    data['targetType'] ?? data['entityType'] ?? '';
                data['targetId'] = data['targetId'] ?? data['entityId'] ?? '';
                await db.upsertAuditLog(data);
              } else if (col == 'payment_intents') {
                await db.upsertPaymentIntent(data);
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
      final localProductsAfter = await db.getAllProducts();
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

      // Nếu không có shopId và không phải super admin, bỏ qua
      if (!isSuperAdmin && (shopId == null || shopId.isEmpty)) {
        debugPrint("syncCustomersFromCloud: Không có shopId, bỏ qua");
        return;
      }

      final dbHelper = DBHelper();

      // Query customers từ Firestore
      Query query = _db.collection('customers');
      if (!isSuperAdmin && shopId != null) {
        query = query.where('shopId', isEqualTo: shopId);
      }

      // Refresh token trước khi query để đảm bảo claims được cập nhật
      try {
        await user.getIdToken(true);
      } catch (e) {
        debugPrint("syncCustomersFromCloud: Không thể refresh token: $e");
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
