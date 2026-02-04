import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/validated_text_field.dart';

class SaleInvoiceTemplateView extends StatefulWidget {
  const SaleInvoiceTemplateView({super.key});

  @override
  State<SaleInvoiceTemplateView> createState() => _SaleInvoiceTemplateViewState();
}

class _SaleInvoiceTemplateViewState extends State<SaleInvoiceTemplateView> {
  final _headerController = TextEditingController();
  final _bodyController = TextEditingController();
  final _footerController = TextEditingController();
  final _headerFocus = FocusNode();
  final _bodyFocus = FocusNode();
  final _footerFocus = FocusNode();
  bool _useTemplate = false;
  String _previewText = '';

  @override
  void initState() {
    super.initState();
    _loadTemplate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).unfocus();
    });
  }

  @override
  void dispose() {
    _headerFocus.dispose();
    _bodyFocus.dispose();
    _footerFocus.dispose();
    _headerController.dispose();
    _bodyController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useTemplate = prefs.getBool('sale_invoice_use_template') ?? false;
      _headerController.text = prefs.getString('sale_invoice_header') ??
          '=== HÓA ĐƠN BÁN HÀNG ===\n{shopName}\n{shopAddr}\nHotline: {shopPhone}\n--------------------------------';
      _bodyController.text = prefs.getString('sale_invoice_body') ??
          'Mã HD: {code}\nNgày: {date} {time}\n\nKhách: {customerName}\nSĐT: {customerPhone}\nĐ/c: {customerAddress}\n\nSản phẩm: {products}\nIMEI: {imeis}\nBảo hành: {warranty}\n\nTổng: {total} đ\nGiảm: {discount} đ\nThực thu: {finalTotal} đ\nThanh toán: {paymentMethod}\nNV bán: {sellerName}\n\nTRẢ GÓP\nĐặt cọc: {downPayment} đ ({downPaymentMethod})\nVay NH1: {loanAmount} đ - {bankName}\nVay NH2: {loanAmount2} đ - {bankName2}\nKỳ hạn: {installmentTerm}\nCòn nợ: {remainingDebt} đ\n[QR]{qrData}';
      _footerController.text = prefs.getString('sale_invoice_footer') ??
          '--------------------------------\nCảm ơn quý khách!';
      _updatePreview();
    });
  }

  Future<void> _saveTemplate() async {
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sale_invoice_use_template', _useTemplate);
    await prefs.setString('sale_invoice_header', _headerController.text);
    await prefs.setString('sale_invoice_body', _bodyController.text);
    await prefs.setString('sale_invoice_footer', _footerController.text);
    messenger.showSnackBar(const SnackBar(content: Text('Đã lưu mẫu hóa đơn bán')));
  }

  String _applyTemplate(String template, Map<String, String> data) {
    var result = template;
    data.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }

  void _insertNewLine(TextEditingController controller) {
    final selection = controller.selection;
    final text = controller.text;
    final insertAt = selection.isValid ? selection.start : text.length;
    final newText = text.replaceRange(insertAt, insertAt, '\n');
    controller.text = newText;
    controller.selection = TextSelection.collapsed(offset: insertAt + 1);
    _updatePreview();
  }


  void _updatePreview() {
    final sample = <String, String>{
      'shopName': 'SHOP NEW',
      'shopAddr': '123 Đường ABC, Q1, TP.HCM',
      'shopPhone': '0123 456 789',
      'code': 'SALE_001',
      'date': '02/02/2026',
      'time': '10:30',
      'customerName': 'Nguyễn Văn B',
      'customerPhone': '0912 222 333',
      'customerAddress': 'Q7, TP.HCM',
      'products': 'iPhone 12 Pro, AirPods Pro',
      'imeis': '356789012345678, 778899001122334',
      'warranty': '12 tháng',
      'total': '35.000.000',
      'discount': '500.000',
      'finalTotal': '34.500.000',
      'paymentMethod': 'CHUYỂN KHOẢN',
      'sellerName': 'NV01',
      'downPayment': '5.000.000',
      'downPaymentMethod': 'TIỀN MẶT',
      'loanAmount': '20.000.000',
      'loanAmount2': '9.500.000',
      'installmentTerm': '12 tháng',
      'bankName': 'FE CREDIT',
      'bankName2': 'HOME CREDIT',
      'remainingDebt': '29.500.000',
    };

    final templateText = [
      _headerController.text,
      _bodyController.text,
      _footerController.text,
    ].where((s) => s.trim().isNotEmpty).join('\n');

    setState(() {
      _previewText = _applyTemplate(templateText, sample);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MẪU HÓA ĐƠN BÁN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveTemplate,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SwitchListTile(
              value: _useTemplate,
              onChanged: (v) => setState(() => _useTemplate = v),
              title: const Text('Áp dụng mẫu này khi in'),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Header:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _insertNewLine(_headerController),
                        icon: const Icon(Icons.keyboard_return, size: 16),
                        label: const Text('Xuống dòng'),
                      ),
                    ),
                    ValidatedTextField(
                      controller: _headerController,
                      label: 'HEADER',
                      maxLength: 800,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      uppercase: false,
                      focusNode: _headerFocus,
                      onChanged: (_) => _updatePreview(),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Body (placeholder: {code}, {products}, {total}...)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _insertNewLine(_bodyController),
                        icon: const Icon(Icons.keyboard_return, size: 16),
                        label: const Text('Xuống dòng'),
                      ),
                    ),
                    ValidatedTextField(
                      controller: _bodyController,
                      label: 'NỘI DUNG',
                      maxLength: 3000,
                      maxLines: 12,
                      keyboardType: TextInputType.multiline,
                      uppercase: false,
                      focusNode: _bodyFocus,
                      onChanged: (_) => _updatePreview(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Footer:', style: TextStyle(fontWeight: FontWeight.bold)),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _insertNewLine(_footerController),
                        icon: const Icon(Icons.keyboard_return, size: 16),
                        label: const Text('Xuống dòng'),
                      ),
                    ),
                    ValidatedTextField(
                      controller: _footerController,
                      label: 'FOOTER',
                      maxLength: 800,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      uppercase: false,
                      focusNode: _footerFocus,
                      onChanged: (_) => _updatePreview(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Xem trước (dữ liệu mẫu):', style: TextStyle(fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _previewText,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
