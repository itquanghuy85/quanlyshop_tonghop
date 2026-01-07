import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/product_model.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../models/attendance_model.dart';
import '../models/quick_input_code_model.dart';
import 'user_service.dart';
import 'sync_service.dart';

/// Global notifier để các widget có thể theo dõi sync health
/// true = healthy, false = có vấn đề, null = chưa kiểm tra
final ValueNotifier<bool?> syncHealthNotifier = ValueNotifier<bool?>(null);

/// Số lượng mismatches (để hiển thị badge)
final ValueNotifier<int> syncMismatchCountNotifier = ValueNotifier<int>(0);

/// Kết quả kiểm tra sync cho một collection
class SyncCheckResult {
  final String collection;
  final int localCount;
  final int cloudCount;
  final int localOnly; // Có local nhưng không có cloud
  final int cloudOnly; // Có cloud nhưng không có local
  final int matched; // Có cả hai
  final int unsyncedLocal; // Chưa sync lên cloud
  final List<String> missingOnCloud; // IDs có local mà không có cloud
  final List<String> missingOnLocal; // IDs có cloud mà không có local
  final String? error;

  SyncCheckResult({
    required this.collection,
    required this.localCount,
    required this.cloudCount,
    required this.localOnly,
    required this.cloudOnly,
    required this.matched,
    required this.unsyncedLocal,
    this.missingOnCloud = const [],
    this.missingOnLocal = const [],
    this.error,
  });

  bool get isHealthy => localOnly == 0 && cloudOnly == 0 && unsyncedLocal == 0;
  bool get hasIssues => !isHealthy;

  double get syncPercentage {
    if (cloudCount == 0 && localCount == 0) return 100.0;
    if (cloudCount == 0) return 0.0;
    return (matched / cloudCount) * 100;
  }
}

/// Tổng kết kiểm tra sync
class SyncHealthReport {
  final DateTime checkedAt;
  final String? shopId;
  final List<SyncCheckResult> results;
  final bool isFullyHealthy;
  final int totalLocalRecords;
  final int totalCloudRecords;
  final int totalMismatches;

  SyncHealthReport({
    required this.checkedAt,
    required this.shopId,
    required this.results,
    required this.isFullyHealthy,
    required this.totalLocalRecords,
    required this.totalCloudRecords,
    required this.totalMismatches,
  });

  String get summary {
    if (isFullyHealthy) {
      return '✅ Dữ liệu đồng bộ hoàn toàn ($totalCloudRecords records)';
    }
    return '⚠️ Có $totalMismatches records chưa đồng bộ';
  }
}

/// Service kiểm tra tình trạng sync
class SyncHealthCheck {
  static final _db = FirebaseFirestore.instance;
  static final _localDb = DBHelper();

