import 'package:flutter/material.dart';
import '../models/supplier_model.dart';
import '../services/supplier_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';

class SupplierFormView extends StatefulWidget {
  final Supplier? editing;
  const SupplierFormView({super.key, this.editing});

  @override
  State<SupplierFormView> createState() => _SupplierFormViewState();
}

class _SupplierFormViewState extends State<SupplierFormView> {
  final _service = SupplierService();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _active = true;
  bool _favorite = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.editing != null) {
      final s = widget.editing!;
      _nameCtrl.text = s.name;
      _phoneCtrl.text = s.phone ?? '';
      _addressCtrl.text = s.address ?? '';
      _noteCtrl.text = s.note ?? '';
      _active = s.active;
      _favorite = s.favorite;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      NotificationService.showSnackBar('Tên NCC bắt buộc', color: Colors.red);
      return;
    }
    setState(() => _saving = true);
    try {
      final shopId = await UserService.getCurrentShopId();
      final supplier = Supplier(
        id: widget.editing?.id,
        firestoreId: widget.editing?.firestoreId,
        name: _nameCtrl.text.trim().toUpperCase(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        active: _active,
        favorite: _favorite,
        shopId: shopId ?? '',
      );
      if (widget.editing == null) {
        await _service.addSupplier(supplier);
        NotificationService.showSnackBar('Đã tạo NCC', color: Colors.green);
      } else {
        await _service.updateSupplier(supplier);
        NotificationService.showSnackBar('Đã cập nhật NCC', color: Colors.green);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      NotificationService.showSnackBar('Lỗi lưu NCC: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editing != null;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(isEdit ? 'SỬA NCC' : 'THÊM NCC'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'Tên NCC *', prefixIcon: Icon(Icons.business)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneCtrl,
              decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone)),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _addressCtrl,
              decoration: const InputDecoration(labelText: 'Địa chỉ', prefixIcon: Icon(Icons.location_on)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(labelText: 'Ghi chú', prefixIcon: Icon(Icons.notes)),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Hoạt động'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
            SwitchListTile(
              title: const Text('Ưu tiên (favorite)'),
              value: _favorite,
              onChanged: (v) => setState(() => _favorite = v),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: AppButtonStyles.elevatedButtonStyle,
                child: _saving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(isEdit ? 'LƯU THAY ĐỔI' : 'TẠO MỚI', style: AppTextStyles.button.copyWith(color: AppColors.onPrimary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
