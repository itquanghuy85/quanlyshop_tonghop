import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/utils/money_utils.dart';
import '../utils/money_utils.dart' as input_money;
import '../l10n/app_localizations.dart';
import '../services/event_bus.dart';
import '../services/current_shop_service.dart';
import 'order_list_view.dart';
import 'revenue_view.dart';
import 'monthly_profit_report_view.dart';
import 'inventory_view.dart';
import 'fast_inventory_input_view.dart';
import 'fast_inventory_check_view.dart';
import 'supplier_list_view.dart';
import 'quick_input_codes_view.dart';
import 'sale_list_view.dart';
import 'sales_return_list_view.dart';
import 'expense_view.dart';
import 'debt_view.dart';
import 'warranty_view.dart';
import 'shop_settings_view.dart';
import 'advanced_chat_view.dart';
import 'printer_settings_view.dart';
import 'super_admin_view.dart' as admin_view;
import 'staff_list_view.dart';
import 'qr_scan_view.dart';
import 'attendance_view.dart';
import 'attendance_management_view.dart';
import 'staff_performance_view.dart';
import 'notifications_view.dart';
import 'notification_settings_view.dart';
import 'global_search_view.dart';
import 'work_schedule_settings_view.dart';
import 'create_sale_view.dart';
import 'customer_management_view.dart';
import 'create_repair_order_view.dart';
import 'about_developer_view.dart';
import 'cash_closing_view.dart';
import 'bank_installment_report_view.dart';
import 'parts_inventory_view.dart';
import 'salvage_phone_view.dart';
import 'financial_report_view.dart';
import 'audit_log_view.dart';
import 'recent_activity_view.dart';
import 'firestore_connectivity_test_view.dart';
import 'firebase_rw_stats_view.dart';
import 'hr_salary_settings_view.dart';
import 'smart_stock_in_view.dart';
import 'pending_stock_list_view.dart';
import 'import_history_view.dart';
import 'user_guide_view.dart';
import '../data/db_helper.dart';
import '../widgets/pending_stock_widget.dart';
import '../widgets/unified_sync_button.dart';
import '../widgets/notification_badge.dart';
import '../widgets/simple_sync_indicator.dart';
import '../widgets/shop_switcher_widget.dart';
import '../widgets/custom_app_bar.dart';
import '../services/sync_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/sync_health_check.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/encryption_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import '../services/category_service.dart';
import '../services/expiry_alert_service.dart';
import '../services/variant_service.dart';
import '../services/business_type_helper.dart';
import '../services/debt_summary_service.dart';
import '../services/payment_intent_service.dart';
import '../services/adjustment_service.dart';
import '../services/daily_financial_analysis_service.dart';
import '../models/shop_settings_model.dart';
import '../models/payment_intent_model.dart';
import '../models/repair_model.dart';
import '../models/product_model.dart';
import '../models/sale_order_model.dart';
import '../models/expense_model.dart';
import '../models/debt_model.dart';
import '../constants/financial_constants.dart';
import '../widgets/currency_text_field.dart';
import 'food/expiry_management_view.dart';
import 'fashion/variant_management_view.dart';
import 'onboarding/business_type_wizard.dart';
import 'dashboard_settings_view.dart';
import 'payment_request_chat_view.dart';
import 'daily_activity_report_view.dart';
import 'reminders_view.dart';
import '../services/test_data_service.dart';
import '../services/social_auth_service.dart';
import '../services/reminder_service.dart';
import '../services/dashboard_config_service.dart';
import '../widgets/dashboard_cards.dart';
import '../widgets/responsive_wrapper.dart';

class HomeView extends StatefulWidget {
  final String role;
  final void Function(Locale)? setLocale;

  const HomeView({super.key, required this.role, this.setLocale});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeShopReadScope {
  final String? shopId;

  const _HomeShopReadScope(this.shopId);

  bool get hasScopedShop => shopId != null && shopId!.isNotEmpty;

  String where(String baseWhere, {bool includeLegacyNull = true}) {
    if (!hasScopedShop) return baseWhere;
    final legacyClause = includeLegacyNull ? ' OR shopId IS NULL' : '';
    return '($baseWhere) AND (shopId = ?$legacyClause)';
  }

  List<Object?> args(List<Object?> baseArgs, {bool includeLegacyNull = true}) {
    if (!hasScopedShop) return baseArgs;
    return [...baseArgs, shopId];
  }

  String get coreRecordCountSql {
    if (hasScopedShop) {
      return 'SELECT '
          '(SELECT COUNT(*) FROM repairs WHERE shopId = ? OR shopId IS NULL) + '
          '(SELECT COUNT(*) FROM sales WHERE shopId = ? OR shopId IS NULL) + '
          '(SELECT COUNT(*) FROM products WHERE shopId = ? OR shopId IS NULL) '
          'AS total';
    }
    return 'SELECT '
        '(SELECT COUNT(*) FROM repairs) + '
        '(SELECT COUNT(*) FROM sales) + '
        '(SELECT COUNT(*) FROM products) '
        'AS total';
  }

  List<Object?> get coreRecordCountArgs {
    if (!hasScopedShop) return const [];
    return [shopId, shopId, shopId];
  }

  String get breakdownRecordCountSql {
    if (hasScopedShop) {
      return 'SELECT '
          '(SELECT COUNT(*) FROM repairs WHERE shopId = ? OR shopId IS NULL) as repairs, '
          '(SELECT COUNT(*) FROM sales WHERE shopId = ? OR shopId IS NULL) as sales, '
          '(SELECT COUNT(*) FROM products WHERE shopId = ? OR shopId IS NULL) as products';
    }
    return 'SELECT '
        '(SELECT COUNT(*) FROM repairs) as repairs, '
        '(SELECT COUNT(*) FROM sales) as sales, '
        '(SELECT COUNT(*) FROM products) as products';
  }

  List<Object?> get breakdownRecordCountArgs => coreRecordCountArgs;
}

class _HomeViewState extends State<HomeView>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _lastTabIndexPrefKey = 'home_last_tab_index_v1';
  static const String _lastTabIdPrefKey = 'home_last_tab_id_v1';
  static const String _homeTabId = 'home';
  static const String _financeTabId = 'finance';

  final db = DBHelper();
  final _debtSummaryService = DebtSummaryService();
  int totalPendingRepair = 0;
  int todaySaleCount = 0;
  int _currentIndex = 0; // Bottom navigation index
  int? _restoredTabIndex;
  String? _restoredTabId;
  final Map<String, GlobalKey<NavigatorState>> _tabNavigatorKeys = {};
  final Map<String, int> _tabHostVersions = {};

  /// Getter for localization - dùng chung cho tất cả methods
  AppLocalizations get loc => AppLocalizations.of(context)!;

  _HomeViewState() {
    debugPrint('HomeView: _HomeViewState constructor called');
  }

