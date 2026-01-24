import 'package:flutter/material.dart';

import '../core/utils/money_utils.dart';
import '../models/label_template_model.dart';
import '../models/printer_types.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/label_settings_service.dart';
import '../services/unified_printer_service.dart';
import '../theme/app_text_styles.dart';
import 'printer_selection_dialog.dart';

/// Dialog in tem sản phẩm đa năng
/// - Hỗ trợ nhiều loại mẫu tem: Kiểm kho, Bán hàng, Khuyến mãi, Bảo hành, Tùy chỉnh
/// - Tùy biến nội dung theo từng shop
/// - Preview trước khi in
class PrintLabelDialogV2 extends StatefulWidget {
  final Map<String, dynamic> product;
  final LabelType? initialType;

  const PrintLabelDialogV2({
    super.key,
    required this.product,
    this.initialType,
  });

  /// Hiển thị dialog và trả về true nếu in thành công
  static Future<bool?> show(
    BuildContext context,
    Map<String, dynamic> product, {
    LabelType? initialType,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => PrintLabelDialogV2(
        product: product,
        initialType: initialType,
      ),
    );
  }

  @override
  State<PrintLabelDialogV2> createState() => _PrintLabelDialogV2State();
}

class _PrintLabelDialogV2State extends State<PrintLabelDialogV2> {
  final _labelService = LabelSettingsService();

  List<LabelTemplate> _templates = [];
  LabelTemplate? _selectedTemplate;
  ShopLabelSettings? _shopSettings;
  bool _isLoading = true;
  bool _isPrinting = false;
  int _quantity = 1;

  // Tùy chỉnh
  bool _isCustomMode = false;
  final _priceKPKCtrl = TextEditingController();
  final _priceCPKCtrl = TextEditingController();
  final _originalPriceCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  final _customLine1Ctrl = TextEditingController();
  final _customLine2Ctrl = TextEditingController();
  final _customLine3Ctrl = TextEditingController();

  // Các trường hiển thị (copy từ template, có thể override)
  late LabelFieldSettings _fieldSettings;
  late ShopInfoSettings _shopInfoSettings;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final templates = await _labelService.getTemplates();
      final shopSettings = await _labelService.getShopLabelSettings();
      final defaultTemplate = await _labelService.getDefaultTemplate();

      // Chọn template theo initialType nếu có
      LabelTemplate selectedTemplate = defaultTemplate;
      if (widget.initialType != null) {
        final found = templates.firstWhere(
          (t) => t.type == widget.initialType,
          orElse: () => defaultTemplate,
        );
        selectedTemplate = found;
      }

