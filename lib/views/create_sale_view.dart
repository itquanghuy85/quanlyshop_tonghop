import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/money_utils.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/customer_model.dart';
import '../models/sale_order_model.dart';
import '../models/debt_model.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/customer_service.dart';
import '../services/sync_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/user_service.dart';
import '../services/event_bus.dart';
import '../services/adjustment_service.dart';
import '../services/audit_service.dart';
import '../services/claims_service.dart';
import '../services/financial_activity_service.dart';
import '../services/first_time_guide_service.dart';
import '../services/payment_intent_service.dart';
import '../models/payment_intent_model.dart';
import '../constants/financial_constants.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/debounced_search_field.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/section_card.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import 'smart_stock_in_view.dart';
import 'supplier_list_view.dart';
import '../l10n/app_localizations.dart';

class CreateSaleView extends StatefulWidget {
  final Product? preSelectedProduct;
  final SaleOrder? editSale; // Thêm parameter cho edit mode

  const CreateSaleView({super.key, this.preSelectedProduct, this.editSale});
  @override
  State<CreateSaleView> createState() => _CreateSaleViewState();
}

class _CreateSaleViewState extends State<CreateSaleView> {
  final db = DBHelper();
  final nameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final priceCtrl = TextEditingController(text: "0");
  final noteCtrl = TextEditingController();
  final searchProdCtrl = TextEditingController();
  final discountCtrl = TextEditingController(text: "0"); // Giảm trừ trực tiếp

  bool _isInstallment = false;
  final downPaymentCtrl = TextEditingController(text: "0");
  final loanAmountCtrl = TextEditingController(text: "0");
  final bankCtrl = TextEditingController();
  // Hỗ trợ 2 ngân hàng
  final bankCtrl2 = TextEditingController();
  final loanAmountCtrl2 = TextEditingController(text: "0");
  bool _hasSecondBank = false;
  String _downPaymentMethod = "TIỀN MẶT"; // Phương thức trả trước

  String _paymentMethod = "TIỀN MẶT";
  String _saleWarranty = "12 THÁNG";
  bool _autoCalcTotal = true;
  bool _isWalkIn = false;

  final List<Map<String, dynamic>> _selectedItems = [];
  List<Map<String, dynamic>> _suggestCustomers = [];
  List<Product> _allInStock = [];
  List<Product> _filteredInStock = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasPermission = false;

