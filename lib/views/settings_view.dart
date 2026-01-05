import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/encryption_service.dart';
import '../data/db_helper.dart';
import '../services/sync_service.dart';
import 'staff_permissions_view.dart';
import 'shop_settings_view.dart';
import 'debt_debug_view.dart';

class SettingsView extends StatefulWidget {
  final void Function(Locale)? setLocale;
  const SettingsView({super.key, this.setLocale});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  String _role = 'user';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRole();
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
      setState(() { _role = role; _loading = false; });
    }
  }

  // HÀM XỬ LÝ TẢI TOÀN BỘ DỮ LIỆU SHOP
  Future<void> _handleDownloadAllData() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("📥 TẢI DỮ LIỆU SHOP", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Hành động này sẽ tải toàn bộ dữ liệu của shop từ đám mây về máy này."),
            SizedBox(height: 10),
            Text("Bao gồm: Đơn sửa chữa, Sản phẩm, Đơn bán hàng, Nợ, Chi phí, Chấm công.", style: TextStyle(fontSize: 12, color: Colors.grey)),
            SizedBox(height: 15),
            Text("Quá trình có thể mất vài phút tùy thuộc vào lượng dữ liệu.", style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("HỦY")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text("BẮT ĐẦU TẢI", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );

    if (result == true) {
      setState(() => _loading = true);
      
      try {
        await SyncService.downloadAllFromCloud();
        NotificationService.showSnackBar("✅ Đã tải xong toàn bộ dữ liệu shop!", color: Colors.green);
      } catch (e) {
        NotificationService.showSnackBar("❌ Lỗi tải dữ liệu: $e", color: Colors.red);
        debugPrint("Download all data error: $e");
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  // HÀM ĐỒNG BỘ DỮ LIỆU LÊN ĐÁM MÂY
  Future<void> _handleUploadData() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("📤 ĐỒNG BỘ LÊN ĐÁM MÂY", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("Đẩy dữ liệu từ máy này lên đám mây để các thiết bị khác trong shop có thể đồng bộ."),
            SizedBox(height: 10),
            Text("Dữ liệu sẽ được mã hóa an toàn trước khi upload.", style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("HỦY")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("ĐỒNG BỘ", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );

    if (result == true) {
      setState(() => _loading = true);
      
      try {
        await SyncService.syncAllToCloud();
        NotificationService.showSnackBar("✅ Đã đồng bộ dữ liệu lên đám mây!", color: Colors.green);
      } catch (e) {
        NotificationService.showSnackBar("❌ Lỗi đồng bộ: $e", color: Colors.red);
        debugPrint("Upload data error: $e");
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  // HÀM XỬ LÝ XÓA TRẮNG SHOP (BẢO MẬT TUYỆT ĐỐI)
  Future<void> _handleResetShop() async {
    // Chỉ super admin mới được xóa dữ liệu shop
    if (!UserService.isCurrentUserSuperAdmin()) {
      NotificationService.showSnackBar("CHỈ SUPER ADMIN MỚI ĐƯỢC XÓA DỮ LIỆU SHOP!", color: Colors.red);
      return;
    }

    final confirmTextC = TextEditingController();
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("⚠️ CẢNH BÁO NGUY HIỂM", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Hành động này sẽ xóa sạch 100% dữ liệu Đơn hàng, Kho, Nợ và Nhật ký của Shop trên cả Đám mây và Máy này. KHÔNG THỂ KHÔI PHỤC!"),
            const SizedBox(height: 15),
            const Text("Nhập chữ 'XOA HET' để xác nhận:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            TextField(controller: confirmTextC, decoration: const InputDecoration(hintText: "XOA HET"), textAlign: TextAlign.center),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("HỦY")),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, confirmTextC.text.trim() == "XOA HET"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("XÁC NHẬN XÓA SẠCH", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );

    if (result == true) {
      setState(() => _loading = true);
      final errorMessage = await FirestoreService.resetEntireShopData();
      await DBHelper().clearAllData();
      
      if (errorMessage == null) {
        NotificationService.showSnackBar("ĐÃ XÓA SẠCH DỮ LIỆU SHOP!", color: Colors.green);
      } else {
        NotificationService.showSnackBar("LỖI KHI XÓA DỮ LIỆU ĐÁM MÂY: $errorMessage", color: Colors.red);
      }
      await SyncService.cancelAllSubscriptions();
      EncryptionService.reset(); // Reset mã hóa khi xóa dữ liệu
      try {
        await FirebaseAuth.instance.signOut();
      } catch (e) {
        debugPrint('Logout error: $e');
      }
      if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("CÀI ĐẶT HỆ THỐNG"), automaticallyImplyLeading: true),
      body: _loading ? const Center(child: CircularProgressIndicator()) : ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection("NGÔN NGỮ & GIAO DIỆN"),
          ListTile(
            leading: const Icon(Icons.language, color: Colors.blue),
            title: const Text("Ngôn ngữ ứng dụng"),
            trailing: const Text("Tiếng Việt"),
            onTap: () {
              if (widget.setLocale != null) widget.setLocale!(const Locale('vi'));
            },
          ),
          const Divider(),
          _buildSection("TÀI KHOẢN & BẢO MẬT"),
          ListTile(
            leading: const Icon(Icons.person_pin, color: Colors.teal),
            title: const Text("Vai trò của bạn"),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
              child: Text(_getRoleDisplayName(_role), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.blue)),
            ),
          ),
          const SizedBox(height: 15),

          // Debug section - di chuyển lên trên để dễ thấy
          _buildSection("DEBUG TOOLS"),
          Card(
            color: Colors.orange.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.orange.shade200)),
            child: ListTile(
              leading: const Icon(Icons.bug_report, color: Colors.orange),
              title: const Text("DEBT DEBUG", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
              subtitle: const Text("Kiểm tra dữ liệu công nợ chi tiết", style: TextStyle(fontSize: 11)),
              onTap: () {
                debugPrint('Debt Debug button tapped');
                Navigator.push(context, MaterialPageRoute(builder: (_) => const DebtDebugView()));
              },
            ),
          ),
          const SizedBox(height: 15),

          Card(
            color: Colors.red.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.red.shade200)),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("ĐĂNG XUẤT TÀI KHOẢN", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              subtitle: const Text("Đăng xuất khỏi ứng dụng", style: TextStyle(fontSize: 11)),
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text("Đăng xuất?"),
                    content: const Text("Bạn có chắc muốn đăng xuất khỏi tài khoản?"),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("HỦY")),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: const Text("ĐĂNG XUẤT", style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await SyncService.cancelAllSubscriptions();
                  EncryptionService.reset(); // Reset mã hóa khi đăng xuất
                  try {
                    await FirebaseAuth.instance.signOut();
                  } catch (e) {
                    debugPrint('Logout error: $e');
                  }
                  if (mounted) Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
                }
              },
            ),
          ),

          // ĐỒNG BỘ DỮ LIỆU - Hiển thị cho tất cả người dùng
          const SizedBox(height: 30),
          _buildSection("ĐỒNG BỘ DỮ LIỆU"),
          Card(
            color: Colors.blue.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.blue.shade200)),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_download, color: Colors.blue, size: 28),
              ),
              title: const Text("TẢI DỮ LIỆU SHOP VỀ MÁY", style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
              subtitle: const Text("Dành cho nhân viên mới hoặc khi đổi máy. Tải toàn bộ dữ liệu shop từ đám mây.", style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.blue),
              onTap: _handleDownloadAllData,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            color: Colors.green.shade50,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.green.shade200)),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_upload, color: Colors.green, size: 28),
              ),
              title: const Text("ĐỒNG BỘ DỮ LIỆU LÊN MÂY", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              subtitle: const Text("Đẩy dữ liệu từ máy này lên đám mây để các thiết bị khác đồng bộ.", style: TextStyle(fontSize: 11)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.green),
              onTap: _handleUploadData,
            ),
          ),
          
          // QUẢN TRỊ SHOP CHO OWNER/MANAGER
          if (_role == 'owner' || _role == 'manager') ...[
            const SizedBox(height: 30),
            _buildSection("QUẢN TRỊ SHOP"),
            Card(
              color: Colors.purple.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.purple.shade200)),
              child: ListTile(
                leading: const Icon(Icons.store, color: Colors.purple),
                title: const Text("THÔNG TIN CỬA HÀNG", style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold)),
                subtitle: const Text("Cập nhật logo, thông tin, địa chỉ và quản lý thành viên", style: TextStyle(fontSize: 11)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ShopSettingsView())),
              ),
            ),
            const SizedBox(height: 15),
          ],
          
          // NÚT XÓA TRẮNG CHỈ HIỆN CHO SUPER ADMIN
          if (UserService.isCurrentUserSuperAdmin()) ...[
            const SizedBox(height: 30),
            _buildSection("QUẢN TRỊ NÂNG CAO"),
            Card(
              color: Colors.orange.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.orange.shade200)),
              child: ListTile(
                leading: const Icon(Icons.admin_panel_settings, color: Colors.orange),
                title: const Text("QUẢN LÝ PHÂN QUYỀN NHÂN VIÊN", style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                subtitle: const Text("Xem và chỉnh sửa quyền truy cập của từng nhân viên", style: TextStyle(fontSize: 11)),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StaffPermissionsView())),
              ),
            ),
            const SizedBox(height: 15),
            Card(
              color: Colors.red.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15), side: BorderSide(color: Colors.red.shade200)),
              child: ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text("XÓA TRẮNG DỮ LIỆU SHOP", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                subtitle: const Text("Dùng khi muốn khởi tạo lại toàn bộ dữ liệu cửa hàng (CHỈ SUPER ADMIN)", style: TextStyle(fontSize: 11)),
                onTap: _handleResetShop,
              ),
            ),

          ],
          
          const SizedBox(height: 50),
          Center(child: Text("Phiên bản 1.0.0+7", style: TextStyle(color: Colors.grey.shade400, fontSize: 10))),
        ],
      ),
    );
  }

  Widget _buildSection(String title) => Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5), child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)));
}
