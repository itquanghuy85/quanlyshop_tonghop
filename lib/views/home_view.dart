import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'financial_report_view.dart';
import 'financial_activity_log_view.dart';
import 'hr_salary_settings_view.dart';
import 'smart_stock_in_view.dart';
import 'pending_stock_list_view.dart';
import 'user_guide_view.dart';
import '../data/db_helper.dart';
import '../widgets/pending_stock_widget.dart';
import '../widgets/unified_sync_button.dart';
import '../widgets/notification_badge.dart';
import '../widgets/simple_sync_indicator.dart';
import '../widgets/shop_switcher_widget.dart';
import '../widgets/custom_app_bar.dart';
import '../services/sync_service.dart';
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
import '../services/payment_intent_service.dart';
import '../services/adjustment_service.dart';
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
import '../services/test_data_service.dart';
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

class _HomeViewState extends State<HomeView> with TickerProviderStateMixin, WidgetsBindingObserver {
  final db = DBHelper();
  int totalPendingRepair = 0;
  int todaySaleCount = 0;
  int _currentIndex = 0; // Bottom navigation index
  int _totalLocalRecords =
      0; // Tổng số dữ liệu local (để biết máy mới hay không)
  
  /// Getter for localization - dùng chung cho tất cả methods
  AppLocalizations get loc => AppLocalizations.of(context)!;