  // Focus management cho IMEI fields
  final Map<String, FocusNode> _imeiFocusNodes = {};
  final Map<String, TextEditingController> _imeiControllers = {};

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadData();
    downPaymentCtrl.addListener(_calculateInstallment);
    discountCtrl.addListener(_onDiscountChanged);
    priceCtrl.addListener(_formatPrice);
    loanAmountCtrl.addListener(_onLoanAmount1Changed);
    // Refresh UI for add customer button when name/phone changes
    nameCtrl.addListener(() => setState(() {}));
    phoneCtrl.addListener(() => setState(() {}));
    // Hiển thị hướng dẫn cho người dùng mới
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showCarouselGuide(
      context: context,
      screenKey: FirstTimeGuideService.keySalesView,
      title: 'Tạo Đơn Bán Hàng',
      color: Colors.green,
      steps: const [
        GuideStep(
          title: '👤 Thông tin khách hàng',
          description:
              'Nhập SĐT để tự động điền tên khách cũ. Hoặc chọn từ danh bạ khách hàng.',
          icon: Icons.person,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '📦 Chọn sản phẩm',
          description:
              'Tìm kiếm và chọn sản phẩm trong kho. Có thể bán nhiều sản phẩm trong 1 đơn.',
          icon: Icons.inventory_2,
          iconColor: Colors.orange,
        ),
        GuideStep(
          title: '💰 Giá bán & Giảm giá',
          description:
              'Hệ thống tự tính tổng. Có thể nhập giảm giá trực tiếp hoặc điều chỉnh giá.',
          icon: Icons.attach_money,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '🏦 Thanh toán trả góp',
          description:
              'Bật trả góp để nhập tiền đặt cọc, số tiền vay và ngân hàng hỗ trợ.',
          icon: Icons.credit_card,
          iconColor: Colors.purple,
        ),
        GuideStep(
          title: '📝 Công nợ khách hàng',
          description:
              'Chọn "CÔNG NỢ" nếu khách chưa thanh toán đủ. Theo dõi trong mục Tài chính.',
          icon: Icons.account_balance_wallet,
          iconColor: Colors.red,
        ),
      ],
    );
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = perms['allowViewSales'] ?? false);
  }

  @override
  void dispose() {
    downPaymentCtrl.removeListener(_calculateInstallment);
    discountCtrl.removeListener(_onDiscountChanged);
    priceCtrl.removeListener(_formatPrice);
    loanAmountCtrl.removeListener(_onLoanAmount1Changed);
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    priceCtrl.dispose();
    noteCtrl.dispose();
    searchProdCtrl.dispose();
    downPaymentCtrl.dispose();
    loanAmountCtrl.dispose();
    bankCtrl.dispose();
    discountCtrl.dispose();
    bankCtrl2.dispose();
    loanAmountCtrl2.dispose();

    // Dispose IMEI controllers và focus nodes
    _imeiControllers.forEach((_, controller) => controller.dispose());
    _imeiFocusNodes.forEach((_, focusNode) => focusNode.dispose());

    super.dispose();
  }

  Future<void> _selectCustomer() async {
    debugPrint("_selectCustomer: bắt đầu chọn khách hàng");
    final customerService = CustomerService();

    // Sync customers from cloud first (ignore errors)
    debugPrint("_selectCustomer: bắt đầu sync từ cloud");
    try {
      await SyncService.syncCustomersFromCloud();
      debugPrint("_selectCustomer: đã sync xong từ cloud");
    } catch (e) {
      debugPrint("_selectCustomer: lỗi sync từ cloud (ignored): $e");
    }

    List<Customer> customers = [];
    try {
      customers = await customerService.getCustomers();
      debugPrint(
        "_selectCustomer: lấy được ${customers.length} customers từ local DB",
      );
    } catch (e) {
      debugPrint("_selectCustomer: lỗi lấy customers: $e");
    }

    // Fallback: lấy danh sách khách độc nhất từ lịch sử nếu chưa có trong bảng customers
    if (customers.isEmpty) {
      try {
        final unique = await db.getUniqueCustomersAll();
        customers = unique
            .map(
              (c) => Customer(
                name: (c['customerName'] ?? '').toString(),
                phone: (c['phone'] ?? '').toString(),
                address: (c['address'] ?? '').toString(),
                createdAt: DateTime.now().millisecondsSinceEpoch,
              ),
            )
            .where((c) => c.phone.isNotEmpty)
            .toList();
        debugPrint(
          "_selectCustomer: fallback ${customers.length} customers từ history",
        );
      } catch (e) {
        debugPrint("_selectCustomer: lỗi fallback: $e");
      }
    }

    if (!mounted) return;

    final selectedCustomer = await showDialog<Customer>(
      context: context,
      builder: (context) => CustomerSelectionDialog(customers: customers),
    );

    if (selectedCustomer != null) {
      setState(() {
        nameCtrl.text = selectedCustomer.name;
        phoneCtrl.text = selectedCustomer.phone;
        addressCtrl.text = selectedCustomer.address ?? '';
        _suggestCustomers = [];
      });
    }
  }

  Future<void> _addCustomerQuick() async {
    if (_isWalkIn) {
      NotificationService.showSnackBar(
        "Khách vãng lai không lưu danh bạ",
        color: Colors.blue,
      );
      return;
    }
    final name = nameCtrl.text.trim().toUpperCase();
    final phone = phoneCtrl.text.trim();
    final address = addressCtrl.text.trim().toUpperCase();

    if (name.isEmpty || phone.isEmpty) {
      NotificationService.showSnackBar(
        "Vui lòng nhập đủ tên và số điện thoại",
        color: Colors.orange,
      );
      return;
    }

    // Kiểm tra phone format
    final phoneError = UserService.validatePhone(
      phone,
      AppLocalizations.of(context)!,
    );
    if (phoneError != null) {
      NotificationService.showSnackBar(phoneError, color: Colors.red);
      return;
    }

    try {
      final customerService = CustomerService();
      // Kiểm tra khách hàng đã tồn tại chưa
      final existingCustomers = await customerService.getCustomers();
      final existing = existingCustomers
          .where((c) => c.phone == phone)
          .toList();

      if (existing.isNotEmpty) {
        NotificationService.showSnackBar(
          "Khách hàng với SĐT này đã tồn tại: ${existing.first.name}",
          color: Colors.orange,
        );
        return;
      }

      final newCustomer = Customer(
        name: name,
        phone: phone,
        address: address,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );
      await customerService.addCustomer(newCustomer);

      NotificationService.showSnackBar(
        "Đã thêm khách hàng: $name",
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar(
        "Lỗi thêm khách hàng: $e",
        color: Colors.red,
      );
    }
  }

  Future<void> _loadData() async {
    final prods = await db.getInStockProducts();
    final suggests = await db.getCustomerSuggestions();
    if (!mounted) return;
    setState(() {
      _allInStock = prods;
      _filteredInStock = prods;
      _suggestCustomers = suggests;
      _isLoading = false;
    });
    if (widget.preSelectedProduct != null) {
      _addProductToSale(widget.preSelectedProduct!);
    }
    if (widget.editSale != null) {
      _loadEditData();
    }
  }

  void _loadEditData() {
    final sale = widget.editSale!;
    _isWalkIn = sale.isWalkIn;
    nameCtrl.text = sale.isWalkIn
      ? (sale.walkInName ?? sale.customerName)
      : sale.customerName;
    phoneCtrl.text = sale.isWalkIn
      ? (sale.walkInPhone ?? sale.phone)
      : sale.phone;
    addressCtrl.text = sale.address;
    priceCtrl.text = _formatCurrency(sale.totalPrice);
    discountCtrl.text = _formatCurrency(sale.discount); // FIX: Load discount
    noteCtrl.text = sale.notes ?? '';
    _paymentMethod = sale.paymentMethod;
    _saleWarranty = sale.warranty;
    _isInstallment = sale.isInstallment;
    if (_isInstallment) {
      downPaymentCtrl.text = _formatCurrency(sale.downPayment);
      loanAmountCtrl.text = _formatCurrency(sale.loanAmount);
      bankCtrl.text = sale.bankName ?? '';
      _downPaymentMethod = sale.downPaymentMethod ?? 'TIỀN MẶT';
      // Load second bank if exists
      if (sale.bankName2 != null && sale.bankName2!.isNotEmpty) {
        _hasSecondBank = true;
        bankCtrl2.text = sale.bankName2!;
        loanAmountCtrl2.text = _formatCurrency(sale.loanAmount2);
      }
    }

    // Load selected items từ sale
    final productNames = sale.productNames.split(',');
    final productImeis = sale.productImeis.split(',');
    for (int i = 0; i < productNames.length; i++) {
      final name = productNames[i].trim();
      final imei = productImeis.length > i ? productImeis[i].trim() : '';

      // Tìm product trong _allInStock
      final product = _allInStock.firstWhere(
        (p) => p.name == name || p.imei == imei,
        orElse: () => Product(
          name: name,
          imei: imei,
          cost: 0,
          price: sale.totalPrice ~/ productNames.length,
          condition: 'UNKNOWN',
          type: 'DIEN_THOAI',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

      _addProductToSale(product);
    }
  }

  void _onDiscountChanged() {
    // Khi thay đổi giảm giá, tính lại số tiền vay nếu là trả góp
    if (_isInstallment) {
      _calculateInstallment();
    }
  }

  void _onLoanAmount1Changed() {
    // Khi thay đổi khoản vay NH1, nếu có NH2 thì tự động tính lại NH2
    if (_hasSecondBank) {
      _calculateBank2Loan();
    }
  }

  void _calculateBank2Loan() {
    // Tổng cần vay = tổng tiền - giảm giá - trả trước
    int total = _parseCurrency(priceCtrl.text);
    int discount = _parseCurrency(discountCtrl.text);
    int down = _parseCurrency(downPaymentCtrl.text);
    int loan1 = _parseCurrency(loanAmountCtrl.text);
    int remaining = total - discount - down - loan1;
    loanAmountCtrl2.text = _formatCurrency(remaining > 0 ? remaining : 0);
  }

  void _calculateInstallment() {
    int total = _parseCurrency(priceCtrl.text);
    int discount = _parseCurrency(discountCtrl.text);
    int down = _parseCurrency(downPaymentCtrl.text);
    int loanTotal = total - discount - down;

    if (_hasSecondBank) {
      // Nếu có 2 NH, tính số tiền còn lại cho NH2
      int loan1 = _parseCurrency(loanAmountCtrl.text);
      loanAmountCtrl2.text = _formatCurrency(
        loanTotal - loan1 > 0 ? loanTotal - loan1 : 0,
      );
    } else {
      loanAmountCtrl.text = _formatCurrency(loanTotal > 0 ? loanTotal : 0);
    }
  }

  void _calculateTotal() {
    if (!_autoCalcTotal) return;
    int total = _selectedItems.fold(
      0,
      (sum, item) =>
          sum +
          (item['isGift']
              ? 0
              : ((item['sellPrice'] as int) * (item['quantity'] as int))),
    );
    priceCtrl.text = _formatCurrency(total);
    _calculateInstallment();
  }

  /// Tính số tiền khách thực trả (sau giảm giá)
  int get _finalPrice {
    int total = _parseCurrency(priceCtrl.text);
    int discount = _parseCurrency(discountCtrl.text);
    return total - discount > 0 ? total - discount : 0;
  }

  int _parseCurrency(String value) {
    // Không còn auto multiply - nhập đủ số tiền
    return MoneyUtils.parseCurrency(value);
  }

  String _formatCurrency(int amount) => MoneyUtils.formatCurrency(amount);

  void _formatPrice() {
    final text = priceCtrl.text.trim();
    if (text.isEmpty) return;
    final parsed = _parseCurrency(text);
    final formatted = _formatCurrency(parsed);
    if (formatted != text) {
      priceCtrl.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
  }

  void _addItem(Product p) {
    if (_selectedItems.any((item) => item['product'].id == p.id)) return;

    final productId = p.id;
    final imeiController = TextEditingController(text: p.imei ?? '');
    final imeiFocusNode = FocusNode();

    setState(() {
      _selectedItems.add({
        'product': p,
        'isGift': false,
        'sellPrice': p.price,
        'quantity': 1,
        'imei': p.imei ?? '',
      });

      _imeiControllers[productId.toString()] = imeiController;
      _imeiFocusNodes[productId.toString()] = imeiFocusNode;

      _calculateTotal();
      searchProdCtrl.clear();
      _filteredInStock = _allInStock;
    });

    // Tự động focus vào IMEI field sau khi thêm sản phẩm
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _imeiFocusNodes[productId.toString()]?.context != null) {
        FocusScope.of(
          context,
        ).requestFocus(_imeiFocusNodes[productId.toString()]);
      }
    });
  }

  void _addProductToSale(Product p) {
    if (_selectedItems.any((item) => item['product'].id == p.id)) return;

    final productId = p.id;
    final imeiController = TextEditingController(text: p.imei ?? '');
    final imeiFocusNode = FocusNode();

    setState(() {
      _selectedItems.add({
        'product': p,
        'isGift': false,
        'sellPrice': p.price,
        'quantity': 1,
        'imei': p.imei ?? '',
      });

      _imeiControllers[productId.toString()] = imeiController;
      _imeiFocusNodes[productId.toString()] = imeiFocusNode;

      _calculateTotal();
    });

    // Tự động focus vào IMEI field
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && _imeiFocusNodes[productId.toString()]?.context != null) {
        FocusScope.of(
          context,
        ).requestFocus(_imeiFocusNodes[productId.toString()]);
      }
    });
  }

  Future<void> _revertOldSaleChanges() async {
    final oldSale = widget.editSale!;
    debugPrint('Reverting changes for old sale: ${oldSale.firestoreId}');

    // 1. Hoàn trả inventory dựa trên IMEI của đơn hàng cũ
    final imeis = oldSale.productImeis.split(', ');
    for (final imei in imeis) {
      if (imei.isNotEmpty && imei != "NO_IMEI" && !imei.startsWith("PKx")) {
        // Tìm sản phẩm theo IMEI và tăng quantity
        final product = await db.getProductByImei(imei);
        if (product != null) {
          await db.addProductQuantity(product.id!, 1);
          // Cập nhật local object
          product.quantity += 1;
          if (product.type == 'DIEN_THOAI' &&
              product.status == 0 &&
              product.quantity > 0) {
            product.status = 1; // Đánh dấu là available
            await db.updateProductStatus(product.id!, 1);
          }
          // Enqueue sync lên cloud thay vì gọi trực tiếp
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.product,
            entityId: product.id!,
            firestoreId: product.firestoreId,
            operation: SyncOperation.update,
            data: product.toMap(),
          );
          debugPrint(
            'Restored inventory for product: ${product.name}, new quantity: ${product.quantity}',
          );
        }
      }
    }

    // 2. Xóa debt cũ nếu có
    if (oldSale.firestoreId != null) {
      final existingDebts = await db.getAllDebts();
      final linkedDebt = existingDebts
          .where((d) => d['linkedId'] == oldSale.firestoreId)
          .firstOrNull;
      if (linkedDebt != null) {
        await db.deleteDebtByFirestoreId(linkedDebt['firestoreId']);
        // Enqueue soft delete lên cloud
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.debt,
          entityId: linkedDebt['id'] as int,
          firestoreId: linkedDebt['firestoreId'] as String?,
          operation: SyncOperation.delete,
          data: {...linkedDebt, 'deleted': true},
        );
        debugPrint(
          'Marked old debt as deleted for sale: ${oldSale.firestoreId}',
        );
      }
    }

    // 3. Xóa expense records liên quan đến đơn hàng cũ (nếu có)
    // Note: Logic này có thể cần điều chỉnh tùy theo cách lưu expense
  }

  Future<void> _processSale() async {
    debugPrint('🛒 _processSale: Starting...');
    if (_isSaving) {
      debugPrint('🛒 _processSale: Already saving, returning...');
      return;
    }

    // ✅ QUAN TRỌNG: Finalize tất cả currency fields trước khi xử lý
    // Giải quyết vấn đề: nhập số rồi bấm lưu ngay mà không blur field
    CurrencyTextField.finalizeAll();

    // Kiểm tra ngày hôm nay đã chốt quỹ chưa
    final today = DateTime.now();
    debugPrint('🛒 _processSale: Checking canEditDirectly for today...');
    final canEdit = await AdjustmentService.canEditDirectly(
      today.millisecondsSinceEpoch,
    );
    debugPrint('🛒 _processSale: canEdit = $canEdit');
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể tạo đơn bán mới.',
        color: Colors.red,
      );
      return;
    }

    if (_selectedItems.isEmpty) {
      debugPrint('🛒 _processSale: No items selected');
      NotificationService.showSnackBar(
        "VUI LÒNG CHỌN SẢN PHẨM",
        color: Colors.red,
      );
      return;
    }
    final isNameEmpty = nameCtrl.text.isEmpty;
    final isPhoneEmpty = phoneCtrl.text.isEmpty;
    if (!_isWalkIn && (isNameEmpty || isPhoneEmpty)) {
      debugPrint('🛒 _processSale: Name or phone empty (non walk-in)');
      NotificationService.showSnackBar(
        "NHẬP ĐỦ THÔNG TIN KHÁCH",
        color: Colors.red,
      );
      return;
    }
    if (_isWalkIn && isNameEmpty && isPhoneEmpty) {
      debugPrint('🛒 _processSale: Walk-in missing both name and phone');
      NotificationService.showSnackBar(
        "Nhập tên hoặc SĐT cho khách vãng lai",
        color: Colors.red,
      );
      return;
    }

    // Validate phone format (only when provided)
    if (!isPhoneEmpty) {
      final phoneError = UserService.validatePhone(
        phoneCtrl.text.trim(),
        AppLocalizations.of(context)!,
      );
      if (phoneError != null) {
        debugPrint('🛒 _processSale: Phone validation failed: $phoneError');
        NotificationService.showSnackBar(phoneError, color: Colors.red);
        return;
      }
    }

    debugPrint('🛒 _processSale: Validation passed, starting save...');

    setState(() => _isSaving = true);
    try {
      // XỬ LÝ EDIT MODE: Hoàn trả inventory và xóa debt cũ trước khi áp dụng thay đổi mới
      if (widget.editSale != null) {
        await _revertOldSaleChanges();
      }

      final now = DateTime.now().millisecondsSinceEpoch;
        final safeTail = phoneCtrl.text.isNotEmpty
          ? phoneCtrl.text
          : (nameCtrl.text.isNotEmpty ? nameCtrl.text.trim().toUpperCase() : 'walkin');
        final String uniqueId =
          widget.editSale?.firestoreId ?? "sale_${now}_$safeTail";
      String seller =
          FirebaseAuth.instance.currentUser?.email
              ?.split('@')
              .first
              .toUpperCase() ??
          "NV";
      int totalPrice = _parseCurrency(priceCtrl.text);

      // Parse discount và tính finalPrice (thành tiền sau giảm giá)
      int discount = _parseCurrency(discountCtrl.text);
      int finalPrice = totalPrice - discount;
      if (finalPrice < 0) finalPrice = 0;

      // FIX: paidAmount phải dựa trên finalPrice (sau giảm giá), không phải totalPrice
      int paidAmount = _parseCurrency(downPaymentCtrl.text);
      if (_paymentMethod != "CÔNG NỢ" &&
          _paymentMethod != "TRẢ GÓP (NH)" &&
          paidAmount == 0) {
        paidAmount = finalPrice; // FIX: Dùng finalPrice thay vì totalPrice
      }

      int totalCost = _selectedItems.fold(
        0,
        (sum, item) =>
            sum +
            ((item['product'] as Product).cost * (item['quantity'] as int)),
      );

      // Debug logging
      debugPrint(
        "Sale debug - totalPrice: $totalPrice, totalCost: $totalCost, selectedItems: ${_selectedItems.length}",
      );

      // Validate totals
      if (totalPrice <= 0) {
        NotificationService.showSnackBar(
          "TỔNG TIỀN PHẢI LỚN HƠN 0",
          color: Colors.red,
        );
        setState(() => _isSaving = false);
        return;
      }
      if (totalCost < 0) {
        NotificationService.showSnackBar(
          "TỔNG GIÁ VỐN KHÔNG ĐƯỢC ÂM",
          color: Colors.red,
        );
        setState(() => _isSaving = false);
        return;
      }

      final fallbackName = nameCtrl.text.trim().isNotEmpty
          ? nameCtrl.text.trim().toUpperCase()
          : 'KHÁCH VÃNG LAI';
      final normalizedPhone = phoneCtrl.text.trim();
      final sale = SaleOrder(
        firestoreId: uniqueId,
        customerName: fallbackName,
        phone: normalizedPhone,
        isWalkIn: _isWalkIn,
        walkInName: _isWalkIn ? fallbackName : null,
        walkInPhone: _isWalkIn && normalizedPhone.isNotEmpty
            ? normalizedPhone
            : null,
        address: addressCtrl.text.trim().toUpperCase(),
        productNames: _selectedItems
            .map((e) => "${(e['product'] as Product).name} x${e['quantity']}")
            .join(', '),
        productImeis: _selectedItems
            .map((e) {
              final product = e['product'] as Product;
              final quantity = e['quantity'] as int;
              final customImei = e['imei'] as String?;
              if (customImei != null && customImei.isNotEmpty) {
                return customImei;
              }
              // Logic cũ nếu không nhập IMEI tùy chọn
              if (product.type == 'DIEN_THOAI') {
                return product.imei ?? "NO_IMEI";
              } else {
                return "PKx$quantity";
              }
            })
            .join(', '),
        totalPrice: totalPrice,
        totalCost: _selectedItems.fold(
          0,
          (sum, item) =>
              sum +
              ((item['product'] as Product).cost * (item['quantity'] as int)),
        ),
        discount: discount,
        paymentMethod: _paymentMethod,
        sellerName: seller,
        // FIX: Giữ nguyên soldAt gốc khi edit, không thay đổi ngày bán
        soldAt: widget.editSale?.soldAt ?? now,
        isInstallment: _isInstallment,
        downPayment: paidAmount,
        downPaymentMethod: _isInstallment ? _downPaymentMethod : null,
        loanAmount: _isInstallment ? _parseCurrency(loanAmountCtrl.text) : 0,
        bankName: bankCtrl.text.toUpperCase(),
        bankName2: _hasSecondBank ? bankCtrl2.text.toUpperCase() : null,
        loanAmount2: _hasSecondBank ? _parseCurrency(loanAmountCtrl2.text) : 0,
        notes: noteCtrl.text,
        warranty: _saleWarranty,
      );

      // Validate IMEI trước khi thực hiện transaction
      for (var item in _selectedItems) {
        final p = item['product'] as Product;
        final customImei = item['imei'] as String?;
        if (p.type == 'DIEN_THOAI' &&
            (customImei == null || customImei.isEmpty) &&
            (p.imei == null || p.imei!.isEmpty)) {
          NotificationService.showSnackBar(
            "Không thể bán máy chưa có IMEI: ${p.name}",
            color: Colors.red,
          );
          setState(() => _isSaving = false);
          return;
        }
      }

      // === FIRESTORE TRANSACTION: KIỂM TRA + TRỪ KHO + TẠO SALE (ATOMIC) ===
      // Tránh race condition khi 2 nhân viên bán cùng 1 món

      // Refresh token và claims để đảm bảo shopId được cập nhật trước transaction
      try {
        // Gọi Cloud Function để sync claims từ Firestore lên JWT
        final claimsResult = await ClaimsService().refreshMyClaims();
        debugPrint('✅ Claims refresh result: $claimsResult');

        // Force refresh token để áp dụng claims mới
        await FirebaseAuth.instance.currentUser?.getIdToken(true);
        debugPrint('✅ Token refreshed before sale transaction');
      } catch (e) {
        debugPrint('⚠️ Could not refresh claims/token: $e');
        // Tiếp tục thử transaction, có thể vẫn hoạt động nếu claims đã đúng
      }

      // Kiểm tra xem tất cả sản phẩm đã có firestoreId chưa
      bool allHaveFirestoreId = _selectedItems.every((item) {
        final p = item['product'] as Product;
        return p.firestoreId != null && p.firestoreId!.isNotEmpty;
      });

      // Chuẩn bị data cho transaction
      final transactionItems = _selectedItems.map((item) {
        final p = item['product'] as Product;
        return {
          'firestoreId': p.firestoreId ?? '',
          'quantity': item['quantity'] as int,
          'productName': p.name,
          'type': p.type,
        };
      }).toList();

      // Chuẩn bị debt data nếu cần - sử dụng finalPrice (đã trừ giảm giá)
      Map<String, dynamic>? debtDataForTransaction;
      if (_paymentMethod == "CÔNG NỢ" ||
          (_paymentMethod != "TRẢ GÓP (NH)" && paidAmount < finalPrice)) {
        debtDataForTransaction = {
          'firestoreId': 'debt_${now}_${phoneCtrl.text.trim()}',
          'personName': nameCtrl.text.trim().toUpperCase(),
          'phone': phoneCtrl.text.trim(),
          'totalAmount': finalPrice, // FIX: Dùng finalPrice thay vì totalPrice
          'paidAmount': paidAmount,
          'type': "CUSTOMER_OWES",
          'status': "ACTIVE",
          'createdAt': now,
          'note': "Nợ mua máy: ${sale.productNames}",
          'linkedId': uniqueId,
        };
      }

      // Thực hiện Firestore transaction (chỉ khi tất cả sản phẩm đã sync)
      Map<String, dynamic> transactionResult;
      if (allHaveFirestoreId) {
        transactionResult = await FirestoreService.executeSaleTransaction(
          items: transactionItems,
          saleData: sale.toMap(),
          debtData: debtDataForTransaction,
        );
      } else {
        // Fallback: Bán local trước, sync sau
        debugPrint(
          '⚠️ Some products missing firestoreId, using local-first sale',
        );
        transactionResult = {'success': true, 'localOnly': true};
      }

      if (!transactionResult['success']) {
        // Transaction failed
        final outOfStockItems =
            transactionResult['outOfStockItems'] as List<dynamic>?;
        final needRelogin = transactionResult['needRelogin'] == true;
        final errorMsg = transactionResult['error']?.toString() ?? '';

        // Nếu lỗi permission-denied, cho phép bán local và sync sau
        if (errorMsg.contains('permission-denied') || needRelogin) {
          debugPrint(
            '⚠️ Firestore permission denied, falling back to local-first sale',
          );
          // Hiển thị thông báo và cho phép bán local
          if (mounted) {
            final shouldContinue = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Lỗi đồng bộ'),
                content: const Text(
                  'Không thể đồng bộ với server.\n\n'
                  'Bạn có muốn tiếp tục bán hàng offline? Dữ liệu sẽ được đồng bộ sau.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Hủy'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: const Text('Tiếp tục bán'),
                  ),
                ],
              ),
            );

            if (shouldContinue == true) {
              // Tiếp tục với local-first sale
              transactionResult = {'success': true, 'localOnly': true};
            } else {
              setState(() => _isSaving = false);
              return;
            }
          }
        } else if (outOfStockItems != null && outOfStockItems.isNotEmpty) {
          NotificationService.showSnackBar(
            "⚠️ Hàng đã được bán bởi nhân viên khác!\n${outOfStockItems.join('\n')}",
            color: Colors.red,
          );
          await _loadData();
          setState(() => _isSaving = false);
          return;
        } else {
          NotificationService.showSnackBar(
            "❌ Lỗi: ${transactionResult['error']}",
            color: Colors.red,
          );
          await _loadData();
          setState(() => _isSaving = false);
          return;
        }
      }

      // Transaction thành công → Cập nhật local DB
      // CHỈ trừ kho LOCAL khi là bán offline (localOnly = true)
      // Nếu Firestore transaction thành công, real-time sync sẽ tự động cập nhật local qua upsertProduct
      final isLocalOnly = transactionResult['localOnly'] == true;

      for (var item in _selectedItems) {
        final p = item['product'] as Product;
        final quantity = item['quantity'] as int;

        if (isLocalOnly) {
          // Chỉ cập nhật local database khi bán offline
          if (p.type == 'DIEN_THOAI') {
            await db.updateProductStatus(p.id!, 0);
          }
          await db.deductProductQuantity(p.id!, quantity);
          debugPrint(
            '📦 Local-only sale: Deducted ${p.name} quantity by $quantity',
          );
        } else {
          // Firestore transaction đã cập nhật cloud, sync sẽ tự động cập nhật local
          debugPrint(
            '☁️ Cloud sale: ${p.name} quantity will be synced from Firestore',
          );
        }

        // Cập nhật local object cho UI
        p.quantity -= quantity;
        if (p.type == 'DIEN_THOAI') {
          p.status = 0;
        }

        // Check for low inventory notification
        try {
          await NotificationService.checkAndNotifyLowInventory(
            p.firestoreId ?? p.id.toString(),
            p.name,
            p.quantity,
            5,
          );
        } catch (e) {
          debugPrint('Failed to check low inventory: $e');
        }
      }

      // Lưu sale vào local DB (cloud đã có từ transaction)
      await db.upsertSale(sale);
      // NOTE: FinancialActivityService.logSale REMOVED - ledger handled by PaymentIntentService

      // === TẠO PAYMENTINTENT ĐỂ HIỂN THỊ TRÊN TRANG "THANH TOÁN" ===
      try {
        final saleRef = sale.firestoreId ?? 'sale_${sale.soldAt}';
        final now = DateTime.now().millisecondsSinceEpoch;
        final userName =
            FirebaseAuth.instance.currentUser?.email
                ?.split('@')
                .first
                .toUpperCase() ??
            'NV';
        final downPaymentAmount = _parseCurrency(downPaymentCtrl.text);
        final payerName = sale.walkInName ?? sale.customerName;
        final payerPhone = sale.walkInPhone ?? sale.phone;

        if (_paymentMethod == "CÔNG NỢ") {
          // Công nợ khách hàng - chưa nhận tiền, ghi nhận debt
          // Dùng otherDebt để ghi nhận, không dùng salePayment vì chưa nhận tiền
          final intent = PaymentIntent(
            id: 'pi_sale_debt_${saleRef}_$now',
            type: PaymentIntentType.otherDebt,
            amount: finalPrice,
            description:
                'Công nợ bán hàng: $payerName - ${_selectedItems.length} SP',
            referenceId: saleRef,
            referenceType: 'sale',
            status: PaymentIntentStatus.completed, // Đã ghi nhận công nợ
            createdBy: userName,
            createdAt: now,
            paidAt: now,
            paymentMethod: PaymentMethod.debt,
            personName: payerName,
            personPhone: payerPhone,
            metadata: {
              'customerName': payerName,
              'phone': payerPhone,
              'productNames': sale.productNames,
              'debtFirestoreId': debtDataForTransaction?['firestoreId'],
            },
          );
          await PaymentIntentService.createIntent(intent);
          debugPrint('✅ Created PaymentIntent for sale CÔNG NỢ: ${intent.id}');
        } else if (_isInstallment) {
          // Trả góp - ghi nhận tiền trả trước nếu có
          if (downPaymentAmount > 0) {
            final intent = PaymentIntent(
              id: 'pi_sale_down_${saleRef}_$now',
              type: PaymentIntentType.salePayment,
              amount: downPaymentAmount,
              description:
                  'Trả trước trả góp: $payerName - ${_selectedItems.length} SP',
              referenceId: saleRef,
              referenceType: 'sale',
              status: PaymentIntentStatus.completed,
              createdBy: userName,
              createdAt: now,
              paidAt: now,
              paymentMethod: PaymentMethod.fromCode(_downPaymentMethod),
              personName: payerName,
              personPhone: payerPhone,
              metadata: {
                'customerName': payerName,
                'phone': payerPhone,
                'productNames': sale.productNames,
                'isInstallment': true,
                'bankName': bankCtrl.text.toUpperCase(),
              },
            );
            await PaymentIntentService.createIntent(intent);
            debugPrint(
              '✅ Created PaymentIntent for installment down payment: ${intent.id}',
            );
          }
        } else {
          // Tiền mặt / Chuyển khoản - đã nhận đủ tiền
          final intent = PaymentIntent(
            id: 'pi_sale_${saleRef}_$now',
            type: PaymentIntentType.salePayment,
            amount: finalPrice,
            description:
                'Bán hàng: $payerName - ${_selectedItems.length} SP',
            referenceId: saleRef,
            referenceType: 'sale',
            status: PaymentIntentStatus.completed,
            createdBy: userName,
            createdAt: now,
            paidAt: now,
            paymentMethod: PaymentMethod.fromCode(_paymentMethod),
            personName: payerName,
            personPhone: payerPhone,
            metadata: {
              'customerName': payerName,
              'phone': payerPhone,
              'productNames': sale.productNames,
            },
          );
          await PaymentIntentService.createIntent(intent);
          debugPrint('✅ Created PaymentIntent for sale: ${intent.id}');
        }
      } catch (e) {
        debugPrint('⚠️ Failed to create PaymentIntent for sale: $e');
        // Không fail sale nếu PaymentIntent thất bại
      }

      // Lưu debt vào local DB nếu có (dùng upsert để tránh duplicate khi sync)
      if (debtDataForTransaction != null) {
        final firestoreId = debtDataForTransaction['firestoreId'] as String?;
        if (firestoreId != null && firestoreId.isNotEmpty) {
          // Sử dụng upsertDebt thay vì insertDebt để tránh duplicate
          final debt = Debt(
            firestoreId: firestoreId,
            personName: debtDataForTransaction['personName'] as String,
            phone: debtDataForTransaction['phone'] as String,
            totalAmount: debtDataForTransaction['totalAmount'] as int,
            paidAmount: debtDataForTransaction['paidAmount'] as int? ?? 0,
            type: debtDataForTransaction['type'] as String,
            status: debtDataForTransaction['status'] as String? ?? 'ACTIVE',
            createdAt: debtDataForTransaction['createdAt'] as int,
            note: debtDataForTransaction['note'] as String?,
            linkedId: debtDataForTransaction['linkedId'] as String?,
            isSynced: true, // Đánh dấu đã sync vì đã lưu trên cloud
          );
          await db.upsertDebt(debt);
        } else {
          await db.insertDebt(debtDataForTransaction);
        }
      }

      // Create customer if not exists - FIX: Dùng finalPrice
      final customerService = CustomerService();
      final existingCustomers = await customerService.getCustomers();
      final existing = existingCustomers
          .where((c) => c.phone == phoneCtrl.text.trim())
          .toList();
      if (existing.isEmpty) {
        final newCustomer = Customer(
          name: nameCtrl.text.trim().toUpperCase(),
          phone: phoneCtrl.text.trim(),
          address: addressCtrl.text.trim().toUpperCase(),
          createdAt: DateTime.now().millisecondsSinceEpoch,
          totalSpent: finalPrice, // FIX: Dùng finalPrice
        );
        await customerService.addCustomer(newCustomer);
      } else {
        // Update customer stats (tổng chi tiêu) - FIX: Dùng finalPrice
        await customerService.updateCustomerStatsAfterSale(
          phoneCtrl.text.trim(),
          finalPrice, // FIX: Dùng finalPrice
        );
      }

      // Trigger payment notification if payment is completed - FIX: Dùng finalPrice
      if (_paymentMethod != "CÔNG NỢ" && !_isInstallment) {
        try {
          await NotificationService.notifyPaymentCompleted(
            sale.firestoreId ?? 'SALE_${sale.soldAt}_${sale.sellerName}',
            finalPrice.toDouble(), // FIX: Dùng finalPrice
            _paymentMethod,
          );
        } catch (e) {
          debugPrint('Failed to send payment notification: $e');
          // Don't fail the sale if notification fails
        }
      }

      // GHIM ĐƠN BÁN VÀO CHAT NỘI BỘ
      try {
        final chatUser = FirebaseAuth.instance.currentUser;
        final key = sale.firestoreId ?? "sale_${sale.soldAt}";
        final summary =
            "ĐƠN BÁN - ${sale.customerName} - ${sale.phone} - ${MoneyUtils.formatCurrency(totalPrice)} đ";
        final msg = "🛒 ĐÃ BÁN: $summary";
        await FirestoreService.sendChat(
          message: msg,
          senderId: chatUser?.uid ?? 'guest',
          senderName: chatUser?.email?.split('@').first.toUpperCase() ?? 'NV',
          linkedType: 'sale',
          linkedKey: key,
          linkedSummary: summary,
        );
      } catch (e) {
        debugPrint('Failed to send chat notification: $e');
        // Don't fail the sale if chat fails
      }

      // Notify other views about the new sale
      debugPrint('CreateSaleView: Emitting sales_changed event');
      EventBus().emit('sales_changed');

      // Ghi log hoạt động
      await AuditService.logAction(
        action: 'TẠO ĐƠN BÁN',
        entityType: 'SALE',
        entityId: sale.firestoreId ?? 'sale_${sale.soldAt}',
        summary:
            'Đã bán ${_selectedItems.length} sp cho ${sale.customerName} - ${MoneyUtils.formatCurrency(finalPrice)}đ',
        payload: {
          'customerName': sale.customerName,
          'phone': sale.phone,
          'totalPrice': finalPrice,
          'paymentMethod': _paymentMethod,
          'itemCount': _selectedItems.length,
        },
      );

      NotificationService.showSnackBar(
        "ĐÃ BÁN HÀNG THÀNH CÔNG!",
        color: Colors.green,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSaving = false);
      NotificationService.showSnackBar(
        "LỖI KHI LƯU ĐƠN BÁN: ${e.toString()}",
        color: Colors.red,
      );
      debugPrint("Sale save error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: AppColors.background,
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
          title: const Text("TẠO ĐƠN BÁN HÀNG"),
        ),
        body: Center(
          child: Text(
            "Bạn không có quyền truy cập tính năng này",
            style: TextStyle(
              fontSize: AppTextStyles.headline3.fontSize,
              color: Colors.grey,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
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
        title: Tooltip(
          message: widget.editSale != null
              ? "Chỉnh sửa thông tin đơn bán hàng"
              : "Chọn sản phẩm, nhập thông tin khách và hoàn tất đơn bán.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.editSale != null
                    ? "SỬA ĐƠN BÁN HÀNG"
                    : "TẠO ĐƠN BÁN HÀNG",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.headline2.fontSize,
                ),
              ),
              Text(
                '${_selectedItems.length} sản phẩm đã chọn',
                style: TextStyle(
                  fontSize: AppTextStyles.body1.fontSize,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.business_center),
            tooltip: 'Quản lý NCC & Đối tác',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SupplierListView()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // === COMPACT: SẢN PHẨM + KHÁCH HÀNG gộp chung ===
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Search sản phẩm
                          Row(
                            children: [
                              Icon(
                                Icons.inventory_2,
                                size: 18,
                                color: Colors.purple.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "SẢN PHẨM",
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple.shade700,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                "${_selectedItems.length} đã chọn",
                                style: AppTextStyles.caption.copyWith(
                                  color: Colors.purple,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          DebouncedSearchField(
                            controller: searchProdCtrl,
                            hint: "Tìm máy hoặc IMEI...",
                            onSearch: (v) => setState(
                              () => _filteredInStock = _allInStock
                                  .where(
                                    (p) =>
                                        p.name.contains(v.toUpperCase()) ||
                                        (p.imei ?? "").contains(v),
                                  )
                                  .toList(),
                            ),
                          ),
                          if (_allInStock.isEmpty) _buildEmptyStockGuidance(),
                          if (searchProdCtrl.text.isNotEmpty)
                            _buildSearchResults(),
                          _buildSelectedItemsList(),

                          // Divider giữa sản phẩm và khách hàng
                          const Divider(height: 16),

                          // Thông tin khách hàng compact
                          Row(
                            children: [
                              Icon(
                                Icons.person,
                                size: 18,
                                color: Colors.blue.shade700,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                "KHÁCH HÀNG",
                                style: AppTextStyles.caption.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _selectCustomer,
                                icon: const Icon(Icons.search, size: 16),
                                label: const Text("Chọn KH"),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ],
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            title: const Text('Khách vãng lai (không lưu danh bạ)'),
                            subtitle: Text(
                              _isWalkIn
                                  ? 'Tên/SĐT chỉ lưu trên đơn, SĐT không bắt buộc'
                                  : 'Nhập SĐT để lưu khách vào danh bạ',
                              style: AppTextStyles.caption,
                            ),
                            value: _isWalkIn,
                            onChanged: (v) {
                              setState(() {
                                _isWalkIn = v;
                                if (_isWalkIn && nameCtrl.text.trim().isEmpty) {
                                  nameCtrl.text = 'KHÁCH VÃNG LAI';
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 6),
                          // 2 fields trên 1 hàng
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: nameCtrl,
                                  decoration: InputDecoration(
                                    labelText:
                                        _isWalkIn ? "TÊN (tùy chọn)" : "TÊN",
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                      size: 18,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  textCapitalization:
                                      TextCapitalization.characters,
                                  style: AppTextStyles.body2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 130,
                                child: TextFormField(
                                  controller: phoneCtrl,
                                  decoration: InputDecoration(
                                    labelText: _isWalkIn
                                        ? "SĐT (không bắt buộc)"
                                        : "SĐT",
                                    prefixIcon:
                                        const Icon(Icons.phone, size: 18),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                  ),
                                  keyboardType: TextInputType.phone,
                                  style: AppTextStyles.body2,
                                ),
                              ),
                              if (!_isWalkIn &&
                                  nameCtrl.text.trim().isNotEmpty &&
                                  phoneCtrl.text.trim().isNotEmpty)
                                IconButton(
                                  onPressed: _addCustomerQuick,
                                  icon: const Icon(Icons.person_add, size: 18),
                                  color: AppColors.success,
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.only(left: 4),
                                  tooltip: 'Thêm nhanh KH',
                                ),
                            ],
                          ),
                          _buildCustomerSuggestions(),
                        ],
                      ),
                    ),
                  ),

                  // === COMPACT: THANH TOÁN ===
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _buildCompactPaymentSection(),
                    ),
                  ),

                  // === NÚT HOÀN TẤT ===
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_isSaving || _selectedItems.isEmpty)
                          ? null
                          : _processSale,
                      style: AppButtonStyles.successElevatedButtonStyle,
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              _selectedItems.isEmpty
                                  ? "CHƯA CHỌN SẢN PHẨM"
                                  : "HOÀN TẤT ĐƠN HÀNG",
                              style: AppTextStyles.button.copyWith(
                                color: AppColors.onSuccess,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }

  Widget _buildCompactPaymentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.payment, size: 18, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Text(
              "THANH TOÁN",
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Tổng tiền + Giảm giá (responsive để tránh overflow)
        LayoutBuilder(
          builder: (ctx, constraints) {
            final isNarrow = constraints.maxWidth < 360;
            final itemWidth = isNarrow
                ? constraints.maxWidth
                : (constraints.maxWidth / 2) - 6;
            return Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: Row(
                    children: [
                      Text(
                        "TỔNG:",
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          _autoCalcTotal ? Icons.lock_outline : Icons.edit,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        onPressed: () =>
                            setState(() => _autoCalcTotal = !_autoCalcTotal),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: CurrencyTextField(
                          controller: priceCtrl,
                          label: "",
                          enabled: !_autoCalcTotal,
                          autoMultiply1000: false,
                          onChanged: (_) => _calculateInstallment(),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.discount,
                        size: 16,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "Giảm:",
                        style: AppTextStyles.caption.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: CurrencyTextField(
                          controller: discountCtrl,
                          label: "",
                          autoMultiply1000: false,
                          onChanged: (_) {
                            _calculateInstallment();
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),

        // Thành tiền
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "THÀNH TIỀN:",
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              Text(
                "${_formatCurrency(_finalPrice)} Đ",
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
        ),

        // Payment methods compact
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: ["TIỀN MẶT", "CHUYỂN KHOẢN", "CÔNG NỢ", "TRẢ GÓP (NH)"]
              .map(
                (e) => ChoiceChip(
                  label: Text(
                    e,
                    style: AppTextStyles.caption.copyWith(fontSize: 11),
                  ),
                  selected: _paymentMethod == e,
                  onSelected: (v) => setState(() {
                    _paymentMethod = e;
                    _isInstallment = (e == "TRẢ GÓP (NH)");
                    if (!_isInstallment) _hasSecondBank = false;
                  }),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              )
              .toList(),
        ),

        const Divider(height: 12),

        // Số tiền thu thực tế
        _moneyInput(
          downPaymentCtrl,
          _isInstallment ? "KHÁCH TRẢ" : "SỐ TIỀN",
          AppColors.secondary,
        ),

        // Phương thức trả trước (trả góp) - Gộp trong ExpansionTile
        if (_isInstallment)
          Card(
            margin: const EdgeInsets.only(top: 6),
            color: Colors.blue.shade50,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              dense: true,
              initiallyExpanded: true,
              leading: Icon(
                Icons.account_balance,
                color: Colors.blue.shade700,
                size: 18,
              ),
              title: Text(
                "CHI TIẾT TRẢ GÓP",
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                  fontSize: 12,
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    children: [
                      // Phương thức trả trước
                      Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            "TRẢ TRƯỚC:",
                            style: AppTextStyles.caption.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          ...["T.MẶT", "C.KHOẢN"].map(
                            (m) => ChoiceChip(
                              label: Text(
                                m,
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: 10,
                                ),
                              ),
                              selected:
                                  _downPaymentMethod ==
                                  (m == "C.KHOẢN"
                                      ? "CHUYỂN KHOẢN"
                                      : (m == "T.MẶT" ? "TIỀN MẶT" : m)),
                              onSelected: (v) => setState(
                                () => _downPaymentMethod = m == "C.KHOẢN"
                                    ? "CHUYỂN KHOẢN"
                                    : (m == "T.MẮT" ? "TIỀN MẶT" : m),
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      _moneyInput(
                        loanAmountCtrl,
                        _hasSecondBank ? "NH 1 VAY" : "NH VAY",
                        AppColors.grey600,
                        enabled: _hasSecondBank,
                      ),
                      const SizedBox(height: 6),
                      // Tên NH + Quick chips
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: bankCtrl,
                              decoration: const InputDecoration(
                                labelText: "TÊN NH/TCTT",
                                prefixIcon: Icon(
                                  Icons.account_balance,
                                  size: 18,
                                ),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              style: AppTextStyles.body2,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: ["FE", "HOME", "MIRAE", "HD", "F83", "T86"]
                            .map(
                              (b) => ActionChip(
                                label: Text(
                                  b,
                                  style: AppTextStyles.caption.copyWith(
                                    fontSize: 10,
                                  ),
                                ),
                                onPressed: () =>
                                    setState(() => bankCtrl.text = b),
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                              ),
                            )
                            .toList(),
                      ),

                      // Ngân hàng thứ 2
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: Checkbox(
                              value: _hasSecondBank,
                              onChanged: (v) => setState(() {
                                _hasSecondBank = v ?? false;
                                if (_hasSecondBank) {
                                  _calculateBank2Loan();
                                } else {
                                  bankCtrl2.clear();
                                  loanAmountCtrl2.text = "0";
                                  _calculateInstallment();
                                }
                              }),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          Text("2 ngân hàng", style: AppTextStyles.caption),
                        ],
                      ),

                      if (_hasSecondBank) ...[
                        const SizedBox(height: 6),
                        _moneyInput(
                          loanAmountCtrl2,
                          "NH 2 VAY",
                          AppColors.grey600,
                          enabled: false,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: bankCtrl2,
                                decoration: const InputDecoration(
                                  labelText: "TÊN NH 2",
                                  prefixIcon: Icon(
                                    Icons.account_balance,
                                    size: 18,
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                ),
                                textCapitalization:
                                    TextCapitalization.characters,
                                style: AppTextStyles.body2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: ["FE", "HOME", "MIRAE", "HD", "F83", "T86"]
                              .map(
                                (b) => ActionChip(
                                  label: Text(
                                    b,
                                    style: AppTextStyles.caption.copyWith(
                                      fontSize: 10,
                                    ),
                                  ),
                                  onPressed: () =>
                                      setState(() => bankCtrl2.text = b),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

        const Divider(height: 12),

        // Bảo hành + Ghi chú: dùng Row flexible để tránh tràn ngang
        Row(
          children: [
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<String>(
                value: _saleWarranty,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: "B.HÀNH",
                  prefixIcon: Icon(Icons.verified_user, size: 16),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                ),
                items: ["KO BH", "1 THÁNG", "3 THÁNG", "6 THÁNG", "12 THÁNG"]
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(
                          e,
                          style: AppTextStyles.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _saleWarranty = v ?? "KO BH"),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: noteCtrl,
                maxLines: 1,
                decoration: const InputDecoration(
                  labelText: "Ghi chú",
                  prefixIcon: Icon(Icons.note, size: 16),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                style: AppTextStyles.body2,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentSection() {
    return Column(
      children: [
        // TỔNG TIỀN
        Row(
          children: [
            Flexible(
              child: Text(
                "TỔNG TIỀN:",
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Spacer(),
            IconButton(
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              icon: Icon(
                _autoCalcTotal ? Icons.lock_outline : Icons.edit,
                size: 18,
                color: AppColors.primary,
              ),
              onPressed: () => setState(() => _autoCalcTotal = !_autoCalcTotal),
            ),
            SizedBox(
              width: 130,
              child: CurrencyTextField(
                controller: priceCtrl,
                label: "",
                enabled: !_autoCalcTotal,
                autoMultiply1000: false,
                onChanged: (_) {
                  _calculateInstallment();
                },
              ),
            ),
            Text(
              " Đ",
              style: AppTextStyles.body1.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),

        // GIẢM GIÁ TRỰC TIẾP
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.discount, size: 18, color: Colors.orange),
                const SizedBox(width: 6),
                Text(
                  "GIẢM GIÁ:",
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            SizedBox(
              width: 150,
              child: CurrencyTextField(
                controller: discountCtrl,
                label: "",
                autoMultiply1000: false,
                onChanged: (_) {
                  _calculateInstallment();
                  setState(() {});
                },
              ),
            ),
          ],
        ),

        // THÀNH TIỀN SAU GIẢM GIÁ - FIX: Luôn hiển thị để user thấy số tiền thực thu
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "THÀNH TIỀN:",
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              Text(
                "${_formatCurrency(_finalPrice)} Đ",
                style: AppTextStyles.headline6.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 15),
        Wrap(
          spacing: 8,
          children: ["TIỀN MẶT", "CHUYỂN KHOẢN", "CÔNG NỢ", "TRẢ GÓP (NH)"]
              .map(
                (e) => ChoiceChip(
                  label: Text(e, style: AppTextStyles.caption),
                  selected: _paymentMethod == e,
                  onSelected: (v) => setState(() {
                    _paymentMethod = e;
                    _isInstallment = (e == "TRẢ GÓP (NH)");
                    if (!_isInstallment) {
                      _hasSecondBank = false;
                    }
                  }),
                ),
              )
              .toList(),
        ),
        const Divider(height: 30),
        _moneyInput(
          downPaymentCtrl,
          _isInstallment ? "KHÁCH TRẢ TRƯỚC" : "SỐ TIỀN THU THỰC TẾ",
          AppColors.secondary,
        ),
        // Phương thức thanh toán cho tiền trả trước
        if (_isInstallment) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                "TRẢ TRƯỚC:",
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              ...["TIỀN MẶT", "C.KHOẢN"].map(
                (m) => ChoiceChip(
                  label: Text(m, style: AppTextStyles.caption),
                  selected:
                      _downPaymentMethod ==
                      (m == "C.KHOẢN" ? "CHUYỂN KHOẢN" : m),
                  onSelected: (v) => setState(
                    () => _downPaymentMethod = m == "C.KHOẢN"
                        ? "CHUYỂN KHOẢN"
                        : m,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
        if (_isInstallment) ...[
          const SizedBox(height: 10),
          _moneyInput(
            loanAmountCtrl,
            _hasSecondBank ? "NGÂN HÀNG 1 CHO VAY" : "NGÂN HÀNG CHO VAY",
            AppColors.grey600,
            enabled: _hasSecondBank, // Cho phép sửa nếu có 2 NH
          ),
          const SizedBox(height: 10),
          ValidatedTextField(
            controller: bankCtrl,
            label: "TÊN CÔNG TY TÀI CHÍNH",
            icon: Icons.account_balance,
            uppercase: true,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ["FE", "HOME", "MIRAE", "HD", "F83", "T86"]
                .map(
                  (b) => ActionChip(
                    label: Text(b, style: AppTextStyles.caption),
                    onPressed: () => setState(() => bankCtrl.text = b),
                  ),
                )
                .toList(),
          ),

          // THÊM NGÂN HÀNG THỨ 2
          const SizedBox(height: 12),
          Row(
            children: [
              Checkbox(
                value: _hasSecondBank,
                onChanged: (v) => setState(() {
                  _hasSecondBank = v ?? false;
                  if (_hasSecondBank) {
                    _calculateBank2Loan();
                  } else {
                    bankCtrl2.clear();
                    loanAmountCtrl2.text = "0";
                    _calculateInstallment();
                  }
                }),
              ),
              const Text("Trả góp 2 ngân hàng"),
            ],
          ),

          if (_hasSecondBank) ...[
            const Divider(),
            const SizedBox(height: 8),
            Text(
              "NGÂN HÀNG THỨ 2",
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            _moneyInput(
              loanAmountCtrl2,
              "NGÂN HÀNG 2 CHO VAY",
              AppColors.grey600,
              enabled: false,
            ),
            const SizedBox(height: 10),
            ValidatedTextField(
              controller: bankCtrl2,
              label: "TÊN CÔNG TY TÀI CHÍNH 2",
              icon: Icons.account_balance,
              uppercase: true,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ["FE", "HOME", "MIRAE", "HD", "F83", "T86"]
                  .map(
                    (b) => ActionChip(
                      label: Text(b, style: AppTextStyles.caption),
                      onPressed: () => setState(() => bankCtrl2.text = b),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
        const Divider(height: 30),
        // KHÔI PHỤC TAB BẢO HÀNH: Cho phép chọn bảo hành bất kể trạng thái nợ
        DropdownButtonFormField<String>(
          value: _saleWarranty,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: "CHỌN THỜI GIAN BẢO HÀNH",
            prefixIcon: Icon(Icons.verified_user),
          ),
          items: [
            "KO BH",
            "1 THÁNG",
            "3 THÁNG",
            "6 THÁNG",
            "12 THÁNG",
          ].map((e) => DropdownMenuItem(
            value: e,
            child: Text(e, overflow: TextOverflow.ellipsis),
          )).toList(),
          onChanged: (v) => setState(() => _saleWarranty = v ?? "KO BH"),
        ),
        const SizedBox(height: 15),
        TextFormField(
          controller: noteCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: "GHI CHÚ ĐƠN HÀNG",
            hintText: "Nhập ghi chú (nếu có)...",
            prefixIcon: Icon(Icons.note_alt_outlined),
          ),
        ),
      ],
    );
  }

  Widget _moneyInput(
    TextEditingController ctrl,
    String label,
    Color color, {
    bool enabled = true,
    Function()? onChanged,
  }) {
    return CurrencyTextField(
      controller: ctrl,
      label: label,
      icon: Icons.money,
      enabled: enabled,
      onChanged: (_) {
        _calculateInstallment();
        if (onChanged != null) onChanged();
      },
    );
  }

  Widget _buildSearchResults() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        boxShadow: const [BoxShadow(color: AppColors.shadow, blurRadius: 10)],
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _filteredInStock.length,
        itemBuilder: (ctx, i) {
          final p = _filteredInStock[i];
          return ListTile(
            title: Text(
              p.name,
              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              "IMEI: ${p.imei ?? 'PK'} - Giá: ${MoneyUtils.formatCurrency(p.price)}",
            ),
            // HIỂN THỊ SỐ LƯỢNG TỒN TRONG LIST CHỌN
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  p.quantity > 0 ? Icons.add_circle : Icons.warning,
                  color: p.quantity > 0 ? AppColors.success : AppColors.error,
                ),
                Text(
                  "Tồn: ${p.quantity}",
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: p.quantity > 0 ? AppColors.warning : AppColors.error,
                  ),
                ),
              ],
            ),
            onTap: () {
              if (p.quantity == 0) {
                NotificationService.showSnackBar(
                  "Sản phẩm '${p.name}' chưa có trong kho!\nVui lòng tạo nhà cung cấp và nhập kho trước khi bán.",
                  color: AppColors.error,
                );
                return;
              }
              _addItem(p);
            },
          );
        },
      ),
    );
  }

  Widget _buildSelectedItemsList() {
    return Column(
      children: _selectedItems.map((item) {
        final product = item['product'] as Product;
        final quantity = item['quantity'] as int? ?? 1;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: AppColors.error),
                      onPressed: () {
                        setState(() {
                          _selectedItems.remove(item);
                          // Dispose IMEI controller và focus node khi xóa sản phẩm
                          final productId = product.id;
                          _imeiControllers[productId.toString()]?.dispose();
                          _imeiFocusNodes[productId.toString()]?.dispose();
                          _imeiControllers.remove(productId.toString());
                          _imeiFocusNodes.remove(productId.toString());
                          _calculateTotal();
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  "Giá bán: ${MoneyUtils.formatCurrency(item['sellPrice'])}",
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text("Số lượng: "),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 20),
                      onPressed: () {
                        if (quantity > 1) {
                          setState(() {
                            item['quantity'] = quantity - 1;
                            _calculateTotal();
                          });
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    SizedBox(
                      width: 50,
                      child: TextFormField(
                        initialValue: quantity.toString(),
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        onChanged: (value) {
                          final newQuantity = int.tryParse(value) ?? 1;
                          setState(() {
                            item['quantity'] = newQuantity;
                            _calculateTotal();
                          });
                        },
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 20),
                      onPressed: () {
                        setState(() {
                          item['quantity'] = quantity + 1;
                          _calculateTotal();
                        });
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Text("IMEI: "),
                    Expanded(
                      child: TextField(
                        controller:
                            _imeiControllers[product.id.toString()] ??
                            TextEditingController(text: item['imei'] ?? ''),
                        focusNode: _imeiFocusNodes[product.id.toString()],
                        onChanged: (value) {
                          setState(() {
                            item['imei'] = value.trim();
                          });
                        },
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          hintText: "Nhập IMEI (tùy chọn)",
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCustomerSuggestions() {
    if (_suggestCustomers.isEmpty) return const SizedBox();
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _suggestCustomers.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ActionChip(
            label: Text(_suggestCustomers[i]['customerName']),
            onPressed: () {
              nameCtrl.text = _suggestCustomers[i]['customerName'];
              phoneCtrl.text = _suggestCustomers[i]['phone'];
              setState(() => _suggestCustomers = []);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStockGuidance() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.inventory_2_outlined,
                color: AppColors.warning,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'KHO HÀNG TRỐNG',
                  style: AppTextStyles.body1.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.warning,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Shop của bạn chưa có hàng trong kho. Để bán hàng, vui lòng:',
            style: AppTextStyles.body2.copyWith(color: AppColors.onSurface),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const SmartStockInView(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add_box, size: 18),
                  label: const Text('NHẬP KHO'),
                  style: AppButtonStyles.successElevatedButtonStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class CustomerSelectionDialog extends StatefulWidget {
  final List<Customer> customers;

  const CustomerSelectionDialog({super.key, required this.customers});

  @override
  State<CustomerSelectionDialog> createState() =>
      _CustomerSelectionDialogState();
}

class _CustomerSelectionDialogState extends State<CustomerSelectionDialog> {
  String _searchQuery = '';
  late List<Customer> _filteredCustomers;

  @override
  void initState() {
    super.initState();
    _filteredCustomers = widget.customers;
  }

  void _filterCustomers(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredCustomers = widget.customers;
      } else {
        _filteredCustomers = widget.customers.where((customer) {
          return customer.name.toLowerCase().contains(query.toLowerCase()) ||
              customer.phone.contains(query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.people),
                const SizedBox(width: 8),
                Text(
                  'Chọn khách hàng',
                  style: TextStyle(
                    fontSize: AppTextStyles.headline2.fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),

            const Divider(),

            // Search
            TextField(
              decoration: const InputDecoration(
                hintText: 'Tìm kiếm khách hàng...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _filterCustomers,
            ),

            const SizedBox(height: 16),

            // Customer list
            Expanded(
              child: _filteredCustomers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isEmpty
                                ? 'Chưa có khách hàng nào'
                                : 'Không tìm thấy khách hàng',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _filteredCustomers.length,
                      itemBuilder: (context, index) {
                        final customer = _filteredCustomers[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            child: Text(
                              customer.name.isNotEmpty
                                  ? customer.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(customer.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(customer.phone),
                              if (customer.address?.isNotEmpty == true)
                                Text(
                                  'Địa chỉ: ${customer.address!}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: AppTextStyles.subtitle1.fontSize,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              if (customer.notes?.isNotEmpty == true)
                                Text(
                                  'Ghi chú: ${customer.notes!}',
                                  style: TextStyle(
                                    color: Colors.blue,
                                    fontSize: AppTextStyles.subtitle1.fontSize,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                          isThreeLine:
                              (customer.address?.isNotEmpty == true) ||
                              (customer.notes?.isNotEmpty == true),
                          onTap: () => Navigator.pop(context, customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