      setState(() {
        _templates = templates;
        _shopSettings = shopSettings;
        _selectedTemplate = selectedTemplate;
        _isLoading = false;
        _initFieldsFromTemplate(selectedTemplate);
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  void _initFieldsFromTemplate(LabelTemplate template) {
    _fieldSettings = template.fields;
    _shopInfoSettings = template.shopInfo;

    final price = widget.product['price'] ?? 0;
    _priceKPKCtrl.text = MoneyUtils.formatVND(price);

    // Tính CPK
    final cpk = _shopSettings?.calculateCPK(price) ?? (price + 500000);
    _priceCPKCtrl.text = MoneyUtils.formatVND(cpk);

    // Giá gốc (nếu có khuyến mãi)
    _originalPriceCtrl.text = '';
    _discountCtrl.text = '';
  }

  @override
  void dispose() {
    _priceKPKCtrl.dispose();
    _priceCPKCtrl.dispose();
    _originalPriceCtrl.dispose();
    _discountCtrl.dispose();
    _customLine1Ctrl.dispose();
    _customLine2Ctrl.dispose();
    _customLine3Ctrl.dispose();
    super.dispose();
  }

  int _parsePrice(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(clean) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        constraints: const BoxConstraints(maxWidth: 550, maxHeight: 750),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTemplateSelector(),
                          const SizedBox(height: 12),
                          _buildModeToggle(),
                          const SizedBox(height: 12),
                          if (_isCustomMode) ...[
                            _buildFieldOptions(),
                            const SizedBox(height: 12),
                            _buildPriceInputs(),
                            const SizedBox(height: 12),
                            _buildCustomLines(),
                            const SizedBox(height: 12),
                          ],
                          _buildQuantitySelector(),
                          const SizedBox(height: 16),
                          _buildPreview(),
                        ],
                      ),
                    ),
                  ),
                  _buildActions(),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.qr_code_2, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IN TEM SẢN PHẨM',
                  style: AppTextStyles.headline4.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  widget.product['name'] ?? 'N/A',
                  style: AppTextStyles.caption.copyWith(color: Colors.white70),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.style, size: 18, color: Colors.purple),
            const SizedBox(width: 8),
            Text(
              'CHỌN MẪU TEM',
              style: AppTextStyles.subtitle2.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _templates.length,
            itemBuilder: (ctx, i) {
              final template = _templates[i];
              final isSelected = _selectedTemplate?.id == template.id;
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTemplate = template;
                    _initFieldsFromTemplate(template);
                  });
                },
                child: Container(
                  width: 90,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.purple.shade50 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? Colors.purple : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        template.type.icon,
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        template.name,
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.purple : Colors.grey.shade700,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeButton(
              'NHANH',
              'In theo mẫu đã chọn',
              Icons.flash_on,
              !_isCustomMode,
              () => setState(() => _isCustomMode = false),
            ),
          ),
          Expanded(
            child: _modeButton(
              'TÙY CHỈNH',
              'Sửa nội dung trước khi in',
              Icons.edit_note,
              _isCustomMode,
              () => setState(() => _isCustomMode = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(
      String title, String subtitle, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.purple : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey, size: 20),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.caption.copyWith(
                    color: selected ? Colors.white : Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: selected ? Colors.white70 : Colors.grey,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldOptions() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.checklist, size: 18, color: Colors.blue),
              const SizedBox(width: 8),
              Text(
                'THÔNG TIN HIỂN THỊ',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 0,
            children: [
              _fieldChip('Tên SP', _fieldSettings.showProductName, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showProductName: v));
              }),
              _fieldChip('Mã SP', _fieldSettings.showProductCode, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showProductCode: v));
              }),
              _fieldChip('QR Code', _fieldSettings.showQrCode, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showQrCode: v));
              }),
              _fieldChip('Giá KPK', _fieldSettings.showPriceKPK, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showPriceKPK: v));
              }),
              _fieldChip('Giá CPK', _fieldSettings.showPriceCPK, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showPriceCPK: v));
              }),
              _fieldChip('Tình trạng', _fieldSettings.showCondition, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showCondition: v));
              }),
              _fieldChip('Bảo hành', _fieldSettings.showWarranty, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showWarranty: v));
              }),
              _fieldChip('IMEI', _fieldSettings.showImei, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showImei: v));
              }),
              _fieldChip('Dung lượng', _fieldSettings.showStorage, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showStorage: v));
              }),
              _fieldChip('Màu sắc', _fieldSettings.showColor, (v) {
                setState(() => _fieldSettings = _fieldSettings.copyWith(showColor: v));
              }),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Thông tin Shop:',
            style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            runSpacing: 0,
            children: [
              _fieldChip('Tên shop', _shopInfoSettings.showShopName, (v) {
                setState(() => _shopInfoSettings = _shopInfoSettings.copyWith(showShopName: v));
              }),
              _fieldChip('Hotline', _shopInfoSettings.showHotline, (v) {
                setState(() => _shopInfoSettings = _shopInfoSettings.copyWith(showHotline: v));
              }),
              _fieldChip('Slogan', _shopInfoSettings.showSlogan, (v) {
                setState(() => _shopInfoSettings = _shopInfoSettings.copyWith(showSlogan: v));
              }),
            ],
          ),
        ],
      ),
    );
  }

  Widget _fieldChip(String label, bool value, Function(bool) onChanged) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: value,
      onSelected: onChanged,
      selectedColor: Colors.purple.shade100,
      checkmarkColor: Colors.purple,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  Widget _buildPriceInputs() {
    final isPromotion = _selectedTemplate?.type == LabelType.promotion;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_money, size: 18, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'GIÁ HIỂN THỊ',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '📌 KPK = Không Phụ Kiện | CPK = Có Phụ Kiện',
            style: AppTextStyles.caption.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _priceField('Giá KPK', _priceKPKCtrl, Colors.blue),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _priceField('Giá CPK', _priceCPKCtrl, Colors.red),
              ),
            ],
          ),
          if (isPromotion) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _priceField('Giá gốc (gạch)', _originalPriceCtrl, Colors.grey),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _discountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '% Giảm',
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: Colors.white,
                      suffixText: '%',
                      suffixStyle: TextStyle(color: Colors.green.shade700),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _priceField(String label, TextEditingController controller, Color color) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: color, fontSize: 12),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
        suffixText: 'đ',
        suffixStyle: TextStyle(color: color),
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildCustomLines() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_fields, size: 18, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'NỘI DUNG TÙY BIẾN',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
              const Spacer(),
              Text(
                'Cho giấy lớn',
                style: AppTextStyles.caption.copyWith(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _customLineField('Dòng 1', _customLine1Ctrl, _shopSettings?.slogan ?? ''),
          const SizedBox(height: 6),
          _customLineField('Dòng 2', _customLine2Ctrl, ''),
          const SizedBox(height: 6),
          _customLineField('Dòng 3', _customLine3Ctrl, ''),
        ],
      ),
    );
  }

  Widget _customLineField(String label, TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint.isNotEmpty ? 'VD: $hint' : null,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
      ),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _buildQuantitySelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.print, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          const Text('Số lượng:', style: TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          IconButton(
            onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
            icon: const Icon(Icons.remove_circle_outline),
            color: Colors.purple,
            iconSize: 28,
          ),
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Text(
              '$_quantity',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed: _quantity < 99 ? () => setState(() => _quantity++) : null,
            icon: const Icon(Icons.add_circle_outline),
            color: Colors.purple,
            iconSize: 28,
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final template = _selectedTemplate;
    if (template == null) return const SizedBox.shrink();

    final product = widget.product;
    final shopName = _shopSettings?.shopName ?? '';
    final hotline = _shopSettings?.hotline ?? '';
    final slogan = _shopSettings?.slogan ?? '';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.preview, size: 18, color: Colors.grey),
              const SizedBox(width: 8),
              Text(
                'XEM TRƯỚC',
                style: AppTextStyles.subtitle2.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
              ),
              const Spacer(),
              Text(
                template.size.displayName,
                style: AppTextStyles.caption.copyWith(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 280,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade400),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header shop
                  if (_shopInfoSettings.showShopName || _shopInfoSettings.showHotline)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
                      ),
                      child: Column(
                        children: [
                          if (_shopInfoSettings.showShopName && shopName.isNotEmpty)
                            Text(
                              shopName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          if (_shopInfoSettings.showHotline && hotline.isNotEmpty)
                            Text(
                              '📞 $hotline',
                              style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                            ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 6),

                  // Tên sản phẩm
                  if (_fieldSettings.showProductName)
                    Text(
                      product['name'] ?? 'Tên sản phẩm',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                  // Thông số
                  if (_fieldSettings.showStorage || _fieldSettings.showColor || _fieldSettings.showCondition)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if (_fieldSettings.showStorage) product['capacity'] ?? '',
                          if (_fieldSettings.showColor) product['color'] ?? '',
                          if (_fieldSettings.showCondition) product['condition'] ?? '',
                        ].where((s) => s.isNotEmpty).join(' | '),
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                      ),
                    ),

                  const SizedBox(height: 6),

                  // Giá
                  if (_fieldSettings.showPriceKPK || _fieldSettings.showPriceCPK)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (_fieldSettings.showPriceKPK)
                            Column(
                              children: [
                                const Text('KPK', style: TextStyle(fontSize: 8, color: Colors.blue)),
                                Text(
                                  _formatPreviewPrice(_priceKPKCtrl.text),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Colors.blue,
                                  ),
                                ),
                              ],
                            ),
                          if (_fieldSettings.showPriceKPK && _fieldSettings.showPriceCPK)
                            Container(width: 1, height: 20, color: Colors.grey.shade300),
                          if (_fieldSettings.showPriceCPK)
                            Column(
                              children: [
                                const Text('CPK', style: TextStyle(fontSize: 8, color: Colors.red)),
                                Text(
                                  _formatPreviewPrice(_priceCPKCtrl.text),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: Colors.red,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),

                  // Bảo hành
                  if (_fieldSettings.showWarranty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '🛡️ BH: ${product['warrantyPeriod'] ?? '6 tháng'}',
                        style: TextStyle(fontSize: 9, color: Colors.green.shade700),
                      ),
                    ),

                  // IMEI
                  if (_fieldSettings.showImei && product['imei'] != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'IMEI: ${product['imei']}',
                        style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
                      ),
                    ),

                  const SizedBox(height: 6),

                  // QR + Mã SP
                  if (_fieldSettings.showQrCode || _fieldSettings.showProductCode)
                    Row(
                      children: [
                        if (_fieldSettings.showQrCode)
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade400),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Icon(Icons.qr_code, size: 40),
                          ),
                        if (_fieldSettings.showQrCode && _fieldSettings.showProductCode)
                          const SizedBox(width: 8),
                        if (_fieldSettings.showProductCode)
                          Flexible(
                            child: Text(
                              'Mã: ${product['id'] ?? product['productCode'] ?? 'N/A'}',
                              style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),

                  // Custom lines
                  if (_customLine1Ctrl.text.isNotEmpty || _customLine2Ctrl.text.isNotEmpty || _customLine3Ctrl.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_customLine1Ctrl.text.isNotEmpty)
                            Text(_customLine1Ctrl.text, style: const TextStyle(fontSize: 9)),
                          if (_customLine2Ctrl.text.isNotEmpty)
                            Text(_customLine2Ctrl.text, style: const TextStyle(fontSize: 9)),
                          if (_customLine3Ctrl.text.isNotEmpty)
                            Text(_customLine3Ctrl.text, style: const TextStyle(fontSize: 9)),
                        ],
                      ),
                    ),

                  // Slogan
                  if (_shopInfoSettings.showSlogan && slogan.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Center(
                        child: Text(
                          '"$slogan"',
                          style: TextStyle(
                            fontSize: 9,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPreviewPrice(String text) {
    final value = _parsePrice(text);
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}tr';
    }
    return MoneyUtils.formatVND(value);
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context, false),
              icon: const Icon(Icons.close),
              label: const Text('HỦY'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _isPrinting ? null : _handlePrint,
              icon: _isPrinting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.print),
              label: Text(_isPrinting ? 'ĐANG IN...' : 'IN TEM ($_quantity)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePrint() async {
    setState(() => _isPrinting = true);

    // Lưu printer config để sử dụng
    PrinterType? printerType;
    dynamic bluetoothPrinter;
    String? wifiIp;

    try {
      // Kiểm tra kết nối máy in
      final isConnected = await BluetoothPrinterService.isConnected();
      if (!isConnected) {
        final result = await showDialog<Map<String, dynamic>?>(
          context: context,
          builder: (ctx) => const PrinterSelectionDialog(),
        );
        if (result == null) {
          setState(() => _isPrinting = false);
          return;
        }
        // Lấy cấu hình từ dialog
        printerType = result['type'] as PrinterType?;
        bluetoothPrinter = result['bluetoothPrinter'];
        wifiIp = result['wifiIp'] as String?;
      }

      // Chuẩn bị dữ liệu in
      final printData = _buildPrintData();

      // In tem
      final printerService = UnifiedPrinterService();
      bool success = true;

      for (int i = 0; i < _quantity; i++) {
        final ok = await printerService.printProductLabelAdvanced(
          printData,
          printerType: printerType,
          bluetoothPrinter: bluetoothPrinter,
          wifiIp: wifiIp,
        );
        if (!ok) {
          success = false;
          break;
        }
        if (i < _quantity - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Đã in $_quantity tem thành công!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Có lỗi khi in tem!'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  LabelPrintData _buildPrintData() {
    return LabelPrintData(
      template: _selectedTemplate!.copyWith(
        fields: _fieldSettings,
        shopInfo: _shopInfoSettings,
      ),
      product: widget.product,
      quantity: _quantity,
      customPriceKPK: _parsePrice(_priceKPKCtrl.text),
      customPriceCPK: _parsePrice(_priceCPKCtrl.text),
      originalPrice: _parsePrice(_originalPriceCtrl.text),
      discountPercent: int.tryParse(_discountCtrl.text),
      additionalLines: [
        _customLine1Ctrl.text,
        _customLine2Ctrl.text,
        _customLine3Ctrl.text,
      ].where((s) => s.isNotEmpty).toList(),
    );
  }
}
