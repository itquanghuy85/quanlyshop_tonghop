import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Represents a dashboard card type
enum DashboardCardType {
  greeting, // Lời chào
  actionRequired, // Cần xử lý (badges)
  quickActions, // Thao tác nhanh (grid)
  todayActivity, // Hoạt động vận hành hôm nay
  financeSummary, // Tóm tắt Thu/Chi (compact)
  financeDetail, // Chi tiết tài chính (full breakdown)
  activityFeed, // Hoạt động gần đây
  chat, // Chat nhóm
  alerts, // Cảnh báo (bảo hành, HSD)
  userGuide, // Hướng dẫn sử dụng
  financeShortcuts, // Truy cập nhanh tài chính (Sổ quỹ/Công nợ/Thu chi)
}

/// Config for a single dashboard card
class DashboardCardConfig {
  final DashboardCardType type;
  bool visible;
  int order;

  DashboardCardConfig({
    required this.type,
    required this.visible,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'visible': visible,
    'order': order,
  };

  factory DashboardCardConfig.fromJson(Map<String, dynamic> json) {
    return DashboardCardConfig(
      type: DashboardCardType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => DashboardCardType.greeting,
      ),
      visible: json['visible'] ?? true,
      order: json['order'] ?? 0,
    );
  }

  /// Display name (Vietnamese)
  String get displayName {
    switch (type) {
      case DashboardCardType.greeting:
        return 'Lời chào';
      case DashboardCardType.actionRequired:
        return 'Cần xử lý';
      case DashboardCardType.quickActions:
        return 'Thao tác nhanh';
      case DashboardCardType.todayActivity:
        return 'Hoạt động hôm nay';
      case DashboardCardType.financeSummary:
        return 'Tóm tắt tài chính';
      case DashboardCardType.financeDetail:
        return 'Chi tiết tài chính';
      case DashboardCardType.activityFeed:
        return 'Hoạt động gần đây';
      case DashboardCardType.chat:
        return 'Chat nhóm';
      case DashboardCardType.alerts:
        return 'Cảnh báo';
      case DashboardCardType.userGuide:
        return 'Hướng dẫn sử dụng';
      case DashboardCardType.financeShortcuts:
        return 'Truy cập nhanh tài chính';
    }
  }

  /// Description for each card
  String get description {
    switch (type) {
      case DashboardCardType.greeting:
        return 'Hiện tên, vai trò và ngày tháng';
      case DashboardCardType.actionRequired:
        return 'Đơn chờ xử lý, hàng chờ xác nhận';
      case DashboardCardType.quickActions:
        return 'Bán hàng, nhập kho, chấm công...';
      case DashboardCardType.todayActivity:
        return 'Các chỉ số vận hành và nhắc nhở trong ngày';
      case DashboardCardType.financeSummary:
        return 'Thu/Chi hôm nay (compact)';
      case DashboardCardType.financeDetail:
        return 'Biến động, lợi nhuận chi tiết';
      case DashboardCardType.activityFeed:
        return '10 giao dịch gần nhất';
      case DashboardCardType.chat:
        return 'Tin nhắn nhóm mới nhất';
      case DashboardCardType.alerts:
        return 'Bảo hành, hết hạn sử dụng';
      case DashboardCardType.userGuide:
        return 'Lối tắt đến hướng dẫn';
      case DashboardCardType.financeShortcuts:
        return 'Sổ quỹ, Công nợ, Thu chi';
    }
  }

  /// Icon for each card
  IconData get icon {
    switch (type) {
      case DashboardCardType.greeting:
        return Icons.waving_hand;
      case DashboardCardType.actionRequired:
        return Icons.notification_important;
      case DashboardCardType.quickActions:
        return Icons.apps;
      case DashboardCardType.todayActivity:
        return Icons.space_dashboard_rounded;
      case DashboardCardType.financeSummary:
        return Icons.account_balance_wallet;
      case DashboardCardType.financeDetail:
        return Icons.bar_chart;
      case DashboardCardType.activityFeed:
        return Icons.history;
      case DashboardCardType.chat:
        return Icons.chat_bubble;
      case DashboardCardType.alerts:
        return Icons.warning_amber;
      case DashboardCardType.userGuide:
        return Icons.menu_book;
      case DashboardCardType.financeShortcuts:
        return Icons.account_balance;
    }
  }

