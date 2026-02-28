import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Represents a dashboard card type
enum DashboardCardType {
  greeting,       // Lời chào
  actionRequired, // Cần xử lý (badges)
  quickActions,   // Thao tác nhanh (grid)
  financeSummary, // Tóm tắt Thu/Chi (compact)
  financeDetail,  // Chi tiết tài chính (full breakdown)
  activityFeed,   // Hoạt động gần đây
  chat,           // Chat nhóm
  alerts,         // Cảnh báo (bảo hành, HSD)
  userGuide,      // Hướng dẫn sử dụng
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
    }
  }

  /// Whether this card requires owner/admin role
  bool get requiresFinanceAccess {
    return type == DashboardCardType.financeSummary ||
           type == DashboardCardType.financeDetail;
  }
}

/// Service to manage dashboard layout configuration
class DashboardConfigService {
  static const String _prefsKey = 'dashboard_config_v3';

  /// Get default layout based on role
  static List<DashboardCardConfig> getDefaultLayout({
    required String role,
    required bool isSuperAdmin,
  }) {
    final isOwnerOrAdmin = role == 'owner' || role == 'admin' || isSuperAdmin;

    return [
      DashboardCardConfig(type: DashboardCardType.greeting, visible: false, order: 0),
      DashboardCardConfig(type: DashboardCardType.actionRequired, visible: true, order: 1),
      DashboardCardConfig(type: DashboardCardType.quickActions, visible: true, order: 2),
      DashboardCardConfig(type: DashboardCardType.financeSummary, visible: false, order: 3),
      DashboardCardConfig(type: DashboardCardType.financeDetail, visible: false, order: 4),
      DashboardCardConfig(type: DashboardCardType.activityFeed, visible: true, order: 5),
      DashboardCardConfig(type: DashboardCardType.chat, visible: true, order: 6),
      DashboardCardConfig(type: DashboardCardType.alerts, visible: true, order: 7),
      DashboardCardConfig(type: DashboardCardType.userGuide, visible: true, order: 8),
    ];
  }