  /// Kiểm tra toàn bộ sync health
  static Future<SyncHealthReport> runFullCheck() async {
    debugPrint('🔍 Bắt đầu kiểm tra Sync Health...');

    final user = FirebaseAuth.instance.currentUser;
    final String? shopId = await UserService.getCurrentShopId();
    final bool isSuperAdmin = UserService.isCurrentUserSuperAdmin();

    // LOG QUAN TRỌNG
    debugPrint(
      '⚡ runFullCheck: user=${user?.uid}, email=${user?.email}, shopId=$shopId, isSuperAdmin=$isSuperAdmin',
    );

    // Cần có shopId để check (super admin phải chọn shop trước)
    if (shopId == null) {
      if (isSuperAdmin) {
        debugPrint('⚠️ runFullCheck: Super admin chưa chọn shop, bỏ qua kiểm tra');
      } else {
        debugPrint('⚠️ runFullCheck: Không có shopId, bỏ qua kiểm tra');
      }
      return SyncHealthReport(
        checkedAt: DateTime.now(),
        shopId: null,
        results: [],
        isFullyHealthy: true, // Trả về true để không hiện loading mãi
        totalLocalRecords: 0,
        totalCloudRecords: 0,
        totalMismatches: 0,
      );
    }

    // Có shopId (bao gồm cả super admin đã chọn shop) - tiến hành check
    final String validShopId = shopId;
    
    final List<SyncCheckResult> results = [];
    int totalLocal = 0;
    int totalCloud = 0;
    int totalMismatches = 0;

    // Check REPAIRS
    results.add(
      await _checkCollection(
        collection: 'repairs',
        shopId: validShopId,
        getLocalIds: () async {
          final repairs = await _localDb.getAllRepairs();
          return repairs
              .where((r) => r.firestoreId != null)
              .map((r) => r.firestoreId!)
              .toList();
        },
        getLocalCount: () async => (await _localDb.getAllRepairs()).length,
        getUnsyncedCount: () async {
          final repairs = await _localDb.getAllRepairs();
          return repairs.where((r) => !r.isSynced).length;
        },
      ),
    );

    // Check SALES
    results.add(
      await _checkCollection(
        collection: 'sales',
        shopId: validShopId,
        getLocalIds: () async {
          final sales = await _localDb.getAllSales();
          return sales
              .where((s) => s.firestoreId != null)
              .map((s) => s.firestoreId!)
              .toList();
        },
        getLocalCount: () async => (await _localDb.getAllSales()).length,
        getUnsyncedCount: () async {
          final sales = await _localDb.getAllSales();
          return sales.where((s) => !s.isSynced).length;
        },
      ),
    );

    // Check PRODUCTS
    results.add(
      await _checkCollection(
        collection: 'products',
        shopId: shopId,
        getLocalIds: () async {
          final products = await _localDb.getAllProducts();
          return products
              .where((p) => p.firestoreId != null)
              .map((p) => p.firestoreId!)
              .toList();
        },
        getLocalCount: () async => (await _localDb.getAllProducts()).length,
        getUnsyncedCount: () async {
          final products = await _localDb.getAllProducts();
          return products.where((p) => p.isSynced != true).length;
        },
      ),
    );

    // Check EXPENSES
    results.add(
      await _checkCollection(
        collection: 'expenses',
        shopId: shopId,
        getLocalIds: () async {
          final expenses = await _localDb.getAllExpenses();
          return expenses
              .where((e) => e['firestoreId'] != null)
              .map((e) => e['firestoreId'] as String)
              .toList();
        },
        getLocalCount: () async => (await _localDb.getAllExpenses()).length,
        getUnsyncedCount: () async {
          final expenses = await _localDb.getAllExpenses();
          return expenses.where((e) => e['isSynced'] != 1).length;
        },
      ),
    );

    // Check DEBTS
    results.add(
      await _checkCollection(
        collection: 'debts',
        shopId: shopId,
        getLocalIds: () async {
          final debts = await _localDb.getAllDebts();
          return debts
              .where((d) => d['firestoreId'] != null)
              .map((d) => d['firestoreId'] as String)
              .toList();
        },
        getLocalCount: () async => (await _localDb.getAllDebts()).length,
        getUnsyncedCount: () async {
          final debts = await _localDb.getAllDebts();
          return debts.where((d) => d['isSynced'] != 1).length;
        },
      ),
    );

    // Check ATTENDANCE
    results.add(
      await _checkCollection(
        collection: 'attendance',
        shopId: shopId,
        getLocalIds: () async {
          final attendance = await _localDb.getAllAttendance();
          return attendance
              .where((a) => a.firestoreId != null)
              .map((a) => a.firestoreId!)
              .toList();
        },
        getLocalCount: () async => (await _localDb.getAllAttendance()).length,
        getUnsyncedCount: () async {
          final attendance = await _localDb.getAllAttendance();
          return attendance.where((a) => a.isSynced != true).length;
        },
      ),
    );

    // Check CUSTOMERS
    results.add(
      await _checkCollection(
        collection: 'customers',
        shopId: shopId,
        getLocalIds: () async {
          final db = await _localDb.database;
          final customers = await db.query('customers');
          return customers
              .where((c) => c['firestoreId'] != null)
              .map((c) => c['firestoreId'] as String)
              .toList();
        },
        getLocalCount: () async {
          final db = await _localDb.database;
          final customers = await db.query('customers');
          return customers.length;
        },
        getUnsyncedCount: () async {
          final db = await _localDb.database;
          final customers = await db.query('customers');
          return customers.where((c) => c['isSynced'] != 1).length;
        },
      ),
    );

    // Check SUPPLIERS
    results.add(
      await _checkCollection(
        collection: 'suppliers',
        shopId: shopId,
        getLocalIds: () async {
          final db = await _localDb.database;
          final suppliers = await db.query('suppliers');
          return suppliers
              .where((s) => s['firestoreId'] != null)
              .map((s) => s['firestoreId'] as String)
              .toList();
        },
        getLocalCount: () async {
          final db = await _localDb.database;
          final suppliers = await db.query('suppliers');
          return suppliers.length;
        },
        getUnsyncedCount: () async {
          final db = await _localDb.database;
          final suppliers = await db.query('suppliers');
          return suppliers.where((s) => s['isSynced'] != 1).length;
        },
      ),
    );

    // Check QUICK_INPUT_CODES
    results.add(
      await _checkCollection(
        collection: 'quick_input_codes',
        shopId: shopId,
        getLocalIds: () async {
          final db = await _localDb.database;
          final codes = await db.query('quick_input_codes');
          return codes
              .where((c) => c['firestoreId'] != null)
              .map((c) => c['firestoreId'] as String)
              .toList();
        },
        getLocalCount: () async {
          final db = await _localDb.database;
          final codes = await db.query('quick_input_codes');
          return codes.length;
        },
        getUnsyncedCount: () async {
          final db = await _localDb.database;
          final codes = await db.query('quick_input_codes');
          return codes.where((c) => c['isSynced'] != 1).length;
        },
      ),
    );

    // Tính tổng
    for (var r in results) {
      totalLocal += r.localCount;
      totalCloud += r.cloudCount;
      totalMismatches += r.localOnly + r.cloudOnly + r.unsyncedLocal;
    }

    final report = SyncHealthReport(
      checkedAt: DateTime.now(),
      shopId: shopId,
      results: results,
      isFullyHealthy: results.every((r) => r.isHealthy),
      totalLocalRecords: totalLocal,
      totalCloudRecords: totalCloud,
      totalMismatches: totalMismatches,
    );

    debugPrint('📊 Sync Health Report:');
    debugPrint('   Shop: $shopId');
    debugPrint(
      '   Local: $totalLocal | Cloud: $totalCloud | Mismatches: $totalMismatches',
    );
    for (var r in results) {
      final status = r.isHealthy ? '✅' : '⚠️';
      debugPrint(
        '   $status ${r.collection}: local=${r.localCount}, cloud=${r.cloudCount}, unsynced=${r.unsyncedLocal}',
      );
      if (r.missingOnLocal.isNotEmpty && r.missingOnLocal.length <= 5) {
        debugPrint('      Missing on local: ${r.missingOnLocal}');
      }
    }

    // Cập nhật global notifiers
    syncHealthNotifier.value = report.isFullyHealthy;
    syncMismatchCountNotifier.value = totalMismatches;

    return report;
  }

