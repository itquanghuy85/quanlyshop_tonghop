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
      appBar: CustomAppBar.build(
        title: 'Cài đặt Tem sản phẩm',
      ),
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
                      Tab(icon: Icon(Icons.store, size: 18), text: 'Shop'),
                      Tab(icon: Icon(Icons.style, size: 18), text: 'Mẫu Tem'),
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
    // Mở dialog chỉnh sửa template
    showDialog(
      context: context,
      builder: (ctx) => _EditTemplateDialog(
        template: template,
        onSave: (updatedTemplate) async {
          await _labelService.updateTemplate(updatedTemplate);
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Đã cập nhật mẫu "${updatedTemplate.name}"'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
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

/// Dialog chỉnh sửa mẫu tem
class _EditTemplateDialog extends StatefulWidget {
  final LabelTemplate template;
  final Function(LabelTemplate) onSave;

  const _EditTemplateDialog({
    required this.template,
    required this.onSave,
  });

  @override
  State<_EditTemplateDialog> createState() => _EditTemplateDialogState();
}

class _EditTemplateDialogState extends State<_EditTemplateDialog> {
  late TextEditingController _nameCtrl;
  late TextEditingController _cpkFormulaCtrl;
  late LabelFieldSettings _fields;
  late ShopInfoSettings _shopInfo;
  late LabelSize _size;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.template.name);
    _cpkFormulaCtrl = TextEditingController(text: widget.template.cpkFormula ?? 'price + 500000');
    _fields = widget.template.fields;
    _shopInfo = widget.template.shopInfo;
    _size = widget.template.size;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _cpkFormulaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.purple.shade50,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(widget.template.type.icon, style: const TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Chỉnh sửa mẫu tem',
                          style: AppTextStyles.subtitle1.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          widget.template.type.displayName,
                          style: AppTextStyles.caption.copyWith(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tên mẫu
                    TextField(
                      controller: _nameCtrl,
                      decoration: InputDecoration(
                        labelText: 'Tên mẫu tem',
                        prefixIcon: const Icon(Icons.label, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Kích thước
                    Text('Kích thước tem', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: LabelSize.values.map((size) => ChoiceChip(
                        label: Text(size.displayName),
                        selected: _size == size,
                        onSelected: (v) => setState(() => _size = size),
                        selectedColor: Colors.purple.shade100,
                      )).toList(),
                    ),
                    const SizedBox(height: 16),

                    // Công thức CPK
                    if (widget.template.type == LabelType.sales || widget.template.type == LabelType.promotion) ...[
                      TextField(
                        controller: _cpkFormulaCtrl,
                        decoration: InputDecoration(
                          labelText: 'Công thức tính giá CPK',
                          hintText: 'price + 500000 hoặc price * 1.05',
                          prefixIcon: const Icon(Icons.calculate, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '💡 VD: "price + 500000" = Giá + 500k | "price * 1.05" = Giá + 5%',
                        style: AppTextStyles.caption.copyWith(color: Colors.grey, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Thông tin sản phẩm
                    _buildSection('Thông tin sản phẩm', [
                      _buildSwitch('Tên sản phẩm', _fields.showProductName, 
                        (v) => setState(() => _fields = _fields.copyWith(showProductName: v))),
                      _buildSwitch('Mã sản phẩm', _fields.showProductCode, 
                        (v) => setState(() => _fields = _fields.copyWith(showProductCode: v))),
                      _buildSwitch('Mã QR', _fields.showQrCode, 
                        (v) => setState(() => _fields = _fields.copyWith(showQrCode: v))),
                      _buildSwitch('IMEI/Serial', _fields.showImei, 
                        (v) => setState(() => _fields = _fields.copyWith(showImei: v))),
                      _buildSwitch('Dung lượng', _fields.showStorage, 
                        (v) => setState(() => _fields = _fields.copyWith(showStorage: v))),
                      _buildSwitch('Màu sắc', _fields.showColor, 
                        (v) => setState(() => _fields = _fields.copyWith(showColor: v))),
                      _buildSwitch('Tình trạng', _fields.showCondition, 
                        (v) => setState(() => _fields = _fields.copyWith(showCondition: v))),
                    ]),

                    // Giá cả
                    _buildSection('Thông tin giá', [
                      _buildSwitch('Giá KPK (không PK)', _fields.showPriceKPK, 
                        (v) => setState(() => _fields = _fields.copyWith(showPriceKPK: v))),
                      _buildSwitch('Giá CPK (có PK)', _fields.showPriceCPK, 
                        (v) => setState(() => _fields = _fields.copyWith(showPriceCPK: v))),
                      if (widget.template.type == LabelType.promotion) ...[
                        _buildSwitch('Giá gốc (gạch)', _fields.showOriginalPrice, 
                          (v) => setState(() => _fields = _fields.copyWith(showOriginalPrice: v))),
                        _buildSwitch('% Giảm giá', _fields.showDiscountPercent, 
                          (v) => setState(() => _fields = _fields.copyWith(showDiscountPercent: v))),
                      ],
                    ]),

                    // Thông tin shop
                    _buildSection('Thông tin Shop', [
                      _buildSwitch('Tên Shop', _shopInfo.showShopName, 
                        (v) => setState(() => _shopInfo = _shopInfo.copyWith(showShopName: v))),
                      _buildSwitch('Hotline', _shopInfo.showHotline, 
                        (v) => setState(() => _shopInfo = _shopInfo.copyWith(showHotline: v))),
                      _buildSwitch('Slogan', _shopInfo.showSlogan, 
                        (v) => setState(() => _shopInfo = _shopInfo.copyWith(showSlogan: v))),
                      _buildSwitch('Logo', _shopInfo.showLogo, 
                        (v) => setState(() => _shopInfo = _shopInfo.copyWith(showLogo: v))),
                    ]),

                    // Khác
                    _buildSection('Khác', [
                      _buildSwitch('Bảo hành', _fields.showWarranty, 
                        (v) => setState(() => _fields = _fields.copyWith(showWarranty: v))),
                      _buildSwitch('Nhà cung cấp', _fields.showSupplier, 
                        (v) => setState(() => _fields = _fields.copyWith(showSupplier: v))),
                      _buildSwitch('Ngày nhập', _fields.showImportDate, 
                        (v) => setState(() => _fields = _fields.copyWith(showImportDate: v))),
                    ]),
                  ],
                ),
              ),
            ),
            // Actions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('HỦY'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveTemplate,
                      icon: _isSaving 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                      label: Text(_isSaving ? 'Đang lưu...' : 'LƯU MẪU TEM'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            title,
            style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: Colors.purple),
          ),
        ),
        const SizedBox(height: 8),
        ...children,
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildSwitch(String label, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: AppTextStyles.body2),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.purple,
          ),
        ],
      ),
    );
  }

  Future<void> _saveTemplate() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập tên mẫu tem'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final updatedTemplate = widget.template.copyWith(
        name: _nameCtrl.text.trim(),
        size: _size,
        fields: _fields,
        shopInfo: _shopInfo,
        cpkFormula: _cpkFormulaCtrl.text.trim().isEmpty ? null : _cpkFormulaCtrl.text.trim(),
        updatedAt: DateTime.now(),
      );

      widget.onSave(updatedTemplate);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
