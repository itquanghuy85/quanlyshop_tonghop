import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/debt_model.dart';
import '../models/quick_input_code_model.dart';
import '../models/supplier_model.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/event_bus.dart';
import '../services/supplier_service.dart';
import '../core/utils/money_utils.dart';
import '../utils/sku_generator.dart';
import '../widgets/currency_text_field.dart';
import 'quick_input_library_view.dart';

// Formatter to force uppercase input without triggering controller loops
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final upper = newValue.text.toUpperCase();
    return newValue.copyWith(text: upper, selection: newValue.selection);
  }
}

class FastStockInView extends StatefulWidget {
  final String? preselectedSupplier;
  final QuickInputCode? quickInputCode;
  final bool
  embedded; // When true, removes Scaffold/AppBar for embedding in tabs

  const FastStockInView({
    super.key,
    this.preselectedSupplier,
    this.quickInputCode,
    this.embedded = false,
  });

  @override
  State<FastStockInView> createState() => _FastStockInViewState();
}

class _FastStockInViewState extends State<FastStockInView> {
  final db = DBHelper();
  final supplierService = SupplierService();
  bool _saving = false;
  bool _isLoading = true;
  String? _loadingError;

  // Current quick input code for price sync
  QuickInputCode? _currentQuickInputCode;

  // Selected values
  String? selectedBrand;
  String? selectedCapacity;
  String? selectedColor;
  String? selectedCondition;
  String? selectedSupplier;
  String? selectedPaymentMethod;

  final TextEditingController modelCtrl = TextEditingController();
  final TextEditingController imeiCtrl = TextEditingController();
  final TextEditingController quantityCtrl = TextEditingController(text: '1');
  final TextEditingController costCtrl = TextEditingController();
  final TextEditingController priceCtrl = TextEditingController();

  List<Map<String, dynamic>> suppliers = [];

  // Options
  final List<String> brands = ['IPHONE', 'SAMSUNG', 'OPPO', 'REDMI', 'KHÁC'];
  final List<String> capacities = ['64GB', '128GB', '256GB', '512GB', '1TB'];
  final List<String> colors = ['ĐEN', 'TRẮNG', 'XANH', 'ĐỎ', 'VÀNG', 'TÍM'];
  final List<String> conditions = ['MỚI', '99', 'KHÁC'];
  final List<String> paymentMethods = ['TIỀN MẶT', 'CHUYỂN KHOẢN', 'CÔNG NỢ'];

  // Model suggestions based on brand
  final Map<String, List<String>> modelSuggestions = {
    'IPHONE': [
      '17',
      '16',
      '15',
      '14',
      '13',
      '12',
      '11',
      'XS MAX',
      'XS',
      'X',
      'SE',
      '8',
      'PRO',
      'PROMAX',
    ],
    'SAMSUNG': ['S24', 'S23', 'S22', 'S21', 'A54', 'A34', 'A14'],
    'OPPO': ['A18', 'A17', 'A16', 'A15', 'F11', 'F9'],
    'REDMI': ['13C', '12C', '11', '10', '9', 'Note 12'],
    'KHÁC': [],
  };

  @override
  void initState() {
    super.initState();
    _initData();
    imeiCtrl.addListener(_updateConfirmButton);
    modelCtrl.addListener(_updateConfirmButton);
    // CurrencyTextField handles formatting automatically - no need for listeners
  }

  int _parseMoneyWithK(String text) {
    // CurrencyTextField stores formatted value (e.g., "500.000" for 500000 VND)
    // parseValueWithMultiply removes formatting and applies x1000 rule if needed
    return CurrencyTextField.parseValueWithMultiply(text);
  }

