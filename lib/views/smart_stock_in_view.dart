import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/stock_entry_model.dart';
import '../models/supplier_model.dart';
import '../services/stock_entry_service.dart';
import '../services/supplier_service.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/first_time_guide_service.dart';
import '../widgets/currency_text_field.dart';

/// Form nhập kho thông minh - hỗ trợ cả Nhập nhanh và Nhập tạm
class SmartStockInView extends StatefulWidget {
  final StockEntry? editEntry; // Để chỉnh sửa phiếu DRAFT

  const SmartStockInView({super.key, this.editEntry});

  @override
  State<SmartStockInView> createState() => _SmartStockInViewState();
}

class _SmartStockInViewState extends State<SmartStockInView> {
  final _formKey = GlobalKey<FormState>();
  final _service = StockEntryService();
  final _supplierService = SupplierService();

  bool _isLoading = false;
  bool _isSaving = false;

  // Loại sản phẩm
  String _productType = 'DIEN_THOAI';

  // Controllers - Chung
  final _nameCtrl = TextEditingController();
  final _quantityCtrl = TextEditingController(text: '1');
  final _costCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  // Controllers - Điện thoại
  final _imeiCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();

  // Controllers - Phụ kiện/Linh kiện
  final _skuCtrl = TextEditingController();

  // Dropdown values
  String? _selectedBrand;
  String? _selectedCapacity;
  String? _selectedColor;
  String? _selectedCondition;
  String? _selectedUnit;
  String? _selectedSupplier;
  String? _selectedSupplierId;
  String? _selectedPaymentMethod;

  // Data
  List<Map<String, dynamic>> _suppliers = [];

  // Options
  final _brands = ['IPHONE', 'SAMSUNG', 'OPPO', 'XIAOMI', 'VIVO', 'REALME', 'KHÁC'];
  final _capacities = ['64GB', '128GB', '256GB', '512GB', '1TB'];
  final _colors = ['ĐEN', 'TRẮNG', 'XANH', 'ĐỎ', 'VÀNG', 'TÍM', 'HỒNG', 'BẠC', 'XANH LÁ'];
  final _conditions = ['MỚI', '99%', '98%', '97%', '95%', 'KHÁC'];
  final _units = ['Cái', 'Hộp', 'Bộ', 'Chiếc', 'Cuộn', 'Túi'];
  final _paymentMethods = ['TIỀN MẶT', 'CHUYỂN KHOẢN', 'CÔNG NỢ'];

