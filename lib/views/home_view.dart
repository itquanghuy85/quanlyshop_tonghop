import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/money_utils.dart';
import '../services/event_bus.dart';
import 'order_list_view.dart';
import 'revenue_view.dart';
import 'inventory_view.dart';
import 'fast_inventory_input_view.dart';
import 'fast_inventory_check_view.dart';
import 'supplier_list_view.dart';
import 'quick_input_codes_view.dart';
import 'sale_list_view.dart';
import 'expense_view.dart';
import 'debt_view.dart';
import 'warranty_view.dart';
import 'settings_view.dart';
import 'chat_view.dart';
import 'thermal_printer_design_view.dart';
import 'super_admin_view.dart' as admin_view;
import 'staff_list_view.dart';
import 'qr_scan_view.dart';
import 'attendance_view.dart';
import 'staff_performance_view.dart';
import 'audit_log_view.dart';
import 'notifications_view.dart';
import 'notification_settings_view.dart';
import 'global_search_view.dart';
import 'work_schedule_settings_view.dart';
import 'debt_analysis_view.dart';
import 'create_sale_view.dart';
import 'customer_management_view.dart';
import 'parts_inventory_view.dart';
import 'create_repair_order_view.dart';
import 'about_developer_view.dart';
import '../data/db_helper.dart';
import '../widgets/notification_badge.dart';
import '../widgets/perpetual_calendar.dart';
import '../services/sync_service.dart';
import '../services/sync_health_check.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/encryption_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';

class HomeView extends StatefulWidget {
  final String role;
  final void Function(Locale)? setLocale;