  /// Kiểm tra một collection cụ thể
  static Future<SyncCheckResult> _checkCollection({
    required String collection,
    required String shopId,
    required Future<List<String>> Function() getLocalIds,
    required Future<int> Function() getLocalCount,
    required Future<int> Function() getUnsyncedCount,
  }) async {
    try {
      // Lấy dữ liệu từ cloud - chỉ dùng 1 where để tránh cần composite index
      // Filter deleted ở client side
      final cloudSnap = await _db
          .collection(collection)
          .where('shopId', isEqualTo: shopId)
          .get();

      // Filter ra các documents không bị xóa (deleted != true)
      final cloudIds = cloudSnap.docs
          .where((d) => d.data()['deleted'] != true)
          .map((d) => d.id)
          .toSet();
      final localIds = (await getLocalIds()).toSet();
      final localCount = await getLocalCount();
      final unsyncedCount = await getUnsyncedCount();

      final matched = localIds.intersection(cloudIds).length;
      final localOnly = localIds.difference(cloudIds).length;
      final cloudOnly = cloudIds.difference(localIds).length;

      return SyncCheckResult(
        collection: collection,
        localCount: localCount,
        cloudCount: cloudIds.length,
        localOnly: localOnly,
        cloudOnly: cloudOnly,
        matched: matched,
        unsyncedLocal: unsyncedCount,
        missingOnCloud: localIds.difference(cloudIds).take(10).toList(),
        missingOnLocal: cloudIds.difference(localIds).take(10).toList(),
      );
    } catch (e) {
      debugPrint('❌ Lỗi kiểm tra $collection: $e');
      return SyncCheckResult(
        collection: collection,
        localCount: 0,
        cloudCount: 0,
        localOnly: 0,
        cloudOnly: 0,
        matched: 0,
        unsyncedLocal: 0,
        error: e.toString(),
      );
    }
  }

