import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/utils/money_utils.dart';
import '../controllers/fast_inventory_input_controller.dart';
import '../models/product_model.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/validated_text_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import 'stock_in_view.dart';

class FastInventoryInputView extends StatefulWidget {
  const FastInventoryInputView({super.key});

  @override
  State<FastInventoryInputView> createState() => _FastInventoryInputViewState();
}

class _FastInventoryInputViewState extends State<FastInventoryInputView> with TickerProviderStateMixin {
  final FastInventoryInputController _controller = FastInventoryInputController();
  late TabController _tabController;

  // Scanner
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isScanning = false;

  // Product data
  final TextEditingController _imeiController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  final TextEditingController _retailController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(text: "1");

  // SKU generation
  String _selectedGroup = 'IP';
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _infoController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();

  // Settings
  String _selectedType = 'PHONE';
  String _selectedSupplier = '';
  String _selectedPayment = 'TIỀN MẶT';
  List<Map<String, dynamic>> _suppliers = [];
  bool _isSaving = false;

  // Templates
  final List<Map<String, dynamic>> _productTemplates = [
    {
      'name': 'iPhone Template',
      'group': 'IP',
      'type': 'PHONE',
      'cost': 15000000,
      'kpk': 18000000,
      'retail': 20000000,
    },
    {
      'name': 'Samsung Template',
      'group': 'SS',
      'type': 'PHONE',
      'cost': 8000000,
      'kpk': 10000000,
      'retail': 12000000,
    },
    {
      'name': 'Phụ kiện Template',
      'group': 'PK',
      'type': 'ACCESSORY',
      'cost': 200000,
      'kpk': 300000,
      'retail': 400000,
    },
  ];

  // Batch import
  final List<Map<String, dynamic>> _batchItems = [];
  bool _isBatchMode = false;

  // Recent products
  List<Product> _recentProducts = [];
  bool _showRecent = false;

  // Manual input variables from StockInView
  final TextEditingController typeCtrl = TextEditingController();
  final TextEditingController brandCtrl = TextEditingController();
  final TextEditingController modelCtrl = TextEditingController();
  final TextEditingController capacityCtrl = TextEditingController();
  final TextEditingController colorCtrl = TextEditingController();
  final TextEditingController conditionCtrl = TextEditingController();
  final TextEditingController imeiCtrl = TextEditingController();
  final TextEditingController quantityCtrl = TextEditingController(text: '1');
  final TextEditingController costCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();
  final TextEditingController supplierCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();

  final FocusNode brandF = FocusNode();
  final FocusNode modelF = FocusNode();
  final FocusNode capacityF = FocusNode();
  final FocusNode colorF = FocusNode();
  final FocusNode imeiF = FocusNode();
  final FocusNode quantityF = FocusNode();
  final FocusNode costF = FocusNode();
  final FocusNode priceF = FocusNode();
  final FocusNode notesF = FocusNode();

  bool _brandChanged = false;
  bool _modelChanged = false;
  bool _capacityChanged = false;
  bool _colorChanged = false;
  bool _conditionChanged = false;
  bool _imeiChanged = false;
  bool _quantityChanged = false;
  bool _costChanged = false;
  bool _priceChanged = false;
  bool _supplierChanged = false;
  bool _notesChanged = false;

  final List<String> types = ['PHONE', 'ACCESSORY', 'LINHKIEN'];
  final List<String> conditions = ['Mới 100%', 'Mới 99%', 'Mới 95%', 'Mới 90%', 'Đã sử dụng'];
  String selectedPaymentMethod = 'Tiền mặt';
  DateTime selectedDate = DateTime.now();
  bool _saving = false;

  bool get _isAccessoryOrLinhKien => typeCtrl.text == 'ACCESSORY' || typeCtrl.text == 'LINHKIEN';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialData();
    
