import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants/product_constants.dart';
import '../models/stock_entry_model.dart';
import '../models/supplier_model.dart';
import '../models/quick_input_code_model.dart';
import '../services/stock_entry_service.dart';
import '../services/supplier_service.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/first_time_guide_service.dart';
import '../widgets/currency_text_field.dart';
import '../theme/app_text_styles.dart';

/// Form nhập kho thông minh - hỗ trợ cả Nhập nhanh và Nhập tạm
class SmartStockInView extends StatefulWidget {
  final StockEntry? editEntry; // Để chỉnh sửa phiếu DRAFT
  final QuickInputCode? quickInputCode; // Để điền từ mã nhập nhanh

  const SmartStockInView({super.key, this.editEntry, this.quickInputCode});

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
  final _labelInfoCtrl = TextEditingController();

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
  String? _selectedSupplierId; // Firestore ID
  int? _selectedSupplierLocalId; // SQLite local ID
  String? _selectedPaymentMethod;

  // Data
  List<Map<String, dynamic>> _suppliers = [];

  // Options - sử dụng constants để đồng bộ
  List<String> get _brands => ProductConstants.brands;
  List<String> get _capacities => ProductConstants.capacities;
  List<String> get _colors => ProductConstants.colors;
  List<String> get _conditions => ProductConstants.conditions;
  final _units = ProductConstants.units;
  final _paymentMethods = ProductConstants.paymentMethods;