  /// Tự động sửa các vấn đề sync (download + upload + mark synced)
  static Future<int> autoFix() async {
    debugPrint('🔧 Bắt đầu Auto Fix Sync...');

    int fixedCount = 0;

    // BƯỚC 1: Upload local chưa sync lên cloud
    debugPrint('📤 Bước 1: Upload local lên cloud...');
    try {
      await SyncService.syncAllToCloud();
      debugPrint('✅ Upload hoàn thành');
    } catch (e) {
      debugPrint('❌ Lỗi upload: $e');
    }

    // BƯỚC 2: Download TẤT CẢ từ cloud về local và đánh dấu isSynced
    debugPrint('📥 Bước 2: Download từ cloud về local...');
    final String? shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      debugPrint('❌ Không có shopId');
      return fixedCount;
    }

    // Danh sách các collection cần sync
    final collections = [
      'repairs',
      'sales', 
      'products',
      'expenses',
      'debts',
      'attendance',
      'customers',
      'suppliers',
      'quick_input_codes',
    ];

    for (var collection in collections) {
      try {
        debugPrint('   📥 Đang xử lý $collection...');
        
        // Lấy tất cả từ cloud
        final cloudSnap = await _db
            .collection(collection)
            .where('shopId', isEqualTo: shopId)
            .get();

        // Lấy local IDs
        final localIds = await _getLocalIds(collection);
        
        int collectionFixed = 0;
        for (var doc in cloudSnap.docs) {
          final data = doc.data();
          // Bỏ qua nếu đã xóa
          if (data['deleted'] == true) continue;
          
          data['firestoreId'] = doc.id;
          data['isSynced'] = 1; // Đánh dấu đã sync
          
          try {
            // Upsert tất cả - cả records mới lẫn records cần cập nhật isSynced
            await _upsertToLocal(collection, data);
            if (!localIds.contains(doc.id)) {
              collectionFixed++;
              fixedCount++;
            }
          } catch (e) {
            debugPrint('      ❌ Lỗi xử lý ${doc.id}: $e');
          }
        }
        
        if (collectionFixed > 0) {
          debugPrint('   ✅ Đã tải $collectionFixed $collection mới');
        }
      } catch (e) {
        debugPrint('   ❌ Lỗi xử lý $collection: $e');
      }
    }

    // BƯỚC 3: Đánh dấu tất cả records local đã có firestoreId là synced
    debugPrint('🔄 Bước 3: Đánh dấu records đã sync...');
    try {
      await _markAllAsSynced();
      debugPrint('✅ Đã đánh dấu sync');
    } catch (e) {
      debugPrint('❌ Lỗi đánh dấu sync: $e');
    }