    // Listen for supplier changes
    EventBus().stream.listen((event) {
      if (event == 'suppliers_changed' && mounted) {
        _loadSuppliers();
      }
    });
  }

  Future<void> _loadInitialData() async {
    try {
      final suppliers = await _controller.getSuppliers();
      final recentProducts = await _controller.loadRecentProducts();

      if (mounted) {
        setState(() {
          _suppliers = suppliers;
          if (_suppliers.isNotEmpty) {
            _selectedSupplier = _suppliers.first['name'] as String;
          }
          _recentProducts = recentProducts;
        });
      }
    } catch (e) {
      NotificationService.showSnackBar("Lỗi tải dữ liệu: $e", color: AppColors.error);
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await _controller.getSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = suppliers;
          if (_suppliers.isNotEmpty && _selectedSupplier.isEmpty) {
            _selectedSupplier = _suppliers.first['name'] as String;
          }
        });
      }
    } catch (e) {
      NotificationService.showSnackBar("Lỗi tải nhà cung cấp: $e", color: AppColors.error);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    _imeiController.dispose();
    _nameController.dispose();
    _costController.dispose();
    _retailController.dispose();
    _detailController.dispose();
    _quantityController.dispose();
    _modelController.dispose();
    _infoController.dispose();
    _skuController.dispose();

    // Dispose manual input controllers
    typeCtrl.dispose();
    brandCtrl.dispose();
    modelCtrl.dispose();
    capacityCtrl.dispose();
    colorCtrl.dispose();
    imeiCtrl.dispose();
    quantityCtrl.dispose();
    costCtrl.dispose();
    priceCtrl.dispose();
    supplierCtrl.dispose();
    notesCtrl.dispose();
    brandF.dispose();
    modelF.dispose();
    capacityF.dispose();
    colorF.dispose();
    imeiF.dispose();
    quantityF.dispose();
    costF.dispose();
    priceF.dispose();
    notesF.dispose();
    super.dispose();
  }

  bool _validateForm() {
    if (typeCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng chọn loại hàng!", color: AppColors.error);
      return false;
    }
    if (brandCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng nhập loại!", color: AppColors.error);
      return false;
    }
    if (!_isAccessoryOrLinhKien && modelCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng nhập model!", color: AppColors.error);
      return false;
    }
    if (!_isAccessoryOrLinhKien && capacityCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng nhập dung lượng!", color: AppColors.error);
      return false;
    }
    if (colorCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng nhập màu/thông tin!", color: AppColors.error);
      return false;
    }
    if (quantityCtrl.text.isEmpty || int.tryParse(quantityCtrl.text) == null || int.parse(quantityCtrl.text) <= 0) {
      NotificationService.showSnackBar("Vui lòng nhập số lượng hợp lệ!", color: AppColors.error);
      return false;
    }
    if (costCtrl.text.isEmpty || CurrencyTextField.parseValue(costCtrl.text) <= 0) {
      NotificationService.showSnackBar("Vui lòng nhập giá nhập hợp lệ!", color: AppColors.error);
      return false;
    }
    if (supplierCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng chọn nhà cung cấp!", color: AppColors.error);
      return false;
    }
    return true;
  }

  Future<void> _saveProduct() async {
    if (!_validateForm()) return;

    setState(() => _saving = true);

    try {
      final productData = {
        'type': typeCtrl.text,
        'brand': brandCtrl.text,
        'model': modelCtrl.text,
        'capacity': capacityCtrl.text,
        'color': colorCtrl.text,
        'condition': conditionCtrl.text,
        'imei': imeiCtrl.text,
        'quantity': int.parse(quantityCtrl.text),
        'cost': CurrencyTextField.parseValue(costCtrl.text),
        'price': priceCtrl.text.isNotEmpty ? CurrencyTextField.parseValue(priceCtrl.text) : null,
        'supplier': supplierCtrl.text,
        'paymentMethod': selectedPaymentMethod,
        'notes': notesCtrl.text,
        'importDate': selectedDate,
        'importedBy': FirebaseAuth.instance.currentUser?.email?.split('@').first.toUpperCase() ?? "NV",
      };

      await _controller.saveProductBatch(productData);

      // Reset form
      _resetForm();

      NotificationService.showSnackBar("Đã lưu sản phẩm thành công!", color: AppColors.success);
      HapticFeedback.lightImpact();

      // Refresh recent products
      await _refreshRecentProducts();
    } catch (e) {
      NotificationService.showSnackBar("Lỗi lưu sản phẩm: $e", color: AppColors.error);
    } finally {
      setState(() => _saving = false);
    }
  }



  void _resetForm() {
    typeCtrl.clear();
    brandCtrl.clear();
    modelCtrl.clear();
    capacityCtrl.clear();
    colorCtrl.clear();
    conditionCtrl.clear();
    imeiCtrl.clear();
    quantityCtrl.text = '1';
    costCtrl.clear();
    priceCtrl.clear();
    supplierCtrl.clear();
    notesCtrl.clear();
    selectedDate = DateTime.now();
    selectedPaymentMethod = 'Tiền mặt';

    // Reset change tracking
    _brandChanged = false;
    _modelChanged = false;
    _capacityChanged = false;
    _colorChanged = false;
    _conditionChanged = false;
    _imeiChanged = false;
    _quantityChanged = false;
    _costChanged = false;
    _priceChanged = false;
    _supplierChanged = false;
    _notesChanged = false;
  }



  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  Widget _buildDropdownField({
    required String label,
    required TextEditingController controller,
    required List<String> items,
    FocusNode? nextFocus,
    IconData? icon,
    bool hasChanged = false,
  }) {
    return DropdownButtonFormField<String>(
      value: controller.text.isNotEmpty ? controller.text : null,
      style: AppTextStyles.caption.copyWith(
        color: hasChanged ? AppColors.primary : AppColors.onSurface,
        fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.caption.copyWith(
          color: hasChanged ? AppColors.primary : AppColors.onSurface,
          fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
        ),
        prefixIcon: icon != null ? Icon(icon, size: 16, color: hasChanged ? AppColors.primary : AppColors.onSurface.withOpacity(0.6)) : null,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: false, // Override theme to not fill background
        fillColor: hasChanged ? AppColors.primary.withOpacity(0.1) : null,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: hasChanged ? AppColors.primary : AppColors.outline,
            width: hasChanged ? 1.5 : 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: hasChanged ? const Color(0xFF1976D2) : Colors.blue,
            width: hasChanged ? 2.0 : 1.0,
          ),
        ),
      ),
      items: items.map((item) => DropdownMenuItem(
        value: item,
        child: Text(item, style: AppTextStyles.caption.copyWith(color: AppColors.onSurface)),
      )).toList(),
      onChanged: (value) {
        setState(() {
          controller.text = value!;
        });
        if (nextFocus != null) {
          FocusScope.of(context).requestFocus(nextFocus);
        }
      },
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required FocusNode focusNode,
    FocusNode? nextFocus,
    TextInputType keyboardType = TextInputType.text,
    IconData? icon,
    bool required = false,
    String? suffix,
    List<TextInputFormatter>? inputFormatters,
    bool hasChanged = false,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      textCapitalization: TextCapitalization.characters,
      inputFormatters: inputFormatters,
      style: AppTextStyles.caption.copyWith(
        color: hasChanged ? AppColors.primary : AppColors.onSurface,
        fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTextStyles.caption.copyWith(
          color: hasChanged ? AppColors.primary : AppColors.onSurface,
          fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
        ),
        prefixIcon: icon != null ? Icon(icon, size: 16, color: hasChanged ? AppColors.primary : AppColors.onSurface.withOpacity(0.6)) : null,
        suffixText: suffix,
        suffixStyle: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: false, // Override theme to not fill background
        // Add subtle background color when changed
        fillColor: hasChanged ? AppColors.primary.withOpacity(0.1) : null,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: hasChanged ? AppColors.primary : AppColors.outline,
            width: hasChanged ? 1.5 : 1.0,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: hasChanged ? const Color(0xFF1976D2) : Colors.blue,
            width: hasChanged ? 2.0 : 1.0,
          ),
        ),
      ),
      onChanged: (value) {
        controller.value = controller.value.copyWith(
          text: value.toUpperCase(),
          selection: TextSelection.collapsed(offset: value.length),
        );
      },
      onFieldSubmitted: (_) {
        if (nextFocus != null) {
          FocusScope.of(context).requestFocus(nextFocus);
        }
      },
    );
  }

  void _applyTemplate(Map<String, dynamic> template) {
    setState(() {
      _selectedGroup = template['group'];
      _selectedType = template['type'];
      _costController.text = CurrencyTextField.formatDisplay(template['cost'] as int? ?? 0);
      _retailController.text = CurrencyTextField.formatDisplay(template['retail'] as int? ?? 0);
    });
    NotificationService.showSnackBar("Đã áp dụng template: ${template['name']}", color: Colors.blue);
  }

  Future<void> _generateSKU() async {
    if (_selectedGroup.isEmpty) {
      NotificationService.showSnackBar("Vui lòng chọn nhóm sản phẩm!", color: Colors.red);
      return;
    }

    try {
      final generatedSKU = await _controller.generateSKU(
        group: _selectedGroup,
        model: _modelController.text.trim().isNotEmpty ? _modelController.text.trim() : null,
        info: _infoController.text.trim().isNotEmpty ? _infoController.text.trim() : null,
      );

      setState(() => _skuController.text = generatedSKU);
      NotificationService.showSnackBar("Đã tạo mã hàng: $generatedSKU", color: Colors.blue);
    } catch (e) {
      NotificationService.showSnackBar("Lỗi tạo mã hàng: $e", color: Colors.red);
    }
  }

  void _onScanResult(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String code = barcodes.first.rawValue ?? '';
      if (code.isNotEmpty) {
        setState(() {
          _imeiController.text = code;
          _isScanning = false;
        });
        NotificationService.showSnackBar("Đã scan: $code", color: Colors.green);
        _scannerController.stop();
      }
    }
  }





  Future<void> _saveBatch() async {
    if (_batchItems.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      // Parallel processing for better performance
      await _controller.saveBatchProducts(_batchItems);

      setState(() => _batchItems.clear());
      NotificationService.showSnackBar("Đã nhập kho ${_batchItems.length} sản phẩm thành công!", color: Colors.green);
      HapticFeedback.lightImpact();

      // Parallel refresh
      await _refreshRecentProducts();

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      NotificationService.showSnackBar("Lỗi khi nhập batch: $e", color: Colors.red);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _refreshRecentProducts() async {
    try {
      final recentProducts = await _controller.loadRecentProducts();
      if (mounted) {
        setState(() => _recentProducts = recentProducts);
      }
    } catch (e) {
      // Silent fail for refresh
    }
  }

  void _clearForm() {
    _imeiController.clear();
    _nameController.clear();
    _costController.clear();
    _retailController.clear();
    _detailController.clear();
    _quantityController.text = "1";
    _modelController.clear();
    _infoController.clear();
    _skuController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: Text(
          "NHẬP KHO SIÊU TỐC",
          style: AppTextStyles.headline6.copyWith(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.add_circle), text: "Nhập đơn"),
            Tab(icon: Icon(Icons.qr_code_scanner), text: "Scan QR"),
            Tab(icon: Icon(Icons.inventory), text: "Batch"),
          ],
          labelColor: const Color(0xFF2962FF),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF2962FF),
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => _showRecent = !_showRecent),
            icon: Icon(_showRecent ? Icons.history : Icons.history_outlined),
            tooltip: _showRecent ? "Ẩn sản phẩm gần đây" : "Hiện sản phẩm gần đây",
          ),
          if (_isBatchMode && _batchItems.isNotEmpty)
            IconButton(
              onPressed: _saveBatch,
              icon: const Icon(Icons.save, color: Colors.green),
              tooltip: "Lưu batch",
            ),
          IconButton(
            onPressed: () => setState(() => _isBatchMode = !_isBatchMode),
            icon: Icon(
              _isBatchMode ? Icons.batch_prediction : Icons.batch_prediction_outlined,
              color: _isBatchMode ? Colors.blue : Colors.grey,
            ),
            tooltip: _isBatchMode ? "Tắt chế độ batch" : "Bật chế độ batch",
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSingleInputTab(),
          _buildScannerTab(),
          _buildBatchTab(),
        ],
      ),
    );
  }

  Widget _buildSingleInputTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Loại hàng
          _buildDropdownField(
            label: 'Loại hàng *',
            controller: typeCtrl,
            items: types,
            icon: Icons.category,
          ),
          const SizedBox(height: 8),

          // Loại (thay cho Hãng, nhập tay được)
          _buildTextField(
            controller: brandCtrl,
            label: 'Loại *',
            focusNode: brandF,
            nextFocus: _isAccessoryOrLinhKien ? colorF : modelF,
            icon: Icons.business,
            hasChanged: _brandChanged,
          ),
          const SizedBox(height: 8),

          // Model (ẩn với accessory/linh kiện)
          if (!_isAccessoryOrLinhKien) ...[
            _buildTextField(
              controller: modelCtrl,
              label: 'Model *',
              focusNode: modelF,
              nextFocus: capacityF,
              icon: Icons.smartphone,
              hasChanged: _modelChanged,
            ),
            const SizedBox(height: 8),
          ],

          // Dung lượng (ẩn với accessory/linh kiện)
          if (!_isAccessoryOrLinhKien) ...[
            _buildTextField(
              controller: capacityCtrl,
              label: 'Dung lượng *',
              focusNode: capacityF,
              nextFocus: colorF,
              icon: Icons.memory,
              hasChanged: _capacityChanged,
            ),
            const SizedBox(height: 8),
          ],

          // Thông tin (thay cho Màu sắc)
          _buildTextField(
            controller: colorCtrl,
            label: 'Màu (Thông tin) *',
            focusNode: colorF,
            nextFocus: _isAccessoryOrLinhKien ? quantityF : imeiF,
            icon: Icons.info,
            hasChanged: _colorChanged,
          ),
          const SizedBox(height: 8),

          // Tình trạng máy
          _buildDropdownField(
            label: 'Tình trạng',
            controller: conditionCtrl,
            items: conditions,
            icon: Icons.check_circle,
            hasChanged: _conditionChanged,
          ),
          const SizedBox(height: 8),

          // IMEI/Serial (chỉ cho phone)
          if (!_isAccessoryOrLinhKien) ...[
            _buildTextField(
              controller: imeiCtrl,
              label: 'IMEI/Serial (5 số cuối)',
              focusNode: imeiF,
              nextFocus: quantityF,
              keyboardType: TextInputType.number,
              icon: Icons.qr_code,
              inputFormatters: [LengthLimitingTextInputFormatter(5)],
              hasChanged: _imeiChanged,
            ),
            const SizedBox(height: 8),
          ],

          // Số lượng (cho tất cả loại sản phẩm)
          _buildTextField(
            controller: quantityCtrl,
            label: 'Số lượng *',
            focusNode: quantityF,
            nextFocus: costF,
            keyboardType: TextInputType.number,
            icon: Icons.add_box,
            hasChanged: _quantityChanged,
          ),
          const SizedBox(height: 8),

          // Giá nhập
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CurrencyTextField(
              controller: costCtrl,
              label: 'Giá nhập (VNĐ) *',
              icon: Icons.attach_money,
              autoMultiply1000: true,
              onSubmitted: () => FocusScope.of(context).requestFocus(priceF),
            ),
          ),
          const SizedBox(height: 8),

          // Giá bán (cho accessory) hoặc Giá thay (cho linh kiện)
          if (_isAccessoryOrLinhKien) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CurrencyTextField(
                controller: priceCtrl,
                label: typeCtrl.text == 'ACCESSORY' ? 'Giá (VNĐ)' : 'Giá thay (VNĐ)',
                icon: Icons.sell,
                autoMultiply1000: true,
                onSubmitted: () => FocusScope.of(context).requestFocus(notesF),
              ),
            ),
          ] else ...[
            // Giá bán không phụ kiện (cho phone)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CurrencyTextField(
                controller: priceCtrl,
                label: 'Giá bán (VNĐ)',
                icon: Icons.sell,
                autoMultiply1000: true,
                onSubmitted: () => FocusScope.of(context).requestFocus(notesF),
              ),
            ),
          ],

          // Nhà cung cấp
          DropdownButtonFormField<String>(
            value: supplierCtrl.text.isNotEmpty ? supplierCtrl.text : null,
            style: AppTextStyles.caption.copyWith(
              color: _supplierChanged ? AppColors.primary : AppColors.onSurface,
              fontWeight: _supplierChanged ? FontWeight.bold : FontWeight.normal,
            ),
            dropdownColor: AppColors.surface,
            decoration: InputDecoration(
              labelText: 'Nhà cung cấp *',
              labelStyle: AppTextStyles.caption.copyWith(
                color: _supplierChanged ? AppColors.primary : AppColors.onSurface,
                fontWeight: _supplierChanged ? FontWeight.bold : FontWeight.normal,
              ),
              prefixIcon: Icon(
                Icons.business_center,
                size: 16,
                color: _supplierChanged ? AppColors.primary : AppColors.onSurface.withOpacity(0.6),
              ),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              filled: false,
              fillColor: _supplierChanged ? AppColors.primary.withOpacity(0.1) : null,
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: _supplierChanged ? const Color(0xFF1976D2) : Colors.grey.shade400,
                  width: _supplierChanged ? 1.5 : 1.0,
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 1.0),
              ),
            ),
            items: _suppliers.map((supplier) => DropdownMenuItem<String>(
              value: supplier['name'] as String,
              child: Text(
                supplier['name'] as String,
                style: AppTextStyles.caption.copyWith(
                  color: _supplierChanged ? AppColors.primary : AppColors.onSurface,
                  fontWeight: _supplierChanged ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            )).toList(),
            onChanged: (value) {
              setState(() {
                supplierCtrl.text = value!;
              });
            },
          ),
          const SizedBox(height: 8),

          // Payment method
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Phương thức thanh toán', style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text('Công nợ', style: AppTextStyles.caption),
                      value: 'Công nợ',
                      groupValue: selectedPaymentMethod,
                      onChanged: (value) => setState(() => selectedPaymentMethod = value!),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text('Tiền mặt', style: AppTextStyles.caption),
                      value: 'Tiền mặt',
                      groupValue: selectedPaymentMethod,
                      onChanged: (value) => setState(() => selectedPaymentMethod = value!),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: Text('Chuyển khoản', style: AppTextStyles.caption),
                      value: 'Chuyển khoản',
                      groupValue: selectedPaymentMethod,
                      onChanged: (value) => setState(() => selectedPaymentMethod = value!),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Ngày nhập
          InkWell(
            onTap: () => _selectDate(context),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Ngày nhập',
                labelStyle: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.7)),
                prefixIcon: Icon(Icons.calendar_today, size: 16),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              ),
              child: Text(
                '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                style: AppTextStyles.caption,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Ghi chú
          _buildTextField(
            controller: notesCtrl,
            label: 'Ghi chú',
            focusNode: notesF,
            icon: Icons.note,
            hasChanged: _notesChanged,
          ),
          const SizedBox(height: 16),

          // Save button
          ElevatedButton(
            onPressed: _saving ? null : _saveProduct,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: _saving
                ? CircularProgressIndicator(color: AppColors.onPrimary)
                : Text('LƯU', style: AppTextStyles.button.copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerTab() {
    return Column(
      children: [
        Expanded(
          child: _isScanning
              ? MobileScanner(
                  controller: _scannerController,
                  onDetect: _onScanResult,
                )
              : Container(
                  color: Colors.black,
                  child: const Center(
                    child: Text(
                      "Camera chưa được khởi động",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _isScanning = !_isScanning);
                        if (_isScanning) {
                          _scannerController.start();
                        } else {
                          _scannerController.stop();
                        }
                      },
                      icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                      label: Text(_isScanning ? "DỪNG SCAN" : "BẮT ĐẦU SCAN"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isScanning ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => _scannerController.toggleTorch(),
                    icon: const Icon(Icons.flashlight_on),
                    tooltip: "Bật/tắt đèn flash",
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ValidatedTextField(
                controller: _imeiController,
                label: "IMEI/Serial (có thể nhập thủ công)",
                icon: Icons.fingerprint,
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBatchTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "DANH SÁCH BATCH (${_batchItems.length})",
                style: AppTextStyles.headline6.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              if (_batchItems.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _saveBatch,
                  icon: Icon(Icons.save, color: AppColors.onSuccess),
                  label: Text("LƯU TẤT CẢ", style: AppTextStyles.button),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: AppColors.onSuccess,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _batchItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        "Chưa có sản phẩm nào trong batch",
                        style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Chuyển sang tab 'Nhập đơn' và bật chế độ batch",
                        style: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _batchItems.length,
                  itemBuilder: (context, index) {
                    final item = _batchItems[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(item['name']),
                        subtitle: Text("IMEI: ${item['imei']} • Giá: ${MoneyUtils.formatVND(item['price'])}đ"),
                        trailing: IconButton(
                          onPressed: () => setState(() => _batchItems.removeAt(index)),
                          icon: const Icon(Icons.delete, color: Colors.red),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}