  @override
  void initState() {
    super.initState();
    _loadData();
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
          description:
              'Điện thoại (có IMEI), Phụ kiện hoặc Linh kiện - mỗi loại có thông tin khác nhau.',
          icon: Icons.category,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '🏢 Tạo nhà cung cấp trước',
          description:
              'Bạn cần tạo NCC trong mục "Quản lý NCC" trước khi nhập kho để theo dõi công nợ.',
          icon: Icons.store,
          iconColor: Colors.orange,
        ),
        GuideStep(
          title: '💾 LƯU TẠM',
          description:
              'Chỉ cần nhập tên sản phẩm, lưu nhanh khi bận rộn. Bổ sung thông tin sau ở "Hàng chờ xác nhận".',
          icon: Icons.save_outlined,
          iconColor: Colors.amber,
        ),
        GuideStep(
          title: '✅ LƯU VÀO HÀNG CHỜ',
          description:
              'Điền đầy đủ: Tên, Giá vốn, NCC, Phương thức TT. Hàng sẽ vào "Hàng chờ xác nhận", cần duyệt để vào kho chính.',
          icon: Icons.inventory_2,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '📷 Quét mã IMEI',
          description:
              'Với điện thoại, nhấn icon camera để quét barcode IMEI tự động.',
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
      // Load edit data SAU KHI đã load suppliers
      if (widget.editEntry != null) {
        _loadEditData();
      }
      // Load từ QuickInputCode nếu có
      if (widget.quickInputCode != null) {
        _loadQuickInputData();
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Load dữ liệu từ QuickInputCode để điền vào form
  void _loadQuickInputData() {
    final code = widget.quickInputCode!;
    
    // Set loại sản phẩm
    _productType = code.type;
    _nameCtrl.text = code.name;
    _quantityCtrl.text = '1';
    
    // Giá
    if (code.cost != null && code.cost! > 0) {
      _costCtrl.text = CurrencyTextField.formatDisplay(code.cost!.toInt());
    }
    if (code.price != null && code.price! > 0) {
      _priceCtrl.text = CurrencyTextField.formatDisplay(code.price!.toInt());
    }
    
    // Thông tin điện thoại
    if (code.type == 'DIEN_THOAI') {
      if (code.brand != null && _brands.contains(code.brand)) {
        _selectedBrand = code.brand;
      }
      _modelCtrl.text = code.model ?? '';
      if (code.capacity != null && _capacities.contains(code.capacity)) {
        _selectedCapacity = code.capacity;
      }
      if (code.color != null && _colors.contains(code.color)) {
        _selectedColor = code.color;
      }
      if (code.condition != null && _conditions.contains(code.condition)) {
        _selectedCondition = code.condition;
      }
    }
    // Phụ kiện không có unit trong QuickInputCode
    
    // Nhà cung cấp
    if (code.supplier != null && code.supplier!.isNotEmpty) {
      final supplierMatch = _suppliers.where((s) => s['name'] == code.supplier).toList();
      if (supplierMatch.isNotEmpty) {
        _selectedSupplier = code.supplier;
        _selectedSupplierId = supplierMatch.first['firestoreId']?.toString();
      }
    }
    
    // Phương thức thanh toán
    if (code.paymentMethod != null && _paymentMethods.contains(code.paymentMethod)) {
      _selectedPaymentMethod = code.paymentMethod;
    }
    
    // Ghi chú
    if (code.description != null && code.description!.isNotEmpty) {
      _notesCtrl.text = code.description!;
    }

    // Thông tin in trên tem
    if (code.labelInfo != null && code.labelInfo!.isNotEmpty) {
      _labelInfoCtrl.text = code.labelInfo!;
    }
  }

  void _loadEditData() {
    final entry = widget.editEntry!;
    if (entry.items.isNotEmpty) {
      final item = entry.items.first;
      _productType = item.productType;
      _nameCtrl.text = item.name;
      _quantityCtrl.text = item.quantity.toString();
      // Hiển thị giá trị VNĐ đã lưu (không chia 1000)
      if (item.cost != null)
        _costCtrl.text = CurrencyTextField.formatDisplay(item.cost!.toInt());
      if (item.price != null)
        _priceCtrl.text = CurrencyTextField.formatDisplay(item.price!.toInt());

      if (_productType == 'DIEN_THOAI') {
        _imeiCtrl.text = item.imei ?? '';
        // Validate brand - chỉ set nếu có trong list
        if (item.brand != null && _brands.contains(item.brand)) {
          _selectedBrand = item.brand;
        }
        _modelCtrl.text = item.model ?? '';
        // Validate capacity - chỉ set nếu có trong list
        if (item.capacity != null && _capacities.contains(item.capacity)) {
          _selectedCapacity = item.capacity;
        }
        // Validate color - chỉ set nếu có trong list
        if (item.color != null && _colors.contains(item.color)) {
          _selectedColor = item.color;
        }
        // Validate condition - chỉ set nếu có trong list
        if (item.condition != null && _conditions.contains(item.condition)) {
          _selectedCondition = item.condition;
        }
      } else {
        _skuCtrl.text = item.sku ?? '';
        // Validate unit - chỉ set nếu có trong list
        if (item.unit != null && _units.contains(item.unit)) {
          _selectedUnit = item.unit;
        }
      }
      _labelInfoCtrl.text = item.labelInfo ?? '';
    }

    _selectedSupplierId = entry.supplierId;
    // Validate supplier name - chỉ set nếu có trong list hiện tại
    if (entry.supplierName != null && entry.supplierName!.isNotEmpty) {
      final exists = _suppliers.any((s) => s['name'] == entry.supplierName);
      if (exists) {
        _selectedSupplier = entry.supplierName;
      } else {
        // Nếu supplier name không có trong list, reset để tránh lỗi dropdown
        _selectedSupplier = null;
        _selectedSupplierId = null;
      }
    }
    // Validate payment method - chỉ set nếu có trong list
    if (entry.paymentMethod != null && _paymentMethods.contains(entry.paymentMethod)) {
      _selectedPaymentMethod = entry.paymentMethod;
    }
    _notesCtrl.text = entry.notes ?? '';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _quantityCtrl.dispose();
    _costCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    _labelInfoCtrl.dispose();
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

    // Điện thoại phải có đầy đủ: IMEI (hoặc nhập lô), Hãng, Dung lượng, Màu, Tình trạng
    if (_isPhone) {
      if (_selectedBrand == null) return false;
      if (_selectedCapacity == null) return false;
      if (_selectedColor == null) return false;
      if (_selectedCondition == null) return false;
    }
    return true;
  }

  /// Lấy danh sách thông tin còn thiếu để xác nhận
  List<String> get _missingConfirmInfo {
    final missing = <String>[];
    if (_nameCtrl.text.trim().isEmpty) missing.add('Tên sản phẩm');
    if (CurrencyTextField.getValue(_costCtrl) <= 0) missing.add('Giá vốn');
    if (_selectedSupplier == null) missing.add('Nhà cung cấp');
    if (_selectedPaymentMethod == null) missing.add('Phương thức TT');
    if (_isPhone) {
      if (_selectedBrand == null) missing.add('Hãng');
      if (_selectedCapacity == null) missing.add('Dung lượng');
      if (_selectedColor == null) missing.add('Màu sắc');
      if (_selectedCondition == null) missing.add('Tình trạng');
    }
    return missing;
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

    // Nhập trực tiếp VNĐ - KHÔNG nhân 1000 nữa
    double? cost;
    if (costValue > 0) {
      cost = costValue.toDouble();
    }

    double? price;
    if (priceValue > 0) {
      price = priceValue.toDouble();
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
      labelInfo: _labelInfoCtrl.text.trim(),
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
    final edit = widget.editEntry;

    return StockEntry(
      firestoreId: edit?.firestoreId,
      shopId: edit?.shopId ?? shopId,
      // Giữ nguyên status và entryType từ edit entry (không thay đổi khi update)
      status: edit?.status ?? StockEntryStatus.draft,
      entryType: edit?.entryType ?? StockEntryType.staging,
      locked: edit?.locked ?? false,
      items: [item],
      supplierId: _selectedSupplierId,
      supplierName: _selectedSupplier,
      paymentMethod: _selectedPaymentMethod,
      notes: _notesCtrl.text.trim(),
      // Giữ nguyên các trường timestamp và audit từ edit entry
      createdAt: edit?.createdAt,
      createdBy: edit?.createdBy,
      confirmedAt: edit?.confirmedAt,
      confirmedBy: edit?.confirmedBy,
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
      NotificationService.showSnackBar(
        'Vui lòng nhập tên sản phẩm',
        color: Colors.red,
      );
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

  /// Lưu đầy đủ thông tin - TẤT CẢ đều qua HÀNG CHỜ XÁC NHẬN
  /// Theo yêu cầu: Dù nhập đầy đủ thông tin vẫn phải qua "HÀNG CHỜ XÁC NHẬN" 
  /// mới vào kho chính và ghi nhận số liệu tài chính liên quan
  Future<void> _saveAndConfirm() async {
    if (_hasIMEIConflict) {
      NotificationService.showSnackBar(
        'Điện thoại có IMEI chỉ được nhập số lượng = 1',
        color: Colors.red,
      );
      return;
    }
    if (!_canConfirmNow) {
      NotificationService.showSnackBar(
        'Vui lòng điền đầy đủ thông tin',
        color: Colors.red,
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final entry = await _buildEntry();
      debugPrint(
        '📋 _saveAndConfirm: Built entry - firestoreId=${entry.firestoreId}, supplierId=${entry.supplierId}, paymentMethod=${entry.paymentMethod}',
      );
      debugPrint(
        '📋 _saveAndConfirm: entry items=${entry.items.length}, canConfirm=${entry.canConfirm}',
      );

      bool success;
      if (widget.editEntry != null) {
        // Cập nhật phiếu đã có
        debugPrint('📋 _saveAndConfirm: Updating existing entry...');
        success = await _service.updateEntry(entry);
        debugPrint('📋 _saveAndConfirm: updateEntry result=$success');
      } else {
        // TẤT CẢ đều vào HÀNG CHỜ XÁC NHẬN trước
        // Không xác nhận ngay dù đầy đủ thông tin
        debugPrint('📋 _saveAndConfirm: Saving to pending (draft)...');
        final created = await _service.saveDraft(entry);
        success = created != null;
        debugPrint('📋 _saveAndConfirm: saveDraft result=$success');
      }

      if (success && mounted) {
        NotificationService.showSnackBar(
          'Đã lưu vào hàng chờ xác nhận. Vui lòng xác nhận để nhập kho chính.',
          color: Colors.green,
        );
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
          style: TextStyle(
            fontSize: AppTextStyles.headline3.fontSize,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
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
                          if (_isPhone)
                            _buildPhoneForm()
                          else
                            _buildAccessoryForm(),

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
                            style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
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
            Text(
              'Loại sản phẩm',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline5.fontSize),
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
              fontSize: AppTextStyles.subtitle1.fontSize,
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
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),


            TextFormField(
              controller: _labelInfoCtrl,
              decoration: const InputDecoration(
                labelText: 'Thông tin in trên tem',
                hintText: 'VD: BH 6T, Hàng mới',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_offer_outlined, size: 20),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
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
                  icon: const Icon(Icons.qr_code_scanner, size: 20),
                  color: Colors.blue,
                  tooltip: 'Quét IMEI',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextFormField(
              controller: _labelInfoCtrl,
              decoration: const InputDecoration(
                labelText: 'Thông tin in trên tem',
                hintText: 'VD: Bảo hành 6T, Máy đẹp 99%',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.local_offer_outlined, size: 20),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _brands
                        .map(
                          (b) => DropdownMenuItem(
                            value: b,
                            child: Text(
                              b,
                              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedBrand = v),
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.black87),
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _capacities
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCapacity = v),
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedColor,
                    decoration: const InputDecoration(
                      labelText: 'Màu sắc',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _colors
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedColor = v),
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.black87),
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _conditions
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedCondition = v),
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.black87),
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
                        enabled: _imeiCtrl.text
                            .trim()
                            .isEmpty, // Khóa khi có IMEI
                        decoration: InputDecoration(
                          labelText: 'SL',
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          filled: _imeiCtrl.text.trim().isNotEmpty,
                          fillColor: Colors.grey.shade200,
                        ),
                        style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
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
                            style: TextStyle(fontSize: AppTextStyles.overlineSize, color: Colors.grey),
                          ),
                        ),
                      // Hiển thị ghi chú nhập lô
                      if (_imeiCtrl.text.trim().isEmpty &&
                          (int.tryParse(_quantityCtrl.text) ?? 1) > 1)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            '📦 Nhập lô',
                            style: TextStyle(fontSize: AppTextStyles.overlineSize, color: Colors.blue),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            // Ghi chú nhập lô điện thoại
            if (_imeiCtrl.text.trim().isEmpty &&
                (int.tryParse(_quantityCtrl.text) ?? 1) > 1)
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.blue.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Nhập ${_quantityCtrl.text} máy → Khi xác nhận sẽ tạo ${_quantityCtrl.text} sản phẩm riêng biệt, mỗi máy có IMEI tạm (cần cập nhật sau)',
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                          color: Colors.blue.shade700,
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
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
              onChanged: (_) => setState(() {}),
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
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedUnit ?? 'Cái',
                    decoration: const InputDecoration(
                      labelText: 'Đơn vị',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _units
                        .map(
                          (u) => DropdownMenuItem(
                            value: u,
                            child: Text(
                              u,
                              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setState(() => _selectedUnit = v),
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.black87),
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
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
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
                Icon(
                  Icons.account_balance_wallet,
                  size: 18,
                  color: Colors.orange.shade700,
                ),
                const SizedBox(width: 8),
                Text(
                  'Thông tin kế toán',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextStyles.headline5.fontSize,
                    color: Colors.orange.shade700,
                  ),
                ),
                const Spacer(),
                Text(
                  '(Để trống nếu chưa biết)',
                  style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade600),
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
                    label: 'Giá vốn (VNĐ)',
                    icon: Icons.attach_money,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CurrencyTextField(
                    controller: _priceCtrl,
                    label: 'Giá bán (VNĐ)',
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
                    value:
                        _selectedSupplier != null &&
                            _suppliers.any(
                              (s) => s['name'] == _selectedSupplier,
                            )
                        ? _selectedSupplier
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Nhà cung cấp',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business, size: 20),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: _suppliers
                        .where(
                          (s) =>
                              s['name'] != null &&
                              s['name'].toString().isNotEmpty,
                        )
                        .map(
                          (s) => DropdownMenuItem(
                            value: s['name'] as String,
                            child: Text(
                              s['name'] ?? '',
                              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      final supplier = _suppliers.firstWhere(
                        (s) => s['name'] == v,
                        orElse: () => {},
                      );
                      setState(() {
                        _selectedSupplier = v;
                        _selectedSupplierId = supplier['firestoreId'];
                        _selectedSupplierLocalId = supplier['id'] as int?;
                      });
                    },
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _addNewSupplier,
                  icon: const Icon(
                    Icons.add_circle,
                    color: Colors.green,
                    size: 28,
                  ),
                  tooltip: 'Thêm NCC mới',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Phương thức thanh toán
            Text(
              'Phương thức thanh toán',
              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: _paymentMethods.map((method) {
                final isSelected = _selectedPaymentMethod == method;
                return ChoiceChip(
                  label: Text(method, style: TextStyle(fontSize: AppTextStyles.body1.fontSize)),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(
                      () => _selectedPaymentMethod = selected ? method : null,
                    );
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
    final missingInfo = _missingConfirmInfo;
    final hasMissing = missingInfo.isNotEmpty;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hiển thị thông tin còn thiếu
            if (hasMissing && !_isSaving)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.orange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Thiếu: ${missingInfo.join(", ")}',
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                          color: Colors.orange.shade700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                // Nút Lưu tạm - luôn hiện nếu có thể
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isSaving || !_canSaveDraft ? null : _saveDraft,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('LƯU TẠM'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: BorderSide(
                        color: _canSaveDraft
                            ? Colors.amber.shade700
                            : Colors.grey.shade400,
                      ),
                      foregroundColor: _canSaveDraft
                          ? Colors.amber.shade700
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Nút Lưu vào hàng chờ - đủ thông tin mới bật
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving || !_canConfirmNow
                        ? null
                        : _saveAndConfirm,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.inventory_2, size: 18),
                    label: Text(_isSaving ? 'Đang lưu...' : 'LƯU VÀO HÀNG CHỜ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canConfirmNow
                          ? Colors.green
                          : Colors.grey.shade400,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
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
        title: Text('Thêm NCC mới', style: TextStyle(fontSize: AppTextStyles.headline4.fontSize)),
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
                NotificationService.showSnackBar(
                  'Nhập tên NCC',
                  color: Colors.red,
                );
                return;
              }
              final shopId = await UserService.getCurrentShopId();
              final supplier = Supplier(
                name: nameCtrl.text.trim().toUpperCase(),
                phone: phoneCtrl.text.trim().isNotEmpty
                    ? phoneCtrl.text.trim()
                    : null,
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
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 1000,
    formats: [BarcodeFormat.all],
  );
  bool _scanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Quét IMEI', style: TextStyle(fontSize: AppTextStyles.headline4.fontSize)),
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
