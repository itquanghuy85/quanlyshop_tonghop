import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:io';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/data_migration_service.dart';
import '../services/sync_service.dart';
import '../widgets/validated_text_field.dart';
import '../theme/app_text_styles.dart';
import 'adjustment_history_view.dart';
import 'hr_salary_settings_view.dart';

class ShopSettingsView extends StatefulWidget {
  const ShopSettingsView({super.key});

  @override
  State<ShopSettingsView> createState() => _ShopSettingsViewState();
}

class _ShopSettingsViewState extends State<ShopSettingsView> {
  final _formKey = GlobalKey<FormState>();
  bool _loading = true;
  bool _saving = false;

  // Shop data
  String _shopName = '';
  String _shopAddress = '';
  String _shopPhone = '';
  String _shopEmail = '';
  String _shopDescription = '';
  String _shopLogoUrl = '';
  double? _shopLatitude;
  double? _shopLongitude;
  File? _selectedLogo;

  // Controllers
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadShopData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadShopData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      NotificationService.showSnackBar("Vui lòng đăng nhập", color: Colors.red);
      setState(() => _loading = false);
      return;
    }

    // Strategy: Try multiple sources to get shopId
    // 1. UserService cache/claims
    // 2. Firestore users doc
    // 3. Fallback to uid (owner case)
    String? shopId;

    try {
      shopId = await UserService.getCurrentShopId();
    } catch (e) {
      debugPrint('UserService.getCurrentShopId failed: $e');
    }

    // If no shopId from claims, try reading from users doc directly
    if (shopId == null || shopId.isEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          shopId = userDoc.data()?['shopId'] as String?;
          debugPrint('Got shopId from users doc: $shopId');
        }
      } catch (e) {
        debugPrint('Failed to read users doc: $e');
      }
    }

    // Final fallback: use uid as shopId (owner case)
    if (shopId == null || shopId.isEmpty) {
      shopId = user.uid;
      debugPrint('Using uid as shopId fallback: $shopId');
    }

    // Now try to load shop data with retry
    for (int retry = 0; retry < 3; retry++) {
      try {
        final shopDoc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(shopId)
            .get();
        if (shopDoc.exists) {
          final data = shopDoc.data()!;
          setState(() {
            _shopName = data['name'] ?? '';
            _shopAddress = data['address'] ?? '';
            _shopPhone = data['phone'] ?? '';
            _shopEmail = data['email'] ?? '';
            _shopDescription = data['description'] ?? '';
            _shopLogoUrl = data['logoUrl'] ?? '';
            _shopLatitude = data['latitude']?.toDouble();
            _shopLongitude = data['longitude']?.toDouble();

            _nameController.text = _shopName;
            _addressController.text = _shopAddress;
            _phoneController.text = _shopPhone;
            _emailController.text = _shopEmail;
            _descriptionController.text = _shopDescription;
          });
          await _syncToSharedPreferences(_shopName, _shopAddress, _shopPhone);
          debugPrint('Shop data loaded successfully');
          break;
        } else {
          // Shop doc doesn't exist yet - this is normal for new registration
          debugPrint('Shop doc not found, may be new registration');
          break;
        }
      } catch (e) {
        debugPrint('Retry ${retry + 1}/3 - Load shop failed: $e');
        if (retry < 2) {
          // Wait a bit for claims to sync before retry
          await Future.delayed(const Duration(seconds: 2));
          // Try refreshing token
          try {
            await user.getIdToken(true);
          } catch (_) {}
        } else {
          // Final retry failed - show user-friendly error
          NotificationService.showSnackBar(
            "Đang chờ quyền truy cập. Vui lòng thử lại sau vài giây.",
            color: Colors.orange,
          );
        }
      }
    }

    setState(() => _loading = false);
  }

  /// Đồng bộ thông tin shop vào SharedPreferences để các màn hình in hóa đơn đọc được
  Future<void> _syncToSharedPreferences(
    String name,
    String address,
    String phone,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shop_name', name);
    await prefs.setString('shop_address', address);
    await prefs.setString('shop_phone', phone);
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      setState(() {
        _selectedLogo = File(pickedFile.path);
      });
    }
  }

  Future<void> _saveShopData() async {
    // Manual validation
    if (_nameController.text.trim().isEmpty) {
      NotificationService.showSnackBar(
        "Vui lòng nhập tên cửa hàng",
        color: Colors.red,
      );
      return;
    }

    setState(() => _saving = true);

    try {
      var shopId = await UserService.getCurrentShopId();
      // Fallback: thử dùng uid của user làm shopId (owner case)
      if (shopId == null || shopId.isEmpty) {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          shopId = user.uid;
        }
      }

      if (shopId == null || shopId.isEmpty) {
        NotificationService.showSnackBar(
          "Không tìm thấy thông tin shop",
          color: Colors.red,
        );
        return;
      }

      String logoUrl = _shopLogoUrl;

      // Upload logo if selected
      if (_selectedLogo != null) {
        final urls = await StorageService.uploadMultipleImages([
          _selectedLogo!.path,
        ], 'shop_logos');
        if (urls.isNotEmpty) {
          logoUrl = urls.first;
        }
      }

      // Update shop data
      final shopData = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'description': _descriptionController.text.trim(),
        'logoUrl': logoUrl,
        'latitude': _shopLatitude,
        'longitude': _shopLongitude,
        'updatedAt': DateTime.now(),
        'updatedBy': FirebaseAuth.instance.currentUser?.uid,
      };

      await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .update(shopData);

      // Đồng bộ thông tin shop vào SharedPreferences để các màn hình in hóa đơn đọc được
      await _syncToSharedPreferences(
        _nameController.text.trim(),
        _addressController.text.trim(),
        _phoneController.text.trim(),
      );

      setState(() {
        _shopName = _nameController.text.trim();
        _shopAddress = _addressController.text.trim();
        _shopPhone = _phoneController.text.trim();
        _shopEmail = _emailController.text.trim();
        _shopDescription = _descriptionController.text.trim();
        _shopLogoUrl = logoUrl;
        _selectedLogo = null;
      });

      NotificationService.showSnackBar(
        "✅ Đã cập nhật thông tin shop!",
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar("❌ Lỗi cập nhật: $e", color: Colors.red);
    } finally {
      setState(() => _saving = false);
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
        title: const Text(
          "CÀI ĐẶT SHOP",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _saveShopData,
              icon: const Icon(Icons.save),
              tooltip: 'Lưu thay đổi',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // === LOGO + THÔNG TIN CƠ BẢN ===
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            // Logo Row
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _pickLogo,
                                  child: Container(
                                    width: 70,
                                    height: 70,
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: _selectedLogo != null
                                        ? ClipRRect(
                                            borderRadius: BorderRadius.circular(12),
                                            child: Image.file(_selectedLogo!, fit: BoxFit.cover),
                                          )
                                        : _shopLogoUrl.isNotEmpty
                                            ? ClipRRect(
                                                borderRadius: BorderRadius.circular(12),
                                                child: Image.network(_shopLogoUrl, fit: BoxFit.cover),
                                              )
                                            : const Icon(Icons.add_a_photo, size: 28, color: Colors.grey),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ValidatedTextField(
                                    controller: _nameController,
                                    label: "Tên cửa hàng *",
                                    icon: Icons.store,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ValidatedTextField(
                              controller: _addressController,
                              label: "Địa chỉ",
                              icon: Icons.location_on,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ValidatedTextField(
                                    controller: _phoneController,
                                    label: "SĐT",
                                    icon: Icons.phone,
                                    keyboardType: TextInputType.phone,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ValidatedTextField(
                                    controller: _emailController,
                                    label: "Email",
                                    icon: Icons.email,
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ValidatedTextField(
                              controller: _descriptionController,
                              label: "Mô tả cửa hàng",
                              icon: Icons.description,
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // === VỊ TRÍ CHẤM CÔNG ===
                    _buildCompactLocationSection(),
                    const SizedBox(height: 12),

                    // === QUICK ACTIONS ===
                    _buildQuickActionsSection(),
                    const SizedBox(height: 12),

                    // === ADVANCED SETTINGS (Collapsible) ===
                    _buildAdvancedSettingsSection(),
                    const SizedBox(height: 12),

                    // === THÀNH VIÊN ===
                    _buildSection("THÀNH VIÊN"),
                    const SizedBox(height: 8),
                    _buildMembersList(),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildSection(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: AppTextStyles.body1.fontSize,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF2962FF),
      ),
    );
  }

  /// Compact location section - chỉ 1 row
  Widget _buildCompactLocationSection() {
    final hasLocation = _shopLatitude != null && _shopLongitude != null;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: Icon(
          hasLocation ? Icons.location_on : Icons.location_off,
          color: hasLocation ? Colors.green : Colors.orange,
        ),
        title: Text(
          hasLocation ? 'Vị trí chấm công đã cài' : 'Chưa cài vị trí chấm công',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        subtitle: hasLocation
            ? Text(
                '${_shopLatitude!.toStringAsFixed(4)}, ${_shopLongitude!.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 11),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasLocation)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                onPressed: _clearLocation,
                tooltip: 'Xóa vị trí',
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.all(8),
              ),
            IconButton(
              icon: Icon(
                Icons.my_location,
                size: 20,
                color: hasLocation ? Colors.blue : Colors.green,
              ),
              onPressed: _setCurrentLocation,
              tooltip: hasLocation ? 'Cập nhật vị trí' : 'Cài vị trí',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(8),
            ),
          ],
        ),
      ),
    );
  }

  /// Quick Actions - các shortcut hay dùng
  Widget _buildQuickActionsSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.account_balance_wallet, color: Colors.green.shade700, size: 22),
            title: const Text('Cài đặt lương & hoa hồng', style: TextStyle(fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HRSalarySettingsView()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: Icon(Icons.history, color: Colors.orange.shade700, size: 22),
            title: const Text('Lịch sử điều chỉnh tài chính', style: TextStyle(fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdjustmentHistoryView()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: Icon(Icons.cloud_download, color: Colors.blue.shade700, size: 22),
            title: const Text('Tải dữ liệu shop từ cloud', style: TextStyle(fontSize: 13)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _showDownloadDataDialog,
          ),
        ],
      ),
    );
  }

  /// Advanced Settings - gom các cài đặt ít dùng vào ExpansionTile
  Widget _buildAdvancedSettingsSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(Icons.settings_suggest, color: Colors.grey.shade600, size: 22),
        title: const Text('Cài đặt nâng cao', style: TextStyle(fontSize: 13)),
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.restore, color: Colors.amber.shade700, size: 20),
            title: const Text('Khôi phục dữ liệu cũ', style: TextStyle(fontSize: 12)),
            subtitle: const Text('Migrate từ shop/tài khoản khác', style: TextStyle(fontSize: 10)),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _showDataMigrationDialog,
          ),
        ],
      ),
    );
  }

  // Old methods removed - functionality moved to _buildQuickActionsSection() and _buildAdvancedSettingsSection()

  Future<void> _showDataMigrationDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Đang quét dữ liệu trên cloud..."),
          ],
        ),
      ),
    );

    try {
      final currentShopId = await UserService.getCurrentShopId();
      final orphanData = await DataMigrationService.findOrphanData();

      if (!mounted) return;
      Navigator.pop(context); // Đóng loading

      if (orphanData.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text("KHÔNG CÓ DỮ LIỆU CŨ"),
              ],
            ),
            content: const Text(
              "Không tìm thấy dữ liệu nào từ tài khoản/shop khác trên cloud.\n\n"
              "Nếu bạn chắc chắn có dữ liệu cũ, hãy kiểm tra:\n"
              "• Đăng nhập đúng email\n"
              "• Kết nối internet ổn định",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("ĐÓNG"),
              ),
            ],
          ),
        );
        return;
      }

      // Nhóm dữ liệu theo shopId
      final groupedByShopId = <String, List<OrphanDataInfo>>{};
      for (var item in orphanData) {
        groupedByShopId.putIfAbsent(item.shopId, () => []).add(item);
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cloud_queue, color: Colors.blue),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "TÌM THẤY DỮ LIỆU CŨ",
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Shop hiện tại: ${currentShopId ?? 'N/A'}",
                    style: TextStyle(
                      fontSize: AppTextStyles.body1.fontSize,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Dữ liệu từ các nguồn khác:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextStyles.headline5.fontSize,
                  ),
                ),
                const SizedBox(height: 10),
                ...groupedByShopId.entries.map((entry) {
                  final shopId = entry.key;
                  final items = entry.value;
                  final totalCount = items.fold<int>(
                    0,
                    (sum, item) => sum + item.count,
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              shopId == 'null'
                                  ? Icons.help_outline
                                  : Icons.store,
                              size: 16,
                              color: shopId == 'null'
                                  ? Colors.orange
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                shopId == 'null'
                                    ? "Dữ liệu chưa gán shop"
                                    : "Shop: ${shopId.substring(0, 8)}...",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextStyles.subtitle1.fontSize,
                                ),
                              ),
                            ),
                            Text(
                              "$totalCount bản ghi",
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextStyles.subtitle1.fontSize,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: items
                              .map(
                                (item) => Chip(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                  labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  label: Text(
                                    "${item.collection}: ${item.count}",
                                    style: TextStyle(
                                      fontSize: AppTextStyles.caption.fontSize,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmMigration(shopId, totalCount);
                            },
                            icon: const Icon(Icons.download, size: 16),
                            label: const Text("MIGRATE VỀ SHOP NÀY"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ĐÓNG"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      NotificationService.showSnackBar("❌ Lỗi: $e", color: Colors.red);
    }
  }

  Future<void> _confirmMigration(String fromShopId, int totalCount) async {
    final currentShopId = await UserService.getCurrentShopId();
    if (currentShopId == null) {
      NotificationService.showSnackBar(
        "❌ Không xác định được shop hiện tại",
        color: Colors.red,
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text("XÁC NHẬN MIGRATE", style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Bạn sắp migrate $totalCount bản ghi từ:"),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                fromShopId == 'null'
                    ? "Dữ liệu chưa gán shop"
                    : "Shop: $fromShopId",
                style: TextStyle(
                  fontSize: AppTextStyles.body1.fontSize,
                  color: Colors.red.shade800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text("Sang shop hiện tại:"),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "Shop: $currentShopId",
                style: TextStyle(
                  fontSize: AppTextStyles.body1.fontSize,
                  color: Colors.green.shade800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "⚠️ Hành động này không thể hoàn tác!",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: AppTextStyles.subtitle1.fontSize,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("MIGRATE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Thực hiện migration
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text("Đang migrate dữ liệu..."),
                const SizedBox(height: 8),
                Text(
                  _migrationProgress,
                  style: TextStyle(
                    fontSize: AppTextStyles.body1.fontSize,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
      ),
    );

    try {
      final results = await DataMigrationService.migrateData(
        fromShopId: fromShopId,
        toShopId: currentShopId,
        onProgress: (message) {
          setState(() => _migrationProgress = message);
        },
      );

      if (!mounted) return;
      Navigator.pop(context); // Đóng loading

      final totalMigrated = results.values.fold<int>(
        0,
        (sum, count) => sum + count,
      );

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Text("MIGRATE THÀNH CÔNG"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Đã migrate $totalMigrated bản ghi:"),
              const SizedBox(height: 10),
              ...results.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        "${e.key}: ${e.value}",
                        style: TextStyle(
                          fontSize: AppTextStyles.subtitle1.fontSize,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Vui lòng khởi động lại app để dữ liệu được cập nhật đầy đủ.",
                style: TextStyle(
                  fontSize: AppTextStyles.body1.fontSize,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                // Có thể trigger reload data ở đây
              },
              child: const Text("ĐÓNG"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      NotificationService.showSnackBar("❌ Lỗi migrate: $e", color: Colors.red);
    }
  }

  String _migrationProgress = '';

  Widget _buildMembersList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadShopMembers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text("Lỗi tải danh sách thành viên: ${snapshot.error}");
        }

        final members = snapshot.data ?? [];

        if (members.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text("Chưa có thành viên nào trong shop"),
            ),
          );
        }

        return Column(
          children: members
              .map(
                (member) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getRoleColor(member['role']),
                      child: Text(
                        member['name']?.substring(0, 1).toUpperCase() ?? '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(member['name'] ?? 'Chưa cập nhật'),
                    subtitle: Text(
                      "${member['email'] ?? ''} • ${_getRoleDisplayName(member['role'])}",
                    ),
                    trailing: Icon(
                      _getRoleIcon(member['role']),
                      color: _getRoleColor(member['role']),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadShopMembers() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('shopId', isEqualTo: shopId)
          .get();

      final members = <Map<String, dynamic>>[];
      for (var doc in usersSnapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        members.add(data);
      }

      return members;
    } catch (e) {
      debugPrint("Error loading shop members: $e");
      return [];
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'owner':
        return Colors.purple;
      case 'manager':
        return Colors.blue;
      case 'technician':
        return Colors.orange;
      case 'employee':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String? role) {
    switch (role) {
      case 'owner':
        return Icons.admin_panel_settings;
      case 'manager':
        return Icons.manage_accounts;
      case 'technician':
        return Icons.build;
      case 'employee':
        return Icons.work;
      default:
        return Icons.person;
    }
  }

  String _getRoleDisplayName(String? role) {
    switch (role) {
      case 'owner':
        return 'Chủ shop';
      case 'manager':
        return 'Quản lý';
      case 'technician':
        return 'Kỹ thuật';
      case 'employee':
        return 'Nhân viên';
      default:
        return 'Thành viên';
    }
  }

  // _buildDownloadShopDataSection removed - moved to _buildQuickActionsSection()

  Future<void> _showDownloadDataDialog() async {
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
                  const TextSpan(text: 'Tải dữ liệu của shop '),
                  TextSpan(
                    text: '"$_shopName"',
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
                        fontSize: AppTextStyles.body1.fontSize,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Quá trình có thể mất vài phút tùy lượng dữ liệu.",
              style: TextStyle(
                fontSize: AppTextStyles.body1.fontSize,
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
        builder: (ctx) => PopScope(
          canPop: false,
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
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      try {
        await SyncService.downloadAllFromCloud();
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
          Text(
            text,
            style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
          ),
        ],
      ),
    );
  }

  // _buildLocationSection removed - moved to _buildCompactLocationSection()

  Future<void> _setCurrentLocation() async {
    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          NotificationService.showSnackBar(
            'Cần quyền truy cập vị trí',
            color: Colors.red,
          );
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        NotificationService.showSnackBar(
          'Vui lòng bật quyền vị trí trong cài đặt',
          color: Colors.red,
        );
        return;
      }

      NotificationService.showSnackBar(
        'Đang lấy vị trí...',
        color: Colors.blue,
      );

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _shopLatitude = position.latitude;
        _shopLongitude = position.longitude;
      });

      NotificationService.showSnackBar(
        '✅ Đã cập nhật vị trí! Nhấn Lưu để hoàn tất.',
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar('Lỗi lấy vị trí: $e', color: Colors.red);
    }
  }

  void _clearLocation() {
    setState(() {
      _shopLatitude = null;
      _shopLongitude = null;
    });
    NotificationService.showSnackBar(
      'Đã xóa vị trí. Nhấn Lưu để hoàn tất.',
      color: Colors.orange,
    );
  }
}
