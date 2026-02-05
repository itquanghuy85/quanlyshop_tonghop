import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

import '../models/printer_types.dart';
import '../utils/money_utils.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/unified_printer_service.dart';
import '../widgets/printer_selection_dialog.dart';

class SaleInvoicePreviewView extends StatefulWidget {
  final Map<String, dynamic> saleData;
  final PaperSize paper;

  const SaleInvoicePreviewView({
    super.key,
    required this.saleData,
    this.paper = PaperSize.mm58,
  });

  @override
  State<SaleInvoicePreviewView> createState() => _SaleInvoicePreviewViewState();
}

class _SaleInvoicePreviewViewState extends State<SaleInvoicePreviewView> {
  bool _isLoading = true;
  bool _useTemplate = false;
  String _previewText = '';

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  String _applyTemplate(String template, Map<String, String> data) {
    var result = template;
    data.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }

  Future<void> _loadPreview() async {
    final prefs = await SharedPreferences.getInstance();
    final useTemplate = prefs.getBool('sale_invoice_use_template') ?? false;
    final header = prefs.getString('sale_invoice_header') ??
        '=== HÓA ĐƠN BÁN HÀNG ===\n{shopName}\n{shopAddr}\nHotline: {shopPhone}\n--------------------------------';
    final body = prefs.getString('sale_invoice_body') ??
      'Mã HD: {code}\nNgày: {date} {time}\n\nKhách: {customerName}\nSĐT: {customerPhone}\nĐ/c: {customerAddress}\n\nSản phẩm: {products}\nIMEI: {imeis}\nBảo hành: {warranty}\n\nTổng: {total} đ\nGiảm: {discount} đ\nThực thu: {finalTotal} đ\nThanh toán: {paymentMethod}\nNV bán: {sellerName}\n\nTRẢ GÓP\nĐặt cọc: {downPayment} đ ({downPaymentMethod})\nVay NH1: {loanAmount} đ - {bankName}\nVay NH2: {loanAmount2} đ - {bankName2}\nKỳ hạn: {installmentTerm}\nCòn nợ: {remainingDebt} đ\n[QR]{qrData}';
    final footer = prefs.getString('sale_invoice_footer') ??
        '--------------------------------\nCảm ơn quý khách!';

    final soldAtRaw = widget.saleData['soldAt'];
    int soldAt = 0;
    if (soldAtRaw != null) {
      soldAt = soldAtRaw is int ? soldAtRaw : int.tryParse(soldAtRaw.toString()) ?? 0;
    }
    final soldAtDate = soldAt > 0 ? DateTime.fromMillisecondsSinceEpoch(soldAt) : DateTime.now();

    final productNames = widget.saleData['productNames'];
    final productImeis = widget.saleData['productImeis'];
    final names = productNames is List
      ? productNames.map((e) => e?.toString() ?? 'N/A').toList()
      : productNames is String
        ? productNames
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList()
        : <String>[];
    final imeis = productImeis is List
      ? productImeis.map((e) => e?.toString() ?? '').toList()
      : productImeis is String
        ? productImeis
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList()
        : <String>[];

    final totalPrice = widget.saleData['totalPrice'];
    final priceValue = totalPrice is num
        ? totalPrice.toInt()
        : int.tryParse(totalPrice?.toString() ?? '0') ?? 0;

    final data = <String, String>{
      'shopName': widget.saleData['shopName']?.toString() ?? 'SHOP NEW',
      'shopAddr': widget.saleData['shopAddr']?.toString() ?? '',
      'shopPhone': widget.saleData['shopPhone']?.toString() ?? '',
      'code': widget.saleData['firestoreId']?.toString() ?? 'N/A',
      'date': DateFormat('dd/MM/yyyy').format(soldAtDate),
      'time': DateFormat('HH:mm').format(soldAtDate),
      'customerName': widget.saleData['customerName']?.toString() ?? 'Khach le',
      'customerPhone': widget.saleData['customerPhone']?.toString() ?? '',
      'customerAddress': widget.saleData['customerAddress']?.toString() ?? '',
      'products': names.join(', '),
      'imeis': imeis.where((e) => e.trim().isNotEmpty).join(', '),
      'warranty': widget.saleData['warranty']?.toString() ?? '',
      'total': MoneyUtils.formatVND(priceValue),
      'paymentMethod': widget.saleData['paymentMethod']?.toString() ?? '',
      'sellerName': widget.saleData['sellerName']?.toString() ?? '',
      'discount': MoneyUtils.formatVND(
        widget.saleData['discount'] is num
            ? (widget.saleData['discount'] as num).toInt()
            : int.tryParse(widget.saleData['discount']?.toString() ?? '0') ??
                0,
      ),
      'finalTotal': MoneyUtils.formatVND(
        widget.saleData['finalTotal'] is num
            ? (widget.saleData['finalTotal'] as num).toInt()
            : int.tryParse(widget.saleData['finalTotal']?.toString() ?? '0') ??
                priceValue,
      ),
      'downPayment': MoneyUtils.formatVND(
        widget.saleData['downPayment'] is num
            ? (widget.saleData['downPayment'] as num).toInt()
            : int.tryParse(widget.saleData['downPayment']?.toString() ?? '0') ??
                0,
      ),
      'downPaymentMethod': widget.saleData['downPaymentMethod']?.toString() ?? '',
      'loanAmount': MoneyUtils.formatVND(
        widget.saleData['loanAmount'] is num
            ? (widget.saleData['loanAmount'] as num).toInt()
            : int.tryParse(widget.saleData['loanAmount']?.toString() ?? '0') ??
                0,
      ),
      'loanAmount2': MoneyUtils.formatVND(
        widget.saleData['loanAmount2'] is num
            ? (widget.saleData['loanAmount2'] as num).toInt()
            : int.tryParse(widget.saleData['loanAmount2']?.toString() ?? '0') ??
                0,
      ),
      'installmentTerm': widget.saleData['installmentTerm']?.toString() ?? '',
      'bankName': widget.saleData['bankName']?.toString() ?? '',
      'bankName2': widget.saleData['bankName2']?.toString() ?? '',
      'remainingDebt': MoneyUtils.formatVND(
        widget.saleData['remainingDebt'] is num
            ? (widget.saleData['remainingDebt'] as num).toInt()
            : int.tryParse(widget.saleData['remainingDebt']?.toString() ?? '0') ??
                0,
      ),
      'qrData':
          'sale_check:${widget.saleData['firestoreId']?.toString() ?? 'N/A'}',
    };

    final templateText = [header, body, footer].where((s) => s.trim().isNotEmpty).join('\n');

    setState(() {
      _useTemplate = useTemplate;
      _previewText = _applyTemplate(templateText, data);
      _isLoading = false;
    });
  }

  Future<void> _print() async {
    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return;

    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter = printerConfig['bluetoothPrinter'] as BluetoothPrinterConfig?;
    final wifiIp = printerConfig['wifiIp'] as String?;

    await UnifiedPrinterService.printSaleReceipt(
      widget.saleData,
      widget.paper,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XEM TRƯỚC HÓA ĐƠN BÁN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print),
            onPressed: _print,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_useTemplate)
                    const Text(
                      'Mẫu đang tắt, bản xem trước dùng template mặc định.',
                      style: TextStyle(color: Colors.orange),
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Container(
                        width: double.infinity,
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
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
