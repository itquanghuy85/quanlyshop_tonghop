import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/supplier_service.dart';
import '../services/event_bus.dart';
import '../services/sync_orchestrator.dart';
import '../utils/imei_extractor.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/imei_scan_result_dialog.dart';
import 'fast_stock_in_view.dart';
import '../models/debt_model.dart';

class StockInView extends StatefulWidget {
  final Map<String, dynamic>? prefilledData;

  const StockInView({super.key, this.prefilledData});

  @override
  State<StockInView> createState() => _StockInViewState();
}

class _StockInViewState extends State<StockInView> {
  final db = DBHelper();
  bool _saving = false;

  // Controllers
  final typeCtrl = TextEditingController(text: 'PHONE');
  final brandCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  final capacityCtrl = TextEditingController();
  final colorCtrl = TextEditingController();
  final conditionCtrl = TextEditingController(text: 'MỚI');
  final imeiCtrl = TextEditingController();
  final quantityCtrl = TextEditingController(text: '1');
  final costCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final supplierCtrl = TextEditingController();
  final notesCtrl = TextEditingController();
  DateTime selectedDate = DateTime.now();

  // Payment method - UPPERCASE to match fast_stock_in_view
  String selectedPaymentMethod = 'CÔNG NỢ';

  // EventBus subscription for memory leak prevention
  late final Stream<String> _eventStream;
  bool _eventListenerAttached = false;

  // Focus nodes
  final brandF = FocusNode();
  final modelF = FocusNode();
  final capacityF = FocusNode();
  final colorF = FocusNode();
  final imeiF = FocusNode();
  final quantityF = FocusNode();
  final costF = FocusNode();
  final priceF = FocusNode();
  final notesF = FocusNode();

  // Track field changes for visual feedback
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

  // Dropdown options
  final List<String> types = ['PHONE', 'ACCESSORY', 'LINHKIEN'];
  // Đồng bộ với fast_stock_in_view.dart
  final List<String> conditions = ['MỚI', '99', 'KHÁC'];
  List<Map<String, dynamic>> suppliers = [];

  // Computed property to check if current type is accessory or linh kiện
  bool get _isAccessoryOrLinhKien => typeCtrl.text == 'ACCESSORY' || typeCtrl.text == 'LINHKIEN';

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
    imeiCtrl.addListener(_onImeiChanged);

    // Listen for supplier changes - store reference for cleanup
    _eventStream = EventBus().stream;
    _eventListenerAttached = true;
    _eventStream.listen((event) {
      if (!_eventListenerAttached) return;
      if (event == 'suppliers_changed' && mounted) {
        _loadSuppliers();
      }
    });

    // Add listeners to track field changes
    brandCtrl.addListener(() => _onFieldChanged(brandCtrl, (changed) => _brandChanged = changed));
    modelCtrl.addListener(() => _onFieldChanged(modelCtrl, (changed) => _modelChanged = changed));
    capacityCtrl.addListener(() => _onFieldChanged(capacityCtrl, (changed) => _capacityChanged = changed));
    colorCtrl.addListener(() => _onFieldChanged(colorCtrl, (changed) => _colorChanged = changed));
    conditionCtrl.addListener(() => _onFieldChanged(conditionCtrl, (changed) => _conditionChanged = changed));
    imeiCtrl.addListener(() => _onFieldChanged(imeiCtrl, (changed) => _imeiChanged = changed));
    quantityCtrl.addListener(() => _onFieldChanged(quantityCtrl, (changed) => _quantityChanged = changed));
    costCtrl.addListener(() => _onFieldChanged(costCtrl, (changed) => _costChanged = changed));
    priceCtrl.addListener(() => _onFieldChanged(priceCtrl, (changed) => _priceChanged = changed));
    // CurrencyTextField handles formatting automatically - no need for format listeners
    supplierCtrl.addListener(() => _onFieldChanged(supplierCtrl, (changed) => _supplierChanged = changed));
    notesCtrl.addListener(() => _onFieldChanged(notesCtrl, (changed) => _notesChanged = changed));

