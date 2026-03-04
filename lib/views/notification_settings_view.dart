import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../theme/app_text_styles.dart';

class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key});

  @override
  State<NotificationSettingsView> createState() => _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<NotificationSettingsView> {
  bool _newOrderEnabled = true;
  bool _paymentEnabled = true;
  bool _inventoryEnabled = false;
  bool _staffEnabled = false;
  bool _systemEnabled = true;

  String _userRole = 'user';
  bool _permissionGranted = false;
  bool _hasFcmToken = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _loadUserRole();
    _checkPermissionStatus();
  }

  Future<void> _loadSettings() async {
    final newOrder = await NotificationService.getNotificationEnabled('new_order');
    final payment = await NotificationService.getNotificationEnabled('payment');
    final inventory = await NotificationService.getNotificationEnabled('inventory');
    final staff = await NotificationService.getNotificationEnabled('staff');
    final system = await NotificationService.getNotificationEnabled('system');

    if (mounted) {
      setState(() {
        _newOrderEnabled = newOrder;
        _paymentEnabled = payment;
        _inventoryEnabled = inventory;
        _staffEnabled = staff;
        _systemEnabled = system;
      });
    }
  }

  Future<void> _loadUserRole() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final role = await UserService.getUserRole(user.uid);
        if (mounted) {
          setState(() {
            _userRole = role;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading user role: $e');
    }
  }

  Future<void> _checkPermissionStatus() async {
    // Use dual-check method: permission_handler + Firebase Messaging
    // This avoids false-negative on iOS where permission_handler
    // reports 'permanentlyDenied' even though iOS Settings has notifications ON
    final status = await NotificationService.checkNotificationStatus();
    if (mounted) {
      setState(() {
        _permissionGranted = status['permissionGranted'] ?? false;
        _hasFcmToken = status['hasFcmToken'] ?? false;
      });
    }
  }

  Future<void> _updateSetting(String type, bool value) async {
    await NotificationService.setNotificationEnabled(type, value);
    setState(() {
      switch (type) {
        case 'new_order':
          _newOrderEnabled = value;
          break;
        case 'payment':
          _paymentEnabled = value;
          break;
        case 'inventory':
          _inventoryEnabled = value;
          break;
        case 'staff':
          _staffEnabled = value;
          break;
        case 'system':
          _systemEnabled = value;
          break;
      }
    });

    NotificationService.showSnackBar(
      value ? 'Đã bật thông báo' : 'Đã tắt thông báo',
      color: value ? Colors.green : Colors.orange,
    );
  }

  @override
  Widget build(BuildContext context) {
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
        title: Text(
          "CÀI ĐẶT THÔNG BÁO",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline3.fontSize, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Permission Status Section
          _buildPermissionStatusCard(),
          const SizedBox(height: 24),

          // Role Information
          _buildRoleInfoCard(),
          const SizedBox(height: 24),

          _buildSectionHeader('THÔNG BÁO QUAN TRỌNG'),
          _buildNotificationTile(
            'Đơn hàng mới',
            'Thông báo khi có khách hàng tạo đơn hàng mới',
            _newOrderEnabled,
            (value) => _updateSetting('new_order', value),
            Icons.shopping_cart,
            Colors.blue,
            enabled: _isRoleAllowed('new_order'),
          ),
          _buildNotificationTile(
            'Thanh toán',
            'Thông báo khi có thanh toán thành công',
            _paymentEnabled,
            (value) => _updateSetting('payment', value),
            Icons.payment,
            Colors.green,
            enabled: _isRoleAllowed('payment'),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('THÔNG BÁO KHÁC'),
          _buildNotificationTile(
            'Kho hàng',
            'Cảnh báo khi sản phẩm sắp hết hàng',
            _inventoryEnabled,
            (value) => _updateSetting('inventory', value),
            Icons.inventory,
            Colors.orange,
            enabled: _isRoleAllowed('inventory'),
          ),
          _buildNotificationTile(
            'Nhân viên',
            'Thông báo về hoạt động của nhân viên',
            _staffEnabled,
            (value) => _updateSetting('staff', value),
            Icons.people,
            Colors.blue,
            enabled: _isRoleAllowed('staff'),
          ),
          _buildNotificationTile(
            'Hệ thống',
            'Thông báo cập nhật và bảo trì hệ thống',
            _systemEnabled,
            (value) => _updateSetting('system', value),
            Icons.settings,
            Colors.grey,
            enabled: _isRoleAllowed('system'),
          ),

          const SizedBox(height: 32),
          _buildRefreshTokenButton(),
          const SizedBox(height: 16),
          _buildTestNotificationButton(),
          _buildInfoCard(),
        ],
      ),
    );
  }

  Widget _buildPermissionStatusCard() {
    final isFullyWorking = _permissionGranted && _hasFcmToken;

    return Card(
      color: isFullyWorking ? Colors.green.shade50 : Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isFullyWorking ? Icons.notifications_active : Icons.notifications_off,
                  color: isFullyWorking ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Quyền thông báo',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isFullyWorking ? Colors.green : Colors.orange,
                    ),
                  ),
                ),
                // Status badges
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _permissionGranted ? Colors.green.shade100 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _permissionGranted ? 'Quyền OK' : 'Chưa cấp quyền',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                      color: _permissionGranted ? Colors.green.shade800 : Colors.red.shade800),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _hasFcmToken ? Colors.green.shade100 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _hasFcmToken ? 'Token OK' : 'Chưa có token',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                      color: _hasFcmToken ? Colors.green.shade800 : Colors.red.shade800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isFullyWorking
                ? 'Đã cấp quyền thông báo. Bạn sẽ nhận được thông báo push.'
                : !_permissionGranted
                  ? 'Cần cấp quyền thông báo để nhận thông báo push.${Platform.isIOS ? "\nNếu đã bật trong Cài đặt iOS, hãy nhấn \"Làm mới FCM Token\"." : ""}'
                  : 'Đã cấp quyền nhưng chưa có FCM Token. Nhấn "Làm mới FCM Token" bên dưới.',
              style: TextStyle(
                fontSize: AppTextStyles.subtitle1.fontSize,
                color: isFullyWorking ? Colors.green.shade700 : Colors.orange.shade700,
              ),
            ),
            if (!_permissionGranted) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _requestNotificationPermission,
                  icon: const Icon(Icons.settings),
                  label: const Text('Cấp quyền'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRoleInfoCard() {
    final roleDisplayName = _getRoleDisplayName(_userRole);

    return Card(
      color: Colors.blue.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  'Vai trò của bạn: $roleDisplayName',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Một số loại thông báo chỉ dành cho vai trò nhất định để đảm bảo bảo mật và tránh spam.',
              style: TextStyle(
                fontSize: AppTextStyles.subtitle1.fontSize,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: AppTextStyles.subtitle1.fontSize,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildNotificationTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
    IconData icon,
    Color color, {
    bool enabled = true,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: enabled ? null : Colors.grey.shade100,
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: enabled ? color.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: enabled ? color : Colors.grey),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: AppTextStyles.headline3.fontSize,
            color: enabled ? null : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              subtitle,
              style: TextStyle(
                fontSize: AppTextStyles.subtitle1.fontSize,
                color: enabled ? Colors.grey : Colors.grey.shade600,
              ),
            ),
            if (!enabled) ...[
              const SizedBox(height: 4),
              Text(
                'Không khả dụng cho vai trò hiện tại',
                style: TextStyle(
                  fontSize: AppTextStyles.caption.fontSize,
                  color: Colors.red.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
        trailing: Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeThumbColor: color,
        ),
      ),
    );
  }

  Widget _buildRefreshTokenButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton.icon(
        onPressed: _refreshFCMToken,
        icon: const Icon(Icons.refresh),
        label: const Text('LÀM MỚI FCM TOKEN'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildTestNotificationButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ElevatedButton.icon(
        onPressed: _sendTestNotification,
        icon: const Icon(Icons.notifications_active),
        label: const Text('GỬI THÔNG BÁO TEST'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Future<void> _requestNotificationPermission() async {
    // On iOS, try opening system settings directly since permission_handler
    // often reports wrong status. The user can enable notifications there.
    if (Platform.isIOS) {
      _showPermissionSettingsDialog();
      return;
    }

    final status = await Permission.notification.request();
    // Recheck using dual method
    await _checkPermissionStatus();

    if (status.isGranted || _permissionGranted) {
      NotificationService.showSnackBar('Đã cấp quyền thông báo!', color: Colors.green);
      // Also refresh FCM token after granting permission
      await NotificationService.forceRefreshFCMToken();
      await _checkPermissionStatus();
    } else if (status.isPermanentlyDenied) {
      _showPermissionSettingsDialog();
    } else {
      NotificationService.showSnackBar('Cần cấp quyền để nhận thông báo', color: Colors.orange);
    }
  }

  Future<void> _showPermissionSettingsDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cấp quyền thông báo'),
        content: const Text(
          'Ứng dụng cần quyền thông báo để gửi thông báo quan trọng. '
          'Vui lòng bật quyền trong cài đặt hệ thống.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mở cài đặt'),
          ),
        ],
      ),
    );

    if (result == true) {
      final opened = await NotificationService.openNotificationSettings();
      if (opened) {
        // Refresh permission status after returning from settings
        Future.delayed(const Duration(seconds: 1), _checkPermissionStatus);
      }
    }
  }

  bool _isRoleAllowed(String notificationType) {
    // Define role-based permissions
    final rolePermissions = {
      'new_order': ['admin', 'owner', 'manager', 'employee'],
      'payment': ['admin', 'owner', 'manager', 'employee'],
      'inventory': ['admin', 'owner', 'manager', 'technician'],
      'staff': ['admin', 'owner', 'manager'],
      'system': ['admin', 'owner', 'manager', 'employee', 'technician', 'user'],
    };

    final allowedRoles = rolePermissions[notificationType] ?? [];
    return allowedRoles.contains(_userRole) || UserService.isCurrentUserSuperAdmin();
  }

  Future<void> _sendTestNotification() async {
    try {
      await NotificationService.sendSystemNotification(
        'Đây là thông báo test từ hệ thống push notification. Nếu bạn thấy thông báo này, hệ thống đang hoạt động bình thường!'
      );
      NotificationService.showSnackBar(
        'Đã gửi thông báo test!',
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar(
        'Lỗi gửi thông báo: $e',
        color: Colors.red,
      );
    }
  }

  Future<void> _refreshFCMToken() async {
    // Hiển thị loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Đang làm mới FCM token...'),
            ],
          ),
        ),
      ),
    );

    try {
      final success = await NotificationService.forceRefreshFCMToken();
      if (mounted) Navigator.of(context).pop(); // Đóng loading

      if (success) {
        NotificationService.showSnackBar(
          '✅ Đã làm mới FCM token thành công!',
          color: Colors.green,
        );
        // Reload permission status
        await _checkPermissionStatus();
      } else {
        NotificationService.showSnackBar(
          '❌ Không thể làm mới FCM token. Thử lại sau.',
          color: Colors.red,
        );
      }
    } catch (e) {
      if (mounted) Navigator.of(context).pop(); // Đóng loading
      NotificationService.showSnackBar(
        'Lỗi làm mới token: $e',
        color: Colors.red,
      );
    }
  }

  Widget _buildInfoCard() {
    return Card(
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'THÔNG TIN THÔNG BÁO',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '• Thông báo được gửi dựa trên vai trò của bạn\n'
              '• Admin & Owner nhận tất cả thông báo\n'
              '• Manager & Technician nhận thông báo quan trọng\n'
              '• Employee chỉ nhận thông báo cá nhân',
              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.grey.shade700),
            ),
          ],
        ),
      ),
    );
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
      default:
        return role.toUpperCase();
    }
  }
}
