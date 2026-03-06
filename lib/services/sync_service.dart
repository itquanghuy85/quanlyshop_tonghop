import 'dart:async';
import 'dart:convert';
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
import 'shop_deletion_service.dart';
import '../utils/perf_monitor.dart';

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

  static List<String> _splitImagePaths(String? csv) {
    if (csv == null || csv.trim().isEmpty) return const [];

    final raw = csv.trim();
    final output = <String>[];

    void addCandidate(String? value) {
      if (value == null) return;
      var s = value.trim();
      if (s.isEmpty) return;
      if ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'"))) {
        s = s.substring(1, s.length - 1).trim();
      }
      if (s.startsWith('[') && s.endsWith(']')) {
        s = s.substring(1, s.length - 1).trim();
      }
      if (s.isEmpty) return;
      if (!output.contains(s)) {
        output.add(s);
      }
    }

    if (raw.startsWith('[') && raw.endsWith(']')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            addCandidate(item?.toString());
          }
          if (output.isNotEmpty) return output;
        }
      } catch (_) {
        // Continue with delimiter fallback.
      }
    }

    for (final part in raw.split(RegExp(r'[,;\n]'))) {
      addCandidate(part);
    }

    return output;
  }

  static bool _isCloudImagePath(String path) {
    return path.startsWith('http://') ||
        path.startsWith('https://') ||
        path.startsWith('gs://');
  }

  static bool _hasLocalImagePath(String? csv) {
    return _splitImagePaths(csv).any((p) => !_isCloudImagePath(p));
  }

  static String _normalizeLegacyShopName(String? rawName) {
    final name = (rawName ?? '').trim();
    if (name.isEmpty) return 'QUAN LY SHOP';
    final lower = name.toLowerCase();
    if (lower == 'shop new' || lower == 'shop_new' || lower == 'shopnew') {
      return 'QUAN LY SHOP';
    }
    return name;
  }

  /// Public wrapper cho _convertTimestampFields (dùng bởi SyncHealthCheck.autoFix)
  static void convertTimestampFieldsPublic(Map<String, dynamic> data) =>
      _convertTimestampFields(data);

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

    // Local có thay đổi chưa sync (isSynced=false) → LUÔN giữ local
    // Đây là fix cho race condition: khi vừa cập nhật status, cloud listener
    // có thể trả về data cũ (echo) và ghi đè local changes
    debugPrint(
      '🔒 SYNC: $collection/$firestoreId - Local chưa sync (isSynced=false), SKIP cloud (cloud: $cloudTime, local: $localUpdatedAt), enqueue local',
    );
    // Enqueue local data để push lên cloud
    await _enqueueLocalForSync(collection, firestoreId);
    return false;
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
    PerfMonitor.start('initRealTimeSync');
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
    // force mark các records có firestoreId là đã sync
    // và fix records bị stuck deleted=1 do bug cũ
    try {
      final dbHelper = DBHelper();
      final deduped = await dbHelper.cleanupCloudShadowDuplicates();
      final orphansCleaned = await dbHelper.cleanupOrphanRepairParts();
      final forceMarked = await dbHelper.forceMarkRepairPartsSynced();
      final stuckFixed = await dbHelper.fixStuckDeletedRepairParts();
      if (deduped > 0 || orphansCleaned > 0 || forceMarked > 0 || stuckFixed > 0) {
        debugPrint("🧹 Auto-cleanup: deduped $deduped cloud-shadow rows, removed $orphansCleaned orphans, force-marked $forceMarked synced, fixed $stuckFixed stuck-deleted");
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
        // Chỉ emit EventBus — HomeView + các view khác đã listen EventBus
        // (bỏ onDataChanged() để tránh double-hit reload)
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
        // Chỉ emit EventBus — tránh double-hit reload
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

              // Map 'detail' → 'description' nếu cloud chỉ có 'detail' (backward compat)
              if (data['description'] == null && data['detail'] != null) {
                data['description'] = data['detail'];
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
        // Chỉ emit EventBus — tránh double-hit reload
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
        // Chỉ emit EventBus — tránh double-hit reload
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
        // Chỉ emit EventBus — tránh double-hit reload
        EventBus().emit('debts_changed');
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
        final shopName = _normalizeLegacyShopName(data['name']?.toString());
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

    // ═══════════════════════════════════════════════════════════════════════
    // CRITICAL subscriptions done — mark as initialized so UI can proceed
    // ═══════════════════════════════════════════════════════════════════════
    _isInitialized = true;
    PerfMonitor.stop('initRealTimeSync');
    debugPrint(
      "✅ Critical sync ready (${_subscriptions.length} subs) — "
      "deferred collections will load in 3s...",
    );

    // Schedule DEFERRED subscriptions after 3s to reduce initial load
    Future.delayed(const Duration(seconds: 3), () {
      if (_currentShopId != shopId) {
        debugPrint('⚠️ Shop changed before deferred sync — skipping');
        return;
      }
      _initDeferredSubscriptions(
        shopId: shopId,
        isSuperAdmin: isSuperAdmin,
        onDataChanged: onDataChanged,
      );
    });

    debugPrint(
      "📊 Subscription status: $_subscriptionStatus",
    );
  }

  /// Khởi tạo các subscription KHÔNG CẤP BÁCH sau 3 giây delay
  /// (attendance, suppliers, audit_logs, cash_closings, v.v.)
  static void _initDeferredSubscriptions({
    required String? shopId,
    required bool isSuperAdmin,
    required VoidCallback onDataChanged,
  }) {
    debugPrint("🕐 Starting deferred sync subscriptions...");
    PerfMonitor.start('deferredSync');

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
          // Chỉ emit EventBus — tránh double-hit reload
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

    // 14b. Đồng bộ PARTNER REPAIR HISTORY (lịch sử gửi sửa đối tác)
    try {
      _subscribeToCollection(
        collection: 'partner_repair_history',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deletePartnerRepairHistoryByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1;
              // Convert Timestamp to milliseconds for SQLite
              if (data['sentAt'] is Timestamp) {
                data['sentAt'] =
                    (data['sentAt'] as Timestamp).millisecondsSinceEpoch;
              }
              if (data['updatedAt'] is Timestamp) {
                data['updatedAt'] =
                    (data['updatedAt'] as Timestamp).millisecondsSinceEpoch;
              }
              await db.upsertPartnerRepairHistory(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync partner_repair_history $docId: $e");
          }
        },
        onBatchDone: onDataChanged,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo partner_repair_history sync: $e");
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

    // 23. Đồng bộ WORK SCHEDULES (Lịch làm việc nhân viên)
    try {
      _subscribeToCollection(
        collection: 'work_schedules',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              // Không xóa hẳn, chỉ bỏ qua
              debugPrint("Work schedule $docId marked as deleted");
            } else {
              // Lấy userId từ docId (format: staff_<userId>_<shopId>)
              String? userId;
              if (docId.startsWith('staff_')) {
                final parts = docId.split('_');
                if (parts.length >= 2) {
                  userId = parts[1];
                }
              }
              if (userId != null && userId.isNotEmpty) {
                final scheduleData = Map<String, dynamic>.from(data);
                _convertTimestampFields(scheduleData);
                await db.upsertWorkSchedule(userId, scheduleData);
                debugPrint("✅ Synced work_schedule for user $userId");
              }
            }
          } catch (e) {
            debugPrint("Lỗi sync work_schedule $docId: $e");
          }
        },
        onBatchDone: () {
          onDataChanged();
          EventBus().emit('work_schedules_changed');
        },
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo work_schedules sync: $e");
    }

    // 24. Đồng bộ EMPLOYEE SALARY SETTINGS (Cài đặt lương nhân viên)
    try {
      _subscribeToCollection(
        collection: 'employee_salary_settings',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['deleted'] == true) {
              await db.deleteEmployeeSalarySettingsByFirestoreId(docId);
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1;
              _convertTimestampFields(data);
              await db.upsertEmployeeSalarySettings(data);
              debugPrint("✅ Synced employee_salary_setting for ${data['staffId']}");
            }
          } catch (e) {
            debugPrint("Lỗi sync employee_salary_setting $docId: $e");
          }
        },
        onBatchDone: () {
          onDataChanged();
          EventBus().emit('employee_salary_settings_changed');
        },
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo employee_salary_settings sync: $e");
    }

    // === MULTI-INDUSTRY EXPANSION - Phase 1 (v75) ===

    // 25. Đồng bộ PRODUCT CATEGORIES (Danh mục sản phẩm)
    try {
      // Categories được lưu trong subcollection của shops
      final categoriesSub = _db
          .collection('shops')
          .doc(shopId)
          .collection('product_categories')
          .snapshots()
          .listen((snapshot) async {
        for (final change in snapshot.docChanges) {
          try {
            final docId = change.doc.id;
            final data = change.doc.data() ?? {};
            final db = DBHelper();

            if (data['isActive'] == false) {
              // Soft delete locally
              await db.rawUpdate(
                'UPDATE product_categories SET isActive = 0 WHERE firestoreId = ?',
                [docId],
              );
            } else {
              data['firestoreId'] = docId;
              data['shopId'] = shopId;
              data['isSynced'] = 1;
              _convertTimestampFields(data);
              await db.upsertProductCategory(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync product_category ${change.doc.id}: $e");
          }
        }
        onDataChanged();
        EventBus().emit('product_categories_changed');
      }, onError: (e) => debugPrint("Sync error in product_categories: $e"));
      _subscriptions.add(categoriesSub);
    } catch (e) {
      debugPrint("Lỗi khởi tạo product_categories sync: $e");
    }

    // 26. Đồng bộ PRODUCT VARIANTS (Biến thể sản phẩm)
    try {
      _subscribeToCollection(
        collection: 'product_variants',
        shopId: shopId,
        onChanged: (data, docId) async {
          try {
            final db = DBHelper();
            if (data['isActive'] == false) {
              await db.rawUpdate(
                'UPDATE product_variants SET isActive = 0 WHERE firestoreId = ?',
                [docId],
              );
            } else {
              data['firestoreId'] = docId;
              data['isSynced'] = 1;
              _convertTimestampFields(data);
              await db.upsertProductVariant(data);
            }
          } catch (e) {
            debugPrint("Lỗi sync product_variant $docId: $e");
          }
        },
        onBatchDone: () {
          onDataChanged();
          EventBus().emit('product_variants_changed');
        },
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo product_variants sync: $e");
    }

    PerfMonitor.stop('deferredSync');
    debugPrint(
      "✅ Deferred sync done — total ${_subscriptions.length} subscriptions active "
      "for ${isSuperAdmin ? 'super admin' : 'shop: $shopId'}",
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
    // Skip nếu shop đang bị xóa
    if (shopId != null && ShopDeletionService.isShopBeingDeleted(shopId)) {
      debugPrint("⏭️ Skipping subscribe to $collection - shop $shopId is being deleted");
      return;
    }
    
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
        // Double check shop không bị xóa trong lúc đang xử lý
        if (shopId != null && ShopDeletionService.isShopBeingDeleted(shopId)) {
          debugPrint("⏭️ Ignoring snapshot for $collection - shop $shopId is being deleted");
          return;
        }
        
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

        // Check for permission-denied errors
        final isPermissionError = errorStr.contains('permission-denied') ||
            errorStr.contains('PERMISSION_DENIED') ||
            errorStr.contains('Missing or insufficient permissions');
        
        if (isPermissionError) {
          debugPrint(
            "🔒 Permission denied for $collection - shop may be deleted or user lost access",
          );
          
          // Emit event để UI biết
          EventBus().emit('permission_denied:$collection');
          
          // Nếu đây là collection repairs và shopId đang bị xóa, không retry
          if (shopId != null && ShopDeletionService.isShopBeingDeleted(shopId)) {
            debugPrint("⏭️ Shop is being deleted, not retrying");
            return;
          }
          
          // Không retry cho permission errors - đây là lỗi cấu hình hoặc shop bị xóa
          debugPrint(
            "⚠️ Permission denied for $collection - skipping re-subscribe (check Firestore rules or shop status)",
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

  /// Sync payment-related data immediately after payment execution
  /// Targets: payment_intents, debt_payments, expenses, financial_activity_log
  /// Much faster than syncAllToCloud() since it only syncs payment-related tables
  static Future<void> syncPaymentRelatedData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final String? shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;

      // FIX: Super admin có shopId → cho phép sync (không block nữa)

      final dbHelper = DBHelper();
      debugPrint('⚡ syncPaymentRelatedData: starting targeted sync...');

      // 1. Sync payment_intents
      try {
        final paymentIntents = await dbHelper.getPaymentIntentsForSync();
        if (paymentIntents.isNotEmpty) {
          final WriteBatch batch = _db.batch();
          for (var intentMap in paymentIntents) {
            final firestoreId = intentMap['firestoreId'];
            final isSynced = intentMap['isSynced'] == 1 || intentMap['isSynced'] == true;
            if (firestoreId != null && firestoreId.toString().isNotEmpty && isSynced) continue;

            final data = Map<String, dynamic>.from(intentMap);
            data['shopId'] = shopId;
            data['deleted'] = data['deleted'] == 1 || data['deleted'] == true;
            final localId = data['id'];
            data.remove('id');

            final docId = firestoreId ?? "pi_${data['intentId'] ?? data['createdAt']}_${data['type'] ?? 'unknown'}";
            batch.set(_db.collection('payment_intents').doc(docId), data, SetOptions(merge: true));
            await dbHelper.updatePaymentIntentSynced(localId, docId);
          }
          await batch.commit();
          debugPrint('  -> Synced ${paymentIntents.length} payment intents');
        }
      } catch (e) {
        debugPrint('  -> Error syncing payment_intents: $e');
      }

      // 2. Sync debt_payments
      try {
        final debtPayments = await dbHelper.getAllDebtPaymentsForSync();
        if (debtPayments.isNotEmpty) {
          final WriteBatch batch = _db.batch();
          int count = 0;
          for (var dp in debtPayments) {
            final firestoreId = dp['firestoreId'];
            final isSynced = dp['isSynced'] == 1 || dp['isSynced'] == true;
            if (firestoreId != null && firestoreId.toString().isNotEmpty && isSynced) continue;

            final data = Map<String, dynamic>.from(dp);
            data['shopId'] = shopId;
            final localId = data['id'];
            data.remove('id');

            final docId = firestoreId ?? "dp_${data['debtId']}_${data['paidAt'] ?? data['createdAt']}";
            batch.set(_db.collection('debt_payments').doc(docId), data, SetOptions(merge: true));
            await dbHelper.updateDebtPaymentSynced(localId as int, docId);
            count++;
          }
          if (count > 0) {
            await batch.commit();
            debugPrint('  -> Synced $count debt payments');
          }
        }
      } catch (e) {
        debugPrint('  -> Error syncing debt_payments: $e');
      }

      // 3. Sync debts (status may have changed after payment)
      try {
        final debts = await dbHelper.getAllDebts();
        final unsyncedDebts = debts.where((d) => d['isSynced'] != 1 && d['isSynced'] != true).toList();
        if (unsyncedDebts.isNotEmpty) {
          final WriteBatch batch = _db.batch();
          int count = 0;
          for (var debt in unsyncedDebts) {
            final firestoreId = debt['firestoreId'];
            if (firestoreId == null || firestoreId.toString().isEmpty) continue;

            final data = Map<String, dynamic>.from(debt);
            data['shopId'] = shopId;
            data['deleted'] = data['deleted'] == 1 || data['deleted'] == true;
            data.remove('id');

            batch.set(_db.collection('debts').doc(firestoreId), data, SetOptions(merge: true));
            count++;
          }
          if (count > 0) {
            await batch.commit();
            debugPrint('  -> Synced $count debts');
          }
        }
      } catch (e) {
        debugPrint('  -> Error syncing debts: $e');
      }

      // 4. Sync expenses (in case payment created an expense)
      try {
        final expenses = await dbHelper.getAllExpensesForSync();
        final unsyncedExpenses = expenses.where((e) => e.isSynced != 1).toList();
        if (unsyncedExpenses.isNotEmpty) {
          final WriteBatch batch = _db.batch();
          int count = 0;
          for (var expense in unsyncedExpenses) {
            final data = expense.toMap();
            data['shopId'] = shopId;
            data['deleted'] = data['deleted'] == 1 || data['deleted'] == true;
            final localId = data['id'];
            data.remove('id');

            final docId = expense.firestoreId ?? "exp_${expense.date}_${expense.amount}";
            batch.set(_db.collection('expenses').doc(docId), data, SetOptions(merge: true));

            // Mark as synced
            final updatedExpense = Expense.fromMap({...expense.toMap(), 'firestoreId': docId, 'isSynced': 1});
            await dbHelper.updateExpense(updatedExpense);
            count++;
          }
          if (count > 0) {
            await batch.commit();
            debugPrint('  -> Synced $count expenses');
          }
        }
      } catch (e) {
        debugPrint('  -> Error syncing expenses: $e');
      }

      // 5. Sync financial_activity_log
      try {
        final activities = await dbHelper.getUnsyncedFinancialActivities();
        if (activities.isNotEmpty) {
          final WriteBatch batch = _db.batch();
          int count = 0;
          for (var act in activities) {
            final data = Map<String, dynamic>.from(act);
            data['shopId'] = shopId;
            final localId = data['id'];
            data.remove('id');

            final docId = data['firestoreId'] ?? "fal_${data['createdAt']}_${data['activityType'] ?? 'unknown'}";
            batch.set(_db.collection('financial_activity_log').doc(docId), data, SetOptions(merge: true));

            // Mark as synced
            await dbHelper.updateFinancialActivitySynced(localId as int, docId);
            count++;
          }
          if (count > 0) {
            await batch.commit();
            debugPrint('  -> Synced $count financial activities');
          }
        }
      } catch (e) {
        debugPrint('  -> Error syncing financial_activity_log: $e');
      }

      // 6. Sync supplier_payments and repair_partner_payments
      try {
        final supplierPayments = await dbHelper.getSupplierPaymentsForSync();
        final unsyncedSP = supplierPayments.where((sp) => sp['isSynced'] != 1 && sp['isSynced'] != true).toList();
        if (unsyncedSP.isNotEmpty) {
          final WriteBatch batch = _db.batch();
          int count = 0;
          final List<Map<String, dynamic>> toMarkSynced = [];
          for (var sp in unsyncedSP) {
            final firestoreId = sp['firestoreId'];
            final data = Map<String, dynamic>.from(sp);
            data['shopId'] = shopId;
            data['deleted'] = data['deleted'] == 1 || data['deleted'] == true;
            final localId = data['id'];
            data.remove('id');
            data.remove('isSynced');

            final docId = firestoreId ?? "sp_${data['supplierId']}_${data['paidAt']}";
            batch.set(_db.collection('supplier_payments').doc(docId), data, SetOptions(merge: true));
            toMarkSynced.add({'localId': localId, 'firestoreId': docId});
            count++;
          }
          if (count > 0) {
            await batch.commit();
            // Mark as synced in local DB after successful Firestore commit
            for (var item in toMarkSynced) {
              await dbHelper.updateSupplierPayment(
                item['localId'] as int,
                {'isSynced': 1, 'firestoreId': item['firestoreId']},
              );
            }
            debugPrint('  -> Synced $count supplier payments');
          }
        }
      } catch (e) {
        debugPrint('  -> Error syncing supplier_payments: $e');
      }

      try {
        final partnerPayments = await dbHelper.getRepairPartnerPaymentsForSync();
        final unsyncedPP = partnerPayments.where((pp) => pp['isSynced'] != 1 && pp['isSynced'] != true).toList();
        if (unsyncedPP.isNotEmpty) {
          final WriteBatch batch = _db.batch();
          int count = 0;
          final List<Map<String, dynamic>> toMarkSynced = [];
          for (var pp in unsyncedPP) {
            final firestoreId = pp['firestoreId'];
            final data = Map<String, dynamic>.from(pp);
            data['shopId'] = shopId;
            data['deleted'] = data['deleted'] == 1 || data['deleted'] == true;
            final localId = data['id'];
            data.remove('id');
            data.remove('isSynced');

            final docId = firestoreId ?? "rpp_${data['partnerId']}_${data['paidAt']}";
            batch.set(_db.collection('repair_partner_payments').doc(docId), data, SetOptions(merge: true));
            toMarkSynced.add({'localId': localId, 'firestoreId': docId});
            count++;
          }
          if (count > 0) {
            await batch.commit();
            // Mark as synced in local DB after successful Firestore commit
            for (var item in toMarkSynced) {
              await dbHelper.updateRepairPartnerPayment(
                item['localId'] as int,
                {'isSynced': 1, 'firestoreId': item['firestoreId']},
              );
            }
            debugPrint('  -> Synced $count repair partner payments');
          }
        }
      } catch (e) {
        debugPrint('  -> Error syncing repair_partner_payments: $e');
      }

      debugPrint('⚡ syncPaymentRelatedData: completed');
    } catch (e) {
      debugPrint('⚡ syncPaymentRelatedData error: $e');
    }
  }

  /// Sync repair data immediately after repair status changes
  /// Targets: repairs table only - much faster than syncAllToCloud()
  /// Ensures status updates (chờ duyệt, giao máy, etc.) sync to other devices immediately
  static Future<void> syncRepairData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final String? shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;

      // FIX: Super admin có shopId → cho phép sync (không block nữa)

      final dbHelper = DBHelper();
      debugPrint('⚡ syncRepairData: starting targeted repair sync...');

      // Sync unsynced repairs
      final repairs = await dbHelper.getAllRepairs();
        final unsyncedRepairs = repairs
          .where((r) => !r.isSynced || _hasLocalImagePath(r.imagePath))
          .toList();

      if (unsyncedRepairs.isEmpty) {
        debugPrint('⚡ syncRepairData: no unsynced repairs');
        return;
      }

      debugPrint('⚡ syncRepairData: found ${unsyncedRepairs.length} unsynced repairs');
      final WriteBatch batch = _db.batch();
      final List<Repair> toMarkSynced = [];

      for (var r in unsyncedRepairs) {
        try {
          Map<String, dynamic> data = r.toMap();
          data['shopId'] = shopId;
          data.remove('id');
          data['updatedAt'] = FieldValue.serverTimestamp();
          data.remove('isSynced');
          data.remove('firestoreId');

          // Upload local images if needed
          if (_hasLocalImagePath(r.imagePath)) {
            try {
              final allPaths = _splitImagePaths(r.imagePath);
              List<String> urls = await StorageService.uploadMultipleImages(
                allPaths.where((path) => !_isCloudImagePath(path)).toList(),
                'repairs/${r.createdAt}',
              ).timeout(
                const Duration(seconds: 15),
                onTimeout: () => <String>[],
              );
              List<String> allUrls =
                  allPaths.where((path) => _isCloudImagePath(path)).toList();
              allUrls.addAll(urls);
              data['imagePath'] = allUrls.join(',');
            } catch (e) {
              debugPrint('⚡ syncRepairData: image upload failed for ${r.id}: $e');
            }
          }

          final docId = r.firestoreId ?? "repair_${r.createdAt}_${r.phone}_${r.id ?? 0}";
          batch.set(
            _db.collection('repairs').doc(docId),
            data,
            SetOptions(merge: true),
          );

          r.firestoreId = docId;
          r.imagePath = data['imagePath'];
          toMarkSynced.add(r);
        } catch (e) {
          debugPrint('⚡ syncRepairData: error preparing repair ${r.id}: $e');
        }
      }

      try {
        await batch.commit();
        for (var r in toMarkSynced) {
          r.isSynced = true;
          await dbHelper.updateRepair(r);
        }
        debugPrint('⚡ syncRepairData: ✅ synced ${toMarkSynced.length} repairs to cloud');
      } catch (e) {
        debugPrint('⚡ syncRepairData: ❌ batch commit failed: $e - will retry next sync');
      }
    } catch (e) {
      debugPrint('⚡ syncRepairData error: $e');
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

      // FIX: Super admin CÓ shopId (đã chọn shop) → cho phép upload data
      // (Trước đây block hoàn toàn → gây tích lũy records chưa đồng bộ)

      final dbHelper = DBHelper();

      // Chỉ đẩy những đơn hàng CHƯA đồng bộ hoặc CÓ thay đổi hình ảnh
      final repairs = await dbHelper.getAllRepairs();
      debugPrint("syncAllToCloud: có ${repairs.length} repairs cần sync");
      final WriteBatch repairBatch = _db.batch();
      // FIX: Collect items to mark synced AFTER batch commit succeeds
      final List<Repair> repairsToMarkSynced = [];
      for (var r in repairs) {
        if (r.isSynced && !(r.imagePath?.contains('cache') ?? false)) continue;

        try {
          Map<String, dynamic> data = r.toMap();
          data['shopId'] = shopId;
          data.remove('id');
          // FIX: Add updatedAt for conflict resolution on receiving devices
          data['updatedAt'] = FieldValue.serverTimestamp();
          // FIX: Remove local-only fields from cloud data
          data.remove('isSynced');
          data.remove('firestoreId');

          // Xử lý upload ảnh nếu là ảnh local với timeout
          if (_hasLocalImagePath(r.imagePath)) {
            final allPaths = _splitImagePaths(r.imagePath);
            List<String> urls =
                await StorageService.uploadMultipleImages(
                  allPaths.where((path) => !_isCloudImagePath(path)).toList(),
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
            List<String> allUrls =
              allPaths.where((path) => _isCloudImagePath(path)).toList();
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

          // FIX: Defer marking synced - collect for after commit
          r.firestoreId = docId;
          r.imagePath = data['imagePath'];
          repairsToMarkSynced.add(r);
        } catch (e) {
          debugPrint("Lỗi sync repair ${r.id}: $e");
          // Tiếp tục với repair tiếp theo thay vì dừng toàn bộ
        }
      }
      try {
        await repairBatch.commit();
        // FIX: Only mark synced AFTER batch commit succeeds
        for (var r in repairsToMarkSynced) {
          r.isSynced = true;
          await dbHelper.updateRepair(r);
        }
        debugPrint("✅ Synced ${repairsToMarkSynced.length} repairs to cloud");
      } catch (e) {
        debugPrint("❌ Batch commit repairs failed: $e - repairs will retry next sync");
      }

      // Sync SALES
      final sales = await dbHelper.getAllSales();
      debugPrint("syncAllToCloud: có ${sales.length} sales cần sync");
      final WriteBatch saleBatch = _db.batch();
      final List<SaleOrder> salesToMarkSynced = [];
      for (var s in sales) {
        if (s.isSynced) continue;

        try {
          Map<String, dynamic> data = s.toMap();
          data['shopId'] = shopId;
          data.remove('id');
          data['updatedAt'] = FieldValue.serverTimestamp();
          data.remove('isSynced');
          data.remove('firestoreId');

          final docId =
              s.firestoreId ?? "sale_${s.soldAt}_${s.phone}_${s.id ?? 0}";
          saleBatch.set(
            _db.collection('sales').doc(docId),
            data,
            SetOptions(merge: true),
          );

          s.firestoreId = docId;
          salesToMarkSynced.add(s);
        } catch (e) {
          debugPrint("Lỗi sync sale ${s.id}: $e");
          // Tiếp tục với sale tiếp theo
        }
      }
      try {
        await saleBatch.commit();
        for (var s in salesToMarkSynced) {
          s.isSynced = true;
          await dbHelper.updateSale(s);
        }
        debugPrint("✅ Synced ${salesToMarkSynced.length} sales to cloud");
      } catch (e) {
        debugPrint("❌ Batch commit sales failed: $e - sales will retry next sync");
      }

      // Sync EXPENSES (Chi phí)
      try {
        final expenses = await dbHelper.getAllExpensesForSync();
        debugPrint(
          "syncAllToCloud: có ${expenses.length} expenses cần kiểm tra sync",
        );
        if (expenses.isNotEmpty) {
          final WriteBatch expenseBatch = _db.batch();
          final List<dynamic> expensesToMarkSynced = [];
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
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId =
                  firestoreId ??
                  "exp_${expense.date}_${expense.title.hashCode}";
              expenseBatch.set(
                _db.collection('expenses').doc(docId),
                data,
                SetOptions(merge: true),
              );

              // Defer marking synced
              expense.firestoreId = docId;
              expensesToMarkSynced.add(expense);
            } catch (e) {
              debugPrint("Lỗi sync expense ${expense.id}: $e");
            }
          }
          try {
            await expenseBatch.commit();
            for (var expense in expensesToMarkSynced) {
              expense.isSynced = true;
              await dbHelper.updateExpense(expense);
            }
            debugPrint("✅ Synced ${expensesToMarkSynced.length} expenses to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit expenses failed: $e - expenses will retry next sync");
          }
        }
      } catch (e) {
        debugPrint("Lỗi sync expenses collection: $e");
      }

      // Sync PRODUCTS
      final products = await dbHelper.getAllProducts();
      debugPrint("syncAllToCloud: có ${products.length} products cần sync");
      final WriteBatch productBatch = _db.batch();
      final List<Product> productsToMarkSynced = [];
      for (var p in products) {
        if (p.isSynced) continue;

        try {
          Map<String, dynamic> data = p.toMap();
          data['shopId'] = shopId;
          data.remove('id');
          data['updatedAt'] = FieldValue.serverTimestamp();
          data.remove('isSynced');
          data.remove('firestoreId');

          // Xử lý upload ảnh nếu là ảnh local với timeout
          if (_hasLocalImagePath(p.images)) {
            final allPaths = _splitImagePaths(p.images);
            List<String> urls =
                await StorageService.uploadMultipleImages(
                  allPaths.where((path) => !_isCloudImagePath(path)).toList(),
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
            final existingCloud =
                allPaths.where((path) => _isCloudImagePath(path)).toList();
            existingCloud.addAll(urls);
            data['images'] = existingCloud.join(',');
          }

          final docId =
              p.firestoreId ??
              "product_${p.createdAt}_${p.imei ?? 'noimei'}_${p.id ?? 0}";
          productBatch.set(
            _db.collection('products').doc(docId),
            data,
            SetOptions(merge: true),
          );

          p.firestoreId = docId;
          p.images = data['images'];
          productsToMarkSynced.add(p);
        } catch (e) {
          debugPrint("Lỗi sync product ${p.id}: $e");
          // Tiếp tục với product tiếp theo
        }
      }
      try {
        await productBatch.commit();
        for (var p in productsToMarkSynced) {
          p.isSynced = true;
          await dbHelper.updateProduct(p);
        }
        debugPrint("✅ Synced ${productsToMarkSynced.length} products to cloud");
      } catch (e) {
        debugPrint("❌ Batch commit products failed: $e - products will retry next sync");
      }

      // Sync ATTENDANCE
      try {
        final attendance = await dbHelper.getAllAttendance();
        debugPrint(
          "syncAllToCloud: có ${attendance.length} attendance cần sync",
        );
        final WriteBatch attendanceBatch = _db.batch();
        final List<dynamic> attendanceToMarkSynced = [];
        for (var a in attendance) {
          if (a.firestoreId != null && a.firestoreId!.isNotEmpty) {
            continue; // Đã sync rồi
          }

          try {
            Map<String, dynamic> data = a.toMap();
            data['shopId'] = shopId;
            data.remove('id');
            data['updatedAt'] = FieldValue.serverTimestamp();
            data.remove('isSynced');
            data.remove('firestoreId');

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
            attendanceToMarkSynced.add(a);
          } catch (e) {
            debugPrint("Lỗi sync attendance ${a.id}: $e");
            // Tiếp tục với attendance tiếp theo
          }
        }
        try {
          await attendanceBatch.commit();
          for (var a in attendanceToMarkSynced) {
            await dbHelper.updateAttendance(a);
          }
          debugPrint("✅ Synced ${attendanceToMarkSynced.length} attendance to cloud");
        } catch (e) {
          debugPrint("❌ Batch commit attendance failed: $e - attendance will retry next sync");
        }
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
          final List<dynamic> qicToMarkSynced = [];
          for (var code in quickInputCodes) {
            if (code.isSynced) continue;

            try {
              Map<String, dynamic> data = code.toMap();
              data['shopId'] = shopId;
              data.remove('id');
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

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
              qicToMarkSynced.add(code);
            } catch (e) {
              debugPrint("Lỗi sync quick input code ${code.id}: $e");
            }
          }
          try {
            await quickInputBatch.commit();
            for (var code in qicToMarkSynced) {
              code.isSynced = true;
              await dbHelper.updateQuickInputCode(code);
            }
            debugPrint("✅ Synced ${qicToMarkSynced.length} quick input codes to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit quick input codes failed: $e");
          }
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
          final List<Map<String, dynamic>> suppliersToMarkSynced = [];
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
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId =
                  "supplier_${supplierMap['createdAt']}_${supplierMap['name'].toString().replaceAll(' ', '_')}";
              supplierBatch.set(
                _db.collection('suppliers').doc(docId),
                data,
                SetOptions(merge: true),
              );

              suppliersToMarkSynced.add({'supplierMap': supplierMap, 'docId': docId});
            } catch (e) {
              debugPrint("Lỗi sync supplier ${supplierMap['id']}: $e");
            }
          }
          try {
            await supplierBatch.commit();
            for (var item in suppliersToMarkSynced) {
              final updateData = Map<String, dynamic>.from(item['supplierMap']);
              updateData['firestoreId'] = item['docId'];
              await dbHelper.upsertSupplier(updateData);
            }
            debugPrint("✅ Synced ${suppliersToMarkSynced.length} suppliers to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit suppliers failed: $e");
          }
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
          final List<Map<String, dynamic>> partnersToMarkSynced = [];
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
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId =
                  "rp_${partnerMap['createdAt']}_${partnerMap['name'].toString().replaceAll(' ', '_')}";
              partnerBatch.set(
                _db.collection('repair_partners').doc(docId),
                data,
                SetOptions(merge: true),
              );

              partnersToMarkSynced.add({'partnerMap': partnerMap, 'docId': docId});
            } catch (e) {
              debugPrint("Lỗi sync repair partner ${partnerMap['id']}: $e");
            }
          }
          try {
            await partnerBatch.commit();
            for (var item in partnersToMarkSynced) {
              final updateData = Map<String, dynamic>.from(item['partnerMap']);
              updateData['firestoreId'] = item['docId'];
              await dbHelper.upsertRepairPartner(updateData);
            }
            debugPrint("✅ Synced ${partnersToMarkSynced.length} repair partners to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit repair partners failed: $e");
          }
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
          final List<Map<String, dynamic>> supPayToMarkSynced = [];
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
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId = firestoreId ??
                  "sup_pay_${data['paidAt']}_${data['supplierId'] ?? 'sup'}";
              supplierPaymentBatch.set(
                _db.collection('supplier_payments').doc(docId),
                data,
                SetOptions(merge: true),
              );

              supPayToMarkSynced.add({'id': paymentMap['id'], 'docId': docId});
            } catch (e) {
              debugPrint("Lỗi sync supplier payment ${paymentMap['id']}: $e");
            }
          }
          try {
            await supplierPaymentBatch.commit();
            for (var item in supPayToMarkSynced) {
              await dbHelper.updateSupplierPayment(
                item['id'],
                {'firestoreId': item['docId'], 'isSynced': 1},
              );
            }
            debugPrint("✅ Synced ${supPayToMarkSynced.length} supplier payments to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit supplier payments failed: $e");
          }
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
          final List<Map<String, dynamic>> partPayToMarkSynced = [];
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
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId = firestoreId ??
                  "part_pay_${data['paidAt']}_${data['partnerId'] ?? 'partner'}";
              partnerPaymentBatch.set(
                _db.collection('repair_partner_payments').doc(docId),
                data,
                SetOptions(merge: true),
              );

              partPayToMarkSynced.add({'id': paymentMap['id'], 'docId': docId});
            } catch (e) {
              debugPrint(
                "Lỗi sync repair partner payment ${paymentMap['id']}: $e",
              );
            }
          }
          try {
            await partnerPaymentBatch.commit();
            for (var item in partPayToMarkSynced) {
              await dbHelper.updateRepairPartnerPayment(
                item['id'],
                {'firestoreId': item['docId'], 'isSynced': 1},
              );
            }
            debugPrint("✅ Synced ${partPayToMarkSynced.length} repair partner payments to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit repair partner payments failed: $e");
          }
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
          final List<Map<String, dynamic>> debtsToMarkSynced = [];
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
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId =
                  firestoreId ??
                  "debt_${debtMap['createdAt']}_${debtMap['phone'] ?? 'ncc'}";
              debtBatch.set(
                _db.collection('debts').doc(docId),
                data,
                SetOptions(merge: true),
              );

              debtsToMarkSynced.add({'id': debtMap['id'], 'docId': docId});
            } catch (e) {
              debugPrint("Lỗi sync debt ${debtMap['id']}: $e");
            }
          }
          try {
            await debtBatch.commit();
            for (var item in debtsToMarkSynced) {
              await dbHelper.updateDebtSynced(item['id'], item['docId']);
            }
            debugPrint("✅ Synced ${debtsToMarkSynced.length} debts to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit debts failed: $e");
          }
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
          final List<Map<String, dynamic>> debtPayToMarkSynced = [];
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
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId =
                  firestoreId ??
                  "pay_${data['paidAt']}_${data['debtId'] ?? 'debt'}";
              paymentBatch.set(
                _db.collection('debt_payments').doc(docId),
                data,
                SetOptions(merge: true),
              );

              debtPayToMarkSynced.add({'id': paymentMap['id'], 'docId': docId});
            } catch (e) {
              debugPrint("Lỗi sync debt payment ${paymentMap['id']}: $e");
            }
          }
          try {
            await paymentBatch.commit();
            for (var item in debtPayToMarkSynced) {
              await dbHelper.updateDebtPaymentSynced(item['id'], item['docId']);
            }
            debugPrint("✅ Synced ${debtPayToMarkSynced.length} debt payments to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit debt payments failed: $e");
          }
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
          final List<String> auditDocsToMarkSynced = [];
          for (var logMap in auditLogs) {
            try {
              Map<String, dynamic> data = Map<String, dynamic>.from(logMap);
              data['shopId'] = shopId;
              data.remove('id');
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId =
                  logMap['firestoreId'] ??
                  "log_${data['createdAt']}_${data['userId']}";
              auditBatch.set(
                _db.collection('audit_logs').doc(docId),
                data,
                SetOptions(merge: true),
              );

              auditDocsToMarkSynced.add(docId);
            } catch (e) {
              debugPrint("Lỗi sync audit log ${logMap['id']}: $e");
            }
          }
          try {
            await auditBatch.commit();
            for (var docId in auditDocsToMarkSynced) {
              await dbHelper.updateAuditLogSynced(docId);
            }
            debugPrint("✅ Synced ${auditDocsToMarkSynced.length} audit logs to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit audit logs failed: $e");
          }
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
          final List<Map<String, dynamic>> partsToMarkSynced = [];
          for (var partMap in repairParts) {
            try {
              Map<String, dynamic> data = Map<String, dynamic>.from(partMap);
              data['shopId'] = shopId;
              final localId = data['id'];
              data.remove('id');
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId =
                  partMap['firestoreId'] ??
                  "part_${data['createdAt']}_${data['partName'].toString().replaceAll(' ', '_')}";
              partsBatch.set(
                _db.collection('repair_parts').doc(docId),
                data,
                SetOptions(merge: true),
              );

              partsToMarkSynced.add({'localId': localId, 'docId': docId});
            } catch (e) {
              debugPrint("Lỗi sync repair part ${partMap['id']}: $e");
            }
          }
          try {
            await partsBatch.commit();
            for (var item in partsToMarkSynced) {
              await dbHelper.updateRepairPartSynced(item['localId'], item['docId']);
            }
            debugPrint("✅ Synced ${partsToMarkSynced.length} repair parts to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit repair parts failed: $e");
          }
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
          final List<Map<String, dynamic>> intentsToMarkSynced = [];
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
              data['updatedAt'] = FieldValue.serverTimestamp();
              data.remove('isSynced');
              data.remove('firestoreId');

              final docId = firestoreId ??
                  "pi_${data['intentId'] ?? data['createdAt']}_${data['type'] ?? 'unknown'}";
              intentBatch.set(
                _db.collection('payment_intents').doc(docId),
                data,
                SetOptions(merge: true),
              );

              intentsToMarkSynced.add({'localId': localId, 'docId': docId});
            } catch (e) {
              debugPrint("Lỗi sync payment intent ${intentMap['id']}: $e");
            }
          }
          try {
            await intentBatch.commit();
            for (var item in intentsToMarkSynced) {
              await dbHelper.updatePaymentIntentSynced(item['localId'], item['docId']);
            }
            debugPrint("✅ Synced ${intentsToMarkSynced.length} payment intents to cloud");
          } catch (e) {
            debugPrint("❌ Batch commit payment intents failed: $e");
          }
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
      // Use sync cache first (set by syncUserInfo), fallback to async
      String? shopId = UserService.getShopIdSync();
      shopId ??= await UserService.getCurrentShopId();

      // LOG QUAN TRỌNG: Hiển thị shopId được sử dụng
      debugPrint(
        "⚡ downloadAllFromCloud: user=${user.uid}, email=${user.email}, shopId=$shopId, isSuperAdmin=$isSuperAdmin",
      );

      // Retry lấy shopId nếu chưa có (claims có thể chưa sync)
      if (shopId == null && !isSuperAdmin) {
        debugPrint("⚠️ shopId null, thử refresh claims...");
        for (int retry = 0; retry < 2; retry++) {
          await Future.delayed(const Duration(seconds: 1));
          try {
            await user.getIdToken(true);
            shopId = await UserService.getCurrentShopId();
            if (shopId != null) {
              debugPrint("✅ Lấy được shopId sau retry ${retry + 1}: $shopId");
              break;
            }
          } catch (e) {
            debugPrint("Retry ${retry + 1}/2 lấy shopId: $e");
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
        'cash_closings', // FIX: Thêm để đồng bộ lịch sử chốt quỹ + số dư đầu kỳ khi switch account
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
              } else if (col == 'cash_closings') {
                await db.upsertCashClosing(data);
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
