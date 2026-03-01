import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/repair_model.dart';
import '../models/printer_types.dart';
import '../utils/money_utils.dart';
import '../services/unified_printer_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../widgets/printer_selection_dialog.dart';

class RepairInvoicePreviewView extends StatefulWidget {
  final Repair repair;
  final Map<String, dynamic> shopInfo;

  const RepairInvoicePreviewView({
    super.key,
    required this.repair,
    required this.shopInfo,
  });

  @override
  State<RepairInvoicePreviewView> createState() => _RepairInvoicePreviewViewState();
}

class _RepairInvoicePreviewViewState extends State<RepairInvoicePreviewView> {
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

  String _statusText(int status) {
    switch (status) {
      case 1:
        return 'Tiếp nhận';
      case 2:
        return 'Đang sửa';
      case 3:
        return 'Sửa xong';
      case 4:
        return 'Đã giao';
      default:
        return 'Không xác định';
    }
  }

  Future<void> _loadPreview() async {
    final prefs = await SharedPreferences.getInstance();
    final useTemplate = prefs.getBool('repair_invoice_use_template') ?? false;
    final header = prefs.getString('repair_invoice_header') ??
        '=== PHIẾU SỬA CHỮA ===\n{shopName}\n{shopAddr}\nHotline: {shopPhone}\n--------------------------------';
    final body = prefs.getString('repair_invoice_body') ??
      'Mã đơn: {code}\nNgày: {date} {time}\n\nKhách: {customerName}\nSĐT: {customerPhone}\n\nMáy: {model}\nIMEI: {imei}\nLỗi: {issue}\nPhụ kiện: {accessories}\nLinh kiện đã dùng: {partsUsed}\nDịch vụ: {services}\nBảo hành: {warranty}\nGhi chú: {notes}\n{warrantyPolicy}\n\nGiá: {price} đ\nThanh toán: {paymentMethod}\nTrạng thái: {status}\n[QR]{qrData}';
    final footer = prefs.getString('repair_invoice_footer') ??
        '--------------------------------\nCảm ơn quý khách!';

    final createdAt = DateTime.fromMillisecondsSinceEpoch(widget.repair.createdAt);
    final data = <String, String>{
      'shopName': widget.shopInfo['shopName']?.toString() ?? 'SHOP NEW',
      'shopAddr': widget.shopInfo['shopAddr']?.toString() ?? '',
      'shopPhone': widget.shopInfo['shopPhone']?.toString() ?? '',
      'code': widget.repair.firestoreId?.toString() ?? widget.repair.createdAt.toString(),
      'date': DateFormat('dd/MM/yyyy').format(createdAt),
      'time': DateFormat('HH:mm').format(createdAt),
      'customerName': widget.repair.customerName ?? '',
      'customerPhone': widget.repair.phone ?? '',
      'model': widget.repair.model ?? '',
      'imei': widget.repair.imei ?? '',
      'issue': widget.repair.issue ?? '',
      'accessories': widget.repair.accessories ?? '',
      'warranty': widget.repair.warranty ?? '',
      'partsUsed': widget.repair.partsUsed ?? '',
      'color': widget.repair.color ?? '',
      'condition': widget.repair.condition ?? '',
      'notes': widget.repair.notes ?? '',
      'createdBy': widget.repair.createdBy ?? '',
      'repairedBy': widget.repair.repairedBy ?? '',
      'deliveredBy': widget.repair.deliveredBy ?? '',
      'services': widget.repair.services.map((s) => s.serviceName).join(', '),
      'price': MoneyUtils.formatVND(widget.repair.price),
      'paymentMethod': widget.repair.paymentMethod ?? '',
      'status': _statusText(widget.repair.status),
      'qrData': 'repair_check:${widget.repair.firestoreId ?? widget.repair.createdAt}',
      'warrantyPolicy': prefs.getString('warranty_policy') ?? '',
      'returnPolicy': prefs.getString('return_policy') ?? '',
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

    await UnifiedPrinterService.printRepairReceiptFromRepair(
      widget.repair,
      widget.shopInfo,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('XEM TRƯỚC PHIẾU SỬA'),
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