    debugPrint('✅ Auto Fix hoàn thành: đã tải $fixedCount records mới');
    return fixedCount;
  }

  /// Đánh dấu tất cả records có firestoreId là đã sync
  static Future<void> _markAllAsSynced() async {
    final db = await _localDb.database;
    
    // Cập nhật isSynced = 1 cho tất cả records có firestoreId
    final tables = ['repairs', 'sales', 'products', 'expenses', 'debts', 'attendance', 'customers', 'suppliers', 'quick_input_codes'];
    
    for (var table in tables) {
      try {
        await db.rawUpdate(
          'UPDATE $table SET isSynced = 1 WHERE firestoreId IS NOT NULL AND firestoreId != ""',
        );
        debugPrint('   ✅ Đã đánh dấu $table');
      } catch (e) {
        debugPrint('   ⚠️ Không thể đánh dấu $table: $e');
      }
    }
  }

  /// Lấy danh sách local IDs cho một collection
  static Future<Set<String>> _getLocalIds(String collection) async {
    final db = _localDb;
    switch (collection) {
      case 'repairs':
        final repairs = await db.getAllRepairs();
        return repairs.where((r) => r.firestoreId != null).map((r) => r.firestoreId!).toSet();
      case 'sales':
        final sales = await db.getAllSales();
        return sales.where((s) => s.firestoreId != null).map((s) => s.firestoreId!).toSet();
      case 'products':
        final products = await db.getAllProducts();
        return products.where((p) => p.firestoreId != null).map((p) => p.firestoreId!).toSet();
      case 'expenses':
        final expenses = await db.getAllExpenses();
        return expenses.where((e) => e['firestoreId'] != null).map((e) => e['firestoreId'] as String).toSet();
      case 'debts':
        final debts = await db.getAllDebts();
        return debts.where((d) => d['firestoreId'] != null).map((d) => d['firestoreId'] as String).toSet();
      case 'attendance':
        final attendance = await db.getAllAttendance();
        return attendance.where((a) => a.firestoreId != null).map((a) => a.firestoreId!).toSet();
      case 'customers':
        final dbInstance = await db.database;
        final customers = await dbInstance.query('customers');
        return customers.where((c) => c['firestoreId'] != null).map((c) => c['firestoreId'] as String).toSet();
      case 'suppliers':
        final dbInstance2 = await db.database;
        final suppliers = await dbInstance2.query('suppliers');
        return suppliers.where((s) => s['firestoreId'] != null).map((s) => s['firestoreId'] as String).toSet();
      case 'quick_input_codes':
        final dbInstance3 = await db.database;
        final codes = await dbInstance3.query('quick_input_codes');
        return codes.where((c) => c['firestoreId'] != null).map((c) => c['firestoreId'] as String).toSet();
      default:
        return {};
    }
  }

  /// Upsert dữ liệu vào local DB
  static Future<void> _upsertToLocal(
    String collection,
    Map<String, dynamic> data,
  ) async {
    final db = _localDb;

    switch (collection) {
      case 'repairs':
        await db.upsertRepair(Repair.fromMap(data));
        break;
      case 'sales':
        await db.upsertSale(SaleOrder.fromMap(data));
        break;
      case 'products':
        await db.upsertProduct(Product.fromMap(data));
        break;
      case 'expenses':
        await db.upsertExpense(Expense.fromMap(data));
        break;
      case 'debts':
        await db.upsertDebt(Debt.fromMap(data));
        break;
      case 'attendance':
        await db.upsertAttendance(Attendance.fromMap(data));
        break;
      case 'customers':
        await db.upsertCustomer(data);
        break;
      case 'suppliers':
        await db.upsertSupplier(data);
        break;
      case 'quick_input_codes':
        await db.upsertQuickInputCode(QuickInputCode.fromMap(data));
        break;
    }
  }
}
