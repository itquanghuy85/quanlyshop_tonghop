import 'package:flutter/material.dart';
import '../core/utils/money_utils.dart';
import '../services/unified_printer_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../models/printer_types.dart';
import '../theme/app_text_styles.dart';
import 'printer_selection_dialog.dart';

/// Dialog in tem sản phẩm với nhiều tùy chọn
/// - Chế độ TỰ ĐỘNG: Dùng cấu hình từ Thiết kế tem
/// - Chế độ TÙY CHỈNH: Cho phép nhập giá, text tùy biến, số lượng
class PrintLabelDialog extends StatefulWidget {
  final Map<String, dynamic> product;

  const PrintLabelDialog({super.key, required this.product});

  /// Hiển thị dialog và trả về true nếu in thành công
  static Future<bool?> show(BuildContext context, Map<String, dynamic> product) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => PrintLabelDialog(product: product),
    );
  }

  @override
  State<PrintLabelDialog> createState() => _PrintLabelDialogState();
}

class _PrintLabelDialogState extends State<PrintLabelDialog> {
  bool _isCustomMode = false;
  bool _isPrinting = false;
  int _quantity = 1;

  // Controllers cho chế độ tùy chỉnh
  final _priceKPKCtrl = TextEditingController();
  final _priceCPKCtrl = TextEditingController();
  final _customLine1Ctrl = TextEditingController();
  final _customLine2Ctrl = TextEditingController();
  final _customLine3Ctrl = TextEditingController();

  // Tùy chọn hiển thị (cho chế độ tùy chỉnh)
  bool _showName = true;
  bool _showDetail = true;
  bool _showKPK = true;
  bool _showCPK = true;
  bool _showIMEI = true;
  bool _showQR = true;
  bool _showCustomLines = false;

  @override
  void initState() {
    super.initState();
    _initValues();
  }

  void _initValues() {
    final price = widget.product['price'] ?? 0;
    _priceKPKCtrl.text = MoneyUtils.formatVND(price);
    // Mặc định CPK = KPK + 500,000 (phụ kiện cơ bản)
    final priceCPK = widget.product['priceCPK'] ?? (price + 500000);
    _priceCPKCtrl.text = MoneyUtils.formatVND(priceCPK);
  }

