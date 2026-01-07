import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/notification_service.dart';
import '../services/encryption_service.dart';
import '../services/sync_health_check.dart';
import '../data/db_helper.dart';
import '../services/sync_service.dart';
import 'staff_permissions_view.dart';
import 'shop_settings_view.dart';
import 'debt_debug_view.dart';
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

  // Sync health status
  bool _checkingSyncHealth = false;
  SyncHealthReport? _syncHealthReport;

  // Super admin shop selection
  List<Map<String, dynamic>> _allShops = [];
  String? _selectedShopId;
  bool _loadingShops = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _checkSyncHealthInBackground();
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

    // Refresh sync health
    _checkSyncHealthInBackground();
  }

  /// Kiểm tra sync health ngầm khi mở Settings
  Future<void> _checkSyncHealthInBackground() async {
    if (mounted) setState(() => _checkingSyncHealth = true);
    try {
      final report = await SyncHealthCheck.runFullCheck();
      if (mounted) {
        setState(() {
          _syncHealthReport = report;
          _checkingSyncHealth = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Lỗi kiểm tra sync health: $e');
      if (mounted) setState(() => _checkingSyncHealth = false);
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

  // HÀM KIỂM TRA TÌNH TRẠNG ĐỒNG BỘ
  Future<void> _handleCheckSyncHealth() async {
    // Hiển thị loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Đang kiểm tra đồng bộ..."),
            Text(
              "So sánh Local vs Cloud",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      ),
    );

    try {
      final report = await SyncHealthCheck.runFullCheck();
      if (!mounted) return;
      Navigator.pop(context); // Đóng loading

      // Hiển thị kết quả
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                report.isFullyHealthy ? Icons.check_circle : Icons.warning,
                color: report.isFullyHealthy ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  report.isFullyHealthy
                      ? "ĐỒNG BỘ HOÀN TẤT"
                      : "CÓ VẤN ĐỀ ĐỒNG BỘ",
                  style: TextStyle(
                    color: report.isFullyHealthy ? Colors.green : Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: report.isFullyHealthy
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Shop ID: ${report.shopId ?? 'N/A'}",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        "Local: ${report.totalLocalRecords} records",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "Cloud: ${report.totalCloudRecords} records",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (report.totalMismatches > 0)
                        Text(
                          "Chưa đồng bộ: ${report.totalMismatches}",
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                const Text(
                  "CHI TIẾT TỪNG LOẠI:",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 10),
                ...report.results.map((r) => _buildSyncResultItem(r)),
              ],
            ),
          ),
          actions: [
            if (!report.isFullyHealthy)
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _handleAutoFixSync();
                },
                icon: const Icon(Icons.sync, color: Colors.white),
                label: const Text(
                  "ĐỒNG BỘ NGAY",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ĐÓNG"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      NotificationService.showSnackBar("❌ Lỗi kiểm tra: $e", color: Colors.red);
    }
  }

  Widget _buildSyncResultItem(SyncCheckResult r) {
    final isOk = r.isHealthy;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOk ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isOk ? Colors.green.shade200 : Colors.red.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check : Icons.error,
            color: isOk ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.collection.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                Text(
                  "Local: ${r.localCount} | Cloud: ${r.cloudCount}",
                  style: const TextStyle(fontSize: 10),
                ),
                if (r.unsyncedLocal > 0)
                  Text(
                    "Chưa sync lên: ${r.unsyncedLocal}",
                    style: const TextStyle(fontSize: 10, color: Colors.orange),
                  ),
                if (r.cloudOnly > 0)
                  Text(
                    "Thiếu ở local: ${r.cloudOnly}",
                    style: const TextStyle(fontSize: 10, color: Colors.red),
                  ),
                if (r.error != null)
                  Text(
                    "Lỗi: ${r.error}",
                    style: const TextStyle(fontSize: 9, color: Colors.red),
                  ),
              ],
            ),
          ),
          Text(
            "${r.syncPercentage.toStringAsFixed(0)}%",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isOk ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleAutoFixSync() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Đang đồng bộ dữ liệu..."),
            SizedBox(height: 8),
            Text(
              "1. Upload local → Cloud\n2. Download Cloud → Local",
              style: TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );

    try {
      final fixedCount = await SyncHealthCheck.autoFix();
      if (!mounted) return;
      Navigator.pop(context);
      NotificationService.showSnackBar(
        "✅ Đồng bộ hoàn tất! Đã sửa $fixedCount records",
        color: Colors.green,
      );
      // Refresh sync health
      _checkSyncHealthInBackground();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      NotificationService.showSnackBar("❌ Lỗi: $e", color: Colors.red);
    }
  }

  // Helper methods cho sync health UI
  Color _getSyncHealthCardColor() {
    if (_checkingSyncHealth || _syncHealthReport == null)
      return Colors.orange.shade50;
    return _syncHealthReport!.isFullyHealthy
        ? Colors.green.shade50
        : Colors.red.shade50;
  }

  Color _getSyncHealthBorderColor() {
    if (_checkingSyncHealth || _syncHealthReport == null)
      return Colors.orange.shade200;
    return _syncHealthReport!.isFullyHealthy
        ? Colors.green.shade200
        : Colors.red.shade200;
  }

  Color _getSyncHealthIconBgColor() {
    if (_checkingSyncHealth || _syncHealthReport == null)
      return Colors.orange.shade100;
    return _syncHealthReport!.isFullyHealthy
        ? Colors.green.shade100
        : Colors.red.shade100;
  }

  Color _getSyncHealthIconColor() {
    if (_checkingSyncHealth || _syncHealthReport == null) return Colors.orange;
    return _syncHealthReport!.isFullyHealthy ? Colors.green : Colors.red;
  }

  String _getSyncHealthTitle() {
    if (_checkingSyncHealth) return "ĐANG KIỂM TRA...";
    if (_syncHealthReport == null) return "KIỂM TRA TÌNH TRẠNG ĐỒNG BỘ";
    return _syncHealthReport!.isFullyHealthy
        ? "✅ ĐỒNG BỘ HOÀN TẤT"
        : "⚠️ CẦN ĐỒNG BỘ";
  }

  String _getSyncHealthSubtitle() {
    if (_checkingSyncHealth) return "Đang so sánh dữ liệu local vs cloud...";
    if (_syncHealthReport == null)
      return "So sánh dữ liệu local vs cloud, phát hiện thiếu sót";
    if (_syncHealthReport!.isFullyHealthy) {
      return "Local: ${_syncHealthReport!.totalLocalRecords} | Cloud: ${_syncHealthReport!.totalCloudRecords}";
    }
    return "${_syncHealthReport!.totalMismatches} bản ghi chưa đồng bộ. Nhấn để xem chi tiết.";
  }

  // HÀM XỬ LÝ TẢI TOÀN BỘ DỮ LIỆU SHOP
  Future<void> _handleDownloadAllData() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "📥 TẢI DỮ LIỆU SHOP",
          style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Hành động này sẽ tải toàn bộ dữ liệu của shop từ đám mây về máy này.",
            ),
            SizedBox(height: 10),
            Text(
              "Bao gồm: Đơn sửa chữa, Sản phẩm, Đơn bán hàng, Nợ, Chi phí, Chấm công.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            SizedBox(height: 15),
            Text(
              "Quá trình có thể mất vài phút tùy thuộc vào lượng dữ liệu.",
              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
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
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            child: const Text(
              "BẮT ĐẦU TẢI",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _loading = true);

      try {
        await SyncService.downloadAllFromCloud();
        NotificationService.showSnackBar(
          "✅ Đã tải xong toàn bộ dữ liệu shop!",
          color: Colors.green,
        );
      } catch (e) {
        NotificationService.showSnackBar(
          "❌ Lỗi tải dữ liệu: $e",
          color: Colors.red,
        );
        debugPrint("Download all data error: $e");
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  // HÀM ĐỒNG BỘ DỮ LIỆU LÊN ĐÁM MÂY
  Future<void> _handleUploadData() async {
    // Kiểm tra số lượng dữ liệu local trước khi upload
    final dbHelper = DBHelper();
    final repairs = await dbHelper.getAllRepairs();
    final sales = await dbHelper.getAllSales();
    final products = await dbHelper.getAllProducts();

    final totalLocal = repairs.length + sales.length + products.length;

    // Cảnh báo nếu dữ liệu local quá ít (có thể là máy mới)
    if (totalLocal < 5) {
      final confirmEmpty = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.orange.shade700,
                size: 28,
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  "CẢNH BÁO",
                  style: TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Máy này có rất ít dữ liệu:"),
              const SizedBox(height: 10),
              Text(
                "• ${repairs.length} đơn sửa chữa",
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                "• ${sales.length} đơn bán hàng",
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                "• ${products.length} sản phẩm",
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "⚠️ NẾU BẠN LÀ NHÂN VIÊN MỚI:",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.red,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      "Vui lòng TẢI DỮ LIỆU VỀ MÁY trước, KHÔNG đồng bộ lên đám mây khi chưa có dữ liệu.",
                      style: TextStyle(fontSize: 11, color: Colors.red),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                "Bạn có chắc chắn muốn tiếp tục?",
                style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text(
                "VẪN TIẾP TỤC",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );

      if (confirmEmpty != true) return;
    }

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          "📤 ĐỒNG BỘ LÊN ĐÁM MÂY",
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Đẩy dữ liệu từ máy này lên đám mây để các thiết bị khác trong shop có thể đồng bộ.",
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Dữ liệu sẽ upload:",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  Text(
                    "• ${repairs.where((r) => !r.isSynced).length} đơn sửa mới",
                    style: const TextStyle(fontSize: 11),
                  ),
                  Text(
                    "• ${sales.where((s) => !s.isSynced).length} đơn bán mới",
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              "✅ Dữ liệu cũ trên đám mây sẽ KHÔNG bị xóa.",
              style: TextStyle(fontSize: 11, color: Colors.green),
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
            child: const Text("ĐỒNG BỘ", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (result == true) {
      setState(() => _loading = true);

      try {
        await SyncService.syncAllToCloud();
        NotificationService.showSnackBar(
          "✅ Đã đồng bộ dữ liệu lên đám mây!",
          color: Colors.green,
        );
      } catch (e) {
        NotificationService.showSnackBar(
          "❌ Lỗi đồng bộ: $e",
          color: Colors.red,
        );
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
      if (mounted)
        Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
                    if (widget.setLocale != null)
                      widget.setLocale!(const Locale('vi'));
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

                // Debug section - di chuyển lên trên để dễ thấy
                _buildSection("DEBUG TOOLS"),
                Card(
                  color: Colors.orange.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.orange.shade200),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.bug_report, color: Colors.orange),
                    title: const Text(
                      "DEBT DEBUG",
                      style: TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      "Kiểm tra dữ liệu công nợ chi tiết",
                      style: TextStyle(fontSize: 11),
                    ),
                    onTap: () {
                      debugPrint('Debt Debug button tapped');
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DebtDebugView(),
                        ),
                      );
                    },
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

                // ĐỒNG BỘ DỮ LIỆU - Tải về cho tất cả, Upload chỉ cho Owner/Manager
                const SizedBox(height: 30),
                _buildSection("ĐỒNG BỘ DỮ LIỆU"),
                // Nút KIỂM TRA SYNC với trạng thái
                Card(
                  color: _getSyncHealthCardColor(),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: _getSyncHealthBorderColor()),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _getSyncHealthIconBgColor(),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: _checkingSyncHealth
                          ? const SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _syncHealthReport?.isFullyHealthy == true
                                  ? Icons.check_circle
                                  : Icons.health_and_safety,
                              color: _getSyncHealthIconColor(),
                              size: 28,
                            ),
                    ),
                    title: Text(
                      _getSyncHealthTitle(),
                      style: TextStyle(
                        color: _getSyncHealthIconColor(),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      _getSyncHealthSubtitle(),
                      style: const TextStyle(fontSize: 11),
                    ),
                    trailing:
                        _syncHealthReport != null &&
                            !_syncHealthReport!.isFullyHealthy
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              "${_syncHealthReport!.totalMismatches}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: _getSyncHealthIconColor(),
                          ),
                    onTap: _handleCheckSyncHealth,
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  color: Colors.blue.shade50,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: Colors.blue.shade200),
                  ),
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.cloud_download,
                        color: Colors.blue,
                        size: 28,
                      ),
                    ),
                    title: const Text(
                      "TẢI DỮ LIỆU SHOP VỀ MÁY",
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text(
                      "Dành cho nhân viên mới hoặc khi đổi máy. Tải toàn bộ dữ liệu shop từ đám mây.",
                      style: TextStyle(fontSize: 11),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: Colors.blue,
                    ),
                    onTap: _handleDownloadAllData,
                  ),
                ),
                // Chỉ Owner/Manager mới được upload dữ liệu lên cloud
                if (_role == 'owner' ||
                    _role == 'manager' ||
                    UserService.isCurrentUserSuperAdmin()) ...[
                  const SizedBox(height: 10),
                  Card(
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
                          Icons.cloud_upload,
                          color: Colors.green,
                          size: 28,
                        ),
                      ),
                      title: const Text(
                        "ĐỒNG BỘ DỮ LIỆU LÊN MÂY",
                        style: TextStyle(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        "Đẩy dữ liệu từ máy này lên đám mây để các thiết bị khác đồng bộ.",
                        style: TextStyle(fontSize: 11),
                      ),
                      trailing: const Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.green,
                      ),
                      onTap: _handleUploadData,
                    ),
                  ),
                ],

                // QUẢN TRỊ SHOP CHO OWNER/MANAGER
                if (_role == 'owner' || _role == 'manager') ...[
                  const SizedBox(height: 30),
                  _buildSection("QUẢN TRỊ SHOP"),
                  Card(
                    color: Colors.purple.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                      side: BorderSide(color: Colors.purple.shade200),
                    ),
                    child: ListTile(
                      leading: const Icon(Icons.store, color: Colors.purple),
                      title: const Text(
                        "THÔNG TIN CỬA HÀNG",
                        style: TextStyle(
                          color: Colors.purple,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: const Text(
                        "Cập nhật logo, thông tin, địa chỉ và quản lý thành viên",
                        style: TextStyle(fontSize: 11),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ShopSettingsView(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                ],

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
                              value: _selectedShopId,
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