  /// Color for each card
  Color get color {
    switch (type) {
      case DashboardCardType.greeting:
        return Colors.blue;
      case DashboardCardType.actionRequired:
        return Colors.orange;
      case DashboardCardType.quickActions:
        return Colors.teal;
      case DashboardCardType.todayActivity:
        return Colors.deepOrange;
      case DashboardCardType.financeSummary:
        return Colors.green;
      case DashboardCardType.financeDetail:
        return Colors.indigo;
      case DashboardCardType.activityFeed:
        return Colors.purple;
      case DashboardCardType.chat:
        return Colors.cyan;
      case DashboardCardType.alerts:
        return Colors.red;
      case DashboardCardType.userGuide:
        return Colors.blue;
      case DashboardCardType.financeShortcuts:
        return Colors.indigo;
    }
  }

  /// Whether this card requires owner/admin role
  bool get requiresFinanceAccess {
    return type == DashboardCardType.financeSummary ||
        type == DashboardCardType.financeDetail ||
        type == DashboardCardType.financeShortcuts;
  }
}

/// Service to manage dashboard layout configuration
class DashboardConfigService {
  static const String _prefsKey = 'dashboard_config_v3';
  static const String _prefsVersionKey = 'dashboard_config_version_v1';
  static const String _cloudField = 'dashboardConfigV3';
  static const String _cloudVersionField = 'dashboardConfigVersionV1';
  static const int _schemaVersion = 2;

  static DocumentReference<Map<String, dynamic>>? _userDocRef() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  /// Get default layout based on role
  static List<DashboardCardConfig> getDefaultLayout({
    required String role,
    required bool isSuperAdmin,
  }) {
    final isOwnerOrAdmin = role == 'owner' || role == 'admin' || isSuperAdmin;
    final canViewFinanceByDefault = isOwnerOrAdmin;

    return [
      DashboardCardConfig(
        type: DashboardCardType.actionRequired,
        visible: true,
        order: 0,
      ),
      DashboardCardConfig(
        type: DashboardCardType.quickActions,
        visible: true,
        order: 1,
      ),
      DashboardCardConfig(
        type: DashboardCardType.todayActivity,
        visible: true,
        order: 2,
      ),
      DashboardCardConfig(
        type: DashboardCardType.financeSummary,
        visible: false,
        order: 3,
      ),
      DashboardCardConfig(
        type: DashboardCardType.financeDetail,
        visible: canViewFinanceByDefault,
        order: 4,
      ),
      DashboardCardConfig(
        type: DashboardCardType.financeShortcuts,
        visible: canViewFinanceByDefault,
        order: 5,
      ),
      DashboardCardConfig(
        type: DashboardCardType.alerts,
        visible: true,
        order: 6,
      ),
      DashboardCardConfig(
        type: DashboardCardType.activityFeed,
        visible: true,
        order: 7,
      ),
      DashboardCardConfig(
        type: DashboardCardType.chat,
        visible: false,
        order: 8,
      ),
      DashboardCardConfig(
        type: DashboardCardType.userGuide,
        visible: false,
        order: 9,
      ),
      DashboardCardConfig(
        type: DashboardCardType.greeting,
        visible: false,
        order: 10,
      ),
    ];
  }

  static List<DashboardCardConfig> _getLegacyDefaultLayout({
    required String role,
    required bool isSuperAdmin,
  }) {
    return [
      DashboardCardConfig(
        type: DashboardCardType.greeting,
        visible: false,
        order: 0,
      ),
      DashboardCardConfig(
        type: DashboardCardType.actionRequired,
        visible: false,
        order: 1,
      ),
      DashboardCardConfig(
        type: DashboardCardType.quickActions,
        visible: true,
        order: 2,
      ),
      DashboardCardConfig(
        type: DashboardCardType.financeSummary,
        visible: false,
        order: 3,
      ),
      DashboardCardConfig(
        type: DashboardCardType.financeDetail,
        visible: false,
        order: 4,
      ),
      DashboardCardConfig(
        type: DashboardCardType.activityFeed,
        visible: false,
        order: 5,
      ),
      DashboardCardConfig(
        type: DashboardCardType.chat,
        visible: true,
        order: 6,
      ),
      DashboardCardConfig(
        type: DashboardCardType.alerts,
        visible: false,
        order: 7,
      ),
      DashboardCardConfig(
        type: DashboardCardType.userGuide,
        visible: true,
        order: 8,
      ),
      DashboardCardConfig(
        type: DashboardCardType.financeShortcuts,
        visible: true,
        order: 9,
      ),
    ];
  }

