import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/employee_salary_model.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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

  // Danh sách nhân viên
  List<Map<String, dynamic>> _staffList = [];

  // Cài đặt lương cho từng nhân viên: staffId -> EmployeeSalarySettings
  Map<String, EmployeeSalarySettings> _employeeSettings = {};

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

  // Nhân viên đang được chọn để xem/sửa
  String? _selectedStaffId;

  final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkPermission();
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
      setState(() => _isAdmin = role == 'admin');
    }
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
        title: const Text('CÀI ĐẶT LƯƠNG & HOA HỒNG'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.tune), text: 'MẶC ĐỊNH'),
            Tab(icon: Icon(Icons.people), text: 'NHÂN VIÊN'),
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
          : TabBarView(
              controller: _tabController,
              children: [_buildShopDefaultsTab(), _buildEmployeeSettingsTab()],
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
            'Cài đặt mặc định áp dụng cho nhân viên mới hoặc chưa được cấu hình riêng.',
            Colors.blue,
            Icons.info_outline,
          ),
          const SizedBox(height: 16),

          // LƯƠNG CƠ BẢN
          _buildSectionCard(
            title: '💰 LƯƠNG CƠ BẢN',
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
            title: '🛒 HOA HỒNG BÁN HÀNG',
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
                '⚠️ Chỉ admin mới có thể thay đổi cài đặt',
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

    return Row(
      children: [
        // Sidebar danh sách nhân viên
        Container(
          width: 200,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            border: Border(right: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                color: AppColors.primary.withOpacity(0.1),
                child: Row(
                  children: [
                    const Icon(
                      Icons.people,
                      size: 20,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'NHÂN VIÊN (${_staffList.length})',
                      style: AppTextStyles.body2.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _staffList.length,
                  itemBuilder: (context, index) {
                    final staff = _staffList[index];
                    final staffId = staff['uid'] ?? staff['id'] ?? '';
                    final staffName =
                        staff['name'] ?? staff['displayName'] ?? 'Chưa có tên';
                    final isSelected = _selectedStaffId == staffId;
                    final hasSettings = _employeeSettings.containsKey(staffId);

                    return ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: AppColors.primary.withOpacity(0.1),
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: isSelected
                            ? AppColors.primary
                            : Colors.grey.shade300,
                        child: Text(
                          staffName.isNotEmpty
                              ? staffName[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black54,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      title: Text(
                        staffName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: hasSettings
                          ? const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: Colors.green,
                            )
                          : const Icon(
                              Icons.circle_outlined,
                              size: 16,
                              color: Colors.grey,
                            ),
                      onTap: () => setState(() => _selectedStaffId = staffId),
                    );
                  },
                ),
              ),
            ],
          ),
        ),

        // Panel chi tiết cài đặt
        Expanded(
          child: _selectedStaffId == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.touch_app,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Chọn nhân viên để xem/sửa cài đặt',
                        style: AppTextStyles.body1.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : _buildEmployeeSettingsPanel(),
        ),
      ],
    );
  }

  Widget _buildEmployeeSettingsPanel() {
    final staff = _staffList.firstWhere(
      (s) => (s['uid'] ?? s['id']) == _selectedStaffId,
      orElse: () => {},
    );
    if (staff.isEmpty) {
      return const Center(child: Text('Không tìm thấy nhân viên'));
    }

    final staffId = _selectedStaffId!;
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

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: StatefulBuilder(
        builder: (context, setLocalState) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primary,
                    child: Text(
                      staffName.isNotEmpty ? staffName[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
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
                        ),
                      ],
                    ),
                  ),
                  if (_employeeSettings.containsKey(staffId))
                    Chip(
                      label: const Text('Đã cấu hình'),
                      backgroundColor: Colors.green.shade100,
                      labelStyle: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Action buttons
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      // Reset về giá trị mặc định
                      setLocalState(() {
                        settings = EmployeeSalarySettings(
                          id: settings.id,
                          staffId: staffId,
                          staffName: staffName,
                          shopId: shopId,
                          baseSalary: (_shopDefaults['baseSalary'] ?? 0)
                              .toDouble(),
                          dailyRate: (_shopDefaults['dailyRate'] ?? 0)
                              .toDouble(),
                          salaryType: _shopDefaults['salaryType'] ?? 'monthly',
                          saleCommType:
                              _shopDefaults['saleCommType'] ?? 'percent',
                          saleCommValue: (_shopDefaults['saleCommValue'] ?? 1.0)
                              .toDouble(),
                          repairCommType:
                              _shopDefaults['repairCommType'] ?? 'percent',
                          repairCommValue:
                              (_shopDefaults['repairCommValue'] ?? 10.0)
                                  .toDouble(),
                          transportAllowance:
                              (_shopDefaults['transportAllowance'] ?? 0)
                                  .toDouble(),
                          mealAllowance: (_shopDefaults['mealAllowance'] ?? 0)
                              .toDouble(),
                          phoneAllowance: (_shopDefaults['phoneAllowance'] ?? 0)
                              .toDouble(),
                          standardHoursPerDay:
                              (_shopDefaults['standardHoursPerDay'] ?? 8.0)
                                  .toDouble(),
                          overtimeRate: (_shopDefaults['overtimeRate'] ?? 150)
                              .toDouble(),
                        );
                      });
                    },
                    icon: const Icon(Icons.restore, size: 18),
                    label: const Text('Dùng mặc định'),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 8),

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
                    onChanged: (v) => setLocalState(() {
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
                    onChanged: (v) => setLocalState(() {
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
                    onChanged: (v) => setLocalState(() {
                      settings = settings.copyWith(saleCommType: v);
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (settings.saleCommType == 'percent')
                    _buildPercentField(
                      label: '% Hoa hồng doanh số',
                      value: settings.saleCommValue,
                      onChanged: (v) => setLocalState(() {
                        settings = settings.copyWith(saleCommValue: v);
                      }),
                    )
                  else
                    _buildCurrencyField(
                      label: 'Tiền/đơn bán (đ)',
                      value: settings.saleCommValue,
                      onChanged: (v) => setLocalState(() {
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
                    onChanged: (v) => setLocalState(() {
                      settings = settings.copyWith(repairCommType: v);
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (settings.repairCommType == 'percent')
                    _buildPercentField(
                      label: '% Hoa hồng lợi nhuận sửa',
                      value: settings.repairCommValue,
                      onChanged: (v) => setLocalState(() {
                        settings = settings.copyWith(repairCommValue: v);
                      }),
                    )
                  else
                    _buildCurrencyField(
                      label: 'Tiền/đơn sửa (đ)',
                      value: settings.repairCommValue,
                      onChanged: (v) => setLocalState(() {
                        settings = settings.copyWith(repairCommValue: v);
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
                    onChanged: (v) => setLocalState(() {
                      settings = settings.copyWith(transportAllowance: v);
                    }),
                  ),
                  const SizedBox(height: 12),
                  _buildCurrencyField(
                    label: 'Phụ cấp ăn trưa/tháng (đ)',
                    value: settings.mealAllowance,
                    onChanged: (v) => setLocalState(() {
                      settings = settings.copyWith(mealAllowance: v);
                    }),
                  ),
                  const SizedBox(height: 12),
                  _buildCurrencyField(
                    label: 'Phụ cấp điện thoại/tháng (đ)',
                    value: settings.phoneAllowance,
                    onChanged: (v) => setLocalState(() {
                      settings = settings.copyWith(phoneAllowance: v);
                    }),
                  ),
                  const SizedBox(height: 12),
                  _buildCurrencyField(
                    label: 'Phụ cấp khác/tháng (đ)',
                    value: settings.otherAllowance,
                    onChanged: (v) => setLocalState(() {
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
                    onChanged: (v) => setLocalState(() {
                      settings = settings.copyWith(monthlyTarget: v);
                    }),
                  ),
                  const SizedBox(height: 12),
                  _buildPercentField(
                    label: '% Thưởng khi đạt mục tiêu',
                    value: settings.targetBonusPercent,
                    onChanged: (v) => setLocalState(() {
                      settings = settings.copyWith(targetBonusPercent: v);
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
                    onChanged: (v) => setLocalState(() {
                      settings = settings.copyWith(standardHoursPerDay: v);
                    }),
                    suffix: 'giờ',
                  ),
                  const SizedBox(height: 12),
                  _buildPercentField(
                    label: 'Hệ số OT (%)',
                    value: settings.overtimeRate,
                    max: 300,
                    onChanged: (v) => setLocalState(() {
                      settings = settings.copyWith(overtimeRate: v);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // PREVIEW
              _buildPreviewCard(settings),
              const SizedBox(height: 24),

              // NÚT LƯU
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isAdmin
                      ? () async {
                          await _saveEmployeeSettings(settings);
                          setState(() {
                            _employeeSettings[staffId] = settings;
                          });
                        }
                      : null,
                  icon: const Icon(Icons.save),
                  label: Text('LƯU CÀI ĐẶT CHO ${staffName.toUpperCase()}'),
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
                    '⚠️ Chỉ admin mới có thể thay đổi cài đặt',
                    style: AppTextStyles.caption.copyWith(color: Colors.orange),
                  ),
                ),
            ],
          );
        },
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
            'Giả định: Doanh số ${_currencyFormat.format(exampleSaleRevenue)}đ, '
            'Lợi nhuận sửa ${_currencyFormat.format(exampleRepairProfit)}đ, '
            '$exampleSaleOrders đơn bán, $exampleRepairOrders đơn sửa',
            style: AppTextStyles.caption.copyWith(color: Colors.grey.shade700),
          ),
          const Divider(height: 16),
          _buildPreviewRow('Lương cơ bản', settings.baseSalary),
          _buildPreviewRow('Hoa hồng bán hàng', saleComm),
          _buildPreviewRow('Hoa hồng sửa chữa', repairComm),
          if (bonus > 0) _buildPreviewRow('Thưởng doanh số', bonus),
          _buildPreviewRow('Tổng phụ cấp', totalAllowance),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'TỔNG DỰ TÍNH',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${_currencyFormat.format(total)} đ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                  fontSize: 16,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.body2),
          Text(
            '${_currencyFormat.format(value)} đ',
            style: AppTextStyles.body2,
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
              style: TextStyle(color: color.withOpacity(0.8), fontSize: 13),
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
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: color,
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
      value: value,
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
    final controller = TextEditingController(
      text: _currencyFormat.format(value),
    );
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixText: 'đ',
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      keyboardType: TextInputType.number,
      enabled: _isAdmin,
      onChanged: (v) {
        final clean = v.replaceAll(RegExp(r'[^0-9]'), '');
        final parsed = double.tryParse(clean) ?? 0;
        onChanged(parsed);
      },
    );
  }

  Widget _buildPercentField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    double max = 100,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.body2)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${value.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(0, max),
          min: 0,
          max: max,
          divisions: (max * 2).toInt(),
          onChanged: _isAdmin ? onChanged : null,
        ),
      ],
    );
  }

  Widget _buildNumberField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
    String? suffix,
  }) {
    final controller = TextEditingController(text: value.toStringAsFixed(1));
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixText: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      enabled: _isAdmin,
      onChanged: (v) {
        final parsed = double.tryParse(v) ?? 0;
        onChanged(parsed);
      },
    );
  }
}
