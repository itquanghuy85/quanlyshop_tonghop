import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/user_service.dart';
import '../theme/app_text_styles.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/encryption_service.dart';
import '../data/db_helper.dart';
import '../services/sync_service.dart';
import '../utils/app_info.dart';
import '../services/first_time_guide_service.dart';
import '../widgets/unified_sync_button.dart';
import 'help_center_view.dart';
import 'user_guide_view.dart';
import 'shop_selector_view.dart';
import 'staff_permissions_view.dart';

class SettingsView extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const SettingsView({super.key, this.setLocale});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  // Localization getter
  AppLocalizations get loc => AppLocalizations.of(context)!;
  
  String _role = 'user';
  bool _loading = true;
  late final Future<String> _versionFuture;

  // Super admin shop selection
  List<Map<String, dynamic>> _allShops = [];
  String? _selectedShopId;
  bool _loadingShops = false;
  
  // Current selected locale
  Locale _selectedLocale = const Locale('vi');

  @override
  void initState() {
    super.initState();
    _versionFuture = AppInfo.getVersion();
    _loadRole();
    _loadShopsForAdmin();
    _loadSavedLocale();
  }
  
  /// Load ngôn ngữ đã lưu
  Future<void> _loadSavedLocale() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final languageCode = prefs.getString('app_language') ?? 'vi';
      if (mounted) {
        setState(() {
          _selectedLocale = Locale(languageCode);
        });
      }
    } catch (e) {
      debugPrint('Error loading saved locale: $e');
    }
  }

  /// Load danh sách shops cho super admin
  Future<void> _loadShopsForAdmin() async {
    if (!UserService.isCurrentUserSuperAdmin()) return;
    setState(() => _loadingShops = true);
    try {
      final shops = await UserService.getAllShops();
      if (mounted) {
        setState(() {
          _allShops = shops;
          _selectedShopId = UserService.getAdminSelectedShop();
          _loadingShops = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading shops: $e');
      if (mounted) setState(() => _loadingShops = false);
    }
  }

  /// Super admin chọn shop để xem
  Future<void> _onShopSelected(String? shopId) async {
    if (shopId == null) return;

    // Set shop TRƯỚC khi làm bất cứ gì khác
    UserService.setAdminSelectedShop(shopId);
    setState(() => _selectedShopId = shopId);

    // Hiển thị loading
    NotificationService.showSnackBar(
      loc.loadingShopData,
      color: Colors.blue,
    );

    try {
      // Hủy subscriptions cũ trước
      await SyncService.cancelAllSubscriptions();

      // Xóa local data cũ
      await DBHelper().clearAllData();

      // Download data của shop mới
      await SyncService.downloadAllFromCloud();

      // Khởi động lại real-time sync cho shop mới
      await SyncService.initRealTimeSync(() {
        if (mounted) setState(() {});
      });

      final shopName =
          _allShops.firstWhere(
            (s) => s['id'] == shopId,
            orElse: () => {'name': shopId},
          )['name'] ??
          shopId;

      NotificationService.showSnackBar(
        loc.switchedToShop(shopName),
        color: Colors.green,
      );
    } catch (e) {
      debugPrint('Error switching shop: $e');
      NotificationService.showSnackBar(
        loc.errorSwitchingShop(e.toString()),
        color: Colors.red,
      );
    }
  }

  String _getRoleDisplayName(String role, AppLocalizations localizations) {
    switch (role) {
      case 'owner':
        return localizations.ownerRole;
      case 'manager':
        return localizations.managerRole;
      case 'employee':
        return localizations.employeeRole;
      case 'technician':
        return localizations.technicianRole;
      case 'admin':
        return localizations.adminRole;
      case 'user':
        return localizations.userRole;
      default:
        return role.toUpperCase();
    }
  }

  Future<void> _loadRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final role = await UserService.getUserRole(user.uid);
      if (mounted) {
        setState(() {
          _role = role;
          _loading = false;
        });
      }
    } else {
      // User null - vẫn hiển thị UI
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _openHelpCenter() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HelpCenterView(userRole: _role),
      ),
    );
  }

  void _openUserGuide() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserGuideView(userRole: _role),
      ),
    );
  }

  // HÀM XỬ LÝ XÓA TRẮNG SHOP (BẢO MẬT TUYỆT ĐỐI)
  Future<void> _handleResetShop() async {
    // Chỉ super admin mới được xóa dữ liệu shop
    if (!UserService.isCurrentUserSuperAdmin()) {
      NotificationService.showSnackBar(
        loc.onlySuperAdminCanDelete,
        color: Colors.red,
      );
      return;
    }

    final confirmTextC = TextEditingController();
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          loc.dangerWarning,
          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(loc.deleteAllDataWarning),
            const SizedBox(height: 15),
            Text(
              loc.typeToConfirm,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            TextField(
              controller: confirmTextC,
              decoration: InputDecoration(hintText: loc.deleteAllPlaceholder),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancel.toUpperCase()),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, confirmTextC.text.trim() == "XOA HET"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              loc.confirmDeleteAll,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _loading = true);
      final errorMessage = await FirestoreService.resetEntireShopData();
      await DBHelper().clearAllData();

      if (errorMessage == null) {
        NotificationService.showSnackBar(
          loc.shopDataDeleted,
          color: Colors.green,
        );
      } else {
        NotificationService.showSnackBar(
          loc.errorDeletingCloudData(errorMessage),
          color: Colors.red,
        );
      }
      await SyncService.cancelAllSubscriptions();
      EncryptionService.reset(); // Reset mã hóa khi xóa dữ liệu
      UserService.clearCache(); // Xóa cache shopId
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('Logout error: $e');
      }
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
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
        title: Text(
          localizations.systemSettings,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection(localizations.languageAndInterface),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.language, color: Colors.blue),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                localizations.languageApp,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                localizations.selectLanguage,
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                          ),
                          child: DropdownButton<Locale>(
                            value: _selectedLocale,
                            underline: const SizedBox(),
                            isDense: true,
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.blue),
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue,
                              fontSize: 14,
                            ),
                            items: [
                              DropdownMenuItem(
                                value: const Locale('vi'),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('🇻🇳 ', style: TextStyle(fontSize: 18)),
                                    Text(
                                      localizations.vietnamese,
                                      style: const TextStyle(color: Colors.blue),
                                    ),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: const Locale('en'),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text('🇺🇸 ', style: TextStyle(fontSize: 18)),
                                    Text(
                                      localizations.english,
                                      style: const TextStyle(color: Colors.blue),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (locale) {
                              if (locale != null) {
                                setState(() => _selectedLocale = locale);
                                widget.setLocale?.call(locale);
                                // Lưu vào SharedPreferences
                                SharedPreferences.getInstance().then(
                                  (prefs) => prefs.setString('app_language', locale.languageCode),
                                );
                                NotificationService.showSnackBar(
                                  locale.languageCode == 'vi' 
                                    ? loc.changedToVietnamese
                                    : loc.changedToEnglish,
                                  color: Colors.green,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // ====== HƯỚNG DẪN SỬ DỤNG - MOVE LÊN ĐẦU ĐỂ DỄ TÌM ======
                _buildSection(loc.userGuideSection),
                
                // Card chính: Hướng dẫn sử dụng đầy đủ
                Card(
                  color: Colors.purple.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: Colors.purple.shade100),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(18),
                    leading: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.purple.shade400, Colors.purple.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purple.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.menu_book_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    title: Text(
                      loc.userGuideTitle,
                      style: const TextStyle(
                        color: Colors.purple,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 6),
                        Text(
                          loc.userGuideDesc,
                          style: TextStyle(
                            fontSize: AppTextStyles.body1.fontSize,
                            color: Colors.purple.shade800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildFeatureChip(loc.inventoryFeature, Colors.blue),
                            _buildFeatureChip(loc.salesFeature, Colors.orange),
                            _buildFeatureChip(loc.repairFeature, Colors.purple),
                            _buildFeatureChip(loc.reportFeature, Colors.pink),
                          ],
                        ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.purple,
                      ),
                    ),
                    onTap: _openUserGuide,
                  ),
                ),
                
                const SizedBox(height: 16),
                
                const Divider(),
                _buildSection(localizations.accountAndSecurity),
                ListTile(
                  leading: const Icon(Icons.person_pin, color: Colors.teal),
                  title: Text(localizations.yourRole),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _getRoleDisplayName(_role, localizations),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextStyles.caption.fontSize,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // NÚT CHỌN SHOP KHÁC - Chỉ hiện cho Super Admin
                if (UserService.isCurrentUserSuperAdmin()) ...[
                  Card(
                    color: Colors.deepPurple.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: Colors.deepPurple.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.swap_horiz,
                        color: Colors.deepPurple,
                      ),
                      title: Text(
                        localizations.selectOtherShop,
                        style: const TextStyle(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        "${localizations.currentShop}: ${UserService.getAdminSelectedShop()?.substring(0, 8) ?? 'N/A'}...",
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      onTap: () async {
                        await SyncService.cancelAllSubscriptions();
                        await DBHelper().clearAllData();
                        UserService.setAdminSelectedShop(null);
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) =>
                                  ShopSelectorView(setLocale: widget.setLocale),
                            ),
                            (route) => false,
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 15),
                ],

                Card(
                  color: Colors.red.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.red.shade200),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.logout, color: Colors.red),
                    title: Text(
                      localizations.logoutAccount,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      localizations.logoutFromApp,
                      style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                    ),
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(localizations.logoutQuestion),
                          content: Text(localizations.confirmLogout),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(localizations.cancel.toUpperCase()),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: Text(
                                localizations.logout.toUpperCase(),
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        // Thực hiện đăng xuất trực tiếp, không dùng dialog
                        try {
                          await SyncService.cancelAllSubscriptions();
                          EncryptionService.reset();
                          UserService.clearCache();
                          UserService.setAdminSelectedShop(null);
                          await DBHelper().clearAllData();
                          await FirebaseAuth.instance.signOut();
                          // AuthGate sẽ tự động chuyển về LoginView
                        } catch (e) {
                          debugPrint('Logout error: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  localizations.logoutError(e.toString()),
                                ),
                              ),
                            );
                          }
                        }
                      }
                    },
                  ),
                ),

                // ĐỒNG BỘ DỮ LIỆU - Chỉ còn 1 entry point duy nhất
                const SizedBox(height: 30),
                _buildSection(localizations.syncManagement),
                // Card đơn giản mở Trung tâm đồng bộ
                Card(
                  color: Colors.teal.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.teal.shade200),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.cloud_sync,
                        color: Colors.teal,
                        size: 28,
                      ),
                    ),
                    title: Text(
                      localizations.syncCenter,
                      style: const TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      localizations.syncCenterDesc,
                      style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.teal,
                    ),
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const SyncCenterSheet(),
                      );
                    },
                  ),
                ),

                // NÚT XÓA TRẮNG CHỈ HIỆN CHO SUPER ADMIN
                if (UserService.isCurrentUserSuperAdmin()) ...[
                  const SizedBox(height: 30),
                  _buildSection(localizations.advancedAdmin),

                  // DROPDOWN CHỌN SHOP
                  Card(
                    color: Colors.blue.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: Colors.blue.shade200),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.store, color: Colors.blue.shade700),
                              const SizedBox(width: 10),
                              Text(
                                localizations.selectShopToViewData,
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextStyles.headline3.fontSize,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),


                          Text(
                            localizations.viewShopAsAdmin,
                            style: TextStyle(
                              fontSize: AppTextStyles.subtitle1.fontSize,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 15),
                          if (_loadingShops)
                            const Center(child: CircularProgressIndicator())
                          else if (_allShops.isEmpty)
                            Text(
                              localizations.noShops,
                              style: const TextStyle(color: Colors.grey),
                            )
                          else
                            DropdownButtonFormField<String>(
                              initialValue: _selectedShopId,
                              decoration: InputDecoration(
                                labelText: localizations.selectShopLabel,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              hint: Text(localizations.selectShopPlaceholder),
                              items: _allShops.map((shop) {
                                final shopName =
                                    shop['name'] ?? 'Shop ${shop['id']}';
                                final ownerEmail = shop['ownerEmail'] ?? '';
                                return DropdownMenuItem<String>(
                                  value: shop['id'],
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        shopName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        ownerEmail,
                                        style: TextStyle(
                                          fontSize:
                                              AppTextStyles.body1.fontSize,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                              onChanged: _onShopSelected,
                              isExpanded: true,
                              selectedItemBuilder: (context) {
                                return _allShops.map((shop) {
                                  return Text(
                                    shop['name'] ?? 'Shop ${shop['id']}',
                                  );
                                }).toList();
                              },
                            ),
                          if (_selectedShopId != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.green.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      localizations.currentlyViewing(
                                        _allShops.firstWhere(
                                              (s) => s['id'] == _selectedShopId,
                                              orElse: () => {
                                                'name': _selectedShopId,
                                              },
                                            )['name'] ??
                                            _selectedShopId,
                                      ),
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),

                  Card(
                    color: Colors.orange.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: Colors.orange.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.admin_panel_settings,
                        color: Colors.orange,
                      ),
                      title: Text(
                        localizations.staffPermissions,
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        localizations.viewAndEditStaffPermissions,
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const StaffPermissionsView(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  // Nút reset hướng dẫn sử dụng
                  Card(
                    color: Colors.blue.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: Colors.blue.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.replay,
                        color: Colors.blue,
                      ),
                      title: Text(
                        loc.reviewUserGuide,
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        loc.resetGuidesDesc,
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      onTap: () async {
                        await FirstTimeGuideService.resetAllGuides();
                        if (mounted) {
                          NotificationService.showSnackBar(
                            loc.guidesReset,
                            color: Colors.green,
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 15),
                  Card(
                    color: Colors.red.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.delete_forever,
                        color: Colors.red,
                      ),
                      title: Text(
                        localizations.resetShopData,
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        localizations.resetShopAdminOnly,
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                      onTap: _handleResetShop,
                    ),
                  ),
                ],

                const SizedBox(height: 50),
                Center(
                  child: FutureBuilder<String>(
                    future: _versionFuture,
                    builder: (context, snapshot) {
                      final versionText = snapshot.data != null
                          ? localizations.versionFormat(snapshot.data!)
                          : '${localizations.versionFormat('...')}';
                      return Text(
                        versionText,
                        style: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: AppTextStyles.caption.fontSize,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSection(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
    child: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: AppTextStyles.subtitle1.fontSize,
        color: Colors.blueGrey,
      ),
    ),
  );

  Widget _buildFeatureChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
