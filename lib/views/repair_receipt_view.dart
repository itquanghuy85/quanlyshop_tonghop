import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../theme/app_text_styles.dart';
import '../services/event_bus.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/unified_printer_service.dart';
import '../services/user_service.dart';
import '../services/sync_orchestrator.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/printer_types.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/printer_selection_dialog.dart';

class RepairReceiptView extends StatefulWidget {
  const RepairReceiptView({super.key});

  @override
  State<RepairReceiptView> createState() => _RepairReceiptViewState();
}

class _RepairReceiptViewState extends State<RepairReceiptView> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _deviceModelController = TextEditingController();
  final _issueController = TextEditingController();
  final _accessoriesController = TextEditingController();
  final _estimatedCostController = TextEditingController();

  bool _isLoading = false;
  String _receiptCode = '';

  @override
  void initState() {
    super.initState();
    _generateReceiptCode();
  }

  void _generateReceiptCode() {
    final now = DateTime.now();
    final code = 'RC${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.millisecondsSinceEpoch.toString().substring(8)}';
    setState(() => _receiptCode = code);
  }

  int _parseAmount(String value) {
    // Không nhân 1000 - user đã nhập số đầy đủ với formatter
    return MoneyUtils.parseCurrency(value);
  }

  Future<void> _saveAndPrintReceipt() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final db = DBHelper();
      final now = DateTime.now().millisecondsSinceEpoch;
      final firestoreId = 'rep_${now}_${_phoneController.text.trim()}';
      
      // Tạo repair record
      final estimatedCost = _parseAmount(_estimatedCostController.text);

      final repair = Repair(
        customerName: _customerNameController.text.trim(),
        phone: _phoneController.text.trim(),
        model: _deviceModelController.text.trim(),
        issue: _issueController.text.trim(),
        accessories: _accessoriesController.text.trim(),
        address: _addressController.text.trim(),
        price: estimatedCost,
        status: 1, // Received
        createdAt: now,
        lastCaredAt: now,
        isSynced: false,
        deleted: false,
        firestoreId: firestoreId,
      );

      // Lưu vào local database
      final repairId = await db.insertRepair(repair);

      // Queue sync via SyncOrchestrator
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.repair,
        entityId: repairId,
        firestoreId: firestoreId,
        operation: SyncOperation.create,
        data: repair.toMap(),
      );

      EventBus().emit('repairs_changed');

      // In phiếu tiếp nhận
      await _printReceipt(repair, firestoreId);

      messenger.showSnackBar(
        const SnackBar(content: Text('Đã lưu và in phiếu tiếp nhận thành công!')),
      );

      // Reset form (guard with mounted)
      if (mounted) {
        _formKey.currentState!.reset();
        _generateReceiptCode();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _printReceipt(Repair repair, String docId) async {
    // Show printer selection dialog
    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return; // User cancelled

    final receiptData = {
      'receiptCode': _receiptCode,
      'docId': docId,
      'customerName': repair.customerName,
      'customerPhone': repair.phone,
      'customerAddress': repair.address,
      'deviceModel': repair.model,
      'issue': repair.issue,
      'accessories': repair.accessories,
      'estimatedCost': repair.price,
      'receivedDate': DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
    };

    // Extract printer configuration
    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter = printerConfig['bluetoothPrinter'] as BluetoothPrinterConfig?;
    final wifiIp = printerConfig['wifiIp'] as String?;

    await UnifiedPrinterService.printRepairReceipt(
      receiptData,
      PaperSize.mm80,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('PHIẾ́U TIẾ́P NHẬN SỬa CHỮa'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header với mã phiếu
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.receipt_long, color: Colors.blue, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MÃ PHIẾU TIẾP NHẬN',
                            style: TextStyle(
                              fontSize: AppTextStyles.subtitle1.fontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          Text(
                            _receiptCode,
                            style: TextStyle(
                              fontSize: AppTextStyles.headline2.fontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _generateReceiptCode,
                      icon: const Icon(Icons.refresh, color: Colors.blue),
                      tooltip: 'Tạo mã mới',
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Thông tin khách hàng
              Text(
                'THÔNG TIN KHÁCH HÀNG',
                style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              ValidatedTextField(
                controller: _customerNameController,
                label: 'Tên khách hàng *',
                required: true,
              ),

              const SizedBox(height: 12),

              ValidatedTextField(
                controller: _phoneController,
                label: 'Số điện thoại *',
                keyboardType: TextInputType.phone,
                required: true,
              ),

              const SizedBox(height: 12),

              ValidatedTextField(
                controller: _addressController,
                label: 'Địa chỉ',
              ),

              const SizedBox(height: 24),

              // Thông tin thiết bị
              Text(
                'THÔNG TIN THIẾT BỊ',
                style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),

              ValidatedTextField(
                controller: _deviceModelController,
                label: 'Model thiết bị *',
                required: true,
              ),

              const SizedBox(height: 12),

              ValidatedTextField(
                controller: _issueController,
                label: 'Tình trạng hỏng *',
                required: true,
              ),

              const SizedBox(height: 12),

              ValidatedTextField(
                controller: _accessoriesController,
                label: 'Phụ kiện đi kèm',
                hint: 'Ví dụ: Sạc, tai nghe, ốp lưng...',
              ),

              const SizedBox(height: 12),

              CurrencyTextField(
                controller: _estimatedCostController,
                label: 'Giá dự kiến (VNĐ)',
                hint: 'Để trống nếu chưa xác định',
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.isEmpty) return null; // optional
                  return MoneyUtils.validateAmount(text, min: 0, fieldName: 'Giá dự kiến');
                },
              ),

              const SizedBox(height: 32),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveAndPrintReceipt,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(_isLoading ? 'ĐANG XỬ LÝ...' : 'LƯU & IN PHIẾU'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Preview button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isLoading ? null : () => _showPreviewDialog(context),
                  icon: const Icon(Icons.preview),
                  label: const Text('XEM TRƯỚC PHIẾU'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _showPreviewDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('XEM TRƯỚC PHIẾU TIẾP NHẬN'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPreviewRow('Mã phiếu:', _receiptCode),
              _buildPreviewRow('Khách hàng:', _customerNameController.text),
              _buildPreviewRow('SĐT:', _phoneController.text),
              _buildPreviewRow('Địa chỉ:', _addressController.text),
              _buildPreviewRow('Model:', _deviceModelController.text),
              _buildPreviewRow('Tình trạng:', _issueController.text),
              _buildPreviewRow('Phụ kiện:', _accessoriesController.text),
              _buildPreviewRow('Giá dự kiến:', _estimatedCostController.text.isEmpty ? '(chưa nhập)' : '${MoneyUtils.formatCurrency(_parseAmount(_estimatedCostController.text))} VNĐ'),
              _buildPreviewRow('Ngày nhận:', DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value.isEmpty ? '(chưa nhập)' : value),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _deviceModelController.dispose();
    _issueController.dispose();
    _accessoriesController.dispose();
    _estimatedCostController.dispose();
    super.dispose();
  }
}