  const HomeView({super.key, required this.role, this.setLocale});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin {
  final db = DBHelper();
  int totalPendingRepair = 0;
  int todaySaleCount = 0;
  int _currentIndex = 0; // Bottom navigation index
  int _totalLocalRecords =
      0; // Tổng số dữ liệu local (để biết máy mới hay không)

  _HomeViewState() {
    debugPrint('HomeView: _HomeViewState constructor called');
  }

  // Tab configurations with permissions
  late List<Map<String, dynamic>> _tabConfigs;
  late List<BottomNavigationBarItem> _navItems;
  late List<Widget> _tabWidgets;

  int _rebuildCounter = 0; // Force rebuild counter

  // Missing variable declarations
  Timer? _autoSyncTimer;
  Timer? _statsDebounceTimer; // Add debounce timer
  Map<String, bool> _permissions = {};
  List<dynamic> _lockedByAdmin = []; // Danh sách quyền bị Admin khóa
  List<dynamic> _lockedByOwner = []; // Danh sách quyền bị Chủ shop khóa
  bool _shopLocked = false;
  final TextEditingController _phoneSearchCtrl = TextEditingController();
  bool _isSyncing = false;
  int todayRepairDone = 0;
  int revenueToday = 0;
  int todayNewRepairs = 0;
  int todayExpense = 0;
  int totalDebtRemain = 0;
  int expiringWarranties = 0;
  int unreadChatCount = 0;
  bool _notificationWorking = false; // Trạng thái thông báo

  final bool _isSuperAdmin = UserService.isCurrentUserSuperAdmin();
  bool get hasFullAccess =>
      widget.role == 'admin' || widget.role == 'owner' || _isSuperAdmin;

  @override
  void initState() {
    super.initState();
    debugPrint('HomeView: initState STARTED - instance created');
    _initializeTabConfigs();

    // Delay các tác vụ nặng sau khi UI render xong để tránh treo máy yếu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotificationStatus(); // Kiểm tra trạng thái thông báo
      _initialSetup();
      SyncService.initRealTimeSync(() {
        _debouncedLoadStats();
      });
      _autoSyncTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _syncNow(silent: true),
      );

      // Listen to debt changes to update stats
      EventBus().stream.listen((event) {
        debugPrint('HomeView: Received event: $event');
        if ((event == 'debts_changed' ||
                event == 'sales_changed' ||
                event == 'repairs_changed') &&
            mounted) {
          debugPrint('HomeView: Loading stats for event: $event');
          _debouncedLoadStats();
        }
      }, onError: (e) => debugPrint('HomeView: EventBus error: $e'));

      // Listen to notifications for snackbars
      NotificationService.listenToNotifications((title, body) {
        if (mounted) {
          NotificationService.showSnackBar('$title: $body');
        }
      });

      // Fallback: if permissions not loaded after 5 seconds, force update
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _permissions.isEmpty) {
          debugPrint('Permissions not loaded, forcing update');
          _updatePermissions();
        }
      });
    });
  }

  void _initializeTabConfigs() {
    _tabConfigs = [
      {
        'permission': null, // Home always accessible
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        'widget': _buildHomeTab(),
      },
      {
        'permission': 'allowViewSales',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.shopping_cart_outlined),
          activeIcon: Icon(Icons.shopping_cart_rounded),
          label: 'Bán hàng',
        ),
        'widget': _buildSalesTab(),
      },
      {
        'permission': 'allowViewRepairs',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.build_outlined),
          activeIcon: Icon(Icons.build_rounded),
          label: 'Sửa chữa',
        ),
        'widget': _buildRepairsTab(),
      },
      {
        'permission': 'allowViewInventory',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.inventory_2_outlined),
          activeIcon: Icon(Icons.inventory_2_rounded),
          label: 'Kho',
        ),
        'widget': _buildInventoryTab(),
      },
      {
        'permission':
            'allowManageStaff', // Staff tab requires manage staff permission
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          activeIcon: Icon(Icons.people_rounded),
          label: 'Nhân sự',
        ),
        'widget': _buildStaffTab(),
      },
      {
        'permission':
            'allowViewRevenue', // Finance tab requires revenue permission
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet_outlined),
          activeIcon: Icon(Icons.account_balance_wallet_rounded),
          label: 'Tài chính',
        ),
        'widget': _buildFinanceTab(),
      },
      {
        'permission':
            null, // Cài đặt luôn mở cho tất cả, chỉ Super Admin mới khóa được
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings_rounded),
          label: 'Cài đặt',
        ),
        'widget': _buildSettingsTab(),
      },
    ];
    // Initially show all tabs until permissions are loaded
    _navItems = _tabConfigs
        .map((config) => config['item'] as BottomNavigationBarItem)
        .toList();
    _tabWidgets = _tabConfigs
        .map((config) => config['widget'] as Widget)
        .toList();
  }

  /// Widget hiển thị thông báo chức năng bị khóa - giao diện chuyên nghiệp
  /// [lockedBy]: 'admin' = Super Admin khóa, 'owner' = Chủ shop phân quyền
  Widget _buildLockedFeatureScreen(
    String featureName, {
    String lockedBy = 'owner',
  }) {
    final isLockedByAdmin = lockedBy == 'admin';
    final lockMessage = isLockedByAdmin
        ? 'Tính năng này đã bị khóa bởi Quản trị viên (Admin).\nVui lòng liên hệ nhà phát triển để được hỗ trợ mở khóa.'
        : 'Bạn không có quyền truy cập tính năng này.\nVui lòng liên hệ Chủ shop để được cấp quyền.';
    final contactTitle = isLockedByAdmin
        ? 'HỖ TRỢ KỸ THUẬT'
        : 'LIÊN HỆ CHỦ SHOP';
    final contactName = isLockedByAdmin ? 'Huluca Tech' : 'Chủ cửa hàng';

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon khóa với animation
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: (isLockedByAdmin ? AppColors.error : Colors.orange)
                      .withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isLockedByAdmin
                      ? Icons.admin_panel_settings
                      : Icons.lock_person,
                  size: 80,
                  color: isLockedByAdmin ? AppColors.error : Colors.orange,
                ),
              ),
              const SizedBox(height: 32),

              // Badge nguồn khóa
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isLockedByAdmin
                      ? Colors.red.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isLockedByAdmin
                        ? Colors.red.shade200
                        : Colors.orange.shade200,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLockedByAdmin ? Icons.security : Icons.person,
                      size: 16,
                      color: isLockedByAdmin ? Colors.red : Colors.orange,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLockedByAdmin ? 'ADMIN KHÓA' : 'CHỦ SHOP PHÂN QUYỀN',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isLockedByAdmin ? Colors.red : Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Tiêu đề
              Text(
                'Chức năng bị khóa',
                style: AppTextStyles.headline5.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // Tên chức năng
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  featureName,
                  style: AppTextStyles.subtitle1.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Mô tả
              Text(
                lockMessage,
                style: AppTextStyles.body1.copyWith(
                  color: AppColors.onSurface.withOpacity(0.7),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // Card thông tin liên hệ - chỉ hiển thị cho Admin lock
              if (isLockedByAdmin)
                _buildAdminContactCard(contactTitle, contactName)
              else
                _buildOwnerContactCard(),
            ],
          ),
        ),
      ),
    );
  }

  /// Card liên hệ Admin (Huluca Tech)
  Widget _buildAdminContactCard(String contactTitle, String contactName) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.support_agent_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contactTitle,
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white.withOpacity(0.8),
                            letterSpacing: 1,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          contactName,
                          style: AppTextStyles.headline6.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: Colors.white24, height: 1),
              const SizedBox(height: 20),

              // Số điện thoại
              _buildContactRow(
                icon: Icons.phone_rounded,
                label: 'Hotline',
                value: '0964.09.59.79',
                onTap: () => _makePhoneCall('0964095979'),
              ),
              const SizedBox(height: 16),

              // Zalo
              _buildContactRow(
                icon: Icons.chat_bubble_rounded,
                label: 'Zalo',
                value: '0964.09.59.79',
                onTap: () => _openZalo('0964095979'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Ghi chú thời gian hỗ trợ
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.access_time_rounded, color: AppColors.info, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hỗ trợ 24/7 • Phản hồi trong vòng 30 phút',
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.info,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Card hướng dẫn liên hệ Chủ shop
  Widget _buildOwnerContactCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange.shade600, Colors.orange.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.store_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'LIÊN HỆ CHỦ SHOP',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withOpacity(0.8),
                        letterSpacing: 1,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Yêu cầu cấp quyền',
                      style: AppTextStyles.headline6.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 20),

          // Hướng dẫn
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStepRow('1', 'Liên hệ Chủ shop hoặc Quản lý của bạn'),
                const SizedBox(height: 12),
                _buildStepRow('2', 'Yêu cầu cấp quyền truy cập tính năng này'),
                const SizedBox(height: 12),
                _buildStepRow(
                  '3',
                  'Sau khi được cấp quyền, đăng nhập lại để áp dụng',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(String step, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white.withOpacity(0.7),
                    ),
                  ),
                  Text(
                    value,
                    style: AppTextStyles.subtitle1.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      await launchUrl(launchUri);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể thực hiện cuộc gọi: $phoneNumber'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _openZalo(String phoneNumber) async {
    final Uri zaloUri = Uri.parse('https://zalo.me/$phoneNumber');
    try {
      await launchUrl(zaloUri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở Zalo. Vui lòng liên hệ: $phoneNumber'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  /// Xác định nguồn khóa quyền: 'admin' hoặc 'owner'
  /// [permissionKey] - key quyền như 'allowViewSales', 'allowViewInventory'
  String _getLockedBy(String permissionKey) {
    // Kiểm tra xem quyền này có trong danh sách khóa bởi Admin không
    if (_lockedByAdmin.contains(permissionKey)) {
      return 'admin';
    }
    // Kiểm tra xem quyền này có trong danh sách khóa bởi Owner không
    if (_lockedByOwner.contains(permissionKey)) {
      return 'owner';
    }
    // Mặc định là owner (chủ shop phân quyền)
    return 'owner';
  }

  void _updateAvailableTabs() {
    debugPrint(
      'HomeView: _updateAvailableTabs called, _tabConfigs.length = ${_tabConfigs.length}',
    );
    debugPrint('HomeView: _permissions = $_permissions');

    // THAY ĐỔI: Luôn hiển thị tất cả các tab, nhưng thay nội dung bằng màn hình khóa nếu không có quyền
    final allConfigs = _tabConfigs.map((config) {
      final permission = config['permission'] as String?;
      final hasPermission =
          permission == null || (_permissions[permission] == true);
      debugPrint(
        'HomeView: Tab ${config['item'].label} permission=$permission, hasPermission=$hasPermission',
      );

      // Nếu không có quyền, thay thế widget bằng màn hình khóa
      if (!hasPermission && permission != null) {
        final tabLabel =
            (config['item'] as BottomNavigationBarItem).label ?? 'Chức năng';
        // Xác định nguồn khóa: admin hay owner
        final lockedBy = _getLockedBy(permission);
        return {
          ...config,
          'widget': _buildLockedFeatureScreen(tabLabel, lockedBy: lockedBy),
        };
      }
      return config;
    }).toList();

    // Limit to 7 tabs max for BottomNavigationBar compatibility
    if (allConfigs.length > 7) {
      // Prioritize: Home, Sales, Repairs, Inventory, Staff, Finance, Settings
      final priorityTabs = [
        'Home',
        'Bán hàng',
        'Sửa chữa',
        'Kho',
        'Nhân sự',
        'Tài chính',
        'Cài đặt',
      ];
      final prioritized = allConfigs
          .where(
            (config) => priorityTabs.contains(
              (config['item'] as BottomNavigationBarItem).label,
            ),
          )
          .toList();
      final remaining = allConfigs
          .where(
            (config) => !priorityTabs.contains(
              (config['item'] as BottomNavigationBarItem).label,
            ),
          )
          .toList();
      allConfigs.clear();
      allConfigs.addAll(prioritized);
      allConfigs.addAll(remaining.take(7 - prioritized.length));
    }

    _navItems = allConfigs
        .map((config) => config['item'] as BottomNavigationBarItem)
        .toList();
    _tabWidgets = allConfigs
        .map((config) => config['widget'] as Widget)
        .toList();

    debugPrint('HomeView: Available tabs after limit: ${allConfigs.length}');
    debugPrint(
      'HomeView: Available tab names: ${allConfigs.map((c) => (c['item'] as BottomNavigationBarItem).label)}',
    );

    // Adjust current index if it's out of bounds
    if (_currentIndex >= _navItems.length) {
      _currentIndex = 0;
    }
  }

  /// Rebuild all tab widgets to reflect updated state variables
  /// This is necessary because IndexedStack caches child widgets
  void _rebuildTabWidgets() {
    debugPrint(
      'HomeView: _rebuildTabWidgets called - rebuilding all tabs with fresh data',
    );
    // Rebuild tab configs with current data values
    _tabConfigs = [
      {
        'permission': null,
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home_rounded),
          label: 'Home',
        ),
        'widget': _buildHomeTab(),
      },
      {
        'permission': 'allowViewSales',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.shopping_cart_outlined),
          activeIcon: Icon(Icons.shopping_cart_rounded),
          label: 'Bán hàng',
        ),
        'widget': _buildSalesTab(),
      },
      {
        'permission': 'allowViewRepairs',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.build_outlined),
          activeIcon: Icon(Icons.build_rounded),
          label: 'Sửa chữa',
        ),
        'widget': _buildRepairsTab(),
      },
      {
        'permission': 'allowViewInventory',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.inventory_2_outlined),
          activeIcon: Icon(Icons.inventory_2_rounded),
          label: 'Kho',
        ),
        'widget': _buildInventoryTab(),
      },
      {
        'permission': 'allowManageStaff',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.people_outline),
          activeIcon: Icon(Icons.people_rounded),
          label: 'Nhân sự',
        ),
        'widget': _buildStaffTab(),
      },
      {
        'permission': 'allowViewRevenue',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet_outlined),
          activeIcon: Icon(Icons.account_balance_wallet_rounded),
          label: 'Tài chính',
        ),
        'widget': _buildFinanceTab(),
      },
      {
        'permission':
            null, // Cài đặt luôn mở cho tất cả, chỉ Super Admin mới khóa được
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.settings_outlined),
          activeIcon: Icon(Icons.settings_rounded),
          label: 'Cài đặt',
        ),
        'widget': _buildSettingsTab(),
      },
    ];

    // THAY ĐỔI: Luôn hiển thị tất cả các tab, nhưng thay nội dung bằng màn hình khóa nếu không có quyền
    final allConfigs = _tabConfigs.map((config) {
      final permission = config['permission'] as String?;
      final hasPermission =
          permission == null || (_permissions[permission] == true);

      // Nếu không có quyền, thay thế widget bằng màn hình khóa
      if (!hasPermission) {
        final tabLabel =
            (config['item'] as BottomNavigationBarItem).label ?? 'Chức năng';
        return {...config, 'widget': _buildLockedFeatureScreen(tabLabel)};
      }
      return config;
    }).toList();

    // Limit to 7 tabs max
    if (allConfigs.length > 7) {
      final priorityTabs = [
        'Home',
        'Bán hàng',
        'Sửa chữa',
        'Kho',
        'Nhân sự',
        'Tài chính',
        'Cài đặt',
      ];
      final prioritized = allConfigs
          .where(
            (config) => priorityTabs.contains(
              (config['item'] as BottomNavigationBarItem).label,
            ),
          )
          .toList();
      final remaining = allConfigs
          .where(
            (config) => !priorityTabs.contains(
              (config['item'] as BottomNavigationBarItem).label,
            ),
          )
          .toList();
      allConfigs.clear();
      allConfigs.addAll(prioritized);
      allConfigs.addAll(remaining.take(7 - prioritized.length));
    }

    _navItems = allConfigs
        .map((config) => config['item'] as BottomNavigationBarItem)
        .toList();
    _tabWidgets = allConfigs
        .map((config) => config['widget'] as Widget)
        .toList();

    if (_currentIndex >= _navItems.length) {
      _currentIndex = 0;
    }

    debugPrint('HomeView: Rebuilt ${_tabWidgets.length} tabs');
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _statsDebounceTimer?.cancel();
    _phoneSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _initialSetup() async {
    try {
      // Đợi 1 frame để UI render trước
      await Future.delayed(const Duration(milliseconds: 100));

      final prefs = await SharedPreferences.getInstance();
      final currentUser = FirebaseAuth.instance.currentUser;
      final lastUserId = prefs.getString('lastUserId');

      // Khi đổi user, KHÔNG xóa toàn bộ data local nữa
      // Chỉ cần update lastUserId và sync lại từ cloud
      // Dữ liệu sẽ được lọc theo shopId trong các queries
      if (currentUser != null && currentUser.uid != lastUserId) {
        debugPrint(
          'HomeView: User changed from $lastUserId to ${currentUser.uid}',
        );
        // KHÔNG GỌI db.clearAllData() - giữ lại data để tránh mất dữ liệu
        // Thay vào đó, sync lại từ cloud với shopId mới
        await prefs.setString('lastUserId', currentUser.uid);
        if (currentUser.email != null) {
          await UserService.syncUserInfo(currentUser.uid, currentUser.email!);
          // Download lại dữ liệu từ cloud cho shop mới
          try {
            await SyncService.downloadAllFromCloud().timeout(
              const Duration(seconds: 20),
              onTimeout: () {
                debugPrint('HomeView: Sync timeout khi đổi user');
              },
            );
          } catch (e) {
            debugPrint('HomeView: Lỗi sync khi đổi user: $e');
          }
        }
      }

      // Đợi 1 frame trước khi clean duplicate
      await Future.delayed(Duration.zero);
      await db.cleanDuplicateData();

      // Load stats và permissions
      debugPrint('HomeView: Loading stats and permissions...');
      await _loadStats();
      await _updatePermissions();
    } catch (e) {
      debugPrint('Error in _initialSetup: $e');
      // Still try to load permissions
      await _updatePermissions();
    }
  }

  Future<void> _updatePermissions() async {
    debugPrint('HomeView: _updatePermissions called');
    try {
      final perms = await UserService.getCurrentUserPermissions();
      if (!mounted) return;
      setState(() {
        _shopLocked = perms['shopAppLocked'] == true;
        _lockedByAdmin = perms['lockedByAdmin'] as List<dynamic>? ?? [];
        _lockedByOwner = perms['lockedByOwner'] as List<dynamic>? ?? [];
        _permissions = {};
        perms.forEach((key, value) {
          if (value is bool) {
            _permissions[key] = value;
          }
        });
        _updateAvailableTabs();
      });
      debugPrint('HomeView permissions updated: $_permissions');
      debugPrint('Locked by Admin: $_lockedByAdmin');
      debugPrint('Locked by Owner: $_lockedByOwner');
    } catch (e) {
      debugPrint('Error updating permissions: $e');
      if (!mounted) return;
      setState(() {
        _permissions = {'allowViewSettings': true}; // Minimal permissions
        _lockedByAdmin = [];
        _lockedByOwner = [];
        _updateAvailableTabs();
      });
    }
  }

  Future<void> _syncNow({bool silent = false}) async {
    if (_isSyncing) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      await SyncService.syncAllToCloud();
      await SyncService.downloadAllFromCloud();
      await _loadStats();
    } catch (e) {
      debugPrint("SYNC ERROR: $e");
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  bool _isSameDay(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal();
    final now = DateTime.now();
    final result =
        date.year == now.year && date.month == now.month && date.day == now.day;
    return result;
  }

  void _debouncedLoadStats() {
    _statsDebounceTimer?.cancel();
    _statsDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) _loadStats();
    });
  }

  // State variables for accurate financial overview (same as revenue_view.dart)
  int _todayTotalIn =
      0; // THU HÔM NAY (totalPrice from sales + price from repairs)
  int _todayTotalOut = 0; // CHI HÔM NAY (expenses)
  int _todayNetProfit = 0; // LỢI NHUẬN RÒNG (totalIn - totalOut - costs)
  int _todayRepairCount = 0; // Số đơn sửa chữa hoàn thành hôm nay
  int _todaySaleOrderCount = 0; // Số đơn bán hàng hôm nay
  int _todayExpenseCount = 0; // Số chi phí hôm nay

  Future<void> _loadStats() async {
    // Yield để UI không bị treo
    await Future.delayed(Duration.zero);

    final repairs = await db.getAllRepairs();
    await Future.delayed(Duration.zero); // Yield

    final sales = await db.getAllSales();
    await Future.delayed(Duration.zero); // Yield

    final debts = await db.getAllDebts();
    await Future.delayed(Duration.zero); // Yield

    final expenses = await db.getAllExpenses();

    int pendingR = repairs.where((r) => r.status == 1 || r.status == 2).length;
    int doneT = 0, soldT = 0, newRT = 0, debtR = 0, expW = 0;
    final now = DateTime.now();

    // === TÍNH TOÁN CHÍNH XÁC NHƯ REVENUE_VIEW.DART ===
    // Lọc sales hôm nay
    final fSales = sales.where((s) => _isSameDay(s.soldAt)).toList();

    // Lọc repairs đã giao (status == 4) và deliveredAt hôm nay
    final fRepairs = repairs
        .where(
          (r) =>
              r.status == 4 &&
              r.deliveredAt != null &&
              _isSameDay(r.deliveredAt!),
        )
        .toList();

    // Lọc expenses hôm nay
    final fExpenses = expenses
        .where((e) => _isSameDay(e['date'] as int))
        .toList();

    // THU HÔM NAY = totalPrice (bán hàng) + price (sửa chữa)
    int totalIn =
        fSales.fold<int>(0, (sum, s) => sum + s.totalPrice) +
        fRepairs.fold<int>(0, (sum, r) => sum + r.price);

    // CHI HÔM NAY = tổng expenses
    int totalOut = fExpenses.fold<int>(
      0,
      (sum, e) => sum + (e['amount'] as int),
    );

    // LỢI NHUẬN RÒNG = THU - CHI - GIÁ VỐN
    int profit =
        totalIn -
        totalOut -
        fSales.fold<int>(0, (sum, s) => sum + s.totalCost) -
        fRepairs.fold<int>(0, (sum, r) => sum + r.totalCost);

    // Thống kê số lượng
    doneT = fRepairs.length;
    soldT = fSales.length;

    // Tính toán các số liệu khác
    for (var r in repairs) {
      if (_isSameDay(r.createdAt)) newRT++;
      // Kiểm tra bảo hành sắp hết
      if (r.deliveredAt != null &&
          r.warranty.isNotEmpty &&
          r.warranty != "KO BH") {
        int m = int.tryParse(r.warranty.split(' ').first) ?? 0;
        if (m > 0) {
          DateTime d = DateTime.fromMillisecondsSinceEpoch(r.deliveredAt!);
          DateTime e = DateTime(d.year, d.month + m, d.day);
          if (e.isAfter(now) && e.difference(now).inDays <= 7) expW++;
        }
      }
    }

    // Kiểm tra bảo hành sắp hết cho sales
    for (var s in sales) {
      if (s.warranty.isNotEmpty && s.warranty != "KO BH") {
        int m = int.tryParse(s.warranty.split(' ').first) ?? 12;
        DateTime d = DateTime.fromMillisecondsSinceEpoch(s.soldAt);
        DateTime e = DateTime(d.year, d.month + m, d.day);
        if (e.isAfter(now) && e.difference(now).inDays <= 7) expW++;
      }
    }

    // Tính tổng nợ còn lại
    for (var d in debts) {
      final int remain = (d['totalAmount'] ?? 0) - (d['paidAmount'] ?? 0);
      if (remain > 0) debtR += remain;
    }

    // Tính tổng số dữ liệu local (để biết máy mới hay không)
    final products = await db.getAllProducts();
    final totalRecords = repairs.length + sales.length + products.length;

    if (mounted) {
      setState(() {
        totalPendingRepair = pendingR;
        todayRepairDone = doneT;
        todaySaleCount = soldT;
        revenueToday = profit; // Keep for backward compatibility
        todayNewRepairs = newRT;
        todayExpense = totalOut;
        totalDebtRemain = debtR;
        expiringWarranties = expW;
        // New accurate financial variables
        _todayTotalIn = totalIn;
        _todayTotalOut = totalOut;
        _todayNetProfit = profit;
        _todayRepairCount = fRepairs.length;
        _todaySaleOrderCount = fSales.length;
        _todayExpenseCount = fExpenses.length;
        _totalLocalRecords = totalRecords; // Cập nhật tổng records
        _rebuildCounter++;
        // QUAN TRỌNG: Rebuild _tabWidgets để cập nhật các giá trị mới
        // Các widget trong IndexedStack được cache nên cần tạo lại
        _rebuildTabWidgets();
      });
    }

    // Load unread chat count
    final unread = await UserService.getUnreadChatCount(
      FirebaseAuth.instance.currentUser!.uid,
    );
    if (mounted) setState(() => unreadChatCount = unread);
  }

  /// Kiểm tra trạng thái thông báo (quyền + FCM token)
  Future<void> _checkNotificationStatus() async {
    final status = await NotificationService.checkNotificationStatus();
    if (mounted) {
      setState(() {
        _notificationWorking = status['isFullyWorking'] ?? false;
      });
      debugPrint('Notification status: $_notificationWorking');
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      'HomeView: Building with revenueToday=$revenueToday, todaySaleCount=$todaySaleCount',
    );
    debugPrint('HomeView: Current tab index: $_currentIndex');
    debugPrint('HomeView: _navItems.length = ${_navItems.length}');
    debugPrint(
      'HomeView: _navItems labels = ${_navItems.map((item) => item.label)}',
    );
    return WillPopScope(
      onWillPop: () async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text("Thoát ứng dụng?"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text("HỦY"),
              ),
              TextButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text("THOÁT"),
              ),
            ],
          ),
        );
        return ok ?? false;
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.surface,
          elevation: 0,
          title: Row(
            children: [
              Icon(Icons.store_rounded, color: AppColors.primary, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _getTabTitle(_currentIndex),
                  style: AppTextStyles.headline6.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            NotificationBadge(
              unreadCount: FirestoreService.getUnreadCount(),
              child: IconButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationsView()),
                ),
                icon: Icon(
                  Icons.notifications,
                  color: _notificationWorking
                      ? AppColors.success
                      : AppColors.secondary,
                ),
                tooltip: _notificationWorking
                    ? 'Thông báo (đang hoạt động)'
                    : 'Thông báo (chưa kích hoạt)',
              ),
            ),
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QrScanView(role: widget.role),
                ),
              ),
              icon: Icon(
                Icons.qr_code_scanner_rounded,
                color: AppColors.primary,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GlobalSearchView(role: widget.role),
                ),
              ),
              icon: Icon(Icons.search, color: AppColors.primary, size: 28),
              tooltip: 'Tìm kiếm toàn app',
            ),
            IconButton(
              onPressed: () => _syncNow(),
              icon: _isSyncing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.sync, color: AppColors.success, size: 28),
            ),
            IconButton(
              onPressed: () async {
                await SyncService.cancelAllSubscriptions();
                EncryptionService.reset(); // Reset mã hóa khi đăng xuất
                UserService.clearCache(); // Xóa cache shopId
                UserService.setAdminSelectedShop(null); // Xóa shop đã chọn của admin
                await DBHelper().clearAllData(); // Xóa dữ liệu local
                try {
                  await FirebaseAuth.instance.signOut();
                } catch (e) {
                  debugPrint('Logout error: $e');
                }
              },
              icon: Icon(Icons.logout_rounded, color: AppColors.error),
            ),
          ],
        ),
        body: IndexedStack(
          key: ValueKey(
            'indexed_stack_${_rebuildCounter}',
          ), // Force rebuild when stats change
          index: _currentIndex,
          children: _tabWidgets,
        ),
        bottomNavigationBar: _navItems.length < 2
            ? null
            : Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: List.generate(_navItems.length, (index) {
                        final item = _navItems[index];
                        final isSelected = _currentIndex == index;
                        return _buildAnimatedNavItem(item, index, isSelected);
                      }),
                    ),
                  ),
                ),
              ),
      ),
    );
  }

  /// Animated navigation item với hiệu ứng scale và màu sắc
  Widget _buildAnimatedNavItem(
    BottomNavigationBarItem item,
    int index,
    bool isSelected,
  ) {
    // Màu cho từng tab
    final tabColors = [
      AppColors.primary, // Home - blue
      Colors.green, // Bán hàng - green
      Colors.blue.shade700, // Sửa chữa - blue
      Colors.orange, // Kho - orange
      Colors.teal, // Nhân sự - teal
      Colors.indigo, // Tài chính - indigo
      Colors.blueGrey, // Cài đặt - blueGrey
    ];

    final color = index < tabColors.length
        ? tabColors[index]
        : AppColors.primary;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() => _currentIndex = index);
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.all(isSelected ? 10 : 6),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: AnimatedScale(
                  scale: isSelected ? 1.15 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    isSelected
                        ? (item.activeIcon as Icon).icon
                        : (item.icon as Icon).icon,
                    size: isSelected ? 24 : 22,
                    color: isSelected
                        ? color
                        : AppColors.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isSelected
                      ? color
                      : AppColors.onSurface.withOpacity(0.5),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: isSelected ? 10 : 9,
                ),
                child: Text(
                  item.label ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    debugPrint('_buildHomeTab called with _rebuildCounter=${_rebuildCounter}');
    return RefreshIndicator(
      key: ValueKey(
        'home_tab_${_rebuildCounter}',
      ), // Force rebuild when stats change
      onRefresh: () => _syncNow(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_shopLocked)
            Card(
              color: Colors.red.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(color: Colors.red.shade200),
              ),
              child: const ListTile(
                leading: Icon(Icons.lock, color: Colors.red),
                title: Text(
                  "CỬA HÀNG BỊ KHÓA",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  "Liên hệ Admin để mở khóa",
                  style: TextStyle(fontSize: 11),
                ),
              ),
            ),
          // Banner cho nhân viên mới - CHỈ HIỆN KHI MÁY CÓ ÍT HƠN 5 RECORDS (máy mới/đổi máy)
          if (_totalLocalRecords < 5) _buildNewStaffBanner(),

          // TỔNG QUAN TÀI CHÍNH
          _buildSectionHeader("TỔNG QUAN TÀI CHÍNH"),
          _buildDashboardOverview(),

          const SizedBox(height: 20),

          // THAO TÁC NHANH
          _buildSectionHeader("THAO TÁC NHANH"),
          _buildQuickActionsNew(),

          const SizedBox(height: 20),

          // LỊCH & NHẮC NHỞ
          _buildSectionHeader("LỊCH & NHẮC NHỞ"),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 2,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: PerpetualCalendar(),
            ),
          ),

          const SizedBox(height: 20),

          // CẢNH BÁO
          _buildAlerts(),

          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildNewStaffBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.waving_hand,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chào mừng nhân viên mới!',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Tải dữ liệu shop về máy để bắt đầu làm việc',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showDownloadDataDialog,
              icon: const Icon(Icons.cloud_download, size: 20),
              label: const Text(
                'TẢI DỮ LIỆU SHOP',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade600,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDownloadDataDialog() async {
    // Lấy tên shop để hiển thị
    final shopId = await UserService.getCurrentShopId();
    String shopName = "shop hiện tại";
    if (shopId != null) {
      final shopDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .get();
      if (shopDoc.exists) {
        shopName = shopDoc.data()?['name'] ?? shopName;
      }
    }

    if (!mounted) return;

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.cloud_download, color: Colors.blue.shade600),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "TẢI DỮ LIỆU SHOP",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 14),
                children: [
                  const TextSpan(text: 'Tải dữ liệu của '),
                  TextSpan(
                    text: '"$shopName"',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const TextSpan(text: ' từ đám mây về máy này.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDataItem(Icons.build, 'Đơn sửa chữa'),
                  _buildDataItem(Icons.shopping_cart, 'Đơn bán hàng'),
                  _buildDataItem(Icons.inventory, 'Sản phẩm trong kho'),
                  _buildDataItem(Icons.receipt, 'Công nợ & Chi phí'),
                  _buildDataItem(Icons.people, 'Khách hàng & NCC'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chỉ tải dữ liệu của shop này, không ảnh hưởng shop khác.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Quá trình có thể mất vài phút tùy lượng dữ liệu.",
              style: TextStyle(
                fontSize: 11,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download, size: 18),
            label: const Text("BẮT ĐẦU TẢI"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      // Show loading overlay
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => WillPopScope(
          onWillPop: () async => false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Đang tải dữ liệu shop...',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vui lòng đợi trong giây lát',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ),
      );

      try {
        await SyncService.downloadAllFromCloud();
        try {
          await _loadStats();
        } catch (statsError) {
          debugPrint('Error loading stats after download: $statsError');
        }
        if (mounted) Navigator.of(context).pop(); // Close loading dialog
        NotificationService.showSnackBar(
          "✅ Đã tải xong dữ liệu shop!",
          color: Colors.green,
        );
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // Close loading dialog
        NotificationService.showSnackBar("❌ Lỗi: $e", color: Colors.red);
      }
    }
  }

  Widget _buildDataItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue.shade600),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  /// Section header giống Settings View
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Colors.blueGrey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Quick Actions mới theo style Settings
  Widget _buildQuickActionsNew() {
    return Column(
      children: [
        // BÁN HÀNG
        Card(
          color: Colors.green.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: Colors.green.shade200),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.add_shopping_cart,
                color: Colors.green,
                size: 24,
              ),
            ),
            title: const Text(
              "TẠO ĐƠN BÁN HÀNG",
              style: TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: const Text(
              "Bán sản phẩm nhanh chóng",
              style: TextStyle(fontSize: 11),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.green,
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateSaleView()),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // SỬA CHỮA
        Card(
          color: Colors.blue.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
            side: BorderSide(color: Colors.blue.shade200),
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.build_circle,
                color: Colors.blue,
                size: 24,
              ),
            ),
            title: const Text(
              "TẠO ĐƠN SỬA CHỮA",
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
            subtitle: const Text(
              "Tiếp nhận máy sửa chữa",
              style: TextStyle(fontSize: 11),
            ),
            trailing: const Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Colors.blue,
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateRepairOrderView(role: widget.role),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),

        // Row: Nhập kho & Kiểm kho
        Row(
          children: [
            Expanded(
              child: Card(
                color: Colors.orange.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.orange.shade200),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FastInventoryInputView()),
                  ),
                  borderRadius: BorderRadius.circular(15),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.inventory,
                            color: Colors.orange,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "NHẬP KHO",
                          style: TextStyle(
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const Text(
                          "Nhập hàng nhanh",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Card(
                color: Colors.purple.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.purple.shade200),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FastInventoryCheckView()),
                  ),
                  borderRadius: BorderRadius.circular(15),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.qr_code_scanner,
                            color: Colors.purple,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "KIỂM KHO",
                          style: TextStyle(
                            color: Colors.purple,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const Text(
                          "Quét mã kiểm tra",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row: Báo cáo & Chấm công
        Row(
          children: [
            Expanded(
              child: Card(
                color: Colors.indigo.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.indigo.shade200),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RevenueView()),
                  ),
                  borderRadius: BorderRadius.circular(15),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.bar_chart,
                            color: Colors.indigo,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "BÁO CÁO",
                          style: TextStyle(
                            color: Colors.indigo,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const Text(
                          "Doanh thu",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Card(
                color: Colors.teal.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.teal.shade200),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AttendanceView()),
                  ),
                  borderRadius: BorderRadius.circular(15),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.access_time,
                            color: Colors.teal,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "CHẤM CÔNG",
                          style: TextStyle(
                            color: Colors.teal,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const Text(
                          "Check in/out",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Row: Chat & Bảo hành
        Row(
          children: [
            Expanded(
              child: Card(
                color: Colors.cyan.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.cyan.shade200),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ChatView()),
                  ),
                  borderRadius: BorderRadius.circular(15),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Stack(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.cyan.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.chat,
                                color: Colors.cyan,
                                size: 28,
                              ),
                            ),
                            if (unreadChatCount > 0)
                              Positioned(
                                right: 0,
                                top: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    unreadChatCount > 9
                                        ? '9+'
                                        : unreadChatCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          "CHAT",
                          style: TextStyle(
                            color: Colors.cyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const Text(
                          "Nhóm shop",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Card(
                color: Colors.amber.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.amber.shade200),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const WarrantyView()),
                  ),
                  borderRadius: BorderRadius.circular(15),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.shield,
                            color: Colors.amber,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          "BẢO HÀNH",
                          style: TextStyle(
                            color: Colors.amber.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const Text(
                          "Tra cứu nhanh",
                          style: TextStyle(fontSize: 10, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _quickActionButton(
                "Tạo đơn bán",
                Icons.add_shopping_cart,
                AppColors.secondary,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateSaleView()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickActionButton(
                "Tạo đơn sửa",
                Icons.build_circle,
                AppColors.primary,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateRepairOrderView(role: widget.role),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _quickActionButton(
                "Nhập kho",
                Icons.inventory,
                AppColors.success,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FastInventoryInputView()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickActionButton(
                "Kiểm kho",
                Icons.qr_code_scanner,
                AppColors.warning,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => FastInventoryCheckView()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _quickActionButton(
                "Báo cáo DT",
                Icons.bar_chart,
                AppColors.primaryDark,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RevenueView()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickActionButton(
                "Chấm công",
                Icons.access_time,
                AppColors.info,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AttendanceView()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _quickActionButton(
                "Chat",
                Icons.chat,
                AppColors.primary,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ChatView()),
                ),
                badgeCount: unreadChatCount,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _quickActionButton(
                "Bảo hành",
                Icons.shield,
                AppColors.warning,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WarrantyView()),
                ),
              ),
            ),
          ],
        ),
        // Removed the row with "Đối tác sửa chữa" as it's now in the Repairs tab
      ],
    );
  }

  Widget _quickActionButton(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    int? badgeCount,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.4)),
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                Icon(icon, color: color, size: 24),
                if (badgeCount != null && badgeCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: AppTextStyles.overline.copyWith(
                          color: AppColors.onError,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: AppTextStyles.caption.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Section
          _buildTabHeader("BÁN HÀNG", Icons.shopping_cart, Colors.green),
          const SizedBox(height: 20),

          // Quick Action - Tạo đơn bán
          _buildSectionHeader("THAO TÁC NHANH"),
          Card(
            color: Colors.green.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: Colors.green.shade200),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.add_shopping_cart,
                  color: Colors.green,
                  size: 28,
                ),
              ),
              title: const Text(
                "TẠO ĐƠN BÁN MỚI",
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                "Tạo đơn bán hàng nhanh chóng",
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.green,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateSaleView()),
              ),
            ),
          ),

          const SizedBox(height: 20),
          _buildSectionHeader("QUẢN LÝ"),
          _tabMenuItem(
            "Danh sách đơn bán",
            Icons.list_alt,
            Colors.blue,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SaleListView()),
            ),
            subtitle: "Xem, tìm kiếm và theo dõi tất cả đơn bán hàng.",
          ),
          _tabMenuItem(
            "Quản lý khách hàng",
            Icons.people,
            Colors.purple,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomerManagementView()),
            ),
            subtitle: "Thêm, sửa và xem thông tin khách hàng.",
          ),
          _tabMenuItem(
            "Bảo hành",
            Icons.verified_user,
            Colors.orange,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WarrantyView()),
            ),
            subtitle: "Xem và xử lý các yêu cầu bảo hành sản phẩm.",
          ),
        ],
      ),
    );
  }

  Widget _buildRepairsTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Section
          _buildTabHeader("SỬA CHỮA", Icons.build, Colors.blue),
          const SizedBox(height: 20),

          // Quick Action - Tạo đơn sửa
          _buildSectionHeader("THAO TÁC NHANH"),
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: Colors.blue.shade200),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.build_circle,
                  color: Colors.blue,
                  size: 28,
                ),
              ),
              title: const Text(
                "TẠO ĐƠN SỬA MỚI",
                style: TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                "Tiếp nhận máy sửa chữa",
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.blue,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateRepairOrderView(role: widget.role),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),
          _buildSectionHeader("QUẢN LÝ"),
          _tabMenuItem(
            "Danh sách đơn sửa",
            Icons.list_alt,
            Colors.indigo,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderListView(role: widget.role),
              ),
            ),
            subtitle: "Xem, tìm kiếm và theo dõi tất cả đơn sửa chữa.",
          ),
          _tabMenuItem(
            "Kho phụ tùng",
            Icons.build,
            Colors.orange,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PartsInventoryView()),
            ),
            subtitle: "Quản lý tồn kho phụ tùng cho sửa chữa.",
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Section
          _buildTabHeader("QUẢN LÝ KHO", Icons.inventory_2, Colors.orange),
          const SizedBox(height: 20),

          // Quick Actions
          _buildSectionHeader("THAO TÁC NHANH"),
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.orange.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.orange.shade200),
                  ),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FastInventoryInputView(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(15),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.flash_on,
                              color: Colors.orange,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "NHẬP KHO",
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const Text(
                            "Siêu tốc",
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Card(
                  color: Colors.purple.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.purple.shade200),
                  ),
                  child: InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FastInventoryCheckView(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(15),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.purple.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner,
                              color: Colors.purple,
                              size: 28,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "KIỂM KHO",
                            style: TextStyle(
                              color: Colors.purple,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const Text(
                            "Quét QR",
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          _buildSectionHeader("QUẢN LÝ"),
          _tabMenuItem(
            "Danh sách sản phẩm",
            Icons.inventory,
            Colors.blue,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InventoryView(role: widget.role),
              ),
            ),
            subtitle: "Xem và quản lý danh sách sản phẩm trong kho.",
          ),
          _tabMenuItem(
            "Nhà cung cấp - Đối tác",
            Icons.business_center,
            Colors.teal,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupplierListView()),
            ),
            subtitle: "Quản lý NCC, đối tác sửa chữa và công nợ.",
          ),
          _tabMenuItem(
            "Danh sách mã nhập nhanh",
            Icons.qr_code,
            Colors.indigo,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QuickInputCodesView()),
            ),
            subtitle: "Xem và quản lý danh sách mã nhập nhanh đã tạo.",
          ),
        ],
      ),
    );
  }

  Widget _buildStaffTab() {
    if (!hasFullAccess) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_person, size: 64, color: Colors.orange.shade300),
              const SizedBox(height: 16),
              const Text(
                "Không có quyền truy cập",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                "Liên hệ chủ shop để được cấp quyền",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Section
          _buildTabHeader("QUẢN LÝ NHÂN SỰ", Icons.people, Colors.teal),
          const SizedBox(height: 20),

          // Quick Action - Chấm công
          _buildSectionHeader("THAO TÁC NHANH"),
          Card(
            color: Colors.teal.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: BorderSide(color: Colors.teal.shade200),
            ),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.fingerprint,
                  color: Colors.teal,
                  size: 28,
                ),
              ),
              title: const Text(
                "CHẤM CÔNG",
                style: TextStyle(
                  color: Colors.teal,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: const Text(
                "Ghi nhận giờ làm việc",
                style: TextStyle(fontSize: 11),
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: Colors.teal,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AttendanceView()),
              ),
            ),
          ),

          const SizedBox(height: 20),
          _buildSectionHeader("QUẢN LÝ"),
          _tabMenuItem(
            "Danh sách nhân viên",
            Icons.people,
            Colors.blue,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaffListView()),
            ),
            subtitle: "Xem và quản lý thông tin nhân viên.",
          ),
          _tabMenuItem(
            "Hiệu suất làm việc",
            Icons.bar_chart,
            Colors.orange,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaffPerformanceView()),
            ),
            subtitle: "Xem báo cáo hiệu suất làm việc của nhân viên.",
          ),
          _tabMenuItem(
            "Lịch làm việc",
            Icons.schedule,
            Colors.purple,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => WorkScheduleSettingsView()),
            ),
            subtitle: "Thiết lập và xem lịch làm việc của nhân viên.",
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: () => _syncNow(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header Section
            _buildTabHeader(
              "QUẢN LÝ TÀI CHÍNH",
              Icons.account_balance_wallet,
              Colors.indigo,
            ),
            const SizedBox(height: 20),

            // Financial Overview Cards
            _buildSectionHeader("TỔNG QUAN HÔM NAY"),
            _financeOverviewSection(),

            const SizedBox(height: 20),
            _buildSectionHeader("CHỨC NĂNG"),
            _tabMenuItem(
              "Báo cáo doanh thu",
              Icons.trending_up,
              Colors.green,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RevenueView()),
              ),
              subtitle: "Xem báo cáo doanh thu và lợi nhuận theo thời gian.",
            ),
            _tabMenuItem(
              "Quản lý chi phí",
              Icons.money_off,
              Colors.red,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpenseView()),
              ),
              subtitle: "Thêm và theo dõi các khoản chi phí của cửa hàng.",
            ),
            _tabMenuItem(
              "Công nợ",
              Icons.receipt_long,
              Colors.orange,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebtView()),
              ),
              subtitle: "Quản lý các khoản nợ và thu nợ từ khách hàng.",
            ),
            _tabMenuItem(
              "Phân tích nợ",
              Icons.analytics,
              Colors.purple,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebtAnalysisView()),
              ),
              subtitle: "Phân tích chi tiết các khoản nợ và thống kê.",
            ),
          ],
        ),
      ),
    );
  }

  /// Tab Header đẹp với gradient
  Widget _buildTabHeader(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEEE, dd/MM/yyyy', 'vi').format(DateTime.now()),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Finance Overview Section with modern cards
  Widget _financeOverviewSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // THU và CHI row
          Row(
            children: [
              Expanded(
                child: _financeStatCard(
                  icon: Icons.arrow_circle_down_rounded,
                  label: "THU HÔM NAY",
                  value: _todayTotalIn,
                  color: AppColors.success,
                  detail:
                      "${_todaySaleOrderCount} bán + ${_todayRepairCount} sửa",
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _financeStatCard(
                  icon: Icons.arrow_circle_up_rounded,
                  label: "CHI HÔM NAY",
                  value: _todayTotalOut,
                  color: AppColors.error,
                  detail: "$_todayExpenseCount khoản chi",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ExpenseView()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // LỢI NHUẬN RÒNG
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _todayNetProfit >= 0
                    ? [const Color(0xFF00C853), const Color(0xFF69F0AE)]
                    : [const Color(0xFFFF5252), const Color(0xFFFF8A80)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: (_todayNetProfit >= 0 ? Colors.green : Colors.red)
                      .withOpacity(0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    _todayNetProfit >= 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "LỢI NHUẬN RÒNG HÔM NAY",
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${MoneyUtils.formatVND(_todayNetProfit)} đ",
                        style: AppTextStyles.headline5.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Công nợ
          InkWell(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DebtView()),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.warning.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.receipt_long_rounded,
                    color: AppColors.warning,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "TỔNG CÔNG NỢ",
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          "${MoneyUtils.formatVND(totalDebtRemain)} đ",
                          style: AppTextStyles.headline6.copyWith(
                            color: AppColors.warning,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: AppColors.warning.withOpacity(0.6),
                    size: 16,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Finance stat card for the overview section
  Widget _financeStatCard({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    String? detail,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.overline.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios,
                    color: color.withOpacity(0.5),
                    size: 12,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "${MoneyUtils.formatVND(value)} đ",
              style: AppTextStyles.body1.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail,
                style: AppTextStyles.overline.copyWith(
                  color: AppColors.onSurface.withOpacity(0.5),
                  fontSize: 9,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            "CÀI ĐẶT HỆ THỐNG",
            style: AppTextStyles.headline5.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 20),
          // SYNC HEALTH STATUS CARD
          _buildSyncHealthStatusCard(),
          const SizedBox(height: 10),
          _tabMenuItem(
            "Thông báo",
            Icons.notifications,
            AppColors.primary,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationSettingsView(),
              ),
            ),
            subtitle: "Cấu hình cài đặt thông báo và cảnh báo.",
          ),
          _tabMenuItem(
            "Máy in",
            Icons.print,
            AppColors.success,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const ThermalPrinterDesignView(),
              ),
            ),
            subtitle: "Thiết kế mẫu in cho máy in nhiệt.",
          ),
          _tabMenuItem(
            "Tìm kiếm toàn cục",
            Icons.search,
            AppColors.warning,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GlobalSearchView(role: widget.role),
              ),
            ),
            subtitle: "Tìm kiếm thông tin trên toàn bộ ứng dụng.",
          ),
          if (hasFullAccess)
            _tabMenuItem(
              "Cài đặt hệ thống",
              Icons.settings,
              AppColors.onSurface.withOpacity(0.6),
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SettingsView(setLocale: widget.setLocale),
                ),
              ),
              subtitle: "Thay đổi cài đặt chung của ứng dụng.",
            ),
          if (_isSuperAdmin)
            _tabMenuItem(
              "Trung tâm Admin",
              Icons.admin_panel_settings,
              AppColors.error,
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const admin_view.SuperAdminView(),
                ),
              ),
              subtitle: "Quản lý toàn bộ hệ thống cho admin cấp cao.",
            ),
          if (hasFullAccess)
            _tabMenuItem(
              "Nhật ký hệ thống",
              Icons.history,
              AppColors.info,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AuditLogView()),
              ),
              subtitle: "Xem lịch sử hoạt động và thay đổi trong hệ thống.",
            ),
          _tabMenuItem(
            "Về nhà phát triển",
            Icons.info,
            AppColors.secondary,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutDeveloperView()),
            ),
            subtitle: "Thông tin về nhà phát triển và ứng dụng.",
          ),
        ],
      ),
    );
  }

  /// Widget hiển thị trạng thái sync health
  Widget _buildSyncHealthStatusCard() {
    return ValueListenableBuilder<bool?>(
      valueListenable: syncHealthNotifier,
      builder: (context, isHealthy, _) {
        return ValueListenableBuilder<int>(
          valueListenable: syncMismatchCountNotifier,
          builder: (context, mismatchCount, _) {
            // Chưa kiểm tra
            if (isHealthy == null) {
              return Card(
                color: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: const ListTile(
                  leading: SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text(
                    "Đang kiểm tra đồng bộ...",
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    "Kiểm tra dữ liệu local vs cloud",
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              );
            }

            // Healthy
            if (isHealthy) {
              return Card(
                color: Colors.green.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: Colors.green.shade200),
                ),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 22,
                    ),
                  ),
                  title: const Text(
                    "✅ Dữ liệu đồng bộ hoàn toàn",
                    style: TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  subtitle: const Text(
                    "Local và Cloud đã khớp 100%",
                    style: TextStyle(fontSize: 10),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.green),
                    onPressed: () {
                      SyncHealthCheck.runFullCheck();
                      NotificationService.showSnackBar(
                        "🔄 Đang kiểm tra lại...",
                        color: Colors.blue,
                      );
                    },
                  ),
                ),
              );
            }

            // Has issues
            return Card(
              color: Colors.red.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
                side: BorderSide(color: Colors.red.shade200),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Badge(
                    label: Text(
                      '$mismatchCount',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    backgroundColor: Colors.red,
                    child: const Icon(
                      Icons.warning,
                      color: Colors.red,
                      size: 22,
                    ),
                  ),
                ),
                title: const Text(
                  "⚠️ Cần đồng bộ dữ liệu",
                  style: TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  "$mismatchCount bản ghi chưa đồng bộ. Vào Cài đặt để sửa.",
                  style: const TextStyle(fontSize: 10, color: Colors.red),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.red,
                    size: 16,
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            SettingsView(setLocale: widget.setLocale),
                      ),
                    );
                  },
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SettingsView(setLocale: widget.setLocale),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _tabMenuItem(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    String? subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: color.withOpacity(0.05),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              )
            : null,
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: color.withOpacity(0.5),
          size: 16,
        ),
        onTap: onTap,
      ),
    );
  }

  String _getTabTitle(int index) {
    if (index < _tabWidgets.length) {
      // Get the corresponding config from the original configs
      final availableConfigs = _tabConfigs.where((config) {
        final permission = config['permission'] as String?;
        return permission == null || (_permissions[permission] == true);
      }).toList();

      if (index < availableConfigs.length) {
        final item = availableConfigs[index]['item'] as BottomNavigationBarItem;
        return item.label?.toUpperCase() ?? 'TAB';
      }
    }
    return "SHOP MANAGER";
  }

  Widget _buildDashboardOverview() {
    debugPrint(
      'BUILDING DASHBOARD: totalPendingRepair=$totalPendingRepair, _todayTotalIn=$_todayTotalIn, _todayTotalOut=$_todayTotalOut, _todayNetProfit=$_todayNetProfit',
    );

    return Container(
      key: UniqueKey(),
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header Section
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.analytics_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "BÁO CÁO TÀI CHÍNH HÔM NAY",
                        style: AppTextStyles.body1.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        DateFormat(
                          'EEEE, dd/MM/yyyy',
                          'vi',
                        ).format(DateTime.now()),
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RevenueView()),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Chi tiết",
                          style: AppTextStyles.caption.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: 12,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Main Finance Overview (THU - CHI - LỢI NHUẬN)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // THU và CHI row
                Row(
                  children: [
                    Expanded(
                      child: _financeMetricCard(
                        icon: Icons.arrow_downward_rounded,
                        label: "THU HÔM NAY",
                        value: _todayTotalIn,
                        color: AppColors.success,
                        subLabel:
                            "${_todaySaleOrderCount} đơn bán + ${_todayRepairCount} đơn sửa",
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _financeMetricCard(
                        icon: Icons.arrow_upward_rounded,
                        label: "CHI HÔM NAY",
                        value: _todayTotalOut,
                        color: AppColors.error,
                        subLabel: "$_todayExpenseCount khoản chi",
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ExpenseView(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // LỢI NHUẬN RÒNG - Large Card
                _profitCard(_todayNetProfit),

                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 16),

                // Quick Stats Grid
                Text(
                  "HOẠT ĐỘNG HÔM NAY",
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface.withOpacity(0.5),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: _activityCard(
                        icon: Icons.build_circle,
                        label: "Đơn sửa chờ",
                        value: totalPendingRepair.toString(),
                        color: AppColors.primary,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderListView(
                              role: widget.role,
                              statusFilter: const [1, 2],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _activityCard(
                        icon: Icons.check_circle,
                        label: "Đã giao",
                        value: todayRepairDone.toString(),
                        color: AppColors.info,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderListView(
                              role: widget.role,
                              statusFilter: const [4],
                              todayOnly: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _activityCard(
                        icon: Icons.shopping_cart,
                        label: "Đơn bán",
                        value: todaySaleCount.toString(),
                        color: AppColors.success,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SaleListView(todayOnly: true),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _activityCard(
                        icon: Icons.receipt_long,
                        label: "Công nợ",
                        value: MoneyUtils.formatCompact(totalDebtRemain),
                        color: AppColors.warning,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const DebtView()),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Professional finance metric card
  Widget _financeMetricCard({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
    String? subLabel,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.caption.copyWith(
                      color: color.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios,
                    color: color.withOpacity(0.4),
                    size: 10,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "${MoneyUtils.formatVND(value)} đ",
              style: AppTextStyles.body1.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (subLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                subLabel,
                style: AppTextStyles.overline.copyWith(
                  color: AppColors.onSurface.withOpacity(0.5),
                  fontSize: 9,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Profit card with gradient
  Widget _profitCard(int profit) {
    final isPositive = profit >= 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPositive
              ? [const Color(0xFF00C853), const Color(0xFF69F0AE)]
              : [const Color(0xFFFF5252), const Color(0xFFFF8A80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isPositive ? Colors.green : Colors.red).withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isPositive
                    ? Icons.trending_up_rounded
                    : Icons.trending_down_rounded,
                color: Colors.white.withOpacity(0.9),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                "LỢI NHUẬN RÒNG HÔM NAY",
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "${MoneyUtils.formatVND(profit)} đ",
            style: AppTextStyles.headline5.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "= Thu - Chi - Giá vốn",
            style: AppTextStyles.overline.copyWith(
              color: Colors.white70,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  // Activity card for quick stats
  Widget _activityCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTextStyles.body1.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: AppTextStyles.overline.copyWith(
                color: AppColors.onSurface.withOpacity(0.6),
                fontSize: 9,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlerts() {
    if (expiringWarranties == 0) return const SizedBox();
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const WarrantyView()),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error,
          borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius * 2),
          boxShadow: [
            BoxShadow(color: AppColors.error.withOpacity(0.3), blurRadius: 10),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.notification_important,
              color: AppColors.onError,
              size: 28,
            ),
            const SizedBox(height: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "NHẮC LỊCH BẢO HÀNH",
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.onError,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Có $expiringWarranties máy sắp hết hạn bảo hành. Xem ngay!",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.onError.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: AppColors.onError, size: 16),
          ],
        ),
      ),
    );
  }
}
