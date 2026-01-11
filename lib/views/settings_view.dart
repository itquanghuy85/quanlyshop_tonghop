import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/encryption_service.dart';
import '../data/db_helper.dart';
import '../services/sync_service.dart';
import '../widgets/unified_sync_button.dart';
import 'staff_permissions_view.dart';
import 'shop_selector_view.dart'; // Màn hình chọn shop cho super admin

class SettingsView extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const SettingsView({super.key, this.setLocale});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String _role = 'user';
  bool _loading = true;

  // Super admin shop selection
  List<Map<String, dynamic>> _allShops = [];
  String? _selectedShopId;
  bool _loadingShops = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadShopsForAdmin();
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
      "Đang tải dữ liệu shop...",
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

      final shopName = _allShops.firstWhere(
        (s) => s['id'] == shopId,
        orElse: () => {'name': shopId},
      )['name'] ?? shopId;

      NotificationService.showSnackBar(
        "Đã chuyển sang shop: $shopName",
        color: Colors.green,
      );
    } catch (e) {
      debugPrint('Error switching shop: $e');
      NotificationService.showSnackBar(
        "Lỗi khi chuyển shop: $e",
        color: Colors.red,
      );
    }
  }

  String _getRoleDisplayName(String role) {
    switch (role) {
      case 'owner':
        return 'CHỦ SHOP';
      case 'manager':
        return 'QUẢN LÝ';
      case 'employee':
        return 'NHÂN VIÊN';
      case 'technician':
        return 'KỸ THUẬT';
      case 'admin':
        return 'ADMIN';
      case 'user':
        return 'NGƯỜI DÙNG';
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

  // HÀM XỬ LÝ XÓA TRẮNG SHOP (BẢO MẬT TUYỆT ĐỐI)
  Future<void> _handleResetShop() async {
    // Chỉ super admin mới được xóa dữ liệu shop
    if (!UserService.isCurrentUserSuperAdmin()) {
      NotificationService.showSnackBar(
        "CHỈ SUPER ADMIN MỚI ĐƯỢC XÓA DỮ LIỆU SHOP!",
        color: Colors.red,
      );
      return;
    }

    final confirmTextC = TextEditingController();
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "⚠️ CẢNH BÁO NGUY HIỂM",
          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Hành động này sẽ xóa sạch 100% dữ liệu Đơn hàng, Kho, Nợ và Nhật ký của Shop trên cả Đám mây và Máy này. KHÔNG THỂ KHÔI PHỤC!",
            ),
            const SizedBox(height: 15),
            const Text(
              "Nhập chữ 'XOA HET' để xác nhận:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
            TextField(
              controller: confirmTextC,
              decoration: const InputDecoration(hintText: "XOA HET"),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(ctx, confirmTextC.text.trim() == "XOA HET"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              "XÁC NHẬN XÓA SẠCH",
              style: TextStyle(color: Colors.white),
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
          "ĐÃ XÓA SẠCH DỮ LIỆU SHOP!",
          color: Colors.green,
        );
      } else {
        NotificationService.showSnackBar(
          "LỖI KHI XÓA DỮ LIỆU ĐÁM MÂY: $errorMessage",
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("CÀI ĐẶT HỆ THỐNG"),
        automaticallyImplyLeading: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSection("NGÔN NGỮ & GIAO DIỆN"),
                ListTile(
                  leading: const Icon(Icons.language, color: Colors.blue),
                  title: const Text("Ngôn ngữ ứng dụng"),
                  trailing: const Text("Tiếng Việt"),
                  onTap: () {
                    if (widget.setLocale != null) {
                      widget.setLocale!(const Locale('vi'));
                    }
                  },
                ),
                const Divider(),
                _buildSection("TÀI KHOẢN & BẢO MẬT"),
                ListTile(
                  leading: const Icon(Icons.person_pin, color: Colors.teal),
                  title: const Text("Vai trò của bạn"),
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
                      _getRoleDisplayName(_role),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
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
                      leading: const Icon(Icons.swap_horiz, color: Colors.deepPurple),
                      title: const Text(
                        "CHỌN SHOP KHÁC",
                        style: TextStyle(
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        "Shop hiện tại: ${UserService.getAdminSelectedShop()?.substring(0, 8) ?? 'N/A'}...",
                        style: const TextStyle(fontSize: 11),
                      ),
                      onTap: () async {
                        await SyncService.cancelAllSubscriptions();
                        await DBHelper().clearAllData();
                        UserService.setAdminSelectedShop(null);
                        if (mounted) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (context) => ShopSelectorView(setLocale: widget.setLocale),
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
                    title: const Text(
                      "ĐĂNG XUẤT TÀI KHOẢN",
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      "Đăng xuất khỏi ứng dụng",
                      style: TextStyle(fontSize: 11),
                    ),
                    onTap: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text("Đăng xuất?"),
                          content: const Text(
                            "Bạn có chắc muốn đăng xuất khỏi tài khoản?",
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text("HỦY"),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                              ),
                              child: const Text(
                                "ĐĂNG XUẤT",
                                style: TextStyle(color: Colors.white),
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
                              SnackBar(content: Text('Lỗi đăng xuất: $e')),
                            );
                          }
                        }
                      }
                    },
                  ),
                ),

                // ĐỒNG BỘ DỮ LIỆU - Chỉ còn 1 entry point duy nhất
                const SizedBox(height: 30),
                _buildSection("ĐỒNG BỘ DỮ LIỆU"),
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
                    title: const Text(
                      "TRUNG TÂM ĐỒNG BỘ",
                      style: TextStyle(
                        color: Colors.teal,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      "Tải về, đẩy lên, kiểm tra và khôi phục dữ liệu",
                      style: TextStyle(fontSize: 11),
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
                  _buildSection("QUẢN TRỊ NÂNG CAO"),

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
                                "CHỌN SHOP ĐỂ XEM",
                                style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            "Super Admin có thể chọn shop để xem dữ liệu",
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          const SizedBox(height: 15),
                          if (_loadingShops)
                            const Center(child: CircularProgressIndicator())
                          else if (_allShops.isEmpty)
                            const Text(
                              "Không có shop nào",
                              style: TextStyle(color: Colors.grey),
                            )
                          else
                            DropdownButtonFormField<String>(
                              initialValue: _selectedShopId,
                              decoration: InputDecoration(
                                labelText: "Chọn shop",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                filled: true,
                                fillColor: Colors.white,
                              ),
                              hint: const Text("-- Chọn shop để xem --"),
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
                                        style: const TextStyle(
                                          fontSize: 11,
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
                                      "Đang xem: ${_allShops.firstWhere((s) => s['id'] == _selectedShopId, orElse: () => {'name': _selectedShopId})['name'] ?? _selectedShopId}",
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
                      title: const Text(
                        "QUẢN LÝ PHÂN QUYỀN NHÂN VIÊN",
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        "Xem và chỉnh sửa quyền truy cập của từng nhân viên",
                        style: TextStyle(fontSize: 11),
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
                      title: const Text(
                        "XÓA TRẮNG DỮ LIỆU SHOP",
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        "Dùng khi muốn khởi tạo lại toàn bộ dữ liệu cửa hàng (CHỈ SUPER ADMIN)",
                        style: TextStyle(fontSize: 11),
                      ),
                      onTap: _handleResetShop,
                    ),
                  ),
                ],

                const SizedBox(height: 50),
                Center(
                  child: Text(
                    "Phiên bản 1.0.0+7",
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 10),
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
      style: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 12,
        color: Colors.blueGrey,
      ),
    ),
  );
}
