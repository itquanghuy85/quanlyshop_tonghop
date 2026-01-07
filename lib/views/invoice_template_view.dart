import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../widgets/validated_text_field.dart';

class InvoiceTemplateView extends StatefulWidget {
  const InvoiceTemplateView({super.key});

  @override
  State<InvoiceTemplateView> createState() => _InvoiceTemplateViewState();
}

class _InvoiceTemplateViewState extends State<InvoiceTemplateView> {
  final _headerController = TextEditingController();
  final _bodyController = TextEditingController();
  final _footerController = TextEditingController();

  String _previewText = '';
  String _qrData = '';

  @override
  void initState() {
    super.initState();
    _loadTemplate();
    _updatePreview();
  }

  @override
  void dispose() {
    _headerController.dispose();
    _bodyController.dispose();
    _footerController.dispose();
    super.dispose();
  }

  Future<void> _loadTemplate() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _headerController.text = prefs.getString('invoice_header') ?? 'CỬA HÀNG SỬA CHỮA ĐIỆN THOẠI HULUCA\nĐịa chỉ: 123 Đường ABC, Quận XYZ, TP.HCM\nĐiện thoại: 0123 456 789 | Email: info@huluca.com\n\n================================\n        HÓA ĐƠN THANH TOÁN\n================================';
      _bodyController.text = prefs.getString('invoice_body') ?? 'Ngày: {date}\nGiờ: {time}\n\nKhách hàng: {customerName}\nSố điện thoại: {customerPhone}\nĐịa chỉ: {customerAddress}\n\nDịch vụ: {service}\nMô tả: {description}\n\nGiá: {price} VND\n\n================================\nTỔNG CỘNG: {total} VND\n================================\n\nThanh toán: {paymentMethod}\nTrạng thái: {status}';
      _footerController.text = prefs.getString('invoice_footer') ?? '================================\nCảm ơn quý khách đã tin tưởng HULUCA!\nHẹn gặp lại quý khách lần sau.\n\nHotline: 0123 456 789\nWebsite: www.huluca.com\n================================';
    });
  }

  Future<void> _saveTemplate() async {
    final messenger = ScaffoldMessenger.of(context);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('invoice_header', _headerController.text);
    await prefs.setString('invoice_body', _bodyController.text);
    await prefs.setString('invoice_footer', _footerController.text);
    messenger.showSnackBar(
      const SnackBar(content: Text('Đã lưu mẫu hóa đơn')),
    );
  }

  void _updatePreview() {
    setState(() {
      _previewText = '${_headerController.text}\n\n${_bodyController.text}\n\n${_footerController.text}';
    });
  }

  void _generateQR() {
    // Sample order data
    final sampleOrder = {
      'orderId': 'ORD001',
      'customerName': 'Nguyễn Văn A',
      'customerPhone': '0123456789',
      'service': 'Sửa màn hình iPhone 12',
      'price': '2000000',
      'total': '2000000',
    };
    setState(() {
      _qrData = jsonEncode(sampleOrder);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TẠO MẪU HÓA ĐƠN'),
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
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Header:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ValidatedTextField(
                      controller: _headerController,
                      label: "HEADER HÓA ĐƠN",
                      maxLength: 500,
                      uppercase: true,
                      onChanged: (_) => _updatePreview(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Body (sử dụng placeholders như {customerName}, {total}):', style: TextStyle(fontWeight: FontWeight.bold)),
                    ValidatedTextField(
                      controller: _bodyController,
                      label: "NỘI DUNG CHÍNH",
                      maxLength: 2000,
                      uppercase: true,
                      onChanged: (_) => _updatePreview(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Footer:', style: TextStyle(fontWeight: FontWeight.bold)),
                    ValidatedTextField(
                      controller: _footerController,
                      label: "FOOTER HÓA ĐƠN",
                      maxLength: 500,
                      uppercase: true,
                      onChanged: (_) => _updatePreview(),
                    ),
                    const SizedBox(height: 16),
                    const Text('Preview:', style: TextStyle(fontWeight: FontWeight.bold)),
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
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _generateQR,
                      child: const Text('TẠO QR CHO ĐƠN HÀNG MẪU'),
                    ),
                    if (_qrData.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('QR Code (quét để xem thông tin đơn hàng):', style: TextStyle(fontWeight: FontWeight.bold)),
                      Center(
                        child: QrImageView(
                          data: _qrData,
                          version: QrVersions.auto,
                          size: 200.0,
                        ),
                      ),
                    ],
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