  @override
  void initState() {
    super.initState();
    _loadData();
    if (widget.editEntry != null) {
      _loadEditData();
    }
    // Hiển thị hướng dẫn cho người dùng mới
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showGuideIfNeeded(
      context: context,
      screenKey: FirstTimeGuideService.keySmartStockIn,
      title: 'Nhập Kho Thông Minh',
      icon: Icons.add_box,
      color: Colors.green,
      steps: const [
        GuideStep(
          title: '📱 Chọn loại sản phẩm',
          description: 'Điện thoại (có IMEI), Phụ kiện hoặc Linh kiện - mỗi loại có thông tin khác nhau.',
          icon: Icons.category,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '🏢 Tạo nhà cung cấp trước',
          description: 'Bạn cần tạo NCC trong mục "Quản lý NCC" trước khi nhập kho để theo dõi công nợ.',
          icon: Icons.store,
          iconColor: Colors.orange,
        ),
        GuideStep(
          title: '💾 LƯU TẠM',
          description: 'Chỉ cần nhập tên sản phẩm, lưu nhanh khi bận rộn. Bổ sung thông tin sau ở "Hàng chờ xác nhận".',
          icon: Icons.save_outlined,
          iconColor: Colors.amber,
        ),
        GuideStep(
          title: '✅ LƯU & XÁC NHẬN',
          description: 'Điền đầy đủ: Tên, Giá vốn, NCC, Phương thức TT. Hàng sẽ vào kho ngay lập tức.',
          icon: Icons.check_circle,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '📷 Quét mã IMEI',
          description: 'Với điện thoại, nhấn icon camera để quét barcode IMEI tự động.',
          icon: Icons.qr_code_scanner,
          iconColor: Colors.purple,
        ),
      ],
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final suppliers = await _supplierService.getSuppliers();
      setState(() {
        _suppliers = suppliers.map((s) => s.toMap()).toList();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _loadEditData() {
    final entry = widget.editEntry!;
    if (entry.items.isNotEmpty) {
      final item = entry.items.first;
      _productType = item.productType;
      _nameCtrl.text = item.name;
      _quantityCtrl.text = item.quantity.toString();
      if (item.cost != null) _costCtrl.text = (item.cost! / 1000).toString();
      if (item.price != null) _priceCtrl.text = (item.price! / 1000).toString();

      if (_productType == 'DIEN_THOAI') {
        _imeiCtrl.text = item.imei ?? '';
        _selectedBrand = item.brand;
        _modelCtrl.text = item.model ?? '';
        _selectedCapacity = item.capacity;
        _selectedColor = item.color;
        _selectedCondition = item.condition;
      } else {
        _skuCtrl.text = item.sku ?? '';
        _selectedUnit = item.unit;
      }
    }

    _selectedSupplierId = entry.supplierId;
    _selectedSupplier = entry.supplierName;
    _selectedPaymentMethod = entry.paymentMethod;
    _notesCtrl.text = entry.notes ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _quantityCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    _imeiCtrl.dispose();
    _modelCtrl.dispose();
    _skuCtrl.dispose();
    super.dispose();
  }

  bool get _isPhone => _productType == 'DIEN_THOAI';

  /// Kiểm tra nếu điện thoại có IMEI thì số lượng phải = 1
  bool get _hasIMEIConflict {
    if (!_isPhone) return false;
    final imei = _imeiCtrl.text.trim();
    final qty = int.tryParse(_quantityCtrl.text) ?? 1;
    return imei.isNotEmpty && qty != 1;
  }

  /// Kiểm tra đủ thông tin để xác nhận ngay
  bool get _canConfirmNow {
    if (_nameCtrl.text.trim().isEmpty) return false;
    // Sử dụng CurrencyTextField.getValue() để check giá vốn đúng cách
    if (CurrencyTextField.getValue(_costCtrl) <= 0) return false;
    if (_selectedSupplier == null) return false;
    if (_selectedPaymentMethod == null) return false;
    if (_hasIMEIConflict) return false; // Có IMEI nhưng SL != 1
    return true;
  }

  /// Kiểm tra có thể lưu tạm
  bool get _canSaveDraft {
    if (_nameCtrl.text.trim().isEmpty) return false;
    if (_hasIMEIConflict) return false; // Có IMEI nhưng SL != 1
    return true;
  }

  StockEntryItem _buildItem() {
    // Sử dụng CurrencyTextField.getValue() để parse đúng format (dấu chấm)
    final costValue = CurrencyTextField.getValue(_costCtrl);
    final priceValue = CurrencyTextField.getValue(_priceCtrl);
    
    // Label là "Giá vốn (k)" nên người dùng nhập đơn vị nghìn → nhân 1000
    double? cost;
    if (costValue > 0) {
      cost = costValue.toDouble() * 1000;
    }
    
    double? price;
    if (priceValue > 0) {
      price = priceValue.toDouble() * 1000;
    }

    // Nếu điện thoại có IMEI thì số lượng phải = 1
    int quantity = int.tryParse(_quantityCtrl.text) ?? 1;
    if (_isPhone && _imeiCtrl.text.trim().isNotEmpty) {
      quantity = 1;
    }

    return StockEntryItem(
      name: _nameCtrl.text.trim().toUpperCase(),
      quantity: quantity,
      cost: cost,
      price: price,
      productType: _productType,
      // Điện thoại
      imei: _isPhone ? _imeiCtrl.text.trim() : null,
      brand: _isPhone ? _selectedBrand : null,
      model: _isPhone ? _modelCtrl.text.trim().toUpperCase() : null,
      capacity: _isPhone ? _selectedCapacity : null,
      color: _isPhone ? _selectedColor : null,
      condition: _isPhone ? _selectedCondition : null,
      // Phụ kiện
      sku: !_isPhone ? _skuCtrl.text.trim().toUpperCase() : null,
      unit: !_isPhone ? _selectedUnit : null,
    );
  }

  Future<StockEntry> _buildEntry() async {
    final shopId = await UserService.getCurrentShopId() ?? '';
    final item = _buildItem();

    return StockEntry(
      firestoreId: widget.editEntry?.firestoreId,
      shopId: shopId,
      items: [item],
      supplierId: _selectedSupplierId,
      supplierName: _selectedSupplier,
      paymentMethod: _selectedPaymentMethod,
      notes: _notesCtrl.text.trim(),
    );
  }

  /// Lưu tạm (DRAFT)
  Future<void> _saveDraft() async {
    if (_hasIMEIConflict) {
      NotificationService.showSnackBar(
        'Điện thoại có IMEI chỉ được nhập số lượng = 1',
        color: Colors.red,
      );
      return;
    }
    if (!_canSaveDraft) {
      NotificationService.showSnackBar('Vui lòng nhập tên sản phẩm', color: Colors.red);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final entry = await _buildEntry();

      bool success;
      if (widget.editEntry != null) {
        // Cập nhật
        success = await _service.updateEntry(entry);
      } else {
        // Tạo mới
        final created = await _service.saveDraft(entry);
        success = created != null;
      }

      if (success && mounted) {
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Lưu và xác nhận ngay (QUICK)
  Future<void> _saveAndConfirm() async {
    if (_hasIMEIConflict) {
      NotificationService.showSnackBar(
        'Điện thoại có IMEI chỉ được nhập số lượng = 1',
        color: Colors.red,
      );
      return;
    }
    if (!_canConfirmNow) {
      NotificationService.showSnackBar('Vui lòng điền đầy đủ thông tin', color: Colors.red);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final entry = await _buildEntry();

      bool success;
      if (widget.editEntry != null) {
        // Cập nhật rồi xác nhận
        success = await _service.updateEntry(entry);
        if (success && entry.firestoreId != null) {
          success = await _service.confirmEntry(entry.firestoreId!);
        }
      } else {
        // Nhập nhanh
        success = await _service.quickStockIn(entry);
      }

      if (success && mounted) {
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _scanIMEI() async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _IMEIScannerDialog(),
    );
    if (result != null && result.isNotEmpty) {
      setState(() {
        _imeiCtrl.text = result;
        // Auto set quantity = 1 khi có IMEI
        _quantityCtrl.text = '1';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.editEntry != null ? 'CHỈNH SỬA PHIẾU NHẬP' : 'NHẬP KHO MỚI',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Chọn loại sản phẩm
                          _buildProductTypeSelector(),
                          const SizedBox(height: 16),

                          // Form theo loại
                          if (_isPhone) _buildPhoneForm() else _buildAccessoryForm(),

                          const Divider(height: 24),

                          // Thông tin kế toán
                          _buildAccountingSection(),

                          const SizedBox(height: 16),

                          // Ghi chú
                          TextFormField(
                            controller: _notesCtrl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'Ghi chú',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.note, size: 20),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Nút hành động
                  _buildActionButtons(),
                ],
              ),
            ),
    );
  }

  Widget _buildProductTypeSelector() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Loại sản phẩm',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildTypeChip('DIEN_THOAI', '📱 Điện thoại'),
                const SizedBox(width: 8),
                _buildTypeChip('PHU_KIEN', '🎧 Phụ kiện'),
                const SizedBox(width: 8),
                _buildTypeChip('LINH_KIEN', '🔧 Linh kiện'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypeChip(String type, String label) {
    final isSelected = _productType == type;
    return Expanded(
      child: InkWell(
        onTap: widget.editEntry == null
            ? () => setState(() => _productType = type)
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue.shade100 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey.shade300,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.blue.shade700 : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPhoneForm() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Tên máy
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Tên máy *',
                hintText: 'VD: IPHONE 15 PRO MAX',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone_android, size: 20),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),

            // IMEI + Scan
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _imeiCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(15),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'IMEI',
                      hintText: '15 số',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.fingerprint, size: 20),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (value) {
                      // Nếu có IMEI thì số lượng phải = 1
                      if (value.isNotEmpty) {
                        _quantityCtrl.text = '1';
                      }
                      setState(() {});
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _scanIMEI,
                  icon: const Icon(Icons.qr_code_scanner, size: 28),
                  color: Colors.blue,
                  tooltip: 'Quét IMEI',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Hãng + Model
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedBrand,
                    decoration: const InputDecoration(
                      labelText: 'Hãng',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _brands
                        .map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedBrand = v),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: _modelCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      hintText: 'VD: 15 PRO MAX',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Dung lượng + Màu
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedCapacity,
                    decoration: const InputDecoration(
                      labelText: 'Dung lượng',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _capacities
                        .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCapacity = v),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedColor,
                    decoration: const InputDecoration(
                      labelText: 'Màu sắc',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _colors
                        .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedColor = v),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Tình trạng + Số lượng
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedCondition,
                    decoration: const InputDecoration(
                      labelText: 'Tình trạng',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _conditions
                        .map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCondition = v),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 100,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _quantityCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        enabled: _imeiCtrl.text.trim().isEmpty, // Khóa khi có IMEI
                        decoration: InputDecoration(
                          labelText: 'SL',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          filled: _imeiCtrl.text.trim().isNotEmpty,
                          fillColor: Colors.grey.shade200,
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (v) {
                          // Nếu có IMEI, ép số lượng = 1
                          if (_imeiCtrl.text.trim().isNotEmpty && v != '1') {
                            _quantityCtrl.text = '1';
                            NotificationService.showSnackBar(
                              'Có IMEI → SL phải = 1',
                              color: Colors.orange,
                            );
                          }
                          setState(() {});
                        },
                      ),
                      if (_imeiCtrl.text.trim().isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 2),
                          child: Text(
                            '(có IMEI)',
                            style: TextStyle(fontSize: 9, color: Colors.grey),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccessoryForm() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Tên sản phẩm
            TextFormField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'Tên sản phẩm *',
                hintText: _productType == 'PHU_KIEN'
                    ? 'VD: CÁP SẠC LIGHTNING'
                    : 'VD: MÀN HÌNH IPHONE 15',
                border: const OutlineInputBorder(),
                prefixIcon: Icon(
                  _productType == 'PHU_KIEN' ? Icons.headphones : Icons.build,
                  size: 20,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),

            // SKU + Đơn vị
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _skuCtrl,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Mã SKU',
                      hintText: 'VD: PK-CAP-001',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedUnit ?? 'Cái',
                    decoration: const InputDecoration(
                      labelText: 'Đơn vị',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _units
                        .map((u) => DropdownMenuItem(value: u, child: Text(u, style: const TextStyle(fontSize: 12))))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedUnit = v),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Số lượng
            TextFormField(
              controller: _quantityCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Số lượng *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.add_box, size: 20),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountingSection() {
    return Card(
      elevation: 1,
      color: Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_wallet, size: 18, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  'Thông tin kế toán',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.orange.shade700,
                  ),
                ),
                const Spacer(),
                Text(
                  '(Để trống nếu chưa biết)',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Giá vốn + Giá bán
            Row(
              children: [
                Expanded(
                  child: CurrencyTextField(
                    controller: _costCtrl,
                    label: 'Giá vốn (k)',
                    icon: Icons.attach_money,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CurrencyTextField(
                    controller: _priceCtrl,
                    label: 'Giá bán (k)',
                    icon: Icons.sell,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Nhà cung cấp
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedSupplier,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Nhà cung cấp',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business, size: 20),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: _suppliers
                        .map((s) => DropdownMenuItem(
                              value: s['name'] as String,
                              child: Text(s['name'] ?? '', style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      final supplier = _suppliers.firstWhere(
                        (s) => s['name'] == v,
                        orElse: () => {},
                      );
                      setState(() {
                        _selectedSupplier = v;
                        _selectedSupplierId = supplier['firestoreId'];
                      });
                    },
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addNewSupplier,
                  icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
                  tooltip: 'Thêm NCC mới',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Phương thức thanh toán
            const Text(
              'Phương thức thanh toán',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: _paymentMethods.map((method) {
                final isSelected = _selectedPaymentMethod == method;
                return ChoiceChip(
                  label: Text(method, style: const TextStyle(fontSize: 11)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() => _selectedPaymentMethod = selected ? method : null);
                  },
                  selectedColor: Colors.blue.shade100,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            // Nút Lưu tạm
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isSaving || !_canSaveDraft ? null : _saveDraft,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('LƯU TẠM'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  side: BorderSide(color: Colors.grey.shade400),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Nút Lưu & Xác nhận
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _isSaving || !_canConfirmNow ? null : _saveAndConfirm,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_circle, size: 18),
                label: Text(_isSaving ? 'Đang lưu...' : 'LƯU & XÁC NHẬN'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _canConfirmNow ? Colors.green : Colors.grey,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addNewSupplier() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm NCC mới', style: TextStyle(fontSize: 14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Tên NCC *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Số điện thoại',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) {
                NotificationService.showSnackBar('Nhập tên NCC', color: Colors.red);
                return;
              }
              final shopId = await UserService.getCurrentShopId();
              final supplier = Supplier(
                name: nameCtrl.text.trim().toUpperCase(),
                phone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                shopId: shopId ?? '',
              );
              final saved = await _supplierService.addSupplier(supplier);
              if (saved != null && ctx.mounted) {
                Navigator.pop(ctx, true);
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _loadData();
      // Auto select NCC vừa thêm
      if (_suppliers.isNotEmpty) {
        setState(() {
          _selectedSupplier = _suppliers.last['name'];
          _selectedSupplierId = _suppliers.last['firestoreId'];
        });
      }
    }
  }
}

// === IMEI Scanner Dialog ===
class _IMEIScannerDialog extends StatefulWidget {
  @override
  State<_IMEIScannerDialog> createState() => _IMEIScannerDialogState();
}

class _IMEIScannerDialogState extends State<_IMEIScannerDialog> {
  final _controller = MobileScannerController();
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Quét IMEI', style: TextStyle(fontSize: 14)),
      content: SizedBox(
        width: 300,
        height: 300,
        child: MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_scanned) return;
            final barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              final code = barcode.rawValue;
              if (code != null && code.length >= 15) {
                // Extract IMEI (15 digits)
                final imei = code.replaceAll(RegExp(r'[^0-9]'), '');
                if (imei.length >= 15) {
                  _scanned = true;
                  Navigator.pop(context, imei.substring(0, 15));
                  return;
                }
              }
            }
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
      ],
    );
  }
}
