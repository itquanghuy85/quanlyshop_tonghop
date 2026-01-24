import 'package:flutter/material.dart';

import '../models/label_template_model.dart';
import '../services/label_settings_service.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';

/// Màn hình cài đặt tem sản phẩm cho shop
class LabelSettingsView extends StatefulWidget {
  const LabelSettingsView({super.key});

  @override
  State<LabelSettingsView> createState() => _LabelSettingsViewState();
}

class _LabelSettingsViewState extends State<LabelSettingsView> with SingleTickerProviderStateMixin {
  final _labelService = LabelSettingsService();
  late TabController _tabController;

  List<LabelTemplate> _templates = [];
  ShopLabelSettings? _shopSettings;
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers for shop settings
  final _shopNameCtrl = TextEditingController();
  final _hotlineCtrl = TextEditingController();
  final _sloganCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _cpkFormulaCtrl = TextEditingController();
  final _fixedLine1Ctrl = TextEditingController();
  final _fixedLine2Ctrl = TextEditingController();
  final _fixedLine3Ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final templates = await _labelService.getTemplates();
      final shopSettings = await _labelService.getShopLabelSettings();

      setState(() {
        _templates = templates;
        _shopSettings = shopSettings;
        _isLoading = false;

        // Populate controllers
        _shopNameCtrl.text = shopSettings.shopName;
        _hotlineCtrl.text = shopSettings.hotline;
        _sloganCtrl.text = shopSettings.slogan;
        _addressCtrl.text = shopSettings.address;
        _cpkFormulaCtrl.text = shopSettings.cpkFormula;

        if (shopSettings.fixedLines.isNotEmpty) {
          _fixedLine1Ctrl.text = shopSettings.fixedLines.elementAtOrNull(0) ?? '';
          _fixedLine2Ctrl.text = shopSettings.fixedLines.elementAtOrNull(1) ?? '';
          _fixedLine3Ctrl.text = shopSettings.fixedLines.elementAtOrNull(2) ?? '';
        }
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveShopSettings() async {
    setState(() => _isSaving = true);

    try {
      final fixedLines = <String>[];
      if (_fixedLine1Ctrl.text.trim().isNotEmpty) fixedLines.add(_fixedLine1Ctrl.text.trim());
      if (_fixedLine2Ctrl.text.trim().isNotEmpty) fixedLines.add(_fixedLine2Ctrl.text.trim());
      if (_fixedLine3Ctrl.text.trim().isNotEmpty) fixedLines.add(_fixedLine3Ctrl.text.trim());

      final newSettings = ShopLabelSettings(
        shopName: _shopNameCtrl.text.trim(),
        hotline: _hotlineCtrl.text.trim(),
        slogan: _sloganCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        cpkFormula: _cpkFormulaCtrl.text.trim(),
        fixedLines: fixedLines,
        autoCalculateCPK: _shopSettings?.autoCalculateCPK ?? true,
      );

      await _labelService.saveShopLabelSettings(newSettings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã lưu cài đặt tem!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _shopNameCtrl.dispose();
    _hotlineCtrl.dispose();
    _sloganCtrl.dispose();
    _addressCtrl.dispose();
    _cpkFormulaCtrl.dispose();
    _fixedLine1Ctrl.dispose();
    _fixedLine2Ctrl.dispose();
    _fixedLine3Ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CustomAppBar(title: 'Cài đặt Tem sản phẩm'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: Colors.purple.shade50,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Colors.purple,
                    unselectedLabelColor: Colors.grey,
                    indicatorColor: Colors.purple,
                    tabs: const [
                      Tab(icon: Icon(Icons.store), text: 'Thông tin Shop'),
                      Tab(icon: Icon(Icons.style), text: 'Mẫu Tem'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildShopSettingsTab(),
                      _buildTemplatesTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildShopSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Thông tin hiển thị trên tem', Icons.info_outline),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _shopNameCtrl,
            label: 'Tên Shop',
            hint: 'VD: HULUCA MOBILE',
            icon: Icons.store,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _hotlineCtrl,
            label: 'Hotline',
            hint: 'VD: 0909 123 456',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _sloganCtrl,
            label: 'Slogan',
            hint: 'VD: Cam kết giá tốt nhất thị trường',
            icon: Icons.format_quote,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _addressCtrl,
            label: 'Địa chỉ (tùy chọn)',
            hint: 'VD: 123 ABC, Q1, HCM',
            icon: Icons.location_on,
          ),

          const SizedBox(height: 24),
          _sectionTitle('Cài đặt giá CPK', Icons.attach_money),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '📌 Công thức tính giá CPK (Có Phụ Kiện):',
                  style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                _buildTextField(
                  controller: _cpkFormulaCtrl,
                  label: 'Công thức',
                  hint: 'price + 500000 hoặc price * 1.05',
                  icon: Icons.calculate,
                ),
                const SizedBox(height: 8),
                Text(
                  'VD: "price + 500000" = Giá bán + 500k\n'
                  'VD: "price * 1.05" = Giá bán + 5%',
                  style: AppTextStyles.caption.copyWith(color: Colors.grey),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
          _sectionTitle('Nội dung cố định trên tem', Icons.text_fields),
          const SizedBox(height: 8),
          Text(
            'Các dòng text này sẽ hiển thị mặc định trên mọi tem (nếu được bật)',
            style: AppTextStyles.caption.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _fixedLine1Ctrl,
            label: 'Dòng 1',
            hint: 'VD: Cam kết chính hãng 100%',
            icon: Icons.text_format,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _fixedLine2Ctrl,
            label: 'Dòng 2',
            hint: 'VD: Đổi trả trong 7 ngày',
            icon: Icons.text_format,
          ),
          const SizedBox(height: 8),
          _buildTextField(
            controller: _fixedLine3Ctrl,
            label: 'Dòng 3',
            hint: 'VD: Hỗ trợ trả góp 0%',
            icon: Icons.text_format,
          ),

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _saveShopSettings,
              icon: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? 'Đang lưu...' : 'LƯU CÀI ĐẶT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTemplatesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _templates.length,
      itemBuilder: (ctx, i) {
        final template = _templates[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: _getTemplateColor(template.type).withAlpha(30),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  template.type.icon,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            title: Text(
              template.name,
              style: AppTextStyles.subtitle1.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '${template.type.displayName} • ${template.size.displayName}',
              style: AppTextStyles.caption,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (template.isDefault)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Mặc định',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (template.type == LabelType.custom)
                  IconButton(
                    onPressed: () => _deleteTemplate(template),
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                  ),
              ],
            ),
            onTap: () => _editTemplate(template),
          ),
        );
      },
    );
  }

  Color _getTemplateColor(LabelType type) {
    switch (type) {
      case LabelType.inventory:
        return Colors.blue;
      case LabelType.sales:
        return Colors.green;
      case LabelType.promotion:
        return Colors.orange;
      case LabelType.warranty:
        return Colors.purple;
      case LabelType.custom:
        return Colors.grey;
    }
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.purple),
        const SizedBox(width: 8),
        Text(
          title,
          style: AppTextStyles.subtitle1.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.purple,
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey.shade50,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
    );
  }

  void _editTemplate(LabelTemplate template) {
    // TODO: Mở dialog chỉnh sửa template
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Chỉnh sửa mẫu "${template.name}" - Coming soon!')),
    );
  }

  void _deleteTemplate(LabelTemplate template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa mẫu tem?'),
        content: Text('Bạn có chắc muốn xóa mẫu "${template.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('XÓA'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _labelService.deleteTemplate(template.id);
      await _loadData();
    }
  }
}
