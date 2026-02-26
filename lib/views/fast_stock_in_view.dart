import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants/product_constants.dart';
import '../data/db_helper.dart';
import '../theme/app_text_styles.dart';
import '../models/product_model.dart';
import '../models/debt_model.dart';
import '../models/quick_input_code_model.dart';
import '../models/supplier_model.dart';
import '../models/stock_entry_model.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/event_bus.dart';
import '../services/supplier_service.dart';
import '../services/stock_entry_service.dart';
import '../services/financial_activity_service.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../models/shop_settings_model.dart';
import '../utils/sku_generator.dart';
import '../utils/imei_extractor.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/imei_scan_result_dialog.dart';
import 'quick_input_codes_view.dart';
import 'pending_stock_list_view.dart';

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

  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);
  bool get _isFashion => _shopSettings?.businessType == 'fashion';
  bool get _isElectronics => _shopSettings?.businessType == 'electronics' || _shopSettings == null;
  bool get _enableSerial => _shopSettings?.enableSerial ?? true;

  // Current quick input code for price sync (reserved for future use)
  // ignore: unused_field
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
  final TextEditingController labelInfoCtrl = TextEditingController();

  List<Map<String, dynamic>> suppliers = [];

  // Options - sử dụng constants để đồng bộ
  List<String> get brands => ProductConstants.brands;
  List<String> get capacities => ProductConstants.capacities;
  List<String> get colors => ProductConstants.colors;
  List<String> get conditions => ProductConstants.conditionsShort;
  List<String> get paymentMethods => ProductConstants.paymentMethods;

  // Model suggestions based on brand
  Map<String, List<String>> get modelSuggestions => ProductConstants.modelSuggestions;

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
  /// Sử dụng ProductConstants.mapConditionShort để đồng bộ
  String _mapConditionValue(String condition) {
    return ProductConstants.mapConditionShort(condition);
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

    // Pre-fill color - với mapping để đồng bộ
    if (code.color != null) {
      final mappedColor = ProductConstants.mapColor(code.color);
      if (colors.contains(mappedColor)) {
        selectedColor = mappedColor;
      } else if (colors.contains(code.color!.toUpperCase())) {
        selectedColor = code.color!.toUpperCase();
      }
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
    if (code.type == 'PHỤ KIỆN') {
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
      if (mounted) {
        NotificationService.showSnackBar(
          'Lỗi tải nhà cung cấp: $e',
          color: Colors.red,
        );
      }
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
    labelInfoCtrl.dispose();
    super.dispose();
  }

  void _updateConfirmButton() {
    setState(() {});
  }

  Future<void> _loadSuppliers() async {
    debugPrint('FastStockIn: start loading suppliers');
    try {
      // Load shop settings for terminology
      final settings = await CategoryService().getShopSettings();
      if (mounted) _shopSettings = settings;
      
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

    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Thêm nhà cung cấp mới',
          style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
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
                style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
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
                style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
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
                style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
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
                style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
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
                style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
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
        title: Text('Xác nhận xóa', style: TextStyle(fontSize: AppTextStyles.headline4.fontSize)),
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
        title: Text(
          'Xác nhận xóa nhà cung cấp',
          style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Chỉ chủ shop/quản lý được phép xóa.\nNhập mật khẩu tài khoản để xác nhận:',
              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
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
              style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
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

  /// Mở scanner QR/Barcode để quét IMEI - xử lý thông minh QR nhiều dòng
  void _openQRScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SmartIMEIScannerSheet(
        onIMEISelected: (imei) {
          setState(() {
            imeiCtrl.text = imei;
          });
        },
      ),
    );
  }

  /// Legacy save method - kept for reference, now using StockEntryService.quickStockIn
  // ignore: unused_element
  Future<void> _saveProduct() async {
    // Finalize currency fields trước khi xử lý
    CurrencyTextField.finalizeAll();

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
        "Vui lòng nhập model và ${_terms.specialField1Label}!",
        color: Colors.red,
      );
      return;
    }

    // IMEI không cần unique - cho phép nhập trùng

    final cost = _parseMoneyWithK(costCtrl.text);
    final isPending = cost <= 0; // Kho tạm nếu chưa có giá vốn

    if (cost < 0) {
      NotificationService.showSnackBar(
        "Giá nhập không thể âm!",
        color: Colors.red,
      );
      return;
    }

    // Nếu nhập kho tạm (cost = 0), yêu cầu xác nhận
    if (isPending) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Xác nhận nhập Kho Tạm'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_terms.productLabel} sẽ được nhập vào KHO TẠM vì chưa có giá vốn.'),
              SizedBox(height: 8),
              Text(
                '• Sẽ KHÔNG tạo công nợ NCC',
                style: TextStyle(color: Colors.orange),
              ),
              Text(
                '• Sẽ KHÔNG tính vào chốt quỹ',
                style: TextStyle(color: Colors.orange),
              ),
              SizedBox(height: 8),
              Text('Khi xác nhận giá vốn sau, hệ thống sẽ:'),
              Text('• Chuyển sang kho chính'),
              Text('• Tạo công nợ/chi phí tương ứng'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Nhập Kho Tạm'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
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
      // Generate SKU (saved to product for tracking & barcode printing)
      final generatedSku = await SKUGenerator.generateSKU(
        nhom: _getNhomFromBrand(selectedBrand!),
        model: modelCtrl.text.trim(),
        thongtin: null,
        dbHelper: db,
        firestoreService: null,
      );

      final ts = DateTime.now().millisecondsSinceEpoch;
      final imei = imeiCtrl.text.trim();
      final fId = "prod_${ts}_$imei";

      final product = Product(
        firestoreId: fId,
        name: ProductConstants.generateProductName(
          brand: selectedBrand,
          model: modelCtrl.text.trim(),
          capacity: selectedCapacity,
          color: selectedColor,
          condition: selectedCondition,
        ),
        brand: selectedBrand!,
        model: modelCtrl.text.trim(),
        imei: imei,
        cost: cost,
        price: price,
        condition: selectedCondition!,
        status: 1,
        description: isPending ? 'Kho tạm - Chờ xác nhận giá' : 'Nhập nhanh',
        createdAt: ts,
        updatedAt: ts, // Thêm updatedAt để sort đúng
        supplier: isPending
            ? null
            : selectedSupplier, // Chỉ gán supplier chính khi không pending
        type: 'DIEN_THOAI',
        quantity: quantity,
        color: selectedColor!,
        capacity: selectedCapacity!,
        labelInfo: labelInfoCtrl.text.trim(),
        paymentMethod: isPending
            ? null
            : selectedPaymentMethod, // Chỉ gán khi không pending
        isPending: isPending,
        pendingSupplier: isPending ? selectedSupplier : null, // Lưu NCC tạm
        sku: generatedSku, // Mã SKU tự động sinh
        // Không còn đồng bộ giá KPK và CPK nữa
      );

      await db.upsertProduct(product);

      // Get product ID from local DB for SyncOrchestrator
      final savedProduct = await db.getProductByFirestoreId(fId);
      final productId = savedProduct?.id;

      // Queue sync to cloud via SyncOrchestrator
      if (productId != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.product,
          entityId: productId,
          firestoreId: fId,
          operation: SyncOperation.create,
          data: product.toMap(),
        );
        // Sync ngay lập tức nếu là kho tạm (để isPending được sync lên Firestore)
        if (isPending) {
          await SyncOrchestrator().syncAll();
        }
      }

      // Lưu lịch sử nhập hàng từ nhà cung cấp - CHỈ KHI KHÔNG PENDING
      if (!isPending) {
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
          final importHistoryId = await db.insertSupplierImportHistory(
            importHistory,
          );

          // FIX BUG-001: Enqueue để sync lên Firestore
          if (importHistoryId > 0) {
            await SyncOrchestrator().enqueueSupplierImportHistory(
              importHistoryId,
              firestoreId: importHistory['firestoreId'] as String?,
              operation: SyncOperation.create,
            );
          }

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
      }

      // Xử lý thanh toán nhà cung cấp - CHỈ KHI KHÔNG PENDING
      if (!isPending) {
        final totalCost = cost * quantity;
        final shopId = await UserService.getCurrentShopId();
        
        if (selectedPaymentMethod == 'CÔNG NỢ') {
          // Tạo công nợ shop phải trả cho nhà cung cấp
          final debtFirestoreId = 'debt_${DateTime.now().millisecondsSinceEpoch}_${product.imei}';
          final debtData = Debt(
            firestoreId: debtFirestoreId,
            personName: selectedSupplier ?? 'NCC không xác định',
            phone: '',
            totalAmount: totalCost,
            paidAmount: 0,
            type: 'SHOP_OWES',
            status: 'ACTIVE',
            createdAt: DateTime.now().millisecondsSinceEpoch,
            note: 'Nhập nhanh: ${product.name} (${product.imei}) x$quantity',
            linkedId: product.imei,
          );
          final debtId = await db.insertDebt(debtData.toMap());
          if (debtId > 0) {
            await SyncOrchestrator().enqueueDebt(
              debtId,
              firestoreId: debtFirestoreId,
              operation: SyncOperation.create,
            );
          }
          EventBus().emit('debts_changed');
          debugPrint('FastStockIn: Created debt for CÔNG NỢ: $totalCost');
        } else {
          // TIỀN MẶT hoặc CHUYỂN KHOẢN - Tạo expense record trực tiếp
          final expenseFirestoreId = 'exp_stockin_${DateTime.now().millisecondsSinceEpoch}_${product.imei}';
          final expenseData = {
            'firestoreId': expenseFirestoreId,
            'title': 'Nhập kho: ${product.name}',
            'description': 'NCC: ${selectedSupplier ?? "N/A"} - IMEI: ${product.imei} - SL: $quantity',
            'amount': totalCost,
            'category': 'NHẬP HÀNG',
            'date': DateTime.now().millisecondsSinceEpoch,
            'note': 'Nhập nhanh từ Fast Stock In',
            'paymentMethod': selectedPaymentMethod,
            'createdAt': DateTime.now().millisecondsSinceEpoch,
            'shopId': shopId,
            'isSynced': 0,
          };
          final expenseId = await db.insertExpense(expenseData);
          if (expenseId > 0) {
            await SyncOrchestrator().enqueue(
              entityType: SyncEntityType.expense,
              entityId: expenseId,
              firestoreId: expenseFirestoreId,
              operation: SyncOperation.create,
              data: expenseData,
            );
          }
          
          // Log vào financial_activity_log để hiện trong Nhật ký tài chính
          await FinancialActivityService.logPurchase(
            firestoreId: expenseFirestoreId,
            amount: totalCost,
            productName: product.name,
            quantity: quantity,
            paymentMethod: selectedPaymentMethod!,
            supplierName: selectedSupplier ?? 'N/A',
          );
          
          EventBus().emit('expenses_changed');
          debugPrint('FastStockIn: Created expense for $selectedPaymentMethod: $totalCost');
        }
      }

      // Log action
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";
      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: isPending ? "NHẬP KHO TẠM" : "NHẬP KHO NHANH",
        type: "PRODUCT",
        targetId: product.imei,
        desc: isPending
            ? "Nhập kho tạm ${product.name} (chờ xác nhận giá)"
            : "Nhập nhanh ${product.name}",
      );

      NotificationService.showSnackBar(
        isPending
            ? "Đã nhập vào KHO TẠM! Vui lòng xác nhận giá sau."
            : "Nhập kho nhanh thành công!",
        color: isPending ? Colors.orange : Colors.green,
      );

      // Send chat notification
      await FirestoreService.sendChat(
        message: isPending
            ? "📦⏳ Đã nhập KHO TẠM: ${product.name} (${product.imei}) - SL: $quantity - NCC dự kiến: $selectedSupplier"
            : "📦 Đã nhập kho: ${product.name} (${product.imei}) - SL: $quantity - NCC: $selectedSupplier",
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

  /// Lưu vào Hàng Chờ Xác Nhận thay vì nhập trực tiếp vào kho
  /// Flow mới: Tất cả sản phẩm đều phải qua hàng chờ xác nhận trước khi vào kho chính
  Future<void> _saveToStockEntry() async {
    CurrencyTextField.finalizeAll();

    // Validate thông tin cơ bản - condition chỉ bắt buộc cho electronics
    if (selectedBrand == null ||
        selectedColor == null ||
        (_isElectronics && selectedCondition == null)) {
      NotificationService.showSnackBar(
        "Vui lòng chọn đầy đủ thông tin cơ bản!",
        color: Colors.red,
      );
      return;
    }

    if (modelCtrl.text.trim().isEmpty) {
      NotificationService.showSnackBar(
        "Vui lòng nhập model!",
        color: Colors.red,
      );
      return;
    }

    final cost = _parseMoneyWithK(costCtrl.text);
    final price = _parseMoneyWithK(priceCtrl.text);
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
      // Tạo tên sản phẩm
      final productName = ProductConstants.generateProductName(
        brand: selectedBrand,
        model: modelCtrl.text.trim(),
        capacity: selectedCapacity,
        color: selectedColor,
        condition: selectedCondition,
      );

      // Lấy supplier ID nếu có
      String? supplierId;
      if (selectedSupplier != null && suppliers.isNotEmpty) {
        final supplierData = suppliers.firstWhere(
          (s) => s['name'] == selectedSupplier,
          orElse: () => {},
        );
        supplierId = supplierData['id']?.toString();
      }

      // Lấy shopId
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null || shopId.isEmpty) {
        NotificationService.showSnackBar(
          "Không tìm thấy thông tin shop!",
          color: Colors.red,
        );
        setState(() => _saving = false);
        return;
      }

      // Tạo StockEntryItem
      final item = StockEntryItem(
        name: productName,
        quantity: quantity,
        cost: cost > 0 ? cost.toDouble() : null,
        price: price > 0 ? price.toDouble() : null,
        imei: imeiCtrl.text.trim().isNotEmpty ? imeiCtrl.text.trim() : null,
        brand: selectedBrand,
        model: modelCtrl.text.trim(),
        capacity: selectedCapacity,
        color: selectedColor,
        condition: selectedCondition,
        labelInfo: labelInfoCtrl.text.trim().isNotEmpty ? labelInfoCtrl.text.trim() : null,
        productType: 'DIEN_THOAI',
      );

      // Tạo StockEntry (DRAFT)
      final entry = StockEntry(
        shopId: shopId,
        status: StockEntryStatus.draft,
        entryType:
            cost > 0 &&
                selectedSupplier != null &&
                selectedPaymentMethod != null
            ? StockEntryType.quick
            : StockEntryType.staging,
        items: [item],
        supplierId: supplierId,
        supplierName: selectedSupplier,
        paymentMethod: selectedPaymentMethod,
        notes: 'Nhập từ Nhập Kho Nhanh',
      );

      final stockService = StockEntryService();
      final savedEntry = await stockService.createEntry(entry);

      if (savedEntry != null) {
        final user = FirebaseAuth.instance.currentUser;
        final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";

        // Log action
        await db.logAction(
          userId: user?.uid ?? "0",
          userName: userName,
          action: "TẠO PHIẾU NHẬP",
          type: "STOCK_ENTRY",
          targetId: savedEntry.firestoreId,
          desc: "Tạo phiếu nhập: $productName - SL: $quantity",
        );

        // Thông báo
        NotificationService.showSnackBar(
          "Đã lưu vào Hàng Chờ Xác Nhận!",
          color: Colors.orange,
        );

        // Hỏi user có muốn mở trang xác nhận không
        final goToPending = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Đã tạo phiếu nhập'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_terms.productLabel}: $productName'),
                Text('Số lượng: $quantity'),
                const SizedBox(height: 12),
                const Text(
                  'Phiếu đã được lưu vào "Hàng Chờ Xác Nhận".\n'
                  'Bạn cần XÁC NHẬN phiếu để hàng vào kho chính.',
                  style: TextStyle(color: Colors.orange),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('NHẬP TIẾP'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: const Text(
                  'XEM HÀNG CHỜ',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );

        _resetForm();

        if (goToPending == true && context.mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PendingStockListView()),
          );
        }
      } else {
        NotificationService.showSnackBar(
          "Lỗi tạo phiếu nhập!",
          color: Colors.red,
        );
      }
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
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextStyles.body1.fontSize,
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
                          style: TextStyle(
                            fontSize: AppTextStyles.body1.fontSize,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => selectedSupplier = val),
                decoration: InputDecoration(
                  hintText: 'Chọn nhà cung cấp',
                  hintStyle: TextStyle(
                    fontSize: AppTextStyles.body1.fontSize,
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
                style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.black87),
                dropdownColor: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            // Nút thêm nhà cung cấp
            IconButton(
              onPressed: _addNewSupplier,
              icon: const Icon(Icons.add_circle, color: Colors.green, size: 20),
              tooltip: 'Thêm nhà cung cấp',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
            // Nút xóa nhà cung cấp đang chọn
            IconButton(
              onPressed: validSelectedSupplier != null
                  ? () => _deleteSupplier(validSelectedSupplier)
                  : null,
              icon: Icon(
                Icons.delete_outline,
                color: validSelectedSupplier != null ? Colors.red : Colors.grey,
                size: 18,
              ),
              tooltip: 'Xóa nhà cung cấp',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.body1.fontSize),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: modelCtrl,
          inputFormatters: [
            UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(64),
          ],
          style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
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
            runSpacing: 4,
            children: suggestions
                .map(
                  (model) => GestureDetector(
                    onTap: () => setState(() => modelCtrl.text = model),
                    child: Chip(
                      label: Text(
                        model.toUpperCase(),
                        style: TextStyle(fontSize: AppTextStyles.caption.fontSize),
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
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.subtitle1.fontSize),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          children: options
              .map(
                (option) => ChoiceChip(
                  label: Text(
                    option,
                    style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: Colors.black),
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
    return CurrencyTextField(controller: controller, label: title, icon: icon);
  }

  /// Build prominent Quick Input Code picker at top of form
  Widget _buildQuickInputPicker() {
    return InkWell(
      onTap: _selectFromLibrary,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade50,
              Colors.indigo.shade50,
            ],
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.flash_on, color: Colors.blue.shade700, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Chọn mã nhập nhanh để điền tự động',
                style: TextStyle(
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, 
              color: Colors.blue.shade400, size: 14),
          ],
        ),
      ),
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
              final isPhone = code.type == 'DIEN_THOAI';
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
              MaterialPageRoute(builder: (_) => const QuickInputCodesView()),
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
      if (code.type == 'DIEN_THOAI') {
        // Validate và map các giá trị cho đồng bộ
        if (code.brand != null && brands.contains(code.brand)) {
          selectedBrand = code.brand;
        }
        modelCtrl.text = code.model ?? '';
        if (code.capacity != null && capacities.contains(code.capacity)) {
          selectedCapacity = code.capacity;
        }
        // Map color về dạng chuẩn
        if (code.color != null) {
          final mappedColor = ProductConstants.mapColor(code.color);
          if (colors.contains(mappedColor)) {
            selectedColor = mappedColor;
          } else if (colors.contains(code.color)) {
            selectedColor = code.color;
          }
        }
        // Map condition về dạng short
        if (code.condition != null) {
          final mappedCondition = ProductConstants.mapConditionShort(code.condition!);
          if (conditions.contains(mappedCondition)) {
            selectedCondition = mappedCondition;
          } else if (conditions.contains(code.condition)) {
            selectedCondition = code.condition;
          }
        }
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
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Nhập Kho Nhanh'),
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
                  // === Quick Input Code Picker (trong form body) ===
                  _buildQuickInputPicker(),
                  const SizedBox(height: 8),
                  _buildChipRow(
                    'Loại hàng',
                    brands,
                    selectedBrand,
                    (v) => selectedBrand = v,
                  ),
                  // Dung lượng chỉ cho electronics, Size cho fashion
                  if (_isElectronics)
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
                  // Tình trạng chỉ cho electronics
                  if (_isElectronics)
                    _buildChipRow(
                      'Tình trạng',
                      conditions,
                      selectedCondition,
                      (v) => selectedCondition = v,
                    ),

                  _buildModelField(),
                  Text(
                    'Thông tin in trên tem',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextStyles.body1.fontSize,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TextField(
                    controller: labelInfoCtrl,
                    style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                    decoration: InputDecoration(
                      hintText: 'VD: ${_terms.specialField2Label}, ghi chú nhanh...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildSupplierField(),
                  // Thanh toán đặt dưới nhà cung cấp để người dùng thấy rõ liên quan tới thanh toán
                  const SizedBox(height: 6),
                  _buildChipRow(
                    'Thanh toán',
                    paymentMethods,
                    selectedPaymentMethod,
                    (v) => setState(() => selectedPaymentMethod = v),
                  ),

                  // IMEI/Serial chỉ cho electronics
                  if (_enableSerial) ...[
                    Text(
                      'IMEI/Serial *',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.body1.fontSize),
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
                            style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
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
                  ],

                  Text(
                    'Số lượng',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.body1.fontSize),
                  ),
                  TextField(
                    controller: quantityCtrl,
                    keyboardType: TextInputType.number,
                    enabled: _enableSerial ? imeiCtrl.text.isEmpty : true,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
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
                  // Nút chính: Lưu vào Hàng Chờ Xác Nhận
                  Center(
                    child: Column(
                      children: [
                        ElevatedButton.icon(
                          onPressed: _saving ? null : _saveToStockEntry,
                          icon: const Icon(Icons.pending_actions),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 16,
                            ),
                            backgroundColor: Colors.orange,
                          ),
                          label: _saving
                              ? const CircularProgressIndicator(
                                  color: Colors.white,
                                )
                              : Text(
                                  'LƯU VÀO HÀNG CHỜ XÁC NHẬN',
                                  style: TextStyle(
                                    fontSize: AppTextStyles.headline4.fontSize,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PendingStockListView(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.list_alt, size: 16),
                          label: Text(
                            'Xem hàng chờ xác nhận',
                            style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
                          ),
                        ),
                      ],
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
      NotificationService.showSnackBar('❌ Lỗi xử lý QR: $e', color: Colors.red);
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
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code_scanner, color: Colors.green),
                    const SizedBox(width: 8),
                    Text(
                      'QUÉT QR/BARCODE IMEI',
                      style: TextStyle(
                        fontSize: AppTextStyles.headline3.fontSize,
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
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hỗ trợ QR nhiều dòng (Apple, Samsung...).\n'
                    'Tự động trích xuất IMEI và cho phép chọn nếu có nhiều số.',
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.blue),
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
