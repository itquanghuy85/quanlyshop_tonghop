import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/social_auth_service.dart';
import '../services/super_admin_security_service.dart';
import '../services/user_service.dart';
import '../services/current_shop_service.dart';
import '../theme/app_text_styles.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/encryption_service.dart';
import '../data/db_helper.dart';
import '../services/sync_service.dart';
import '../utils/app_info.dart';
import '../services/first_time_guide_service.dart';
import '../widgets/unified_sync_button.dart';
import '../widgets/shop_switcher_widget.dart';
import '../widgets/custom_app_bar.dart';
import 'help_center_view.dart';
import 'user_guide_view.dart';
import 'shop_selector_view.dart';
import 'staff_permissions_view.dart';
import 'category_management_view.dart';
import '../widgets/responsive_wrapper.dart';

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
  // Language selection hidden — Vietnamese only

  @override
  void initState() {
    super.initState();
    _versionFuture = AppInfo.getVersion();
    _loadRole();
    _loadShopsForAdmin();
    // Language selection hidden
  }
  
  /// Load danh sách shops cho super admin
  Future<void> _loadShopsForAdmin() async {
    if (!UserService.isCurrentUserSuperAdmin()) return;
    setState(() => _loadingShops = true);
    try {
      final shops = await UserService.getAllShops();
      if (mounted) {
        final savedShopId = UserService.getAdminSelectedShop();
        // Validate that savedShopId exists in shops list
        final shopExists = savedShopId != null &&
            shops.any((s) => s['id'] == savedShopId);
        setState(() {
          _allShops = shops;
          _selectedShopId = shopExists ? savedShopId : null;
          _loadingShops = false;
        });
        // Clear invalid saved shop
        if (savedShopId != null && !shopExists) {
          UserService.setAdminSelectedShop(null);
        }
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

      // Xóa local data cũ + reset sync timestamps
      await DBHelper().clearAllData();
      await SyncService.resetSyncTimestamps();

      // Download data của shop mới
      await SyncService.downloadAllFromCloud(force: true);

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
            const SizedBox(height: 8),
            Text(
              loc.typeToConfirm,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
      CurrentShopService().clear(); // Clear multi-shop cache
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
      appBar: CustomAppBar.build(
        title: localizations.systemSettings,
      ),
      body: ResponsiveCenter(
        maxWidth: 800,
        child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(10),
              children: [
                // ====== TÀI KHOẢN & BẢO MẬT - ĐẶT LÊN ĐẦU ĐỂ DỄ TÌM ======
                _buildSection(localizations.accountAndSecurity),
                // Card tài khoản gọn: avatar + tên + email + role + liên kết + đăng xuất
                _buildAccountCard(localizations),
                const SizedBox(height: 8),

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
                  const SizedBox(height: 8),
                ],

                // ====== SHOP SWITCHER (Owner với nhiều shop) ======
                ShopSwitcherWidget(
                  onShopChanged: () {
                    // Reload settings when shop changes
                    _loadRole();
                    _loadShopsForAdmin();
                  },
                ),
                
                // ====== HƯỚNG DẪN SỬ DỤNG - MOVE LÊN ĐẦU ĐỂ DỄ TÌM ======
                _buildSection(loc.userGuideSection),
                
                // Card chính: Hướng dẫn sử dụng đầy đủ
                Card(
                  color: Colors.blue.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: Colors.blue.shade100),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(10),
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade400, Colors.blue.shade600],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blue.withOpacity(0.3),
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
                        color: Colors.blue,
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
                            color: Colors.blue.shade800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildFeatureChip(loc.inventoryFeature, Colors.blue),
                            _buildFeatureChip(loc.salesFeature, Colors.orange),
                            _buildFeatureChip(loc.repairFeature, Colors.blue),
                            _buildFeatureChip(loc.reportFeature, Colors.pink),
                          ],
                        ),
                      ],
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.blue,
                      ),
                    ),
                    onTap: _openUserGuide,
                  ),
                ),

                // ĐỒNG BỘ DỮ LIỆU - Chỉ còn 1 entry point duy nhất
                const SizedBox(height: 10),
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
                      showAppBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) => const SyncCenterSheet(),
                      );
                    },
                  ),
                ),

                // ====== QUẢN LÝ CỬA HÀNG ======
                const SizedBox(height: 10),
                _buildSection('Quản lý cửa hàng'),
                
                // Quản lý danh mục sản phẩm
                if (_role == 'owner' || UserService.isCurrentUserSuperAdmin())
                  Card(
                    color: Colors.indigo.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: Colors.indigo.shade200),
                    ),
                    child: ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.category,
                          color: Colors.indigo,
                          size: 28,
                        ),
                      ),
                      title: const Text(
                        'Quản lý danh mục',
                        style: TextStyle(
                          color: Colors.indigo,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        'Thêm, sửa, xóa danh mục sản phẩm',
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.indigo,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const CategoryManagementView(),
                          ),
                        );
                      },
                    ),
                  ),

                // NÚT XÓA TRẮNG CHỈ HIỆN CHO SUPER ADMIN
                if (UserService.isCurrentUserSuperAdmin()) ...[
                  const SizedBox(height: 10),
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
                          const SizedBox(height: 8),
                          if (_loadingShops)
                            const Center(child: CircularProgressIndicator())
                          else if (_allShops.isEmpty)
                            Text(
                              localizations.noShops,
                              style: const TextStyle(color: Colors.grey),
                            )
                          else
                            DropdownButtonFormField<String>(
                              // Safety: ensure value exists in items to prevent assertion error
                              value: _selectedShopId != null &&
                                      _allShops.any((s) => s['id'] == _selectedShopId)
                                  ? _selectedShopId
                                  : null,
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
                  const SizedBox(height: 8),

                  // BẢO MẬT SUPER ADMIN - PIN & Audit
                  _buildSuperAdminSecurityCard(),
                  const SizedBox(height: 8),

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
                  const SizedBox(height: 8),
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
                  const SizedBox(height: 8),
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

                const SizedBox(height: 16),
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
      ),
    );
  }

  Widget _buildSuperAdminSecurityCard() {
    return Card(
      color: Colors.red.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.red.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield, color: Colors.red.shade700, size: 22),
                const SizedBox(width: 8),
                Text(
                  'Bảo mật Super Admin',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Mã PIN bảo vệ khi đăng nhập & nhật ký truy cập',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Divider(height: 16),
            // PIN Setup/Change
            FutureBuilder<bool>(
              future: SuperAdminSecurityService.isPinSetup(),
              builder: (context, snap) {
                final hasPin = snap.data ?? false;
                return Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        hasPin ? Icons.lock : Icons.lock_open,
                        color: hasPin ? Colors.green : Colors.orange,
                      ),
                      title: Text(
                        hasPin ? 'Mã PIN đã bật' : 'Mã PIN chưa thiết lập',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        hasPin
                            ? 'Mỗi lần đăng nhập sẽ yêu cầu nhập PIN'
                            : 'Bật PIN để bảo vệ tài khoản super admin',
                        style: const TextStyle(fontSize: 12),
                      ),
                      trailing: hasPin
                          ? PopupMenuButton<String>(
                              onSelected: (val) {
                                if (val == 'change') _showSetupPinDialog(isChange: true);
                                if (val == 'remove') _showRemovePinDialog();
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(value: 'change', child: Text('Đổi PIN')),
                                const PopupMenuItem(value: 'remove', child: Text('Tắt PIN')),
                              ],
                            )
                          : TextButton(
                              onPressed: () => _showSetupPinDialog(),
                              child: const Text('Thiết lập'),
                            ),
                    ),
                    const Divider(height: 8),
                    // Audit Log
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.history, color: Colors.deepPurple),
                      title: const Text(
                        'Nhật ký truy cập',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Xem lịch sử đăng nhập & thao tác',
                        style: TextStyle(fontSize: 12),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: _showAuditLogDialog,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSetupPinDialog({bool isChange = false}) {
    final pinC = TextEditingController();
    final confirmC = TextEditingController();
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.pin, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text(isChange ? 'Đổi mã PIN' : 'Thiết lập mã PIN'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinC,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Mã PIN mới (4-6 số)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmC,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: 'Nhập lại mã PIN',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline),
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (pinC.text != confirmC.text) {
                  setDialogState(() => error = 'Mã PIN không khớp');
                  return;
                }
                if (pinC.text.length < 4) {
                  setDialogState(() => error = 'PIN phải từ 4-6 số');
                  return;
                }
                final ok = await SuperAdminSecurityService.setupPin(pinC.text);
                if (ok && mounted) {
                  Navigator.pop(ctx);
                  setState(() {}); // Refresh card
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Đã thiết lập mã PIN thành công!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  setDialogState(() => error = 'Lỗi thiết lập PIN');
                }
              },
              child: const Text('XÁC NHẬN'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRemovePinDialog() {
    final pinC = TextEditingController();
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock_open, color: Colors.red),
              SizedBox(width: 8),
              Text('Tắt mã PIN'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Nhập mã PIN hiện tại để xác nhận tắt:'),
              const SizedBox(height: 12),
              TextField(
                controller: pinC,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Mã PIN hiện tại',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final verified = await SuperAdminSecurityService.verifyPin(pinC.text);
                if (!verified) {
                  setDialogState(() => error = 'Mã PIN không đúng');
                  return;
                }
                await SuperAdminSecurityService.removePin();
                if (mounted) {
                  Navigator.pop(ctx);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Đã tắt mã PIN'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              },
              child: const Text('TẮT PIN', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showAuditLogDialog() async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.history, color: Colors.deepPurple),
            SizedBox(width: 8),
            Text('Nhật ký truy cập'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: SuperAdminSecurityService.getRecentAuditLogs(limit: 30),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final logs = snap.data ?? [];
              if (logs.isEmpty) {
                return const Center(
                  child: Text('Chưa có nhật ký', style: TextStyle(color: Colors.grey)),
                );
              }
              return ListView.separated(
                itemCount: logs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final log = logs[i];
                  final action = log['action'] as String? ?? '';
                  final success = log['success'] as bool? ?? true;
                  final ts = log['timestamp'];
                  final platform = log['platform'] as String? ?? '';
                  String timeStr = '—';
                  if (ts is Timestamp) {
                    timeStr = _formatAuditTime(ts.toDate());
                  }
                  IconData icon;
                  Color color;
                  if (action.contains('login')) {
                    icon = Icons.login;
                    color = Colors.blue;
                  } else if (action.contains('shop_access')) {
                    icon = Icons.store;
                    color = Colors.green;
                  } else if (action.contains('pin_verified')) {
                    icon = Icons.check_circle;
                    color = Colors.green;
                  } else if (action.contains('failed')) {
                    icon = Icons.warning;
                    color = Colors.red;
                  } else {
                    icon = Icons.info;
                    color = Colors.grey;
                  }
                  return ListTile(
                    dense: true,
                    leading: Icon(icon, color: success ? color : Colors.red, size: 20),
                    title: Text(
                      _formatAuditAction(action),
                      style: TextStyle(fontSize: 13, color: success ? Colors.black87 : Colors.red),
                    ),
                    subtitle: Text(
                      '$timeStr · $platform',
                      style: const TextStyle(fontSize: 11),
                    ),
                  );
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );
  }

  String _formatAuditTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 7) return '${diff.inDays} ngày trước';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatAuditAction(String action) {
    if (action == 'super_admin_login') return 'Đăng nhập Super Admin';
    if (action == 'pin_verified') return 'Xác thực PIN thành công';
    if (action == 'pin_verify_failed') return '⚠ Nhập PIN sai';
    if (action.startsWith('shop_access:')) {
      return 'Truy cập shop: ${action.replaceFirst('shop_access: ', '')}';
    }
    return action;
  }

  /// Card tài khoản tổng hợp: user info + liên kết + đăng xuất
  Widget _buildAccountCard(AppLocalizations localizations) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'N/A';
    final displayName = user?.displayName ?? email.split('@').first;
    final photoUrl = user?.photoURL;
    final googleLinked = SocialAuthService.isGoogleLinked();
    final appleLinked = SocialAuthService.isAppleLinked();
    final passwordLinked = SocialAuthService.isPasswordLinked();
    final showApple = kIsWeb || (!kIsWeb && Platform.isIOS) || (!kIsWeb && Platform.isMacOS);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // User info row
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                  backgroundColor: Colors.blue.shade100,
                  child: photoUrl == null
                      ? Text(
                          displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
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
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _getRoleDisplayName(_role, localizations),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),

            // Linked accounts section
            Row(
              children: [
                const Icon(Icons.link, color: Colors.indigo, size: 18),
                const SizedBox(width: 6),
                const Text(
                  'Liên kết tài khoản',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigo),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildProviderRow(
              icon: Icons.email,
              color: Colors.blue,
              label: 'Email/Mật khẩu',
              linked: passwordLinked,
              onLink: null,
              onUnlink: null,
              providerEmail: SocialAuthService.passwordEmail,
            ),
            const SizedBox(height: 6),
            _buildProviderRow(
              icon: Icons.g_mobiledata,
              color: Colors.red,
              label: 'Google',
              linked: googleLinked,
              onLink: () => _linkProvider('google'),
              onUnlink: googleLinked && SocialAuthService.getLinkedProviders().length > 1
                  ? () => _unlinkProvider('google')
                  : null,
              providerEmail: SocialAuthService.googleEmail,
            ),
            if (showApple) ...[
              const SizedBox(height: 6),
              _buildProviderRow(
                icon: Icons.apple,
                color: Colors.black,
                label: 'Apple',
                linked: appleLinked,
                onLink: () => _linkProvider('apple'),
                onUnlink: appleLinked && SocialAuthService.getLinkedProviders().length > 1
                    ? () => _unlinkProvider('apple')
                    : null,
                providerEmail: SocialAuthService.appleEmail,
              ),
            ],
            const Divider(height: 20),

            // Logout button
            InkWell(
              onTap: () => _confirmLogout(localizations),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.logout, color: Colors.red, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      localizations.logoutAccount,
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

  Future<void> _confirmLogout(AppLocalizations localizations) async {
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              localizations.logout.toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try { await SyncService.cancelAllSubscriptions(); } catch (_) {}
      try { EncryptionService.reset(); } catch (_) {}
      try { UserService.clearCache(); } catch (_) {}
      try { UserService.setAdminSelectedShop(null); } catch (_) {}
      try { SuperAdminSecurityService.clearSession(); } catch (_) {}
      try { await DBHelper().clearAllData(); } catch (_) {}
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('Logout error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizations.logoutError(e.toString()))),
          );
        }
      }
    }
  }

  Widget _buildLinkedAccountsCard() {
    final googleLinked = SocialAuthService.isGoogleLinked();
    final appleLinked = SocialAuthService.isAppleLinked();
    final passwordLinked = SocialAuthService.isPasswordLinked();
    final showApple = kIsWeb || (!kIsWeb && Platform.isIOS) || (!kIsWeb && Platform.isMacOS);

    return Card(
      color: Colors.indigo.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: Colors.indigo.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link, color: Colors.indigo, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Liên kết tài khoản',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Liên kết để đăng nhập nhanh hơn',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Divider(height: 16),
            // Email/Password
            _buildProviderRow(
              icon: Icons.email,
              color: Colors.blue,
              label: 'Email/Mật khẩu',
              linked: passwordLinked,
              onLink: null, // Always linked by default
              onUnlink: null, // Cannot unlink if it's the only method
              providerEmail: SocialAuthService.passwordEmail,
            ),
            const SizedBox(height: 8),
            // Google
            _buildProviderRow(
              icon: Icons.g_mobiledata,
              color: Colors.red,
              label: 'Google',
              linked: googleLinked,
              onLink: () => _linkProvider('google'),
              onUnlink: googleLinked && SocialAuthService.getLinkedProviders().length > 1
                  ? () => _unlinkProvider('google')
                  : null,
              providerEmail: SocialAuthService.googleEmail,
            ),
            // Apple (only on iOS/macOS/web)
            if (showApple) ...[
              const SizedBox(height: 8),
              _buildProviderRow(
                icon: Icons.apple,
                color: Colors.black,
                label: 'Apple',
                linked: appleLinked,
                onLink: () => _linkProvider('apple'),
                onUnlink: appleLinked && SocialAuthService.getLinkedProviders().length > 1
                    ? () => _unlinkProvider('apple')
                    : null,
                providerEmail: SocialAuthService.appleEmail,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProviderRow({
    required IconData icon,
    required Color color,
    required String label,
    required bool linked,
    VoidCallback? onLink,
    VoidCallback? onUnlink,
    String? providerEmail,
  }) {
    return Row(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 14)),
              if (linked && providerEmail != null && providerEmail.isNotEmpty)
                Text(providerEmail, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (linked)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 18),
              const SizedBox(width: 4),
              Text(
                'Đã liên kết',
                style: TextStyle(fontSize: 12, color: Colors.green.shade700),
              ),
              if (onUnlink != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: onUnlink,
                  child: Text(
                    'Hủy',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade400,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ],
          )
        else if (onLink != null)
          TextButton.icon(
            onPressed: onLink,
            icon: Icon(Icons.add_link, size: 16, color: color),
            label: Text(
              'Liên kết',
              style: TextStyle(fontSize: 13, color: color),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }

  Future<void> _linkProvider(String provider) async {
    try {
      if (provider == 'google') {
        await SocialAuthService.linkGoogle();
      } else if (provider == 'apple') {
        await SocialAuthService.linkApple();
      }
      // Force refresh to get updated providerData
      await FirebaseAuth.instance.currentUser?.reload();
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
      if (mounted) {
        setState(() {}); // Refresh UI
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã liên kết $provider thành công!'),
            backgroundColor: Colors.green,
          ),
        );
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

  Future<void> _unlinkProvider(String provider) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hủy liên kết'),
        content: Text(
          'Bạn có chắc muốn hủy liên kết $provider? '
          'Bạn sẽ không thể đăng nhập bằng $provider nữa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('XÁC NHẬN', style: TextStyle(color: Colors.white)),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi hủy liên kết: $e')),
        );
      }
    }
  }

  Widget _buildSection(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    child: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: AppTextStyles.caption.fontSize,
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
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
