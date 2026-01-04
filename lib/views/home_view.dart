import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  }

  void _initializeTabConfigs() {
    _tabConfigs = [
      {
        'permission': null, // Home always accessible
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: 'Home',
        ),
        'widget': _buildHomeTab(),
      },
      {
        'permission': 'allowViewSales',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.shopping_cart),
          label: 'Bán hàng',
        ),
        'widget': _buildSalesTab(),
      },
      {
        'permission': 'allowViewRepairs',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.build),
          label: 'Sửa chữa',
        ),
        'widget': _buildRepairsTab(),
      },
      {
        'permission': 'allowViewInventory',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.inventory),
          label: 'Kho',
        ),
        'widget': _buildInventoryTab(),
      },
      {
        'permission':
            'allowManageStaff', // Staff tab requires manage staff permission
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.people),
          label: 'Nhân sự',
        ),
        'widget': _buildStaffTab(),
      },
      {
        'permission':
            'allowViewRevenue', // Finance tab requires revenue permission
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.account_balance_wallet),
          label: 'Tài chính',
        ),
        'widget': _buildFinanceTab(),
      },
      {
        'permission': 'allowViewSettings',
        'item': const BottomNavigationBarItem(
          icon: Icon(Icons.settings),
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

  void _updateAvailableTabs() {
    debugPrint(
      'HomeView: _updateAvailableTabs called, _tabConfigs.length = ${_tabConfigs.length}',
    );
    debugPrint('HomeView: _permissions = $_permissions');
    final availableConfigs = _tabConfigs.where((config) {
      final permission = config['permission'] as String?;
      final hasPermission =
          permission == null || (_permissions[permission] == true);
      debugPrint(
        'HomeView: Tab ${config['item'].label} permission=$permission, hasPermission=$hasPermission',
      );
      return hasPermission;
    }).toList();

    // Limit to 7 tabs max for BottomNavigationBar compatibility
    if (availableConfigs.length > 7) {
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
      final prioritized = availableConfigs
          .where((config) => priorityTabs.contains(config['item'].label))
          .toList();
      final remaining = availableConfigs
          .where((config) => !priorityTabs.contains(config['item'].label))
          .toList();
      availableConfigs.clear();
      availableConfigs.addAll(prioritized);
      availableConfigs.addAll(remaining.take(7 - prioritized.length));
    }

    _navItems = availableConfigs
        .map((config) => config['item'] as BottomNavigationBarItem)
        .toList();
    _tabWidgets = availableConfigs
        .map((config) => config['widget'] as Widget)
        .toList();

    debugPrint(
      'HomeView: Available tabs after limit: ${availableConfigs.length}',
    );
    debugPrint(
      'HomeView: Available tab names: ${availableConfigs.map((c) => c['item'].label)}',
    );

    // Adjust current index if it's out of bounds
    if (_currentIndex >= _navItems.length) {
      _currentIndex = 0;
    }
  }

  /// Rebuild all tab widgets to reflect updated state variables
  /// This is necessary because IndexedStack caches child widgets
  void _rebuildTabWidgets() {
    debugPrint('HomeView: _rebuildTabWidgets called - rebuilding all tabs with fresh data');
    // Rebuild tab configs with current data values
    _tabConfigs = [
      {
        'permission': null,
        'item': const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
        'widget': _buildHomeTab(),
      },
      {
        'permission': 'allowViewSales',
        'item': const BottomNavigationBarItem(icon: Icon(Icons.shopping_cart), label: 'Bán hàng'),
        'widget': _buildSalesTab(),
      },
      {
        'permission': 'allowViewRepairs',
        'item': const BottomNavigationBarItem(icon: Icon(Icons.build), label: 'Sửa chữa'),
        'widget': _buildRepairsTab(),
      },
      {
        'permission': 'allowViewInventory',
        'item': const BottomNavigationBarItem(icon: Icon(Icons.inventory), label: 'Kho'),
        'widget': _buildInventoryTab(),
      },
      {
        'permission': 'allowManageStaff',
        'item': const BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Nhân sự'),
        'widget': _buildStaffTab(),
      },
      {
        'permission': 'allowManageFinance',
        'item': const BottomNavigationBarItem(icon: Icon(Icons.attach_money), label: 'Tài chính'),
        'widget': _buildFinanceTab(),
      },
      {
        'permission': 'allowViewSettings',
        'item': const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Cài đặt'),
        'widget': _buildSettingsTab(),
      },
    ];
    
    // Re-apply permissions filter
    final availableConfigs = _tabConfigs.where((config) {
      final permission = config['permission'] as String?;
      return permission == null || (_permissions[permission] == true);
    }).toList();
    
    // Limit to 7 tabs max
    if (availableConfigs.length > 7) {
      final priorityTabs = ['Home', 'Bán hàng', 'Sửa chữa', 'Kho', 'Nhân sự', 'Tài chính', 'Cài đặt'];
      final prioritized = availableConfigs.where((config) => priorityTabs.contains(config['item'].label)).toList();
      final remaining = availableConfigs.where((config) => !priorityTabs.contains(config['item'].label)).toList();
      availableConfigs.clear();
      availableConfigs.addAll(prioritized);
      availableConfigs.addAll(remaining.take(7 - prioritized.length));
    }
    
    _navItems = availableConfigs.map((config) => config['item'] as BottomNavigationBarItem).toList();
    _tabWidgets = availableConfigs.map((config) => config['widget'] as Widget).toList();
    
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
      final prefs = await SharedPreferences.getInstance();
      final currentUser = FirebaseAuth.instance.currentUser;
      final lastUserId = prefs.getString('lastUserId');
      if (currentUser != null && currentUser.uid != lastUserId) {
        await db.clearAllData();
        await prefs.setString('lastUserId', currentUser.uid);
        if (currentUser.email != null)
          await UserService.syncUserInfo(currentUser.uid, currentUser.email!);
      }
      await db.cleanDuplicateData();
      
      // QUAN TRỌNG: Sync với Firebase TRƯỚC KHI load stats
      // để đảm bảo data hiển thị giống như trong Quản lý tài chính
      debugPrint('HomeView: Syncing with Firebase before loading stats...');
      try {
        await SyncService.downloadAllFromCloud();
        debugPrint('HomeView: Sync completed successfully');
      } catch (syncError) {
        debugPrint('HomeView: Sync failed, using local data: $syncError');
      }
      
      debugPrint('About to call _loadStats in initState');
      await _loadStats();
      debugPrint('After _loadStats in initState');
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
        _permissions = perms.map((key, value) => MapEntry(key, value == true));
        _updateAvailableTabs();
      });
      debugPrint('HomeView permissions updated: $_permissions');
      debugPrint('allowViewSettings: ${_permissions['allowViewSettings']}');
    } catch (e) {
      debugPrint('Error updating permissions: $e');
      if (!mounted) return;
      setState(() {
        _permissions = {'allowViewSettings': true}; // Minimal permissions
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
    final repairs = await db.getAllRepairs();
    final sales = await db.getAllSales();
    final debts = await db.getAllDebts();
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
                  color: _notificationWorking ? AppColors.success : AppColors.secondary,
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
            : BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) => setState(() => _currentIndex = index),
                items: _navItems,
                type: BottomNavigationBarType.fixed,
                selectedItemColor: AppColors.primary,
                unselectedItemColor: AppColors.onSurface.withOpacity(0.6),
                showUnselectedLabels: true,
                backgroundColor: AppColors.surface,
                elevation: 8,
                selectedIconTheme: const IconThemeData(size: 28),
                unselectedIconTheme: const IconThemeData(size: 24),
                selectedLabelStyle: AppTextStyles.button.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                unselectedLabelStyle: AppTextStyles.caption,
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_shopLocked)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  border: Border.all(color: AppColors.error),
                  borderRadius: BorderRadius.circular(
                    AppButtonStyles.borderRadius,
                  ),
                ),
                child: Text(
                  "CỬA HÀNG BỊ KHÓA",
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            _buildDashboardOverview(),
            const SizedBox(height: 20),
            _buildQuickActions(),
            const SizedBox(height: 20),
            const PerpetualCalendar(),
            const SizedBox(height: 25),
            _buildAlerts(),
            const SizedBox(height: 50),
          ],
        ),
      ),
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
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            "BÁN HÀNG",
            style: AppTextStyles.headline5.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 20),
          _tabMenuItem(
            "Danh sách đơn bán",
            Icons.list_alt,
            AppColors.primary,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SaleListView()),
            ),
            subtitle: "Xem, tìm kiếm và theo dõi tất cả đơn bán hàng.",
          ),
          _tabMenuItem(
            "Tạo đơn bán mới",
            Icons.add_circle,
            AppColors.success,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateSaleView()),
            ),
            subtitle: "Tạo đơn bán hàng mới với sản phẩm và thông tin khách.",
          ),
          _tabMenuItem(
            "Quản lý khách hàng",
            Icons.people,
            AppColors.secondary,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CustomerManagementView(),
              ),
            ),
            subtitle: "Thêm, sửa và xem thông tin khách hàng.",
          ),
          _tabMenuItem(
            "Bảo hành",
            Icons.verified_user,
            AppColors.info,
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
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            "SỬA CHỮA",
            style: AppTextStyles.headline5.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 20),
          // Quick Actions for Repairs
          Row(
            children: [
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
          const SizedBox(height: 20),
          _tabMenuItem(
            "Danh sách đơn sửa",
            Icons.list_alt,
            AppColors.primary,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderListView(role: widget.role),
              ),
            ),
            subtitle: "Xem, tìm kiếm và theo dõi tất cả đơn sửa chữa.",
          ),
          _tabMenuItem(
            "Tạo đơn sửa mới",
            Icons.add_circle,
            AppColors.success,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateRepairOrderView(role: widget.role),
              ),
            ),
            subtitle: "Tạo đơn sửa chữa mới với thông tin máy và khách.",
          ),
          _tabMenuItem(
            "Kho phụ tùng",
            Icons.build,
            AppColors.warning,
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
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            "QUẢN LÝ KHO",
            style: AppTextStyles.headline5.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 20),
          _tabMenuItem(
            "Danh sách sản phẩm",
            Icons.inventory,
            AppColors.primary,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => InventoryView(role: widget.role),
              ),
            ),
            subtitle: "Xem và quản lý danh sách sản phẩm trong kho.",
          ),
          _tabMenuItem(
            "Nhà cung cấp - Đối tác sửa chữa",
            Icons.business_center,
            AppColors.secondary,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupplierListView()),
            ),
            subtitle: "Quản lý NCC- Đối tác sửa chữa, công nợ và lịch sử nhập.",
          ),
          _tabMenuItem(
            "Nhập kho siêu tốc",
            Icons.flash_on,
            AppColors.warning,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FastInventoryInputView()),
            ),
            subtitle: "Nhập nhiều sản phẩm vào kho nhanh bằng mã QR.",
          ),
          _tabMenuItem(
            "Danh sách mã nhập nhanh",
            Icons.qr_code,
            AppColors.info,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QuickInputCodesView()),
            ),
            subtitle: "Xem và quản lý danh sách mã nhập nhanh đã tạo.",
          ),
          _tabMenuItem(
            "Kiểm kho QR",
            Icons.qr_code_scanner,
            AppColors.secondary,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FastInventoryCheckView()),
            ),
            subtitle: "Kiểm tra tồn kho bằng cách quét mã QR.",
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
          child: Text("Không có quyền truy cập", style: AppTextStyles.body1),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            "QUẢN LÝ NHÂN SỰ",
            style: AppTextStyles.headline5.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 20),
          _tabMenuItem(
            "Danh sách nhân viên",
            Icons.people,
            AppColors.primary,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaffListView()),
            ),
            subtitle: "Xem và quản lý thông tin nhân viên.",
          ),
          _tabMenuItem(
            "Chấm công",
            Icons.fingerprint,
            AppColors.success,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AttendanceView()),
            ),
            subtitle: "Ghi nhận giờ làm việc của nhân viên.",
          ),
          _tabMenuItem(
            "Hiệu suất",
            Icons.bar_chart,
            AppColors.warning,
            () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const StaffPerformanceView()),
            ),
            subtitle: "Xem báo cáo hiệu suất làm việc của nhân viên.",
          ),
          _tabMenuItem(
            "Lịch làm việc",
            Icons.schedule,
            AppColors.secondary,
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
          padding: const EdgeInsets.all(20),
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet_rounded,
                  color: AppColors.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "QUẢN LÝ TÀI CHÍNH",
                        style: AppTextStyles.headline5.copyWith(
                          color: AppColors.onSurface,
                        ),
                      ),
                      Text(
                        DateFormat(
                          'EEEE, dd/MM/yyyy',
                          'vi',
                        ).format(DateTime.now()),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Financial Overview Cards
            _financeOverviewSection(),

            const SizedBox(height: 24),

            // Quick Actions Section
            Text(
              "CHỨC NĂNG",
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface.withOpacity(0.5),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),

            _tabMenuItem(
              "Báo cáo doanh thu",
              Icons.trending_up,
              AppColors.primary,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const RevenueView()),
              ),
              subtitle: "Xem báo cáo doanh thu và lợi nhuận theo thời gian.",
            ),
            _tabMenuItem(
              "Quản lý chi phí",
              Icons.money_off,
              AppColors.error,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ExpenseView()),
              ),
              subtitle: "Thêm và theo dõi các khoản chi phí của cửa hàng.",
            ),
            _tabMenuItem(
              "Công nợ",
              Icons.receipt_long,
              AppColors.secondary,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebtView()),
              ),
              subtitle: "Quản lý các khoản nợ và thu nợ từ khách hàng.",
            ),
            _tabMenuItem(
              "Phân tích nợ",
              Icons.analytics,
              AppColors.warning,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DebtAnalysisView()),
              ),
              subtitle:
                  "Phân tích chi tiết các khoản nợ và thống kê.",
            ),
          ],
        ),
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
                  Icon(Icons.arrow_forward_ios, color: color.withOpacity(0.5), size: 12),
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

  Widget _tabMenuItem(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    String? subtitle,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppButtonStyles.borderRadius),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: AppTextStyles.body1.copyWith(color: AppColors.onSurface),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.onSurface.withOpacity(0.6),
                ),
              )
            : null,
        trailing: Icon(
          Icons.chevron_right,
          color: AppColors.onSurface.withOpacity(0.4),
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
                          MaterialPageRoute(builder: (_) => const ExpenseView()),
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
                  Icon(Icons.arrow_forward_ios, color: color.withOpacity(0.4), size: 10),
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
