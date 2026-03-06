import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/responsive_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_text_styles.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../services/audit_service.dart';
import '../data/db_helper.dart';
import '../l10n/app_localizations.dart';

ImageProvider? _safeImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return NetworkImage(path);
  final file = File(path);
  return file.existsSync() ? FileImage(file) : null;
}

class StaffPermissionsView extends StatefulWidget {
  const StaffPermissionsView({super.key});

  @override
  State<StaffPermissionsView> createState() => _StaffPermissionsViewState();
}

class _StaffPermissionsViewState extends State<StaffPermissionsView> {
  final db = DBHelper();
  String? _currentRole;
  String? _currentShopId;
  bool _isSuperAdmin = false;
  bool _loadingRole = true;
  bool _hasManageStaffAccess = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUserRole();
  }

  Future<void> _loadCurrentUserRole() async {
    final user = FirebaseAuth.instance.currentUser;
    if (!mounted) return;
    if (user == null) {
      setState(() => _loadingRole = false);
      return;
    }

    final role = await UserService.getUserRole(user.uid);
    final shopId = await UserService.getCurrentShopId();
    final perms = await UserService.getCurrentUserPermissions();

    if (!mounted) return;
    setState(() {
      _currentRole = role;
      _currentShopId = shopId;
      _isSuperAdmin = UserService.isCurrentUserSuperAdmin();
      _hasManageStaffAccess = perms['allowManageStaff'] ?? false;
      _loadingRole = false;
    });
  }

  bool get _canManageStaff => _isSuperAdmin || _currentRole == 'owner' || _currentRole == 'manager';

  Future<void> _updateUserPermission(String uid, String permissionKey, bool value) async {
    try {
      // Lấy dữ liệu user hiện tại để có tất cả permissions
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};

      await UserService.updateUserPermissions(
        uid: uid,
        allowViewSales: permissionKey == 'allowViewSales' ? value : (userData['allowViewSales'] ?? false),
        allowViewRepairs: permissionKey == 'allowViewRepairs' ? value : (userData['allowViewRepairs'] ?? false),
        allowViewInventory: permissionKey == 'allowViewInventory' ? value : (userData['allowViewInventory'] ?? false),
        allowViewParts: permissionKey == 'allowViewParts' ? value : (userData['allowViewParts'] ?? false),
        allowViewSuppliers: permissionKey == 'allowViewSuppliers' ? value : (userData['allowViewSuppliers'] ?? false),
        allowViewCustomers: permissionKey == 'allowViewCustomers' ? value : (userData['allowViewCustomers'] ?? false),
        allowViewWarranty: permissionKey == 'allowViewWarranty' ? value : (userData['allowViewWarranty'] ?? false),
        allowViewChat: permissionKey == 'allowViewChat' ? value : (userData['allowViewChat'] ?? false),
        allowViewAttendance: permissionKey == 'allowViewAttendance' ? value : (userData['allowViewAttendance'] ?? false),
        allowViewPrinter: permissionKey == 'allowViewPrinter' ? value : (userData['allowViewPrinter'] ?? false),
        allowViewRevenue: permissionKey == 'allowViewRevenue' ? value : (userData['allowViewRevenue'] ?? false),
        allowViewExpenses: permissionKey == 'allowViewExpenses' ? value : (userData['allowViewExpenses'] ?? false),
        allowViewDebts: permissionKey == 'allowViewDebts' ? value : (userData['allowViewDebts'] ?? false),
        allowViewCostPrice: permissionKey == 'allowViewCostPrice' ? value : (userData['allowViewCostPrice'] ?? false),
      );
      if (mounted) {
        // Ghi log thay đổi quyền
        await AuditService.logAction(
          action: 'CẬP NHẬT QUYỀN',
          entityType: 'PERMISSION',
          entityId: uid,
          summary: 'Đã ${value ? 'bật' : 'tắt'} quyền ${permissionKey.replaceAll('allowView', '').toLowerCase()}',
          payload: {'permissionKey': permissionKey, 'value': value},
        );

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Đã cập nhật quyền ${permissionKey.replaceAll('allowView', '').toLowerCase()}"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi cập nhật quyền: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _updateUserRole(String uid, String newRole) async {
    try {
      // Lấy thông tin user hiện tại
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};

      await UserService.updateUserInfo(
        uid: uid,
        name: userData['displayName'] ?? 'Unknown',
        phone: userData['phone'] ?? '',
        address: userData['address'] ?? '',
        role: newRole,
        loc: AppLocalizations.of(context)!,
      );

      // Nếu đổi thành owner/manager, tự động cấp full permissions
      if (newRole == 'owner' || newRole == 'manager') {
        await UserService.updateUserPermissions(
          uid: uid,
          allowViewSales: true,
          allowViewRepairs: true,
          allowViewInventory: true,
          allowViewParts: true,
          allowViewSuppliers: true,
          allowViewCustomers: true,
          allowViewWarranty: true,
          allowViewChat: true,
          allowViewAttendance: true,
          allowViewPrinter: true,
          allowViewRevenue: true,
          allowViewExpenses: true,
          allowViewDebts: true,
          allowViewCostPrice: true,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Đã cập nhật vai trò thành ${newRole == 'owner' ? 'Chủ shop' : newRole == 'manager' ? 'Quản lý' : newRole == 'employee' ? 'Nhân viên' : newRole == 'technician' ? 'Kỹ thuật' : newRole}"), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Lỗi cập nhật vai trò: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Kiểm tra quyền truy cập
    if (!_hasManageStaffAccess && !_isSuperAdmin) {
      return Scaffold(
        appBar: AppBar(
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text("QUẢN LÝ PHÂN QUYỀN"),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.admin_panel_settings, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                "Bạn không có quyền truy cập\nmàn hình quản lý phân quyền",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("QUẢN LÝ PHÂN QUYỀN NHÂN VIÊN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline3.fontSize)),
            if (_currentRole != null)
              Text("Role: $_currentRole", style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: Colors.white70)),
          ],
        ),
      ),
      body: ResponsiveCenter(child: StreamBuilder<QuerySnapshot>(
        stream: UserService.getAllUsersStream(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final users = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final shopId = data['shopId'];
            // Chỉ hiển thị nhân viên của shop hiện tại hoặc super admin
            return _isSuperAdmin || shopId == _currentShopId;
          }).toList();

          if (users.isEmpty) {
            return const Center(
              child: Text(
                "Chưa có nhân viên nào trong shop\nMời nhân viên qua mã QR trước",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: users.length,
            itemBuilder: (ctx, i) {
              final userData = users[i].data() as Map<String, dynamic>;
              final uid = users[i].id;
              final email = userData['email'] ?? "Chưa có email";
              final role = userData['role'] ?? 'user';
              final displayName = userData['displayName'] ?? email.split('@').first.toUpperCase();
              final phone = userData['phone'] ?? "Chưa có SĐT";
              final photoUrl = userData['photoUrl'];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ExpansionTile(
                  leading: CircleAvatar(
                    backgroundImage: _safeImageProvider(photoUrl),
                    backgroundColor: role == 'owner' ? Colors.indigo.withAlpha(25) : role == 'manager' ? Colors.orange.withAlpha(25) : role == 'employee' ? Colors.blue.withAlpha(25) : role == 'technician' ? Colors.green.withAlpha(25) : role == 'admin' ? Colors.red.withAlpha(25) : Colors.grey.withAlpha(25),
                    child: photoUrl == null ? Icon(role == 'owner' ? Icons.business : role == 'manager' ? Icons.supervisor_account : role == 'employee' ? Icons.work : role == 'technician' ? Icons.build : role == 'admin' ? Icons.admin_panel_settings : Icons.person, color: role == 'owner' ? Colors.indigo : role == 'manager' ? Colors.orange : role == 'employee' ? Colors.blue : role == 'technician' ? Colors.green : role == 'admin' ? Colors.red : Colors.grey, size: 20) : null,
                  ),
                  title: Text(displayName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline4.fontSize)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(email, style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey)),
                      Text("SĐT: $phone", style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey)),
                      Row(
                        children: [
                          Text("Vai trò: ", style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: role == 'owner' ? Colors.indigo : role == 'manager' ? Colors.orange : role == 'employee' ? Colors.blue : role == 'technician' ? Colors.green : role == 'admin' ? Colors.red : Colors.grey,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(role == 'owner' ? 'CHỦ SHOP' : role == 'manager' ? 'QUẢN LÝ' : role == 'employee' ? 'NHÂN VIÊN' : role == 'technician' ? 'KỸ THUẬT' : role == 'admin' ? 'ADMIN' : role, style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Đổi vai trò
                          Text("VAI TRÒ HỆ THỐNG", style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              _buildRoleChip('employee', 'NHÂN VIÊN', role, uid),
                              _buildRoleChip('technician', 'KỸ THUẬT', role, uid),
                              _buildRoleChip('manager', 'QUẢN LÝ', role, uid),
                              if (_isSuperAdmin) _buildRoleChip('owner', 'CHỦ SHOP', role, uid),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Phân quyền nghiệp vụ
                          if (role != 'owner' && role != 'manager') ...[
                            Text("QUYỀN XEM NỘI DUNG NGHIỆP VỤ", style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                            const SizedBox(height: 8),
                            _buildPermissionRow("BÁN HÀNG", userData['allowViewSales'] ?? false, uid, 'allowViewSales'),
                            _buildPermissionRow("SỬA CHỮA", userData['allowViewRepairs'] ?? false, uid, 'allowViewRepairs'),
                            _buildPermissionRow("KHO HÀNG", userData['allowViewInventory'] ?? false, uid, 'allowViewInventory'),
                            _buildPermissionRow("LINH KIỆN SỬA CHỮA", userData['allowViewParts'] ?? false, uid, 'allowViewParts'),
                            _buildPermissionRow("NHÀ CUNG CẤP", userData['allowViewSuppliers'] ?? false, uid, 'allowViewSuppliers'),
                            _buildPermissionRow("KHÁCH HÀNG", userData['allowViewCustomers'] ?? false, uid, 'allowViewCustomers'),
                            _buildPermissionRow("BẢO HÀNH", userData['allowViewWarranty'] ?? false, uid, 'allowViewWarranty'),
                            _buildPermissionRow("CHAT NỘI BỘ", userData['allowViewChat'] ?? false, uid, 'allowViewChat'),
                            _buildPermissionRow("CHẤM CÔNG", userData['allowViewAttendance'] ?? false, uid, 'allowViewAttendance'),
                            _buildPermissionRow("CẤU HÌNH MÁY IN", userData['allowViewPrinter'] ?? false, uid, 'allowViewPrinter'),
                            const SizedBox(height: 15),

                            // Phân quyền tài chính nhạy cảm
                            Text("QUYỀN XEM NỘI DUNG TÀI CHÍNH", style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, fontWeight: FontWeight.bold, color: Colors.orange)),
                            const SizedBox(height: 8),
                            _buildPermissionRow("DOANH THU & LỜI LỖ", userData['allowViewRevenue'] ?? false, uid, 'allowViewRevenue'),
                            _buildPermissionRow("CHI PHÍ CỬA HÀNG", userData['allowViewExpenses'] ?? false, uid, 'allowViewExpenses'),
                            _buildPermissionRow("SỔ CÔNG NỢ", userData['allowViewDebts'] ?? false, uid, 'allowViewDebts'),
                            _buildPermissionRow("GIÁ VỐN SẢN PHẨM", userData['allowViewCostPrice'] ?? false, uid, 'allowViewCostPrice'),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green.shade200),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.verified, color: Colors.green, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      role == 'owner' ? "CHỦ SHOP có toàn quyền truy cập mọi chức năng trong hệ thống" : "QUẢN LÝ có toàn quyền truy cập mọi chức năng trong hệ thống",
                                      style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.green, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      )),
    );
  }

  Widget _buildRoleChip(String roleValue, String roleLabel, String currentRole, String uid) {
    final isSelected = currentRole == roleValue;
    return FilterChip(
      label: Text(roleLabel, style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: isSelected ? Colors.white : Colors.black87)),
      selected: isSelected,
      onSelected: (selected) {
        if (selected && currentRole != roleValue) {
          _updateUserRole(uid, roleValue);
        }
      },
      backgroundColor: Colors.grey.shade100,
      selectedColor: roleValue == 'owner' ? Colors.indigo : roleValue == 'manager' ? Colors.orange : roleValue == 'employee' ? Colors.blue : roleValue == 'technician' ? Colors.green : Colors.grey,
      checkmarkColor: Colors.white,
    );
  }

  Widget _buildPermissionRow(String label, bool value, String uid, String permissionKey) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize)),
          ),
          Switch(
            value: value,
            onChanged: (newValue) => _updateUserPermission(uid, permissionKey, newValue),
            activeThumbColor: Colors.blue,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}
