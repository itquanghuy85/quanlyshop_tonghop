import 'package:flutter/material.dart';
import '../models/repair_partner_model.dart';
import '../services/repair_partner_service.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
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
  final _partnerService = RepairPartnerService();
  
  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _noteCtrl;
  bool _active = true;
  bool _saving = false;

  bool get isEditing => widget.editing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.editing?.name ?? '');
    _phoneCtrl = TextEditingController(text: widget.editing?.phone ?? '');
    _noteCtrl = TextEditingController(text: widget.editing?.note ?? '');
    _active = widget.editing?.active ?? true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    
    setState(() => _saving = true);
    
    try {
      final shopId = await UserService.getCurrentShopId() ?? '';
      
      if (isEditing) {
        final updated = widget.editing!.copyWith(
          name: _nameCtrl.text.trim().toUpperCase(),
          phone: _phoneCtrl.text.trim(),
          note: _noteCtrl.text.trim(),
          active: _active,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        final success = await _partnerService.updateRepairPartner(updated);
        if (success) {
          NotificationService.showSnackBar('Đã cập nhật đối tác', color: Colors.green);
          if (mounted) Navigator.pop(context, true);
        } else {
          NotificationService.showSnackBar('Lỗi cập nhật đối tác', color: Colors.red);
        }
      } else {
        final partner = RepairPartner(
          name: _nameCtrl.text.trim().toUpperCase(),
          phone: _phoneCtrl.text.trim(),
          note: _noteCtrl.text.trim(),
          active: _active,
          shopId: shopId,
        );
        final result = await _partnerService.addRepairPartner(partner);
        if (result != null) {
          NotificationService.showSnackBar('Đã thêm đối tác mới', color: Colors.green);
          if (mounted) Navigator.pop(context, true);
        } else {
          NotificationService.showSnackBar('Lỗi thêm đối tác', color: Colors.red);
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
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF11998e), Color(0xFF38ef7d)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          isEditing ? 'SỬA ĐỐI TÁC' : 'THÊM ĐỐI TÁC MỚI',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          if (_saving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              onPressed: _save,
              icon: const Icon(Icons.check),
              tooltip: 'Lưu',
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Tên đối tác
            _buildTextField(
              controller: _nameCtrl,
              label: 'Tên đối tác *',
              hint: 'VD: TIỆM SỬA ABC',
              icon: Icons.business,
              caps: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'Vui lòng nhập tên đối tác';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Số điện thoại
            _buildTextField(
              controller: _phoneCtrl,
              label: 'Số điện thoại',
              hint: '0123456789',
              icon: Icons.phone,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 16),
            
            // Ghi chú
            _buildTextField(
              controller: _noteCtrl,
              label: 'Ghi chú',
              hint: 'Chuyên sửa màn hình, main board...',
              icon: Icons.note,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            
            // Trạng thái
            SwitchListTile(
              title: Text('Đang hoạt động', style: AppTextStyles.body1),
              subtitle: Text(
                _active ? 'Đối tác đang hợp tác' : 'Tạm ngừng hợp tác',
                style: AppTextStyles.caption.copyWith(
                  color: _active ? AppColors.success : AppColors.warning,
                ),
              ),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              activeColor: AppColors.success,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppColors.outline.withOpacity(0.5)),
              ),
              tileColor: AppColors.surface,
            ),
            
            const SizedBox(height: 32),
            
            // Nút lưu
            ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving 
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : Icon(isEditing ? Icons.save : Icons.add),
              label: Text(isEditing ? 'CẬP NHẬT' : 'THÊM ĐỐI TÁC'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isEditing ? AppColors.warning : AppColors.success,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    bool caps = false,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      style: AppTextStyles.body1,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, color: AppColors.primary) : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}