  /// Map các giá trị condition từ mã nhập nhanh về danh sách conditions hiện tại
  /// Ví dụ: 'LIKE NEW 99%' -> '99', 'MỚI 100%' -> 'MỚI'
  String _mapConditionValue(String condition) {
    final conditionUpper = condition.toUpperCase();

    // Map các biến thể của "MỚI 100%"
    if (conditionUpper.contains('MỚI 100') ||
        conditionUpper == 'MỚI' ||
        conditionUpper == 'NEW 100' ||
        conditionUpper == '100%') {
      return 'MỚI';
    }

    // Map các biến thể của "99%", "LIKE NEW 99%"
    if (conditionUpper.contains('99') || conditionUpper.contains('LIKE NEW')) {
      return '99';
    }

    // Map các biến thể khác (98%, 95%, CŨ, ĐÃ QUA SD, etc.)
    return 'KHÁC';
  }

  void _preFillFromQuickInputCode(QuickInputCode code) {
    // Pre-fill brand
    if (code.brand != null && brands.contains(code.brand!.toUpperCase())) {
      selectedBrand = code.brand!.toUpperCase();
    }

    // Pre-fill model
    if (code.model != null) {
      modelCtrl.text = code.model!.toUpperCase();
    }

    // Pre-fill capacity
    if (code.capacity != null &&
        capacities.contains(code.capacity!.toUpperCase())) {
      selectedCapacity = code.capacity!.toUpperCase();
    }

    // Pre-fill color
    if (code.color != null && colors.contains(code.color!.toUpperCase())) {
      selectedColor = code.color!.toUpperCase();
    }

    // Pre-fill condition - map từ các giá trị khác nhau
    if (code.condition != null) {
      final conditionUpper = code.condition!.toUpperCase();
      if (conditions.contains(conditionUpper)) {
        selectedCondition = conditionUpper;
      } else {
        // Map các giá trị condition khác về danh sách hiện tại
        selectedCondition = _mapConditionValue(conditionUpper);
      }
    }

    // Pre-fill prices - use CurrencyTextField format for consistency
    if (code.cost != null) {
      costCtrl.text = CurrencyTextField.formatDisplay(code.cost!);
    }
    if (code.price != null) {
      priceCtrl.text = CurrencyTextField.formatDisplay(code.price!);
    }

    // Pre-fill supplier
    if (code.supplier != null) {
      if (suppliers.any((s) => s['name'] == code.supplier)) {
        selectedSupplier = code.supplier;
      } else {
        // Supplier from QuickInputCode not found in current suppliers list
        NotificationService.showSnackBar(
          "Nhà cung cấp '${code.supplier}' từ mã nhập nhanh không có trong danh sách. Vui lòng chọn lại.",
          color: Colors.orange,
        );
        selectedSupplier = null;
      }
    }

    // Pre-fill payment method
    if (code.paymentMethod != null &&
        paymentMethods.contains(code.paymentMethod!.toUpperCase())) {
      selectedPaymentMethod = code.paymentMethod!.toUpperCase();
    }

    // For accessories, set quantity to 1 by default (user can change)
    if (code.type == 'ACCESSORY') {
      quantityCtrl.text = '1';
    }
  }

