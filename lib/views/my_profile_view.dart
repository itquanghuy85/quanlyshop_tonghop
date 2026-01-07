import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';
import '../widgets/validated_text_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';

class MyProfileView extends StatefulWidget {
  const MyProfileView({super.key});

  @override
  State<MyProfileView> createState() => _MyProfileViewState();
}

class _MyProfileViewState extends State<MyProfileView> {
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  String? _photoPath;
  String _role = 'user';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _save() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await UserService.updateUserInfo(
        uid: user.uid,
        name: nameCtrl.text,
        phone: phoneCtrl.text,
        address: addressCtrl.text,
        role: _role,
        photoUrl: _photoPath,
      );
      messenger.showSnackBar(const SnackBar(content: Text('ĐÃ LƯU HỒ SƠ CÁ NHÂN')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HỒ SƠ CÁ NHÂN')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundImage: _photoPath != null && File(_photoPath!).existsSync() ? FileImage(File(_photoPath!)) : null,
                        child: _photoPath == null ? const Icon(Icons.person, size: 30) : null,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_getRoleDisplayName(_role), style: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.6))),
                          const SizedBox(height: 4),
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  _input(nameCtrl, 'Họ và tên'),
                  _input(phoneCtrl, 'Số điện thoại', keyboard: TextInputType.phone),
                  _input(addressCtrl, 'Địa chỉ'),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? CircularProgressIndicator(color: AppColors.onPrimary)
                          : Text('LƯU THAY ĐỔI', style: AppTextStyles.button.copyWith(fontWeight: FontWeight.bold)),
                    ),
                  )
                ],
              ),
            ),
    );
  }

  Widget _input(TextEditingController c, String label, {TextInputType keyboard = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ValidatedTextField(
        controller: c,
        label: label,
        keyboardType: keyboard,
        uppercase: true, // All profile fields should be uppercase
      ),
    );
  }
}