  _HomeViewState() {
    debugPrint('HomeView: _HomeViewState constructor called');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Lifecycle observer for iOS background handling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotificationStatus();
      _initialSetup();
      SyncService.initRealTimeSync(() {
        _debouncedLoadStats();
      });
      _autoSyncTimer = Timer.periodic(
        const Duration(seconds: 120), // Increase to 120s - real-time sync already handles changes
        (_) => _syncNow(silent: true),
      );

      _eventBusSub = EventBus().stream.listen((event) {
        debugPrint('HomeView: Received event: $event');
        if ((event == 'debts_changed' ||
                event == 'sales_changed' ||
                event == 'repairs_changed' ||
                event == 'expenses_changed' ||
                event == 'products_changed' ||
                event == 'sales_returns_changed' ||
                event == 'financial_activity_changed') &&
            mounted) {
          debugPrint('HomeView: Loading stats for event: $event');
          _debouncedLoadStats();
        }
        // Handle shop change event - reload everything
        if (event == EventBus.shopChanged && mounted) {
          debugPrint('HomeView: Shop changed, reloading all data');
          _initialSetup();
          _debouncedLoadStats();
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
          _updatePermissions();
        }
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    // Re-initialize tabs when locale changes
    if (_currentLocale.languageCode != locale.languageCode || !_tabsInitialized) {
      _currentLocale = locale;
      _initializeTabConfigs();
      _tabsInitialized = true;
    }
  }

  // Tab configurations with permissions
  List<Map<String, dynamic>> _tabConfigs = [];
  List<BottomNavigationBarItem> _navItems = [];
  List<Widget> _tabWidgets = [];

  int _rebuildCounter = 0; // Force rebuild counter
  bool _isLoadingStats = false; // Guard chống load nhiều lần
  bool _cloudBootstrapTried = false;
  bool _cloudBootstrapRunning = false;

  Timer? _autoSyncTimer;
  Timer? _statsDebounceTimer; // Add debounce timer
  StreamSubscription? _eventBusSub; // EventBus subscription
  Map<String, bool> _permissions = {};
  List<dynamic> _lockedByAdmin = []; // Danh sách quyền bị Admin khóa
  List<dynamic> _lockedByOwner = []; // Danh sách quyền bị Chủ shop khóa
  bool _shopLocked = false;
  final TextEditingController _phoneSearchCtrl = TextEditingController();
  bool _isSyncing = false;
  int todayRepairDone = 0;
  int pendingApprovalCount = 0; // Số đơn chờ duyệt giao
  int revenueToday = 0;
  int todayNewRepairs = 0;
  int todayExpense = 0;
  int totalDebtRemain = 0;
  int expiringWarranties = 0;
  int unreadChatCount = 0;
  String _latestChatMessage = ''; // Tin nhắn mới nhất
  String _latestChatSender = ''; // Người gửi tin mới nhất
  Locale _currentLocale = const Locale('vi');
  bool _tabsInitialized = false;
  bool _notificationWorking = false; // Trạng thái thông báo
  String _userName = ''; // Tên hiển thị của người dùng
  String _shopName = ''; // Tên cửa hàng

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
  bool get _enableRepair => _shopSettings?.enableRepair ?? true; // Default true for backwards compat
  bool get _enableExpiry => _shopSettings?.enableExpiry ?? false;
  bool get _enableVariants => _shopSettings?.enableVariants ?? false;
  bool get _enableSerial => _shopSettings?.enableSerial ?? false;
  bool get _enableWarranty => _shopSettings?.enableWarranty ?? true; // Default true for backwards compat
  String get _businessType => _shopSettings?.businessType ?? 'electronics';
  bool get _isElectronics => _businessType == 'electronics';
  bool get _isFashion => _businessType == 'fashion';
  bool get _isFood => _businessType == 'food';
  
  /// Terminology động theo ngành - giúp app hiển thị như được thiết kế riêng cho ngành đó
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);

  final bool _isSuperAdmin = UserService.isCurrentUserSuperAdmin();
  bool get hasFullAccess =>
      widget.role == 'admin' || widget.role == 'owner' || _isSuperAdmin;

  void _initializeTabConfigs() {
    final loc = AppLocalizations.of(context)!;
    _tabConfigs = [
      {
        'permission': null, // Home always accessible
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.home_outlined),
          activeIcon: const Icon(Icons.home_rounded),
          label: loc.homeTab,
        ),
        'widget': _buildHomeTab(),
      },
      {
        'permission': 'allowViewSales',
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.shopping_cart_outlined),
          activeIcon: const Icon(Icons.shopping_cart_rounded),
          label: loc.salesTab,
        ),
        'widget': _buildSalesTab(),
      },
      // Only show Repairs tab for electronics shops
      if (_enableRepair) {
        'permission': 'allowViewRepairs',
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.build_outlined),
          activeIcon: const Icon(Icons.build_rounded),
          label: loc.repairsTab,
        ),
        'widget': _buildRepairsTab(),
      },
      {
        'permission': 'allowViewInventory',
        'item': BottomNavigationBarItem(
          icon: const Icon(Icons.inventory_2_outlined),
          activeIcon: const Icon(Icons.inventory_2_rounded),
          label: loc.inventoryTab,
        ),
        'widget': _buildInventoryTab(),
      },
      // Phase 2: Expiry tab for Food shops
      if (_enableExpiry) {
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
      if (_enableVariants) {
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
        'permission':
            null, // Settings always open for all, only Super Admin can lock
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

  void _updateAvailableTabs() {
    // THAY ĐỔI: Luôn hiển thị tất cả các tab, nhưng thay nội dung bằng màn hình khóa nếu không có quyền
    final allConfigs = _tabConfigs.map((config) {
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

    // Adjust current index if it's out of bounds
    if (_currentIndex >= _navItems.length) {
      _currentIndex = 0;
    }
  }

  /// Rebuild ONLY the home tab widget to reflect updated stats.
  /// Other tabs are self-contained views that load their own data,
  /// so rebuilding them here wastes CPU and causes UI lag (~1 min delay
  /// when entering/exiting shortcut edit mode).
  void _rebuildTabWidgets() {
    if (_tabWidgets.isEmpty) return; // Not initialized yet
    // Update home tab (index 0) - shows dashboard stats
    final homeWidget = _buildHomeTab();
    _tabWidgets[0] = homeWidget;
    _tabConfigs[0]['widget'] = homeWidget; // Keep _tabConfigs in sync for _updateAvailableTabs()
    // Update finance tab - also displays _todayTotalIn/_todayTotalOut/_todayNetProfit from parent state
    // Only rebuild with real content if user has finance permission
    final canViewFinance = hasFullAccess || _permissions['allowViewRevenue'] == true;
    for (int i = 1; i < _tabConfigs.length && i < _tabWidgets.length; i++) {
      final label = (_tabConfigs[i]['item'] as BottomNavigationBarItem).label;
      if (label == loc.financeTab) {
        if (canViewFinance) {
          final financeWidget = _buildFinanceTab();
          _tabWidgets[i] = financeWidget;
          _tabConfigs[i]['widget'] = financeWidget; // Keep _tabConfigs in sync
        }
        // If no permission, keep the locked screen - don't overwrite
        break;
      }
    }
    debugPrint('HomeView: Rebuilt home + finance tabs (stats updated)');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Pause sync timer when app is backgrounded (saves battery on iOS)
      _autoSyncTimer?.cancel();
      _autoSyncTimer = null;
      debugPrint('HomeView: App backgrounded - paused sync timer');
    } else if (state == AppLifecycleState.resumed) {
      // Resume sync timer when app returns to foreground
      if (_autoSyncTimer == null) {
        _autoSyncTimer = Timer.periodic(
          const Duration(seconds: 120),
          (_) => _syncNow(silent: true),
        );
        debugPrint('HomeView: App resumed - restarted sync timer');
        // Quick sync after resume
        _syncNow(silent: true);
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
    super.dispose();
  }

  Future<void> _initialSetup() async {
    try {
      // Load UI ngay lập tức với data local, không chờ Firestore
      // 1. Load permissions và config trước (nhanh)
      _updatePermissions();
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
        final counts = await db.database.then((d) => d.rawQuery(
          'SELECT (SELECT COUNT(*) FROM repairs) + (SELECT COUNT(*) FROM sales) + (SELECT COUNT(*) FROM products) AS total',
        ));
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
          debugPrint('HomeView: shopId missing, forcing syncUserInfo recovery...');
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
        debugPrint('HomeView: Cần cloud download, gọi 1 lần duy nhất...');
        await SyncService.downloadAllFromCloud(force: true).timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            debugPrint('HomeView: Cloud download timeout');
          },
        );
      }

      // 4. Load stats (giờ đã có data)
      _loadStats();

      // Clean duplicate ở background, không block UI
      Future.delayed(const Duration(seconds: 2), () {
        db.cleanDuplicateData();
      });
      
    } catch (e) {
      debugPrint('Error in _initialSetup: $e');
      // Still try to load permissions
      _updatePermissions();
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
          return 'QUAN LY SHOP';
        }
        return name;
      }

      final user = FirebaseAuth.instance.currentUser;
      debugPrint('_loadUserAndShopInfo: START, user=${user?.email}');
      if (user == null) {
        debugPrint('_loadUserAndShopInfo: No user, returning');
        return;
      }

      // ====== TỐI ƯU: Load từ cache trước, hiện UI ngay ======
      final prefs = await SharedPreferences.getInstance();
      final cachedUserName = prefs.getString('cached_userName_${user.uid}');
      final cachedShopName = normalizeLegacyShopName(
        prefs.getString('cached_shopName_${user.uid}'),
      );
      debugPrint('_loadUserAndShopInfo: Cache - userName=$cachedUserName, shopName=$cachedShopName');
      
      // Hiển thị cache ngay lập tức (nếu có và không rỗng)
      if ((cachedUserName != null && cachedUserName.isNotEmpty) || 
          (cachedShopName != null && cachedShopName.isNotEmpty)) {
        if (mounted) {
          setState(() {
            if (cachedUserName != null && cachedUserName.isNotEmpty) _userName = cachedUserName;
            if (cachedShopName != null && cachedShopName.isNotEmpty) _shopName = cachedShopName;
          });
          debugPrint('_loadUserAndShopInfo: Set state from cache - userName=$_userName, shopName=$_shopName');
        }
      }

      // Lấy tên hiển thị qua UserService (Auth displayName -> Firestore -> email fallback)
      // Reload Auth trước để đảm bảo displayName mới nhất (quan trọng cho tài khoản mới đăng ký)
      debugPrint('_loadUserAndShopInfo: Reloading user auth profile...');
      try {
        await user.reload();
      } catch (_) {}
      debugPrint('_loadUserAndShopInfo: Getting displayName via UserService...');
      String displayName = await UserService.getCurrentUserName();
      debugPrint('_loadUserAndShopInfo: displayName=$displayName');

      // Nếu vẫn rỗng, dùng email prefix làm tên
      if (displayName.trim().isEmpty && user.email != null) {
        displayName = user.email!.split('@').first;
        if (displayName.isNotEmpty) {
          displayName = displayName[0].toUpperCase() + displayName.substring(1);
        }
        debugPrint('_loadUserAndShopInfo: Using email fallback displayName=$displayName');
      }

      // ====== SET userName NGAY khi đã có displayName (trước khi fetch shop) ======
      // Đảm bảo tên user luôn hiển thị ngay cả khi bước fetch shop bị lỗi
      if (displayName.isNotEmpty && mounted) {
        setState(() {
          _userName = displayName;
        });
        await prefs.setString('cached_userName_${user.uid}', displayName);
        debugPrint('_loadUserAndShopInfo: SET userName=$displayName (before shop fetch)');
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
            debugPrint('_loadUserAndShopInfo: Token refreshed before shop fetch');
          } catch (_) {}
          debugPrint('_loadUserAndShopInfo: Fetching shop doc from Firestore...');
          final shopDoc = await FirebaseFirestore.instance
              .collection('shops')
              .doc(shopId)
              .get();
          if (shopDoc.exists) {
            final shopData = shopDoc.data();
            debugPrint('_loadUserAndShopInfo: Shop doc data=$shopData');
            shopName = normalizeLegacyShopName(shopData?['name']?.toString());
            debugPrint('_loadUserAndShopInfo: shopName from Firestore=$shopName');
          } else {
            debugPrint('_loadUserAndShopInfo: Shop doc does NOT exist');
          }
        }
      } catch (shopError) {
        debugPrint('_loadUserAndShopInfo: Shop fetch error (userName still safe): $shopError');
        // Fallback: lấy shopName từ SharedPreferences (set bởi SyncService hoặc ShopSettings)
        final fallbackShopName = normalizeLegacyShopName(
          prefs.getString('shop_name'),
        );
        if (fallbackShopName.isNotEmpty) {
          shopName = fallbackShopName;
          debugPrint('_loadUserAndShopInfo: shopName from SharedPreferences fallback=$shopName');
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
        });
        debugPrint('_loadUserAndShopInfo: FINAL setState - userName=$_userName, shopName=$_shopName');
      }

      // Retry: Nếu tên vẫn rỗng (race condition với đăng ký mới), thử lại sau 2s
      if (displayName.trim().isEmpty || displayName == user.email?.split('@').first) {
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
            debugPrint('_loadUserAndShopInfo: ERROR FALLBACK userName=$fallbackName');
          }
        }
      }
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
      // Không gọi downloadAllFromCloud ở đây — real-time listeners đã xử lý
      // Chỉ reload stats từ local DB
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
        _shopSettings = settings;
        _expiryStats = expiryStats;
        _variantWarnings = variantWarnings;
        debugPrint('🏠 HomeView: setState done - _enableRepair=$_enableRepair, _enableVariants=$_enableVariants');
        // Re-initialize tabs when shop settings change
        _initializeTabConfigs();
        _updateAvailableTabs();
      });
      
      // CRITICAL: Nếu chưa có settings, hiện wizard để chọn loại hình kinh doanh
      // Guard để tránh hiện wizard nhiều lần (do EventBus + onShopChanged cùng gọi)
      if (settings == null && mounted && !_isShowingBusinessTypeWizard) {
        debugPrint('🏠 HomeView: No settings found - showing business type wizard');
        _isShowingBusinessTypeWizard = true;
        _showBusinessTypeSetupDialog();
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

      // === BATCH 1: Run all independent DB queries in parallel ===
      final batch1 = await Future.wait([
        // [0] pendingR
        dbConn.rawQuery('SELECT COUNT(*) FROM repairs WHERE status IN (1, 2)'),
        // [1] newRT
        dbConn.rawQuery('SELECT COUNT(*) FROM repairs WHERE createdAt >= ? AND createdAt < ?', [startMs, endMs]),
        // [2] fSales
        dbConn.query('sales',
          columns: ['totalPrice', 'totalCost', 'discount', 'paymentMethod', 'isInstallment', 'downPayment', 'downPaymentMethod', 'settlementReceivedAt', 'settlementAmount', 'loanAmount', 'loanAmount2', 'soldAt', 'warranty'],
          where: 'soldAt >= ? AND soldAt < ?', whereArgs: [startMs, endMs]),
        // [3] fSettlements
        dbConn.query('sales',
          columns: ['totalPrice', 'totalCost', 'discount', 'downPayment', 'settlementAmount', 'loanAmount', 'loanAmount2', 'soldAt'],
          where: 'isInstallment = 1 AND settlementReceivedAt IS NOT NULL AND settlementReceivedAt >= ? AND settlementReceivedAt < ?',
          whereArgs: [startMs, endMs]),
        // [4] fRepairs
        dbConn.query('repairs',
          columns: ['price', 'cost', 'paymentMethod', 'deliveredAt', 'warranty'],
          where: 'status = 4 AND deliveredAt IS NOT NULL AND deliveredAt >= ? AND deliveredAt < ?',
          whereArgs: [startMs, endMs]),
        // [5] fExpenses
        dbConn.query('expenses',
          columns: ['amount', 'category', 'description', 'title', 'date', 'type', 'paymentMethod'],
          where: shopId != null && shopId.isNotEmpty
              ? '(date >= ? AND date < ?) AND (shopId = ? OR shopId IS NULL)'
              : 'date >= ? AND date < ?',
          whereArgs: shopId != null && shopId.isNotEmpty
              ? [startMs, endMs, shopId] : [startMs, endMs]),
        // [6] debtPayments
        dbConn.query('debt_payments',
          columns: ['amount', 'paidAt', 'debtType', 'paymentMethod'],
          where: 'paidAt IS NOT NULL AND paidAt >= ? AND paidAt < ?',
          whereArgs: [startMs, endMs]),
        // [7] partnerPayments
        dbConn.query('repair_partner_payments',
          columns: ['amount', 'paidAt', 'paymentMethod'],
          where: 'paidAt IS NOT NULL AND paidAt >= ? AND paidAt < ? AND (deleted IS NULL OR deleted != 1)',
          whereArgs: [startMs, endMs]),
        // [8] supplierPayments
        dbConn.query('supplier_payments',
          columns: ['amount', 'paidAt', 'paymentMethod'],
          where: 'paidAt IS NOT NULL AND paidAt >= ? AND paidAt < ? AND (deleted IS NULL OR deleted != 1)',
          whereArgs: [startMs, endMs]),
        // [9] supplierImports
        dbConn.query('supplier_import_history',
          columns: ['totalAmount', 'costPrice', 'paymentMethod', 'importDate', 'createdAt'],
          where: '((importDate IS NOT NULL AND importDate >= ? AND importDate < ?) OR (importDate IS NULL AND createdAt >= ? AND createdAt < ?))',
          whereArgs: [startMs, endMs, startMs, endMs]),
        // [10] repairPartsCostFund — repairs with cost recorded in fund today
        dbConn.query('repairs',
          columns: ['cost', 'costRecordedAmount', 'costPaymentMethod'],
          where: 'costRecordedInFund = 1 AND costRecordedAt IS NOT NULL AND costRecordedAt >= ? AND costRecordedAt < ?',
          whereArgs: [startMs, endMs]),
        // [11] pendingApproval — đơn chờ duyệt giao (status 3 + pendingDeliveryApproval = 1)
        dbConn.rawQuery('SELECT COUNT(*) FROM repairs WHERE status = 3 AND pendingDeliveryApproval = 1'),
        // [12] salesReturns — phiếu trả hàng hôm nay (trừ vào doanh thu/quỹ)
        dbConn.query('sales_returns',
          columns: ['totalReturnAmount', 'totalReturnCost', 'refundMethod', 'returnDate'],
          where: 'returnDate >= ? AND returnDate < ? AND status = ?',
          whereArgs: [startMs, endMs, 'APPROVED'])
            .catchError((_) => <Map<String, dynamic>>[]),
      ]);
      debugPrint('HomeView: Batch 1 (13 queries) took ${stopwatch.elapsedMilliseconds}ms');

      final pendingR = Sqflite.firstIntValue(batch1[0] as List<Map<String, dynamic>>) ?? 0;
      final newRT = Sqflite.firstIntValue(batch1[1] as List<Map<String, dynamic>>) ?? 0;
      final fSales = batch1[2] as List<Map<String, dynamic>>;
      final fSettlements = batch1[3] as List<Map<String, dynamic>>;
      final fRepairs = batch1[4] as List<Map<String, dynamic>>;
      final fExpenses = batch1[5] as List<Map<String, dynamic>>;
      final debtPayments = batch1[6] as List<Map<String, dynamic>>;
      final partnerPayments = batch1[7] as List<Map<String, dynamic>>;
      final supplierPayments = batch1[8] as List<Map<String, dynamic>>;
      final supplierImports = batch1[9] as List<Map<String, dynamic>>;
      final repairPartsCostFundRows = batch1[10] as List<Map<String, dynamic>>;
      final pendingApprovalR = Sqflite.firstIntValue(batch1[11] as List<Map<String, dynamic>>) ?? 0;
      final fSalesReturns = batch1[12] as List<Map<String, dynamic>>;

      int doneT = 0, soldT = 0, debtR = 0, expW = 0;

      // === PHÂN TÍCH GIAO DỊCH - MIRROR SỔ QUỸ _analyzeTransactions ===
      // Track cash flow (cashIn/cashOut/bankIn/bankOut) cho biểu đồ THU/CHI
      // Track accrual categories cho CHI TIẾT THU/CHI và LỢI NHUẬN RÒNG
      int cashIn = 0, cashOut = 0, bankIn = 0, bankOut = 0;
      int saleIncome = 0, repairIncome = 0, debtCollected = 0;
      int miscIncome = 0; // Thu phát sinh (type=THU)
      int expenseOut = 0, importOut = 0, supplierPaid = 0;
      int partnerPaid = 0; // TT đối tác sửa chữa (tách riêng khỏi supplierPaid)
      int saleCost = 0, repairCost = 0;
      int settlementIncome = 0;

      // ===== SALES (ACCRUAL BASIS) =====
      for (final s in fSales) {
        final paymentMethod = (s['paymentMethod'] ?? '').toString();
        final totalPrice = (s['totalPrice'] as num?)?.toInt() ?? 0;
        final discount = (s['discount'] as num?)?.toInt() ?? 0;
        final finalPrice = totalPrice - discount > 0 ? totalPrice - discount : 0;
        final totalCost = (s['totalCost'] as num?)?.toInt() ?? 0;
        final isInstallment = (s['isInstallment'] == 1 || s['isInstallment'] == true);

        if (paymentMethod == 'CÔNG NỢ') {
          // Accrual: tính doanh thu (sau giảm giá) + giá vốn, nhưng KHÔNG tăng quỹ tiền
          saleIncome += finalPrice;
          saleCost += totalCost;
          continue;
        }

        if (isInstallment) {
          // Trả góp: chỉ tính phần down vào ngày bán
          final downPaid = (s['downPayment'] as num?)?.toInt() ?? 0;
          saleIncome += downPaid;

          final ratio = finalPrice > 0 ? downPaid / finalPrice : 0.0;
          saleCost += (totalCost * ratio).round();

          final downMethod = (s['downPaymentMethod'] ?? paymentMethod).toString();
          if (downMethod == 'TIỀN MẶT') {
            cashIn += downPaid;
          } else {
            bankIn += downPaid;
          }
        } else {
          saleIncome += finalPrice;
          saleCost += totalCost;
          if (paymentMethod == 'TIỀN MẶT') {
            cashIn += finalPrice;
          } else {
            bankIn += finalPrice;
          }
        }
      }

      // ===== BANK SETTLEMENT (Tất toán NH) =====
      // Query riêng: installment sales settled today (có thể bán ngày khác)
      for (final s in fSettlements) {
        final stlAmount = (s['settlementAmount'] as num?)?.toInt() ?? 0;
        final loanAmount = (s['loanAmount'] as num?)?.toInt() ?? 0;
        final loanAmount2 = (s['loanAmount2'] as num?)?.toInt() ?? 0;
        final totalLoan = loanAmount + loanAmount2;
        final amount = stlAmount.clamp(0, totalLoan);
        if (amount > 0) {
          settlementIncome += amount;
          bankIn += amount;
          // Giá vốn phần còn lại (sau down payment)
          final totalPrice = (s['totalPrice'] as num?)?.toInt() ?? 0;
          final discount = (s['discount'] as num?)?.toInt() ?? 0;
          final finalPrice = totalPrice - discount > 0 ? totalPrice - discount : 0;
          final totalCost = (s['totalCost'] as num?)?.toInt() ?? 0;
          final downPaid = (s['downPayment'] as num?)?.toInt() ?? 0;
          final downRatio = finalPrice > 0 ? downPaid / finalPrice : 0.0;
          final remainRatio = 1.0 - downRatio;
          saleCost += (totalCost * remainRatio).round();
        }
      }

      // ===== REPAIRS (ACCRUAL BASIS) =====
      if (_enableRepair) {
        for (final r in fRepairs) {
          final price = (r['price'] as num?)?.toInt() ?? 0;
          final cost = (r['cost'] as num?)?.toInt() ?? 0;
          final paymentMethod = (r['paymentMethod'] ?? '').toString();
          // Cash-basis for repairs: recognize income/profit only when collected.
          // Delivered debt repairs are excluded until money is actually collected.
          if (paymentMethod == 'CÔNG NỢ') continue;
          repairIncome += price;
          repairCost += cost;
          if (paymentMethod == 'TIỀN MẶT') {
            cashIn += price;
          } else {
            bankIn += price;
          }
        }
      } else {
        for (final r in fRepairs) {
          final price = (r['price'] as num?)?.toInt() ?? 0;
          final cost = (r['cost'] as num?)?.toInt() ?? 0;
          repairIncome += price;
          repairCost += cost;
        }
      }

      // ===== EXPENSES =====
      for (final e in fExpenses) {
        final category = (e['category'] as String? ?? '').toUpperCase();
        final amount = (e['amount'] as num?)?.toInt() ?? 0;
        final eType = (e['type'] as String? ?? '').toUpperCase();
        final method = (e['paymentMethod'] as String? ?? 'TIỀN MẶT').toString();

        // Thu phát sinh (type=THU) → income
        if (eType == 'THU') {
          miscIncome += amount;
          if (method == 'TIỀN MẶT') { cashIn += amount; } else { bankIn += amount; }
          continue;
        }

        // Import expenses (tính riêng)
        final isImport = category.contains('NHẬP') ||
            category.contains('LINH KIỆN') ||
            category.contains('PURCHASE');

        if (method == 'TIỀN MẶT') { cashOut += amount; } else { bankOut += amount; }

        if (!isImport) {
          expenseOut += amount;
        }
      }

      // ===== SUPPLIER IMPORT (with dedup against expenses) =====
      for (final imp in supplierImports) {
        final method = (imp['paymentMethod'] as String? ?? 'TIỀN MẶT').toString();
        if (method == 'CÔNG NỢ') continue;

        final amount = (imp['totalAmount'] ?? imp['costPrice'] ?? 0) as int;
        importOut += amount;

        // Dedup: nếu đã có expense nhập hàng cùng ngày với cùng amount → không tính cash flow lần nữa
        final hasMatchingExpense = fExpenses.any((e) {
          final cat = (e['category'] ?? '').toString().toUpperCase();
          if (!cat.contains('NHẬP') && !cat.contains('LINH KIỆN') && !cat.contains('PURCHASE')) return false;
          final expAmount = (e['amount'] as num?)?.toInt() ?? 0;
          return (expAmount - amount).abs() < 1000;
        });
        if (!hasMatchingExpense) {
          if (method == 'TIỀN MẶT') { cashOut += amount; } else { bankOut += amount; }
        }
      }

      // ===== SUPPLIER PAYMENTS (thanh toán trực tiếp NCC) =====
      for (final p in supplierPayments) {
        final amount = (p['amount'] as num?)?.toInt() ?? 0;
        final method = (p['paymentMethod'] as String? ?? 'TIỀN MẶT').toString();
        supplierPaid += amount;
        if (method == 'TIỀN MẶT') { cashOut += amount; } else { bankOut += amount; }
      }

      // ===== REPAIR PARTNER PAYMENTS (tách riêng khỏi NCC) =====
      if (_enableRepair) {
        for (final p in partnerPayments) {
          final amount = (p['amount'] as num?)?.toInt() ?? 0;
          final method = (p['paymentMethod'] as String? ?? 'TIỀN MẶT').toString();
          partnerPaid += amount;
          if (method == 'TIỀN MẶT') { cashOut += amount; } else { bankOut += amount; }
        }
      }

      // ===== DEBT PAYMENTS =====
      for (final p in debtPayments) {
        final amount = (p['amount'] as num?)?.toInt() ?? 0;
        final method = (p['paymentMethod'] as String? ?? 'TIỀN MẶT').toString();
        final debtType = (p['debtType'] ?? '').toString();

        if (debtType == 'SHOP_OWES' || debtType == 'OTHER_SHOP_OWES') {
          // Trả nợ NCC → chi tiền
          supplierPaid += amount;
          if (method == 'TIỀN MẶT') { cashOut += amount; } else { bankOut += amount; }
        } else {
          // Thu nợ KH → thu tiền (không ảnh hưởng lợi nhuận accrual)
          debtCollected += amount;
          if (method == 'TIỀN MẶT') { cashIn += amount; } else { bankIn += amount; }
        }
      }

      // ===== REPAIR PARTS COST FUND RECORDING =====
      // Chi phí vốn linh kiện đã ghi sổ quỹ → CashOut / BankOut
      int repairPartsCostFund = 0;
      for (final r in repairPartsCostFundRows) {
        final cost = (r['costRecordedAmount'] as num?)?.toInt() ??
            (r['cost'] as num?)?.toInt() ??
            0;
        final method = (r['costPaymentMethod'] as String? ?? 'TIỀN MẶT').toString();
        repairPartsCostFund += cost;
        if (method == 'TIỀN MẶT') { cashOut += cost; } else { bankOut += cost; }
      }

      // ===== SALES RETURNS (TRẢ HÀNG - GIẢM DOANH THU & QUỸ) =====
      int refundOut = 0;
      for (final ret in fSalesReturns) {
        final amount = (ret['totalReturnAmount'] as num?)?.toInt() ?? 0;
        final returnCost = (ret['totalReturnCost'] as num?)?.toInt() ?? 0;
        final method = (ret['refundMethod'] as String? ?? 'TIỀN MẶT').toString();
        if (method == 'CÔNG NỢ') {
          // Giảm công nợ — không ảnh hưởng quỹ tiền mặt
          continue;
        }
        refundOut += amount;
        saleIncome -= amount; // Giảm doanh thu
        saleCost -= returnCost; // Giảm giá vốn (hàng trả lại)
        if (method == 'TIỀN MẶT') { cashOut += amount; } else { bankOut += amount; }
      }

      // ===== KẾT QUẢ =====
      final totalCashFlowIn = cashIn + bankIn;
      final totalCashFlowOut = cashOut + bankOut;

      // LỢI NHUẬN RÒNG (ACCRUAL BASIS) = Doanh thu - Chi phí - Giá vốn
      // saleIncome đã bao gồm cả bán công nợ, trừ trả hàng
      // debtCollected KHÔNG tính vào lợi nhuận (đã tính khi bán)
      final profit = saleIncome + settlementIncome + repairIncome + miscIncome
          - expenseOut - saleCost - repairCost;
      final saleProfit = saleIncome + settlementIncome - saleCost;
      final repairProfit = repairIncome - repairCost;

      // Thống kê số lượng
      doneT = fRepairs.length;
      soldT = fSales.length;

      // === BATCH 2: Secondary queries in parallel ===
      // (warranty, debts, partner debts, record counts - all independent)
      final batch2 = await Future.wait([
        // [0] repairsWarranty
        dbConn.query('repairs',
          columns: ['deliveredAt', 'warranty'],
          where: "deliveredAt IS NOT NULL AND warranty IS NOT NULL AND warranty != '' AND UPPER(warranty) != 'KO BH'"),
        // [1] salesWarranty
        dbConn.query('sales',
          columns: ['soldAt', 'warranty'],
          where: "warranty IS NOT NULL AND warranty != '' AND UPPER(warranty) != 'KO BH'"),
        // [2] debtRemain
        dbConn.rawQuery(
          "SELECT SUM(CASE WHEN totalAmount > paidAmount THEN (totalAmount - paidAmount) ELSE 0 END) as remain "
          "FROM debts WHERE (deleted IS NULL OR deleted != 1) AND (status IS NULL OR UPPER(status) NOT IN ('PAID','CANCELLED'))"),
        // [3] partner debt total (single aggregated query instead of N+1)
        dbConn.rawQuery('''
          SELECT
            COALESCE(SUM(h.totalCost), 0) as totalCost,
            COALESCE(SUM(h.totalPaid), 0) as totalPaid
          FROM (
            SELECT
              p.id as partnerId,
              COALESCE((SELECT SUM(partnerCost) FROM partner_repair_history WHERE partnerId = p.id${shopId != null && shopId.isNotEmpty ? " AND shopId = '$shopId'" : ''}), 0) as totalCost,
              COALESCE((SELECT SUM(amount) FROM repair_partner_payments WHERE partnerId = p.id AND deleted = 0${shopId != null && shopId.isNotEmpty ? " AND shopId = '$shopId'" : ''}), 0) as totalPaid
            FROM repair_partners p
          ) h
          WHERE h.totalCost > h.totalPaid
        '''),
        // [4] record counts (single combined query)
        dbConn.rawQuery(
          'SELECT '
          '(SELECT COUNT(*) FROM repairs) as repairs, '
          '(SELECT COUNT(*) FROM sales) as sales, '
          '(SELECT COUNT(*) FROM products) as products'),
      ]);
      debugPrint('HomeView: Batch 2 (5 queries) took ${stopwatch.elapsedMilliseconds}ms');

      final repairsWarranty = batch2[0] as List<Map<String, dynamic>>;
      final salesWarranty = batch2[1] as List<Map<String, dynamic>>;
      final debtRemainRow = batch2[2] as List<Map<String, dynamic>>;
      final partnerDebtRow = batch2[3] as List<Map<String, dynamic>>;
      final recordCounts = batch2[4] as List<Map<String, dynamic>>;

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

      debtR = (debtRemainRow.first['remain'] as num?)?.toInt() ?? 0;

      // Partner debt from aggregated query
      if (partnerDebtRow.isNotEmpty) {
        final ptCost = (partnerDebtRow.first['totalCost'] as num?)?.toInt() ?? 0;
        final ptPaid = (partnerDebtRow.first['totalPaid'] as num?)?.toInt() ?? 0;
        final ptRemain = ptCost - ptPaid;
        if (ptRemain > 0) debtR += ptRemain;
      }

      final totalRecords = (recordCounts.first['repairs'] as int? ?? 0)
          + (recordCounts.first['sales'] as int? ?? 0)
          + (recordCounts.first['products'] as int? ?? 0);

      // Web bootstrap không cần nữa - đã xử lý ở _initialSetup và main.dart
      // Giữ lại flag để tránh duplicate call từ code cũ
      if (kIsWeb && totalRecords == 0 && !_cloudBootstrapTried && !_cloudBootstrapRunning) {
        _cloudBootstrapTried = true;
        debugPrint('🌐 HomeView: DB vẫn trống sau sync, thử bootstrap lần cuối...');
        // ignore: unawaited_futures
        _bootstrapCoreDataFromCloud();
      }

      debugPrint('HomeView: _loadStats total took ${stopwatch.elapsedMilliseconds}ms');

      if (mounted) {
        setState(() {
          totalPendingRepair = pendingR;
          todayRepairDone = doneT;
          pendingApprovalCount = pendingApprovalR;
          todaySaleCount = soldT;
          revenueToday = profit; // Keep for backward compatibility
          todayNewRepairs = newRT;
          todayExpense = totalCashFlowOut; // Chi phí = cash flow out
          totalDebtRemain = debtR;
          expiringWarranties = expW;
          // Cash flow totals (giống Sổ quỹ: cashIn + bankIn / cashOut + bankOut)
          _todayTotalIn = totalCashFlowIn;
          _todayTotalOut = totalCashFlowOut;
          _todayNetProfit = profit;
          _todaySalesProfit = saleProfit;
          _todayRepairProfit = repairProfit;
          _todayRepairCount = fRepairs.length;
          _todaySaleOrderCount = fSales.length;
          _todayExpenseCount = fExpenses.where((e) => (e['type'] as String? ?? '').toUpperCase() != 'THU').length;
          _todayStockInCost = importOut;
          _todayDebtPaidToSupplier = supplierPaid; // Chỉ NCC + shop_owes debt
          _todayExpenseOnly = expenseOut;
          // Detail breakdown (giống Sổ quỹ analysis)
          _todaySaleIncome = saleIncome;
          _todayRepairIncome = repairIncome;
          _todayDebtCollected = debtCollected;
          _todayMiscIncome = miscIncome;
          _todayImportOut = importOut;
          _todayPartnerPaid = partnerPaid; // TT đối tác sửa chữa (tách riêng)
          _todayRepairPartsCostFund = repairPartsCostFund; // Vốn LK SC đã ghi sổ quỹ
          _todaySaleCost = saleCost;
          _todayRepairCost = repairCost;
          _todaySettlementIncome = settlementIncome;
          _totalLocalRecords = totalRecords;
          _rebuildTabWidgets();
        });
      }

      // === DEFERRED: Load chat info from Firestore (don't block dashboard) ===
      _loadChatInfo();
    } finally {
      _isLoadingStats = false;
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
    return WillPopScope(
      onWillPop: () async {
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
                onPressed: () => SystemNavigator.pop(),
                child: Text(loc.exit),
              ),
            ],
          ),
        );
        return ok ?? false;
      },
      child: Scaffold(
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
                onPressed: () => Navigator.push(
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
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QrScanView(role: widget.role),
                ),
              ),
              icon: const Icon(
                Icons.qr_code_scanner_rounded,
                color: Colors.white,
              ),
            ),
            IconButton(
              onPressed: () => Navigator.push(
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
              onPressed: () async {
                await SyncService.cancelAllSubscriptions();
                EncryptionService.reset(); // Reset mã hóa khi đăng xuất
                UserService.clearCache(); // Xóa cache shopId
                CurrentShopService().clear(); // Clear multi-shop cache
                UserService.setAdminSelectedShop(
                  null,
                ); // Xóa shop đã chọn của admin
                await DBHelper().clearAllData(); // Xóa dữ liệu local
                try {
                  await FirebaseAuth.instance.signOut();
                } catch (e) {
                  debugPrint('Logout error: $e');
                }
              },
              icon: const Icon(Icons.logout_rounded, color: AppColors.error),
            ),
          ],
        ),
        body: _buildResponsiveBody(),
        bottomNavigationBar: _buildResponsiveBottomNav(),
      ),
    );
  }

  /// Responsive body: NavigationRail on wide screens, IndexedStack on mobile
  Widget _buildResponsiveBody() {
    final r = context.responsive;
    if (r.isWideLayout && _navItems.length >= 2) {
      return Row(
        children: [
          SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - kToolbarHeight - MediaQuery.of(context).padding.top),
              child: IntrinsicHeight(
                child: NavigationRail(
                  selectedIndex: _currentIndex.clamp(0, _navItems.length - 1),
                  onDestinationSelected: (index) {
                    HapticFeedback.lightImpact();
                    setState(() => _currentIndex = index);
                  },
                  labelType: NavigationRailLabelType.all,
                  backgroundColor: AppColors.surface,
                  selectedIconTheme: const IconThemeData(color: AppColors.primary),
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
              children: _tabWidgets,
            ),
          ),
        ],
      );
    }
    return IndexedStack(
      index: _currentIndex,
      children: _tabWidgets,
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
          setState(() => _currentIndex = index);
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
      final canViewFinance = hasFullAccess || _permissions['allowViewRevenue'] == true;
      if (config.requiresFinanceAccess && !canViewFinance) {
        continue;
      }

      switch (config.type) {
        case DashboardCardType.greeting:
          widgets.add(_buildGreetingCard());
          break;
        case DashboardCardType.actionRequired:
          final canRepair = hasFullAccess || _permissions['allowViewRepairs'] == true;
          final canStock = hasFullAccess || _permissions['allowViewInventory'] == true;
          final canWarranty = hasFullAccess || _permissions['allowViewWarranty'] == true;
          widgets.add(ActionRequiredCard(
            key: const ValueKey('action_required'),
            enableRepair: _enableRepair && canRepair,
            enableWarranty: _enableWarranty && canWarranty,
            enableExpiry: _enableExpiry && canStock,
            onPendingRepairsTap: canRepair ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderListView(
                  role: widget.role,
                  statusFilter: const [1, 2],
                ),
              ),
            ) : null,
            onPendingStockTap: canStock ? () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PendingStockListView(),
              ),
            ) : null,
            onWarrantyTap: canWarranty ? () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WarrantyView()),
            ) : null,
          ));
          break;
        case DashboardCardType.quickActions:
          widgets.add(_buildUnifiedShortcuts());
          break;
        case DashboardCardType.financeSummary:
          widgets.add(FinanceSummaryCard(
            key: const ValueKey('finance_summary'),
            totalIn: _todayTotalIn,
            totalOut: _todayTotalOut,
            netProfit: _todayNetProfit,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CashClosingView()),
            ),
          ));
          break;
        case DashboardCardType.financeDetail:
          widgets.add(_buildSectionHeader("TỔNG QUAN TÀI CHÍNH"));
          widgets.add(_buildDashboardOverview());
          widgets.add(const SizedBox(height: 10));
          break;
        case DashboardCardType.activityFeed:
          widgets.add(ActivityFeedCard(
            key: const ValueKey('activity_feed'),
            enableRepair: _enableRepair,
          ));
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
        _rebuildTabWidgets();
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
              Icon(Icons.dashboard_customize, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              Text(
                'Tùy chỉnh',
                style: TextStyle(
                  fontSize: 11,
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
    } else if (widget.role == 'owner') {
      roleText = loc.ownerRole;
      roleColor = Colors.orange;
      roleIcon = Icons.store;
    } else if (widget.role == 'admin') {
      roleText = loc.managerRole;
      roleColor = Colors.blue;
      roleIcon = Icons.manage_accounts;
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
                          : (FirebaseAuth.instance.currentUser?.email?.split('@').first ?? loc.userLabel),
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
                  _buildDataItem(Icons.people, loc.customersAndSuppliersDataItem),
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
        NotificationService.showSnackBar("❌ ${loc.downloadError(e.toString())}", color: Colors.red);
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
          onTap: () => Navigator.push(
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
                              fontSize: 9,
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
                            "CHAT NHÓM",
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
                                  fontSize: 10,
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
    final canEdit = await AdjustmentService.canEditDirectly(today.millisecondsSinceEpoch);
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.remove_circle, color: Colors.red.shade700, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text("GHI CHI PHÍ NHANH", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("PHÂN LOẠI", style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ["CỐ ĐỊNH", "PHÁT SINH", "LƯƠNG", "MẶT BẰNG", "ĐIỆN NƯỚC", "KHÁC"].map(
                        (c) => ChoiceChip(
                          label: Text(c, style: const TextStyle(fontSize: 11)),
                          selected: category == c,
                          onSelected: (v) => setS(() => category = c),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: "Nội dung chi *",
                        prefixIcon: Icon(Icons.edit_note, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập nội dung' : null,
                    ),
                    const SizedBox(height: 10),
                    CurrencyTextField(
                      controller: amountC,
                      label: "Số tiền (VNĐ) *",
                      icon: Icons.payments,
                      validator: (v) => input_money.MoneyUtils.validateAmount(v ?? '', min: 1, fieldName: 'Số tiền'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteC,
                      decoration: const InputDecoration(
                        labelText: "Ghi chú",
                        prefixIcon: Icon(Icons.description, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Text("THANH TOÁN", style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: ["TIỀN MẶT", "CHUYỂN KHOẢN"].map(
                        (m) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ChoiceChip(
                              label: Text(m, style: const TextStyle(fontSize: 11)),
                              selected: payMethod == m,
                              onSelected: (v) => setS(() => payMethod = m),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("HỦY")),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: _quickSaving ? null : () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  setState(() => _quickSaving = true);
                  final amount = input_money.MoneyUtils.parseCurrency(amountC.text);
                  final user = FirebaseAuth.instance.currentUser;
                  final method = payMethod == 'CHUYỂN KHOẢN' ? PaymentMethod.transfer : PaymentMethod.cash;
                  Navigator.of(ctx).pop();
                  final result = await PaymentIntentService.executePaymentDirect(
                    type: (category == 'ĐIỆN NƯỚC' || category == 'INTERNET')
                        ? PaymentIntentType.utilityExpense
                        : PaymentIntentType.operatingExpense,
                    amount: amount,
                    paymentMethod: method,
                    description: '${titleC.text.toUpperCase()}${noteC.text.isNotEmpty ? " - ${noteC.text}" : ""}',
                    executedBy: user?.displayName ?? user?.email ?? 'unknown',
                    metadata: {'category': category, 'title': titleC.text.toUpperCase(), 'note': noteC.text},
                  );
                  if (result != null && result.success) {
                    EventBus().emit('expenses_changed');
                    NotificationService.showSnackBar("✅ Đã lưu chi phí!", color: AppColors.success);
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
    final canEdit = await AdjustmentService.canEditDirectly(today.millisecondsSinceEpoch);
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.add_circle, color: Colors.green.shade700, size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(child: Text("GHI THU PHÁT SINH", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green))),
              ],
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("PHÂN LOẠI", style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ["PHÁT SINH", "DỊCH VỤ", "HOÀN TIỀN", "BÁN TÀI SẢN", "KHÁC"].map(
                        (c) => ChoiceChip(
                          label: Text(c, style: const TextStyle(fontSize: 11)),
                          selected: category == c,
                          onSelected: (v) => setS(() => category = c),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ).toList(),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: titleC,
                      decoration: const InputDecoration(
                        labelText: "Nội dung thu *",
                        prefixIcon: Icon(Icons.edit_note, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Nhập nội dung' : null,
                    ),
                    const SizedBox(height: 10),
                    CurrencyTextField(
                      controller: amountC,
                      label: "Số tiền (VNĐ) *",
                      icon: Icons.payments,
                      validator: (v) => input_money.MoneyUtils.validateAmount(v ?? '', min: 1, fieldName: 'Số tiền'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: noteC,
                      decoration: const InputDecoration(
                        labelText: "Ghi chú",
                        prefixIcon: Icon(Icons.description, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Text("THANH TOÁN", style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Row(
                      children: ["TIỀN MẶT", "CHUYỂN KHOẢN"].map(
                        (m) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: ChoiceChip(
                              label: Text(m, style: const TextStyle(fontSize: 11)),
                              selected: payMethod == m,
                              onSelected: (v) => setS(() => payMethod = m),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ).toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("HỦY")),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                onPressed: _quickSaving ? null : () async {
                  if (!(formKey.currentState?.validate() ?? false)) return;
                  setState(() => _quickSaving = true);
                  final amount = input_money.MoneyUtils.parseCurrency(amountC.text);
                  final user = FirebaseAuth.instance.currentUser;
                  final method = payMethod == 'CHUYỂN KHOẢN' ? PaymentMethod.transfer : PaymentMethod.cash;
                  Navigator.of(ctx).pop();
                  final result = await PaymentIntentService.executePaymentDirect(
                    type: PaymentIntentType.otherIncome,
                    amount: amount,
                    paymentMethod: method,
                    description: '${titleC.text.toUpperCase()}${noteC.text.isNotEmpty ? " - ${noteC.text}" : ""}',
                    executedBy: user?.displayName ?? user?.email ?? 'unknown',
                    metadata: {'category': category, 'title': titleC.text.toUpperCase(), 'note': noteC.text},
                  );
                  if (result != null && result.success) {
                    EventBus().emit('expenses_changed');
                    NotificationService.showSnackBar("✅ Đã lưu thu phát sinh!", color: AppColors.success);
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
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSaleView()));
        case ShortcutType.repairCreate:
          return _enableRepair ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateRepairOrderView(role: widget.role))) : null;
        case ShortcutType.stockIn:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartStockInView()));
        case ShortcutType.pendingStock:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingStockListView()));
        case ShortcutType.saleList:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SaleListView()));
        case ShortcutType.repairList:
          return _enableRepair ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderListView())) : null;
        case ShortcutType.addExpense:
          return _showQuickExpenseDialog;
        case ShortcutType.addIncome:
          return _showQuickIncomeDialog;
        case ShortcutType.inventoryCheck:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FastInventoryCheckView()));
        case ShortcutType.report:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RevenueView()));
        case ShortcutType.attendance:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceView()));
        case ShortcutType.warranty:
          return _enableWarranty ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WarrantyView())) : null;
        case ShortcutType.cashClosing:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CashClosingView()));
        case ShortcutType.customers:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerManagementView()));
        case ShortcutType.suppliers:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SupplierListView()));
        case ShortcutType.debt:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DebtView()));
        case ShortcutType.qrScan:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScanView()));
        case ShortcutType.financialReport:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancialReportView()));
        case ShortcutType.activityLog:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FinancialActivityLogView()));
        case ShortcutType.printer:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrinterSettingsView()));
        case ShortcutType.quickCodes:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QuickInputCodesView()));
        case ShortcutType.bankInstallment:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BankInstallmentReportView()));
        case ShortcutType.globalSearch:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => GlobalSearchView(role: widget.role)));
        case ShortcutType.staff:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffListView()));
        case ShortcutType.expenses:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseView()));
        case ShortcutType.expiryManage:
          return () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpiryManagementView()));
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
        items.add(_ShortcutItem(config.icon, config.displayName, config.color, action));
      }
    } else {
      // Fallback: no config loaded yet - build defaults with permission checks
      final _p = _permissions;
      final _fa = hasFullAccess;
      bool _ok(String? perm) => _fa || perm == null || (_p[perm] == true);
      items = <_ShortcutItem>[
        if (_ok('allowViewSales'))
          _ShortcutItem(Icons.add_shopping_cart, 'Bán hàng', Colors.green, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateSaleView()))),
        if (_enableRepair && _ok('allowViewRepairs'))
          _ShortcutItem(Icons.build_circle, 'Đơn sửa', Colors.blue, () => Navigator.push(context, MaterialPageRoute(builder: (_) => CreateRepairOrderView(role: widget.role)))),
        if (_ok('allowViewInventory'))
          _ShortcutItem(Icons.add_box, 'Nhập kho', Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SmartStockInView()))),
        if (_ok('allowViewInventory'))
          _ShortcutItem(Icons.pending_actions, 'Chờ XN', Colors.orange, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PendingStockListView()))),
        if (_ok('allowViewSales'))
          _ShortcutItem(Icons.receipt_long, 'Đơn bán', Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SaleListView()))),
        if (_enableRepair && _ok('allowViewRepairs'))
          _ShortcutItem(Icons.list_alt, 'DS sửa', Colors.deepPurple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OrderListView()))),
        if (_ok('allowViewExpenses'))
          _ShortcutItem(Icons.remove_circle_outline, 'Thêm chi', Colors.red, _showQuickExpenseDialog),
        if (_ok('allowViewRevenue'))
          _ShortcutItem(Icons.add_circle_outline, 'Thêm thu', Colors.green.shade700, _showQuickIncomeDialog),
        if (_ok('allowViewInventory'))
          _ShortcutItem(Icons.qr_code_scanner, 'Kiểm kho', Colors.cyan, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FastInventoryCheckView()))),
        if (_ok('allowViewRevenue'))
          _ShortcutItem(Icons.bar_chart, 'Báo cáo', Colors.purple, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RevenueView()))),
        if (_ok('allowViewAttendance'))
          _ShortcutItem(Icons.access_time, 'Chấm công', Colors.teal.shade700, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AttendanceView()))),
        if (_enableWarranty && _ok('allowViewWarranty'))
          _ShortcutItem(Icons.shield, 'Bảo hành', Colors.amber.shade800, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WarrantyView()))),
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 3),
                          Text(
                            'Sửa',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
                children: items.map((item) => SizedBox(
                  width: itemWidth,
                  child: InkWell(
                onTap: item.onTap,
                onLongPress: _shortcutConfigLoaded ? () {
                  HapticFeedback.mediumImpact();
                  setState(() => _shortcutEditMode = true);
                } : null,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: vPad),
                  decoration: BoxDecoration(
                    color: item.color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: item.color.withOpacity(0.2)),
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
                        child: Icon(item.icon, color: item.color, size: iconSize),
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
            )).toList(),
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
                Icon(Icons.dashboard_customize, size: 14, color: Colors.blue.shade700),
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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade600,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'Xong',
                      style: TextStyle(
                        fontSize: 12,
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
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
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
              final borderColor = isVisible ? config.color.withOpacity(0.3) : Colors.grey.shade200;

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
                                color: color.withOpacity(isVisible ? 0.15 : 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                config.icon,
                                color: color.withOpacity(isVisible ? 1.0 : 0.5),
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
                                  color: isVisible ? Colors.green : Colors.grey.shade300,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 1.5),
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
                            fontSize: 10,
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune, size: 14, color: Colors.blue.shade400),
                    const SizedBox(width: 4),
                    Text(
                      'Sắp xếp thứ tự & cài đặt nâng cao',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right, size: 16, color: Colors.blue.shade400),
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
              Expanded(
                child: _buildPinnedCard(
                  icon: Icons.pending_actions,
                  title: loc.pendingStockShort,
                  subtitle: loc.stockIn,
                  color: Colors.orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PendingStockListView(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Thu Chi
              Expanded(
                child: _buildPinnedCard(
                  icon: Icons.account_balance_wallet,
                  title: loc.incomeExpense,
                  subtitle: 'Ghi thu chi',
                  color: Colors.green,
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
          const SizedBox(height: 8),
          Row(
            children: [
              // Danh sách đơn bán
              Expanded(
                child: _buildPinnedCard(
                  icon: Icons.receipt_long,
                  title: loc.salesOrder,
                  subtitle: loc.salesOrderList,
                  color: Colors.blue,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SaleListView(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Danh sách đơn sửa - only show for electronics shops
              if (_enableRepair)
                Expanded(
                  child: _buildPinnedCard(
                    icon: Icons.build_circle,
                    title: loc.repairOrderTitle,
                    subtitle: loc.repairOrderList,
                    color: Colors.deepPurple,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const OrderListView(),
                      ),
                    ),
                  ),
                ),
              // Alternative shortcut for non-electronics shops
              if (!_enableRepair)
                Expanded(
                  child: _buildPinnedCard(
                    icon: Icons.people,
                    title: loc.customers,
                    subtitle: loc.customersAndSuppliers,
                    color: Colors.teal,
                    onTap: () => Navigator.push(
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
    return Column(
      children: [
        // BÁN HÀNG
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
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CreateSaleView()),
            ),
          ),
        ),
        const SizedBox(height: 6),

        // SỬA CHỮA - Only show for electronics shops
        if (_enableRepair)
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
              style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
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
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateRepairOrderView(role: widget.role),
              ),
            ),
          ),
        ),
        if (_enableRepair) const SizedBox(height: 6),

        // Row: Nhập kho & Kiểm kho
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
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SmartStockInView()),
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
                  onTap: () => Navigator.push(
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
        const SizedBox(height: 6),

        // Row: Báo cáo & Chấm công
        Row(
          children: [
            Expanded(
              child: Card(
                color: Colors.indigo.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.indigo.shade200),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
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
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                color: Colors.teal.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.teal.shade200),
                ),
                child: InkWell(
                  onTap: () => Navigator.push(
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
            Expanded(
              child: Card(
                color: Colors.red.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.red.shade300, width: 2),
                ),
                child: InkWell(
                  onTap: _showQuickExpenseDialog,
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
            const SizedBox(width: 8),
            Expanded(
              child: Card(
                color: Colors.green.shade50,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: Colors.green.shade300, width: 2),
                ),
                child: InkWell(
                  onTap: _showQuickIncomeDialog,
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
        if (_enableWarranty)
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
              child: Icon(Icons.shield, color: Colors.amber.shade800, size: 18),
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
            onTap: () => Navigator.push(
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _quickActionButton(
                loc.createSale,
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
                loc.createRepair,
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
                loc.stockIn,
                Icons.inventory,
                AppColors.success,
                () => Navigator.push(
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
                () => Navigator.push(
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
            Expanded(
              child: _quickActionButton(
                loc.revenueReport,
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
                loc.attendance,
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
                  MaterialPageRoute(builder: (_) => const AdvancedChatView()),
                ),
                // Badge đã ẩn theo yêu cầu
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
          _buildTabHeader(loc.sales.toUpperCase(), Icons.shopping_cart, Colors.green),
          const SizedBox(height: 10),

          // Quick Action - Tạo đơn bán
          _buildSectionHeader(loc.quickActions),
          _financeQuickCard(
            loc.createNewSaleOrder,
            Icons.add_shopping_cart,
            Colors.green,
            () => Navigator.push(
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
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SaleListView()),
                ),
                subtitle: loc.viewSearchTrackSales,
              ),
              _tabMenuItem(
                loc.customerManagement,
                Icons.people,
                Colors.blue,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CustomerManagementView()),
                ),
                subtitle: loc.addEditViewCustomers,
              ),
              _tabMenuItem(
                loc.warranty,
                Icons.verified_user,
                Colors.orange,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WarrantyView()),
                ),
                subtitle: loc.viewProcessWarrantyRequests,
              ),
              _tabMenuItem(
                'Trả hàng',
                Icons.assignment_return,
                Colors.red,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SalesReturnListView()),
                ),
                subtitle: 'Danh sách phiếu trả hàng',
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
          _buildTabHeader(loc.repairsTab.toUpperCase(), Icons.build, Colors.blue),
          const SizedBox(height: 10),          // Quick Action - Tạo đơn sửa
          _buildSectionHeader(loc.quickActions),
          _financeQuickCard(
            loc.createNewRepairOrder,
            Icons.build_circle,
            Colors.blue,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CreateRepairOrderView(role: widget.role),
              ),
            ),
          ),

          const SizedBox(height: 10),
          _buildSectionHeader(loc.management),
          _tabMenuItem(
            loc.repairOrderList,
            Icons.list_alt,
            Colors.indigo,
            () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => OrderListView(role: widget.role),
              ),
            ),
            subtitle: loc.viewSearchTrackRepairs,
          ),
          // Kho Phụ Tùng đã được chuyển vào tab Linh kiện trong QUẢN LÝ KHO
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
          _buildTabHeader(loc.inventoryManagement, Icons.inventory_2, Colors.orange),
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
                Icon(Icons.info_outline, size: 14, color: Colors.grey.shade600),
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
                    onTap: () => Navigator.push(
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
                    onTap: () => Navigator.push(
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
                    onTap: () => Navigator.push(
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
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PendingStockListView()),
                ),
                subtitle: loc.viewPendingStockList,
              ),
              _tabMenuItem(
                loc.productList,
                Icons.inventory,
                Colors.blue,
                () => Navigator.push(
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
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SupplierListView()),
                ),
                subtitle: loc.manageSupplierPartnerDebt,
              ),
              _tabMenuItem(
                loc.quickInputCodeList,
                Icons.qr_code,
                Colors.indigo,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QuickInputCodesView()),
                ),
                subtitle: loc.viewManageQuickInputCodes,
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildStaffTab() {
    if (!hasFullAccess && _permissions['allowManageStaff'] != true) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_person, size: 64, color: Colors.orange.shade300),
              const SizedBox(height: 16),
              Text(
                loc.noAccessPermission,
                style: AppTextStyles.headline3.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                loc.contactOwnerForAccess,
                style: AppTextStyles.subtitle1.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }
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
            () => Navigator.push(
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
            crossAxisCount: context.responsive.isMobile ? 2 : (context.responsive.isDesktop ? 4 : 3),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: context.responsive.isMobile ? 2.5 : 3.2,
            children: [
              _staffQuickCard(
                loc.staffListLabel,
                Icons.people,
                Colors.blue,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const StaffListView()),
                ),
              ),
              _staffQuickCardWithHelp(
                loc.salaryCalculation,
                Icons.bar_chart,
                Colors.orange,
                () => Navigator.push(
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
                () => Navigator.push(
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
                () => Navigator.push(
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
                () => Navigator.push(
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
                () => Navigator.push(
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
              Icon(Icons.chevron_right, color: color.withOpacity(0.4), size: 16),
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
                icon: Icon(Icons.help_outline, color: color.withOpacity(0.5), size: 14),
                onPressed: onHelpTap,
                tooltip: loc.usageGuide,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right, color: color.withOpacity(0.4), size: 16),
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
              Navigator.push(
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
            _financeOverviewSection(),

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
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CashClosingView()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _financeQuickCard(
                    'Thu Chi',
                    Icons.swap_vert,
                    Colors.blue,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ExpenseView()),
                    ),
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
              crossAxisCount: context.responsive.isMobile ? 2 : (context.responsive.isDesktop ? 4 : 3),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: context.responsive.isMobile ? 2.5 : 3.2,
              children: [
                _financeQuickCard(
                  'Báo cáo doanh thu',
                  Icons.trending_up,
                  Colors.blue,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RevenueView()),
                  ),
                ),
                _financeQuickCard(
                  'Quản lý công nợ',
                  Icons.account_balance,
                  Colors.orange,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DebtView()),
                  ),
                ),
                _financeQuickCard(
                  'Trả góp NH',
                  Icons.credit_score,
                  Colors.deepOrange,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BankInstallmentReportView(),
                    ),
                  ),
                ),
                _financeQuickCard(
                  'Nhà cung cấp',
                  Icons.local_shipping,
                  Colors.teal,
                  () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SupplierListView()),
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
              Icon(Icons.chevron_right, color: color.withOpacity(0.4), size: 16),
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
          // THU và CHI row
          Row(
            children: [
              Expanded(
                child: _financeStatCard(
                  icon: Icons.arrow_circle_down_rounded,
                  label: loc.todayIncome,
                  value: _todayTotalIn,
                  color: AppColors.success,
                  detail: _enableRepair
                      ? "$_todaySaleOrderCount ${loc.sales} + $_todayRepairCount ${loc.repair}"
                      : "$_todaySaleOrderCount ${loc.sales}",
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CashClosingView()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _financeStatCard(
                  icon: Icons.arrow_circle_up_rounded,
                  label: loc.todayExpense,
                  value: _todayTotalOut,
                  color: AppColors.error,
                  detail: _buildExpenseDetail(loc),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CashClosingView()),
                  ),
                ),
              ),
            ],
          ),
          
          // CHI PHÍ NHẬP KHO - Hiển thị riêng nếu có
          if (_todayStockInCost > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: Colors.orange.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Chi nhập kho hôm nay: ',
                    style: AppTextStyles.body1.copyWith(color: Colors.orange.shade800),
                  ),
                  Expanded(
                    child: Text(
                      '${MoneyUtils.formatVND(_todayStockInCost)}đ',
                      style: AppTextStyles.subtitle1.copyWith(
                        color: Colors.orange.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),

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
                        "${MoneyUtils.formatVND(_todayNetProfit)} đ",
                        style: AppTextStyles.headline5.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '🛒 ${MoneyUtils.formatVND(_todaySalesProfit)}',
                            style: AppTextStyles.overline.copyWith(
                              color: Colors.white.withOpacity(0.85),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (_enableRepair) ...[
                            Text(
                              '  •  ',
                              style: AppTextStyles.overline.copyWith(color: Colors.white54),
                            ),
                            Text(
                              '🔧 ${MoneyUtils.formatVND(_todayRepairProfit)}',
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
                  const Icon(
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
                          loc.totalDebt,
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

  /// Chi tiết breakdown chi phí hôm nay
  String _buildExpenseDetail(AppLocalizations loc) {
    final parts = <String>[];
    if (_todayExpenseOnly > 0) {
      parts.add('$_todayExpenseCount ${loc.expenseItems}: ${MoneyUtils.formatVND(_todayExpenseOnly)}đ');
    } else if (_todayExpenseCount > 0) {
      parts.add('$_todayExpenseCount ${loc.expenseItems}');
    }
    if (_todayDebtPaidToSupplier > 0) {
      parts.add('Trả nợ NCC: ${MoneyUtils.formatVND(_todayDebtPaidToSupplier)}đ');
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
              "${MoneyUtils.formatVND(value)} đ",
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
    final currentLangLabel =
        _currentLocale.languageCode == 'en' ? loc.english : loc.vietnamese;

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
            style: AppTextStyles.headline6.copyWith(color: AppColors.onSurface),
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
              () => Navigator.push(
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
                () => Navigator.push(
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
                () => Navigator.push(
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
                  () => Navigator.push(
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
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AboutDeveloperView()),
                ),
                subtitle: loc.aboutDeveloperDescription,
              ),
            ],
          ),

          // Đăng xuất ở cuối
          const SizedBox(height: 20),
          if (kDebugMode)
            _buildTestDataButton(),
          if (kDebugMode)
            const SizedBox(height: 10),
          _buildLogoutCard(),
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
        title: const Text('🧪 Tạo Data Test', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Tạo sản phẩm, đơn bán, chi phí, trả hàng để debug'),
        onTap: () async {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Tạo Data Test?'),
              content: const Text('Sẽ tạo 8 SP, 4 đơn bán, 4 chi phí, 1 trả hàng.\nDữ liệu sẽ hiển thị trên dashboard.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tạo ngay')),
              ],
            ),
          );
          if (confirm != true) return;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đang tạo data test...'), duration: Duration(seconds: 2)),
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
                    FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
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
          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
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
            try {
              await SyncService.cancelAllSubscriptions();
              UserService.clearCache();
              await DBHelper().clearAllData();
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
                  title: Text(
                    loc.checkingSync,
                    style: AppTextStyles.headline5,
                  ),
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
    // Cash flow totals - giống hệt Sổ quỹ (cashIn + bankIn / cashOut + bankOut)
    final totalIncome = _todayTotalIn;
    final totalExpense = _todayTotalOut;
    final maxVal = totalIncome > totalExpense ? totalIncome : totalExpense;
    final incomeRatio = maxVal > 0 ? totalIncome / maxVal : 0.0;
    final expenseRatio = maxVal > 0 ? totalExpense / maxVal : 0.0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const CashClosingView()),
      ),
      child: Container(
        key: ValueKey('dashboard_overview_${_todayTotalIn}_${_todayTotalOut}'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // BIẾN ĐỘNG TRONG NGÀY header - giống Sổ quỹ
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.bar_chart, color: Colors.orange, size: 20),
                ),
                const SizedBox(width: 10),
                Text(
                  "BIẾN ĐỘNG TRONG NGÀY",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                    fontSize: AppTextStyles.headline4.fontSize,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Bar chart - responsive height/width
            LayoutBuilder(
              builder: (context, constraints) {
                final r = context.responsive;
                final barH = r.isDesktop ? 120.0 : (r.isTablet ? 110.0 : 100.0);
                final barW = r.isDesktop ? 70.0 : (r.isTablet ? 60.0 : 50.0);
            return Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: barH,
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: barW,
                          height: barH * incomeRatio,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.green.shade300, Colors.green.shade600],
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "📥 THU",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.subtitle1.fontSize,
                        ),
                      ),
                      Text(
                        "+${MoneyUtils.formatVND(totalIncome)}",
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.headline5.fontSize,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Container(
                        height: barH,
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: barW,
                          height: barH * expenseRatio,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.red.shade300, Colors.red.shade600],
                            ),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "📤 CHI",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.subtitle1.fontSize,
                        ),
                      ),
                      Text(
                        "-${MoneyUtils.formatVND(totalExpense)}",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.headline5.fontSize,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
              },
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            // CHI TIẾT THU / CHI - giống Sổ quỹ
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "📥 CHI TIẾT THU",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.body1.fontSize,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _homeBreakdownItem("Bán hàng", _todaySaleIncome, Colors.green),
                      _homeBreakdownItem("Tất toán NH", _todaySettlementIncome, Colors.green),
                      if (_enableRepair)
                        _homeBreakdownItem("Sửa chữa", _todayRepairIncome, Colors.green),
                      _homeBreakdownItem("Thu nợ KH", _todayDebtCollected, Colors.green),
                      _homeBreakdownItem("Thu phát sinh", _todayMiscIncome, Colors.teal),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "📤 CHI TIẾT CHI",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.body1.fontSize,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _homeBreakdownItem("Chi phí", _todayExpenseOnly, Colors.red),
                      _homeBreakdownItem("Nhập hàng", _todayImportOut, Colors.red),
                      _homeBreakdownItem("Trả nợ NCC", _todayDebtPaidToSupplier, Colors.red),
                      if (_todayPartnerPaid > 0)
                        _homeBreakdownItem("TT đối tác SC", _todayPartnerPaid, Colors.red),
                      if (_todayRepairPartsCostFund > 0)
                        _homeBreakdownItem("Vốn LK SC", _todayRepairPartsCostFund, Colors.red),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            // LỢI NHUẬN RÒNG - giống Sổ quỹ
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _todayNetProfit >= 0 ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _todayNetProfit >= 0 ? Colors.green.shade200 : Colors.red.shade200,
                ),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "💰 LỢI NHUẬN RÒNG",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.headline5.fontSize,
                        ),
                      ),
                      Text(
                        "${_todayNetProfit >= 0 ? '+' : ''}${MoneyUtils.formatVND(_todayNetProfit)}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.headline3.fontSize,
                          color: _todayNetProfit >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _homeBreakdownItem("Giá vốn bán", _todaySaleCost, Colors.orange),
                      ),
                      Expanded(
                        child: _homeBreakdownItem("Giá vốn SC", _todayRepairCost, Colors.orange),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "= Doanh thu - Chi phí - Giá vốn",
                    style: TextStyle(
                      fontSize: AppTextStyles.caption.fontSize,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            // HOẠT ĐỘNG HÔM NAY
            Text(
              loc.todayActivity,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface.withOpacity(0.5),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            // Grid layout 3 cột - tránh bị bể UI khi nhiều items
            Builder(builder: (context) {
              final activityItems = <Widget>[
                if (_enableRepair)
                  _activityCard(
                    icon: Icons.build_circle,
                    label: loc.pendingRepairs,
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
                if (_enableRepair)
                  _activityCard(
                    icon: Icons.hourglass_top,
                    label: loc.pendingStatus,
                    value: pendingApprovalCount.toString(),
                    color: AppColors.repairPendingApproval,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OrderListView(
                          role: widget.role,
                          statusFilter: const [3],
                        ),
                      ),
                    ),
                  ),
                if (_enableExpiry)
                  _activityCard(
                    icon: Icons.timer,
                    label: 'Sắp hết HSD',
                    value: (_expiryStats?.atRiskCount ?? 0).toString(),
                    color: Colors.orange,
                    onTap: () {
                      final expiryTabIndex = _navItems.indexWhere((item) => item.label == 'HSD');
                      if (expiryTabIndex != -1) {
                        setState(() => _currentIndex = expiryTabIndex);
                      }
                    },
                  ),
                if (_enableVariants)
                  _activityCard(
                    icon: Icons.checkroom,
                    label: 'Hết size/màu',
                    value: (_variantWarnings?.outOfStock ?? 0).toString(),
                    color: Colors.blue,
                    onTap: () {
                      final variantTabIndex = _navItems.indexWhere((item) => item.label == 'Size/Màu');
                      if (variantTabIndex != -1) {
                        setState(() => _currentIndex = variantTabIndex);
                      }
                    },
                  ),
                _activityCard(
                  icon: Icons.shopping_cart,
                  label: loc.saleOrders,
                  value: todaySaleCount.toString(),
                  color: AppColors.success,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SaleListView(todayOnly: true)),
                  ),
                ),
                _activityCard(
                  icon: Icons.receipt_long,
                  label: loc.debt,
                  value: MoneyUtils.formatCompact(totalDebtRemain),
                  color: AppColors.warning,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DebtView()),
                  ),
                ),
              ];
              // Use GridView for consistent layout regardless of item count
              final r2 = context.responsive;
              final crossAxisCount = r2.isDesktop
                  ? activityItems.length.clamp(1, 6)
                  : (r2.isTablet
                      ? activityItems.length.clamp(1, 5)
                      : activityItems.length.clamp(1, 3));
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.0,
                children: activityItems,
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Breakdown item widget cho home dashboard (kiểu Sổ quỹ)
  Widget _homeBreakdownItem(String label, int amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.black54),
            ),
          ),
          Text(
            MoneyUtils.formatVND(amount),
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: color,
              fontWeight: FontWeight.w500,
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
              style: AppTextStyles.headline3.copyWith(
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                subLabel,
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
                loc.todayNetProfit,
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
          const SizedBox(height: 6),
          // Breakdown: sales profit + repair profit
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '🛒 ${MoneyUtils.formatVND(_todaySalesProfit)}',
                style: AppTextStyles.overline.copyWith(
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_enableRepair) ...[
                Text(
                  '  •  ',
                  style: AppTextStyles.overline.copyWith(color: Colors.white54),
                ),
                Text(
                  '🔧 ${MoneyUtils.formatVND(_todayRepairProfit)}',
                  style: AppTextStyles.overline.copyWith(
                    color: Colors.white.withOpacity(0.85),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            loc.netProfitFormula,
            style: AppTextStyles.overline.copyWith(color: Colors.white70),
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
              ),
              textAlign: TextAlign.center,
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
          Navigator.push(
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
                    fontSize: 13,
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

  Widget _buildAlerts() {
    // Only show warranty alerts for shops with warranty enabled (electronics)
    if (!_enableWarranty || expiringWarranties == 0) return const SizedBox();
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