  @override
  void dispose() {
    _priceKPKCtrl.dispose();
    _priceCPKCtrl.dispose();
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
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildProductInfo(),
                    const SizedBox(height: 16),
                    _buildModeSelector(),
                    const SizedBox(height: 16),
                    if (_isCustomMode) _buildCustomOptions(),
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
                  "IN TEM",
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

  Widget _buildProductInfo() {
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
              const Icon(Icons.info_outline, color: Colors.blue, size: 18),
              const SizedBox(width: 8),
              Text(
                "THÔNG TIN SẢN PHẨM",
                style: AppTextStyles.subtitle2.copyWith(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          _infoRow("Tên:", widget.product['name'] ?? 'N/A'),
          _infoRow("Chi tiết:", "${widget.product['capacity'] ?? ''} ${widget.product['color'] ?? ''} ${widget.product['condition'] ?? ''}".trim()),
          _infoRow("IMEI:", widget.product['imei'] ?? 'N/A'),
          _infoRow("Giá bán gốc:", MoneyUtils.formatVND(widget.product['price'] ?? 0)),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: AppTextStyles.caption.copyWith(color: Colors.grey)),
          ),
          Expanded(
            child: Text(value, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _modeButton(
              "TỰ ĐỘNG",
              "Dùng cấu hình thiết kế tem",
              Icons.auto_awesome,
              !_isCustomMode,
              () => setState(() => _isCustomMode = false),
            ),
          ),
          Expanded(
            child: _modeButton(
              "TÙY CHỈNH",
              "Nhập giá & nội dung riêng",
              Icons.edit_note,
              _isCustomMode,
              () => setState(() => _isCustomMode = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(String title, String subtitle, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: selected ? Colors.purple : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: selected ? Colors.white : Colors.grey, size: 22),
            const SizedBox(height: 4),
            Text(
              title,
              style: AppTextStyles.subtitle2.copyWith(
                color: selected ? Colors.white : Colors.grey,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: AppTextStyles.caption.copyWith(
                color: selected ? Colors.white70 : Colors.grey,
                fontSize: 9,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomOptions() {
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
              const Icon(Icons.tune, color: Colors.orange, size: 18),
              const SizedBox(width: 8),
              Text(
                "TÙY CHỈNH NỘI DUNG TEM",
                style: AppTextStyles.subtitle2.copyWith(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Giải thích KPK/CPK
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "📌 KPK = Không Phụ Kiện (giá máy trần)",
                  style: AppTextStyles.caption.copyWith(color: Colors.blue.shade700),
                ),
                Text(
                  "📌 CPK = Có Phụ Kiện (sạc, cáp, ốp, kính...)",
                  style: AppTextStyles.caption.copyWith(color: Colors.red.shade700),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Giá KPK
          Row(
            children: [
              Checkbox(
                value: _showKPK,
                onChanged: (v) => setState(() => _showKPK = v ?? true),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Text("Giá KPK: ", style: TextStyle(fontWeight: FontWeight.w500)),
              Expanded(
                child: TextField(
                  controller: _priceKPKCtrl,
                  enabled: _showKPK,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                    suffixText: "đ",
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Giá CPK
          Row(
            children: [
              Checkbox(
                value: _showCPK,
                onChanged: (v) => setState(() => _showCPK = v ?? true),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const Text("Giá CPK: ", style: TextStyle(fontWeight: FontWeight.w500)),
              Expanded(
                child: TextField(
                  controller: _priceCPKCtrl,
                  enabled: _showCPK,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                    suffixText: "đ",
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Các checkbox hiển thị
          Wrap(
            spacing: 8,
            runSpacing: 0,
            children: [
              _miniCheckbox("Tên máy", _showName, (v) => setState(() => _showName = v)),
              _miniCheckbox("Chi tiết", _showDetail, (v) => setState(() => _showDetail = v)),
              _miniCheckbox("IMEI", _showIMEI, (v) => setState(() => _showIMEI = v)),
              _miniCheckbox("QR Code", _showQR, (v) => setState(() => _showQR = v)),
            ],
          ),
          const Divider(height: 20),

          // Nội dung tùy biến thêm (cho giấy lớn)
          Row(
            children: [
              Checkbox(
                value: _showCustomLines,
                onChanged: (v) => setState(() => _showCustomLines = v ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Expanded(
                child: Text(
                  "Thêm nội dung tùy biến (cho giấy lớn)",
                  style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          if (_showCustomLines) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customLine1Ctrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: "Dòng 1: VD: BẢO HÀNH 12 THÁNG",
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _customLine2Ctrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: "Dòng 2: VD: ĐỔI TRẢ 7 NGÀY",
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _customLine3Ctrl,
              decoration: InputDecoration(
                isDense: true,
                hintText: "Dòng 3: VD: HOTLINE: 0123.456.789",
                contentPadding: const EdgeInsets.all(10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniCheckbox(String label, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        Text(label, style: AppTextStyles.caption),
      ],
    );
  }

  Widget _buildQuantitySelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.print, color: Colors.green),
          const SizedBox(width: 12),
          const Text("Số lượng in:", style: TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          IconButton(
            onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
            icon: const Icon(Icons.remove_circle_outline),
            color: Colors.green,
          ),
          Container(
            width: 50,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green),
            ),
            child: Text(
              "$_quantity",
              style: AppTextStyles.headline5.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed: _quantity < 99 ? () => setState(() => _quantity++) : null,
            icon: const Icon(Icons.add_circle_outline),
            color: Colors.green,
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            "XEM TRƯỚC TEM",
            style: AppTextStyles.caption.copyWith(
              color: Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: 200,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black, width: 1),
            ),
            child: Column(
              children: [
                if (_isCustomMode ? _showName : true)
                  Text(
                    (widget.product['name'] ?? 'N/A').toString().toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                if (_isCustomMode ? _showDetail : true) ...[
                  const SizedBox(height: 2),
                  Text(
                    "${widget.product['capacity'] ?? ''} ${widget.product['color'] ?? ''} ${widget.product['condition'] ?? ''}".trim().toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ],
                const SizedBox(height: 4),
                if (_isCustomMode ? _showKPK : true)
                  Text(
                    "GIÁ KPK: ${_isCustomMode ? _priceKPKCtrl.text : MoneyUtils.formatVND(widget.product['price'] ?? 0)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                  ),
                if (_isCustomMode ? _showCPK : true)
                  Text(
                    "GIÁ CPK: ${_isCustomMode ? _priceCPKCtrl.text : MoneyUtils.formatVND((widget.product['price'] ?? 0) + 500000)}",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                      fontSize: 11,
                    ),
                  ),
                if (_isCustomMode ? _showIMEI : true) ...[
                  const SizedBox(height: 2),
                  Text(
                    "IMEI: ${widget.product['imei'] ?? 'N/A'}",
                    style: const TextStyle(fontSize: 9),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (_isCustomMode && _showCustomLines) ...[
                  if (_customLine1Ctrl.text.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _customLine1Ctrl.text.toUpperCase(),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_customLine2Ctrl.text.isNotEmpty)
                    Text(
                      _customLine2Ctrl.text.toUpperCase(),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  if (_customLine3Ctrl.text.isNotEmpty)
                    Text(
                      _customLine3Ctrl.text.toUpperCase(),
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                ],
                if (_isCustomMode ? _showQR : true) ...[
                  const SizedBox(height: 4),
                  const Icon(Icons.qr_code_2, size: 40),
                ],
              ],
            ),
          ),
        ],
      ),
    );
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
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text("HỦY"),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _isPrinting ? null : _handlePrint,
              icon: _isPrinting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.print, color: Colors.white),
              label: Text(
                _isPrinting ? "ĐANG IN..." : "IN $_quantity TEM",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handlePrint() async {
    setState(() => _isPrinting = true);

    try {
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      // Chọn máy in
      final printerConfig = await showPrinterSelectionDialog(context);
      if (printerConfig == null) {
        return;
      }

      final printerType = printerConfig['type'] as PrinterType?;
      final rawBluetoothPrinter = printerConfig['bluetoothPrinter'];
      BluetoothPrinterConfig? bluetoothPrinter;
      if (rawBluetoothPrinter is BluetoothPrinterConfig) {
        bluetoothPrinter = rawBluetoothPrinter;
      } else if (rawBluetoothPrinter is Map) {
        try {
          bluetoothPrinter = BluetoothPrinterConfig.fromJson(
            Map<String, dynamic>.from(rawBluetoothPrinter),
          );
        } catch (_) {
          bluetoothPrinter = null;
        }
      }
      final wifiIp = printerConfig['wifiIp'] as String?;

      // Chuẩn bị dữ liệu in
      final printData = Map<String, dynamic>.from(widget.product);

      if (_isCustomMode) {
        // Chế độ tùy chỉnh - ghi đè các giá trị
        printData['price'] = _parsePrice(_priceKPKCtrl.text);
        printData['priceCPK'] = _parsePrice(_priceCPKCtrl.text);
        printData['_customShowName'] = _showName;
        printData['_customShowDetail'] = _showDetail;
        printData['_customShowKPK'] = _showKPK;
        printData['_customShowCPK'] = _showCPK;
        printData['_customShowIMEI'] = _showIMEI;
        printData['_customShowQR'] = _showQR;
        
        // Nội dung tùy biến
        final customLines = <String>[];
        if (_showCustomLines) {
          if (_customLine1Ctrl.text.trim().isNotEmpty) customLines.add(_customLine1Ctrl.text.trim());
          if (_customLine2Ctrl.text.trim().isNotEmpty) customLines.add(_customLine2Ctrl.text.trim());
          if (_customLine3Ctrl.text.trim().isNotEmpty) customLines.add(_customLine3Ctrl.text.trim());
        }
        printData['_customLines'] = customLines;
        printData['_isCustomMode'] = true;
      }

      // In theo số lượng
      int successCount = 0;
      for (int i = 0; i < _quantity; i++) {
        final success = await UnifiedPrinterService.printProductQRLabel(
          printData,
          customMac: bluetoothPrinter?.macAddress,
          bluetoothPrinter: bluetoothPrinter,
          printerType: printerType,
          wifiIp: wifiIp,
        );
        if (success) successCount++;
        
        // Delay nhỏ giữa các lần in để tránh quá tải
        if (i < _quantity - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      if (mounted) {
        navigator.pop(successCount > 0);
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              successCount == _quantity
                  ? '✅ Đã in thành công $successCount tem!'
                  : '⚠️ Đã in $successCount/$_quantity tem',
            ),
            backgroundColor: successCount == _quantity ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi in tem: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPrinting = false);
      }
    }
  }
}