    // Fill data from prefilledData if available
    if (widget.prefilledData != null) {
      _fillPrefilledData();
    }
  }

  void _fillPrefilledData() {
    final data = widget.prefilledData!;
    setState(() {
      typeCtrl.text = data['type'] ?? 'PHONE';
      brandCtrl.text = data['brand'] ?? '';
      modelCtrl.text = data['model'] ?? '';
      capacityCtrl.text = data['capacity'] ?? '';
      colorCtrl.text = data['color'] ?? '';
      conditionCtrl.text = data['condition'] ?? 'MỚI';
      imeiCtrl.text = data['imei'] ?? '';
      quantityCtrl.text = data['quantity']?.toString() ?? '1';
      costCtrl.text = data['cost'] != null ? CurrencyTextField.formatDisplay(data['cost'] as int) : '';
      priceCtrl.text = data['price'] != null ? CurrencyTextField.formatDisplay(data['price'] as int) : '';
      supplierCtrl.text = data['supplier'] ?? '';
      selectedPaymentMethod = data['paymentMethod'] ?? 'Công nợ';
      notesCtrl.text = data['notes'] ?? '';
      // Set brand from SKU if available and brand is empty
      if (brandCtrl.text.isEmpty && data['name'] != null && data['name'].toString().isNotEmpty) {
        brandCtrl.text = _extractBrandFromSKU(data['name']);
      }

      // Set changed flags for prefilled data
      _brandChanged = brandCtrl.text.isNotEmpty;
      _modelChanged = modelCtrl.text.isNotEmpty;
      _capacityChanged = capacityCtrl.text.isNotEmpty;
      _colorChanged = colorCtrl.text.isNotEmpty;
      _conditionChanged = conditionCtrl.text != 'MỚI';
      _imeiChanged = imeiCtrl.text.isNotEmpty;
      _quantityChanged = quantityCtrl.text != '1';
      _costChanged = costCtrl.text.isNotEmpty;
      _priceChanged = priceCtrl.text.isNotEmpty;
      _supplierChanged = supplierCtrl.text.isNotEmpty;
      _notesChanged = notesCtrl.text.isNotEmpty;
    });
  }

  String _extractBrandFromSKU(String sku) {
    // Extract brand from SKU (e.g., "IP15PM" -> "iPhone")
    if (sku.startsWith('IP')) return 'iPhone';
    if (sku.startsWith('SS')) return 'Samsung';
    if (sku.startsWith('PK')) return 'Phụ kiện';
    return '';
  }

  int _parseMoneyWithK(String text) {
    // CurrencyTextField stores formatted value (e.g., "500.000" for 500000 VND)
    // parseValue removes formatting and returns the integer
    return CurrencyTextField.parseValue(text);
  }

  // _formatCost and _formatPrice removed - CurrencyTextField handles formatting automatically

  void _onFieldChanged(TextEditingController controller, Function(bool) setChanged) {
    final hasText = controller.text.trim().isNotEmpty;
    if (hasText != setChanged) { // Only update if state actually changed
      setState(() => setChanged(hasText));
    }
  }

  @override
  void dispose() {
    imeiCtrl.removeListener(_onImeiChanged);
    // Remove field change listeners
    brandCtrl.removeListener(() => _onFieldChanged(brandCtrl, (changed) => _brandChanged = changed));
    modelCtrl.removeListener(() => _onFieldChanged(modelCtrl, (changed) => _modelChanged = changed));
    capacityCtrl.removeListener(() => _onFieldChanged(capacityCtrl, (changed) => _capacityChanged = changed));
    colorCtrl.removeListener(() => _onFieldChanged(colorCtrl, (changed) => _colorChanged = changed));
    conditionCtrl.removeListener(() => _onFieldChanged(conditionCtrl, (changed) => _conditionChanged = changed));
    imeiCtrl.removeListener(() => _onFieldChanged(imeiCtrl, (changed) => _imeiChanged = changed));
    quantityCtrl.removeListener(() => _onFieldChanged(quantityCtrl, (changed) => _quantityChanged = changed));
    costCtrl.removeListener(() => _onFieldChanged(costCtrl, (changed) => _costChanged = changed));
    priceCtrl.removeListener(() => _onFieldChanged(priceCtrl, (changed) => _priceChanged = changed));
    // CurrencyTextField handles formatting - no format listeners to remove
    supplierCtrl.removeListener(() => _onFieldChanged(supplierCtrl, (changed) => _supplierChanged = changed));
    notesCtrl.removeListener(() => _onFieldChanged(notesCtrl, (changed) => _notesChanged = changed));
    // Disable EventBus listener to prevent memory leak
    _eventListenerAttached = false;
    // Dispose controllers and focus nodes
    typeCtrl.dispose();
    brandCtrl.dispose();
    modelCtrl.dispose();
    capacityCtrl.dispose();
    colorCtrl.dispose();
    conditionCtrl.dispose();
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

  void _onImeiChanged() {
    if (imeiCtrl.text.isNotEmpty) {
      quantityCtrl.text = '1';
    }
  }

  Future<void> _loadSuppliers() async {
    final supplierService = SupplierService();
    final sups = await supplierService.getSuppliers();
    setState(() {
      suppliers = sups.map((s) => s.toMap()).toList();
      if (suppliers.isNotEmpty && suppliers.first['name'] != null) {
        supplierCtrl.text = suppliers.first['name'] as String;
      }
    });
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

  Future<bool> _validateForm() async {
    if (brandCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng nhập loại!", color: Colors.red);
      return false;
    }

    // Chỉ validate model và capacity cho phone
    if (!_isAccessoryOrLinhKien) {
      if (modelCtrl.text.isEmpty) {
        NotificationService.showSnackBar("Vui lòng nhập model!", color: Colors.red);
        return false;
      }
      if (capacityCtrl.text.isEmpty) {
        NotificationService.showSnackBar("Vui lòng nhập dung lượng!", color: Colors.red);
        return false;
      }
    }

    if (colorCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng nhập màu sắc!", color: Colors.red);
      return false;
    }

    // IMEI không cần unique - cho phép nhập trùng

    final quantity = int.tryParse(quantityCtrl.text);
    if (quantity == null || quantity <= 0) {
      NotificationService.showSnackBar("Số lượng phải là số dương!", color: Colors.red);
      return false;
    }
    final cost = _parseMoneyWithK(costCtrl.text);
    if (cost <= 0) {
      NotificationService.showSnackBar("Giá nhập phải lớn hơn 0!", color: Colors.red);
      return false;
    }
    final price = _parseMoneyWithK(priceCtrl.text);
    if (price < 0) {
      NotificationService.showSnackBar("Giá bán không được âm!", color: Colors.red);
      return false;
    }

    if (supplierCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng chọn nhà cung cấp!", color: Colors.red);
      return false;
    }
    return true;
  }

  Future<void> _saveProduct() async {
    if (!(await _validateForm())) return;

    setState(() => _saving = true);

    try {
      final ts = selectedDate.millisecondsSinceEpoch;
      final imei = imeiCtrl.text.trim();
      // Tạo unique firestoreId để tránh conflict
      final uniqueSuffix = imei.isNotEmpty ? imei : "${ts}_${DateTime.now().millisecondsSinceEpoch}";
      final fId = "prod_${ts}_${uniqueSuffix}";

      final quantity = int.tryParse(quantityCtrl.text) ?? 0;

      // Validate product name
      final productName = _isAccessoryOrLinhKien
          ? '${brandCtrl.text} ${colorCtrl.text}'.trim().toUpperCase()
          : '${brandCtrl.text} ${modelCtrl.text}'.trim().toUpperCase();
      
      if (productName.isEmpty || productName == brandCtrl.text.toUpperCase()) {
        throw Exception("Tên sản phẩm không hợp lệ. Vui lòng nhập đầy đủ thông tin!");
      }

      final product = Product(
        firestoreId: fId,
        name: productName,
        brand: brandCtrl.text.toUpperCase(),
        model: modelCtrl.text.trim().isNotEmpty ? modelCtrl.text.trim() : null,
        imei: (!_isAccessoryOrLinhKien && imei.isNotEmpty) ? imei : null,
        cost: _parseMoneyWithK(costCtrl.text),
        price: _parseMoneyWithK(priceCtrl.text),
        condition: conditionCtrl.text,
        status: 1,
        description: notesCtrl.text.trim(),
        createdAt: ts,
        updatedAt: ts, // Thêm updatedAt để sort đúng
        supplier: supplierCtrl.text,
        type: typeCtrl.text,
        quantity: quantity,
        color: colorCtrl.text.trim().toUpperCase(),
        capacity: !_isAccessoryOrLinhKien ? capacityCtrl.text.trim().toUpperCase() : null,
        paymentMethod: selectedPaymentMethod,
      );

      // Validate cost and price
      if (product.cost <= 0) {
        throw Exception("Giá nhập phải lớn hơn 0!");
      }
      if (product.price < 0) {
        throw Exception("Giá bán không được âm!");
      }

      await db.upsertProduct(product);
      
      // Generate firestoreId if needed and queue sync
      if (product.firestoreId == null || product.firestoreId!.isEmpty) {
        final shopId = await UserService.getCurrentShopId();
        product.firestoreId = 'product_${shopId}_${DateTime.now().millisecondsSinceEpoch}';
      }
      product.isSynced = false;
      await db.upsertProduct(product);
      
      // Get product ID after upsert
      final productFromDb = await db.getProductByFirestoreId(product.firestoreId!);
      final productId = productFromDb?.id ?? 0;
      
      // Queue sync via SyncOrchestrator
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.product,
        entityId: productId,
        firestoreId: product.firestoreId,
        operation: SyncOperation.create,
        data: product.toMap(),
      );

      // Lưu lịch sử nhập hàng từ nhà cung cấp
      if (supplierCtrl.text.isNotEmpty) {
        final supplierData = suppliers.firstWhere((s) => s['name'] == supplierCtrl.text, orElse: () => {});
        final supplierId = supplierData['id'];
        if (supplierId != null) {
          // Log action
          final user = FirebaseAuth.instance.currentUser;
          final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";
          final shopId = await UserService.getCurrentShopId();

          final importHistory = {
            'supplierId': supplierId,
            'supplierName': supplierCtrl.text,
            'productName': product.name,
            'productBrand': product.brand,
            'productModel': product.model,
            'imei': product.imei,
            'quantity': quantity,
            'costPrice': product.cost,
            'totalAmount': product.cost * quantity,
            'paymentMethod': selectedPaymentMethod,
            'importDate': ts,
            'importedBy': userName,
            'notes': notesCtrl.text.trim(),
            'shopId': shopId,
            'isSynced': 0,
          };
          await db.insertSupplierImportHistory(importHistory);

          // Cập nhật giá nhà cung cấp
          await db.deactivateSupplierProductPrice(supplierId, product.name, product.brand, product.model);
          final supplierPrice = {
            'supplierId': supplierId,
            'productName': product.name,
            'productBrand': product.brand,
            'productModel': product.model,
            'costPrice': product.cost,
            'lastUpdated': ts,
            'createdAt': ts,
            'isActive': 1,
            'shopId': shopId,
          };
          await db.insertSupplierProductPrice(supplierPrice);

          // Cập nhật thống kê nhà cung cấp
          await db.updateSupplierStats(supplierId, product.cost * quantity, quantity);
        }
      }

      // Log action
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";
      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: "NHẬP KHO",
        type: "PRODUCT",
        targetId: product.imei ?? product.firestoreId,
        desc: "Đã nhập ${product.name}",
      );

      NotificationService.showSnackBar("Nhập kho thành công!", color: Colors.green);

      // Send chat notification
      await FirestoreService.sendChat(
        message: "📦 Đã nhập kho: ${product.name} (${product.imei ?? 'No IMEI'}) - SL: ${quantityCtrl.text} - NCC: ${supplierCtrl.text.isNotEmpty ? supplierCtrl.text : 'N/A'}",
        senderId: user?.uid ?? "system",
        senderName: userName,
        linkedType: "PRODUCT",
        linkedKey: product.imei ?? product.firestoreId,
        linkedSummary: product.name,
      );

      // Chi phí/công nợ NCC
      if (selectedPaymentMethod == 'CÔNG NỢ') {
        final supplierData = suppliers.firstWhere((s) => s['name'] == supplierCtrl.text, orElse: () => {});
        final supplierPhone = supplierData['phone']?.toString() ?? '';
        final debt = Debt(
          personName: supplierCtrl.text,
          phone: supplierPhone,
          totalAmount: product.cost * product.quantity,
          paidAmount: 0,
          type: 'SHOP_OWES',
          status: 'ACTIVE',
          createdAt: ts,
          note: 'Công nợ nhập hàng ${product.name}',
          linkedId: product.firestoreId,
        );
        debt.firestoreId = "debt_${ts}_${supplierPhone.isNotEmpty ? supplierPhone : supplierCtrl.text.hashCode}";
        try {
          await db.upsertDebt(debt);
          // Get debt ID after upsert and queue sync
          final debtId = await db.getDebtIdByFirestoreId(debt.firestoreId!);
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.debt,
            entityId: debtId ?? 0,
            firestoreId: debt.firestoreId,
            operation: SyncOperation.create,
            data: debt.toMap(),
          );
        } catch (e) {
          debugPrint('StockIn: Debt creation error: $e');
          NotificationService.showSnackBar("Lỗi tạo công nợ: $e", color: Colors.red);
        }
      } else {
        await _addStockInExpense(product);
      }

      // Notify UI update for suppliers
      EventBus().emit('suppliers_changed');
      Navigator.of(context).pop();
    } catch (e) {
      NotificationService.showSnackBar("Lỗi khi nhập kho: $e", color: Colors.red);
    } finally {
      setState(() => _saving = false);
    }
  }

  // THÊM CHI PHÍ NHẬP KHO VÀO TRANG CHI PHÍ
  Future<void> _addStockInExpense(Product product) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";
      final shopId = await UserService.getCurrentShopId();
      final firestoreId = 'expense_${shopId}_${DateTime.now().millisecondsSinceEpoch}';

      final expense = {
        'amount': product.cost * product.quantity,
        'category': 'NHẬP HÀNG',
        'description': 'Nhập kho thủ công: ${product.name} - SL: ${product.quantity}',
        'createdAt': DateTime.now().millisecondsSinceEpoch,
        'createdBy': userName,
        'linkedId': product.firestoreId,
        'paymentMethod': selectedPaymentMethod,
        'isSynced': false,
        'firestoreId': firestoreId,
        'shopId': shopId,
      };

      // Thêm vào local DB
      final expenseId = await db.insertExpense(expense);

      // Queue sync via SyncOrchestrator
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.expense,
        entityId: expenseId,
        firestoreId: firestoreId,
        operation: SyncOperation.create,
        data: expense,
      );

      // Notify expense change
      EventBus().emit('expenses_changed');

      debugPrint('Đã thêm chi phí nhập kho: ${product.cost * product.quantity} cho ${product.name}');
    } catch (e) {
      debugPrint('Lỗi thêm chi phí nhập kho: $e');
      // Không throw error để không làm fail stock in
    }
  }

  /// Mở scanner QR/Barcode để quét IMEI - xử lý thông minh QR nhiều dòng
  void _openQRScannerForIMEI() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SmartIMEIScannerSheet(
        onIMEISelected: (imei) {
          setState(() {
            imeiCtrl.text = imei;
            _imeiChanged = true;
          });
        },
      ),
    );
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
      initialValue: controller.text.isNotEmpty ? controller.text : null,
      style: TextStyle(
        fontSize: 12,
        color: hasChanged ? const Color(0xFF1976D2) : Colors.black87,
        fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 12,
          color: hasChanged ? const Color(0xFF1976D2) : Colors.black87,
          fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
        ),
        prefixIcon: icon != null ? Icon(icon, size: 16, color: hasChanged ? const Color(0xFF1976D2) : Colors.black54) : null,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: false, // Override theme to not fill background
        fillColor: hasChanged ? const Color(0xFFE3F2FD).withAlpha(50) : null,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: hasChanged ? const Color(0xFF1976D2) : Colors.grey.shade400,
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
        child: Text(item, style: const TextStyle(fontSize: 12, color: Colors.black87)),
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
      style: TextStyle(
        fontSize: 12,
        color: hasChanged ? const Color(0xFF1976D2) : Colors.black87, // Blue color when changed
        fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          fontSize: 12,
          color: hasChanged ? const Color(0xFF1976D2) : Colors.black87,
          fontWeight: hasChanged ? FontWeight.bold : FontWeight.normal,
        ),
        prefixIcon: icon != null ? Icon(icon, size: 16, color: hasChanged ? const Color(0xFF1976D2) : Colors.black54) : null,
        suffixText: suffix,
        suffixStyle: const TextStyle(fontSize: 10, color: Colors.grey),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: false, // Override theme to not fill background
        // Add subtle background color when changed
        fillColor: hasChanged ? const Color(0xFFE3F2FD).withAlpha(50) : null,
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: hasChanged ? const Color(0xFF1976D2) : Colors.grey.shade400,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhập Kho'),
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            tooltip: 'Nhập kho nhanh từ mã',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FastStockInView()),
              );
            },
          ),
        ],
      ),
      backgroundColor: const Color(0xFFF0F4F8),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
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
            if (!_isAccessoryOrLinhKien) ...[              Row(
                children: [
                  Expanded(
                    child:
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
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _openQRScannerForIMEI,
                    icon: const Icon(Icons.qr_code_scanner, color: Colors.green),
                    tooltip: 'Quét QR/Barcode IMEI',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
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

            // Giá nhập - sử dụng CurrencyTextField chuẩn hóa
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
              const SizedBox(height: 8),
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
              const SizedBox(height: 8),
            ],

            // Nhà cung cấp
            Builder(
              builder: (context) {
                // Fix: đảm bảo value nằm trong danh sách suppliers
                final supplierNames = suppliers.map((s) => s['name'] as String).toList();
                final validValue = (supplierCtrl.text.isNotEmpty && supplierNames.contains(supplierCtrl.text)) 
                    ? supplierCtrl.text 
                    : null;
                return DropdownButtonFormField<String>(
                  initialValue: validValue,
                  style: TextStyle(
                    fontSize: 12,
                    color: _supplierChanged ? const Color(0xFF1976D2) : Colors.black87,
                fontWeight: _supplierChanged ? FontWeight.bold : FontWeight.normal,
              ),
              dropdownColor: Colors.white,
              decoration: InputDecoration(
                labelText: 'Nhà cung cấp *',
                labelStyle: TextStyle(
                  fontSize: 12,
                  color: _supplierChanged ? const Color(0xFF1976D2) : Colors.black87,
                  fontWeight: _supplierChanged ? FontWeight.bold : FontWeight.normal,
                ),
                prefixIcon: Icon(
                  Icons.business_center,
                  size: 16,
                  color: _supplierChanged ? const Color(0xFF1976D2) : Colors.black54,
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                filled: false,
                fillColor: _supplierChanged ? const Color(0xFFE3F2FD).withAlpha(50) : null,
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
              items: suppliers.map((supplier) => DropdownMenuItem<String>(
                value: supplier['name'] as String,
                child: Text(
                  supplier['name'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: _supplierChanged ? const Color(0xFF1976D2) : Colors.black87,
                    fontWeight: _supplierChanged ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              )).toList(),
                  onChanged: (value) {
                    setState(() {
                      supplierCtrl.text = value!;
                    });
                  },
                );
              },
            ),
            const SizedBox(height: 8),

            // Payment method - values must match UPPERCASE constants
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Phương thức thanh toán', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Công nợ', style: TextStyle(fontSize: 12)),
                        value: 'CÔNG NỢ',
                        groupValue: selectedPaymentMethod,
                        onChanged: (value) => setState(() => selectedPaymentMethod = value!),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Tiền mặt', style: TextStyle(fontSize: 12)),
                        value: 'TIỀN MẶT',
                        groupValue: selectedPaymentMethod,
                        onChanged: (value) => setState(() => selectedPaymentMethod = value!),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Chuyển khoản', style: TextStyle(fontSize: 12)),
                        value: 'CHUYỂN KHOẢN',
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
                decoration: const InputDecoration(
                  labelText: 'Ngày nhập',
                  labelStyle: TextStyle(fontSize: 12),
                  prefixIcon: Icon(Icons.calendar_today, size: 16),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                ),
                child: Text(
                  '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Ghi chú
            _buildTextField(
              controller: notesCtrl,
              label: 'Ghi chú',
              focusNode: notesF,
            ),

            // Save button
            ElevatedButton(
              onPressed: _saving ? null : _saveProduct,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: _saving
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('LƯU', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SMART IMEI SCANNER SHEET - Xử lý thông minh QR nhiều dòng
// ============================================================

class _SmartIMEIScannerSheet extends StatefulWidget {
  final Function(String imei) onIMEISelected;

  const _SmartIMEIScannerSheet({required this.onIMEISelected});

  @override
  State<_SmartIMEIScannerSheet> createState() => _SmartIMEIScannerSheetState();
}

class _SmartIMEIScannerSheetState extends State<_SmartIMEIScannerSheet> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  String? _lastScannedData;
  DateTime? _lastScanTime;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionTimeoutMs: 500,
      returnImage: false,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue ?? '';
    if (rawValue.isEmpty) return;

    // Debounce: Tránh quét trùng trong 2 giây
    final now = DateTime.now();
    if (_lastScannedData == rawValue &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
      return;
    }

    _lastScannedData = rawValue;
    _lastScanTime = now;

    setState(() => _isProcessing = true);

    try {
      // Trích xuất IMEI từ QR data
      final result = IMEIExtractor.extract(rawValue);

      // Nếu có 1 IMEI duy nhất và không phải multi-line phức tạp
      if (result.candidates.length == 1 && !result.isMultiLine) {
        final imei = result.candidates.first;
        final last5 = IMEIExtractor.getLast5Digits(imei);

        Navigator.of(context).pop();
        widget.onIMEISelected(last5);
        NotificationService.showSnackBar(
          '✅ IMEI: ${IMEIExtractor.formatIMEI(imei)} → 5 số cuối: $last5',
          color: Colors.green,
        );
      }
      // Nếu có nhiều candidates hoặc QR phức tạp -> hiện dialog chọn
      else if (result.candidates.isNotEmpty) {
        await _controller?.stop();

        if (!mounted) return;

        final selected = await IMEIScanResultDialog.show(context, result);

        if (selected != null && selected.isNotEmpty) {
          Navigator.of(context).pop();
          widget.onIMEISelected(selected);
          NotificationService.showSnackBar(
            '✅ Đã chọn: $selected',
            color: Colors.green,
          );
        } else {
          await _controller?.start();
        }
      }
      // Không tìm thấy IMEI -> thử lấy raw digits
      else {
        final digitsOnly = rawValue.replaceAll(RegExp(r'[^0-9]'), '');
        if (digitsOnly.length >= 5) {
          final last5 = digitsOnly.substring(digitsOnly.length - 5);

          Navigator.of(context).pop();
          widget.onIMEISelected(last5);
          NotificationService.showSnackBar(
            '⚠️ Không tìm thấy IMEI, dùng 5 số cuối: $last5',
            color: Colors.orange,
          );
        } else {
          NotificationService.showSnackBar(
            '❌ Không tìm thấy số IMEI trong QR',
            color: Colors.red,
          );
        }
      }
    } catch (e) {
      NotificationService.showSnackBar(
        '❌ Lỗi xử lý QR: $e',
        color: Colors.red,
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'QUÉT QR/BARCODE IMEI',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Hướng dẫn
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.blue.shade50,
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hỗ trợ QR nhiều dòng (Apple, Samsung...).\n'
                    'Tự động trích xuất IMEI và cho phép chọn nếu có nhiều số.',
                    style: TextStyle(fontSize: 12, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),

          // Scanner area
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                ),
                // Scan area overlay
                Center(
                  child: Container(
                    width: 280,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                // Processing indicator
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _controller?.toggleTorch(),
                  icon: const Icon(Icons.flashlight_on),
                  tooltip: 'Bật/tắt đèn flash',
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: () => _controller?.switchCamera(),
                  icon: const Icon(Icons.cameraswitch),
                  tooltip: 'Đổi camera',
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onIMEISelected('');
                  },
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Nhập thủ công'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}