  @override
  void initState() {
    super.initState();
    _primePermissionsFromCache();
    WidgetsBinding.instance.addObserver(
      this,
    ); // Lifecycle observer for iOS background handling
    _loadSavedTabIndex();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotificationStatus();
      _initialSetup();
      SyncService.initRealTimeSync(() {
        _debouncedLoadStats();
        _debouncedLoadDebtOverview();
      });

      _eventBusSub = EventBus().stream.listen((event) {
        debugPrint('HomeView: Received event: $event');
        if ((event == 'debts_changed' ||
                event == 'debt_payments_changed' ||
                event == 'repair_partners_changed' ||
                event == 'repair_partner_payments_changed' ||
                event == 'sales_changed' ||
                event == EventBus.repairsChanged ||
                event == 'expenses_changed' ||
                event == 'products_changed' ||
                event == 'sales_returns_changed' ||
                event == EventBus.financialChanged) &&
            mounted) {
          debugPrint('HomeView: Loading stats for event: $event');
          _debouncedLoadStats();
          _debouncedLoadDebtOverview();
        }

        if ((event == 'users_changed' || event == 'user_profile_changed') &&
            mounted) {
          debugPrint('HomeView: User profile changed, reloading greeting info');
          unawaited(_loadUserAndShopInfo());
        }

        // Handle shop change event - reload everything
        if (event == EventBus.shopChanged && mounted) {
          debugPrint('HomeView: Shop changed, reloading all data');
          _initialSetup();
          _debouncedLoadStats();
          _debouncedLoadDebtOverview();
          setState(() {
            _rebuildCounter++; // Force rebuild tabs
          });
        }
      }, onError: (e) => debugPrint('HomeView: EventBus error: $e'));

      // NOTE: listenToNotifications already called in AuthGate (main.dart)
      // Removing duplicate listener to avoid double snackbar/notification on iOS

      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _permissions.isEmpty) {
          debugPrint('Permissions not loaded, forcing update');
          _updatePermissions(forceRefresh: true);
        }
      });
    });
  }

  Future<void> _loadSavedTabIndex() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_lastTabIndexPrefKey);
      final savedTabId = prefs.getString(_lastTabIdPrefKey);
      if (!mounted) return;
      setState(() {
        _restoredTabId = savedTabId;
        _restoredTabIndex = saved != null && saved >= 0 ? saved : null;
      });
    } catch (e) {
      debugPrint('HomeView: Failed to load saved tab index: $e');
    }
  }

  void _primePermissionsFromCache() {
    final cached = UserService.getCurrentUserPermissionsSync();
    if (cached == null) return;

    _shopLocked = cached['shopAppLocked'] == true;
    _lockedByAdmin = List<dynamic>.from(
      cached['lockedByAdmin'] as List<dynamic>? ?? const [],
    );
    _lockedByOwner = List<dynamic>.from(
      cached['lockedByOwner'] as List<dynamic>? ?? const [],
    );
    _permissions = {};
    cached.forEach((key, value) {
      if (value is bool) {
        _permissions[key] = value;
      }
    });
  }

  void _setCurrentTab(int index) {
    if (index < 0 || index >= _navItems.length) return;
    setState(() => _currentIndex = index);
    unawaited(_persistCurrentTabSelection(index));
  }

  String _tabIdAt(int index) {
    final source = _visibleTabConfigs.isNotEmpty
        ? _visibleTabConfigs
        : _tabConfigs;
    if (index < 0 || index >= source.length) return _homeTabId;
    return source[index]['id'] as String? ?? 'tab_$index';
  }

  bool _usesNestedNavigator(int index) {
    final tabId = _tabIdAt(index);
    return tabId != _homeTabId && tabId != _financeTabId;
  }

  GlobalKey<NavigatorState> _navigatorKeyForTab(int index) {
    final tabId = _tabIdAt(index);
    return _tabNavigatorKeys.putIfAbsent(
      tabId,
      () => GlobalKey<NavigatorState>(debugLabel: 'home_tab_$tabId'),
    );
  }

  Future<T?> _pushRoute<T>(BuildContext context, Route<T> route) {
    final index = _currentIndex.clamp(0, _tabConfigs.length - 1);
    if (_usesNestedNavigator(index)) {
      final navigator = _navigatorKeyForTab(index).currentState;
      if (navigator != null) {
        return navigator.push(route);
      }
    }
    return Navigator.of(context).push(route);
  }

  void _openExpensePageAndAdd({required bool isIncome}) {
    _pushRoute(
      context,
      MaterialPageRoute(
        builder: (_) => ExpenseView(
          initialMode: isIncome ? 'THU' : 'CHI',
          openCreateDialogOnStart: true,
        ),
      ),
    );
  }

  Future<bool> _maybePopCurrentTabNavigator() async {
    final index = _currentIndex.clamp(0, _tabConfigs.length - 1);
    if (!_usesNestedNavigator(index)) return false;
    final navigator = _navigatorKeyForTab(index).currentState;
    if (navigator == null) return false;
    return navigator.maybePop();
  }

  Widget _buildTabHost(int index) {
    final tabId = _tabIdAt(index);
    final version = _tabHostVersions[tabId] ?? 0;

    // For home & finance tabs: build inline so that setState() alone
    // refreshes them without replacing widget instances (avoids iOS
    // back-navigation flicker).  Respect locked state — when the tab
    // is locked the cached _tabWidgets already holds the lock screen.
    Widget child;
    final isLocked = _tabAccessState[tabId] == false;
    if (!isLocked && tabId == _homeTabId) {
      child = _buildHomeTab();
    } else if (!isLocked && tabId == _financeTabId) {
      child = _buildFinanceTab();
    } else {
      child = _tabWidgets[index];
    }

    if (!_usesNestedNavigator(index)) {
      return KeyedSubtree(
        key: ValueKey('home_tab_host_${tabId}_$version'),
        child: child,
      );
    }

    return KeyedSubtree(
      key: ValueKey('home_tab_host_${tabId}_$version'),
      child: Navigator(
        key: _navigatorKeyForTab(index),
        onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => child),
      ),
    );
  }

  Future<void> _persistCurrentTabSelection(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_lastTabIndexPrefKey, index);
      await prefs.setString(_lastTabIdPrefKey, _tabIdAt(index));
    } catch (e) {
      debugPrint('HomeView: Failed to persist tab index: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    // Re-initialize tabs when locale changes
    if (_currentLocale.languageCode != locale.languageCode ||
        !_tabsInitialized) {
      _currentLocale = locale;
      _initializeTabConfigs();
      _tabsInitialized = true;
    }
  }

  // Tab configurations with permissions
  List<Map<String, dynamic>> _tabConfigs = [];
  List<Map<String, dynamic>> _visibleTabConfigs = [];
  List<BottomNavigationBarItem> _navItems = [];
  List<Widget> _tabWidgets = [];
  final Map<String, bool> _tabAccessState = {};

  int _rebuildCounter = 0; // Force rebuild counter
  bool _isLoadingStats = false; // Guard chống load nhiều lần
  bool _cloudBootstrapTried = false;
  bool _cloudBootstrapRunning = false;

  Timer? _autoSyncTimer;
  DateTime? _lastPausedAt; // Track when app was paused for iOS flicker fix
  Timer? _statsDebounceTimer; // Add debounce timer
  Timer? _debtOverviewDebounceTimer;
  StreamSubscription? _eventBusSub; // EventBus subscription
  Map<String, bool> _permissions = {};
  List<dynamic> _lockedByAdmin = []; // Danh sách quyền bị Admin khóa
  List<dynamic> _lockedByOwner = []; // Danh sách quyền bị Chủ shop khóa
  bool _shopLocked = false;
  final TextEditingController _phoneSearchCtrl = TextEditingController();
  bool _isSyncing = false;
  int pendingApprovalCount = 0; // Số đơn chờ duyệt giao
  int totalDebtRemain = 0;
  int _customerDebtRemain = 0; // Khách nợ shop
  int _supplierDebtRemain = 0; // Shop nợ NCC
  int _partnerDebtRemain = 0; // Nợ đối tác SC
  int expiringWarranties = 0;
  int unreadChatCount = 0;
  int _totalReminderCount = 0; // Tổng số nhắc nhở
  String _latestChatMessage = ''; // Tin nhắn mới nhất
  String _latestChatSender = ''; // Người gửi tin mới nhất
  Locale _currentLocale = const Locale('vi');
  bool _tabsInitialized = false;
  bool _notificationWorking = false; // Trạng thái thông báo
  String _userName = ''; // Tên hiển thị của người dùng
  String _shopName = ''; // Tên cửa hàng
  String _runtimeRole = '';

  // Modular Dashboard Config
  List<DashboardCardConfig> _dashboardConfigs = [];
  bool _dashboardConfigLoaded = false;

  // Shortcut Config
  List<ShortcutConfig> _shortcutConfigs = [];
  bool _shortcutConfigLoaded = false;
  bool _shortcutEditMode = false; // Inline edit mode on shortcuts grid

  // Phase 2: Multi-Industry - Shop Settings
  ShopSettings? _shopSettings;
  ExpiryStats? _expiryStats;
  VariantWarningCounts? _variantWarnings; // Phase 3: Fashion
  bool get _enableRepair =>
      _shopSettings?.enableRepair ?? true; // Default true for backwards compat
  bool get _enableExpiry => _shopSettings?.enableExpiry ?? false;
  bool get _enableVariants => _shopSettings?.enableVariants ?? false;
  bool get _enableSerial => _shopSettings?.enableSerial ?? false;
  bool get _enableWarranty =>
      _shopSettings?.enableWarranty ??
      true; // Default true for backwards compat
  String get _businessType => _shopSettings?.businessType ?? 'electronics';
  bool get _isElectronics => _businessType == 'electronics';
  bool get _isFashion => _businessType == 'fashion';
  bool get _isFood => _businessType == 'food';

  /// Terminology động theo ngành - giúp app hiển thị như được thiết kế riêng cho ngành đó
  BusinessTerminology get _terms =>
      BusinessTypeHelper.instance.getTerminology(_shopSettings);

  final bool _isSuperAdmin = UserService.isCurrentUserSuperAdmin();
  bool get hasFullAccess =>
      _isSuperAdmin || widget.role == 'owner' || widget.role == 'admin';
  String get _effectiveRole {
    final runtimeRole = _runtimeRole.trim().toLowerCase();
    if (runtimeRole.isNotEmpty) return runtimeRole;
    return widget.role.trim().toLowerCase();
  }

  void _initializeTabConfigs() {
    final loc = AppLocalizations.of(context)!;
    _tabConfigs = [
      {
        'id': _homeTabId,
        'permission': null, // Home always accessible
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.home_outlined),
          activeIcon: const Icon(Icons.home_rounded),
          label: loc.homeTab,
        ),
        'widget': _buildHomeTab(),
      },
      {
        'id': 'sales',
        'permission': 'allowViewSales',
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.shopping_cart_outlined),
          activeIcon: const Icon(Icons.shopping_cart_rounded),
          label: loc.salesTab,
        ),
        'widget': _buildSalesTab(),
      },
      // Only show Repairs tab for electronics shops
      if (_enableRepair)
        {
          'id': 'repairs',
          'permission': 'allowViewRepairs',
          'item': BottomNavigationBarItem(
            icon: const Icon(Icons.build_outlined),
            activeIcon: const Icon(Icons.build_rounded),
            label: loc.repairsTab,
          ),
          'widget': _buildRepairsTab(),
        },
      {
        'id': 'inventory',
        'permission': 'allowViewInventory',
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.inventory_2_outlined),
          activeIcon: const Icon(Icons.inventory_2_rounded),
          label: loc.inventoryTab,
        ),
        'widget': _buildInventoryTab(),
      },
      // Phase 2: Expiry tab for Food shops
      if (_enableExpiry)
        {
          'id': 'expiry',
          'permission': 'allowViewInventory', // Same as inventory access
          'item': BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: (_expiryStats?.atRiskCount ?? 0) > 0,
              label: Text('${_expiryStats?.atRiskCount ?? 0}'),
              child: const Icon(Icons.timer_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: (_expiryStats?.atRiskCount ?? 0) > 0,
              label: Text('${_expiryStats?.atRiskCount ?? 0}'),
              child: const Icon(Icons.timer),
            ),
            label: 'HSD', // Hạn sử dụng
          ),
          'widget': const ExpiryManagementView(),
        },
      // Phase 3: Variants tab for Fashion shops
      if (_enableVariants)
        {
          'id': 'variants',
          'permission': 'allowViewInventory', // Same as inventory access
          'item': BottomNavigationBarItem(
            icon: Badge(
              isLabelVisible: (_variantWarnings?.total ?? 0) > 0,
              label: Text('${_variantWarnings?.total ?? 0}'),
              child: const Icon(Icons.checkroom_outlined),
            ),
            activeIcon: Badge(
              isLabelVisible: (_variantWarnings?.total ?? 0) > 0,
              label: Text('${_variantWarnings?.total ?? 0}'),
              child: const Icon(Icons.checkroom),
            ),
            label: 'Size/Màu', // Biến thể
          ),
          'widget': const VariantManagementView(),
        },
      {
        'id': 'staff',
        'permission':
            'allowManageStaff', // Staff tab requires manage staff permission
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.people_outline),
          activeIcon: const Icon(Icons.people_rounded),
          label: loc.staffTab,
        ),
        'widget': _buildStaffTab(),
      },
      {
        'id': 'finance',
        'permission':
            'allowViewRevenue', // Finance tab requires revenue permission
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          activeIcon: const Icon(Icons.account_balance_wallet_rounded),
          label: loc.financeTab,
        ),
        'widget': _buildFinanceTab(),
      },
      {
        'id': 'settings',
        // Settings always visible: users need access to account, logout, linked accounts
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.settings_outlined),
          activeIcon: const Icon(Icons.settings_rounded),
          label: loc.settingsTab,
        ),
        'widget': _buildSettingsTab(),
      },
    ];
    // Apply permission-based filtering immediately
    // If permissions already loaded, use them; otherwise, default to restricted for non-admin
    _updateAvailableTabs();
  }

  void _changeLanguage(Locale locale) {
    _currentLocale = locale;
    widget.setLocale?.call(locale);
    setState(() {});
  }

  void _showLanguageSheet() {
    final loc = AppLocalizations.of(context)!;
    showAppBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.flag, color: AppColors.primary),
              title: Text(loc.vietnamese),
              onTap: () {
                Navigator.pop(context);
                _changeLanguage(const Locale('vi'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.flag_circle, color: AppColors.primary),
              title: Text(loc.english),
              onTap: () {
                Navigator.pop(context);
                _changeLanguage(const Locale('en'));
              },
            ),
          ],
        ),
      ),
    );
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
                padding: const EdgeInsets.all(12),
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
                  borderRadius: BorderRadius.circular(12),
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
                      style: AppTextStyles.body1.copyWith(
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
                  borderRadius: BorderRadius.circular(12),
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
          padding: const EdgeInsets.all(12),
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
              const Icon(
                Icons.access_time_rounded,
                color: AppColors.info,
                size: 20,
              ),
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
      padding: const EdgeInsets.all(12),
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
              style: AppTextStyles.subtitle1.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.headline5.copyWith(
              color: Colors.white,
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
              child: const Icon(
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

  /// Rebuild the actual tab widget by id (used when access is regained after being locked).
  Widget _rebuildTabWidget(String tabId) {
    switch (tabId) {
      case 'home':
        return _buildHomeTab();
      case 'sales':
        return _buildSalesTab();
      case 'repairs':
        return _buildRepairsTab();
      case 'inventory':
        return _buildInventoryTab();
      case 'expiry':
        return const ExpiryManagementView();
      case 'variants':
        return const VariantManagementView();
      case 'staff':
        return _buildStaffTab();
      case 'finance':
        return _buildFinanceTab();
      case 'settings':
        return _buildSettingsTab();
      default:
        return const SizedBox.shrink();
    }
  }

  void _updateAvailableTabs() {
    // THAY ĐỔI: Luôn hiển thị tất cả các tab, nhưng thay nội dung bằng màn hình khóa nếu không có quyền
    final allConfigs = _tabConfigs.map((config) {
      final tabId = config['id'] as String? ?? 'unknown';
      final permission = config['permission'] as String?;
      // Nếu không có quyền yêu cầu (null), luôn cho phép
      // hasFullAccess (admin/owner/superAdmin) luôn có quyền
      // Nếu permissions chưa load (_permissions rỗng), mặc định khóa cho nhân viên
      final bool hasPermission;
      if (permission == null) {
        hasPermission = true;
      } else if (hasFullAccess) {
        hasPermission = true;
      } else if (_permissions.isEmpty) {
        // Permissions chưa load - mặc định khóa để bảo mật
        hasPermission = false;
      } else {
        hasPermission = _permissions[permission] == true;
      }

      final previousAccess = _tabAccessState[tabId];
      if (previousAccess != null && previousAccess != hasPermission) {
        _tabNavigatorKeys[tabId] = GlobalKey<NavigatorState>(
          debugLabel: 'home_tab_$tabId',
        );
        _tabHostVersions[tabId] = (_tabHostVersions[tabId] ?? 0) + 1;
      }
      _tabAccessState[tabId] = hasPermission;

      // Nếu không có quyền, thay thế widget bằng màn hình khóa
      if (!hasPermission) {
        final tabLabel =
            (config['item'] as BottomNavigationBarItem).label ?? 'Chức năng';
        // Xác định nguồn khóa: admin hay owner
        final lockedBy = _getLockedBy(permission!);
        return {
          ...config,
          'widget': _buildLockedFeatureScreen(tabLabel, lockedBy: lockedBy),
        };
      }
      // When access regained (was locked, now unlocked), rebuild the actual widget
      if (previousAccess == false && hasPermission) {
        return {...config, 'widget': _rebuildTabWidget(tabId)};
      }
      return config;
    }).toList();

    // Limit to 7 tabs max for BottomNavigationBar compatibility
    if (allConfigs.length > 7) {
      // Prioritize by stable tab id instead of localized labels.
      final priorityTabs = [
        _homeTabId,
        'sales',
        'repairs',
        'inventory',
        'staff',
        _financeTabId,
        'settings',
      ];
      final prioritized = allConfigs
          .where((config) => priorityTabs.contains(config['id'] as String?))
          .toList();
      final remaining = allConfigs
          .where((config) => !priorityTabs.contains(config['id'] as String?))
          .toList();
      allConfigs.clear();
      allConfigs.addAll(prioritized);
      allConfigs.addAll(remaining.take(7 - prioritized.length));
    }

    // Preserve current tab by stable id before rebuilding.
    final String? currentTabId = (_currentIndex < _visibleTabConfigs.length)
        ? _visibleTabConfigs[_currentIndex]['id'] as String?
        : null;

    _visibleTabConfigs = List<Map<String, dynamic>>.from(allConfigs);
    _navItems = allConfigs
        .map((config) => config['item'] as BottomNavigationBarItem)
        .toList();
    _tabWidgets = allConfigs
        .map((config) => config['widget'] as Widget)
        .toList();

    // Restore current tab by id match (prevents reset when labels/locales shift).
    if (currentTabId != null) {
      final restored = _visibleTabConfigs.indexWhere(
        (config) => config['id'] == currentTabId,
      );
      if (restored >= 0) {
        _currentIndex = restored;
      } else if (_currentIndex >= _navItems.length) {
        _currentIndex = 0;
      }
    } else if (_restoredTabId != null) {
      final restored = _visibleTabConfigs.indexWhere(
        (config) => config['id'] == _restoredTabId,
      );
      if (restored >= 0) {
        _currentIndex = restored;
        _restoredTabId = null;
        _restoredTabIndex = null;
      } else if (_restoredTabIndex != null &&
          _restoredTabIndex! < _navItems.length) {
        _currentIndex = _restoredTabIndex!;
        _restoredTabIndex = null;
      } else if (_currentIndex >= _navItems.length) {
        _currentIndex = 0;
      }
    } else if (_restoredTabIndex != null &&
        _restoredTabIndex! < _navItems.length) {
      _currentIndex = _restoredTabIndex!;
      _restoredTabIndex = null;
    } else if (_currentIndex >= _navItems.length) {
      _currentIndex = 0;
    }

    unawaited(_persistCurrentTabSelection(_currentIndex));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // Only react to paused (not inactive) — iOS fires inactive for system
      // overlays, route transitions, and notification center, causing false
      // reloads that trigger flicker.
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
      _lastPausedAt = DateTime.now();
      debugPrint('HomeView: App paused - paused sync timer');
    } else if (state == AppLifecycleState.resumed) {
      EventBus().emit('app_resumed');

      // Skip heavy reload if pause was very brief (< 2s) — this happens on
      // iOS when returning from camera, image picker, or quick overlays.
      // Avoids the flicker from full tab rebuild + permission refetch.
      final pauseDuration = _lastPausedAt != null
          ? DateTime.now().difference(_lastPausedAt!)
          : const Duration(seconds: 999);
      _lastPausedAt = null;

      if (pauseDuration.inSeconds >= 2) {
        // Genuine background resume — do full refresh
        unawaited(_updatePermissions(forceRefresh: true));
        unawaited(_loadUserAndShopInfo());
        _syncNow(silent: true);
        _debouncedLoadStats();
        _debouncedLoadDebtOverview();
      } else {
        // Quick resume (camera, picker, etc.) — lightweight refresh only
        debugPrint(
          'HomeView: Quick resume (${pauseDuration.inMilliseconds}ms) - skipping heavy reload',
        );
        _debouncedLoadStats();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventBusSub?.cancel();
    _autoSyncTimer?.cancel();
    _statsDebounceTimer?.cancel();
    _phoneSearchCtrl.dispose();
    _debtOverviewDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialSetup() async {
    try {
      // Load UI ngay lập tức với data local, không chờ Firestore
      // 1. Load permissions và config trước (nhanh)
      unawaited(_updatePermissions(forceRefresh: true));
      _loadShopSettings();
      _loadDashboardConfig();
      _loadShortcutConfig();

      // 2. Load user info NGAY (quan trọng cho lời chào)
      await _loadUserAndShopInfo();

      // Track nếu cần download từ cloud (chỉ gọi TỐI ĐA 1 lần)
      bool needsCloudDownload = false;

      // 3. Trên WEB: đảm bảo đã có data trước khi load stats
      // main.dart đã await downloadAllFromCloud cho web,
      // nhưng nếu vào HomeView qua route khác thì cần kiểm tra lại
      if (kIsWeb) {
        final bootstrapScope = _HomeShopReadScope(UserService.getShopIdSync());
        final counts = await db.database.then(
          (d) => d.rawQuery(
            bootstrapScope.coreRecordCountSql,
            bootstrapScope.coreRecordCountArgs,
          ),
        );
        final totalRecords = (counts.first['total'] as int?) ?? 0;
        if (totalRecords == 0) {
          needsCloudDownload = true;
        }
      }

      // Ensure shop context is valid before relying on local stats/sync.
      final ensuredShopId = await UserService.getCurrentShopId();
      if (ensuredShopId == null || ensuredShopId.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null && user.email != null) {
          debugPrint(
            'HomeView: shopId missing, forcing syncUserInfo recovery...',
          );
          await UserService.syncUserInfo(user.uid, user.email!);
          needsCloudDownload = true;
        }
      }

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
        await prefs.setString('lastUserId', currentUser.uid);
        if (currentUser.email != null) {
          await UserService.syncUserInfo(currentUser.uid, currentUser.email!);
          needsCloudDownload = true;
        }
      }

      // Chỉ gọi downloadAllFromCloud TỐI ĐA 1 lần nếu thực sự cần
      if (needsCloudDownload) {
        if (!kIsWeb &&
            (SyncService.isRealTimeSyncActive ||
                SyncService.isRealtimeInitializationInProgress)) {
          debugPrint(
            'HomeView: Skip cloud download vì realtime sync đang active/initializing',
          );
        } else {
          debugPrint('HomeView: Cần cloud download, gọi 1 lần duy nhất...');
          await SyncService.downloadAllFromCloud().timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              debugPrint('HomeView: Cloud download timeout');
            },
          );
        }
      }

      // 4. Load stats (giờ đã có data)
      _loadStats();
      _loadDebtOverview();

      // Clean duplicate ở background, không block UI
      Future.delayed(const Duration(seconds: 2), () {
        db.cleanDuplicateData();
      });
    } catch (e) {
      debugPrint('Error in _initialSetup: $e');
      // Still try to load permissions
      unawaited(_updatePermissions(forceRefresh: true));
    }
  }

  /// Load thông tin người dùng và tên shop để hiển thị lời chào
  Future<void> _loadUserAndShopInfo() async {
    try {
      String normalizeLegacyShopName(String? rawName) {
        final name = (rawName ?? '').trim();
        if (name.isEmpty) return '';
        final lower = name.toLowerCase();
        if (lower == 'shop new' || lower == 'shop_new' || lower == 'shopnew') {
          return 'Quản Lý Shop';
        }
        return name;
      }

      final user = FirebaseAuth.instance.currentUser;
      debugPrint('_loadUserAndShopInfo: START, user=${user?.email}');
      if (user == null) {
        debugPrint('_loadUserAndShopInfo: No user, returning');
        return;
      }

      String resolvedRole = _effectiveRole;
      try {
        final userInfo = await UserService.getUserInfo(user.uid);
        final firestoreRole =
            (userInfo['role'] ?? '').toString().trim().toLowerCase();
        if (firestoreRole.isNotEmpty) {
          resolvedRole = firestoreRole;
        } else {
          final fastRole = (await UserService.getRoleFast()).trim().toLowerCase();
          if (fastRole.isNotEmpty) {
            resolvedRole = fastRole;
          }
        }
      } catch (roleError) {
        debugPrint('_loadUserAndShopInfo: role fetch error=$roleError');
      }

      // ====== TỐI ƯU: Load từ cache trước, hiện UI ngay ======
      final prefs = await SharedPreferences.getInstance();
      final cachedUserName = prefs.getString('cached_userName_${user.uid}');
      final cachedShopName = normalizeLegacyShopName(
        prefs.getString('cached_shopName_${user.uid}'),
      );
      debugPrint(
        '_loadUserAndShopInfo: Cache - userName=$cachedUserName, shopName=$cachedShopName',
      );

      // Hiển thị cache ngay lập tức (nếu có và không rỗng)
      if ((cachedUserName != null && cachedUserName.isNotEmpty) ||
          (cachedShopName != null && cachedShopName.isNotEmpty)) {
        if (mounted) {
          setState(() {
            if (cachedUserName != null && cachedUserName.isNotEmpty)
              _userName = cachedUserName;
            if (cachedShopName != null && cachedShopName.isNotEmpty)
              _shopName = cachedShopName;
          });
          debugPrint(
            '_loadUserAndShopInfo: Set state from cache - userName=$_userName, shopName=$_shopName',
          );
        }
      }

      // Lấy tên hiển thị qua UserService (ưu tiên Firestore profile -> Auth -> email fallback)
      // Reload Auth trước để đảm bảo displayName mới nhất (quan trọng cho tài khoản mới đăng ký)
      debugPrint('_loadUserAndShopInfo: Reloading user auth profile...');
      try {
        await user.reload();
      } catch (_) {}
      debugPrint(
        '_loadUserAndShopInfo: Getting displayName via UserService...',
      );
      String displayName = await UserService.getCurrentUserName();
      debugPrint('_loadUserAndShopInfo: displayName=$displayName');

      // Nếu vẫn rỗng, dùng email prefix làm tên
      if (displayName.trim().isEmpty && user.email != null) {
        displayName = user.email!.split('@').first;
        if (displayName.isNotEmpty) {
          displayName = displayName[0].toUpperCase() + displayName.substring(1);
        }
        debugPrint(
          '_loadUserAndShopInfo: Using email fallback displayName=$displayName',
        );
      }

      // ====== SET userName NGAY khi đã có displayName (trước khi fetch shop) ======
      // Đảm bảo tên user luôn hiển thị ngay cả khi bước fetch shop bị lỗi
      if (displayName.isNotEmpty && mounted) {
        setState(() {
          _userName = displayName;
          _runtimeRole = resolvedRole;
        });
        await prefs.setString('cached_userName_${user.uid}', displayName);
        debugPrint(
          '_loadUserAndShopInfo: SET userName=$displayName (before shop fetch)',
        );
      }

      // Lấy tên shop (trong try-catch riêng để không ảnh hưởng userName)
      String shopName = '';
      try {
        debugPrint('_loadUserAndShopInfo: Getting shopId...');
        final shopId = await UserService.getCurrentShopId();
        debugPrint('_loadUserAndShopInfo: shopId=$shopId');
        if (shopId != null) {
          // Force refresh token claims trước khi đọc shop doc
          // (tránh stale claims gây permission-denied)
          try {
            await user.getIdToken(true);
            debugPrint(
              '_loadUserAndShopInfo: Token refreshed before shop fetch',
            );
          } catch (_) {}
          debugPrint(
            '_loadUserAndShopInfo: Fetching shop doc from Firestore...',
          );
          final shopDoc = await FirebaseFirestore.instance
              .collection('shops')
              .doc(shopId)
              .get();
          if (shopDoc.exists) {
            final shopData = shopDoc.data();
            debugPrint('_loadUserAndShopInfo: Shop doc data=$shopData');
            shopName = normalizeLegacyShopName(shopData?['name']?.toString());
            debugPrint(
              '_loadUserAndShopInfo: shopName from Firestore=$shopName',
            );
          } else {
            debugPrint('_loadUserAndShopInfo: Shop doc does NOT exist');
          }

          // Legacy fallback: some shops save profile under settings/shop_profile.
          if (shopName.isEmpty) {
            try {
              final profileDoc = await FirebaseFirestore.instance
                  .collection('shops')
                  .doc(shopId)
                  .collection('settings')
                  .doc('shop_profile')
                  .get();
              if (profileDoc.exists) {
                final profileData = profileDoc.data();
                final fallbackName = normalizeLegacyShopName(
                  profileData?['name']?.toString(),
                );
                if (fallbackName.isNotEmpty) {
                  shopName = fallbackName;
                  debugPrint(
                    '_loadUserAndShopInfo: shopName from shop_profile fallback=$shopName',
                  );
                }
              }
            } catch (profileError) {
              debugPrint(
                '_loadUserAndShopInfo: shop_profile fallback error=$profileError',
              );
            }
          }
        }
      } catch (shopError) {
        debugPrint(
          '_loadUserAndShopInfo: Shop fetch error (userName still safe): $shopError',
        );
        // Fallback: lấy shopName từ SharedPreferences (set bởi SyncService hoặc ShopSettings)
        final fallbackShopName = normalizeLegacyShopName(
          prefs.getString('shop_name'),
        );
        if (fallbackShopName.isNotEmpty) {
          shopName = fallbackShopName;
          debugPrint(
            '_loadUserAndShopInfo: shopName from SharedPreferences fallback=$shopName',
          );
        }
      }

      // ====== Cache & update shopName ======
      if (shopName.isNotEmpty) {
        await prefs.setString('cached_shopName_${user.uid}', shopName);
        debugPrint('_loadUserAndShopInfo: Cached shopName=$shopName');
      }

      if (mounted) {
        setState(() {
          if (displayName.isNotEmpty) _userName = displayName;
          _shopName = shopName;
          _runtimeRole = resolvedRole;
        });
        debugPrint(
          '_loadUserAndShopInfo: FINAL setState - userName=$_userName, shopName=$_shopName, role=$_runtimeRole',
        );
      }

      // Retry: Nếu tên vẫn rỗng (race condition với đăng ký mới), thử lại sau 2s
      if (displayName.trim().isEmpty ||
          displayName == user.email?.split('@').first) {
        Future.delayed(const Duration(seconds: 2), () async {
          if (!mounted) return;
          try {
            await user.reload();
            final retryName = await UserService.getCurrentUserName();
            if (retryName.isNotEmpty && retryName != displayName && mounted) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('cached_userName_${user.uid}', retryName);
              setState(() => _userName = retryName);
              debugPrint('_loadUserAndShopInfo: RETRY got userName=$retryName');
            }
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('_loadUserAndShopInfo ERROR: $e');
      debugPrint('_loadUserAndShopInfo STACK: ${StackTrace.current}');
      // Safety net: nếu _userName vẫn rỗng sau lỗi, dùng email prefix
      if (_userName.trim().isEmpty && mounted) {
        final user = FirebaseAuth.instance.currentUser;
        if (user?.email != null) {
          final emailPrefix = user!.email!.split('@').first;
          final fallbackName = emailPrefix.isNotEmpty
              ? emailPrefix[0].toUpperCase() + emailPrefix.substring(1)
              : '';
          if (fallbackName.isNotEmpty) {
            setState(() => _userName = fallbackName);
            debugPrint(
              '_loadUserAndShopInfo: ERROR FALLBACK userName=$fallbackName',
            );
          }
        }
      }
    }
  }

  Future<void> _updatePermissions({bool forceRefresh = false}) async {
    debugPrint('HomeView: _updatePermissions called');
    try {
      final perms = await UserService.getCurrentUserPermissions(
        forceRefresh: forceRefresh,
      );
      if (!mounted) return;

      // Build new permission map
      final newPerms = <String, bool>{};
      perms.forEach((key, value) {
        if (value is bool) {
          newPerms[key] = value;
        }
      });
      final newShopLocked = perms['shopAppLocked'] == true;
      final newLockedByAdmin = perms['lockedByAdmin'] as List<dynamic>? ?? [];
      final newLockedByOwner = perms['lockedByOwner'] as List<dynamic>? ?? [];

      // Skip setState if nothing changed — avoids tab rebuild flicker
      final permsSame =
          _permissions.length == newPerms.length &&
          newPerms.entries.every((e) => _permissions[e.key] == e.value);
      final lockedSame = _shopLocked == newShopLocked;
      if (permsSame && lockedSame && _permissions.isNotEmpty) {
        debugPrint('HomeView: Permissions unchanged, skipping rebuild');
        return;
      }

      setState(() {
        _shopLocked = newShopLocked;
        _lockedByAdmin = newLockedByAdmin;
        _lockedByOwner = newLockedByOwner;
        _permissions = newPerms;
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
      await SyncService.refreshCloudCollections(reason: 'home_sync_now');
      EventBus().emit('sync_now_completed');
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

  void _debouncedLoadDebtOverview() {
    _debtOverviewDebounceTimer?.cancel();
    _debtOverviewDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _loadDebtOverview();
      }
    });
  }

  Future<void> _loadDebtOverview() async {
    try {
      final debtOverview = await _debtSummaryService.getDebtOverview();
      if (!mounted) return;

      final customerRemain = debtOverview['customerRemain'] ?? 0;
      final supplierRemain = debtOverview['supplierRemain'] ?? 0;
      final partnerRemain = debtOverview['partnerRemain'] ?? 0;
      final totalRemain = debtOverview['totalRemain'] ?? 0;

      setState(() {
        _customerDebtRemain = customerRemain;
        _supplierDebtRemain = supplierRemain;
        _partnerDebtRemain = partnerRemain;
        totalDebtRemain = totalRemain;
      });
    } catch (e) {
      debugPrint('HomeView._loadDebtOverview error: $e');
    }
  }

  /// Phase 2: Load shop settings cho multi-industry features
  bool _isShowingBusinessTypeWizard = false;

  /// Load dashboard card layout config from SharedPreferences
  Future<void> _loadDashboardConfig() async {
    try {
      final configs = await DashboardConfigService.loadConfig(
        role: widget.role,
        isSuperAdmin: _isSuperAdmin,
      );
      if (mounted) {
        setState(() {
          _dashboardConfigs = configs;
          _dashboardConfigLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('HomeView: Error loading dashboard config: $e');
      if (mounted) {
        setState(() {
          _dashboardConfigs = DashboardConfigService.getDefaultLayout(
            role: widget.role,
            isSuperAdmin: _isSuperAdmin,
          );
          _dashboardConfigLoaded = true;
        });
      }
    }
  }

  /// Load shortcut grid config from SharedPreferences
  Future<void> _loadShortcutConfig() async {
    try {
      final configs = await ShortcutConfigService.loadConfig();
      if (mounted) {
        setState(() {
          _shortcutConfigs = configs;
          _shortcutConfigLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('HomeView: Error loading shortcut config: $e');
      if (mounted) {
        setState(() {
          _shortcutConfigs = ShortcutConfigService.getDefaultShortcuts();
          _shortcutConfigLoaded = true;
        });
      }
    }
  }

  Future<void> _loadShopSettings() async {
    try {
      // CRITICAL: Clear cache to ensure fresh settings are loaded
      CategoryService().clearCache();

      final shopId = await UserService.getCurrentShopId();
      debugPrint('🏠 HomeView: Loading settings for shopId=$shopId');

      final settings = await CategoryService().getShopSettings();
      final effectiveSettings =
          settings ??
          (!hasFullAccess && shopId != null
              ? ShopSettings.electronics(shopId)
              : null);
      debugPrint('🏠 HomeView: Loaded shop settings:');
      debugPrint('   - businessType: ${settings?.businessType}');
      debugPrint('   - enableRepair: ${settings?.enableRepair}');
      debugPrint('   - enableSerial: ${settings?.enableSerial}');
      debugPrint('   - enableExpiry: ${settings?.enableExpiry}');
      debugPrint('   - enableVariants: ${settings?.enableVariants}');
      debugPrint('   - isDefault: ${settings?.isDefault}');

      if (!mounted) return;

      // Load expiry stats if enabled (Food shops)
      ExpiryStats? expiryStats;
      if (settings?.enableExpiry == true) {
        expiryStats = await ExpiryAlertService().getExpiryStats();
        // Check and notify expiry alerts
        ExpiryAlertService().checkAndNotifyExpiry();
      }

      // Load variant warnings if enabled (Fashion shops) - Phase 3
      VariantWarningCounts? variantWarnings;
      if (settings?.enableVariants == true) {
        variantWarnings = await VariantService().getWarningCounts();
      }

      setState(() {
        _shopSettings = effectiveSettings;
        _expiryStats = expiryStats;
        _variantWarnings = variantWarnings;
        debugPrint(
          '🏠 HomeView: setState done - _enableRepair=$_enableRepair, _enableVariants=$_enableVariants',
        );
        // Re-initialize tabs when shop settings change
        _initializeTabConfigs();
        _updateAvailableTabs();
      });

      // CRITICAL: Nếu chưa có settings, hiện wizard để chọn loại hình kinh doanh
      // Guard để tránh hiện wizard nhiều lần (do EventBus + onShopChanged cùng gọi)
      if (settings == null && mounted) {
        if (hasFullAccess && !_isShowingBusinessTypeWizard) {
          debugPrint(
            '🏠 HomeView: No settings found - showing business type wizard',
          );
          _isShowingBusinessTypeWizard = true;
          _showBusinessTypeSetupDialog();
        } else {
          debugPrint(
            '🏠 HomeView: settings missing for staff role -> skip business type wizard',
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Error loading shop settings: $e');
      debugPrint('Stack: $stack');
    }
  }

  /// Hiển thị dialog chọn ngành kinh doanh cho shops chưa thiết lập
  void _showBusinessTypeSetupDialog() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null || !mounted) return;

    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false, // Force user to choose
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: BusinessTypeWizard(
          shopId: shopId,
          shopName: _shopName.isNotEmpty ? _shopName : 'Cửa hàng',
          onComplete: (newSettings) async {
            Navigator.pop(context);
            _isShowingBusinessTypeWizard = false;
            // Save the new settings
            await CategoryService().saveShopSettings(newSettings);
            // Reload settings to apply changes
            _loadShopSettings();
            NotificationService.showSnackBar(
              'Đã thiết lập ngành kinh doanh: ${newSettings.businessTypeName}',
              color: Colors.green,
            );
          },
        ),
      ),
    ).whenComplete(() {
      _isShowingBusinessTypeWizard = false;
    });
  }

  // State variables for accurate financial overview (same as cash_closing analysis)
  int _todayTotalIn = 0; // THU HÔM NAY (tổng thu)
  int _todayTotalOut = 0; // CHI HÔM NAY (tổng chi thực tế)
  int _todayNetProfit = 0; // LỢI NHUẬN RÒNG
  int _todaySalesProfit = 0; // Lợi nhuận bán hàng
  int _todayRepairProfit = 0; // Lợi nhuận sửa chữa
  int _todayRepairCount = 0; // Số đơn sửa chữa hoàn thành hôm nay
  int _todaySaleOrderCount = 0; // Số đơn bán hàng hôm nay
  int _todayExpenseCount = 0; // Số chi phí hôm nay
  int _todayStockInCost = 0; // Chi phí nhập kho hôm nay (tiền mặt/CK)
  int _todayDebtPaidToSupplier = 0; // Trả nợ NCC hôm nay
  int _todayExpenseOnly = 0; // Chi phí hoạt động thuần (không gồm trả nợ NCC)
  // Detail breakdown for Sổ quỹ style display
  int _todaySaleIncome = 0; // Doanh thu bán hàng
  int _todayRepairIncome = 0; // Doanh thu sửa chữa
  int _todayDebtCollected = 0; // Thu nợ khách hàng
  int _todayMiscIncome = 0; // Thu phát sinh
  int _todayImportOut = 0; // Chi nhập hàng
  int _todayPartnerPaid = 0; // TT đối tác sửa chữa
  int _todayRepairPartsCostFund = 0; // Vốn LK SC đã ghi sổ quỹ
  int _todaySaleCost = 0; // Giá vốn bán hàng
  int _todayRepairCost = 0; // Giá vốn sửa chữa
  int _todaySettlementIncome = 0; // Tất toán NH (bank settlement)
  int _todayRefundOut = 0; // Tiền trả hàng (cash out)
  int _todayReturnCost = 0; // Giá vốn hàng trả lại
  int _previousClosingTotal = 0; // Quỹ chốt ngày trước (cashEnd + bankEnd)

  /// Load chat info separately (deferred) - Firestore calls, don't block main stats
  Future<void> _loadChatInfo() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      final results = await Future.wait([
        UserService.getUnreadChatCount(currentUser.uid),
        UserService.getLatestChatMessage(),
      ]);
      final unread = results[0] as int;
      final latestChat = results[1] as Map<String, dynamic>?;
      if (mounted) {
        setState(() {
          unreadChatCount = unread;
          if (latestChat != null) {
            _latestChatMessage = latestChat['message'] ?? '';
            _latestChatSender = latestChat['senderName'] ?? '';
          }
        });
      }
    } catch (e) {
      debugPrint('HomeView: Error loading chat info: $e');
    }
  }

  Future<void> _loadStats() async {
    // Guard chống load nhiều lần liên tiếp
    if (_isLoadingStats) {
      debugPrint('HomeView: _loadStats already running, skipping...');
      return;
    }
    _isLoadingStats = true;

    try {
      final stopwatch = Stopwatch()..start();
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      final startMs = todayStart.millisecondsSinceEpoch;
      final endMs = todayEnd.millisecondsSinceEpoch;
      final dbConn = await db.database;
      final shopId = UserService.getShopIdSync();
      final scope = _HomeShopReadScope(shopId);

      // === BATCH 1: Run all independent DB queries in parallel ===
      final batch1 = await Future.wait([
        // [0] pendingR
        dbConn.rawQuery(
          'SELECT COUNT(*) FROM repairs WHERE ${scope.where('status IN (1, 2)')}',
          scope.args(const []),
        ),
        // [1] newRT
        dbConn.rawQuery(
          'SELECT COUNT(*) FROM repairs WHERE ${scope.where('createdAt >= ? AND createdAt < ?')}',
          scope.args([startMs, endMs]),
        ),
        // [2] fSales
        dbConn.query(
          'sales',
          columns: [
            'totalPrice',
            'totalCost',
            'discount',
            'paymentMethod',
            'isInstallment',
            'downPayment',
            'downPaymentMethod',
            'settlementReceivedAt',
            'settlementAmount',
            'loanAmount',
            'loanAmount2',
            'soldAt',
            'warranty',
          ],
          where: scope.where('soldAt >= ? AND soldAt < ?'),
          whereArgs: scope.args([startMs, endMs]),
        ),
        // [3] fSettlements
        dbConn.query(
          'sales',
          columns: [
            'totalPrice',
            'totalCost',
            'discount',
            'downPayment',
            'settlementAmount',
            'loanAmount',
            'loanAmount2',
            'soldAt',
          ],
          where: scope.where(
            'isInstallment = 1 AND settlementReceivedAt IS NOT NULL AND settlementReceivedAt >= ? AND settlementReceivedAt < ?',
          ),
          whereArgs: scope.args([startMs, endMs]),
        ),
        // [4] fRepairs
        dbConn.query(
          'repairs',
          columns: [
            'price',
            'cost',
            'paymentMethod',
            'deliveredAt',
            'warranty',
          ],
          where: scope.where(
            'status = 4 AND deliveredAt IS NOT NULL AND deliveredAt >= ? AND deliveredAt < ?',
          ),
          whereArgs: scope.args([startMs, endMs]),
        ),
        // [5] fExpenses
        dbConn.query(
          'expenses',
          columns: [
            'amount',
            'category',
            'description',
            'title',
            'date',
            'type',
            'paymentMethod',
          ],
          where: scope.where('date >= ? AND date < ?'),
          whereArgs: scope.args([startMs, endMs]),
        ),
        // [6] debtPayments - resolved debtType + shop filter để khớp chốt quỹ
        db.getDebtPaymentsForCashFlowByDateRange(startMs, endMs),
        // [7] partnerPayments
        dbConn.query(
          'repair_partner_payments',
          columns: ['amount', 'paidAt', 'paymentMethod'],
          where: scope.where(
            'paidAt IS NOT NULL AND paidAt >= ? AND paidAt < ? AND (deleted IS NULL OR deleted != 1)',
          ),
          whereArgs: scope.args([startMs, endMs]),
        ),
        // [8] supplierPayments
        dbConn.query(
          'supplier_payments',
          columns: ['amount', 'paidAt', 'paymentMethod'],
          where: scope.where(
            'paidAt IS NOT NULL AND paidAt >= ? AND paidAt < ? AND (deleted IS NULL OR deleted != 1)',
          ),
          whereArgs: scope.args([startMs, endMs]),
        ),
        // [9] supplierImports
        dbConn.query(
          'supplier_import_history',
          columns: [
            'totalAmount',
            'costPrice',
            'paymentMethod',
            'importDate',
            'createdAt',
          ],
          where: scope.where(
            '((importDate IS NOT NULL AND importDate >= ? AND importDate < ?) OR (importDate IS NULL AND createdAt >= ? AND createdAt < ?))',
          ),
          whereArgs: scope.args([startMs, endMs, startMs, endMs]),
        ),
        // [10] repairPartsCostFund — repairs with cost recorded in fund today
        dbConn.query(
          'repairs',
          columns: ['cost', 'costRecordedAmount', 'costPaymentMethod'],
          where: scope.where(
            'costRecordedInFund = 1 AND costRecordedAt IS NOT NULL AND costRecordedAt >= ? AND costRecordedAt < ?',
          ),
          whereArgs: scope.args([startMs, endMs]),
        ),
        // [11] pendingApproval — đơn chờ duyệt giao (status 3 + pendingDeliveryApproval = 1)
        dbConn.rawQuery(
          'SELECT COUNT(*) FROM repairs WHERE ${scope.where('status = 3 AND pendingDeliveryApproval = 1')}',
          scope.args(const []),
        ),
        // [12] salesReturns — phiếu trả hàng hôm nay (trừ vào doanh thu/quỹ)
        dbConn
            .query(
              'sales_returns',
              columns: [
                'totalReturnAmount',
                'totalReturnCost',
                'refundMethod',
                'returnDate',
              ],
              where: scope.where(
                'returnDate >= ? AND returnDate < ? AND status = ?',
              ),
              whereArgs: scope.args([startMs, endMs, 'APPROVED']),
            )
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      debugPrint(
        'HomeView: Batch 1 (13 queries) took ${stopwatch.elapsedMilliseconds}ms',
      );

      final pendingR =
          Sqflite.firstIntValue(batch1[0] as List<Map<String, dynamic>>) ?? 0;
      final newRT =
          Sqflite.firstIntValue(batch1[1] as List<Map<String, dynamic>>) ?? 0;
      final fSales = batch1[2] as List<Map<String, dynamic>>;
      final fSettlements = batch1[3] as List<Map<String, dynamic>>;
      final fRepairs = batch1[4] as List<Map<String, dynamic>>;
      final fExpenses = batch1[5] as List<Map<String, dynamic>>;
      final debtPayments = batch1[6] as List<Map<String, dynamic>>;
      final partnerPayments = batch1[7] as List<Map<String, dynamic>>;
      final supplierPayments = batch1[8] as List<Map<String, dynamic>>;
      final supplierImports = batch1[9] as List<Map<String, dynamic>>;
      final repairPartsCostFundRows = batch1[10] as List<Map<String, dynamic>>;
      final pendingApprovalR =
          Sqflite.firstIntValue(batch1[11] as List<Map<String, dynamic>>) ?? 0;
      final fSalesReturns = batch1[12] as List<Map<String, dynamic>>;

      int doneT = 0, soldT = 0, debtR = 0, expW = 0;
      int custDebt = 0, suppDebt = 0, partDebt = 0;

      final analysis = DailyFinancialAnalysisService.analyze(
        sales: fSales,
        settlementSales: fSettlements,
        repairs: fRepairs,
        expenses: fExpenses,
        debtPayments: debtPayments,
        supplierPayments: supplierPayments,
        repairPartnerPayments: partnerPayments,
        supplierImports: supplierImports,
        repairPartsCostFundRows: repairPartsCostFundRows,
        salesReturns: fSalesReturns,
        enableRepair: _enableRepair,
      );

      // Thống kê số lượng
      doneT = fRepairs.length;
      soldT = fSales.length;

      // === BATCH 2: Secondary queries in parallel ===
      // (warranty, debts, partner debts, record counts - all independent)
      final batch2 = await Future.wait<Object?>([
        // [0] repairsWarranty
        dbConn.query(
          'repairs',
          columns: ['deliveredAt', 'warranty'],
          where: scope.where(
            "deliveredAt IS NOT NULL AND warranty IS NOT NULL AND warranty != '' AND UPPER(warranty) != 'KO BH'",
          ),
          whereArgs: scope.args(const []),
        ),
        // [1] salesWarranty
        dbConn.query(
          'sales',
          columns: ['soldAt', 'warranty'],
          where: scope.where(
            "warranty IS NOT NULL AND warranty != '' AND UPPER(warranty) != 'KO BH'",
          ),
          whereArgs: scope.args(const []),
        ),
        // [2] debt overview — same source of truth as DebtView
        _debtSummaryService.getDebtOverview(),
        // [4] record counts (single combined query)
        dbConn.rawQuery(
          scope.breakdownRecordCountSql,
          scope.breakdownRecordCountArgs,
        ),
        // [5] previous day closing balance for "Quỹ hiện có"
        db.getPreviousDayClosing(DateFormat('yyyy-MM-dd').format(todayStart)),
      ]);
      debugPrint(
        'HomeView: Batch 2 (6 queries) took ${stopwatch.elapsedMilliseconds}ms',
      );

      final repairsWarranty = batch2[0] as List<Map<String, dynamic>>;
      final salesWarranty = batch2[1] as List<Map<String, dynamic>>;
      final debtOverview = batch2[2] as Map<String, int>;
      final recordCounts = batch2[3] as List<Map<String, dynamic>>;

      // Warranty check (CPU-only, no I/O)
      for (final r in repairsWarranty) {
        final deliveredAt = (r['deliveredAt'] as num?)?.toInt();
        final warranty = (r['warranty'] ?? '').toString();
        if (deliveredAt == null) continue;
        int m = int.tryParse(warranty.split(' ').first) ?? 0;
        if (m > 0) {
          DateTime d = DateTime.fromMillisecondsSinceEpoch(deliveredAt);
          DateTime e = DateTime(d.year, d.month + m, d.day);
          if (e.isAfter(now) && e.difference(now).inDays <= 7) expW++;
        }
      }
      for (final s in salesWarranty) {
        final soldAt = (s['soldAt'] as num?)?.toInt() ?? 0;
        final warranty = (s['warranty'] ?? '').toString();
        int m = int.tryParse(warranty.split(' ').first) ?? 12;
        DateTime d = DateTime.fromMillisecondsSinceEpoch(soldAt);
        DateTime e = DateTime(d.year, d.month + m, d.day);
        if (e.isAfter(now) && e.difference(now).inDays <= 7) expW++;
      }

      custDebt = debtOverview['customerRemain'] ?? 0;
      suppDebt = debtOverview['supplierRemain'] ?? 0;
      partDebt = debtOverview['partnerRemain'] ?? 0;
      debtR = debtOverview['totalRemain'] ?? 0;

      final previousClosing = batch2[4] as Map<String, dynamic>?;
      final prevCashEnd = (previousClosing?['cashEnd'] as num?)?.toInt() ?? 0;
      final prevBankEnd = (previousClosing?['bankEnd'] as num?)?.toInt() ?? 0;
      final prevClosingTotal = prevCashEnd + prevBankEnd;

      final totalRecords =
          (recordCounts.first['repairs'] as int? ?? 0) +
          (recordCounts.first['sales'] as int? ?? 0) +
          (recordCounts.first['products'] as int? ?? 0);

      // Web bootstrap không cần nữa - đã xử lý ở _initialSetup và main.dart
      // Giữ lại flag để tránh duplicate call từ code cũ
      if (kIsWeb &&
          totalRecords == 0 &&
          !_cloudBootstrapTried &&
          !_cloudBootstrapRunning) {
        _cloudBootstrapTried = true;
        debugPrint(
          '🌐 HomeView: DB vẫn trống sau sync, thử bootstrap lần cuối...',
        );
        // ignore: unawaited_futures
        _bootstrapCoreDataFromCloud();
      }

      debugPrint(
        'HomeView: _loadStats total took ${stopwatch.elapsedMilliseconds}ms',
      );

      if (mounted) {
        setState(() {
          totalPendingRepair = pendingR;
          pendingApprovalCount = pendingApprovalR;
          todaySaleCount = soldT;
          totalDebtRemain = debtR;
          _customerDebtRemain = custDebt;
          _supplierDebtRemain = suppDebt;
          _partnerDebtRemain = partDebt;
          expiringWarranties = expW;
          _todayTotalIn = analysis.totalIn;
          _todayTotalOut = analysis.totalOut;
          _todayNetProfit = analysis.netProfit;
          _todaySalesProfit = analysis.saleProfit;
          _todayRepairProfit = analysis.repairProfit;
          _todayRepairCount = fRepairs.length;
          _todaySaleOrderCount = fSales.length;
          _todayExpenseCount = fExpenses
              .where((e) => (e['type'] as String? ?? '').toUpperCase() != 'THU')
              .length;
          _todayStockInCost = analysis.importOut;
          _todayDebtPaidToSupplier = analysis.supplierPaid;
          _todayExpenseOnly = analysis.expenseOut;
          _todaySaleIncome = analysis.saleIncome;
          _todayRepairIncome = analysis.repairIncome;
          _todayDebtCollected = analysis.debtCollected;
          _todayMiscIncome = analysis.miscIncome;
          _todayImportOut = analysis.importOut;
          _todayPartnerPaid = analysis.partnerPaid;
          _todayRepairPartsCostFund = analysis.repairPartsCostFund;
          _todaySaleCost = analysis.saleCost;
          _todayRepairCost = analysis.repairCost;
          _todaySettlementIncome = analysis.settlementIncome;
          _todayRefundOut = analysis.refundOut;
          _todayReturnCost = analysis.returnCost;
          _previousClosingTotal = prevClosingTotal;
        });
      }

      // === DEFERRED: Load chat info and reminders (don't block dashboard) ===
      _loadChatInfo();
      _loadReminderCount();
    } catch (e) {
      debugPrint('HomeView._loadStats error: $e');
    } finally {
      _isLoadingStats = false;
    }
  }

  Future<void> _loadReminderCount() async {
    try {
      final count = await ReminderService.getTotalReminderCount(
        role: widget.role,
        permissions: _permissions,
      );
      if (mounted && count != _totalReminderCount) {
        setState(() => _totalReminderCount = count);
      }
    } catch (e) {
      debugPrint('HomeView._loadReminderCount error: $e');
    }
  }

  void _normalizeTimestampFields(Map<String, dynamic> data) {
    const fields = [
      'createdAt',
      'updatedAt',
      'soldAt',
      'deliveredAt',
      'paidAt',
      'date',
      'checkInAt',
      'checkOutAt',
      'approvedAt',
      'settlementReceivedAt',
      'settlementPlannedAt',
      'lastVisitAt',
    ];
    for (final key in fields) {
      final v = data[key];
      if (v is Timestamp) {
        data[key] = v.millisecondsSinceEpoch;
      }
    }
  }

  Future<void> _bootstrapCoreDataFromCloud() async {
    if (_cloudBootstrapRunning) return;
    _cloudBootstrapRunning = true;
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null || shopId.isEmpty) return;

      debugPrint('🌐 HomeView bootstrap: start for shopId=$shopId');

      final fs = FirebaseFirestore.instance;

      final repairsSnap = await fs
          .collection('repairs')
          .where('shopId', isEqualTo: shopId)
          .get();
      for (final doc in repairsSnap.docs) {
        final data = EncryptionService.decryptMap(
          Map<String, dynamic>.from(doc.data()),
        );
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;
        _normalizeTimestampFields(data);
        await db.upsertRepair(Repair.fromMap(data));
      }

      final productsSnap = await fs
          .collection('products')
          .where('shopId', isEqualTo: shopId)
          .get();
      for (final doc in productsSnap.docs) {
        final data = EncryptionService.decryptMap(
          Map<String, dynamic>.from(doc.data()),
        );
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;
        _normalizeTimestampFields(data);
        await db.upsertProduct(Product.fromMap(data));
      }

      final salesSnap = await fs
          .collection('sales')
          .where('shopId', isEqualTo: shopId)
          .get();
      for (final doc in salesSnap.docs) {
        final data = EncryptionService.decryptMap(
          Map<String, dynamic>.from(doc.data()),
        );
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;
        _normalizeTimestampFields(data);
        await db.upsertSale(SaleOrder.fromMap(data));
      }

      final expensesSnap = await fs
          .collection('expenses')
          .where('shopId', isEqualTo: shopId)
          .get();
      for (final doc in expensesSnap.docs) {
        final data = EncryptionService.decryptMap(
          Map<String, dynamic>.from(doc.data()),
        );
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;
        _normalizeTimestampFields(data);
        await db.upsertExpense(Expense.fromMap(data));
      }

      final debtsSnap = await fs
          .collection('debts')
          .where('shopId', isEqualTo: shopId)
          .get();
      for (final doc in debtsSnap.docs) {
        final data = EncryptionService.decryptMap(
          Map<String, dynamic>.from(doc.data()),
        );
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;
        _normalizeTimestampFields(data);
        await db.upsertDebt(Debt.fromMap(data));
      }

      debugPrint(
        '🌐 HomeView bootstrap: repairs=${repairsSnap.docs.length}, products=${productsSnap.docs.length}, sales=${salesSnap.docs.length}',
      );

      if (mounted) {
        _debouncedLoadStats();
      }
    } catch (e) {
      debugPrint('🌐 HomeView bootstrap failed: $e');
    } finally {
      _cloudBootstrapRunning = false;
    }
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
    final loc = AppLocalizations.of(context)!;
    final shouldInterceptRootBack =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final homeScaffold = Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: _getTabTitle(_currentIndex),
        subtitle: _shopName.isNotEmpty ? _shopName : null,
        showBackButton: false,
        centerTitle: false,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Icon(Icons.store_rounded, color: Colors.white, size: 20),
        ),
        actions: [
          NotificationBadge(
            unreadCount: FirestoreService.getUnreadCount(),
            child: IconButton(
              onPressed: () => _pushRoute(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsView()),
              ),
              icon: Icon(
                Icons.notifications,
                color: _notificationWorking
                    ? Colors.greenAccent
                    : Colors.white70,
              ),
              tooltip: _notificationWorking
                  ? loc.notificationActive
                  : loc.notificationInactive,
            ),
          ),
          IconButton(
            onPressed: () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => QrScanView(role: widget.role)),
            ),
            icon: const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
            ),
          ),
          IconButton(
            onPressed: () => _pushRoute(
              context,
              MaterialPageRoute(
                builder: (_) => GlobalSearchView(role: widget.role),
              ),
            ),
            icon: const Icon(Icons.search, color: Colors.white, size: 22),
            tooltip: loc.searchWholeApp,
          ),
          // Simple sync indicator - tự động sync, tap để force sync
          const SimpleSyncIndicator(),
          IconButton(
            onPressed: () => _handleLogout(context),
            icon: const Icon(Icons.logout_rounded, color: AppColors.error),
          ),
        ],
      ),
      body: _buildResponsiveBody(),
      bottomNavigationBar: _buildResponsiveBottomNav(),
    );

    if (!shouldInterceptRootBack) {
      return homeScaffold;
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _maybePopCurrentTabNavigator()) {
          return;
        }
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(loc.exitApp),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(loc.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(loc.exit),
              ),
            ],
          ),
        );
        if (ok == true) {
          await SystemNavigator.pop();
        }
      },
      child: homeScaffold,
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    // Check for unsynced data before logout
    try {
      final unsynced = await DBHelper().countAllUnsyncedData();
      final totalUnsynced = unsynced.values.fold<int>(0, (a, b) => a + b);

      if (totalUnsynced > 0 && mounted) {
        final details = unsynced.entries
            .map((e) => '• ${e.key}: ${e.value} bản ghi')
            .join('\n');
        final shouldContinue = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 28,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dữ liệu chưa đồng bộ!',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: Text(
              'Có $totalUnsynced bản ghi chưa được đồng bộ lên server:\n\n$details\n\n'
              'Nếu đăng xuất ngay, dữ liệu này sẽ BỊ MẤT.\n\n'
              'Hãy kiểm tra kết nối mạng và thử đồng bộ trước.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Hủy'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  // Try force sync
                  NotificationService.showSnackBar(
                    'Đang đồng bộ...',
                    color: Colors.blue,
                  );
                  try {
                    await SyncOrchestrator().syncAll();
                    // Re-check
                    final remaining = await DBHelper().countAllUnsyncedData();
                    final remainCount = remaining.values.fold<int>(
                      0,
                      (a, b) => a + b,
                    );
                    if (remainCount == 0) {
                      NotificationService.showSnackBar(
                        '✅ Đã đồng bộ xong!',
                        color: Colors.green,
                      );
                    } else {
                      NotificationService.showSnackBar(
                        '⚠️ Còn $remainCount bản ghi chưa sync. Kiểm tra mạng.',
                        color: Colors.orange,
                      );
                    }
                  } catch (e) {
                    NotificationService.showSnackBar(
                      '❌ Lỗi sync: $e',
                      color: Colors.red,
                    );
                  }
                },
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Thử đồng bộ'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Vẫn đăng xuất'),
              ),
            ],
          ),
        );
        if (shouldContinue != true) return;
      }
    } catch (e) {
      debugPrint('Logout pre-check error (skipping): $e');
    }

    // Always sign out — cleanup failures must not block logout
    try {
      await SyncService.cancelAllSubscriptions();
    } catch (_) {}
    try {
      EncryptionService.reset();
    } catch (_) {}
    try {
      UserService.clearCache();
    } catch (_) {}
    try {
      CurrentShopService().clear();
    } catch (_) {}
    try {
      UserService.setAdminSelectedShop(null);
    } catch (_) {}
    try {
      await DBHelper().clearAllData();
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      debugPrint('Logout signOut error: $e');
    }
  }

  /// Responsive body: NavigationRail on wide screens, IndexedStack on mobile
  Widget _buildResponsiveBody() {
    final r = context.responsive;
    if (r.isWideLayout && _navItems.length >= 2) {
      return Row(
        children: [
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight:
                    MediaQuery.of(context).size.height -
                    kToolbarHeight -
                    MediaQuery.of(context).padding.top,
              ),
              child: IntrinsicHeight(
                child: NavigationRail(
                  selectedIndex: _currentIndex.clamp(0, _navItems.length - 1),
                  onDestinationSelected: (index) {
                    HapticFeedback.lightImpact();
                    _setCurrentTab(index);
                  },
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: AppColors.surface,
                  selectedIconTheme: const IconThemeData(
                    color: AppColors.primary,
                  ),
                  selectedLabelTextStyle: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: r.isDesktop ? 13 : 11,
                  ),
                  unselectedLabelTextStyle: TextStyle(
                    color: AppColors.onSurface.withOpacity(0.6),
                    fontSize: r.isDesktop ? 12 : 10,
                  ),
                  destinations: _navItems.map((item) {
                    return NavigationRailDestination(
                      icon: item.icon,
                      selectedIcon: item.activeIcon,
                      label: Text(item.label ?? ''),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: List.generate(_tabWidgets.length, _buildTabHost),
            ),
          ),
        ],
      );
    }
    return IndexedStack(
      index: _currentIndex,
      children: List.generate(_tabWidgets.length, _buildTabHost),
    );
  }

  /// Bottom nav: only show on narrow screens
  Widget? _buildResponsiveBottomNav() {
    final r = context.responsive;
    if (r.isWideLayout || _navItems.length < 2) return null;
    return Container(
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
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
    );
  }

  /// Helper to extract IconData from Icon or Badge widget
  IconData? _extractIconData(Widget widget) {
    if (widget is Icon) {
      return widget.icon;
    }
    if (widget is Badge && widget.child is Icon) {
      return (widget.child as Icon).icon;
    }
    return null;
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

    // Safely extract IconData from either Icon or Badge
    final iconData = isSelected
        ? _extractIconData(item.activeIcon)
        : _extractIconData(item.icon);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _setCurrentTab(index);
        },
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: EdgeInsets.all(isSelected ? 7 : 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: AnimatedScale(
                  scale: isSelected ? 1.1 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    iconData ?? Icons.circle,
                    size: isSelected ? 22 : 20,
                    color: isSelected
                        ? color
                        : AppColors.onSurface.withOpacity(0.5),
                  ),
                ),
              ),
              const SizedBox(height: 2),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(
                  color: isSelected
                      ? color
                      : AppColors.onSurface.withOpacity(0.5),
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  fontSize: isSelected
                      ? AppTextStyles.captionSize
                      : AppTextStyles.overlineSize,
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
    return GestureDetector(
      onLongPress: _openDashboardSettings,
      child: RefreshIndicator(
        key: const ValueKey('home_tab'), // Stable key to preserve scroll state
        onRefresh: () => _syncNow(),
        child: ResponsiveCenter(
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: context.responsive.horizontalPadding,
              vertical: 10,
            ),
            children: [
              if (_shopLocked)
                Card(
                  color: Colors.red.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.lock, color: Colors.red),
                    title: const Text(
                      "CỬA HÀNG BỊ KHÓA",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "Liên hệ Admin để mở khóa",
                      style: AppTextStyles.body1,
                    ),
                  ),
                ),
              // MODULAR DASHBOARD - render cards based on config
              ..._buildModularDashboard(),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }

  /// Build dashboard cards based on saved config order & visibility
  List<Widget> _buildModularDashboard() {
    // If config not loaded yet, show lightweight defaults (no greeting/finance)
    if (!_dashboardConfigLoaded || _dashboardConfigs.isEmpty) {
      return [
        _buildTodayActivityDashboardCard(),
        _buildChatCard(),
        _buildUnifiedShortcuts(),
        _buildAlerts(),
        _buildUserGuideShortcut(),
      ];
    }

    final widgets = <Widget>[];

    // Customize button at top
    widgets.add(_buildCustomizeDashboardButton());

    for (final config in _dashboardConfigs) {
      if (!config.visible) continue;

      // Role-based AND permission-based filtering for finance cards
      final canViewFinance =
          hasFullAccess || _permissions['allowViewRevenue'] == true;
      if (config.requiresFinanceAccess && !canViewFinance) {
        continue;
      }

      switch (config.type) {
        case DashboardCardType.greeting:
          widgets.add(_buildGreetingCard());
          break;
        case DashboardCardType.actionRequired:
          final canRepair =
              hasFullAccess || _permissions['allowViewRepairs'] == true;
          final canStock =
              hasFullAccess || _permissions['allowViewInventory'] == true;
          final canWarranty =
              hasFullAccess || _permissions['allowViewWarranty'] == true;
          widgets.add(
            ActionRequiredCard(
              key: const ValueKey('action_required'),
              enableRepair: _enableRepair && canRepair,
              enableWarranty: _enableWarranty && canWarranty,
              enableExpiry: _enableExpiry && canStock,
              onPendingRepairsTap: canRepair
                  ? () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderListView(
                          role: widget.role,
                          statusFilter: const [1, 2],
                        ),
                      ),
                    )
                  : null,
              onPendingStockTap: canStock
                  ? () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PendingStockListView(),
                      ),
                    )
                  : null,
              onWarrantyTap: canWarranty
                  ? () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const WarrantyView()),
                    )
                  : null,
              reminderCount: _totalReminderCount,
              onReminderTap: () => _pushRoute(
                context,
                MaterialPageRoute(
                  builder: (_) => RemindersView(
                    role: widget.role,
                    permissions: _permissions,
                  ),
                ),
              ).then((_) => _loadReminderCount()),
            ),
          );
          break;
        case DashboardCardType.quickActions:
          widgets.add(_buildUnifiedShortcuts());
          break;
        case DashboardCardType.financeSummary:
          // Merged into financeDetail below
          break;
        case DashboardCardType.financeDetail:
          widgets.add(
            FinanceSummaryCard(
              key: const ValueKey('finance_summary'),
              revenue:
                  _todaySaleIncome +
                  _todaySettlementIncome +
                  _todayRepairIncome,
              netProfit: _todayNetProfit,
              currentFund:
                  _previousClosingTotal + _todayTotalIn - _todayTotalOut,
              onTap: () => _pushRoute(
                context,
                MaterialPageRoute(builder: (_) => const CashClosingView()),
              ),
            ),
          );
          widgets.add(_buildDashboardOverview());
          widgets.add(const SizedBox(height: 10));
          break;
        case DashboardCardType.activityFeed:
          widgets.add(
            ActivityFeedCard(
              key: const ValueKey('activity_feed'),
              enableRepair: _enableRepair,
              onViewAll: () => _pushRoute(
                context,
                MaterialPageRoute(builder: (_) => const RecentActivityView()),
              ),
            ),
          );
          break;
        case DashboardCardType.chat:
          widgets.add(_buildChatCard());
          break;
        case DashboardCardType.alerts:
          widgets.add(_buildAlerts());
          break;
        case DashboardCardType.userGuide:
          widgets.add(_buildUserGuideShortcut());
          break;
        case DashboardCardType.financeShortcuts:
          widgets.add(_buildFinanceShortcuts());
          break;
        case DashboardCardType.todayActivity:
          // Today's operational activity card
          break;
        case DashboardCardType.dailyReport:
          widgets.add(_buildDailyReportCard());
          break;
      }
    }

    return widgets;
  }

  /// Navigate to dashboard customization settings
  Future<void> _openDashboardSettings() async {
    HapticFeedback.mediumImpact();
    final result = await Navigator.push<dynamic>(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardSettingsView(
          role: widget.role,
          currentConfig: _dashboardConfigs,
          currentShortcuts: _shortcutConfigs,
        ),
      ),
    );
    // Apply configs directly from result (no re-reading SharedPreferences)
    if (result is Map && mounted) {
      setState(() {
        if (result['configs'] is List<DashboardCardConfig>) {
          _dashboardConfigs = result['configs'] as List<DashboardCardConfig>;
          _dashboardConfigLoaded = true;
        }
        if (result['shortcuts'] is List<ShortcutConfig>) {
          _shortcutConfigs = result['shortcuts'] as List<ShortcutConfig>;
          _shortcutConfigLoaded = true;
        }
      });
    }
  }

  /// Compact button to open dashboard customization
  Widget _buildCustomizeDashboardButton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: _openDashboardSettings,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.dashboard_customize,
                size: 14,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 6),
              Text(
                'Tùy chỉnh giao diện Home',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Widget lời chào người dùng - hiển thị tên và vai trò
  Widget _buildGreetingCard() {
    final loc = AppLocalizations.of(context)!;
    // Xác định lời chào theo thời gian
    final hour = DateTime.now().hour;
    String greeting;
    IconData greetingIcon;
    if (hour < 12) {
      greeting = loc.goodMorning;
      greetingIcon = Icons.wb_sunny_outlined;
    } else if (hour < 18) {
      greeting = loc.goodAfternoon;
      greetingIcon = Icons.wb_sunny;
    } else {
      greeting = loc.goodEvening;
      greetingIcon = Icons.nightlight_outlined;
    }

    // Xác định vai trò hiển thị
    String roleText;
    Color roleColor;
    IconData roleIcon;
    if (_isSuperAdmin) {
      roleText = loc.adminRole;
      roleColor = Colors.blue;
      roleIcon = Icons.admin_panel_settings;
    } else if (_effectiveRole == 'owner') {
      roleText = loc.ownerRole;
      roleColor = Colors.orange;
      roleIcon = Icons.store;
    } else if (_effectiveRole == 'admin' || _effectiveRole == 'manager') {
      roleText = loc.managerRole;
      roleColor = Colors.blue;
      roleIcon = Icons.manage_accounts;
    } else if (_effectiveRole == 'technician') {
      roleText = loc.technicianRole;
      roleColor = Colors.teal;
      roleIcon = Icons.build;
    } else {
      roleText = loc.employeeRole;
      roleColor = Colors.green;
      roleIcon = Icons.person;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dòng lời chào
          Row(
            children: [
              Icon(
                greetingIcon,
                color: Colors.white.withOpacity(0.9),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                greeting,
                style: AppTextStyles.headline6.copyWith(
                  color: Colors.white.withOpacity(0.9),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('EEEE, dd/MM', 'vi').format(DateTime.now()),
                style: AppTextStyles.caption.copyWith(
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Tên người dùng
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _userName.isNotEmpty
                          ? _userName
                          : (FirebaseAuth.instance.currentUser?.email
                                    ?.split('@')
                                    .first ??
                                loc.userLabel),
                      style: AppTextStyles.headline3.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: roleColor.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(roleIcon, color: Colors.white, size: 12),
                              const SizedBox(width: 4),
                              Text(
                                roleText,
                                style: AppTextStyles.body1.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_shopName.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '• $_shopName',
                              style: AppTextStyles.subtitle1.copyWith(
                                color: Colors.white.withOpacity(0.85),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNewStaffBannerSimple() {
    final loc = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade400, Colors.blue.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withOpacity(0.25),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.waving_hand, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.welcomeNewStaff,
                  style: AppTextStyles.headline3.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  loc.newStaffSyncGuide,
                  style: AppTextStyles.subtitle1.copyWith(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
        ],
      ),
    );
  }

  // Giữ lại _buildNewStaffBanner cũ nhưng không dùng - có thể xóa sau
  Widget _buildNewStaffBanner() {
    final loc = AppLocalizations.of(context)!;
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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.welcomeNewStaff,
                      style: AppTextStyles.headline3.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      loc.downloadShopDataToStart,
                      style: AppTextStyles.subtitle1.copyWith(
                        color: Colors.white70,
                      ),
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
              label: Text(
                loc.downloadShopDataTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
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
    final loc = AppLocalizations.of(context)!;
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
            Expanded(
              child: Text(
                loc.downloadShopDataTitle,
                style: const TextStyle(fontWeight: FontWeight.bold),
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
                style: AppTextStyles.headline4.copyWith(color: Colors.black87),
                children: [
                  TextSpan(text: '${loc.downloadDataOf} '),
                  TextSpan(
                    text: '"$shopName"',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  TextSpan(text: ' ${loc.fromCloudToThisDevice}'),
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
                  _buildDataItem(Icons.build, loc.repairOrdersDataItem),
                  _buildDataItem(Icons.shopping_cart, loc.saleOrdersDataItem),
                  _buildDataItem(Icons.inventory, loc.productsInStock),
                  _buildDataItem(Icons.receipt, loc.debtsAndExpensesDataItem),
                  _buildDataItem(
                    Icons.people,
                    loc.customersAndSuppliersDataItem,
                  ),
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
                      loc.onlyDownloadThisShopData,
                      style: AppTextStyles.body1.copyWith(
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              loc.processMayTakeFewMinutes,
              style: AppTextStyles.body1.copyWith(
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel.toUpperCase()),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download, size: 18),
            label: Text(loc.startDownload),
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
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  loc.downloadingShopData,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  loc.pleaseWait,
                  style: AppTextStyles.subtitle1.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      try {
        await SyncService.downloadAllFromCloud(force: true);
        try {
          await _loadStats();
        } catch (statsError) {
          debugPrint('Error loading stats after download: $statsError');
        }
        if (mounted) Navigator.of(context).pop(); // Close loading dialog
        NotificationService.showSnackBar(
          "✅ ${loc.downloadSuccess}",
          color: Colors.green,
        );
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // Close loading dialog
        NotificationService.showSnackBar(
          "❌ ${loc.downloadError(e.toString())}",
          color: Colors.red,
        );
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
          Text(text, style: AppTextStyles.headline5),
        ],
      ),
    );
  }

  /// Chat card - hiển thị ngay dưới lời chào với badge tin nhắn chưa đọc
  Widget _buildChatCard() {
    if (!(hasFullAccess || _permissions['allowViewChat'] == true)) {
      return const SizedBox();
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        color: Colors.cyan.shade50,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.cyan.shade200),
        ),
        child: InkWell(
          onTap: () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const AdvancedChatView()),
          ),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Icon với badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.cyan.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.chat_bubble_rounded,
                        color: Colors.cyan.shade700,
                        size: 20,
                      ),
                    ),
                    if (unreadChatCount > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            unreadChatCount > 99 ? '99+' : '$unreadChatCount',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            "CHAT NỘI BỘ",
                            style: AppTextStyles.body2.copyWith(
                              color: Colors.cyan.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (unreadChatCount > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$unreadChatCount mới',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _latestChatMessage.isNotEmpty
                            ? "${_latestChatSender.isNotEmpty ? '$_latestChatSender: ' : ''}${_latestChatMessage.length > 45 ? '${_latestChatMessage.substring(0, 45)}...' : _latestChatMessage}"
                            : "Chưa có tin nhắn nào",
                        style: AppTextStyles.caption.copyWith(
                          color: unreadChatCount > 0
                              ? Colors.cyan.shade700
                              : Colors.grey.shade600,
                          fontWeight: unreadChatCount > 0
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Colors.cyan.shade400,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // QUICK EXPENSE/INCOME DIALOGS — shortcuts from home screen
  // ═══════════════════════════════════════════════════════════════════════════

  bool _quickSaving = false;

  void _showQuickExpenseDialog() async {
    if (_quickSaving) return;

    // Check if day is already closed
    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(
      today.millisecondsSinceEpoch,
    );
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể thêm chi phí mới.',
        color: Colors.red,
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final titleC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    String category = "PHÁT SINH";
    String payMethod = "TIỀN MẶT";

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.remove_circle,
                    color: Colors.red.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "GHI CHI PHÍ NHANH",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "PHÂN LOẠI",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          [
                                "CỐ ĐỊNH",
                                "PHÁT SINH",
                                "LƯƠNG",
                                "MẶT BẰNG",
                                "ĐIỆN NƯỚC",
                                "KHÁC",
                              ]
                              .map(
                                (c) => ChoiceChip(
                                  label: Text(
                                    c,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  selected: category == c,
                                  onSelected: (v) => setS(() => category = c),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: "Nội dung chi *",
                        prefixIcon: Icon(Icons.edit_note, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Nhập nội dung'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    CurrencyTextField(
                      controller: amountC,
                      label: "Số tiền (VNĐ) *",
                      icon: Icons.payments,
                      validator: (v) => input_money.MoneyUtils.validateAmount(
                        v ?? '',
                        min: 1,
                        fieldName: 'Số tiền',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteC,
                      decoration: const InputDecoration(
                        labelText: "Ghi chú",
                        prefixIcon: Icon(Icons.description, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "THANH TOÁN",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: ["TIỀN MẶT", "CHUYỂN KHOẢN"]
                          .map(
                            (m) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: ChoiceChip(
                                  label: Text(
                                    m,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  selected: payMethod == m,
                                  onSelected: (v) => setS(() => payMethod = m),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("HỦY"),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: _quickSaving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false))
                          return;
                        setState(() => _quickSaving = true);
                        final amount = input_money.MoneyUtils.parseCurrency(
                          amountC.text,
                        );
                        final user = FirebaseAuth.instance.currentUser;
                        final method = payMethod == 'CHUYỂN KHOẢN'
                            ? PaymentMethod.transfer
                            : PaymentMethod.cash;
                        final txRef =
                            'home_expense_${DateTime.now().millisecondsSinceEpoch}_${category.trim().toUpperCase()}_${method.code}_${amount}_${titleC.text.trim().toUpperCase()}';
                        Navigator.of(ctx).pop();
                        final result =
                            await PaymentIntentService.executePaymentDirect(
                              type:
                                  (category == 'ĐIỆN NƯỚC' ||
                                      category == 'INTERNET')
                                  ? PaymentIntentType.utilityExpense
                                  : PaymentIntentType.operatingExpense,
                              amount: amount,
                              paymentMethod: method,
                              description:
                                  '${titleC.text.toUpperCase()}${noteC.text.isNotEmpty ? " - ${noteC.text}" : ""}',
                              executedBy:
                                  user?.displayName ?? user?.email ?? 'unknown',
                              referenceId: txRef,
                              referenceType: 'home_quick_expense',
                              notes: noteC.text.trim().isEmpty
                                  ? null
                                  : noteC.text.trim(),
                              idempotencyKey: txRef,
                              metadata: {
                                'category': category,
                                'title': titleC.text.toUpperCase(),
                                'note': noteC.text,
                              },
                            );
                        if (result != null && result.success) {
                          EventBus().emit('expenses_changed');
                          NotificationService.showSnackBar(
                            "✅ Đã lưu chi phí!",
                            color: AppColors.success,
                          );
                        }
                        if (mounted) setState(() => _quickSaving = false);
                      },
                icon: const Icon(Icons.save, size: 16),
                label: const Text("LƯU CHI PHÍ"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showQuickIncomeDialog() async {
    if (_quickSaving) return;

    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(
      today.millisecondsSinceEpoch,
    );
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể thêm thu phát sinh.',
        color: Colors.red,
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final titleC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    String category = "PHÁT SINH";
    String payMethod = "TIỀN MẶT";

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.add_circle,
                    color: Colors.green.shade700,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    "GHI THU PHÁT SINH",
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "PHÂN LOẠI",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children:
                          [
                                "PHÁT SINH",
                                "DỊCH VỤ",
                                "HOÀN TIỀN",
                                "BÁN TÀI SẢN",
                                "KHÁC",
                              ]
                              .map(
                                (c) => ChoiceChip(
                                  label: Text(
                                    c,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  selected: category == c,
                                  onSelected: (v) => setS(() => category = c),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                              )
                              .toList(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: "Nội dung thu *",
                        prefixIcon: Icon(Icons.edit_note, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Nhập nội dung'
                          : null,
                    ),
                    const SizedBox(height: 10),
                    CurrencyTextField(
                      controller: amountC,
                      label: "Số tiền (VNĐ) *",
                      icon: Icons.payments,
                      validator: (v) => input_money.MoneyUtils.validateAmount(
                        v ?? '',
                        min: 1,
                        fieldName: 'Số tiền',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteC,
                      decoration: const InputDecoration(
                        labelText: "Ghi chú",
                        prefixIcon: Icon(Icons.description, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "THANH TOÁN",
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: ["TIỀN MẶT", "CHUYỂN KHOẢN"]
                          .map(
                            (m) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: ChoiceChip(
                                  label: Text(
                                    m,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  selected: payMethod == m,
                                  onSelected: (v) => setS(() => payMethod = m),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("HỦY"),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _quickSaving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false))
                          return;
                        setState(() => _quickSaving = true);
                        final amount = input_money.MoneyUtils.parseCurrency(
                          amountC.text,
                        );
                        final user = FirebaseAuth.instance.currentUser;
                        final method = payMethod == 'CHUYỂN KHOẢN'
                            ? PaymentMethod.transfer
                            : PaymentMethod.cash;
                        final txRef =
                            'home_income_${DateTime.now().millisecondsSinceEpoch}_${category.trim().toUpperCase()}_${method.code}_${amount}_${titleC.text.trim().toUpperCase()}';
                        Navigator.of(ctx).pop();
                        final result =
                            await PaymentIntentService.executePaymentDirect(
                              type: PaymentIntentType.otherIncome,
                              amount: amount,
                              paymentMethod: method,
                              description:
                                  '${titleC.text.toUpperCase()}${noteC.text.isNotEmpty ? " - ${noteC.text}" : ""}',
                              executedBy:
                                  user?.displayName ?? user?.email ?? 'unknown',
                              referenceId: txRef,
                              referenceType: 'home_quick_income',
                              notes: noteC.text.trim().isEmpty
                                  ? null
                                  : noteC.text.trim(),
                              idempotencyKey: txRef,
                              metadata: {
                                'category': category,
                                'title': titleC.text.toUpperCase(),
                                'note': noteC.text,
                              },
                            );
                        if (result != null && result.success) {
                          EventBus().emit('expenses_changed');
                          NotificationService.showSnackBar(
                            "✅ Đã lưu thu phát sinh!",
                            color: AppColors.success,
                          );
                        }
                        if (mounted) setState(() => _quickSaving = false);
                      },
                icon: const Icon(Icons.save, size: 16),
                label: const Text("LƯU THU"),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Check if current user has permission for a shortcut
  bool _hasShortcutPermission(ShortcutConfig config) {
    // Admin/Owner/SuperAdmin always have full access
    if (hasFullAccess) return true;
    final perm = config.requiredPermission;
    if (perm == null) return true; // No permission required (utility shortcuts)
    return _permissions[perm] == true;
  }

  /// Unified compact shortcuts section - uses configurable shortcut configs
  Widget _buildUnifiedShortcuts() {
    // Map ShortcutType → onTap callback (with permission check)
    VoidCallback? _getShortcutAction(ShortcutType type) {
      switch (type) {
        case ShortcutType.sellCreate:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const CreateSaleView()),
          );
        case ShortcutType.repairCreate:
          return _enableRepair
              ? () => _pushRoute(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateRepairOrderView(role: widget.role),
                  ),
                )
              : null;
        case ShortcutType.stockIn:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const SmartStockInView()),
          );
        case ShortcutType.pendingStock:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const PendingStockListView()),
          );
        case ShortcutType.saleList:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const SaleListView()),
          );
        case ShortcutType.repairList:
          return _enableRepair
              ? () => _pushRoute(
                  context,
                  MaterialPageRoute(builder: (_) => const OrderListView()),
                )
              : null;
        case ShortcutType.addExpense:
          return () => _openExpensePageAndAdd(isIncome: false);
        case ShortcutType.addIncome:
          return () => _openExpensePageAndAdd(isIncome: true);
        case ShortcutType.inventoryCheck:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const FastInventoryCheckView()),
          );
        case ShortcutType.report:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const RevenueView()),
          );
        case ShortcutType.attendance:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const AttendanceView()),
          );
        case ShortcutType.warranty:
          return _enableWarranty
              ? () => _pushRoute(
                  context,
                  MaterialPageRoute(builder: (_) => const WarrantyView()),
                )
              : null;
        case ShortcutType.cashClosing:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const CashClosingView()),
          );
        case ShortcutType.customers:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const CustomerManagementView()),
          );
        case ShortcutType.suppliers:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const SupplierListView()),
          );
        case ShortcutType.debt:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const DebtView()),
          );
        case ShortcutType.qrScan:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const QrScanView()),
          );
        case ShortcutType.financialReport:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const FinancialReportView()),
          );
        case ShortcutType.activityLog:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const RecentActivityView()),
          );
        case ShortcutType.printer:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const PrinterSettingsView()),
          );
        case ShortcutType.quickCodes:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const QuickInputCodesView()),
          );
        case ShortcutType.bankInstallment:
          return () => _pushRoute(
            context,
            MaterialPageRoute(
              builder: (_) => const BankInstallmentReportView(),
            ),
          );
        case ShortcutType.globalSearch:
          return () => _pushRoute(
            context,
            MaterialPageRoute(
              builder: (_) => GlobalSearchView(role: widget.role),
            ),
          );
        case ShortcutType.staff:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const StaffListView()),
          );
        case ShortcutType.expenses:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const ExpenseView()),
          );
        case ShortcutType.expiryManage:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const ExpiryManagementView()),
          );
        case ShortcutType.paymentRequest:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const PaymentRequestChatView()),
          );
        case ShortcutType.dailyReport:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const DailyActivityReportView()),
          );
        case ShortcutType.importHistory:
          return () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const ImportHistoryView()),
          );
      }
    }

    // In edit mode, show ALL shortcuts (visible + hidden) for reorder & toggle
    if (_shortcutEditMode && _shortcutConfigLoaded) {
      return _buildShortcutEditMode();
    }

    // Build visible items from config (with permission filtering)
    final List<_ShortcutItem> items;
    if (_shortcutConfigLoaded && _shortcutConfigs.isNotEmpty) {
      items = <_ShortcutItem>[];
      for (final config in _shortcutConfigs) {
        if (!config.visible) continue;
        if (config.requiresRepair && !_enableRepair) continue;
        if (config.requiresWarranty && !_enableWarranty) continue;
        // Permission check: skip shortcuts the user doesn't have access to
        if (!_hasShortcutPermission(config)) continue;
        final action = _getShortcutAction(config.type);
        if (action == null) continue;
        items.add(
          _ShortcutItem(config.icon, config.displayName, config.color, action),
        );
      }
    } else {
      // Fallback: no config loaded yet - build defaults with permission checks
      final _p = _permissions;
      final _fa = hasFullAccess;
      bool _ok(String? perm) => _fa || perm == null || (_p[perm] == true);
      items = <_ShortcutItem>[
        if (_ok('allowViewSales'))
          _ShortcutItem(
            Icons.add_shopping_cart,
            'Bán hàng',
            Colors.green,
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const CreateSaleView()),
            ),
          ),
        if (_enableRepair && _ok('allowViewRepairs'))
          _ShortcutItem(
            Icons.build_circle,
            'Đơn sửa',
            Colors.blue,
            () => _pushRoute(
              context,
              MaterialPageRoute(
                builder: (_) => CreateRepairOrderView(role: widget.role),
              ),
            ),
          ),
        if (_ok('allowViewInventory'))
          _ShortcutItem(
            Icons.add_box,
            'Nhập kho',
            Colors.teal,
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const SmartStockInView()),
            ),
          ),
        if (_ok('allowViewInventory'))
          _ShortcutItem(
            Icons.pending_actions,
            'Chờ XN',
            Colors.orange,
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const PendingStockListView()),
            ),
          ),
        if (_ok('allowViewSales'))
          _ShortcutItem(
            Icons.receipt_long,
            'Đơn bán',
            Colors.indigo,
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const SaleListView()),
            ),
          ),
        if (_enableRepair && _ok('allowViewRepairs'))
          _ShortcutItem(
            Icons.list_alt,
            'DS sửa',
            Colors.deepPurple,
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const OrderListView()),
            ),
          ),
        if (_ok('allowViewExpenses'))
          _ShortcutItem(
            Icons.remove_circle_outline,
            'Thêm chi',
            Colors.red,
            () => _openExpensePageAndAdd(isIncome: false),
          ),
        if (_ok('allowViewRevenue'))
          _ShortcutItem(
            Icons.add_circle_outline,
            'Thêm thu',
            Colors.green.shade700,
            () => _openExpensePageAndAdd(isIncome: true),
          ),
        if (_ok('allowViewInventory'))
          _ShortcutItem(
            Icons.qr_code_scanner,
            'Kiểm kho',
            Colors.cyan,
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const FastInventoryCheckView()),
            ),
          ),
        if (_ok('allowViewRevenue'))
          _ShortcutItem(
            Icons.bar_chart,
            'Báo cáo',
            Colors.purple,
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const RevenueView()),
            ),
          ),
        if (_ok('allowViewAttendance'))
          _ShortcutItem(
            Icons.access_time,
            'Chấm công',
            Colors.teal.shade700,
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const AttendanceView()),
            ),
          ),
        if (_enableWarranty && _ok('allowViewWarranty'))
          _ShortcutItem(
            Icons.shield,
            'Bảo hành',
            Colors.amber.shade800,
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const WarrantyView()),
            ),
          ),
        if (_ok('allowViewInventory'))
          _ShortcutItem(
            Icons.history_edu,
            'LS nhập kho',
            const Color(0xFF00897B),
            () => _pushRoute(
              context,
              MaterialPageRoute(builder: (_) => const ImportHistoryView()),
            ),
          ),
      ];
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(Icons.apps, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  'THAO TÁC NHANH',
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                if (_shortcutConfigLoaded)
                  InkWell(
                    onTap: () => setState(() => _shortcutEditMode = true),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.edit,
                            size: 12,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            'Sửa',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Grid layout - responsive columns
          LayoutBuilder(
            builder: (context, constraints) {
              final r = context.responsive;
              final cols = r.shortcutColumns;
              final iconSize = r.isDesktop ? 18.0 : (r.isTablet ? 18.0 : 20.0);
              final vPad = r.isDesktop ? 8.0 : 10.0;
              final fontSize = r.isDesktop ? 11.5 : 12.0;
              final itemWidth = (constraints.maxWidth - (cols - 1) * 8) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: itemWidth,
                        child: InkWell(
                          onTap: item.onTap,
                          onLongPress: _shortcutConfigLoaded
                              ? () {
                                  HapticFeedback.mediumImpact();
                                  setState(() => _shortcutEditMode = true);
                                }
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: EdgeInsets.symmetric(vertical: vPad),
                            decoration: BoxDecoration(
                              color: item.color.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: item.color.withOpacity(0.2),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: item.color.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    item.icon,
                                    color: item.color,
                                    size: iconSize,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    fontWeight: FontWeight.w600,
                                    color: item.color.withOpacity(0.9),
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  /// Edit mode for shortcuts: clean toggle grid + link to advanced settings
  Widget _buildShortcutEditMode() {
    final visibleCount = _shortcutConfigs.where((c) => c.visible).length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Icon(
                  Icons.dashboard_customize,
                  size: 14,
                  color: Colors.blue.shade700,
                ),
                const SizedBox(width: 6),
                Text(
                  'TÙY CHỈNH ($visibleCount đang hiện)',
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                // Done button - instant save, no await
                InkWell(
                  onTap: () {
                    // Fire-and-forget save - no spinner
                    ShortcutConfigService.saveConfig(_shortcutConfigs);
                    setState(() => _shortcutEditMode = false);
                    HapticFeedback.lightImpact();
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Xong',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Subtitle
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Nhấn để ẩn/hiện • Sắp xếp thứ tự trong Cài đặt',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ),

          // Unified grid: all shortcuts, visible ones colored, hidden ones greyed
          LayoutBuilder(
            builder: (context, constraints) {
              final cols = context.responsive.shortcutColumns;
              final itemWidth = (constraints.maxWidth - (cols - 1) * 8) / cols;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _shortcutConfigs.map((config) {
                  final isVisible = config.visible;
                  final color = isVisible ? config.color : Colors.grey.shade400;
                  final bgOpacity = isVisible ? 0.08 : 0.04;
                  final borderColor = isVisible
                      ? config.color.withOpacity(0.3)
                      : Colors.grey.shade200;

                  return SizedBox(
                    width: itemWidth,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() => config.visible = !config.visible);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: color.withOpacity(bgOpacity),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: borderColor),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Icon with check/uncheck badge
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: color.withOpacity(
                                      isVisible ? 0.15 : 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    config.icon,
                                    color: color.withOpacity(
                                      isVisible ? 1.0 : 0.5,
                                    ),
                                    size: 20,
                                  ),
                                ),
                                // Small badge: check (visible) or empty circle (hidden)
                                Positioned(
                                  right: -4,
                                  top: -4,
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 16,
                                    height: 16,
                                    decoration: BoxDecoration(
                                      color: isVisible
                                          ? Colors.green
                                          : Colors.grey.shade300,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      isVisible ? Icons.check : Icons.remove,
                                      color: Colors.white,
                                      size: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              config.displayName,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: color.withOpacity(isVisible ? 0.9 : 0.5),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          // Link to advanced settings (reorder, etc.)
          const SizedBox(height: 10),
          Center(
            child: InkWell(
              onTap: () {
                // Save current state first
                ShortcutConfigService.saveConfig(_shortcutConfigs);
                setState(() => _shortcutEditMode = false);
                _openDashboardSettings();
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune, size: 14, color: Colors.blue.shade400),
                    const SizedBox(width: 4),
                    Text(
                      'Sắp xếp thứ tự & cài đặt nâng cao',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: Colors.blue.shade400,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Widget hiển thị 2 lối tắt quan trọng: Hàng chờ xác nhận & Thanh toán
  Widget _buildPinnedShortcutsSection() {
    final loc = AppLocalizations.of(context)!;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.push_pin, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(
                  loc.quickAccess,
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          // Two rows of pinned cards
          Row(
            children: [
              // Hàng chờ xác nhận
              if (hasFullAccess || _permissions['allowViewInventory'] == true)
                Expanded(
                  child: _buildPinnedCard(
                    icon: Icons.pending_actions,
                    title: loc.pendingStockShort,
                    subtitle: loc.stockIn,
                    color: Colors.orange,
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PendingStockListView(),
                      ),
                    ),
                  ),
                ),
              if (hasFullAccess || _permissions['allowViewInventory'] == true)
                const SizedBox(width: 10),
              // Thu Chi
              if (hasFullAccess || _permissions['allowViewExpenses'] == true)
                Expanded(
                  child: _buildPinnedCard(
                    icon: Icons.account_balance_wallet,
                    title: loc.incomeExpense,
                    subtitle: 'Ghi thu chi',
                    color: Colors.green,
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const ExpenseView()),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Danh sách đơn bán
              if (hasFullAccess || _permissions['allowViewSales'] == true)
                Expanded(
                  child: _buildPinnedCard(
                    icon: Icons.receipt_long,
                    title: loc.salesOrder,
                    subtitle: loc.salesOrderList,
                    color: Colors.blue,
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const SaleListView()),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              // Danh sách đơn sửa - only show for electronics shops
              if (_enableRepair &&
                  (hasFullAccess || _permissions['allowViewRepairs'] == true))
                Expanded(
                  child: _buildPinnedCard(
                    icon: Icons.build_circle,
                    title: loc.repairOrderTitle,
                    subtitle: loc.repairOrderList,
                    color: Colors.deepPurple,
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const OrderListView()),
                    ),
                  ),
                ),
              // Alternative shortcut for non-electronics shops
              if (!_enableRepair &&
                  (hasFullAccess || _permissions['allowViewCustomers'] == true))
                Expanded(
                  child: _buildPinnedCard(
                    icon: Icons.people,
                    title: loc.customers,
                    subtitle: loc.customersAndSuppliers,
                    color: Colors.teal,
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CustomerManagementView(),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Widget card cho lối tắt được ghim
  Widget _buildPinnedCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.05),
                color.withValues(alpha: 0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.headline5.copyWith(
                        fontWeight: FontWeight.bold,
                        color: color.withValues(alpha: 0.9),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: color.withValues(alpha: 0.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Section header giống Settings View
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        title,
        style: AppTextStyles.caption.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.blueGrey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Hiển thị dialog hướng dẫn tính năng
  void _showFeatureGuide(
    String title,
    String description,
    IconData icon,
    Color color,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: AppTextStyles.headline2.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          description,
          style: AppTextStyles.headline4.copyWith(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'ĐÃ HIỂU',
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  /// Quick Actions mới theo style Settings
  Widget _buildQuickActionsNew() {
    final loc = AppLocalizations.of(context)!;
    bool _can(String perm) => hasFullAccess || _permissions[perm] == true;
    return Column(
      children: [
        // BÁN HÀNG
        if (_can('allowViewSales'))
          Card(
            color: Colors.green.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.green.shade200),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.add_shopping_cart,
                  color: Colors.green,
                  size: 20,
                ),
              ),
              title: Text(
                loc.createSaleOrder,
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                loc.sellProductsQuickly,
                style: AppTextStyles.caption,
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.green,
              ),
              onTap: () => _pushRoute(
                context,
                MaterialPageRoute(builder: (_) => const CreateSaleView()),
              ),
            ),
          ),
        if (_can('allowViewSales')) const SizedBox(height: 6),

        // SỬA CHỮA - Only show for electronics shops
        if (_enableRepair && _can('allowViewRepairs'))
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.blue.shade200),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.build_circle,
                  color: Colors.blue,
                  size: 20,
                ),
              ),
              title: Text(
                loc.createRepairOrder,
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                loc.receiveDeviceForRepair,
                style: AppTextStyles.caption,
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.blue,
              ),
              onTap: () => _pushRoute(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateRepairOrderView(role: widget.role),
                ),
              ),
            ),
          ),
        if (_enableRepair && _can('allowViewRepairs'))
          const SizedBox(height: 6),

        // Row: Nhập kho & Kiểm kho
        if (_can('allowViewInventory'))
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.green.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.green.shade300, width: 2),
                  ),
                  child: InkWell(
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SmartStockInView(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.add_box,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            loc.addStock,
                            style: AppTextStyles.subtitle1.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            loc.newStockIn,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
                  color: Colors.blue.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.blue.shade200),
                  ),
                  child: InkWell(
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FastInventoryCheckView(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner,
                              color: Colors.blue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            loc.checkInventory,
                            style: AppTextStyles.subtitle1.copyWith(
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            loc.scanToCheck,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (_can('allowViewInventory')) const SizedBox(height: 6),

        // Row: Chờ nhập & Lịch sử nhập kho
        if (_can('allowViewInventory'))
          Row(
            children: [
              Expanded(
                child: Card(
                  color: Colors.orange.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.orange.shade200),
                  ),
                  child: InkWell(
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const PendingStockListView(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.pending_actions,
                              color: Colors.orange,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Chờ nhập',
                            style: AppTextStyles.subtitle1.copyWith(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Phiếu đang chờ',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Card(
                  color: Colors.teal.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.teal.shade200),
                  ),
                  child: InkWell(
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ImportHistoryView(),
                      ),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.history,
                              color: Colors.teal,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Lịch sử nhập',
                            style: AppTextStyles.subtitle1.copyWith(
                              color: Colors.teal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Xem phiếu nhập kho',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        if (_can('allowViewInventory')) const SizedBox(height: 6),

        // Row: Báo cáo & Chấm công
        Row(
          children: [
            if (_can('allowViewRevenue'))
              Expanded(
                child: Card(
                  color: Colors.indigo.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.indigo.shade200),
                  ),
                  child: InkWell(
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const RevenueView()),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.bar_chart,
                              color: Colors.indigo,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            loc.report,
                            style: AppTextStyles.subtitle1.copyWith(
                              color: Colors.indigo,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            loc.revenue,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_can('allowViewRevenue')) const SizedBox(width: 8),
            if (_can('allowViewAttendance'))
              Expanded(
                child: Card(
                  color: Colors.teal.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.teal.shade200),
                  ),
                  child: InkWell(
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const AttendanceView()),
                    ),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.teal.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.access_time,
                              color: Colors.teal,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            loc.attendance,
                            style: AppTextStyles.subtitle1.copyWith(
                              color: Colors.teal,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            loc.checkInOut,
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),

        // Row: Thêm chi phí & Thêm thu phát sinh
        Row(
          children: [
            if (_can('allowViewExpenses'))
              Expanded(
                child: Card(
                  color: Colors.red.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.red.shade300, width: 2),
                  ),
                  child: InkWell(
                    onTap: () => _openExpensePageAndAdd(isIncome: false),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.remove_circle_outline,
                              color: Colors.red,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Thêm chi',
                            style: AppTextStyles.subtitle1.copyWith(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Ghi nhanh khoản chi',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_can('allowViewExpenses')) const SizedBox(width: 8),
            if (_can('allowViewRevenue'))
              Expanded(
                child: Card(
                  color: Colors.green.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: Colors.green.shade300, width: 2),
                  ),
                  child: InkWell(
                    onTap: () => _openExpensePageAndAdd(isIncome: true),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.green,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Thêm thu',
                            style: AppTextStyles.subtitle1.copyWith(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Ghi nhanh khoản thu',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),

        // BẢO HÀNH - Only show for electronics shops (repair/warranty enabled)
        if (_enableWarranty && _can('allowViewWarranty'))
          Card(
            color: Colors.amber.shade50,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: Colors.amber.shade200),
            ),
            child: ListTile(
              dense: true,
              visualDensity: const VisualDensity(vertical: -2),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.shield,
                  color: Colors.amber.shade800,
                  size: 18,
                ),
              ),
              title: Text(
                "BẢO HÀNH",
                style: TextStyle(
                  color: Colors.amber.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "Tra cứu bảo hành nhanh",
                style: AppTextStyles.caption,
              ),
              trailing: const Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: Colors.amber,
              ),
              onTap: () => _pushRoute(
                context,
                MaterialPageRoute(builder: (_) => const WarrantyView()),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildQuickActions() {
    final loc = AppLocalizations.of(context)!;
    bool _can(String perm) => hasFullAccess || _permissions[perm] == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            if (_can('allowViewSales'))
              Expanded(
                child: _quickActionButton(
                  loc.createSale,
                  Icons.add_shopping_cart,
                  AppColors.secondary,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateSaleView()),
                  ),
                ),
              ),
            if (_can('allowViewSales') && _can('allowViewRepairs'))
              const SizedBox(width: 8),
            if (_can('allowViewRepairs'))
              Expanded(
                child: _quickActionButton(
                  loc.createRepair,
                  Icons.build_circle,
                  AppColors.primary,
                  () => _pushRoute(
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
        if (_can('allowViewInventory'))
          Row(
            children: [
              Expanded(
                child: _quickActionButton(
                  loc.stockIn,
                  Icons.inventory,
                  AppColors.success,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      // Electronics: FastInventoryInputView (has IMEI)
                      // Fashion/Food: SmartStockInView (has size/color)
                      builder: (_) => _isElectronics
                          ? const FastInventoryInputView()
                          : const SmartStockInView(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _quickActionButton(
                  loc.checkInventory,
                  Icons.qr_code_scanner,
                  AppColors.warning,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FastInventoryCheckView(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_can('allowViewRevenue'))
              Expanded(
                child: _quickActionButton(
                  loc.revenueReport,
                  Icons.bar_chart,
                  AppColors.primaryDark,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(builder: (_) => const RevenueView()),
                  ),
                ),
              ),
            if (_can('allowViewRevenue') && _can('allowViewAttendance'))
              const SizedBox(width: 8),
            if (_can('allowViewAttendance'))
              Expanded(
                child: _quickActionButton(
                  loc.attendance,
                  Icons.access_time,
                  AppColors.info,
                  () => _pushRoute(
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
            if (_can('allowViewChat'))
              Expanded(
                child: _quickActionButton(
                  "Chat",
                  Icons.chat,
                  AppColors.primary,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(builder: (_) => const AdvancedChatView()),
                  ),
                  // Badge đã ẩn theo yêu cầu
                ),
              ),
            if (_can('allowViewChat') && _can('allowViewWarranty'))
              const SizedBox(width: 8),
            if (_can('allowViewWarranty'))
              Expanded(
                child: _quickActionButton(
                  "Bảo hành",
                  Icons.shield,
                  AppColors.warning,
                  () => _pushRoute(
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
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ResponsiveCenter(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive.horizontalPadding,
            vertical: 10,
          ),
          children: [
            // Header Section
            _buildTabHeader(
              loc.sales.toUpperCase(),
              Icons.shopping_cart,
              Colors.green,
            ),
            const SizedBox(height: 10),

            // Quick Action - Tạo đơn bán
            _buildSectionHeader(loc.quickActions),
            _financeQuickCard(
              loc.createNewSaleOrder,
              Icons.add_shopping_cart,
              Colors.green,
              () => _pushRoute(
                context,
                MaterialPageRoute(builder: (_) => const CreateSaleView()),
              ),
            ),

            const SizedBox(height: 10),
            _buildSectionHeader(loc.management),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: context.responsive.isMobile ? 1 : 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 8,
              childAspectRatio: context.responsive.isMobile ? 5.5 : 5.0,
              children: [
                _tabMenuItem(
                  loc.saleOrderList,
                  Icons.list_alt,
                  Colors.blue,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(builder: (_) => const SaleListView()),
                  ),
                  subtitle: loc.viewSearchTrackSales,
                ),
                _tabMenuItem(
                  loc.customerManagement,
                  Icons.people,
                  Colors.blue,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CustomerManagementView(),
                    ),
                  ),
                  subtitle: loc.addEditViewCustomers,
                ),
                _tabMenuItem(
                  loc.warranty,
                  Icons.verified_user,
                  Colors.orange,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(builder: (_) => const WarrantyView()),
                  ),
                  subtitle: loc.viewProcessWarrantyRequests,
                ),
                _tabMenuItem(
                  'Trả hàng',
                  Icons.assignment_return,
                  Colors.red,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SalesReturnListView(),
                    ),
                  ),
                  subtitle: 'Danh sách phiếu trả hàng',
                ),
                if (_enableRepair)
                  _tabMenuItem(
                    'Kho máy xác',
                    Icons.phone_android,
                    Colors.brown,
                    () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SalvagePhoneView(),
                      ),
                    ),
                    subtitle: 'Mua bán máy xác, linh kiện',
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRepairsTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ResponsiveCenter(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive.horizontalPadding,
            vertical: 10,
          ),
          children: [
            // Header Section
            _buildTabHeader(
              loc.repairsTab.toUpperCase(),
              Icons.build,
              Colors.blue,
            ),
            const SizedBox(height: 10), // Quick Action - Tạo đơn sửa
            _buildSectionHeader(loc.quickActions),
            _financeQuickCard(
              loc.createNewRepairOrder,
              Icons.build_circle,
              Colors.blue,
              () => _pushRoute(
                context,
                MaterialPageRoute(
                  builder: (_) => CreateRepairOrderView(role: widget.role),
                ),
              ),
            ),
            const SizedBox(height: 6),
            _financeQuickCard(
              'Yêu cầu đóng tiền',
              Icons.receipt_long,
              const Color(0xFF075E54),
              () => _pushRoute(
                context,
                MaterialPageRoute(
                  builder: (_) => const PaymentRequestChatView(),
                ),
              ),
            ),

            const SizedBox(height: 10),
            _buildSectionHeader(loc.management),
            _tabMenuItem(
              loc.repairOrderList,
              Icons.list_alt,
              Colors.indigo,
              () => _pushRoute(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderListView(role: widget.role),
                ),
              ),
              subtitle: loc.viewSearchTrackRepairs,
            ),
            // Parts inventory - requires repair + inventory permission
            if (hasFullAccess ||
                (_permissions['allowViewRepairs'] == true &&
                    _permissions['allowViewInventory'] == true))
              _tabMenuItem(
                'Kho phụ tùng / linh kiện',
                Icons.settings_suggest_outlined,
                Colors.deepOrange,
                () => _pushRoute(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InventoryView(
                      role: widget.role,
                      initialFilterType: 'LINH_KIEN',
                    ),
                  ),
                ),
                subtitle: 'Quản lý linh kiện, giá nhập, tồn kho',
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryTab() {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ResponsiveCenter(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive.horizontalPadding,
            vertical: 10,
          ),
          children: [
            // Header Section
            _buildTabHeader(
              loc.inventoryManagement,
              Icons.inventory_2,
              Colors.orange,
            ),
            const SizedBox(height: 8),

            // Pending Stock Widget (Hàng chờ xác nhận)
            const PendingStockWidget(),
            const SizedBox(height: 12),

            // Quick Actions
            _buildSectionHeader(loc.quickActions),
            // Dòng hướng dẫn cho người mới
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    loc.holdForDetailedGuide,
                    style: AppTextStyles.body1.copyWith(
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                // Nhập kho thông minh (MỚI)
                Expanded(
                  child: Card(
                    color: Colors.green.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.green.shade300, width: 2),
                    ),
                    child: InkWell(
                      onTap: () => _pushRoute(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SmartStockInView(),
                        ),
                      ),
                      onLongPress: () => _showFeatureGuide(
                        loc.stockInNew,
                        loc.stockInNewGuide,
                        Icons.add_box,
                        Colors.green,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.green.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.add_box,
                                color: Colors.green,
                                size: 20,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              loc.stockInNew,
                              style: AppTextStyles.subtitle1.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              loc.fullInformation,
                              style: AppTextStyles.overline.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Nhập siêu tốc - chỉ hiện cho electronics (có IMEI scan)
                if (_isElectronics)
                  Expanded(
                    child: Card(
                      color: Colors.orange.shade50,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: Colors.orange.shade200),
                      ),
                      child: InkWell(
                        onTap: () => _pushRoute(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const FastInventoryInputView(),
                          ),
                        ),
                        onLongPress: () => _showFeatureGuide(
                          loc.quickStockIn,
                          loc.quickStockInGuide,
                          Icons.flash_on,
                          Colors.orange,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(7),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.flash_on,
                                  color: Colors.orange,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                loc.quickStockIn,
                                style: AppTextStyles.subtitle1.copyWith(
                                  color: Colors.orange,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                loc.continuousScan,
                                style: AppTextStyles.overline.copyWith(
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
                Expanded(
                  child: Card(
                    color: Colors.blue.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: Colors.blue.shade200),
                    ),
                    child: InkWell(
                      onTap: () => _pushRoute(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const FastInventoryCheckView(),
                        ),
                      ),
                      onLongPress: () => _showFeatureGuide(
                        loc.checkInventory,
                        loc.checkInventoryGuide,
                        Icons.qr_code_scanner,
                        Colors.blue,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(7),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.qr_code_scanner,
                                color: Colors.blue,
                                size: 20,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              loc.checkInventory,
                              style: AppTextStyles.subtitle1.copyWith(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              loc.compareInventory,
                              style: AppTextStyles.overline.copyWith(
                                color: Colors.grey.shade600,
                              ),
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
            _buildSectionHeader(loc.management),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: context.responsive.isMobile ? 1 : 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 8,
              childAspectRatio: context.responsive.isMobile ? 5.5 : 5.0,
              children: [
                _tabMenuItem(
                  loc.pendingConfirmation,
                  Icons.pending_actions,
                  Colors.orange,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PendingStockListView(),
                    ),
                  ),
                  subtitle: loc.viewPendingStockList,
                ),
                _tabMenuItem(
                  loc.productList,
                  Icons.inventory,
                  Colors.blue,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InventoryView(role: widget.role),
                    ),
                  ),
                  subtitle: loc.viewManageProducts,
                ),
                _tabMenuItem(
                  loc.suppliersPartners,
                  Icons.business_center,
                  Colors.teal,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(builder: (_) => const SupplierListView()),
                  ),
                  subtitle: loc.manageSupplierPartnerDebt,
                ),
                _tabMenuItem(
                  loc.quickInputCodeList,
                  Icons.qr_code,
                  Colors.indigo,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const QuickInputCodesView(),
                    ),
                  ),
                  subtitle: loc.viewManageQuickInputCodes,
                ),
                _tabMenuItem(
                  'Lịch sử nhập kho',
                  Icons.history_edu,
                  Colors.teal,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ImportHistoryView(),
                    ),
                  ),
                  subtitle: 'Xem phiếu nhập kho đã xác nhận',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffTab() {
    // Permission check is handled by _updateAvailableTabs() — do NOT duplicate here
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ResponsiveCenter(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive.horizontalPadding,
            vertical: 10,
          ),
          children: [
            // Header Section
            _buildTabHeader(loc.staffManagement, Icons.people, Colors.teal),
            const SizedBox(height: 10),

            // Quick Action - Chấm công
            _buildSectionHeader(loc.quickActions),
            _staffQuickCard(
              loc.attendance,
              Icons.fingerprint,
              Colors.teal,
              () => _pushRoute(
                context,
                MaterialPageRoute(builder: (_) => const AttendanceView()),
              ),
            ),

            const SizedBox(height: 10),
            _buildSectionHeader(loc.staffManagement),

            // Grid responsive cho các chức năng chính
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: context.responsive.isMobile
                  ? 2
                  : (context.responsive.isDesktop ? 4 : 3),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: context.responsive.isMobile ? 2.5 : 3.2,
              children: [
                _staffQuickCard(
                  loc.staffListLabel,
                  Icons.people,
                  Colors.blue,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(builder: (_) => const StaffListView()),
                  ),
                ),
                _staffQuickCardWithHelp(
                  loc.salaryCalculation,
                  Icons.bar_chart,
                  Colors.orange,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const StaffPerformanceView(),
                    ),
                  ),
                  _showSalaryHelpDialog,
                ),
                _staffQuickCard(
                  loc.workSchedule,
                  Icons.schedule,
                  Colors.blue,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const WorkScheduleSettingsView(),
                    ),
                  ),
                ),
                _staffQuickCard(
                  loc.salaryCommissionSettings,
                  Icons.account_balance_wallet,
                  Colors.green,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HRSalarySettingsView(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            _buildSectionHeader(loc.report),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: context.responsive.isMobile ? 1 : 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 8,
              childAspectRatio: context.responsive.isMobile ? 5.5 : 5.0,
              children: [
                _tabMenuItem(
                  loc.attendanceTracking,
                  Icons.people_outline,
                  Colors.teal,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AttendanceManagementView(),
                    ),
                  ),
                  subtitle: loc.viewAttendanceAllStaff,
                ),
                _tabMenuItem(
                  loc.personalAttendance,
                  Icons.history,
                  Colors.indigo,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(builder: (_) => const AttendanceView()),
                  ),
                  subtitle: loc.personalAttendanceDescription,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Card nhỏ cho Staff Quick Actions
  Widget _staffQuickCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: color.withOpacity(0.05),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: color.withOpacity(0.4),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Card với nút help cho LƯƠNG Tính lương
  Widget _staffQuickCardWithHelp(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
    VoidCallback onHelpTap,
  ) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: color.withOpacity(0.05),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.help_outline,
                  color: color.withOpacity(0.5),
                  size: 14,
                ),
                onPressed: onHelpTap,
                tooltip: loc.usageGuide,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: color.withOpacity(0.4),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Hiển thị popup hướng dẫn sử dụng LƯƠNG Tính lương
  void _showSalaryHelpDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.bar_chart,
                color: Colors.orange,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.salaryCalculationGuide,
                style: const TextStyle(
                  fontSize: AppTextStyles.h3,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHelpSection(
                AppLocalizations.of(context)!.accessSalaryTable,
                AppLocalizations.of(context)!.accessSalaryDesc,
                Colors.blue,
              ),
              _buildHelpSection(
                AppLocalizations.of(context)!.salarySettings,
                AppLocalizations.of(context)!.salarySettingsDesc,
                Colors.green,
              ),
              _buildHelpSection(
                AppLocalizations.of(context)!.salaryComponents,
                AppLocalizations.of(context)!.salaryComponentsDesc,
                Colors.orange,
              ),
              _buildHelpSection(
                AppLocalizations.of(context)!.viewDetails,
                AppLocalizations.of(context)!.viewDetailsDesc,
                Colors.blue,
              ),
              _buildHelpSection(
                AppLocalizations.of(context)!.printSalarySlip,
                AppLocalizations.of(context)!.printSalaryDesc,
                Colors.teal,
              ),
              _buildHelpSection(
                AppLocalizations.of(context)!.taxAndInsurance,
                AppLocalizations.of(context)!.taxAndInsuranceDesc,
                Colors.red,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.of(context)!.understood,
              style: const TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _pushRoute(
                context,
                MaterialPageRoute(builder: (_) => const StaffPerformanceView()),
              );
            },
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(AppLocalizations.of(context)!.goToSalaryTable),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Widget cho mỗi section trong help dialog
  Widget _buildHelpSection(String title, String content, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.headline5.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              content,
              style: AppTextStyles.subtitle1.copyWith(height: 1.4),
            ),
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
        child: ResponsiveCenter(
          child: ListView(
            padding: EdgeInsets.symmetric(
              horizontal: context.responsive.horizontalPadding,
              vertical: 16,
            ),
            children: [
              // Header Section
              _buildTabHeader(
                loc.financialManagement,
                Icons.account_balance_wallet,
                Colors.indigo,
              ),
              const SizedBox(height: 20),

              // Financial Overview Cards
              _buildSectionHeader(loc.todayOverview),
              FinanceSummaryCard(
                key: const ValueKey('finance_tab_summary'),
                revenue:
                    _todaySaleIncome +
                    _todaySettlementIncome +
                    _todayRepairIncome,
                netProfit: _todayNetProfit,
                currentFund:
                    _previousClosingTotal + _todayTotalIn - _todayTotalOut,
                onTap: () => _pushRoute(
                  context,
                  MaterialPageRoute(builder: (_) => const CashClosingView()),
                ),
              ),
              _buildDashboardOverview(),

              const SizedBox(height: 16),

              // CÔNG NỢ TỔNG HỢP
              _buildSectionHeader("CÔNG NỢ"),
              _buildDebtSummaryCard(),

              const SizedBox(height: 16),

              // THAO TÁC NHANH - Sổ quỹ + Thu Chi
              _buildSectionHeader(loc.quickActions),
              Row(
                children: [
                  Expanded(
                    child: _financeQuickCard(
                      'Sổ quỹ',
                      Icons.menu_book,
                      Colors.green,
                      () => _pushRoute(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const CashClosingView(),
                        ),
                      ),
                      subtitle: MoneyUtils.formatCompact(
                        _previousClosingTotal + _todayTotalIn - _todayTotalOut,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (hasFullAccess ||
                      _permissions['allowViewExpenses'] == true)
                    Expanded(
                      child: _financeQuickCard(
                        'Thu Chi',
                        Icons.swap_vert,
                        Colors.blue,
                        () => _pushRoute(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ExpenseView(),
                          ),
                        ),
                        subtitle:
                            '+${MoneyUtils.formatCompact(_todayTotalIn)} / -${MoneyUtils.formatCompact(_todayTotalOut)}',
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 16),
              _buildSectionHeader(loc.reportAndAnalysis),

              // Grid responsive - Main financial views
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: context.responsive.isMobile
                    ? 2
                    : (context.responsive.isDesktop ? 4 : 3),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: context.responsive.isMobile ? 2.5 : 3.2,
                children: [
                  _financeQuickCard(
                    'Báo cáo doanh thu',
                    Icons.trending_up,
                    Colors.blue,
                    () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const RevenueView()),
                    ),
                  ),
                  if (hasFullAccess || _permissions['allowViewDebts'] == true)
                    _financeQuickCard(
                      'Quản lý công nợ',
                      Icons.account_balance,
                      Colors.orange,
                      () => _pushRoute(
                        context,
                        MaterialPageRoute(builder: (_) => const DebtView()),
                      ),
                    ),
                  _financeQuickCard(
                    'Lịch sử tài chính',
                    Icons.receipt_long,
                    Colors.indigo,
                    () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            const CashClosingView(showOnlyTransactions: true),
                      ),
                    ),
                  ),
                  _financeQuickCard(
                    'Nhật ký hệ thống',
                    Icons.history,
                    Colors.purple,
                    () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const AuditLogView()),
                    ),
                  ),
                  _financeQuickCard(
                    'Lợi nhuận theo tháng',
                    Icons.bar_chart,
                    Colors.teal,
                    () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const MonthlyProfitReportView(),
                      ),
                    ),
                  ),
                  if (hasFullAccess || _permissions['allowViewRevenue'] == true)
                    _financeQuickCard(
                      'Báo cáo hoạt động',
                      Icons.summarize,
                      const Color(0xFF1565C0),
                      () => _pushRoute(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DailyActivityReportView(),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Card nhỏ cho Finance Quick Actions
  Widget _financeQuickCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    String? subtitle,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: color.withOpacity(0.05),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: color.withOpacity(0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: color.withOpacity(0.4),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tab Header đẹp với gradient
  Widget _buildTabHeader(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.headline3.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  DateFormat('EEEE, dd/MM', 'vi').format(DateTime.now()),
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Debt summary card for Finance tab: Khách nợ / NCC nợ / Đối tác nợ
  Widget _buildDebtSummaryCard() {
    if (!(hasFullAccess || _permissions['allowViewDebts'] == true)) {
      return const SizedBox();
    }
    return GestureDetector(
      onTap: () => _pushRoute(
        context,
        MaterialPageRoute(builder: (_) => const DebtView()),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.account_balance,
                    color: Colors.orange.shade600,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CÔNG NỢ TỔNG HỢP',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.orange.shade700,
                      fontSize: 13,
                      letterSpacing: 0.4,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Tổng: ${MoneyUtils.formatCompact(totalDebtRemain)}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: totalDebtRemain > 0
                          ? Colors.red.shade600
                          : Colors.grey.shade500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 10,
                  color: Colors.grey.shade400,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _debtTypeColumn(
                    '👤 Khách nợ',
                    _customerDebtRemain,
                    Colors.cyan,
                    'Phải thu',
                  ),
                ),
                Container(width: 1, height: 44, color: Colors.grey.shade200),
                Expanded(
                  child: _debtTypeColumn(
                    '🏭 Nợ NCC',
                    _supplierDebtRemain,
                    Colors.deepOrange,
                    'Phải trả',
                  ),
                ),
                Container(width: 1, height: 44, color: Colors.grey.shade200),
                Expanded(
                  child: _debtTypeColumn(
                    '🤝 Đối tác',
                    _partnerDebtRemain,
                    Colors.purple,
                    'Phải trả',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _debtTypeColumn(
    String label,
    int amount,
    Color color,
    String subLabel,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          MoneyUtils.formatCompact(amount),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: amount > 0 ? color : Colors.grey,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          subLabel,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
      ],
    );
  }

  // Finance Overview Section with modern cards
  Widget _financeOverviewSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
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
          // LỢI NHUẬN RÒNG
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
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
                        loc.todayNetProfit,
                        style: AppTextStyles.caption.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        MoneyUtils.formatCompact(_todayNetProfit),
                        style: AppTextStyles.headline5.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '🛒 ${MoneyUtils.formatCompact(_todaySalesProfit)}',
                            style: AppTextStyles.overline.copyWith(
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_enableRepair) ...[
                            Text(
                              '  •  ',
                              style: AppTextStyles.overline.copyWith(
                                color: Colors.white54,
                              ),
                            ),
                            Text(
                              '🔧 ${MoneyUtils.formatCompact(_todayRepairProfit)}',
                              style: AppTextStyles.overline.copyWith(
                                color: Colors.white.withOpacity(0.85),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Finance stat card for the overview section

  /// Chi tiết breakdown chi phí hôm nay
  String _buildExpenseDetail(AppLocalizations loc) {
    final parts = <String>[];
    if (_todayExpenseOnly > 0) {
      parts.add(
        '$_todayExpenseCount ${loc.expenseItems}: ${MoneyUtils.formatCompact(_todayExpenseOnly)}',
      );
    } else if (_todayExpenseCount > 0) {
      parts.add('$_todayExpenseCount ${loc.expenseItems}');
    }
    if (_todayDebtPaidToSupplier > 0) {
      parts.add(
        'Trả nợ NCC: ${MoneyUtils.formatCompact(_todayDebtPaidToSupplier)}',
      );
    }
    if (parts.isEmpty) return '0 ${loc.expenseItems}';
    return parts.join(' · ');
  }

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
              MoneyUtils.formatCompact(value),
              style: AppTextStyles.headline3.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 4),
              Text(
                detail,
                style: AppTextStyles.overline.copyWith(
                  color: AppColors.onSurface.withOpacity(0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    final loc = AppLocalizations.of(context)!;
    final currentLangLabel = _currentLocale.languageCode == 'en'
        ? loc.english
        : loc.vietnamese;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: ResponsiveCenter(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: context.responsive.horizontalPadding,
            vertical: 10,
          ),
          children: [
            Text(
              loc.settings,
              style: AppTextStyles.headline6.copyWith(
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 10),

            // ====== SHOP SWITCHER (Owner với nhiều shop) ======
            ShopSwitcherWidget(
              onShopChanged: () {
                // Reload data when shop changes
                _loadStats();
                _loadUserAndShopInfo();
                _loadShopSettings(); // Ensure shop settings reload after switch
              },
            ),

            // ====== TÀI KHOẢN ======
            _buildHomeAccountCard(),
            const SizedBox(height: 12),

            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.language, color: AppColors.primary),
                title: Text(loc.languageApp),
                subtitle: Text(loc.languageAndInterface),
                trailing: Text(currentLangLabel),
                onTap: _showLanguageSheet,
              ),
            ),
            const SizedBox(height: 12),

            // CÀI ĐẶT CỬA HÀNG - Đưa ra ngoài đầu tiên
            if (hasFullAccess)
              _tabMenuItem(
                loc.shopSettings,
                Icons.store,
                Colors.blue,
                () => _pushRoute(
                  context,
                  MaterialPageRoute(builder: (_) => const ShopSettingsView()),
                ),
                subtitle: loc.shopSettingsDescription,
              ),

            // SYNC HEALTH STATUS CARD - Chỉ còn 1 nút đồng bộ duy nhất
            _buildSyncHealthStatusCard(),
            const SizedBox(height: 10),

            // Menu items - grid 2 cột trên wide
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: context.responsive.isMobile ? 1 : 2,
              mainAxisSpacing: 6,
              crossAxisSpacing: 8,
              childAspectRatio: context.responsive.isMobile ? 5.5 : 5.0,
              children: [
                _tabMenuItem(
                  loc.notifications,
                  Icons.notifications,
                  AppColors.primary,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const NotificationSettingsView(),
                    ),
                  ),
                  subtitle: loc.notificationSettingsDescription,
                ),
                _tabMenuItem(
                  loc.printer,
                  Icons.print,
                  AppColors.success,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrinterSettingsView(),
                    ),
                  ),
                  subtitle: loc.printerSettingsDescription,
                ),
                if (_isSuperAdmin)
                  _tabMenuItem(
                    loc.adminCenter,
                    Icons.admin_panel_settings,
                    AppColors.error,
                    () => _pushRoute(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const admin_view.SuperAdminView(),
                      ),
                    ),
                    subtitle: loc.adminCenterDescription,
                  ),
                _tabMenuItem(
                  loc.aboutDeveloper,
                  Icons.info,
                  AppColors.secondary,
                  () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AboutDeveloperView(),
                    ),
                  ),
                  subtitle: loc.aboutDeveloperDescription,
                ),
              ],
            ),

            // Đăng xuất nằm trong account card ở trên
          ],
        ),
      ),
    );
  }

  Widget _buildTestDataButton() {
    return Card(
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.orange.shade300),
      ),
      child: ListTile(
        leading: Icon(Icons.science, color: Colors.orange.shade700),
        title: const Text(
          '🧪 Tạo Data Test',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: const Text(
          'Tạo sản phẩm, đơn bán, chi phí, trả hàng để debug',
        ),
        onTap: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Tạo Data Test?'),
              content: const Text(
                'Sẽ tạo 8 SP, 4 đơn bán, 4 chi phí, 1 trả hàng.\nDữ liệu sẽ hiển thị trên dashboard.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Tạo ngay'),
                ),
              ],
            ),
          );
          if (confirm != true) return;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Đang tạo data test...'),
              duration: Duration(seconds: 2),
            ),
          );
          try {
            final result = await TestDataService.seedTestData();
            if (mounted) {
              _debouncedLoadStats();
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('✅ Tạo thành công!'),
                  content: Text(result),
                  actions: [
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
              );
            }
          }
        },
      ),
    );
  }

  Widget _buildHomeAccountCard() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'N/A';
    final displayName = user?.displayName ?? email.split('@').first;
    final photoUrl = user?.photoURL;
    final googleLinked = SocialAuthService.isGoogleLinked();
    final appleLinked = SocialAuthService.isAppleLinked();
    final passwordLinked = SocialAuthService.isPasswordLinked();
    final showApple =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundImage: photoUrl != null
                      ? NetworkImage(photoUrl)
                      : null,
                  backgroundColor: Colors.blue.shade100,
                  child: photoUrl == null
                      ? Text(
                          displayName.isNotEmpty
                              ? displayName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        email,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _getRoleLabel(_effectiveRole),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Linked accounts
            Row(
              children: [
                Icon(Icons.link, color: Colors.indigo.shade400, size: 18),
                const SizedBox(width: 6),
                Text(
                  'Liên kết tài khoản',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.indigo.shade400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Email
            _buildProviderTile(
              Icons.email,
              Colors.blue,
              'Email',
              passwordLinked,
              null,
              null,
              providerEmail: SocialAuthService.passwordEmail,
            ),
            // Google
            _buildProviderTile(
              Icons.g_mobiledata,
              Colors.red,
              'Google',
              googleLinked,
              () => _linkSocialProvider('google'),
              googleLinked ? () => _unlinkSocialProvider('google') : null,
              providerEmail: SocialAuthService.googleEmail,
            ),
            // Apple
            if (showApple)
              _buildProviderTile(
                Icons.apple,
                Colors.black,
                'Apple',
                appleLinked,
                () => _linkSocialProvider('apple'),
                appleLinked ? () => _unlinkSocialProvider('apple') : null,
                providerEmail: SocialAuthService.appleEmail,
              ),

            const Divider(height: 20),
            // Logout
            InkWell(
              onTap: () => _confirmAndLogout(),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      loc.logout,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderTile(
    IconData icon,
    Color color,
    String label,
    bool linked,
    VoidCallback? onLink,
    VoidCallback? onUnlink, {
    String? providerEmail,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 13)),
                if (linked && providerEmail != null && providerEmail.isNotEmpty)
                  Text(
                    providerEmail,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (linked)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Đã liên kết',
                  style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                ),
                if (onUnlink != null &&
                    SocialAuthService.getLinkedProviders().length > 1) ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onUnlink,
                    child: Text(
                      'Hủy',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.red.shade400,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            )
          else if (onLink != null)
            TextButton(
              onPressed: onLink,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Liên kết',
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
        ],
      ),
    );
  }

  String _getRoleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Chủ shop';
      case 'manager':
        return 'Quản lý';
      case 'employee':
        return 'Nhân viên';
      case 'technician':
        return 'Kỹ thuật';
      case 'admin':
        return 'Admin';
      default:
        return 'User';
    }
  }

  Future<void> _linkSocialProvider(String provider) async {
    try {
      UserCredential? result;
      if (provider == 'google') {
        result = await SocialAuthService.linkGoogle();
      } else if (provider == 'apple') {
        result = await SocialAuthService.linkApple();
      }
      // Force refresh to get updated providerData
      await FirebaseAuth.instance.currentUser?.reload();
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (mounted) {
        setState(() {});
        if (result != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Đã liên kết $provider thành công!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? 'Lỗi liên kết $provider'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceAll('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, maxLines: 4),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
  }

  Future<void> _unlinkSocialProvider(String provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy liên kết'),
        content: Text('Bạn có chắc muốn hủy liên kết $provider?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'XÁC NHẬN',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      if (provider == 'google') {
        await SocialAuthService.unlinkGoogle();
      } else if (provider == 'apple') {
        await SocialAuthService.unlinkApple();
      }
      await FirebaseAuth.instance.currentUser?.reload();
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã hủy liên kết $provider'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
      }
    }
  }

  Future<void> _confirmAndLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.logoutConfirmTitle),
        content: Text(loc.logoutConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              loc.logout,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await SyncService.cancelAllSubscriptions();
      } catch (_) {}
      try {
        EncryptionService.reset();
      } catch (_) {}
      try {
        UserService.clearCache();
      } catch (_) {}
      try {
        CurrentShopService().clear();
      } catch (_) {}
      try {
        UserService.setAdminSelectedShop(null);
      } catch (_) {}
      try {
        await DBHelper().clearAllData();
      } catch (_) {}
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('Logout error: $e');
      }
    }
  }

  Widget _buildLogoutCard() {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: Text(
          loc.logout,
          style: const TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(loc.logoutFromAccount, style: AppTextStyles.body1),
        onTap: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(loc.logoutConfirmTitle),
              content: Text(loc.logoutConfirmMessage),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(loc.cancel),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                  child: Text(
                    loc.logout,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
          if (confirm == true) {
            // Always sign out — cleanup failures must not block logout
            try {
              await SyncService.cancelAllSubscriptions();
            } catch (_) {}
            try {
              EncryptionService.reset();
            } catch (_) {}
            try {
              UserService.clearCache();
            } catch (_) {}
            try {
              CurrentShopService().clear();
            } catch (_) {}
            try {
              UserService.setAdminSelectedShop(null);
            } catch (_) {}
            try {
              await DBHelper().clearAllData();
            } catch (_) {}
            try {
              await FirebaseAuth.instance.signOut();
            } catch (e) {
              debugPrint('Logout error: $e');
            }
          }
        },
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
                child: ListTile(
                  leading: const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text(loc.checkingSync, style: AppTextStyles.headline5),
                  subtitle: Text(
                    loc.checkingLocalVsCloud,
                    style: AppTextStyles.caption,
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
                  title: Text(
                    loc.dataSyncedFully,
                    style: AppTextStyles.headline5.copyWith(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    loc.localCloudMatched,
                    style: AppTextStyles.caption,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.refresh, color: Colors.green),
                    onPressed: () {
                      SyncHealthCheck.runFullCheck();
                      NotificationService.showSnackBar(
                        loc.recheckingSync,
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
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    backgroundColor: Colors.red,
                    child: const Icon(
                      Icons.warning,
                      color: Colors.red,
                      size: 22,
                    ),
                  ),
                ),
                title: Text(
                  loc.needSyncData,
                  style: AppTextStyles.headline5.copyWith(
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  loc.recordsNotSynced(mismatchCount),
                  style: AppTextStyles.caption.copyWith(color: Colors.red),
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.red,
                    size: 16,
                  ),
                  onPressed: () {
                    showAppBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => const SyncCenterSheet(),
                    );
                  },
                ),
                onTap: () {
                  showAppBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (context) => const SyncCenterSheet(),
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
      margin: const EdgeInsets.only(bottom: 6),
      color: color.withOpacity(0.05),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: ListTile(
        dense: true,
        visualDensity: const VisualDensity(vertical: -2),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
        title: Text(
          title,
          style: AppTextStyles.body1.copyWith(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: AppTextStyles.caption.copyWith(color: Colors.grey),
              )
            : null,
        trailing: Icon(
          Icons.arrow_forward_ios,
          color: color.withOpacity(0.5),
          size: 14,
        ),
        onTap: onTap,
      ),
    );
  }

  String _getTabTitle(int index) {
    if (index >= 0 && index < _visibleTabConfigs.length) {
      final item = _visibleTabConfigs[index]['item'] as BottomNavigationBarItem;
      return item.label?.toUpperCase() ?? 'TAB';
    }
    return "SHOP MANAGER";
  }

  Widget _buildDashboardOverview() {
    final totalIncome = _todayTotalIn;
    final totalExpense = _todayTotalOut;
    final netProfit = totalIncome - totalExpense;

    // Income breakdown for donut
    final incomeItems = <_HomeDashItem>[
      _HomeDashItem(
        'Bán hàng',
        _todaySaleIncome + _todayRefundOut,
        const Color(0xFF43A047),
      ),
      if (_todaySettlementIncome > 0)
        _HomeDashItem(
          'Tất toán NH',
          _todaySettlementIncome,
          const Color(0xFF00897B),
        ),
      if (_enableRepair && _todayRepairIncome > 0)
        _HomeDashItem('Sửa chữa', _todayRepairIncome, const Color(0xFF1E88E5)),
      if (_todayDebtCollected > 0)
        _HomeDashItem(
          'Thu nợ KH',
          _todayDebtCollected,
          const Color(0xFF5C6BC0),
        ),
      if (_todayMiscIncome > 0)
        _HomeDashItem('Thu khác', _todayMiscIncome, const Color(0xFF7E57C2)),
    ].where((i) => i.value > 0).toList();

    final expenseItems = <_HomeDashItem>[
      _HomeDashItem('Chi phí', _todayExpenseOnly, const Color(0xFFE53935)),
      if (_todayImportOut > 0)
        _HomeDashItem('Nhập hàng', _todayImportOut, const Color(0xFFFB8C00)),
      if (_todayDebtPaidToSupplier > 0)
        _HomeDashItem(
          'Trả nợ NCC',
          _todayDebtPaidToSupplier,
          const Color(0xFFFF7043),
        ),
      if (_todayPartnerPaid > 0)
        _HomeDashItem('TT đối tác', _todayPartnerPaid, const Color(0xFFAB47BC)),
      if (_todayRefundOut > 0)
        _HomeDashItem('Trả hàng', _todayRefundOut, const Color(0xFFEF5350)),
    ].where((i) => i.value > 0).toList();

    // Bar chart data
    final barItems = <_HomeDashItem>[
      _HomeDashItem('Bán hàng', _todaySaleIncome, const Color(0xFF43A047)),
      if (_enableRepair)
        _HomeDashItem('Sửa chữa', _todayRepairIncome, const Color(0xFF1E88E5)),
      _HomeDashItem('Chi phí', _todayExpenseOnly, const Color(0xFFE53935)),
      _HomeDashItem('Nhập hàng', _todayImportOut, const Color(0xFFFB8C00)),
    ];
    final barMax = barItems.fold<double>(
      0,
      (m, i) => math.max(m, i.value.toDouble()),
    );

    return GestureDetector(
      onTap: () => _pushRoute(
        context,
        MaterialPageRoute(builder: (_) => const CashClosingView()),
      ),
      child: Container(
        key: ValueKey('dashboard_overview_${_todayTotalIn}_${_todayTotalOut}'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Profit header ──
            _dashProfitHeader(netProfit, totalIncome, totalExpense),

            const SizedBox(height: 12),

            // ── 2x2 metric tiles ──
            Row(
              children: [
                _dashMetric(
                  'Thu',
                  totalIncome,
                  const Color(0xFF2E7D32),
                  Icons.trending_up,
                ),
                const SizedBox(width: 8),
                _dashMetric(
                  'Chi',
                  totalExpense,
                  const Color(0xFFC62828),
                  Icons.trending_down,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _dashMetric(
                  'Đơn bán',
                  todaySaleCount,
                  const Color(0xFF1E88E5),
                  Icons.shopping_cart_outlined,
                  raw: true,
                  suffix: '',
                ),
                const SizedBox(width: 8),
                _dashMetric(
                  _enableRepair ? 'Sửa chữa' : 'Chi phí HĐ',
                  _enableRepair ? _todayRepairCount : _todayExpenseCount,
                  _enableRepair
                      ? const Color(0xFFFB8C00)
                      : const Color(0xFFE53935),
                  _enableRepair ? Icons.build_outlined : Icons.receipt_outlined,
                  raw: true,
                  suffix: '',
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Donut breakdown: THU ──
            if (incomeItems.isNotEmpty)
              _dashDonut(
                'THU NHẬP',
                incomeItems,
                totalIncome,
                const Color(0xFF2E7D32),
              ),

            if (incomeItems.isNotEmpty && expenseItems.isNotEmpty)
              const SizedBox(height: 10),

            // ── Donut breakdown: CHI ──
            if (expenseItems.isNotEmpty)
              _dashDonut(
                'CHI TIÊU',
                expenseItems,
                totalExpense,
                const Color(0xFFC62828),
              ),

            const SizedBox(height: 14),

            // ── Bar chart ──
            if (barMax > 0) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'BIẾN ĐỘNG',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.grey.shade600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 110,
                      child: BarChart(
                        BarChartData(
                          alignment: BarChartAlignment.spaceAround,
                          maxY: barMax * 1.15,
                          barTouchData: BarTouchData(enabled: false),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (v, _) {
                                  final idx = v.toInt();
                                  if (idx < 0 || idx >= barItems.length)
                                    return const SizedBox();
                                  return Text(
                                    barItems[idx].label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: barItems[idx].color,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          barGroups: barItems.asMap().entries.map((e) {
                            return BarChartGroupData(
                              x: e.key,
                              barRods: [
                                BarChartRodData(
                                  toY: e.value.value.toDouble(),
                                  color: e.value.color,
                                  width: 20,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(5),
                                  ),
                                  backDrawRodData: BackgroundBarChartRodData(
                                    show: true,
                                    toY: 0,
                                    color: e.value.color.withOpacity(0.06),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTodayActivityItems() {
    final canRepair = hasFullAccess || _permissions['allowViewRepairs'] == true;
    final canInventory =
        hasFullAccess || _permissions['allowViewInventory'] == true;
    final canSales = hasFullAccess || _permissions['allowViewSales'] == true;
    final canDebt = hasFullAccess || _permissions['allowViewDebts'] == true;

    return [
      if (_enableRepair && canRepair)
        _activityCard(
          icon: Icons.build_circle,
          label: loc.pendingRepairs,
          value: totalPendingRepair.toString(),
          color: AppColors.primary,
          onTap: () => _pushRoute(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  OrderListView(role: widget.role, statusFilter: const [1, 2]),
            ),
          ),
        ),
      if (_enableRepair && canRepair)
        _activityCard(
          icon: Icons.hourglass_top,
          label: loc.pendingStatus,
          value: pendingApprovalCount.toString(),
          color: AppColors.repairPendingApproval,
          onTap: () => _pushRoute(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  OrderListView(role: widget.role, statusFilter: const [3]),
            ),
          ),
        ),
      if (_enableExpiry && canInventory)
        _activityCard(
          icon: Icons.timer,
          label: 'Sắp hết HSD',
          value: (_expiryStats?.atRiskCount ?? 0).toString(),
          color: Colors.orange,
          onTap: () {
            final expiryTabIndex = _navItems.indexWhere(
              (item) => item.label == 'HSD',
            );
            if (expiryTabIndex != -1) {
              _setCurrentTab(expiryTabIndex);
            }
          },
        ),
      if (_enableVariants && canInventory)
        _activityCard(
          icon: Icons.checkroom,
          label: 'Hết size/màu',
          value: (_variantWarnings?.outOfStock ?? 0).toString(),
          color: Colors.blue,
          onTap: () {
            final variantTabIndex = _navItems.indexWhere(
              (item) => item.label == 'Size/Màu',
            );
            if (variantTabIndex != -1) {
              _setCurrentTab(variantTabIndex);
            }
          },
        ),
      if (canSales)
        _activityCard(
          icon: Icons.shopping_cart,
          label: loc.saleOrders,
          value: todaySaleCount.toString(),
          color: AppColors.success,
          onTap: () => _pushRoute(
            context,
            MaterialPageRoute(
              builder: (_) => const SaleListView(todayOnly: true),
            ),
          ),
        ),
      if (canDebt)
        _activityCard(
          icon: Icons.receipt_long,
          label: loc.debt,
          value: MoneyUtils.formatCompact(totalDebtRemain),
          color: AppColors.warning,
          onTap: () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const DebtView()),
          ),
        ),
      _activityCard(
        icon: Icons.notifications_active_rounded,
        label: 'Nhắc nhở',
        value: _totalReminderCount.toString(),
        color: _totalReminderCount > 0
            ? const Color(0xFFE65100)
            : AppColors.inactive,
        onTap: () => _pushRoute(
          context,
          MaterialPageRoute(
            builder: (_) =>
                RemindersView(role: widget.role, permissions: _permissions),
          ),
        ).then((_) => _loadReminderCount()),
      ),
    ];
  }

  Widget _buildDailyReportCard() {
    final totalRevenue =
        _todaySaleIncome + _todaySettlementIncome + _todayRepairIncome;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _pushRoute(
            context,
            MaterialPageRoute(builder: (_) => const DailyActivityReportView()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.summarize,
                      color: const Color(0xFF1565C0),
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'HOẠT ĐỘNG HÔM NAY',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF1565C0),
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _dailyReportStat(
                        'Doanh thu',
                        MoneyUtils.formatCompact(totalRevenue),
                        Colors.green,
                        Icons.trending_up,
                      ),
                    ),
                    Expanded(
                      child: _dailyReportStat(
                        'Bán hàng',
                        todaySaleCount.toString(),
                        Colors.blue,
                        Icons.shopping_cart,
                      ),
                    ),
                    if (_enableRepair)
                      Expanded(
                        child: _dailyReportStat(
                          'Sửa chữa',
                          totalPendingRepair.toString(),
                          Colors.orange,
                          Icons.build_circle,
                        ),
                      ),
                    Expanded(
                      child: _dailyReportStat(
                        'Lợi nhuận',
                        MoneyUtils.formatCompact(_todayNetProfit),
                        _todayNetProfit >= 0 ? Colors.teal : Colors.red,
                        Icons.account_balance_wallet,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dailyReportStat(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTodayActivityDashboardCard() {
    final activityItems = _buildTodayActivityItems();
    if (activityItems.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.space_dashboard_rounded,
                color: Colors.deepOrange.shade400,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                loc.todayActivity.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange.shade600,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final r2 = context.responsive;
              final itemCount = activityItems.length;
              final width = constraints.maxWidth;
              final isPhone = !r2.isTablet && !r2.isDesktop;
              final isVeryNarrow = width < 360;
              final crossAxisCount = r2.isDesktop
                  ? itemCount.clamp(1, 6)
                  : r2.isTablet
                  ? itemCount.clamp(1, 4)
                  : itemCount <= 3
                  ? itemCount
                  : isVeryNarrow
                  ? 3
                  : isPhone
                  ? 3
                  : 4;
              final childAspectRatio = r2.isDesktop
                  ? 1.0
                  : r2.isTablet
                  ? 0.9
                  : isVeryNarrow
                  ? 0.72
                  : 0.84;

              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: childAspectRatio,
                children: activityItems,
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Dashboard chart helpers ──

  Widget _dashProfitHeader(int net, int income, int expense) {
    final isPositive = net >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isPositive ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'HÔM NAY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            isPositive ? Icons.arrow_upward : Icons.arrow_downward,
            size: 16,
            color: isPositive
                ? const Color(0xFF2E7D32)
                : const Color(0xFFC62828),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              '${isPositive ? "+" : "-"}${MoneyUtils.formatCompact(net.abs())}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: isPositive
                    ? const Color(0xFF2E7D32)
                    : const Color(0xFFC62828),
              ),
            ),
          ),
          Icon(Icons.arrow_forward_ios, size: 12, color: Colors.grey.shade400),
        ],
      ),
    );
  }

  Widget _dashMetric(
    String label,
    num value,
    Color color,
    IconData icon, {
    bool raw = false,
    String? suffix,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    raw
                        ? '${value.toInt()}${suffix ?? ''}'
                        : MoneyUtils.formatCompact(value.toInt()),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashDonut(
    String title,
    List<_HomeDashItem> items,
    int total,
    Color titleColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // Donut
          SizedBox(
            width: 70,
            height: 70,
            child: PieChart(
              PieChartData(
                sectionsSpace: 1.5,
                centerSpaceRadius: 20,
                sections: items.map((i) {
                  final pct = total > 0 ? i.value / total * 100 : 0.0;
                  return PieChartSectionData(
                    value: i.value.toDouble(),
                    color: i.color,
                    radius: 14,
                    title: pct >= 15 ? '${pct.round()}%' : '',
                    titleStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Legend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      MoneyUtils.formatCompact(total),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ...items.map(
                  (i) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1.5),
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: i.color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            i.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                        Text(
                          MoneyUtils.formatCompact(i.value),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: i.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppTextStyles.body2.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: AppColors.onSurface.withOpacity(0.6),
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// Lối tắt đến Hướng dẫn sử dụng ở cuối Home
  Widget _buildUserGuideShortcut() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: InkWell(
        onTap: () {
          _pushRoute(
            context,
            MaterialPageRoute(
              builder: (_) => UserGuideView(userRole: widget.role),
            ),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  color: Colors.blue.shade700,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  loc.userGuide,
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.blue.shade300,
                size: 14,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Finance shortcuts: Sổ quỹ / Công nợ / Thu chi
  Widget _buildFinanceShortcuts() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.account_balance,
                color: Colors.indigo.shade400,
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                'TRUY CẬP NHANH TÀI CHÍNH',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.indigo.shade600,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _financeShortcutButton(
                  icon: Icons.menu_book,
                  label: 'Sổ quỹ',
                  color: Colors.green,
                  onTap: () => _pushRoute(
                    context,
                    MaterialPageRoute(builder: (_) => const CashClosingView()),
                  ),
                ),
              ),
              if (hasFullAccess || _permissions['allowViewDebts'] == true) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _financeShortcutButton(
                    icon: Icons.account_balance_wallet,
                    label: 'Công nợ',
                    color: Colors.orange,
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const DebtView()),
                    ),
                  ),
                ),
              ],
              if (hasFullAccess ||
                  _permissions['allowViewExpenses'] == true) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: _financeShortcutButton(
                    icon: Icons.swap_vert,
                    label: 'Thu Chi',
                    color: Colors.blue,
                    onTap: () => _pushRoute(
                      context,
                      MaterialPageRoute(builder: (_) => const ExpenseView()),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _financeShortcutButton(
                  icon: Icons.history,
                  label: 'Hoạt động',
                  color: Colors.deepPurple,
                  onTap: () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RecentActivityView(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _financeShortcutButton(
                  icon: Icons.wifi_find,
                  label: 'Test Firestore',
                  color: Colors.indigo,
                  onTap: () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FirestoreConnectivityTestView(),
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
                child: _financeShortcutButton(
                  icon: Icons.query_stats,
                  label: 'Thống kê Số liệu',
                  color: Colors.blueGrey,
                  onTap: () => _pushRoute(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const FirebaseRwStatsView(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _financeShortcutButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlerts() {
    // Only show warranty alerts for shops with warranty enabled (electronics)
    if (!_enableWarranty || expiringWarranties == 0) return const SizedBox();
    final canWarranty =
        hasFullAccess || _permissions['allowViewWarranty'] == true;
    if (!canWarranty) return const SizedBox();
    return InkWell(
      onTap: () => _pushRoute(
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
            const Icon(
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
                    loc.warrantyReminder,
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.onError,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "$expiringWarranties ${loc.devicesExpiringWarranty}",
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.onError.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              color: AppColors.onError,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

/// Simple data class for shortcut items
class _ShortcutItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ShortcutItem(this.icon, this.label, this.color, this.onTap);
}

/// Data class for dashboard chart items
class _HomeDashItem {
  final String label;
  final int value;
  final Color color;
  const _HomeDashItem(this.label, this.value, this.color);
}