  static bool _matchesDashboardTemplate(
    List<DashboardCardConfig> configs,
    List<DashboardCardConfig> template,
  ) {
    if (configs.length != template.length) return false;

    final sortedConfigs = [...configs]
      ..sort((a, b) => a.order.compareTo(b.order));
    final sortedTemplate = [...template]
      ..sort((a, b) => a.order.compareTo(b.order));

    for (int i = 0; i < sortedTemplate.length; i++) {
      if (sortedConfigs[i].type != sortedTemplate[i].type) return false;
      if (sortedConfigs[i].visible != sortedTemplate[i].visible) return false;
    }
    return true;
  }

  static List<DashboardCardConfig> _cloneDashboardConfigs(
    List<DashboardCardConfig> configs,
  ) {
    return configs
        .map(
          (config) => DashboardCardConfig(
            type: config.type,
            visible: config.visible,
            order: config.order,
          ),
        )
        .toList();
  }

  static ({List<DashboardCardConfig> configs, bool migrated})
  _migrateDashboardConfigs({
    required List<DashboardCardConfig> configs,
    required int savedVersion,
    required String role,
    required bool isSuperAdmin,
  }) {
    final defaults = getDefaultLayout(role: role, isSuperAdmin: isSuperAdmin);
    final legacyDefaults = _getLegacyDefaultLayout(
      role: role,
      isSuperAdmin: isSuperAdmin,
    );

    if (savedVersion < _schemaVersion &&
        _matchesDashboardTemplate(configs, legacyDefaults)) {
      return (configs: _cloneDashboardConfigs(defaults), migrated: true);
    }

    bool migrated = savedVersion < _schemaVersion;
    final configByType = {
      for (final config in configs)
        config.type: DashboardCardConfig(
          type: config.type,
          visible: config.visible,
          order: config.order,
        ),
    };

    final ordered = <DashboardCardConfig>[];
    final seen = <DashboardCardType>{};
    final existingSorted = [...configs]
      ..sort((a, b) => a.order.compareTo(b.order));

    for (final config in existingSorted) {
      final item = configByType[config.type];
      if (item == null || seen.contains(item.type)) continue;
      ordered.add(item);
      seen.add(item.type);
    }

    for (final defaultConfig in defaults) {
      if (seen.contains(defaultConfig.type)) continue;
      ordered.add(
        DashboardCardConfig(
          type: defaultConfig.type,
          visible: defaultConfig.visible,
          order: ordered.length,
        ),
      );
      seen.add(defaultConfig.type);
      migrated = true;
    }

    for (int i = 0; i < ordered.length; i++) {
      ordered[i].order = i;
    }

    return (configs: ordered, migrated: migrated);
  }

  static Future<void> _writeLocalConfig(
    List<DashboardCardConfig> configs,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final key = '${_prefsKey}_$uid';
    final jsonStr = jsonEncode(configs.map((c) => c.toJson()).toList());
    await prefs.setString(key, jsonStr);
    await prefs.setInt('${_prefsVersionKey}_$uid', _schemaVersion);
  }

