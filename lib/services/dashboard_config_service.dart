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
  static const String _prefsKey = 'dashboard_config_v2';

  /// Get default layout based on role
  static List<DashboardCardConfig> getDefaultLayout({
    required String role,
    required bool isSuperAdmin,
  }) {
    final isOwnerOrAdmin = role == 'owner' || role == 'admin' || isSuperAdmin;

    return [
      DashboardCardConfig(type: DashboardCardType.greeting, visible: true, order: 0),
      DashboardCardConfig(type: DashboardCardType.actionRequired, visible: true, order: 1),
      DashboardCardConfig(type: DashboardCardType.quickActions, visible: true, order: 2),
      DashboardCardConfig(type: DashboardCardType.financeSummary, visible: isOwnerOrAdmin, order: 3),
      DashboardCardConfig(type: DashboardCardType.financeDetail, visible: isOwnerOrAdmin, order: 4),
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
