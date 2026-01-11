import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_service.dart';
import '../services/claims_service.dart';

String getRoleDisplayName(String role) {
  switch (role) {
    case 'owner':
      return 'Chủ shop';
    case 'manager':
      return 'Quản lý';
    case 'employee':
      return 'Nhân viên';
    case 'technician':
      return 'Kỹ thuật';
    case 'admin':
      return 'Admin';
    case 'user':
      return 'Người dùng';
    default:
      return role;
  }
}

class SuperAdminView extends StatelessWidget {
  const SuperAdminView({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFF),
        appBar: AppBar(
          title: const Text(
            'SUPER ADMIN CONTROL',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'SHOPS'),
              Tab(text: 'USERS'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            ShopsTab(),
            UsersTab(),
          ],
        ),
      ),
    );
  }
}

class ShopsTab extends StatefulWidget {
  const ShopsTab({super.key});

  @override
  State<ShopsTab> createState() => _ShopsTabState();
}

class _ShopsTabState extends State<ShopsTab> {
  bool _isSyncingClaims = false;

  Future<void> _syncAllClaims() async {
    setState(() => _isSyncingClaims = true);
    
    try {
      final result = await ClaimsService().batchSyncAllClaims();
      
      if (!mounted) return;
      
      if (result['success'] == true) {
        // Safely cast stats map
        final statsRaw = result['stats'];
        final stats = statsRaw is Map ? Map<String, dynamic>.from(statsRaw) : <String, dynamic>{};
        final total = stats['total'] ?? 0;
        final success = stats['success'] ?? 0;
        final skipped = stats['skipped'] ?? 0;
        final failed = stats['failed'] ?? 0;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Đồng bộ hoàn tất!\n'
              'Tổng: $total | Thành công: $success | Bỏ qua: $skipped | Lỗi: $failed',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi: ${result['error'] ?? 'Không xác định'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingClaims = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: UserService.getAllShopsStreamForSuperAdmin(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'Chưa có shop nào được tạo',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final shops = snapshot.data!.docs;
        return ListView(
          padding: const EdgeInsets.all(15),
          children: [
            _buildIntroCard(context),
            const SizedBox(height: 12),
            _buildClaimsSyncCard(),
            const SizedBox(height: 12),
            _buildStatsCard(shops.length),
            const SizedBox(height: 12),
            ...shops.map((doc) {
              final data = doc.data() as Map<String, dynamic>;
              final shopId = doc.id;
              final shopName = data['name'] ?? 'Shop chưa đặt tên';
              final ownerEmail = data['ownerEmail'] ?? 'Không rõ email chủ shop';
              final ownerUid = data['ownerUid'] ?? 'Không rõ UID chủ shop';
              final createdAt = data['createdAt'];
              final appLocked = data['appLocked'] == true;
              final adminFinanceLocked = data['adminFinanceLocked'] == true;
              final staffSalesLocked = data['staffSalesLocked'] == true;
              final staffInventoryLocked = data['staffInventoryLocked'] == true;
              final staffDebtLocked = data['staffDebtLocked'] == true;
              final staffSettingsLocked = data['staffSettingsLocked'] == true;

              String createdText = 'Chưa rõ ngày tạo';
              if (createdAt is Timestamp) {
                createdText = 'Tạo: ${createdAt.toDate().toString().substring(0, 16)}';
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: ExpansionTile(
                  leading: Icon(
                    appLocked ? Icons.lock : Icons.store_mall_directory,
                    color: appLocked ? Colors.red : Colors.blueAccent,
                  ),
                  title: Text(
                    shopName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: appLocked ? Colors.red : Colors.black87,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ID: $shopId', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(ownerEmail, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Owner UID: $ownerUid', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          Text(createdText, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          const Divider(height: 20),
                          const Text('🔐 ĐIỀU KHIỂN SUPER ADMIN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                          const SizedBox(height: 8),
                          _buildLockSwitch(
                            context: context,
                            title: '🚫 KHÓA TOÀN BỘ APP',
                            subtitle: 'Mọi tài khoản của shop không truy cập được app.',
                            value: appLocked,
                            onChanged: (v) => _updateFlag(context, shopId, 'appLocked', v, 'toàn bộ app'),
                            isDestructive: true,
                          ),
                          _buildLockSwitch(
                            context: context,
                            title: '💰 KHÓA TÀI CHÍNH CHO QUẢN LÝ',
                            subtitle: 'Quản lý không xem được doanh thu, chi phí, công nợ.',
                            value: adminFinanceLocked,
                            onChanged: (v) => _updateFlag(context, shopId, 'adminFinanceLocked', v, 'tài chính quản lý'),
                          ),
                          const Divider(height: 20),
                          const Text('👷 KHÓA CHỨC NĂNG CHO NHÂN VIÊN', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange)),
                          const SizedBox(height: 8),
                          _buildLockSwitch(
                            context: context,
                            title: '🛒 KHÓA XEM BÁN HÀNG',
                            subtitle: 'Nhân viên không xem được danh sách bán hàng.',
                            value: staffSalesLocked,
                            onChanged: (v) => _updateFlag(context, shopId, 'staffSalesLocked', v, 'bán hàng nhân viên'),
                          ),
                          _buildLockSwitch(
                            context: context,
                            title: '📦 KHÓA XEM KHO',
                            subtitle: 'Nhân viên không xem được kho hàng.',
                            value: staffInventoryLocked,
                            onChanged: (v) => _updateFlag(context, shopId, 'staffInventoryLocked', v, 'kho nhân viên'),
                          ),
                          _buildLockSwitch(
                            context: context,
                            title: '📋 KHÓA XEM CÔNG NỢ',
                            subtitle: 'Nhân viên không xem được sổ công nợ.',
                            value: staffDebtLocked,
                            onChanged: (v) => _updateFlag(context, shopId, 'staffDebtLocked', v, 'công nợ nhân viên'),
                          ),
                          _buildLockSwitch(
                            context: context,
                            title: '⚙️ KHÓA CÀI ĐẶT',
                            subtitle: 'Nhân viên & Quản lý không vào được trang Cài đặt.',
                            value: staffSettingsLocked,
                            onChanged: (v) => _updateFlag(context, shopId, 'staffSettingsLocked', v, 'cài đặt'),
                          ),
                          const Divider(height: 20),
                          const Text('👥 THÀNH VIÊN TRONG SHOP', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal)),
                          const SizedBox(height: 8),
                          _buildShopMembersList(shopId),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildShopMembersList(String shopId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('shopId', isEqualTo: shopId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Không có thành viên', style: TextStyle(color: Colors.grey, fontSize: 12)),
          );
        }

        final members = snapshot.data!.docs;
        return Column(
          children: members.map((doc) {
            final userData = doc.data() as Map<String, dynamic>;
            final email = userData['email'] ?? 'Không có email';
            final displayName = userData['displayName'] ?? '';
            final role = userData['role'] ?? 'user';
            final phone = userData['phone'] ?? '';
            
            // Map role to Vietnamese
            String roleText;
            Color roleColor;
            IconData roleIcon;
            switch (role) {
              case 'owner':
                roleText = 'Chủ shop';
                roleColor = Colors.purple;
                roleIcon = Icons.star;
                break;
              case 'manager':
                roleText = 'Quản lý';
                roleColor = Colors.blue;
                roleIcon = Icons.manage_accounts;
                break;
              case 'employee':
                roleText = 'Nhân viên';
                roleColor = Colors.green;
                roleIcon = Icons.person;
                break;
              case 'technician':
                roleText = 'Kỹ thuật';
                roleColor = Colors.orange;
                roleIcon = Icons.build;
                break;
              case 'admin':
                roleText = 'Admin';
                roleColor = Colors.red;
                roleIcon = Icons.admin_panel_settings;
                break;
              default:
                roleText = 'Người dùng';
                roleColor = Colors.grey;
                roleIcon = Icons.person_outline;
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: roleColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: roleColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: roleColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(roleIcon, color: roleColor, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName.isNotEmpty ? displayName : email,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (displayName.isNotEmpty)
                          Text(email, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        if (phone.isNotEmpty)
                          Text('📞 $phone', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: roleColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      roleText,
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildStatsCard(int totalShops) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.analytics, color: Colors.blue, size: 32),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Tổng số Shop', style: TextStyle(fontSize: 12, color: Colors.grey)),
                Text('$totalShops', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLockSwitch({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
    bool isDestructive = false,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDestructive && value ? Colors.red : Colors.black87,
        ),
      ),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      value: value,
      activeThumbColor: isDestructive ? Colors.red : Colors.blue,
      onChanged: onChanged,
    );
  }

  Future<void> _updateFlag(BuildContext context, String shopId, String flag, bool value, String featureName) async {
    final messenger = ScaffoldMessenger.of(context);
    await UserService.updateShopControlFlags(shopId: shopId, flagName: flag, flagValue: value);
    messenger.showSnackBar(
      SnackBar(
        content: Text(value ? 'ĐÃ KHÓA $featureName cho shop $shopId' : 'ĐÃ MỞ KHÓA $featureName cho shop $shopId'),
        backgroundColor: value ? Colors.orange : Colors.green,
      ),
    );
  }

  Widget _buildIntroCard(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blueAccent),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Giới thiệu ứng dụng',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Text(
              'Ứng dụng quản lý sửa chữa điện thoại HULUCA giúp cửa hàng theo dõi đơn sửa chữa, khách hàng, thu chi và tồn kho một cách đơn giản, có hỗ trợ làm việc cả khi offline và đồng bộ dữ liệu với Firebase.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            SizedBox(height: 8),
            Text(
              'Ứng dụng được xây dựng và vận hành bởi HULUCA (admin@huluca.com) với mục tiêu hỗ trợ các cửa hàng sửa chữa điện thoại vừa và nhỏ quản lý công việc hiệu quả, minh bạch và chuyên nghiệp hơn.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClaimsSyncCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: Colors.deepPurple.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.sync, color: Colors.deepPurple),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Đồng bộ Custom Claims',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Sau khi thay đổi Firestore Rules để sử dụng Custom Claims, bạn cần đồng bộ claims cho TẤT CẢ user để họ có thể truy cập được dữ liệu.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSyncingClaims ? null : _syncAllClaims,
                icon: _isSyncingClaims 
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_sync),
                label: Text(_isSyncingClaims ? 'Đang đồng bộ...' : 'ĐỒNG BỘ TẤT CẢ CLAIMS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UsersTab extends StatelessWidget {
  const UsersTab({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: UserService.getAllUsersStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              'Chưa có user nào',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        final users = snapshot.data!.docs;
        return ListView(
          padding: const EdgeInsets.all(15),
          children: users.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final uid = doc.id;
            final email = data['email'] ?? 'Không rõ email';
            final displayName = data['displayName'] ?? 'Không rõ tên';
            final phone = data['phone'] ?? 'Không rõ số điện thoại';
            final address = data['address'] ?? 'Không rõ địa chỉ';
            final role = data['role'] ?? 'user';
            final shopId = data['shopId'] ?? 'Không có shop';

            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              child: Padding(
                padding: const EdgeInsets.all(15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.person, color: Colors.blueAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            email,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.orange),
                          onPressed: () => _showEditUserDialog(context, uid, data),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _showDeleteUserDialog(context, uid, email),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('Tên: $displayName', style: const TextStyle(fontSize: 12)),
                    Text('SĐT: $phone', style: const TextStyle(fontSize: 12)),
                    Text('Địa chỉ: $address', style: const TextStyle(fontSize: 12)),
                    Text('Vai trò: ${getRoleDisplayName(role)}', style: const TextStyle(fontSize: 12)),
                    Text('Shop ID: $shopId', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  void _showEditUserDialog(BuildContext context, String uid, Map<String, dynamic> data) {
    final nameController = TextEditingController(text: data['displayName'] ?? '');
    final phoneController = TextEditingController(text: data['phone'] ?? '');
    final addressController = TextEditingController(text: data['address'] ?? '');
    final roleController = TextEditingController(text: data['role'] ?? 'user');
    final shopIdController = TextEditingController(text: data['shopId'] ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chỉnh sửa thông tin user'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Tên'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Số điện thoại'),
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Địa chỉ'),
              ),
              TextField(
                controller: roleController,
                decoration: const InputDecoration(labelText: 'Vai trò'),
              ),
              TextField(
                controller: shopIdController,
                decoration: const InputDecoration(labelText: 'Shop ID'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              try {
                await UserService.updateUserInfo(
                  uid: uid,
                  name: nameController.text,
                  phone: phoneController.text,
                  address: addressController.text,
                  role: roleController.text,
                  shopId: shopIdController.text.isEmpty ? null : shopIdController.text,
                );
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Đã cập nhật thông tin user')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Lỗi: $e')),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _showDeleteUserDialog(BuildContext context, String uid, String email) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa user'),
        content: Text('Bạn có chắc muốn xóa user $email? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              await UserService.deleteUser(uid);
              navigator.pop();
              messenger.showSnackBar(
                SnackBar(content: Text('Đã xóa user $email')),
              );
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}