  static Future<void> _writeCloudConfig(
    List<DashboardCardConfig> configs,
  ) async {
    final ref = _userDocRef();
    if (ref == null) return;

    await ref.set({
      _cloudField: configs.map((c) => c.toJson()).toList(),
      _cloudVersionField: _schemaVersion,
      'dashboardConfigUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Load saved config or return default
  static Future<List<DashboardCardConfig>> loadConfig({
    required String role,
    required bool isSuperAdmin,
  }) async {
    List<DashboardCardConfig>? localSaved;
    int localVersion = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final key = '${_prefsKey}_$uid';
      final jsonStr = prefs.getString(key);
      localVersion = prefs.getInt('${_prefsVersionKey}_$uid') ?? 0;

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        localSaved = jsonList
            .map((j) => DashboardCardConfig.fromJson(j))
            .toList();

        localSaved.sort((a, b) => a.order.compareTo(b.order));
      }
    } catch (e) {
      debugPrint('DashboardConfigService: Error loading local config: $e');
    }

    try {
      final ref = _userDocRef();
      if (ref != null) {
        final snap = await ref.get();
        final cloudRaw = snap.data()?[_cloudField];
        final cloudVersion =
            (snap.data()?[_cloudVersionField] as num?)?.toInt() ?? 0;
        if (cloudRaw is List) {
          final cloudSaved = cloudRaw
              .whereType<Map>()
              .map(
                (j) =>
                    DashboardCardConfig.fromJson(Map<String, dynamic>.from(j)),
              )
              .toList();
          if (cloudSaved.isNotEmpty) {
            final migrated = _migrateDashboardConfigs(
              configs: cloudSaved,
              savedVersion: cloudVersion,
              role: role,
              isSuperAdmin: isSuperAdmin,
            );
            if (migrated.migrated || cloudVersion != _schemaVersion) {
              await _writeLocalConfig(migrated.configs);
              await _writeCloudConfig(migrated.configs);
            } else {
              await _writeLocalConfig(migrated.configs);
            }
            return migrated.configs;
          }
        }
      }
    } catch (e) {
      debugPrint('DashboardConfigService: Error loading cloud config: $e');
    }

    if (localSaved != null) {
      // Backfill cloud from local cache if cloud is empty.
      try {
        final migrated = _migrateDashboardConfigs(
          configs: localSaved,
          savedVersion: localVersion,
          role: role,
          isSuperAdmin: isSuperAdmin,
        );
        await _writeLocalConfig(migrated.configs);
        await _writeCloudConfig(migrated.configs);
        return migrated.configs;
      } catch (e) {
        debugPrint(
          'DashboardConfigService: Error backfilling cloud config: $e',
        );
      }
    }

    return getDefaultLayout(role: role, isSuperAdmin: isSuperAdmin);
  }

  /// Save config
  static Future<void> saveConfig(List<DashboardCardConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final key = '${_prefsKey}_$uid';
      // Update order based on list position
      for (int i = 0; i < configs.length; i++) {
        configs[i].order = i;
      }
      final jsonStr = jsonEncode(configs.map((c) => c.toJson()).toList());
      await prefs.setString(key, jsonStr);
      await prefs.setInt('${_prefsVersionKey}_$uid', _schemaVersion);

      final ref = _userDocRef();
      if (ref != null) {
        await ref.set({
          _cloudField: configs.map((c) => c.toJson()).toList(),
          _cloudVersionField: _schemaVersion,
          'dashboardConfigUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('DashboardConfigService: Error saving config: $e');
    }
  }

  /// Reset to defaults
  static Future<void> resetConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final key = '${_prefsKey}_$uid';
      await prefs.remove(key);
      await prefs.remove('${_prefsVersionKey}_$uid');

      final ref = _userDocRef();
      if (ref != null) {
        await ref.set({
          _cloudField: FieldValue.delete(),
          _cloudVersionField: FieldValue.delete(),
          'dashboardConfigUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('DashboardConfigService: Error resetting config: $e');
    }
  }
}

// ============================================================
// SHORTCUT CONFIG - Configurable shortcut grid items
// ============================================================

/// All available shortcut types
enum ShortcutType {
  // -- Default visible (12 original) --
  sellCreate, // Bán hàng
  repairCreate, // Đơn sửa
  stockIn, // Nhập kho
  pendingStock, // Chờ XN
  saleList, // Đơn bán
  repairList, // DS sửa
  addExpense, // Thêm chi
  addIncome, // Thêm thu
  inventoryCheck, // Kiểm kho
  report, // Báo cáo
  attendance, // Chấm công
  warranty, // Bảo hành
  // -- Hidden by default (extra) --
  cashClosing, // Sổ quỹ
  customers, // Khách hàng
  suppliers, // Nhà cung cấp
  debt, // Công nợ
  qrScan, // Quét QR
  financialReport, // Tài chính
  activityLog, // Nhật ký TC
  printer, // Máy in
  quickCodes, // Mã nhanh
  bankInstallment, // Trả góp NH
  globalSearch, // Tìm kiếm
  staff, // Nhân sự
  expenses, // Thu chi
  expiryManage, // Hạn sử dụng
  paymentRequest, // Yêu cầu đóng tiền
}

/// Config for a single shortcut item
class ShortcutConfig {
  final ShortcutType type;
  bool visible;
  int order;

  ShortcutConfig({
    required this.type,
    required this.visible,
    required this.order,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'visible': visible,
    'order': order,
  };

  factory ShortcutConfig.fromJson(Map<String, dynamic> json) {
    return ShortcutConfig(
      type: ShortcutType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => ShortcutType.sellCreate,
      ),
      visible: json['visible'] ?? true,
      order: json['order'] ?? 0,
    );
  }

  /// Vietnamese display name
  String get displayName {
    switch (type) {
      case ShortcutType.sellCreate:
        return 'Bán hàng';
      case ShortcutType.repairCreate:
        return 'Đơn sửa';
      case ShortcutType.stockIn:
        return 'Nhập kho';
      case ShortcutType.pendingStock:
        return 'Chờ XN';
      case ShortcutType.saleList:
        return 'Đơn bán';
      case ShortcutType.repairList:
        return 'DS sửa';
      case ShortcutType.addExpense:
        return 'Thêm chi';
      case ShortcutType.addIncome:
        return 'Thêm thu';
      case ShortcutType.inventoryCheck:
        return 'Kiểm kho';
      case ShortcutType.report:
        return 'Báo cáo';
      case ShortcutType.attendance:
        return 'Chấm công';
      case ShortcutType.warranty:
        return 'Bảo hành';
      case ShortcutType.cashClosing:
        return 'Sổ quỹ';
      case ShortcutType.customers:
        return 'Khách hàng';
      case ShortcutType.suppliers:
        return 'Nhà cung cấp';
      case ShortcutType.debt:
        return 'Công nợ';
      case ShortcutType.qrScan:
        return 'Quét QR';
      case ShortcutType.financialReport:
        return 'Tài chính';
      case ShortcutType.activityLog:
        return 'Nhật ký HT';
      case ShortcutType.printer:
        return 'Máy in';
      case ShortcutType.quickCodes:
        return 'Mã nhanh';
      case ShortcutType.bankInstallment:
        return 'Trả góp NH';
      case ShortcutType.globalSearch:
        return 'Tìm kiếm';
      case ShortcutType.staff:
        return 'Nhân sự';
      case ShortcutType.expenses:
        return 'Thu chi';
      case ShortcutType.expiryManage:
        return 'Hạn SD';
      case ShortcutType.paymentRequest:
        return 'Đóng tiền';
    }
  }

  /// Icon for each shortcut
  IconData get icon {
    switch (type) {
      case ShortcutType.sellCreate:
        return Icons.add_shopping_cart;
      case ShortcutType.repairCreate:
        return Icons.build_circle;
      case ShortcutType.stockIn:
        return Icons.add_box;
      case ShortcutType.pendingStock:
        return Icons.pending_actions;
      case ShortcutType.saleList:
        return Icons.receipt_long;
      case ShortcutType.repairList:
        return Icons.list_alt;
      case ShortcutType.addExpense:
        return Icons.remove_circle_outline;
      case ShortcutType.addIncome:
        return Icons.add_circle_outline;
      case ShortcutType.inventoryCheck:
        return Icons.qr_code_scanner;
      case ShortcutType.report:
        return Icons.bar_chart;
      case ShortcutType.attendance:
        return Icons.access_time;
      case ShortcutType.warranty:
        return Icons.shield;
      case ShortcutType.cashClosing:
        return Icons.account_balance_wallet;
      case ShortcutType.customers:
        return Icons.people;
      case ShortcutType.suppliers:
        return Icons.local_shipping;
      case ShortcutType.debt:
        return Icons.money_off;
      case ShortcutType.qrScan:
        return Icons.qr_code;
      case ShortcutType.financialReport:
        return Icons.pie_chart;
      case ShortcutType.activityLog:
        return Icons.history;
      case ShortcutType.printer:
        return Icons.print;
      case ShortcutType.quickCodes:
        return Icons.bolt;
      case ShortcutType.bankInstallment:
        return Icons.credit_card;
      case ShortcutType.globalSearch:
        return Icons.search;
      case ShortcutType.staff:
        return Icons.badge;
      case ShortcutType.expenses:
        return Icons.swap_horiz;
      case ShortcutType.expiryManage:
        return Icons.timer;
      case ShortcutType.paymentRequest:
        return Icons.request_page;
    }
  }

  /// Color for each shortcut
  Color get color {
    switch (type) {
      case ShortcutType.sellCreate:
        return Colors.green;
      case ShortcutType.repairCreate:
        return Colors.blue;
      case ShortcutType.stockIn:
        return Colors.teal;
      case ShortcutType.pendingStock:
        return Colors.orange;
      case ShortcutType.saleList:
        return Colors.indigo;
      case ShortcutType.repairList:
        return Colors.deepPurple;
      case ShortcutType.addExpense:
        return Colors.red;
      case ShortcutType.addIncome:
        return const Color(0xFF388E3C); // Colors.green.shade700
      case ShortcutType.inventoryCheck:
        return Colors.cyan;
      case ShortcutType.report:
        return Colors.purple;
      case ShortcutType.attendance:
        return const Color(0xFF00796B); // Colors.teal.shade700
      case ShortcutType.warranty:
        return const Color(0xFFEF6C00); // Colors.amber.shade800
      case ShortcutType.cashClosing:
        return Colors.blueGrey;
      case ShortcutType.customers:
        return Colors.pink;
      case ShortcutType.suppliers:
        return Colors.brown;
      case ShortcutType.debt:
        return Colors.deepOrange;
      case ShortcutType.qrScan:
        return Colors.lightBlue;
      case ShortcutType.financialReport:
        return Colors.indigo;
      case ShortcutType.activityLog:
        return Colors.amber;
      case ShortcutType.printer:
        return Colors.blueGrey;
      case ShortcutType.quickCodes:
        return Colors.lime;
      case ShortcutType.bankInstallment:
        return Colors.teal;
      case ShortcutType.globalSearch:
        return Colors.grey;
      case ShortcutType.staff:
        return Colors.blue;
      case ShortcutType.expenses:
        return Colors.redAccent;
      case ShortcutType.expiryManage:
        return Colors.orange;
      case ShortcutType.paymentRequest:
        return const Color(0xFF075E54);
    }
  }

  /// Whether this shortcut requires repair module
  bool get requiresRepair {
    return type == ShortcutType.repairCreate || type == ShortcutType.repairList;
  }

  /// Whether this shortcut requires warranty module
  bool get requiresWarranty {
    return type == ShortcutType.warranty;
  }

  /// Permission key required to use this shortcut (null = no restriction)
  String? get requiredPermission {
    switch (type) {
      case ShortcutType.sellCreate:
      case ShortcutType.saleList:
      case ShortcutType.bankInstallment:
        return 'allowViewSales';
      case ShortcutType.repairCreate:
      case ShortcutType.repairList:
        return 'allowViewRepairs';
      case ShortcutType.stockIn:
      case ShortcutType.pendingStock:
      case ShortcutType.inventoryCheck:
      case ShortcutType.expiryManage:
        return 'allowViewInventory';
      case ShortcutType.addExpense:
      case ShortcutType.expenses:
        return 'allowViewExpenses';
      case ShortcutType.addIncome:
      case ShortcutType.report:
      case ShortcutType.cashClosing:
      case ShortcutType.financialReport:
      case ShortcutType.activityLog:
        return 'allowViewRevenue';
      case ShortcutType.attendance:
        return 'allowViewAttendance';
      case ShortcutType.warranty:
        return 'allowViewWarranty';
      case ShortcutType.customers:
        return 'allowViewCustomers';
      case ShortcutType.suppliers:
        return 'allowViewSuppliers';
      case ShortcutType.debt:
        return 'allowViewDebts';
      case ShortcutType.printer:
        return 'allowViewPrinter';
      case ShortcutType.staff:
        return 'allowManageStaff';
      case ShortcutType.quickCodes:
      case ShortcutType.qrScan:
      case ShortcutType.globalSearch:
      case ShortcutType.paymentRequest:
        return null; // Utility shortcuts - no permission required
    }
  }
}

/// Service to manage shortcut configuration
class ShortcutConfigService {
  static const String _prefsKey = 'shortcut_config_v1';
  static const String _prefsVersionKey = 'shortcut_config_version_v1';
  static const String _cloudField = 'shortcutConfigV1';
  static const String _cloudVersionField = 'shortcutConfigVersionV1';
  static const int _schemaVersion = 2;

  /// Get default shortcuts - first 12 visible, rest hidden
  static List<ShortcutConfig> getDefaultShortcuts() {
    const visibleDefaults = {
      ShortcutType.sellCreate,
      ShortcutType.repairCreate,
      ShortcutType.stockIn,
      ShortcutType.pendingStock,
      ShortcutType.saleList,
      ShortcutType.repairList,
      ShortcutType.inventoryCheck,
      ShortcutType.attendance,
      ShortcutType.customers,
      ShortcutType.warranty,
      ShortcutType.qrScan,
      ShortcutType.globalSearch,
    };
    final defaults = <ShortcutConfig>[];
    for (int i = 0; i < ShortcutType.values.length; i++) {
      final type = ShortcutType.values[i];
      defaults.add(
        ShortcutConfig(
          type: type,
          visible: visibleDefaults.contains(type),
          order: i,
        ),
      );
    }
    return defaults;
  }

  static List<ShortcutConfig> _getLegacyDefaultShortcuts() {
    final defaults = <ShortcutConfig>[];
    for (int i = 0; i < ShortcutType.values.length; i++) {
      defaults.add(
        ShortcutConfig(type: ShortcutType.values[i], visible: i < 12, order: i),
      );
    }
    return defaults;
  }

  static bool _matchesShortcutTemplate(
    List<ShortcutConfig> configs,
    List<ShortcutConfig> template,
  ) {
    if (configs.length != template.length) return false;

    final sortedConfigs = [...configs]
      ..sort((a, b) => a.order.compareTo(b.order));
    final sortedTemplate = [...template]
      ..sort((a, b) => a.order.compareTo(b.order));

    for (int i = 0; i < sortedTemplate.length; i++) {
      if (sortedConfigs[i].type != sortedTemplate[i].type) return false;
      if (sortedConfigs[i].visible != sortedTemplate[i].visible) return false;
    }
    return true;
  }

  static List<ShortcutConfig> _cloneShortcutConfigs(
    List<ShortcutConfig> configs,
  ) {
    return configs
        .map(
          (config) => ShortcutConfig(
            type: config.type,
            visible: config.visible,
            order: config.order,
          ),
        )
        .toList();
  }

  static ({List<ShortcutConfig> configs, bool migrated})
  _migrateShortcutConfigs(List<ShortcutConfig> configs, int savedVersion) {
    final defaults = getDefaultShortcuts();
    final legacyDefaults = _getLegacyDefaultShortcuts();

    if (savedVersion < _schemaVersion &&
        _matchesShortcutTemplate(configs, legacyDefaults)) {
      return (configs: _cloneShortcutConfigs(defaults), migrated: true);
    }

    bool migrated = savedVersion < _schemaVersion;
    final configByType = {
      for (final config in configs)
        config.type: ShortcutConfig(
          type: config.type,
          visible: config.visible,
          order: config.order,
        ),
    };
    final ordered = <ShortcutConfig>[];
    final seen = <ShortcutType>{};
    final existingSorted = [...configs]
      ..sort((a, b) => a.order.compareTo(b.order));

    for (final config in existingSorted) {
      final item = configByType[config.type];
      if (item == null || seen.contains(item.type)) continue;
      ordered.add(item);
      seen.add(item.type);
    }

    for (final defaultConfig in defaults) {
      if (seen.contains(defaultConfig.type)) continue;
      ordered.add(
        ShortcutConfig(
          type: defaultConfig.type,
          visible: defaultConfig.visible,
          order: ordered.length,
        ),
      );
      seen.add(defaultConfig.type);
      migrated = true;
    }

    for (int i = 0; i < ordered.length; i++) {
      ordered[i].order = i;
    }

    return (configs: ordered, migrated: migrated);
  }

  static Future<void> _writeLocalConfig(List<ShortcutConfig> configs) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final key = '${_prefsKey}_$uid';
    final jsonStr = jsonEncode(configs.map((c) => c.toJson()).toList());
    await prefs.setString(key, jsonStr);
    await prefs.setInt('${_prefsVersionKey}_$uid', _schemaVersion);
  }

  static Future<void> _writeCloudConfig(List<ShortcutConfig> configs) async {
    final ref = DashboardConfigService._userDocRef();
    if (ref == null) return;

    await ref.set({
      _cloudField: configs.map((c) => c.toJson()).toList(),
      _cloudVersionField: _schemaVersion,
      'shortcutConfigUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Load saved shortcut config or return defaults
  static Future<List<ShortcutConfig>> loadConfig() async {
    List<ShortcutConfig>? localSaved;
    int localVersion = 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final key = '${_prefsKey}_$uid';
      final jsonStr = prefs.getString(key);
      localVersion = prefs.getInt('${_prefsVersionKey}_$uid') ?? 0;

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        localSaved = jsonList.map((j) => ShortcutConfig.fromJson(j)).toList();

        localSaved.sort((a, b) => a.order.compareTo(b.order));
      }
    } catch (e) {
      debugPrint('ShortcutConfigService: Error loading local config: $e');
    }

    try {
      final ref = DashboardConfigService._userDocRef();
      if (ref != null) {
        final snap = await ref.get();
        final cloudRaw = snap.data()?[_cloudField];
        final cloudVersion =
            (snap.data()?[_cloudVersionField] as num?)?.toInt() ?? 0;
        if (cloudRaw is List) {
          final cloudSaved = cloudRaw
              .whereType<Map>()
              .map((j) => ShortcutConfig.fromJson(Map<String, dynamic>.from(j)))
              .toList();
          if (cloudSaved.isNotEmpty) {
            final migrated = _migrateShortcutConfigs(cloudSaved, cloudVersion);
            if (migrated.migrated || cloudVersion != _schemaVersion) {
              await _writeLocalConfig(migrated.configs);
              await _writeCloudConfig(migrated.configs);
            } else {
              await _writeLocalConfig(migrated.configs);
            }
            return migrated.configs;
          }
        }
      }
    } catch (e) {
      debugPrint('ShortcutConfigService: Error loading cloud config: $e');
    }

    if (localSaved != null) {
      try {
        final migrated = _migrateShortcutConfigs(localSaved, localVersion);
        await _writeLocalConfig(migrated.configs);
        await _writeCloudConfig(migrated.configs);
        return migrated.configs;
      } catch (e) {
        debugPrint('ShortcutConfigService: Error backfilling cloud config: $e');
      }
    }

    return getDefaultShortcuts();
  }

  /// Save shortcut config
  static Future<void> saveConfig(List<ShortcutConfig> configs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final key = '${_prefsKey}_$uid';
      for (int i = 0; i < configs.length; i++) {
        configs[i].order = i;
      }
      final jsonStr = jsonEncode(configs.map((c) => c.toJson()).toList());
      await prefs.setString(key, jsonStr);
      await prefs.setInt('${_prefsVersionKey}_$uid', _schemaVersion);

      final ref = DashboardConfigService._userDocRef();
      if (ref != null) {
        await ref.set({
          _cloudField: configs.map((c) => c.toJson()).toList(),
          _cloudVersionField: _schemaVersion,
          'shortcutConfigUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('ShortcutConfigService: Error saving config: $e');
    }
  }

  /// Reset to defaults
  static Future<void> resetConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final key = '${_prefsKey}_$uid';
      await prefs.remove(key);
      await prefs.remove('${_prefsVersionKey}_$uid');

      final ref = DashboardConfigService._userDocRef();
      if (ref != null) {
        await ref.set({
          _cloudField: FieldValue.delete(),
          _cloudVersionField: FieldValue.delete(),
          'shortcutConfigUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('ShortcutConfigService: Error resetting config: $e');
    }
  }
}
