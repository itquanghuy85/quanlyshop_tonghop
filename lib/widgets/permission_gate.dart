import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// Maps a permission key to a human-readable Vietnamese label.
const _permissionLabels = <String, String>{
  'allowViewSales': 'Bán hàng',
  'allowViewRepairs': 'Sửa chữa',
  'allowViewInventory': 'Kho hàng',
  'allowViewParts': 'Linh kiện',
  'allowViewSuppliers': 'Nhà cung cấp',
  'allowViewCustomers': 'Khách hàng',
  'allowViewWarranty': 'Bảo hành',
  'allowViewChat': 'Trò chuyện',
  'allowViewAttendance': 'Chấm công',
  'allowViewPrinter': 'Máy in',
  'allowViewRevenue': 'Doanh thu / Tài chính',
  'allowViewExpenses': 'Chi phí',
  'allowViewDebts': 'Công nợ',
  'allowViewCostPrice': 'Giá vốn',
  'allowManageStaff': 'Nhân viên',
};

/// Wraps any child widget with a runtime permission check.
///
/// - If [requiredPermission] is null, always shows [child].
/// - If the current user has the permission (or is owner/admin/superAdmin),
///   shows [child].
/// - Otherwise shows a "no access" screen with a back button.
///
/// Usage:
/// ```dart
/// PermissionGate(
///   requiredPermission: 'allowViewInventory',
///   child: const SmartStockInView(),
/// )
/// ```
class PermissionGate extends StatelessWidget {
  final String? requiredPermission;
  final Widget child;

  const PermissionGate({
    super.key,
    required this.requiredPermission,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (requiredPermission == null) return child;
    if (_hasAccess()) return child;
    return _NoAccessScreen(featureName: _permissionLabels[requiredPermission] ?? requiredPermission!);
  }

  bool _hasAccess() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    // Super admin always has access
    if (user.email == 'admin@huluca.com') return true;

    final perms = UserService.getCurrentUserPermissionsSync();
    if (perms == null) {
      // Permissions not loaded yet — allow access (will be checked on next load)
      return true;
    }

    return perms[requiredPermission] == true;
  }
}

/// Static helper for imperative permission checks before navigation.
///
/// Returns true if the user has the given permission.
/// If not, shows a snackbar and returns false.
///
/// Usage:
/// ```dart
/// if (!PermissionGate.check(context, 'allowViewInventory')) return;
/// Navigator.push(context, ...);
/// ```
extension PermissionGateCheck on PermissionGate {
  static bool check(BuildContext context, String? permission) {
    if (permission == null) return true;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    if (user.email == 'admin@huluca.com') return true;

    final perms = UserService.getCurrentUserPermissionsSync();
    if (perms == null) return true; // Not loaded yet — allow

    if (perms[permission] == true) return true;

    // Permission denied — show snackbar
    final label = _permissionLabels[permission] ?? permission;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Bạn không có quyền truy cập "$label".\nLiên hệ Chủ shop để được cấp quyền.'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
    return false;
  }
}

class _NoAccessScreen extends StatelessWidget {
  final String featureName;
  const _NoAccessScreen({required this.featureName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(featureName),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(25),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_person,
                  size: 80,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Không có quyền truy cập',
                style: AppTextStyles.headline3.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Bạn không có quyền truy cập tính năng "$featureName".\n'
                'Vui lòng liên hệ Chủ shop để được cấp quyền.',
                style: AppTextStyles.subtitle1.copyWith(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('QUAY LẠI'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