  /// Load saved config or return default
  static Future<List<DashboardCardConfig>> loadConfig({
    required String role,
    required bool isSuperAdmin,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final key = '${_prefsKey}_$uid';
      final jsonStr = prefs.getString(key);

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        final saved = jsonList
            .map((j) => DashboardCardConfig.fromJson(j))
            .toList();

        // Ensure all card types exist (in case we added new ones)
        final defaults = getDefaultLayout(role: role, isSuperAdmin: isSuperAdmin);
        final savedTypes = saved.map((c) => c.type).toSet();
        for (final def in defaults) {
          if (!savedTypes.contains(def.type)) {
            saved.add(DashboardCardConfig(
              type: def.type,
              visible: def.visible,
              order: saved.length,
            ));
          }
        }

        saved.sort((a, b) => a.order.compareTo(b.order));
        return saved;
      }
    } catch (e) {
      debugPrint('DashboardConfigService: Error loading config: $e');
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
  sellCreate,      // Bán hàng
  repairCreate,    // Đơn sửa
  stockIn,         // Nhập kho
  pendingStock,    // Chờ XN
  saleList,        // Đơn bán
  repairList,      // DS sửa
  addExpense,      // Thêm chi
  addIncome,       // Thêm thu
  inventoryCheck,  // Kiểm kho
  report,          // Báo cáo
  attendance,      // Chấm công
  warranty,        // Bảo hành
  // -- Hidden by default (extra) --
  cashClosing,     // Sổ quỹ
  customers,       // Khách hàng
  suppliers,       // Nhà cung cấp
  debt,            // Công nợ
  qrScan,          // Quét QR
  financialReport, // Tài chính
  activityLog,     // Nhật ký TC
  printer,         // Máy in
  quickCodes,      // Mã nhanh
  bankInstallment, // Trả góp NH
  globalSearch,    // Tìm kiếm
  staff,           // Nhân sự
  expenses,        // Thu chi
  expiryManage,    // Hạn sử dụng
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
      case ShortcutType.sellCreate: return 'Bán hàng';
      case ShortcutType.repairCreate: return 'Đơn sửa';
      case ShortcutType.stockIn: return 'Nhập kho';
      case ShortcutType.pendingStock: return 'Chờ XN';
      case ShortcutType.saleList: return 'Đơn bán';
      case ShortcutType.repairList: return 'DS sửa';
      case ShortcutType.addExpense: return 'Thêm chi';
      case ShortcutType.addIncome: return 'Thêm thu';
      case ShortcutType.inventoryCheck: return 'Kiểm kho';
      case ShortcutType.report: return 'Báo cáo';
      case ShortcutType.attendance: return 'Chấm công';
      case ShortcutType.warranty: return 'Bảo hành';
      case ShortcutType.cashClosing: return 'Sổ quỹ';
      case ShortcutType.customers: return 'Khách hàng';
      case ShortcutType.suppliers: return 'Nhà cung cấp';
      case ShortcutType.debt: return 'Công nợ';
      case ShortcutType.qrScan: return 'Quét QR';
      case ShortcutType.financialReport: return 'Tài chính';
      case ShortcutType.activityLog: return 'Nhật ký TC';
      case ShortcutType.printer: return 'Máy in';
      case ShortcutType.quickCodes: return 'Mã nhanh';
      case ShortcutType.bankInstallment: return 'Trả góp NH';
      case ShortcutType.globalSearch: return 'Tìm kiếm';
      case ShortcutType.staff: return 'Nhân sự';
      case ShortcutType.expenses: return 'Thu chi';
      case ShortcutType.expiryManage: return 'Hạn SD';
    }
  }

  /// Icon for each shortcut
  IconData get icon {
    switch (type) {
      case ShortcutType.sellCreate: return Icons.add_shopping_cart;
      case ShortcutType.repairCreate: return Icons.build_circle;
      case ShortcutType.stockIn: return Icons.add_box;
      case ShortcutType.pendingStock: return Icons.pending_actions;
      case ShortcutType.saleList: return Icons.receipt_long;
      case ShortcutType.repairList: return Icons.list_alt;
      case ShortcutType.addExpense: return Icons.remove_circle_outline;
      case ShortcutType.addIncome: return Icons.add_circle_outline;
      case ShortcutType.inventoryCheck: return Icons.qr_code_scanner;
      case ShortcutType.report: return Icons.bar_chart;
      case ShortcutType.attendance: return Icons.access_time;
      case ShortcutType.warranty: return Icons.shield;
      case ShortcutType.cashClosing: return Icons.account_balance_wallet;
      case ShortcutType.customers: return Icons.people;
      case ShortcutType.suppliers: return Icons.local_shipping;
      case ShortcutType.debt: return Icons.money_off;
      case ShortcutType.qrScan: return Icons.qr_code;
      case ShortcutType.financialReport: return Icons.pie_chart;
      case ShortcutType.activityLog: return Icons.history;
      case ShortcutType.printer: return Icons.print;
      case ShortcutType.quickCodes: return Icons.bolt;
      case ShortcutType.bankInstallment: return Icons.credit_card;
      case ShortcutType.globalSearch: return Icons.search;
      case ShortcutType.staff: return Icons.badge;
      case ShortcutType.expenses: return Icons.swap_horiz;
      case ShortcutType.expiryManage: return Icons.timer;
    }
  }

  /// Color for each shortcut
  Color get color {
    switch (type) {
      case ShortcutType.sellCreate: return Colors.green;
      case ShortcutType.repairCreate: return Colors.blue;
      case ShortcutType.stockIn: return Colors.teal;
      case ShortcutType.pendingStock: return Colors.orange;
      case ShortcutType.saleList: return Colors.indigo;
      case ShortcutType.repairList: return Colors.deepPurple;
      case ShortcutType.addExpense: return Colors.red;
      case ShortcutType.addIncome: return const Color(0xFF388E3C); // Colors.green.shade700
      case ShortcutType.inventoryCheck: return Colors.cyan;
      case ShortcutType.report: return Colors.purple;
      case ShortcutType.attendance: return const Color(0xFF00796B); // Colors.teal.shade700
      case ShortcutType.warranty: return const Color(0xFFEF6C00); // Colors.amber.shade800
      case ShortcutType.cashClosing: return Colors.blueGrey;
      case ShortcutType.customers: return Colors.pink;
      case ShortcutType.suppliers: return Colors.brown;
      case ShortcutType.debt: return Colors.deepOrange;
      case ShortcutType.qrScan: return Colors.lightBlue;
      case ShortcutType.financialReport: return Colors.indigo;
      case ShortcutType.activityLog: return Colors.amber;
      case ShortcutType.printer: return Colors.blueGrey;
      case ShortcutType.quickCodes: return Colors.lime;
      case ShortcutType.bankInstallment: return Colors.teal;
      case ShortcutType.globalSearch: return Colors.grey;
      case ShortcutType.staff: return Colors.blue;
      case ShortcutType.expenses: return Colors.redAccent;
      case ShortcutType.expiryManage: return Colors.orange;
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
}

/// Service to manage shortcut configuration
class ShortcutConfigService {
  static const String _prefsKey = 'shortcut_config_v1';

  /// Get default shortcuts - first 12 visible, rest hidden
  static List<ShortcutConfig> getDefaultShortcuts() {
    final defaults = <ShortcutConfig>[];
    for (int i = 0; i < ShortcutType.values.length; i++) {
      final type = ShortcutType.values[i];
      defaults.add(ShortcutConfig(
        type: type,
        visible: i < 12, // First 12 visible by default
        order: i,
      ));
    }
    return defaults;
  }

  /// Load saved shortcut config or return defaults
  static Future<List<ShortcutConfig>> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      final key = '${_prefsKey}_$uid';
      final jsonStr = prefs.getString(key);

      if (jsonStr != null) {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        final saved = jsonList
            .map((j) => ShortcutConfig.fromJson(j))
            .toList();

        // Ensure all shortcut types exist (in case we added new ones)
        final savedTypes = saved.map((c) => c.type).toSet();
        final defaults = getDefaultShortcuts();
        for (final def in defaults) {
          if (!savedTypes.contains(def.type)) {
            saved.add(ShortcutConfig(
              type: def.type,
              visible: false, // New shortcuts hidden by default
              order: saved.length,
            ));
          }
        }

        saved.sort((a, b) => a.order.compareTo(b.order));
        return saved;
      }
    } catch (e) {
      debugPrint('ShortcutConfigService: Error loading config: $e');
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
    } catch (e) {
      debugPrint('ShortcutConfigService: Error resetting config: $e');
    }
  }
}
