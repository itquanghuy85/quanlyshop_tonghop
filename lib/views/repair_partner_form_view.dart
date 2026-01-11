import 'package:flutter/material.dart';
import '../models/repair_partner_model.dart';
import '../services/repair_partner_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/event_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class RepairPartnerFormView extends StatefulWidget {
  final RepairPartner? editing;
  const RepairPartnerFormView({super.key, this.editing});

  @override
  State<RepairPartnerFormView> createState() => _RepairPartnerFormViewState();
}

class _RepairPartnerFormViewState extends State<RepairPartnerFormView> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _service = RepairPartnerService();
  bool _active = true;
  bool _saving = false;

  bool get _isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _nameCtrl.text = widget.editing!.name;
      _phoneCtrl.text = widget.editing!.phone ?? '';
      _noteCtrl.text = widget.editing!.note ?? '';
      _active = widget.editing!.active;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final shopId = await UserService.getCurrentShopId() ?? '';
      final partner = RepairPartner(
        id: widget.editing?.id,
        name: _nameCtrl.text.trim().toUpperCase(),
        phone: _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        active: _active,
        shopId: shopId,
        firestoreId: widget.editing?.firestoreId,
        createdAt: widget.editing?.createdAt,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      if (_isEditing) {
        final success = await _service.updateRepairPartner(partner);
        if (success) {
          NotificationService.showSnackBar(
            'Đã cập nhật đối tác sửa chữa',
            color: Colors.green,
          );
          EventBus().emit('repair_partners_changed');
          if (mounted) Navigator.pop(context, true);
        } else {
          NotificationService.showSnackBar(
            'Lỗi cập nhật đối tác',
            color: Colors.red,
          );
        }
      } else {
        final result = await _service.addRepairPartner(partner);
        if (result != null) {
          NotificationService.showSnackBar(
            'Đã thêm đối tác sửa chữa mới',
            color: Colors.green,
          );
          EventBus().emit('repair_partners_changed');
          if (mounted) Navigator.pop(context, true);
        } else {
          NotificationService.showSnackBar(
            'Lỗi thêm đối tác',
            color: Colors.red,
          );
        }
      }
    } catch (e) {
      NotificationService.showSnackBar('Lỗi: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'SỬA ĐỐI TÁC SỬA CHỮA' : 'THÊM ĐỐI TÁC SỬA CHỮA',
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        actions: [
          if (_isEditing)
            IconButton(
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete),
              tooltip: 'Xóa',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSection('Thông tin đối tác', [
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Tên đối tác *',
                  hintText: 'VD: TIỆM SỬA DIEN_THOAI ABC',
                  prefixIcon: Icon(Icons.business),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Vui lòng nhập tên'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  hintText: '0901234567',
                  prefixIcon: Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  hintText: 'Chuyên sửa iPhone, thay IC...',
                  prefixIcon: Icon(Icons.note),
                ),
              ),
            ]),
            const SizedBox(height: 16),
            _buildSection('Trạng thái', [
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                title: Text('Đang hoạt động', style: AppTextStyles.body1),
                subtitle: Text(
                  _active
                      ? 'Đối tác sẽ xuất hiện trong danh sách chọn'
                      : 'Đối tác sẽ bị ẩn',
                  style: AppTextStyles.caption,
                ),
                secondary: Icon(
                  _active ? Icons.check_circle : Icons.cancel,
                  color: _active ? AppColors.success : AppColors.error,
                ),
              ),
            ]),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(_isEditing ? 'CẬP NHẬT' : 'THÊM ĐỐI TÁC'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                minimumSize: const Size(double.infinity, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 6)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.headline6.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const Divider(height: 20),
          ...children,
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
          'Bạn có chắc muốn xóa đối tác "${widget.editing!.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('XÓA'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final success = await _service.deleteRepairPartner(widget.editing!.id!);
      if (success) {
        NotificationService.showSnackBar('Đã xóa đối tác', color: Colors.green);
        EventBus().emit('repair_partners_changed');
        if (mounted) Navigator.pop(context, true);
      } else {
        NotificationService.showSnackBar('Lỗi xóa đối tác', color: Colors.red);
      }
    }
  }
}
