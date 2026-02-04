import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../services/user_service.dart';
import '../data/db_helper.dart';
import '../services/storage_service.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../widgets/gradient_fab.dart';
import 'repair_detail_view.dart';
import 'sale_detail_view.dart';
import '../core/utils/money_utils.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';

ImageProvider? _safeImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;
  if (path.startsWith('http')) return NetworkImage(path);
  final file = File(path);
  return file.existsSync() ? FileImage(file) : null;
}

class StaffListView extends StatefulWidget {
  const StaffListView({super.key});

  @override
  State<StaffListView> createState() => _StaffListViewState();
}

class _StaffListViewState extends State<StaffListView> {
  final db = DBHelper();
  String? _currentRole;
  String? _currentShopId;
  bool _isSuperAdmin = false;
  bool _loadingRole = true;
  bool _hasManageStaffAccess = false;

  // Invite code QR
  String? _currentInviteCode;
  String? _currentShopName;
  bool _generatingInvite = false;

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

    // Load current invite code if owner
    if (role == 'owner' && shopId != null) {
      _loadCurrentInviteCode();
    }
    // Load shop name for all roles (owner, manager, employee, technician)
    if (shopId != null) {
      _loadShopName();
    }
  }

  Future<void> _loadShopName() async {
    if (_currentShopId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(_currentShopId)
          .get();

      if (doc.exists) {
        final data = doc.data();
        setState(() => _currentShopName = data?['name'] ?? 'Shop không tên');
      } else {
        setState(() => _currentShopName = 'Shop không tên');
      }
    } catch (e) {
      setState(() => _currentShopName = 'Shop không tên');
    }
  }

  Future<void> _loadCurrentInviteCode() async {
    if (_currentShopId == null) return;

    try {
      final query = await FirebaseFirestore.instance
          .collection('invites')
          .where('shopId', isEqualTo: _currentShopId)
          .where('used', isEqualTo: false)
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final inviteData = query.docs.first.data();
        final expiresAt = DateTime.tryParse(inviteData['expiresAt']);
        if (expiresAt != null && expiresAt.isAfter(DateTime.now())) {
          setState(() => _currentInviteCode = query.docs.first.id);
        }
      }
    } catch (e) {
      // Ignore errors when loading current invite code
    }
  }

  bool get _canManageStaff =>
      _isSuperAdmin || _currentRole == 'owner' || _currentRole == 'manager';

  Future<void> _generateInviteCode() async {
    final messenger = ScaffoldMessenger.of(context);
    if (_currentShopId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Không tìm thấy thông tin shop')),
      );
      return;
    }

    setState(() => _generatingInvite = true);
    try {
      final code = await UserService.createInviteCode(_currentShopId!);
      setState(() => _currentInviteCode = code);
      messenger.showSnackBar(
        const SnackBar(content: Text('Đã tạo mã mời mới!')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi tạo mã mời: $e')));
    } finally {
      if (mounted) setState(() => _generatingInvite = false);
    }
  }

  void _showInviteQRDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('MÃ MỜI THAM GIA SHOP'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_currentInviteCode != null) ...[
                Text(
                  'Quét mã QR hoặc nhập mã bên dưới để tham gia shop:',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body1,
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: QrImageView(
                    data: _currentInviteCode != null && _currentShopName != null
                        ? '{"type":"invite_code","code":"$_currentInviteCode","shopName":"$_currentShopName"}'
                        : _currentInviteCode ?? '',
                    size: 200,
                    backgroundColor: AppColors.surface,
                  ),
                ),
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.primaryLight),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentInviteCode!,
                          style: AppTextStyles.headline4.copyWith(
                            color: AppColors.primary,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: AppColors.primary),
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await Clipboard.setData(
                            ClipboardData(text: _currentInviteCode!),
                          );
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Đã sao chép mã mời vào clipboard'),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Mã có hiệu lực trong 7 ngày',
                  style: AppTextStyles.caption,
                ),
              ] else ...[
                const Text(
                  'Chưa có mã mời nào được tạo',
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ĐÓNG'),
          ),
          ElevatedButton.icon(
            onPressed: _generatingInvite ? null : _generateInviteCode,
            icon: _generatingInvite
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(_generatingInvite ? 'ĐANG TẠO...' : 'TẠO MÃ MỚI'),
          ),
        ],
      ),
    );
  }

  void _openCreateStaffDialog() {
    final emailC = TextEditingController();
    final passC = TextEditingController();
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final addressC = TextEditingController();
    final shopC = TextEditingController(text: _currentShopId ?? "");

    showDialog(
      context: context,
      builder: (ctx) {
        String role = 'employee'; // Default to employee instead of user
        String? errorText;
        bool submitting = false;
        bool autoGeneratePassword =
            false; // Changed to false to allow manual password entry

        // Auto-generate strong password
        String generatePassword() {
          const chars =
              'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#\$%^&*';
          final random = DateTime.now().millisecondsSinceEpoch.toString();
          String password = '';
          for (int i = 0; i < 10; i++) {
            password +=
                chars[random.codeUnitAt(i % random.length) % chars.length];
          }
          return password;
        }

        Future<void> submit() async {
          if (submitting) return;
          final email = emailC.text.trim();
          final password = autoGeneratePassword
              ? generatePassword()
              : passC.text.trim();
          final displayName = nameC.text.trim();
          if (email.isEmpty ||
              (!autoGeneratePassword && password.length < 6) ||
              displayName.isEmpty) {
            setState(
              () => errorText = autoGeneratePassword
                  ? 'Nhập email và họ tên'
                  : 'Nhập email, mật khẩu >= 6 ký tự và họ tên',
            );
            return;
          }

          if (_isSuperAdmin && shopC.text.trim().isEmpty) {
            setState(
              () => errorText = 'Nhập shopId khi tạo từ tài khoản super admin',
            );
            return;
          }

          setState(() {
            submitting = true;
            errorText = null;
          });

          final messenger = ScaffoldMessenger.of(context);
          final navigator = Navigator.of(ctx);

          try {
            final callable = FirebaseFunctions.instanceFor(
              region: 'asia-southeast1',
            ).httpsCallable('createStaffAccount');
            final payload = {
              'email': email,
              'password': password,
              'displayName': displayName,
              'phone': phoneC.text.trim(),
              'address': addressC.text.trim(),
              'role': role,
              'autoGeneratedPassword': autoGeneratePassword,
            };
            // Always include shopId for owner accounts
            if (_isSuperAdmin) {
              payload['shopId'] = shopC.text.trim();
            } else if (_currentRole == 'owner' && _currentShopId != null) {
              payload['shopId'] = _currentShopId!;
            }

            debugPrint('Creating staff account with payload: $payload');
            final result = await callable.call(payload);
            debugPrint('Firebase Functions result: $result');
            final resultData = result.data;
            final createdShop =
                resultData is Map && resultData['shopId'] != null
                ? resultData['shopId']
                : (_currentShopId ?? '');
            if (!mounted) return;
            navigator.pop();

            // Show generated password if auto-generated
            final passwordMessage = autoGeneratePassword
                ? '\nMật khẩu tạm thời: $password\nKhuyến nghị đổi mật khẩu sau khi đăng nhập!'
                : '';

            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Đã tạo tài khoản nhân viên cho ${displayName.toUpperCase()} (shop: $createdShop)$passwordMessage',
                ),
                duration: const Duration(seconds: 8),
              ),
            );
          } on FirebaseFunctionsException catch (e) {
            debugPrint('Firebase Functions error: ${e.code} - ${e.message}');
            setState(
              () => errorText =
                  'Lỗi Firebase: ${e.message ?? 'Không thể tạo tài khoản'}',
            );
          } catch (e) {
            debugPrint('General error: $e');
            setState(() => errorText = 'Lỗi: $e');
          } finally {
            setState(() => submitting = false);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setState) {
            return AlertDialog(
              title: const Text('TẠO TÀI KHOẢN NHÂN VIÊN'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: emailC,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email đăng nhập',
                      ),
                    ),
                    // Auto-generate password option
                    CheckboxListTile(
                      title: const Text('Tự động tạo mật khẩu mạnh'),
                      subtitle: const Text('Bỏ chọn để tự nhập mật khẩu'),
                      value: autoGeneratePassword,
                      onChanged: (value) =>
                          setState(() => autoGeneratePassword = value ?? false),
                    ),
                    if (!autoGeneratePassword)
                      TextField(
                        controller: passC,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Mật khẩu (>=6 ký tự)',
                        ),
                      ),
                    TextField(
                      controller: nameC,
                      decoration: const InputDecoration(
                        labelText: 'Họ tên nhân viên',
                      ),
                    ),
                    TextField(
                      controller: phoneC,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                      ),
                    ),
                    TextField(
                      controller: addressC,
                      decoration: const InputDecoration(labelText: 'Địa chỉ'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Quyền'),
                        DropdownButton<String>(
                          value: role,
                          items: const [
                            DropdownMenuItem(
                              value: 'employee',
                              child: Text('Nhân viên'),
                            ),
                            DropdownMenuItem(
                              value: 'technician',
                              child: Text('Kỹ thuật'),
                            ),
                            DropdownMenuItem(
                              value: 'manager',
                              child: Text('Quản lý'),
                            ),
                            DropdownMenuItem(
                              value: 'owner',
                              child: Text('Chủ shop'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => role = v ?? 'employee'),
                        ),
                      ],
                    ),
                    if (_isSuperAdmin)
                      TextField(
                        controller: shopC,
                        decoration: const InputDecoration(
                          labelText: 'Shop ID (nhập khi tạo từ super admin)',
                        ),
                      ),
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          errorText!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('HỦY'),
                ),
                ElevatedButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('TẠO TÀI KHOẢN'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showBulkInviteDialog() {
    final emailsC = TextEditingController();
    final roleC = TextEditingController(text: 'employee');

    showDialog(
      context: context,
      builder: (ctx) {
        String role = 'employee';
        String? errorText;
        bool submitting = false;

        return StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> submit() async {
              if (submitting) return;

              final emailsText = emailsC.text.trim();
              if (emailsText.isEmpty) {
                setState(() => errorText = 'Nhập ít nhất một email');
                return;
              }

              final emails = emailsText
                  .split('\n')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();

              if (emails.isEmpty) {
                setState(() => errorText = 'Không tìm thấy email hợp lệ');
                return;
              }

              // Validate email format
              final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
              final invalidEmails = emails
                  .where((email) => !emailRegex.hasMatch(email))
                  .toList();

              if (invalidEmails.isNotEmpty) {
                setState(
                  () => errorText =
                      'Email không hợp lệ: ${invalidEmails.join(', ')}',
                );
                return;
              }

              setState(() {
                submitting = true;
                errorText = null;
              });

              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(ctx);

              try {
                int successCount = 0;
                int failCount = 0;
                List<String> failedEmails = [];

                for (final email in emails) {
                  try {
                    final callable = FirebaseFunctions.instanceFor(
                      region: 'asia-southeast1',
                    ).httpsCallable('createStaffAccount');
                    final payload = {
                      'email': email,
                      'password': _generateTempPassword(),
                      'displayName': email.split('@').first,
                      'role': role,
                      'autoGeneratedPassword': true,
                      'bulkInvite': true,
                    };

                    await callable.call(payload);
                    successCount++;
                  } catch (e) {
                    failCount++;
                    failedEmails.add(email);
                  }
                }

                if (!mounted) return;
                navigator.pop();

                String message = 'Đã mời $successCount nhân viên thành công';
                if (failCount > 0) {
                  message +=
                      ', $failCount thất bại: ${failedEmails.join(', ')}';
                }

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(message),
                    duration: const Duration(seconds: 5),
                  ),
                );
              } catch (e) {
                setState(() => errorText = 'Lỗi: $e');
              } finally {
                setState(() => submitting = false);
              }
            }

            return AlertDialog(
              title: const Text('MỜI NHÂN VIÊN HÀNG LOẠT'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nhập email của nhân viên (mỗi email một dòng)\nMật khẩu sẽ được tạo tự động và gửi qua email.',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: emailsC,
                      maxLines: 5,
                      keyboardType: TextInputType.multiline,
                      decoration: const InputDecoration(
                        labelText: 'Danh sách email',
                        hintText: 'email1@example.com\nemail2@example.com',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Quyền mặc định'),
                        DropdownButton<String>(
                          value: role,
                          items: const [
                            DropdownMenuItem(
                              value: 'employee',
                              child: Text('Nhân viên'),
                            ),
                            DropdownMenuItem(
                              value: 'technician',
                              child: Text('Kỹ thuật'),
                            ),
                            DropdownMenuItem(
                              value: 'manager',
                              child: Text('Quản lý'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => role = v ?? 'employee'),
                        ),
                      ],
                    ),
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          errorText!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('HỦY'),
                ),
                ElevatedButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('GỬI LỜI MỜI'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String _generateTempPassword() {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!@#\$%^&*';
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    String password = '';
    for (int i = 0; i < 12; i++) {
      password += chars[random.codeUnitAt(i % random.length) % chars.length];
    }
    return password;
  }

  void _showImportDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        String? errorText;
        bool submitting = false;
        List<Map<String, dynamic>>? parsedData;

        return StatefulBuilder(
          builder: (ctx, setState) {
            Future<void> pickFile() async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['csv'],
              );

              if (result != null && result.files.single.path != null) {
                final file = File(result.files.single.path!);
                final content = await file.readAsString();
                final csvData = const CsvToListConverter().convert(content);

                if (csvData.isEmpty || csvData[0].length < 2) {
                  setState(
                    () => errorText =
                        'File CSV không hợp lệ. Cần ít nhất 2 cột: Email, Họ tên',
                  );
                  return;
                }

                // Parse CSV data (skip header row)
                parsedData = [];
                for (int i = 1; i < csvData.length; i++) {
                  final row = csvData[i];
                  if (row.length >= 2) {
                    parsedData!.add({
                      'email': row[0]?.toString().trim() ?? '',
                      'displayName': row[1]?.toString().trim() ?? '',
                      'phone': row.length > 2 ? row[2]?.toString().trim() : '',
                      'address': row.length > 3
                          ? row[3]?.toString().trim()
                          : '',
                      'role': row.length > 4
                          ? row[4]?.toString().trim()
                          : 'employee',
                    });
                  }
                }

                setState(() => errorText = null);
              }
            }

            Future<void> submit() async {
              if (parsedData == null || parsedData!.isEmpty) {
                setState(() => errorText = 'Chưa chọn file hoặc file trống');
                return;
              }

              setState(() {
                submitting = true;
                errorText = null;
              });

              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(ctx);

              try {
                int successCount = 0;
                int failCount = 0;
                List<String> failedEmails = [];

                for (final staff in parsedData!) {
                  try {
                    final callable = FirebaseFunctions.instanceFor(
                      region: 'asia-southeast1',
                    ).httpsCallable('createStaffAccount');
                    final payload = {
                      'email': staff['email'],
                      'password': _generateTempPassword(),
                      'displayName': staff['displayName'],
                      'phone': staff['phone'] ?? '',
                      'address': staff['address'] ?? '',
                      'role': staff['role'] ?? 'employee',
                      'autoGeneratedPassword': true,
                      'bulkImport': true,
                    };

                    await callable.call(payload);
                    successCount++;
                  } catch (e) {
                    failCount++;
                    failedEmails.add(staff['email']);
                  }
                }

                if (!mounted) return;
                navigator.pop();

                String message = 'Đã import $successCount nhân viên thành công';
                if (failCount > 0) {
                  message +=
                      ', $failCount thất bại: ${failedEmails.join(', ')}';
                }

                messenger.showSnackBar(
                  SnackBar(
                    content: Text(message),
                    duration: const Duration(seconds: 5),
                  ),
                );
              } catch (e) {
                setState(() => errorText = 'Lỗi: $e');
              } finally {
                setState(() => submitting = false);
              }
            }

            return AlertDialog(
              title: const Text('IMPORT NHÂN VIÊN TỪ CSV'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Chọn file CSV với định dạng:\nEmail, Họ tên, SĐT (tùy chọn), Địa chỉ (tùy chọn), Quyền (tùy chọn)\n\nVí dụ:\nemail@example.com,Nguyễn Văn A,0987654321,Hà Nội,employee',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: 15),
                    ElevatedButton.icon(
                      onPressed: pickFile,
                      icon: const Icon(Icons.file_upload),
                      label: const Text('Chọn file CSV'),
                    ),
                    if (parsedData != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Đã tải ${parsedData!.length} nhân viên',
                          style: AppTextStyles.body2.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    if (errorText != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          errorText!,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('HỦY'),
                ),
                ElevatedButton(
                  onPressed: (parsedData != null && !submitting)
                      ? submit
                      : null,
                  child: submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('IMPORT'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingRole) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Kiểm tra quyền truy cập
    if (!_hasManageStaffAccess && !_isSuperAdmin) {
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
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text("QUẢN LÝ NHÂN VIÊN"),
          automaticallyImplyLeading: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.people, size: 64, color: AppColors.inactive),
              const SizedBox(height: 16),
              Text(
                "Bạn không có quyền truy cập\nmàn hình quản lý nhân viên",
                textAlign: TextAlign.center,
                style: AppTextStyles.body1.copyWith(color: AppColors.inactive),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: 'QUẢN LÝ NHÂN VIÊN',
        subtitle: _currentRole != null ? 'Vai trò: ${_currentRole!.toUpperCase()}' : null,
        accentColor: AppBarAccents.staff,
      ),
      floatingActionButton: _canManageStaff
          ? GradientFab.primary(
              onPressed: _openCreateStaffDialog,
              icon: Icons.person_add_alt_1,
              label: 'Thêm NV',
            )
          : null,
      body: _loadingRole
          ? const Center(child: CircularProgressIndicator())
          : _currentShopId == null && !_isSuperAdmin
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 64,
                    color: AppColors.warning,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Chưa có thông tin shop\nVui lòng đăng xuất và đăng nhập lại",
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body1.copyWith(
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      // Thử load lại shopId
                      final shopId = await UserService.getCurrentShopId();
                      if (shopId != null && mounted) {
                        setState(() => _currentShopId = shopId);
                      }
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            )
          : StreamBuilder<QuerySnapshot>(
              stream: _isSuperAdmin
                  ? UserService.getAllUsersStream()
                  : (_currentShopId != null
                        ? UserService.getUsersStreamByShopId(_currentShopId!)
                        : UserService.getAllUsersStream()),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Lỗi tải dữ liệu: ${snapshot.error}\nShopId: $_currentShopId",
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body1.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = snapshot.data!.docs;
                if (users.isEmpty) {
                  return Center(
                    child: Text(
                      "Chưa có dữ liệu nhân viên\nMỗi tài khoản sẽ tự xuất hiện sau khi đăng nhập",
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body1.copyWith(
                        color: AppColors.inactive,
                      ),
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
                    final displayName =
                        userData['displayName'] ??
                        email.split('@').first.toUpperCase();
                    final phone = userData['phone'] ?? "Chưa có SĐT";
                    final photoUrl = userData['photoUrl'];
                    final shopId = userData['shopId'];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: _safeImageProvider(photoUrl),
                          backgroundColor: role == 'owner'
                              ? AppColors.primary.withOpacity(0.1)
                              : role == 'manager'
                              ? AppColors.secondary.withOpacity(0.1)
                              : role == 'employee'
                              ? AppColors.info.withOpacity(0.1)
                              : role == 'technician'
                              ? AppColors.success.withOpacity(0.1)
                              : role == 'admin'
                              ? AppColors.error.withOpacity(0.1)
                              : AppColors.inactive.withOpacity(0.1),
                          child: photoUrl == null
                              ? Icon(
                                  role == 'owner'
                                      ? Icons.business
                                      : role == 'manager'
                                      ? Icons.supervisor_account
                                      : role == 'employee'
                                      ? Icons.work
                                      : role == 'technician'
                                      ? Icons.build
                                      : role == 'admin'
                                      ? Icons.admin_panel_settings
                                      : Icons.person,
                                  color: role == 'owner'
                                      ? AppColors.primary
                                      : role == 'manager'
                                      ? AppColors.secondary
                                      : role == 'employee'
                                      ? AppColors.info
                                      : role == 'technician'
                                      ? AppColors.success
                                      : role == 'admin'
                                      ? AppColors.error
                                      : AppColors.inactive,
                                )
                              : null,
                        ),
                        title: Text(
                          displayName,
                          style: AppTextStyles.headline6,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              email,
                              style: AppTextStyles.caption.copyWith(
                                fontSize: AppTextStyles.body1.fontSize,
                              ),
                            ),
                            Text(
                              "SĐT: $phone",
                              style: AppTextStyles.caption.copyWith(
                                fontSize: AppTextStyles.body1.fontSize,
                              ),
                            ),
                            role == 'admin'
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.error,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      "Vai trò: Admin",
                                      style: AppTextStyles.caption.copyWith(
                                        fontSize: AppTextStyles.body1.fontSize,
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  )
                                : Text(
                                    "Vai trò: ${role == 'owner'
                                        ? 'Chủ shop'
                                        : role == 'manager'
                                        ? 'Quản lý'
                                        : role == 'employee'
                                        ? 'Nhân viên'
                                        : role == 'technician'
                                        ? 'Kỹ thuật'
                                        : role == 'admin'
                                        ? 'Admin'
                                        : role == 'user'
                                        ? 'Người dùng'
                                        : role}",
                                    style: AppTextStyles.caption.copyWith(
                                      fontSize: AppTextStyles.body1.fontSize,
                                    ),
                                  ),
                            if (shopId != null)
                              FutureBuilder<DocumentSnapshot>(
                                future: FirebaseFirestore.instance
                                    .collection('shops')
                                    .doc(shopId)
                                    .get(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState ==
                                      ConnectionState.waiting) {
                                    return Text(
                                      "Shop: Đang tải...",
                                      style: AppTextStyles.caption.copyWith(
                                        fontSize: AppTextStyles.body1.fontSize,
                                        color: AppColors.secondary,
                                      ),
                                    );
                                  }
                                  if (snapshot.hasData &&
                                      snapshot.data!.exists) {
                                    final shopData =
                                        snapshot.data!.data()
                                            as Map<String, dynamic>;
                                    final shopName =
                                        shopData['name'] ?? 'Shop không tên';
                                    return Text(
                                      "Shop: $shopName",
                                      style: AppTextStyles.caption.copyWith(
                                        fontSize: AppTextStyles.body1.fontSize,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    );
                                  } else if (snapshot.hasError) {
                                    // Permission denied hoặc lỗi khác - hiển thị shop ID thay vì lỗi
                                    final shortId = shopId.length > 8
                                        ? '${shopId.substring(0, 8)}...'
                                        : shopId;
                                    return Text(
                                      "Shop: $shortId",
                                      style: AppTextStyles.caption.copyWith(
                                        fontSize: AppTextStyles.body1.fontSize,
                                        color: AppColors.secondary,
                                      ),
                                    );
                                  } else {
                                    final shortId = shopId.length > 8
                                        ? '${shopId.substring(0, 8)}...'
                                        : shopId;
                                    return Text(
                                      "Shop: $shortId",
                                      style: AppTextStyles.caption.copyWith(
                                        fontSize: AppTextStyles.body1.fontSize,
                                        color: AppColors.primary,
                                      ),
                                    );
                                  }
                                },
                              )
                            else
                              Text(
                                "Shop: Chưa gán",
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: AppTextStyles.body1.fontSize,
                                  color: AppColors.secondary,
                                ),
                              ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: const Icon(
                          Icons.edit_note_rounded,
                          color: Colors.blueAccent,
                        ),
                        onTap: () => _showStaffActivityCenter(
                          uid,
                          displayName,
                          email,
                          role,
                          userData,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  void _showStaffActivityCenter(
    String uid,
    String name,
    String email,
    String currentRole,
    Map<String, dynamic> fullData,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StaffActivityCenter(
        uid: uid,
        name: name,
        email: email,
        role: currentRole,
        fullData: fullData,
        isSuperAdmin: _isSuperAdmin,
      ),
    );
  }
}

class _StaffActivityCenter extends StatefulWidget {
  final String uid, name, email, role;
  final Map<String, dynamic> fullData;
  final bool isSuperAdmin;
  const _StaffActivityCenter({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    required this.fullData,
    required this.isSuperAdmin,
  });

  @override
  State<_StaffActivityCenter> createState() => _StaffActivityCenterState();
}

class _StaffActivityCenterState extends State<_StaffActivityCenter>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final db = DBHelper();

  // Controllers cho phần chỉnh sửa thông tin
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  String? _photoPath;
  String _selectedRole = 'employee'; // Mặc định là employee
  bool _isEditing = false;

  String? _staffShopId;
  String? _currentUserShopId;
  bool _loadingShop = true;
  bool _assigningShop = false;

  // Phân quyền ẩn/hiện nội dung cho nhân viên
  bool _canViewSales = true;
  bool _canViewRepairs = true;
  bool _canViewInventory = true;
  bool _canViewParts = true;
  bool _canViewSuppliers = true;
  bool _canViewCustomers = true;
  bool _canViewWarranty = true;
  bool _canViewChat = true;
  bool _canViewAttendance = true;
  bool _canViewPrinter = true;
  bool _canViewRevenue = false;
  bool _canViewExpenses = false;
  bool _canViewDebts = false;

  List<Repair> _repairsReceived = [];
  List<Repair> _repairsDelivered = [];
  List<SaleOrder> _sales = [];

  Map<String, dynamic>? _workSchedule;

  @override
  void initState() {
    super.initState();
    try {
      _tabController = TabController(length: 4, vsync: this);

      // Gán dữ liệu ban đầu
      nameCtrl.text = widget.fullData['displayName'] ?? widget.name;
      phoneCtrl.text = widget.fullData['phone'] ?? "";
      addressCtrl.text = widget.fullData['address'] ?? "";
      _photoPath = widget.fullData['photoUrl'];
      // Đảm bảo role nằm trong danh sách dropdown, nếu không dùng mặc định 'employee'
      const validRoles = ['owner', 'manager', 'employee', 'technician'];
      _selectedRole = validRoles.contains(widget.role)
          ? widget.role
          : 'employee';
      _staffShopId = widget.fullData['shopId'];

      // Quyền xem nội dung (mặc định: chỉ quản lý thấy toàn bộ tài chính)
      _canViewSales = widget.fullData['allowViewSales'] == true;
      _canViewRepairs = widget.fullData['allowViewRepairs'] == true;
      _canViewInventory = widget.fullData['allowViewInventory'] == true;
      _canViewParts = widget.fullData['allowViewParts'] == true;
      _canViewSuppliers = widget.fullData['allowViewSuppliers'] == true;
      _canViewCustomers = widget.fullData['allowViewCustomers'] == true;
      _canViewWarranty = widget.fullData['allowViewWarranty'] == true;
      _canViewChat = widget.fullData['allowViewChat'] == true;
      _canViewAttendance = widget.fullData['allowViewAttendance'] == true;
      _canViewPrinter = widget.fullData['allowViewPrinter'] == true;
      _canViewRevenue = widget.fullData['allowViewRevenue'] == true;
      _canViewExpenses = widget.fullData['allowViewExpenses'] == true;
      _canViewDebts = widget.fullData['allowViewDebts'] == true;

      // Đồng bộ permissions với role hiện tại
      _syncPermissionsWithRole();

      _loadCurrentShop();
      _loadAllStaffData();
      _loadWorkSchedule();
    } catch (e) {
      debugPrint('Error in _StaffActivityCenterState.initState: $e');
      // Fallback values
      _tabController = TabController(length: 4, vsync: this);
      nameCtrl.text = widget.name;
      _selectedRole = 'employee';
    }
  }

  void _syncPermissionsWithRole() {
    // Nếu là owner hoặc manager, luôn có full permissions
    if (_selectedRole == 'owner' || _selectedRole == 'manager') {
      _canViewSales = true;
      _canViewRepairs = true;
      _canViewInventory = true;
      _canViewParts = true;
      _canViewSuppliers = true;
      _canViewCustomers = true;
      _canViewWarranty = true;
      _canViewChat = true;
      _canViewAttendance = true;
      _canViewPrinter = true;
      _canViewRevenue = true;
      _canViewExpenses = true;
      _canViewDebts = true;
    }
  }

  Future<void> _loadCurrentShop() async {
    try {
      final id = await UserService.getCurrentShopId();
      if (!mounted) return;
      setState(() {
        _currentUserShopId = id;
        _loadingShop = false;
      });
    } catch (e) {
      debugPrint('Error loading current shop: $e');
      if (!mounted) return;
      setState(() {
        _currentUserShopId = null;
        _loadingShop = false;
      });
    }
  }

  Future<void> _loadAllStaffData() async {
    try {
      final allR = await db.getAllRepairs();
      final allS = await db.getAllSales();
      if (!mounted) return;

      // Staff identifier có thể là email prefix (HUY từ huy@gmail.com)
      // hoặc displayName đầy đủ - cần so sánh cả hai
      final emailPrefix = widget.email
          .split('@')
          .first
          .toUpperCase(); // VD: "HUY"
      final displayName = widget.name.toUpperCase(); // VD: "NGUYEN VAN HUY"

      bool matchesStaff(String? value) {
        if (value == null || value.isEmpty) return false;
        final v = value.toUpperCase();
        return v == emailPrefix || v == displayName || v.contains(emailPrefix);
      }

      setState(() {
        _repairsReceived = allR
            .where((r) => matchesStaff(r.createdBy))
            .toList();
        _repairsDelivered = allR
            .where((r) => matchesStaff(r.deliveredBy))
            .toList();
        _sales = allS.where((s) => matchesStaff(s.sellerName)).toList();
      });
      debugPrint(
        'Staff data loaded: received=${_repairsReceived.length}, delivered=${_repairsDelivered.length}, sales=${_sales.length} for $emailPrefix / $displayName',
      );
    } catch (e) {
      debugPrint('Error loading staff data: $e');
      if (!mounted) return;
      setState(() {
        _repairsReceived = [];
        _repairsDelivered = [];
        _sales = [];
      });
    }
  }

  Future<void> _loadWorkSchedule() async {
    try {
      final schedule = await db.getWorkSchedule(widget.uid);
      if (!mounted) return;
      setState(() => _workSchedule = schedule);
    } catch (e) {
      debugPrint('Error loading work schedule: $e');
      if (!mounted) return;
      setState(() => _workSchedule = null);
    }
  }

  void _editWorkScheduleForStaff() async {
    final startTimeCtrl = TextEditingController(
      text: _workSchedule?['startTime'] ?? '08:00',
    );
    final endTimeCtrl = TextEditingController(
      text: _workSchedule?['endTime'] ?? '17:00',
    );
    final breakTimeCtrl = TextEditingController(
      text: (_workSchedule?['breakTime'] ?? 1).toString(),
    );
    final maxOtCtrl = TextEditingController(
      text: (_workSchedule?['maxOtHours'] ?? 4).toString(),
    );

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Chỉnh sửa lịch làm việc cho ${widget.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: startTimeCtrl,
              decoration: const InputDecoration(
                labelText: 'Giờ bắt đầu (HH:mm)',
              ),
            ),
            TextField(
              controller: endTimeCtrl,
              decoration: const InputDecoration(
                labelText: 'Giờ kết thúc (HH:mm)',
              ),
            ),
            TextField(
              controller: breakTimeCtrl,
              decoration: const InputDecoration(labelText: 'Giờ nghỉ (giờ)'),
              keyboardType: TextInputType.number,
            ),
            TextField(
              controller: maxOtCtrl,
              decoration: const InputDecoration(
                labelText: 'OT tối đa (giờ/ngày)',
              ),
              keyboardType: TextInputType.number,
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
              final newSchedule = {
                'userId': widget.uid,
                'startTime': startTimeCtrl.text,
                'endTime': endTimeCtrl.text,
                'breakTime': int.tryParse(breakTimeCtrl.text) ?? 1,
                'maxOtHours': int.tryParse(maxOtCtrl.text) ?? 4,
                'workDays': [1, 2, 3, 4, 5, 6], // Monday to Saturday
                'updatedAt': DateTime.now().millisecondsSinceEpoch,
              };

              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);
              await db.upsertWorkSchedule(widget.uid, newSchedule);
              await _loadWorkSchedule();
              navigator.pop();
              messenger.showSnackBar(
                const SnackBar(
                  content: Text("Đã cập nhật lịch làm việc"),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('LƯU'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickPhoto() async {
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 50,
    );
    if (f != null) setState(() => _photoPath = f.path);
  }

  Future<void> _saveStaffInfo() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      // Upload photo if it's a local file
      String? photoUrl = _photoPath;
      if (_photoPath != null && !_photoPath!.startsWith('http')) {
        print('Uploading photo: $_photoPath');
        photoUrl = await StorageService.uploadAndGetUrl(
          _photoPath!,
          'user_photos',
        );
        if (photoUrl == null) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text("Lỗi khi upload ảnh - kiểm tra kết nối internet"),
            ),
          );
          return;
        }
        print('Photo uploaded successfully: $photoUrl');
      }

      print('Updating user info for ${widget.uid}');
      await UserService.updateUserInfo(
        uid: widget.uid,
        name: nameCtrl.text,
        phone: phoneCtrl.text,
        address: addressCtrl.text,
        role: _selectedRole,
        photoUrl: photoUrl,
      );

      print('Updating user permissions for ${widget.uid}');
      // Lưu cấu hình phân quyền hiển thị nội dung
      await UserService.updateUserPermissions(
        uid: widget.uid,
        allowViewSales: _canViewSales,
        allowViewRepairs: _canViewRepairs,
        allowViewInventory: _canViewInventory,
        allowViewParts: _canViewParts,
        allowViewSuppliers: _canViewSuppliers,
        allowViewCustomers: _canViewCustomers,
        allowViewWarranty: _canViewWarranty,
        allowViewChat: _canViewChat,
        allowViewAttendance: _canViewAttendance,
        allowViewPrinter: _canViewPrinter,
        allowViewRevenue: _canViewRevenue,
        allowViewExpenses: _canViewExpenses,
        allowViewDebts: _canViewDebts,
      );

      if (!mounted) return;
      setState(() => _isEditing = false);
      messenger.showSnackBar(
        const SnackBar(content: Text("ĐÃ CẬP NHẬT HỒ SƠ NHÂN VIÊN!")),
      );
    } catch (e) {
      print('Error saving staff info: $e');
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text("Lỗi khi cập nhật: $e")));
    }
  }

  Future<void> _assignToMyShop() async {
    if (_currentUserShopId == null || _currentUserShopId!.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Không xác định được cửa hàng hiện tại")),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _assigningShop = true);
    try {
      await UserService.assignUserToCurrentShop(widget.uid);
      if (!mounted) return;
      setState(() {
        _staffShopId = _currentUserShopId;
      });
      messenger.showSnackBar(
        const SnackBar(content: Text("ĐÃ GÁN NHÂN VIÊN VÀO CỬA HÀNG CỦA BẠN")),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text("Lỗi khi gán cửa hàng: $e")),
      );
    } finally {
      if (mounted) setState(() => _assigningShop = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(10),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _isEditing ? _pickPhoto : null,
                  child: CircleAvatar(
                    radius: 30,
                    backgroundImage: _safeImageProvider(_photoPath),
                    backgroundColor: Colors.blue.withAlpha(25),
                    child: _photoPath == null
                        ? const Icon(Icons.camera_alt, color: Colors.blue)
                        : null,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: TextStyle(
                          fontSize: AppTextStyles.headline2.fontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        widget.email,
                        style: TextStyle(
                          fontSize: AppTextStyles.subtitle1.fontSize,
                          color: Colors.grey,
                        ),
                      ),
                      if (widget.isSuperAdmin)
                        Text(
                          "UID: ${widget.uid}",
                          style: TextStyle(
                            fontSize: AppTextStyles.body1.fontSize,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _isEditing ? Icons.check_circle : Icons.edit,
                    color: _isEditing ? Colors.green : Colors.blue,
                  ),
                  onPressed: () {
                    if (_isEditing) {
                      _saveStaffInfo();
                    } else {
                      setState(() => _isEditing = true);
                    }
                  },
                ),
              ],
            ),
          ),

          if (_isEditing)
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _editInput(
                        nameCtrl,
                        "Họ và tên nhân viên",
                        Icons.person_outline,
                      ),
                      _editInput(
                        phoneCtrl,
                        "Số điện thoại liên hệ",
                        Icons.phone_android_outlined,
                        type: TextInputType.phone,
                      ),
                      _editInput(
                        addressCtrl,
                        "Địa chỉ thường trú",
                        Icons.location_on_outlined,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Quyền hệ thống:",
                            style: TextStyle(
                              fontSize: AppTextStyles.headline5.fontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          DropdownButton<String>(
                            value: _selectedRole,
                            items: const [
                              DropdownMenuItem(
                                value: 'owner',
                                child: Text("CHỦ SHOP"),
                              ),
                              DropdownMenuItem(
                                value: 'manager',
                                child: Text("QUẢN LÝ"),
                              ),
                              DropdownMenuItem(
                                value: 'employee',
                                child: Text("NHÂN VIÊN"),
                              ),
                              DropdownMenuItem(
                                value: 'technician',
                                child: Text("KỸ THUẬT"),
                              ),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _selectedRole = v!;
                                _syncPermissionsWithRole();
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              "Cửa hàng của nhân viên: ${_staffShopId ?? 'Chưa gán'}",
                              style: TextStyle(
                                fontSize: AppTextStyles.subtitle1.fontSize,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                          if (!_loadingShop && _currentUserShopId != null)
                            TextButton.icon(
                              onPressed: _assigningShop
                                  ? null
                                  : _assignToMyShop,
                              icon: _assigningShop
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.store_mall_directory,
                                      size: 18,
                                    ),
                              label: Text(
                                "GÁN VÀO SHOP CỦA TÔI",
                                style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                              ),
                            ),
                        ],
                      ),
                      const Divider(),

                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "PHÂN QUYỀN NỘI DUNG CHO NHÂN VIÊN",
                          style: TextStyle(
                            fontSize: AppTextStyles.subtitle1.fontSize,
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey[700],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.withAlpha(51)),
                        ),
                        child: Column(
                          children: [
                            if (_selectedRole == 'owner' ||
                                _selectedRole == 'manager')
                              Padding(
                                padding: const EdgeInsets.all(10),
                                child: Text(
                                  "Tài khoản CHỦ SHOP/QUẢN LÝ luôn được xem đầy đủ mọi nội dung trong hệ thống.",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                              )
                            else ...[
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    "MÀN HÌNH NGHIỆP VỤ",
                                    style: TextStyle(
                                      fontSize: AppTextStyles.body1.fontSize,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "BÁN HÀNG",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Xem và tạo đơn bán máy / phụ kiện",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewSales,
                                onChanged: (v) =>
                                    setState(() => _canViewSales = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "SỬA CHỮA",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Xem danh sách đơn sửa, tạo đơn mới",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewRepairs,
                                onChanged: (v) =>
                                    setState(() => _canViewRepairs = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "KHO",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Xem hàng tồn kho và phụ kiện",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewInventory,
                                onChanged: (v) =>
                                    setState(() => _canViewInventory = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "KHO LINH KIỆN SỬA CHỮA",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Quản lý linh kiện dùng cho sửa chữa",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewParts,
                                onChanged: (v) =>
                                    setState(() => _canViewParts = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "NHÀ CUNG CẤP",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Xem sổ nhà phân phối, lịch sử nhập hàng",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewSuppliers,
                                onChanged: (v) =>
                                    setState(() => _canViewSuppliers = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "KHÁCH HÀNG",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Xem danh sách khách và lịch sử mua/sửa",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewCustomers,
                                onChanged: (v) =>
                                    setState(() => _canViewCustomers = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "BẢO HÀNH",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Truy cập sổ bảo hành của cửa hàng",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewWarranty,
                                onChanged: (v) =>
                                    setState(() => _canViewWarranty = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "CHAT NỘI BỘ",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Cho phép sử dụng phòng chat trong cửa hàng",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewChat,
                                onChanged: (v) =>
                                    setState(() => _canViewChat = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "CHẤM CÔNG",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Cho phép chấm công và xem báo cáo chấm công",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewAttendance,
                                onChanged: (v) =>
                                    setState(() => _canViewAttendance = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "CẤU HÌNH MÁY IN",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Kết nối và in hóa đơn qua Bluetooth",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewPrinter,
                                onChanged: (v) =>
                                    setState(() => _canViewPrinter = v),
                              ),

                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    "MÀN HÌNH TÀI CHÍNH NHẠY CẢM",
                                    style: TextStyle(
                                      fontSize: AppTextStyles.body1.fontSize,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blueGrey,
                                    ),
                                  ),
                                ),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "Cho phép xem màn DOANH THU",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Bao gồm báo cáo lời/lỗ, doanh số bán và sửa",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewRevenue,
                                onChanged: (v) =>
                                    setState(() => _canViewRevenue = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "Cho phép xem màn CHI PHÍ",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Xem và quản lý các khoản chi ra của cửa hàng",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewExpenses,
                                onChanged: (v) =>
                                    setState(() => _canViewExpenses = v),
                              ),
                              SwitchListTile(
                                title: Text(
                                  "Cho phép xem SỔ CÔNG NỢ",
                                  style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                                ),
                                subtitle: Text(
                                  "Bao gồm khách nợ shop và shop nợ nhà cung cấp",
                                  style: TextStyle(
                                    fontSize: AppTextStyles.body1.fontSize,
                                    color: Colors.grey,
                                  ),
                                ),
                                value: _canViewDebts,
                                onChanged: (v) =>
                                    setState(() => _canViewDebts = v),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 10),
          TabBar(
            controller: _tabController,
            labelColor: Colors.blueAccent,
            unselectedLabelColor: Colors.grey,
            labelStyle: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              fontWeight: FontWeight.bold,
            ),
            tabs: const [
              Tab(
                text: "ĐÃ NHẬN",
                icon: Icon(Icons.move_to_inbox_rounded, size: 20),
              ),
              Tab(text: "ĐÃ GIAO", icon: Icon(Icons.outbox_rounded, size: 20)),
              Tab(
                text: "ĐÃ BÁN",
                icon: Icon(Icons.shopping_cart_checkout_rounded, size: 20),
              ),
              Tab(text: "LỊCH LÀM VIỆC", icon: Icon(Icons.schedule, size: 20)),
            ],
          ),

          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRepairList(_repairsReceived),
                _buildRepairList(_repairsDelivered),
                _buildSaleList(_sales),
                _buildWorkScheduleTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _editInput(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    TextInputType type = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        style: TextStyle(fontSize: AppTextStyles.headline4.fontSize, color: Colors.black),
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18, color: Colors.blueAccent),
          border: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blueAccent, width: 1),
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blueAccent, width: 1),
          ),
          focusedBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.blueAccent, width: 2),
          ),
          errorBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.red, width: 1),
          ),
          focusedErrorBorder: const OutlineInputBorder(
            borderSide: BorderSide(color: Colors.red, width: 2),
          ),
          contentPadding: const EdgeInsets.all(10),
          fillColor: Colors.white,
          filled: true,
        ),
      ),
    );
  }

  Widget _buildRepairList(List<Repair> list) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          "Không có dữ liệu",
          style: TextStyle(color: Colors.grey, fontSize: AppTextStyles.subtitle1.fontSize),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final r = list[i];
        final statusLabel = _repairStatusLabel(r.status);
        final statusColor = _repairStatusColor(r.status);
        final deliveredAt = r.deliveredAt ?? 0;
        final time = deliveredAt > 0 ? deliveredAt : r.createdAt;
        final dateStr = DateFormat('dd/MM HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(time));

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: statusColor.withOpacity(0.35)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => RepairDetailView(repair: r)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.model,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextStyles.headline5.fontSize,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${r.customerName} • ${r.phone}',
                              style: TextStyle(
                                fontSize: AppTextStyles.body1.fontSize,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              statusLabel,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppTextStyles.overlineSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: AppTextStyles.caption.fontSize,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      if (r.issue.isNotEmpty)
                        _infoChip('🛠️ ${r.issue}', Colors.orange.shade100),
                      if ((r.imei ?? '').trim().isNotEmpty)
                        _infoChip('🔎 ${r.imei}', Colors.blue.shade100),
                      _infoChip(
                        '💰 ${MoneyUtils.formatVND(r.price)}đ',
                        Colors.green.shade100,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaleList(List<SaleOrder> list) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          "Không có dữ liệu",
          style: TextStyle(color: Colors.grey, fontSize: AppTextStyles.subtitle1.fontSize),
        ),
      );
    }
    final fmt = NumberFormat('#,###');
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final s = list[i];
        final isPaid = s.isPaid;
        final remain = s.remainingDebt;
        final date = DateFormat('dd/MM HH:mm')
            .format(DateTime.fromMillisecondsSinceEpoch(s.soldAt));

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.green.withOpacity(0.25)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SaleDetailView(sale: s)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.productNames,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextStyles.headline5.fontSize,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${s.customerName} • ${s.phone}',
                              style: TextStyle(
                                fontSize: AppTextStyles.body1.fontSize,
                                color: Colors.grey.shade700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isPaid ? Colors.green : Colors.orange,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isPaid ? 'ĐÃ THU' : 'CÒN NỢ',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppTextStyles.overlineSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            date,
                            style: TextStyle(
                              fontSize: AppTextStyles.caption.fontSize,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      _saleInfoChip(
                        '💰 ${fmt.format(s.finalPrice)}đ',
                        Colors.blue.shade100,
                      ),
                      if (s.downPayment > 0)
                        _saleInfoChip(
                          '✅ ${fmt.format(s.downPayment)}đ',
                          Colors.green.shade100,
                        ),
                      if (remain > 0)
                        _saleInfoChip(
                          '⚠️ Nợ ${fmt.format(remain)}đ',
                          Colors.red.shade100,
                        ),
                      _saleInfoChip(
                        '💳 ${s.paymentMethod}',
                        _getPayColor(s.paymentMethod).withAlpha(40),
                      ),
                      _saleInfoChip(
                        '👤 ${s.sellerName}',
                        Colors.purple.shade100,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _repairStatusLabel(int status) {
    switch (status) {
      case 1:
        return 'ĐÃ NHẬN';
      case 2:
        return 'ĐANG SỬA';
      case 3:
        return 'ĐÃ XONG';
      case 4:
        return 'ĐÃ GIAO';
      default:
        return 'KHÁC';
    }
  }

  Color _repairStatusColor(int status) {
    switch (status) {
      case 1:
        return Colors.blue;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.green;
      case 4:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  Color _getPayColor(String m) {
    if (m.contains("TIỀN MẶT")) return AppColors.success;
    if (m.contains("CHUYỂN KHOẢN")) return AppColors.primary;
    if (m.contains("TRẢ GÓP")) return AppColors.warning;
    return AppColors.error;
  }

  Widget _infoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTextStyles.caption.fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _saleInfoChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTextStyles.caption.fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildWorkScheduleTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Lịch làm việc hiện tại",
                style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold),
              ),
              ElevatedButton.icon(
                onPressed: _editWorkScheduleForStaff,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text("Chỉnh sửa"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_workSchedule != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.access_time, color: Colors.blue),
                        const SizedBox(width: 8),
                        Text(
                          "Giờ làm việc: ${_workSchedule!['startTime']} - ${_workSchedule!['endTime']}",
                          style: TextStyle(
                            fontSize: AppTextStyles.headline3.fontSize,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.free_breakfast, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          "Giờ nghỉ: ${_workSchedule!['breakTime']} giờ",
                          style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.timer, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          "OT tối đa: ${_workSchedule!['maxOtHours']} giờ/ngày",
                          style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, color: Colors.purple),
                        const SizedBox(width: 8),
                        Text(
                          "Ngày làm việc: Thứ 2 - Thứ 7",
                          style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(Icons.schedule, size: 48, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text(
                      "Chưa có lịch làm việc",
                      style: TextStyle(color: Colors.grey, fontSize: AppTextStyles.headline3.fontSize),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Nhấn 'Chỉnh sửa' để thiết lập lịch làm việc cho nhân viên này",
                      style: TextStyle(color: Colors.grey, fontSize: AppTextStyles.subtitle1.fontSize),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }
}