  Future<void> _initData() async {
    setState(() {
      _isLoading = true;
      _loadingError = null;
    });
    try {
      // Timeout to prevent permanent loading state
      await _loadSuppliers().timeout(const Duration(seconds: 5));
      // Set preselected supplier if provided
      if (widget.preselectedSupplier != null &&
          suppliers.any((s) => s['name'] == widget.preselectedSupplier)) {
        selectedSupplier = widget.preselectedSupplier;
      }

      // Pre-fill form with quick input code data
      if (widget.quickInputCode != null) {
        _currentQuickInputCode = widget.quickInputCode;
        _preFillFromQuickInputCode(widget.quickInputCode!);
      }
    } catch (e) {
      // Handle timeout or other errors
      debugPrint('FastStockIn: load suppliers error: $e');
      _loadingError = 'Lỗi tải dữ liệu, thử lại.';
      if (mounted)
        NotificationService.showSnackBar(
          'Lỗi tải nhà cung cấp: $e',
          color: Colors.red,
        );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    imeiCtrl.removeListener(_updateConfirmButton);
    modelCtrl.removeListener(_updateConfirmButton);
    // CurrencyTextField handles formatting - no format listeners to remove
    modelCtrl.dispose();
    imeiCtrl.dispose();
    quantityCtrl.dispose();
    costCtrl.dispose();
    priceCtrl.dispose();
    super.dispose();
  }

  void _updateConfirmButton() {
    setState(() {});
  }

  Future<void> _loadSuppliers() async {
    debugPrint('FastStockIn: start loading suppliers');
    try {
      final sups = await supplierService.getSuppliers();
      if (mounted) {
        setState(() {
          suppliers = sups
              .map((s) => s.toMap())
              .where(
                (s) => s['name'] != null && s['name'].toString().isNotEmpty,
              )
              .toList();
        });
        debugPrint('FastStockIn: loaded suppliers count=${suppliers.length}');
      }
    } catch (e) {
      debugPrint('FastStockIn: loadSuppliers error: $e');
      if (mounted) {
        NotificationService.showSnackBar(
          "Lỗi tải nhà cung cấp: $e",
          color: Colors.red,
        );
      }
    }
  }

  Future<void> _addNewSupplier() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final addressCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Thêm nhà cung cấp mới',
          style: TextStyle(fontSize: 14),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                inputFormatters: [
                  UpperCaseTextFormatter(),
                  LengthLimitingTextInputFormatter(60),
                ],
                decoration: const InputDecoration(
                  labelText: 'Tên nhà cung cấp *',
                  hintText: 'VD: KHO HÀ NỘI',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  hintText: 'Số điện thoại liên hệ',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Địa chỉ email (tùy chọn)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressCtrl,
                inputFormatters: [UpperCaseTextFormatter()],
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ',
                  hintText: 'Địa chỉ kho hàng',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  hintText: 'Thông tin bổ sung (tùy chọn)',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
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
                  "Vui lòng nhập tên nhà cung cấp",
                  color: Colors.red,
                );
                return;
              }
              try {
                final shopId = await UserService.getCurrentShopId();
                final supplier = Supplier(
                  name: nameCtrl.text.trim().toUpperCase(),
                  phone: phoneCtrl.text.trim().isNotEmpty
                      ? phoneCtrl.text.trim()
                      : null,
                  email: emailCtrl.text.trim().isNotEmpty
                      ? emailCtrl.text.trim()
                      : null,
                  address: addressCtrl.text.trim().isNotEmpty
                      ? addressCtrl.text.trim().toUpperCase()
                      : null,
                  note: noteCtrl.text.trim().isNotEmpty
                      ? noteCtrl.text.trim()
                      : null,
                  shopId: shopId ?? '',
                );
                final savedSupplier = await supplierService.addSupplier(
                  supplier,
                );
                if (savedSupplier != null) {
                  await _loadSuppliers();
                  setState(
                    () => selectedSupplier = nameCtrl.text.trim().toUpperCase(),
                  );
                  EventBus().emit('suppliers_changed');
                  Navigator.pop(ctx, true);
                  NotificationService.showSnackBar(
                    "Đã thêm nhà cung cấp thành công",
                    color: Colors.green,
                  );
                } else {
                  NotificationService.showSnackBar(
                    "Lỗi thêm nhà cung cấp",
                    color: Colors.red,
                  );
                }
              } catch (e) {
                NotificationService.showSnackBar(
                  "Lỗi thêm nhà cung cấp: $e",
                  color: Colors.red,
                );
              }
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSupplier(String supplierName) async {
    // Tìm supplier trong danh sách
    final supplierMap = suppliers.firstWhere(
      (s) => s['name'] == supplierName,
      orElse: () => {},
    );

    if (supplierMap.isEmpty) {
      NotificationService.showSnackBar(
        "Không tìm thấy nhà cung cấp",
        color: Colors.red,
      );
      return;
    }

    // Xác nhận mật khẩu trước khi xóa
    final password = await _showPasswordDialog();
    if (password == null || password.isEmpty) return;

    // Xác thực mật khẩu
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      NotificationService.showSnackBar(
        "Vui lòng đăng nhập lại",
        color: Colors.red,
      );
      return;
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: currentUser.email!,
        password: password,
      );
      await currentUser.reauthenticateWithCredential(credential);
    } catch (e) {
      NotificationService.showSnackBar(
        "Mật khẩu không đúng!",
        color: Colors.red,
      );
      return;
    }

    // Xác nhận xóa
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa', style: TextStyle(fontSize: 14)),
        content: Text(
          'Bạn có chắc muốn xóa nhà cung cấp "$supplierName"?\n\nLưu ý: Dữ liệu liên quan có thể bị ảnh hưởng.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final supplierId = supplierMap['id'] as int;
      final firestoreId = supplierMap['firestoreId'] as String?;

      final success = await supplierService.deleteSupplier(
        supplierId,
        firestoreId: firestoreId,
      );

      if (success) {
        await _loadSuppliers();
        setState(() => selectedSupplier = null);
        EventBus().emit('suppliers_changed');
        NotificationService.showSnackBar(
          "Đã xóa nhà cung cấp thành công",
          color: Colors.green,
        );
      } else {
        NotificationService.showSnackBar(
          "Lỗi: Không thể xóa nhà cung cấp",
          color: Colors.red,
        );
      }
    } catch (e) {
      NotificationService.showSnackBar(
        "Lỗi xóa nhà cung cấp: $e",
        color: Colors.red,
      );
    }
  }

  Future<String?> _showPasswordDialog() async {
    String password = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          'Xác nhận xóa nhà cung cấp',
          style: TextStyle(fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Chỉ chủ shop/quản lý được phép xóa.\nNhập mật khẩu tài khoản để xác nhận:',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              obscureText: true,
              onChanged: (value) => password = value,
              decoration: const InputDecoration(
                hintText: 'Mật khẩu',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, password),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  /// Mở scanner QR/Barcode để quét IMEI - chỉ quét 1 lần, lấy 5 số cuối
  void _openQRScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
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
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'QUÉT QR/BARCODE IMEI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Hướng camera vào mã QR hoặc Barcode IMEI.\nChỉ lấy 5 số cuối để nhập vào trường IMEI.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
            // Scanner
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  controller: MobileScannerController(
                    detectionTimeoutMs: 1000,
                    returnImage: false,
                  ),
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final rawValue = barcodes.first.rawValue ?? '';
                      if (rawValue.isNotEmpty) {
                        // Lấy 5 số cuối từ IMEI
                        final digitsOnly = rawValue.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        final last5 = digitsOnly.length >= 5
                            ? digitsOnly.substring(digitsOnly.length - 5)
                            : digitsOnly;

                        // Đóng scanner và set IMEI
                        Navigator.pop(ctx);
                        setState(() {
                          imeiCtrl.text = last5;
                        });
                        NotificationService.showSnackBar(
                          'Đã quét: $rawValue → 5 số cuối: $last5',
                          color: Colors.green,
                        );
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProduct() async {
    if (selectedBrand == null ||
        selectedCapacity == null ||
        selectedColor == null ||
        selectedCondition == null ||
        selectedSupplier == null ||
        selectedPaymentMethod == null) {
      NotificationService.showSnackBar(
        "Vui lòng chọn đầy đủ thông tin!",
        color: Colors.red,
      );
      return;
    }
    if (modelCtrl.text.trim().isEmpty || imeiCtrl.text.trim().isEmpty) {
      NotificationService.showSnackBar(
        "Vui lòng nhập model và IMEI!",
        color: Colors.red,
      );
      return;
    }

    // IMEI không cần unique - cho phép nhập trùng

    final cost = _parseMoneyWithK(costCtrl.text);
    if (cost <= 0) {
      NotificationService.showSnackBar(
        "Vui lòng nhập giá nhập hợp lệ!",
        color: Colors.red,
      );
      return;
    }

    final price = _parseMoneyWithK(priceCtrl.text);
    if (price < 0) {
      NotificationService.showSnackBar(
        "Vui lòng nhập giá bán hợp lệ!",
        color: Colors.red,
      );
      return;
    }

    final quantity = int.tryParse(quantityCtrl.text) ?? 1;
    if (quantity <= 0) {
      NotificationService.showSnackBar(
        "Số lượng phải lớn hơn 0!",
        color: Colors.red,
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // Generate SKU
      final sku = await SKUGenerator.generateSKU(
        nhom: _getNhomFromBrand(selectedBrand!),
        model: modelCtrl.text.trim(),
        thongtin: null,
        dbHelper: db,
        firestoreService: null,
      );

      final ts = DateTime.now().millisecondsSinceEpoch;
      final imei = imeiCtrl.text.trim();
      final fId = "prod_${ts}_${imei}";

      final product = Product(
        firestoreId: fId,
        name:
            '$selectedBrand ${modelCtrl.text.trim()} $selectedCapacity $selectedColor $selectedCondition'
                .toUpperCase(),
        brand: selectedBrand!,
        model: modelCtrl.text.trim(),
        imei: imei,
        cost: cost,
        price: price,
        condition: selectedCondition!,
        status: 1,
        description: 'Nhập nhanh',
        createdAt: ts,
        supplier: selectedSupplier,
        type: 'PHONE',
        quantity: quantity,
        color: selectedColor!,
        capacity: selectedCapacity!,
        paymentMethod: selectedPaymentMethod,
        // Không còn đồng bộ giá KPK và CPK nữa
      );

      await db.upsertProduct(product);
      await FirestoreService.addProduct(product);

      // Lưu lịch sử nhập hàng từ nhà cung cấp
      final supplierData = suppliers.firstWhere(
        (s) => s['name'] == selectedSupplier,
        orElse: () => {},
      );
      final supplierId = supplierData['id'];
      final shopId = await UserService.getCurrentShopId();
      if (supplierId != null) {
        final importHistory = {
          'supplierId': supplierId,
          'supplierName': selectedSupplier,
          'productName': product.name,
          'productBrand': selectedBrand,
          'productModel': modelCtrl.text.trim(),
          'imei': imei,
          'quantity': quantity,
          'costPrice': cost,
          'totalAmount': cost * quantity,
          'paymentMethod': selectedPaymentMethod,
          'importDate': ts,
          'importedBy':
              FirebaseAuth.instance.currentUser?.email
                  ?.split('@')
                  .first
                  .toUpperCase() ??
              "NV",
          'notes': 'Nhập nhanh từ Fast Stock In',
          'shopId': shopId,
          'isSynced': 0,
        };
        await db.insertSupplierImportHistory(importHistory);

        // Cập nhật giá nhà cung cấp
        await db.deactivateSupplierProductPrice(
          supplierId,
          product.name,
          selectedBrand!,
          modelCtrl.text.trim().isNotEmpty ? modelCtrl.text.trim() : null,
        );
        final supplierPrice = {
          'supplierId': supplierId,
          'productName': product.name,
          'productBrand': selectedBrand,
          'productModel': modelCtrl.text.trim().isNotEmpty
              ? modelCtrl.text.trim()
              : null,
          'costPrice': cost,
          'lastUpdated': ts,
          'createdAt': ts,
          'isActive': 1,
          'shopId': shopId,
        };
        await db.insertSupplierProductPrice(supplierPrice);

        // Cập nhật thống kê nhà cung cấp
        await db.updateSupplierStats(supplierId, cost * quantity, quantity);
      }

      // Xử lý công nợ nhà cung cấp - ĐƠN GIẢN VÀ TRỰC TIẾP
      if (selectedPaymentMethod == 'CÔNG NỢ') {
        final supplierData = suppliers.firstWhere(
          (s) => s['name'] == selectedSupplier,
          orElse: () => {},
        );
        final supplierPhone = supplierData['phone']?.toString() ?? '';

        // Tạo debt record đơn giản
        final debt = Debt(
          personName: selectedSupplier!,
          phone: supplierPhone,
          totalAmount: cost * quantity,
          paidAmount: 0,
          type: 'SHOP_OWES',
          status: 'ACTIVE',
          createdAt: ts,
          note: 'Công nợ nhập hàng ${product.name}',
          linkedId: product.firestoreId,
        );

        // Set firestoreId to prevent duplicates
        debt.firestoreId = "debt_${ts}_${supplierPhone}";

        try {
          debugPrint(
            'FastStockIn: Creating debt for supplier $selectedSupplier, amount: ${cost * quantity}',
          );
          await db.upsertDebt(debt);
          debugPrint(
            'FastStockIn: Debt created successfully, firestoreId: ${debt.firestoreId}',
          );

          // Sync to Firestore
          await FirestoreService.addDebtCloud(debt.toMap());

          // Notify UI update
          EventBus().emit('debts_changed');

          NotificationService.showSnackBar(
            "Đã tạo công nợ cho nhà cung cấp!",
            color: Colors.green,
          );
        } catch (e) {
          debugPrint('FastStockIn: Debt creation error: $e');
          NotificationService.showSnackBar(
            "Lỗi tạo công nợ: $e",
            color: Colors.red,
          );
          return; // Don't continue if debt creation fails
        }
      } else {
        // Xử lý thanh toán tiền mặt/chuyển khoản - tạo expense record
        final exp = {
          'title': 'Nhập hàng - $selectedSupplier',
          'amount': cost * quantity,
          'category': 'PURCHASE',
          'date': ts,
          'note': 'Chi phí nhập hàng ${product.name}',
          'paymentMethod': selectedPaymentMethod,
          'createdAt': ts,
        };
        try {
          await db.insertExpense(exp);
          await FirestoreService.addExpenseCloud(exp);
          EventBus().emit('expenses_changed');
        } catch (e) {
          debugPrint('FastStockIn: Failed to create expense: $e');
          NotificationService.showSnackBar(
            "Lỗi tạo chi phí: $e",
            color: Colors.red,
          );
        }
      }

      // Log action
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";
      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: "NHẬP KHO NHANH",
        type: "PRODUCT",
        targetId: product.imei,
        desc: "Nhập nhanh ${product.name}",
      );

      NotificationService.showSnackBar(
        "Nhập kho nhanh thành công!",
        color: Colors.green,
      );

      // Send chat notification
      await FirestoreService.sendChat(
        message:
            "📦 Đã nhập kho: ${product.name} (${product.imei}) - SL: $quantity - NCC: $selectedSupplier",
        senderId: user?.uid ?? "system",
        senderName: userName,
        linkedType: "PRODUCT",
        linkedKey: product.imei,
        linkedSummary: product.name,
      );

      // Notify UI update for suppliers
      EventBus().emit('suppliers_changed');

      // Reset form
      _resetForm();
    } catch (e) {
      NotificationService.showSnackBar("Lỗi: $e", color: Colors.red);
    } finally {
      setState(() => _saving = false);
    }
  }

  String _getNhomFromBrand(String brand) {
    switch (brand) {
      case 'IPHONE':
        return 'IP';
      case 'SAMSUNG':
        return 'SS';
      case 'OPPO':
        return 'OP';
      case 'REDMI':
        return 'RD';
      default:
        return 'OT';
    }
  }

  void _resetForm() {
    setState(() {
      selectedBrand = null;
      selectedCapacity = null;
      selectedColor = null;
      selectedCondition = null;
      selectedSupplier = null;
      selectedPaymentMethod = null;
    });
    modelCtrl.clear();
    imeiCtrl.clear();
    quantityCtrl.text = '1';
    costCtrl.clear();
    priceCtrl.clear();
  }

  Widget _buildSupplierField() {
    // Fix: đảm bảo selectedSupplier nằm trong danh sách suppliers
    final supplierNames = suppliers.map((s) => s['name'] as String).toList();
    final validSelectedSupplier =
        (selectedSupplier != null && supplierNames.contains(selectedSupplier))
        ? selectedSupplier
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Nhà cung cấp',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 11,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: validSelectedSupplier,
                items: suppliers
                    .map(
                      (sup) => DropdownMenuItem<String>(
                        value: sup['name'] as String,
                        child: Text(
                          sup['name'] as String,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => selectedSupplier = val),
                decoration: InputDecoration(
                  hintText: 'Chọn nhà cung cấp',
                  hintStyle: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  filled: false,
                ),
                style: const TextStyle(fontSize: 11, color: Colors.black87),
                dropdownColor: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            // Nút thêm nhà cung cấp
            IconButton(
              onPressed: _addNewSupplier,
              icon: const Icon(Icons.add_circle, color: Colors.green, size: 28),
              tooltip: 'Thêm nhà cung cấp',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            // Nút xóa nhà cung cấp đang chọn
            IconButton(
              onPressed: validSelectedSupplier != null
                  ? () => _deleteSupplier(validSelectedSupplier!)
                  : null,
              icon: Icon(
                Icons.delete_outline,
                color: validSelectedSupplier != null ? Colors.red : Colors.grey,
                size: 24,
              ),
              tooltip: 'Xóa nhà cung cấp',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildModelField() {
    final suggestions = selectedBrand != null
        ? modelSuggestions[selectedBrand!] ?? []
        : [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Model',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: modelCtrl,
          inputFormatters: [
            UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(64),
          ],
          style: const TextStyle(fontSize: 11),
          decoration: InputDecoration(
            hintText: 'Nhập model',
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 8,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 4,
            children: suggestions
                .take(5)
                .map(
                  (model) => GestureDetector(
                    onTap: () => setState(() => modelCtrl.text = model),
                    child: Chip(
                      label: Text(
                        model.toUpperCase(),
                        style: const TextStyle(fontSize: 10),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 2,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildChipRow(
    String title,
    List<String> options,
    String? selected,
    Function(String) onSelect,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: options
              .map(
                (option) => ChoiceChip(
                  label: Text(
                    option,
                    style: const TextStyle(fontSize: 10, color: Colors.black),
                  ),
                  selected: selected == option,
                  selectedColor: Colors.blue[100],
                  onSelected: (sel) => setState(() => onSelect(option)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCurrencyField(
    String title,
    TextEditingController controller,
    IconData icon,
  ) {
    return CurrencyTextField(
      controller: controller,
      label: title,
      icon: icon,
      autoMultiply1000: true,
    );
  }

  Future<void> _selectFromLibrary() async {
    final codes = await db.getQuickInputCodes();
    final activeCodes = codes.where((c) => c.isActive).toList();

    if (activeCodes.isEmpty) {
      NotificationService.showSnackBar(
        'Không có mã nhập nhanh nào đang hoạt động',
        color: Colors.orange,
      );
      return;
    }

    if (!mounted) return;

    final selectedCode = await showDialog<QuickInputCode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chọn mã nhập nhanh'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: activeCodes.length,
            itemBuilder: (ctx, i) {
              final code = activeCodes[i];
              final isPhone = code.type == 'PHONE';
              return ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isPhone
                        ? Colors.blue.withAlpha(25)
                        : Colors.orange.withAlpha(25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isPhone ? Icons.smartphone : Icons.inventory_2,
                    color: isPhone ? Colors.blue : Colors.orange,
                    size: 20,
                  ),
                ),
                title: Text(code.name),
                subtitle: Text(
                  isPhone
                      ? "${code.brand ?? ''} ${code.model ?? ''}".trim()
                      : code.description ?? '',
                ),
                onTap: () => Navigator.pop(ctx, code),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const QuickInputLibraryView()),
            ),
            child: const Text('Quản lý mã nhập'),
          ),
        ],
      ),
    );

    if (selectedCode != null) {
      _applyQuickInputCode(selectedCode);
    }
  }

  void _applyQuickInputCode(QuickInputCode code) {
    setState(() {
      if (code.type == 'PHONE') {
        selectedBrand = code.brand;
        modelCtrl.text = code.model ?? '';
        selectedCapacity = code.capacity;
        selectedColor = code.color;
        selectedCondition = code.condition;
      } else {
        // For accessories, set description as model
        modelCtrl.text = code.description ?? '';
      }

      if (code.cost != null) {
        costCtrl.text = CurrencyTextField.formatDisplay(code.cost!);
      }
      if (code.price != null) {
        priceCtrl.text = CurrencyTextField.formatDisplay(code.price!);
      }
      selectedSupplier = code.supplier;
      if (code.supplier != null &&
          !suppliers.any((s) => s['name'] == code.supplier)) {
        NotificationService.showSnackBar(
          "Nhà cung cấp '${code.supplier}' không có trong danh sách. Vui lòng chọn lại.",
          color: Colors.orange,
        );
        selectedSupplier = null;
      }
      selectedPaymentMethod = code.paymentMethod;

      // Reset IMEI for new entry
      imeiCtrl.clear();
      quantityCtrl.text = '1';
    });

    NotificationService.showSnackBar(
      'Đã áp dụng mã nhập nhanh: ${code.name}',
      color: Colors.green,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bodyContent = _buildBody(context);

    // If embedded mode, return body directly without Scaffold
    if (widget.embedded) {
      return bodyContent;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nhập Kho Nhanh'),
        backgroundColor: Theme.of(context).primaryColor,
        actions: [
          IconButton(
            onPressed: _selectFromLibrary,
            icon: const Icon(Icons.library_books, color: Colors.white),
            tooltip: 'Chọn từ thư viện',
          ),
        ],
      ),
      body: bodyContent,
    );
  }

  Widget _buildBody(BuildContext context) {
    return Builder(
      builder: (ctx) {
        Widget bodyContent;
        try {
          if (_isLoading) {
            bodyContent = Center(
              child: CircularProgressIndicator(
                color: Theme.of(ctx).primaryColor,
              ),
            );
          } else if (_loadingError != null) {
            bodyContent = Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _loadingError!,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _initData,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            );
          } else {
            bodyContent = SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildChipRow(
                    'Loại hàng',
                    brands,
                    selectedBrand,
                    (v) => selectedBrand = v,
                  ),
                  _buildChipRow(
                    'Dung lượng',
                    capacities,
                    selectedCapacity,
                    (v) => selectedCapacity = v,
                  ),
                  _buildChipRow(
                    'Màu sắc',
                    colors,
                    selectedColor,
                    (v) => selectedColor = v,
                  ),
                  _buildChipRow(
                    'Tình trạng',
                    conditions,
                    selectedCondition,
                    (v) => selectedCondition = v,
                  ),

                  _buildModelField(),
                  _buildSupplierField(),
                  // Thanh toán đặt dưới nhà cung cấp để người dùng thấy rõ liên quan tới thanh toán
                  const SizedBox(height: 6),
                  _buildChipRow(
                    'Thanh toán',
                    paymentMethods,
                    selectedPaymentMethod,
                    (v) => setState(() => selectedPaymentMethod = v),
                  ),

                  Text(
                    'IMEI/Serial *',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: imeiCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(5),
                          ],
                          style: const TextStyle(fontSize: 11),
                          decoration: InputDecoration(
                            hintText: 'Nhập 5 số cuối IMEI (bắt buộc)',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _openQRScanner,
                        icon: const Icon(
                          Icons.qr_code_scanner,
                          color: Colors.green,
                        ),
                        tooltip: 'Quét QR/Barcode IMEI',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.green.withOpacity(0.1),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Số lượng',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  TextField(
                    controller: quantityCtrl,
                    keyboardType: TextInputType.number,
                    enabled: imeiCtrl.text.isEmpty,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: const TextStyle(fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Số lượng',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  _buildCurrencyField(
                    'Giá nhập (VNĐ) *',
                    costCtrl,
                    Icons.attach_money,
                  ),
                  const SizedBox(height: 8),
                  _buildCurrencyField('Giá bán (VNĐ)', priceCtrl, Icons.sell),

                  const SizedBox(height: 24),
                  Center(
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveProduct,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.green,
                      ),
                      child: _saving
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'XÁC NHẬN NHẬP KHO',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            );
          }
        } catch (e, st) {
          debugPrint('FastStockIn: build exception: $e\n$st');
          bodyContent = Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Lỗi hiển thị, thử lại sau.',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _initData,
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          );
        }
        return bodyContent;
      },
    );
  }
}
