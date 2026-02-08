import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/employee_salary_model.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../l10n/app_localizations.dart';

/// Trang quản lý cài đặt lương và hoa hồng nhân viên
/// Tích hợp: lương cơ bản, hoa hồng bán hàng, hoa hồng sửa chữa, phụ cấp, thưởng doanh số
class HRSalarySettingsView extends StatefulWidget {
  const HRSalarySettingsView({super.key});

  @override
  State<HRSalarySettingsView> createState() => _HRSalarySettingsViewState();
}

class _HRSalarySettingsViewState extends State<HRSalarySettingsView>
    with SingleTickerProviderStateMixin {
  final db = DBHelper();
  late TabController _tabController;

  bool _loading = true;
  bool _isAdmin = false;
  bool _loadingShops = false;
  List<Map<String, dynamic>> _allShops = [];
  String? _selectedShopId;

  // Danh sách nhân viên
  List<Map<String, dynamic>> _staffList = [];

  // Cài đặt lương cho từng nhân viên: staffId -> EmployeeSalarySettings
  final Map<String, EmployeeSalarySettings> _employeeSettings = {};

  // Cài đặt mặc định của shop
  Map<String, dynamic> _shopDefaults = {
    'baseSalary': 0.0,
    'dailyRate': 0.0,
    'salaryType': 'monthly',
    'saleCommType': 'percent',
    'saleCommValue': 1.0,
    'repairCommType': 'percent',
    'repairCommValue': 10.0,
    'transportAllowance': 0.0,
    'mealAllowance': 0.0,
    'phoneAllowance': 0.0,
    'standardHoursPerDay': 8.0,
    'overtimeRate': 150.0,
  };

  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkPermission();
    _initAdminShopSelector();
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final role = await UserService.getUserRole(uid);
    if (mounted) {
      // Cho phép admin hoặc owner (chủ shop) có quyền cài đặt
      setState(() => _isAdmin = role == 'admin' || role == 'owner');
    }
  }

  void _initAdminShopSelector() {
    if (!UserService.isCurrentUserSuperAdmin()) return;
    _selectedShopId = UserService.getAdminSelectedShop();
    _loadShopsForAdmin();
  }

  Future<void> _loadShopsForAdmin() async {
    if (!UserService.isCurrentUserSuperAdmin()) return;
    setState(() => _loadingShops = true);
    try {
      final shops = await UserService.getAllShops();
      if (!mounted) return;
      setState(() {
        _allShops = shops;
        if (_selectedShopId != null &&
            !_allShops.any((s) => s['id'] == _selectedShopId)) {
          _selectedShopId = null;
        }
        _loadingShops = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading shops for admin: $e');
      if (mounted) setState(() => _loadingShops = false);
    }
  }

  Future<void> _onAdminShopSelected(String? shopId) async {
    if (shopId == null || !UserService.isCurrentUserSuperAdmin()) return;
    setState(() => _selectedShopId = shopId);
    UserService.setAdminSelectedShop(shopId);
    await _loadData();

    if (!mounted) return;
    final loc = AppLocalizations.of(context);
    final shopName = _allShops.firstWhere(
      (s) => s['id'] == shopId,
      orElse: () => {'name': shopId},
    )['name'];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(loc?.switchedToShop('$shopName') ?? 'Đã chuyển shop'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      // 1. Load danh sách nhân viên
      await _loadStaffList();

      // 2. Load cài đặt mặc định của shop
      await _loadShopDefaults();

      // 3. Load cài đặt lương cho từng nhân viên
      await _loadEmployeeSettings();
    } catch (e) {
      debugPrint('❌ Error loading HR settings: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadStaffList() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;

      // Lấy từ Firestore
      final snapshot = await FirestoreService.getStaffByShopId(shopId);
      if (snapshot != null) {
        _staffList = snapshot;
      }
    } catch (e) {
      debugPrint('❌ Error loading staff list: $e');
    }
  }

  Future<void> _loadShopDefaults() async {
    try {
      // Try Firestore first
      final cloudDefaults =
          await FirestoreService.getShopDefaultSalarySettings();
      if (cloudDefaults != null) {
        _shopDefaults = {..._shopDefaults, ...cloudDefaults};
        return;
      }

      // Fallback to local payroll_settings
      final localSettings = await db.getPayrollSettings();
      _shopDefaults = {
        'baseSalary': (localSettings['baseSalary'] ?? 0).toDouble(),
        'dailyRate':
            (localSettings['baseSalary'] ?? 0).toDouble() /
            26, // Ước tính 26 ngày/tháng
        'salaryType': 'monthly',
        'saleCommType': localSettings['saleCommType'] ?? 'percent',
        'saleCommValue': (localSettings['saleCommPercent'] ?? 1.0).toDouble(),
        'repairCommType': localSettings['repairCommType'] ?? 'percent',
        'repairCommValue': (localSettings['repairProfitPercent'] ?? 10.0)
            .toDouble(),
        'transportAllowance': (localSettings['transportAllowance'] ?? 0)
            .toDouble(),
        'mealAllowance': (localSettings['mealAllowance'] ?? 0).toDouble(),
        'phoneAllowance': (localSettings['phoneAllowance'] ?? 0).toDouble(),
        'standardHoursPerDay': 8.0,
        'overtimeRate': 150.0,
      };
    } catch (e) {
      debugPrint('❌ Error loading shop defaults: $e');
    }
  }

  Future<void> _loadEmployeeSettings() async {
    try {
      // Load from local DB first
      final localSettings = await db.getEmployeeSalarySettings();
      for (final setting in localSettings) {
        final staffId = setting['staffId'] as String?;
        if (staffId != null) {
          _employeeSettings[staffId] = EmployeeSalarySettings.fromMap(setting);
        }
      }

      // Sync from Firestore
      final cloudSettings = await FirestoreService.getEmployeeSalarySettings();
      for (final setting in cloudSettings) {
        final staffId = setting['staffId'] as String?;
        if (staffId != null) {
          _employeeSettings[staffId] = EmployeeSalarySettings.fromMap(setting);
          // Sync to local
          await db.upsertEmployeeSalarySettings(setting);
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading employee settings: $e');
    }
  }

  Future<void> _saveShopDefaults() async {
    try {
      // Save to Firestore
      await FirestoreService.saveShopDefaultSalarySettings(_shopDefaults);

      // Also save to local payroll_settings for backward compatibility
      await db.savePayrollSettings({
        'baseSalary': (_shopDefaults['baseSalary'] ?? 0).toInt(),
        'saleCommPercent': _shopDefaults['saleCommValue'] ?? 1.0,
        'saleCommType': _shopDefaults['saleCommType'] ?? 'percent',
        'saleCommTier1Max': (_shopDefaults['saleCommTier1Max'] ?? 10000000).toInt(),
        'saleCommTier1Value': (_shopDefaults['saleCommTier1Value'] ?? 20000).toInt(),
        'saleCommTier2Max': (_shopDefaults['saleCommTier2Max'] ?? 50000000).toInt(),
        'saleCommTier2Value': (_shopDefaults['saleCommTier2Value'] ?? 50000).toInt(),
        'saleCommTier3Value': (_shopDefaults['saleCommTier3Value'] ?? 100000).toInt(),
        'repairProfitPercent': _shopDefaults['repairCommValue'] ?? 10.0,
        'repairCommType': _shopDefaults['repairCommType'] ?? 'percent',
        'transportAllowance': (_shopDefaults['transportAllowance'] ?? 0)
            .toInt(),
        'mealAllowance': (_shopDefaults['mealAllowance'] ?? 0).toInt(),
        'phoneAllowance': (_shopDefaults['phoneAllowance'] ?? 0).toInt(),
        'targetBonus': 0,
        'monthlyTarget': (_shopDefaults['monthlyTarget'] ?? 0).toInt(),
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã lưu cài đặt mặc định'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error saving shop defaults: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _saveEmployeeSettings(EmployeeSalarySettings settings) async {
    try {
      // Save to local DB
      await db.saveEmployeeSalarySettings(settings.toMap());

      // Save to Firestore
      final docId = await FirestoreService.saveEmployeeSalarySettings(
        settings.toFirestoreMap(),
      );

      if (docId != null) {
        // Mark as synced
        await db.markEmployeeSalarySettingsSynced(docId);

        // Update local state
        _employeeSettings[settings.staffId] = settings;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã lưu cài đặt cho ${settings.staffName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error saving employee settings: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Quay lại',
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocalizations.of(context)?.salarySettings ?? 'SALARY SETTINGS',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(
              icon: const Icon(Icons.tune, size: 18),
              text: AppLocalizations.of(context)?.defaultSettings ?? 'DEFAULT',
            ),
            Tab(
              icon: const Icon(Icons.people, size: 18),
              text: AppLocalizations.of(context)?.staff ?? 'STAFF',
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (UserService.isCurrentUserSuperAdmin())
                  _buildAdminShopSelectorCard(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildShopDefaultsTab(),
                      _buildEmployeeSettingsTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAdminShopSelectorCard() {
    final loc = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.store, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc?.selectShopToViewData ?? 'Chọn shop để xem dữ liệu',
                  style: TextStyle(
                    color: Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextStyles.headline4.fontSize,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                onPressed: _loadingShops ? null : _loadShopsForAdmin,
                tooltip: 'Tải lại danh sách shop',
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            loc?.viewShopAsAdmin ??
                'Super Admin có thể chọn shop để xem dữ liệu',
            style: TextStyle(
              fontSize: AppTextStyles.subtitle1.fontSize,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 10),
          if (_loadingShops)
            const Center(child: CircularProgressIndicator())
          else if (_allShops.isEmpty)
            Text(
              loc?.noShops ?? 'Không có shop nào',
              style: const TextStyle(color: Colors.grey),
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _selectedShopId,
              decoration: InputDecoration(
                labelText: loc?.selectShopLabel ?? 'Chọn shop',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              hint: Text(loc?.selectShopPlaceholder ?? '-- Chọn shop --'),
              items: _allShops.map((shop) {
                final shopName = shop['name'] ?? 'Shop ${shop['id']}';
                final ownerEmail = shop['ownerEmail'] ?? '';
                return DropdownMenuItem<String>(
                  value: shop['id'],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        shopName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (ownerEmail.toString().isNotEmpty)
                        Text(
                          ownerEmail,
                          style: TextStyle(
                            fontSize: AppTextStyles.body1.fontSize,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _onAdminShopSelected,
            ),
        ],
      ),
    );
  }

  /// Tab 1: Cài đặt mặc định của shop
  Widget _buildShopDefaultsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            'Default settings apply to new staff or those without custom config. / Cài đặt mặc định áp dụng cho nhân viên mới hoặc chưa được cấu hình riêng.',
            Colors.blue,
            Icons.info_outline,
          ),
          const SizedBox(height: 16),

          // LƯƠNG CƠ BẢN
          _buildSectionCard(
            title: '💰 BASE SALARY / LƯƠNG CƠ BẢN',
            color: Colors.green,
            children: [
              _buildDropdownField(
                label: 'Loại lương',
                value: _shopDefaults['salaryType'] ?? 'monthly',
                items: const [
                  DropdownMenuItem(value: 'monthly', child: Text('Theo tháng')),
                  DropdownMenuItem(value: 'daily', child: Text('Theo ngày')),
                  DropdownMenuItem(value: 'hourly', child: Text('Theo giờ')),
                ],
                onChanged: (v) =>
                    setState(() => _shopDefaults['salaryType'] = v),
              ),
              const SizedBox(height: 12),
              _buildCurrencyField(
                label: _shopDefaults['salaryType'] == 'daily'
                    ? 'Lương/ngày (đ)'
                    : _shopDefaults['salaryType'] == 'hourly'
                    ? 'Lương/giờ (đ)'
                    : 'Lương cơ bản/tháng (đ)',
                value: _shopDefaults['baseSalary'] ?? 0,
                onChanged: (v) =>
                    setState(() => _shopDefaults['baseSalary'] = v),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // HOA HỒNG BÁN HÀNG
          _buildSectionCard(
            title: '🛒 SALES COMMISSION / HOA HỒNG BÁN HÀNG',
            color: Colors.orange,
            children: [
              _buildDropdownField(
                label: 'Loại tính',
                value: _shopDefaults['saleCommType'] ?? 'percent',
                items: const [
                  DropdownMenuItem(value: 'percent', child: Text('% Doanh số')),
                  DropdownMenuItem(
                    value: 'fixed_per_order',
                    child: Text('Tiền cố định/đơn'),
                  ),
                  DropdownMenuItem(
                    value: 'tiered',
                    child: Text('Theo bậc giá trị đơn'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _shopDefaults['saleCommType'] = v),
              ),
              const SizedBox(height: 12),
              if (_shopDefaults['saleCommType'] == 'percent')
                _buildPercentField(
                  label: '% Hoa hồng doanh số',
                  value: _shopDefaults['saleCommValue'] ?? 1.0,
                  onChanged: (v) =>
                      setState(() => _shopDefaults['saleCommValue'] = v),
                )
              else if (_shopDefaults['saleCommType'] == 'tiered')
                ..._buildTieredCommissionFields()
              else
                _buildCurrencyField(
                  label: 'Tiền/đơn bán (đ)',
                  value: _shopDefaults['saleCommValue'] ?? 0,
                  onChanged: (v) =>
                      setState(() => _shopDefaults['saleCommValue'] = v),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // HOA HỒNG SỬA CHỮA
          _buildSectionCard(
            title: '🔧 HOA HỒNG SỬA CHỮA',
            color: Colors.purple,
            children: [
              _buildDropdownField(
                label: 'Loại tính',
                value: _shopDefaults['repairCommType'] ?? 'percent',
                items: const [
                  DropdownMenuItem(
                    value: 'percent',
                    child: Text('% Lợi nhuận'),
                  ),
                  DropdownMenuItem(
                    value: 'fixed_per_order',
                    child: Text('Tiền cố định/đơn'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => _shopDefaults['repairCommType'] = v),
              ),
              const SizedBox(height: 12),
              if (_shopDefaults['repairCommType'] == 'percent')
                _buildPercentField(
                  label: '% Hoa hồng lợi nhuận sửa',
                  value: _shopDefaults['repairCommValue'] ?? 10.0,
                  onChanged: (v) =>
                      setState(() => _shopDefaults['repairCommValue'] = v),
                )
              else
                _buildCurrencyField(
                  label: 'Tiền/đơn sửa (đ)',
                  value: _shopDefaults['repairCommValue'] ?? 0,
                  onChanged: (v) =>
                      setState(() => _shopDefaults['repairCommValue'] = v),
                ),
            ],
          ),
          const SizedBox(height: 16),

          // PHỤ CẤP
          _buildSectionCard(
            title: '🎁 PHỤ CẤP',
            color: Colors.teal,
            children: [
              _buildCurrencyField(
                label: 'Phụ cấp xăng xe/tháng (đ)',
                value: _shopDefaults['transportAllowance'] ?? 0,
                onChanged: (v) =>
                    setState(() => _shopDefaults['transportAllowance'] = v),
              ),
              const SizedBox(height: 12),
              _buildCurrencyField(
                label: 'Phụ cấp ăn trưa/tháng (đ)',
                value: _shopDefaults['mealAllowance'] ?? 0,
                onChanged: (v) =>
                    setState(() => _shopDefaults['mealAllowance'] = v),
              ),
              const SizedBox(height: 12),
              _buildCurrencyField(
                label: 'Phụ cấp điện thoại/tháng (đ)',
                value: _shopDefaults['phoneAllowance'] ?? 0,
                onChanged: (v) =>
                    setState(() => _shopDefaults['phoneAllowance'] = v),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // GIỜ LÀM & OT
          _buildSectionCard(
            title: '⏰ GIỜ LÀM & OT',
            color: Colors.indigo,
            children: [
              _buildNumberField(
                label: 'Giờ chuẩn/ngày',
                value: _shopDefaults['standardHoursPerDay'] ?? 8.0,
                onChanged: (v) =>
                    setState(() => _shopDefaults['standardHoursPerDay'] = v),
                suffix: 'giờ',
              ),
              const SizedBox(height: 12),
              _buildPercentField(
                label: 'Hệ số OT (%)',
                value: _shopDefaults['overtimeRate'] ?? 150,
                max: 300,
                onChanged: (v) =>
                    setState(() => _shopDefaults['overtimeRate'] = v),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // NÚT LƯU
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _isAdmin ? _saveShopDefaults : null,
              icon: const Icon(Icons.save),
              label: const Text('LƯU CÀI ĐẶT MẶC ĐỊNH'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
          if (!_isAdmin)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '⚠️ Chỉ chủ shop hoặc admin mới có thể thay đổi',
                style: AppTextStyles.caption.copyWith(color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }

  /// Tab 2: Cài đặt cho từng nhân viên
  Widget _buildEmployeeSettingsTab() {
    if (_staffList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Chưa có nhân viên nào',
              style: AppTextStyles.body1.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Tải lại'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _staffList.length,
      itemBuilder: (context, index) {
        final staff = _staffList[index];
        final staffId = staff['uid'] ?? staff['id'] ?? '';
        final staffName =
            staff['name'] ?? staff['displayName'] ?? 'Chưa có tên';
        final hasSettings = _employeeSettings.containsKey(staffId);

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: hasSettings
                  ? Colors.green
                  : Colors.grey.shade300,
              child: Text(
                staffName.isNotEmpty ? staffName[0].toUpperCase() : '?',
                style: TextStyle(
                  color: hasSettings ? Colors.white : Colors.black54,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              staffName,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              staff['email'] ?? staffId,
              style: AppTextStyles.caption.copyWith(color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasSettings)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20)
                else
                  const Icon(
                    Icons.settings_outlined,
                    color: Colors.grey,
                    size: 20,
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
            onTap: () => _showEmployeeSettingsDialog(staff),
          ),
        );
      },
    );
  }

  void _showEmployeeSettingsDialog(Map<String, dynamic> staff) {
    final staffId = staff['uid'] ?? staff['id'] ?? '';
    final staffName = staff['name'] ?? staff['displayName'] ?? 'Chưa có tên';
    final shopId = staff['shopId'] ?? '';

    // Lấy settings hiện tại hoặc tạo mới từ defaults
    EmployeeSalarySettings settings =
        _employeeSettings[staffId] ??
        EmployeeSalarySettings(
          id: '',
          staffId: staffId,
          staffName: staffName,
          shopId: shopId,
          baseSalary: (_shopDefaults['baseSalary'] ?? 0).toDouble(),
          dailyRate: (_shopDefaults['dailyRate'] ?? 0).toDouble(),
          salaryType: _shopDefaults['salaryType'] ?? 'monthly',
          saleCommType: _shopDefaults['saleCommType'] ?? 'percent',
          saleCommValue: (_shopDefaults['saleCommValue'] ?? 1.0).toDouble(),
          repairCommType: _shopDefaults['repairCommType'] ?? 'percent',
          repairCommValue: (_shopDefaults['repairCommValue'] ?? 10.0)
              .toDouble(),
          transportAllowance: (_shopDefaults['transportAllowance'] ?? 0)
              .toDouble(),
          mealAllowance: (_shopDefaults['mealAllowance'] ?? 0).toDouble(),
          phoneAllowance: (_shopDefaults['phoneAllowance'] ?? 0).toDouble(),
          standardHoursPerDay: (_shopDefaults['standardHoursPerDay'] ?? 8.0)
              .toDouble(),
          overtimeRate: (_shopDefaults['overtimeRate'] ?? 150).toDouble(),
        );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Header
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: AppColors.primary,
                        child: Text(
                          staffName.isNotEmpty
                              ? staffName[0].toUpperCase()
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(staffName, style: AppTextStyles.headline3),
                            Text(
                              staff['email'] ?? staffId,
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setDialogState(() {
                            settings = EmployeeSalarySettings(
                              id: settings.id,
                              staffId: staffId,
                              staffName: staffName,
                              shopId: shopId,
                              baseSalary: (_shopDefaults['baseSalary'] ?? 0)
                                  .toDouble(),
                              dailyRate: (_shopDefaults['dailyRate'] ?? 0)
                                  .toDouble(),
                              salaryType:
                                  _shopDefaults['salaryType'] ?? 'monthly',
                              saleCommType:
                                  _shopDefaults['saleCommType'] ?? 'percent',
                              saleCommValue:
                                  (_shopDefaults['saleCommValue'] ?? 1.0)
                                      .toDouble(),
                              repairCommType:
                                  _shopDefaults['repairCommType'] ?? 'percent',
                              repairCommValue:
                                  (_shopDefaults['repairCommValue'] ?? 10.0)
                                      .toDouble(),
                              transportAllowance:
                                  (_shopDefaults['transportAllowance'] ?? 0)
                                      .toDouble(),
                              mealAllowance:
                                  (_shopDefaults['mealAllowance'] ?? 0)
                                      .toDouble(),
                              phoneAllowance:
                                  (_shopDefaults['phoneAllowance'] ?? 0)
                                      .toDouble(),
                              standardHoursPerDay:
                                  (_shopDefaults['standardHoursPerDay'] ?? 8.0)
                                      .toDouble(),
                              overtimeRate:
                                  (_shopDefaults['overtimeRate'] ?? 150)
                                      .toDouble(),
                            );
                          });
                        },
                        icon: const Icon(Icons.restore, size: 18),
                        label: const Text('Mặc định'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Content
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // LƯƠNG CƠ BẢN
                      _buildSectionCard(
                        title: '💰 LƯƠNG CƠ BẢN',
                        color: Colors.green,
                        children: [
                          _buildDropdownField(
                            label: 'Loại lương',
                            value: settings.salaryType,
                            items: const [
                              DropdownMenuItem(
                                value: 'monthly',
                                child: Text('Theo tháng'),
                              ),
                              DropdownMenuItem(
                                value: 'daily',
                                child: Text('Theo ngày'),
                              ),
                              DropdownMenuItem(
                                value: 'hourly',
                                child: Text('Theo giờ'),
                              ),
                            ],
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(salaryType: v);
                            }),
                          ),
                          const SizedBox(height: 12),
                          _buildCurrencyField(
                            label: settings.salaryType == 'daily'
                                ? 'Lương/ngày (đ)'
                                : settings.salaryType == 'hourly'
                                ? 'Lương/giờ (đ)'
                                : 'Lương cơ bản/tháng (đ)',
                            value: settings.baseSalary,
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(baseSalary: v);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // HOA HỒNG BÁN HÀNG
                      _buildSectionCard(
                        title: '🛒 HOA HỒNG BÁN HÀNG',
                        color: Colors.orange,
                        children: [
                          _buildDropdownField(
                            label: 'Loại tính',
                            value: settings.saleCommType,
                            items: const [
                              DropdownMenuItem(
                                value: 'percent',
                                child: Text('% Doanh số'),
                              ),
                              DropdownMenuItem(
                                value: 'fixed_per_order',
                                child: Text('Tiền cố định/đơn'),
                              ),
                            ],
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(saleCommType: v);
                            }),
                          ),
                          const SizedBox(height: 12),
                          if (settings.saleCommType == 'percent')
                            _buildPercentField(
                              label: '% Hoa hồng doanh số',
                              value: settings.saleCommValue,
                              onChanged: (v) => setDialogState(() {
                                settings = settings.copyWith(saleCommValue: v);
                              }),
                            )
                          else
                            _buildCurrencyField(
                              label: 'Tiền/đơn bán (đ)',
                              value: settings.saleCommValue,
                              onChanged: (v) => setDialogState(() {
                                settings = settings.copyWith(saleCommValue: v);
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // HOA HỒNG SỬA CHỮA
                      _buildSectionCard(
                        title: '🔧 HOA HỒNG SỬA CHỮA',
                        color: Colors.purple,
                        children: [
                          _buildDropdownField(
                            label: 'Loại tính',
                            value: settings.repairCommType,
                            items: const [
                              DropdownMenuItem(
                                value: 'percent',
                                child: Text('% Lợi nhuận'),
                              ),
                              DropdownMenuItem(
                                value: 'fixed_per_order',
                                child: Text('Tiền cố định/đơn'),
                              ),
                            ],
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(repairCommType: v);
                            }),
                          ),
                          const SizedBox(height: 12),
                          if (settings.repairCommType == 'percent')
                            _buildPercentField(
                              label: '% Hoa hồng lợi nhuận',
                              value: settings.repairCommValue,
                              onChanged: (v) => setDialogState(() {
                                settings = settings.copyWith(
                                  repairCommValue: v,
                                );
                              }),
                            )
                          else
                            _buildCurrencyField(
                              label: 'Tiền/đơn sửa (đ)',
                              value: settings.repairCommValue,
                              onChanged: (v) => setDialogState(() {
                                settings = settings.copyWith(
                                  repairCommValue: v,
                                );
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // PHỤ CẤP
                      _buildSectionCard(
                        title: '🎁 PHỤ CẤP',
                        color: Colors.teal,
                        children: [
                          _buildCurrencyField(
                            label: 'Phụ cấp xăng xe/tháng (đ)',
                            value: settings.transportAllowance,
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(
                                transportAllowance: v,
                              );
                            }),
                          ),
                          const SizedBox(height: 12),
                          _buildCurrencyField(
                            label: 'Phụ cấp ăn trưa/tháng (đ)',
                            value: settings.mealAllowance,
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(mealAllowance: v);
                            }),
                          ),
                          const SizedBox(height: 12),
                          _buildCurrencyField(
                            label: 'Phụ cấp điện thoại/tháng (đ)',
                            value: settings.phoneAllowance,
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(phoneAllowance: v);
                            }),
                          ),
                          const SizedBox(height: 12),
                          _buildCurrencyField(
                            label: 'Phụ cấp khác/tháng (đ)',
                            value: settings.otherAllowance,
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(otherAllowance: v);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // THƯỞNG DOANH SỐ
                      _buildSectionCard(
                        title: '🎯 THƯỞNG DOANH SỐ',
                        color: Colors.amber.shade700,
                        children: [
                          _buildCurrencyField(
                            label: 'Mục tiêu doanh số/tháng (đ)',
                            value: settings.monthlyTarget,
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(monthlyTarget: v);
                            }),
                          ),
                          const SizedBox(height: 12),
                          _buildPercentField(
                            label: '% Thưởng khi đạt mục tiêu',
                            value: settings.targetBonusPercent,
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(
                                targetBonusPercent: v,
                              );
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // GIỜ LÀM & OT
                      _buildSectionCard(
                        title: '⏰ GIỜ LÀM & OT',
                        color: Colors.indigo,
                        children: [
                          _buildNumberField(
                            label: 'Giờ chuẩn/ngày',
                            value: settings.standardHoursPerDay,
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(
                                standardHoursPerDay: v,
                              );
                            }),
                            suffix: 'giờ',
                          ),
                          const SizedBox(height: 12),
                          _buildPercentField(
                            label: 'Hệ số OT (%)',
                            value: settings.overtimeRate,
                            max: 300,
                            onChanged: (v) => setDialogState(() {
                              settings = settings.copyWith(overtimeRate: v);
                            }),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // PREVIEW
                      _buildPreviewCard(settings),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                // Bottom buttons
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.2),
                        spreadRadius: 1,
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('HỦY'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _isAdmin
                                ? () async {
                                    await _saveEmployeeSettings(settings);
                                    setState(() {
                                      _employeeSettings[staffId] = settings;
                                    });
                                    if (mounted) Navigator.pop(context);
                                  }
                                : null,
                            icon: const Icon(Icons.save),
                            label: const Text('LƯU'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewCard(EmployeeSalarySettings settings) {
    // Tính toán ví dụ
    const exampleSaleRevenue = 50000000.0; // 50M
    const exampleRepairProfit = 10000000.0; // 10M lợi nhuận
    const exampleSaleOrders = 20;
    const exampleRepairOrders = 15;

    double saleComm = settings.saleCommType == 'percent'
        ? exampleSaleRevenue * (settings.saleCommValue / 100)
        : settings.saleCommValue * exampleSaleOrders;

    double repairComm = settings.repairCommType == 'percent'
        ? exampleRepairProfit * (settings.repairCommValue / 100)
        : settings.repairCommValue * exampleRepairOrders;

    double bonus =
        settings.monthlyTarget > 0 &&
            exampleSaleRevenue >= settings.monthlyTarget
        ? exampleSaleRevenue * (settings.targetBonusPercent / 100)
        : 0;

    double totalAllowance = settings.totalAllowance;
    double total =
        settings.baseSalary + saleComm + repairComm + bonus + totalAllowance;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calculate, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                'DỰ TÍNH LƯƠNG (ví dụ)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Giả định: DS ${_currencyFormat.format(exampleSaleRevenue)}đ, '
            'LN sửa ${_currencyFormat.format(exampleRepairProfit)}đ, '
            '$exampleSaleOrders đơn bán, $exampleRepairOrders đơn sửa',
            style: AppTextStyles.caption.copyWith(color: Colors.grey.shade700),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          const Divider(height: 16),
          _buildPreviewRow('Lương cơ bản', settings.baseSalary),
          _buildPreviewRow('Hoa hồng bán hàng', saleComm),
          _buildPreviewRow('Hoa hồng sửa chữa', repairComm),
          if (bonus > 0) _buildPreviewRow('Thưởng doanh số', bonus),
          _buildPreviewRow('Tổng phụ cấp', totalAllowance),
          const Divider(height: 16),
          Row(
            children: [
              const Expanded(
                flex: 3,
                child: Text(
                  'TỔNG DỰ TÍNH',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: Text(
                  '${_currencyFormat.format(total)}đ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                    fontSize: AppTextStyles.headline3.fontSize,
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: AppTextStyles.body2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              '${_currencyFormat.format(value)}đ',
              style: AppTextStyles.body2,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color.withOpacity(0.8),
                fontSize: AppTextStyles.headline5.fontSize,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Color color,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 4,
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
                width: 4,
                height: 20,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextStyles.headline4.fontSize,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDropdownField<T>({
    required String label,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: items,
      onChanged: _isAdmin ? onChanged : null,
    );
  }

  Widget _buildCurrencyField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return _CurrencyFieldWidget(
      label: label,
      value: value,
      onChanged: onChanged,
      enabled: _isAdmin,
      currencyFormat: _currencyFormat,
    );
  }

  Widget _buildPercentField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double max = 100,
  }) {
    return _PercentFieldWidget(
      label: label,
      value: value,
      onChanged: onChanged,
      max: max,
      enabled: _isAdmin,
    );
  }

  Widget _buildNumberField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    String? suffix,
  }) {
    return _NumberFieldWidget(
      label: label,
      value: value,
      onChanged: onChanged,
      suffix: suffix,
      enabled: _isAdmin,
    );
  }

  /// Builds the tiered commission configuration fields
  List<Widget> _buildTieredCommissionFields() {
    return [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 Hoa hồng theo bậc giá trị đơn hàng:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '• Bậc 1: Đơn dưới mức 1 → Hoa hồng 1\n'
              '• Bậc 2: Đơn từ mức 1 đến mức 2 → Hoa hồng 2\n'
              '• Bậc 3: Đơn trên mức 2 → Hoa hồng 3',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      // Tier 1: Under X -> Y
      Row(
        children: [
          Expanded(
            child: _buildCurrencyField(
              label: 'Mức 1: Đơn dưới (đ)',
              value: (_shopDefaults['saleCommTier1Max'] ?? 10000000).toDouble(),
              onChanged: (v) => setState(() => _shopDefaults['saleCommTier1Max'] = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCurrencyField(
              label: 'Hoa hồng 1 (đ)',
              value: (_shopDefaults['saleCommTier1Value'] ?? 20000).toDouble(),
              onChanged: (v) => setState(() => _shopDefaults['saleCommTier1Value'] = v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // Tier 2: From X to Y -> Z
      Row(
        children: [
          Expanded(
            child: _buildCurrencyField(
              label: 'Mức 2: Đơn đến (đ)',
              value: (_shopDefaults['saleCommTier2Max'] ?? 50000000).toDouble(),
              onChanged: (v) => setState(() => _shopDefaults['saleCommTier2Max'] = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCurrencyField(
              label: 'Hoa hồng 2 (đ)',
              value: (_shopDefaults['saleCommTier2Value'] ?? 50000).toDouble(),
              onChanged: (v) => setState(() => _shopDefaults['saleCommTier2Value'] = v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      // Tier 3: Over Y -> Z
      Row(
        children: [
          const Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Bậc 3: Đơn trên mức 2',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildCurrencyField(
              label: 'Hoa hồng 3 (đ)',
              value: (_shopDefaults['saleCommTier3Value'] ?? 100000).toDouble(),
              onChanged: (v) => setState(() => _shopDefaults['saleCommTier3Value'] = v),
            ),
          ),
        ],
      ),
    ];
  }
}

// Separate StatefulWidget for Currency Field to maintain focus
class _CurrencyFieldWidget extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final bool enabled;
  final NumberFormat currencyFormat;

  const _CurrencyFieldWidget({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.enabled,
    required this.currencyFormat,
  });

  @override
  State<_CurrencyFieldWidget> createState() => _CurrencyFieldWidgetState();
}

class _CurrencyFieldWidgetState extends State<_CurrencyFieldWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  double _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = TextEditingController(
      text: widget.currencyFormat.format(widget.value),
    );
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_CurrencyFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only update if value changed externally and field is not focused
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _currentValue = widget.value;
      _controller.text = widget.currencyFormat.format(widget.value);
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      // When losing focus, notify parent of the change
      if (_currentValue != widget.value) {
        widget.onChanged(_currentValue);
      }
      // Format the display text
      _controller.text = widget.currencyFormat.format(_currentValue);
    } else {
      // When gaining focus, show raw number for easier editing
      _controller.text = _currentValue > 0
          ? _currentValue.toStringAsFixed(0)
          : '';
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixText: 'đ',
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      keyboardType: TextInputType.number,
      enabled: widget.enabled,
      onChanged: (v) {
        final clean = v.replaceAll(RegExp(r'[^0-9]'), '');
        _currentValue = double.tryParse(clean) ?? 0;
      },
      onFieldSubmitted: (_) {
        widget.onChanged(_currentValue);
      },
    );
  }
}

// Separate StatefulWidget for Percent Field to maintain focus
class _PercentFieldWidget extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double max;
  final bool enabled;

  const _PercentFieldWidget({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.max,
    required this.enabled,
  });

  @override
  State<_PercentFieldWidget> createState() => _PercentFieldWidgetState();
}

class _PercentFieldWidgetState extends State<_PercentFieldWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  double _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = TextEditingController(text: widget.value.toStringAsFixed(1));
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_PercentFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _currentValue = widget.value;
      _controller.text = widget.value.toStringAsFixed(1);
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      final clamped = _currentValue.clamp(0.0, widget.max);
      if (clamped != widget.value) {
        widget.onChanged(clamped);
      }
      _controller.text = clamped.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixText: '%',
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      enabled: widget.enabled,
      onChanged: (v) {
        _currentValue = double.tryParse(v) ?? 0;
      },
      onFieldSubmitted: (_) {
        widget.onChanged(_currentValue.clamp(0.0, widget.max));
      },
    );
  }
}

// Separate StatefulWidget for Number Field to maintain focus
class _NumberFieldWidget extends StatefulWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;
  final bool enabled;

  const _NumberFieldWidget({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    required this.enabled,
  });

  @override
  State<_NumberFieldWidget> createState() => _NumberFieldWidgetState();
}

class _NumberFieldWidgetState extends State<_NumberFieldWidget> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  double _currentValue = 0;

  @override
  void initState() {
    super.initState();
    _currentValue = widget.value;
    _controller = TextEditingController(text: widget.value.toStringAsFixed(1));
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(_NumberFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && !_focusNode.hasFocus) {
      _currentValue = widget.value;
      _controller.text = widget.value.toStringAsFixed(1);
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      if (_currentValue != widget.value) {
        widget.onChanged(_currentValue);
      }
      _controller.text = _currentValue.toStringAsFixed(1);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: _controller,
      focusNode: _focusNode,
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        suffixText: widget.suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      enabled: widget.enabled,
      onChanged: (v) {
        _currentValue = double.tryParse(v) ?? 0;
      },
      onFieldSubmitted: (_) {
        widget.onChanged(_currentValue);
      },
    );
  }
}
