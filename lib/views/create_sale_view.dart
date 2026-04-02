import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/money_utils.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/product_variant_model.dart';
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
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../services/variant_service.dart';
import '../models/payment_intent_model.dart';
import '../models/shop_settings_model.dart';
import '../constants/financial_constants.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/debounced_search_field.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/variant_selector.dart';
import '../widgets/responsive_wrapper.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import 'smart_stock_in_view.dart';
import 'supplier_list_view.dart';
import '../l10n/app_localizations.dart';
import '../utils/vietnamese_utils.dart';

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

  // Kết hợp thanh toán (Tiền mặt + Chuyển khoản)
  bool _isCombined = false;
  final cashAmountCtrl = TextEditingController(text: "0");
  final transferAmountCtrl = TextEditingController(text: "0");

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

  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;
  bool get _enableSerial => _shopSettings?.enableSerial ?? true;
  bool get _enableWarranty => _shopSettings?.enableWarranty ?? true;
  bool get _enableVariants => _shopSettings?.enableVariants ?? false;

  /// Terminology động theo ngành
  BusinessTerminology get _terms =>
      BusinessTypeHelper.instance.getTerminology(_shopSettings);

  // Variant Service for fashion/multi-size products
  final VariantService _variantService = VariantService();

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
      steps: [
        const GuideStep(
          title: '👤 Thông tin khách hàng',
          description:
              'Nhập SĐT để tự động điền tên khách cũ. Hoặc chọn từ danh bạ khách hàng.',
          icon: Icons.person,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '📦 Chọn ${_terms.productLabel.toLowerCase()}',
          description:
              'Tìm kiếm và chọn ${_terms.productLabel.toLowerCase()} trong kho. Có thể bán nhiều ${_terms.productLabel.toLowerCase()} trong 1 đơn.',
          icon: Icons.inventory_2,
          iconColor: Colors.orange,
        ),
        const GuideStep(
          title: '💰 Giá bán & Giảm giá',
          description:
              'Hệ thống tự tính tổng. Có thể nhập giảm giá trực tiếp hoặc điều chỉnh giá.',
          icon: Icons.attach_money,
          iconColor: Colors.green,
        ),
        const GuideStep(
          title: '🏦 Thanh toán trả góp',
          description:
              'Bật trả góp để nhập tiền đặt cọc, số tiền vay và ngân hàng hỗ trợ.',
          icon: Icons.credit_card,
          iconColor: Colors.blue,
        ),
        const GuideStep(
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
    cashAmountCtrl.dispose();
    transferAmountCtrl.dispose();

    // Dispose IMEI controllers và focus nodes
    _imeiControllers.forEach((_, controller) => controller.dispose());
    _imeiFocusNodes.forEach((_, focusNode) => focusNode.dispose());

    super.dispose();
  }

  Future<void> _selectCustomer() async {
    debugPrint("_selectCustomer: bắt đầu chọn khách hàng");
    final customerService = CustomerService();

    // Load local data first (fast) - don't block on cloud sync
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

    // Fire-and-forget cloud sync for next time
    SyncService.syncCustomersFromCloud().catchError((e) {
      debugPrint("_selectCustomer: background sync error (ignored): $e");
    });

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

    // Load shop settings for multi-industry terminology
    final shopSettings = await CategoryService().getShopSettings();

    if (!mounted) return;
    setState(() {
      _shopSettings = shopSettings;
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
    _checkAndRestoreDraft();
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
    _isCombined = (sale.paymentMethod == "KẾT HỢP");
    if (_isCombined) {
      cashAmountCtrl.text = _formatCurrency(sale.cashAmount);
      transferAmountCtrl.text = _formatCurrency(sale.transferAmount);
      downPaymentCtrl.text = _formatCurrency(
        sale.cashAmount + sale.transferAmount,
      );
    }
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

  // ── DRAFT SAVE / RESTORE ──

  static const _saleDraftKey = 'sale_draft';

  Future<void> _saveDraft() async {
    if (_selectedItems.isEmpty) {
      NotificationService.showSnackBar('Chưa có sản phẩm để lưu tạm', color: Colors.orange);
      return;
    }
    final draft = {
      'customerName': nameCtrl.text,
      'phone': phoneCtrl.text,
      'address': addressCtrl.text,
      'isWalkIn': _isWalkIn,
      'paymentMethod': _paymentMethod,
      'warranty': _saleWarranty,
      'discount': discountCtrl.text,
      'notes': noteCtrl.text,
      'isInstallment': _isInstallment,
      'downPayment': downPaymentCtrl.text,
      'downPaymentMethod': _downPaymentMethod,
      'loanAmount': loanAmountCtrl.text,
      'bankName': bankCtrl.text,
      'hasSecondBank': _hasSecondBank,
      'bankName2': bankCtrl2.text,
      'loanAmount2': loanAmountCtrl2.text,
      'isCombined': _isCombined,
      'cashAmount': cashAmountCtrl.text,
      'transferAmount': transferAmountCtrl.text,
      'totalPrice': priceCtrl.text,
      'items': _selectedItems.map((e) {
        final p = e['product'] as Product;
        return {
          'productId': p.id,
          'firestoreId': p.firestoreId,
          'quantity': e['quantity'],
          'sellPrice': e['sellPrice'],
          'isGift': e['isGift'] ?? false,
          'imei': e['imei'] ?? '',
          'variantName': e['variantName'],
        };
      }).toList(),
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    };
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_saleDraftKey, jsonEncode(draft));
    if (mounted) {
      NotificationService.showSnackBar('💾 Đã lưu tạm đơn bán', color: Colors.blue);
    }
  }

  Future<bool> _hasDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_saleDraftKey);
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_saleDraftKey);
    if (raw == null) return;
    try {
      final draft = jsonDecode(raw) as Map<String, dynamic>;
      nameCtrl.text = draft['customerName'] ?? '';
      phoneCtrl.text = draft['phone'] ?? '';
      addressCtrl.text = draft['address'] ?? '';
      _isWalkIn = draft['isWalkIn'] ?? false;
      _paymentMethod = draft['paymentMethod'] ?? 'TIỀN MẶT';
      _saleWarranty = draft['warranty'] ?? '12 THÁNG';
      discountCtrl.text = draft['discount'] ?? '0';
      noteCtrl.text = draft['notes'] ?? '';
      _isInstallment = draft['isInstallment'] ?? false;
      downPaymentCtrl.text = draft['downPayment'] ?? '0';
      _downPaymentMethod = draft['downPaymentMethod'] ?? 'TIỀN MẶT';
      loanAmountCtrl.text = draft['loanAmount'] ?? '0';
      bankCtrl.text = draft['bankName'] ?? '';
      _hasSecondBank = draft['hasSecondBank'] ?? false;
      bankCtrl2.text = draft['bankName2'] ?? '';
      loanAmountCtrl2.text = draft['loanAmount2'] ?? '0';
      _isCombined = draft['isCombined'] ?? false;
      cashAmountCtrl.text = draft['cashAmount'] ?? '0';
      transferAmountCtrl.text = draft['transferAmount'] ?? '0';
      priceCtrl.text = draft['totalPrice'] ?? '0';

      final items = (draft['items'] as List?) ?? [];
      for (final itemData in items) {
        final productId = itemData['productId'];
        final firestoreId = itemData['firestoreId'];
        Product? product;
        if (productId != null) {
          product = _allInStock.firstWhere(
            (p) => p.id == productId,
            orElse: () => _allInStock.firstWhere(
              (p) => p.firestoreId == firestoreId,
              orElse: () => Product(name: 'Đã xoá', cost: 0, price: 0, condition: '', type: '', createdAt: 0),
            ),
          );
        }
        if (product != null && product.name != 'Đã xoá') {
          _selectedItems.add({
            'product': product,
            'variant': null,
            'isGift': itemData['isGift'] ?? false,
            'sellPrice': itemData['sellPrice'] ?? product.price,
            'originalPrice': product.price,
            'quantity': itemData['quantity'] ?? 1,
            'imei': itemData['imei'] ?? '',
            'variantName': itemData['variantName'],
          });
        }
      }
      setState(() {});
      await _clearDraft();
      if (mounted) {
        NotificationService.showSnackBar('✅ Đã khôi phục đơn tạm', color: Colors.green);
      }
    } catch (e) {
      debugPrint('Error restoring sale draft: $e');
      await _clearDraft();
    }
  }

  Future<void> _clearDraft() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_saleDraftKey);
  }

  Future<void> _checkAndRestoreDraft() async {
    if (widget.editSale != null || widget.preSelectedProduct != null) return;
    if (!await _hasDraft()) return;
    if (!mounted) return;
    final restore = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Khôi phục đơn tạm?'),
        content: const Text('Bạn có đơn bán chưa hoàn tất. Khôi phục lại?'),
        actions: [
          TextButton(
            onPressed: () async {
              await _clearDraft();
              Navigator.pop(ctx, false);
            },
            child: const Text('XOÁ'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('KHÔI PHỤC'),
          ),
        ],
      ),
    );
    if (restore == true) {
      await _restoreDraft();
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

  /// Tính lại số tiền kết hợp khi chọn KẾT HỢP
  void _recalcCombinedPayment() {
    int total = _parseCurrency(priceCtrl.text);
    int discount = _parseCurrency(discountCtrl.text);
    int finalPrice = total - discount > 0 ? total - discount : 0;
    // Mặc định: đặt tiền mặt = 0 để user nhập, transfer = tổng
    cashAmountCtrl.text = _formatCurrency(0);
    transferAmountCtrl.text = _formatCurrency(finalPrice);
    // Cập nhật downPaymentCtrl = tổng (để logic lưu sale đúng)
    downPaymentCtrl.text = _formatCurrency(finalPrice);
  }

  /// Khi user thay đổi số tiền mặt/CK trong kết hợp
  void _onCombinedAmountChanged() {
    int cashAmt = _parseCurrency(cashAmountCtrl.text);
    int transferAmt = _parseCurrency(transferAmountCtrl.text);
    // Cập nhật downPaymentCtrl = tổng tiền thực nhận
    downPaymentCtrl.text = _formatCurrency(cashAmt + transferAmt);
    setState(() {});
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

  /// Build gifts string for SaleOrder.gifts field
  String? _buildGiftsString() {
    final giftItems = <String>[];
    for (final item in _selectedItems) {
      final product = item['product'] as Product;
      final isGift = item['isGift'] as bool? ?? false;
      final originalPrice = item['originalPrice'] as int? ?? product.price;
      final sellPrice = item['sellPrice'] as int? ?? originalPrice;
      final isDiscounted = !isGift && sellPrice < originalPrice;
      if (isGift) {
        giftItems.add('${product.name} (Tặng)');
      } else if (isDiscounted) {
        giftItems.add(
          '${product.name} (Giảm ${MoneyUtils.formatCurrency(originalPrice - sellPrice)})',
        );
      }
    }
    return giftItems.isNotEmpty ? giftItems.join(', ').toUpperCase() : null;
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
        'originalPrice': p.price,
        'quantity': 1,
        'imei': p.imei ?? '',
      });

      _imeiControllers[productId.toString()] = imeiController;
      _imeiFocusNodes[productId.toString()] = imeiFocusNode;

      _calculateTotal();
      searchProdCtrl.clear();
      _filteredInStock = _allInStock;
    });

    // Tự động focus vào IMEI field sau khi thêm sản phẩm (only for phones)
    if (_enableSerial && p.type == 'DIEN_THOAI') {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _imeiFocusNodes[productId.toString()]?.context != null) {
          FocusScope.of(
            context,
          ).requestFocus(_imeiFocusNodes[productId.toString()]);
        }
      });
    }
  }

  /// Add product to sale - with variant support for fashion shops
  Future<void> _addProductToSale(Product p) async {
    // Check if already added (for non-variant products, check by ID)
    // For variant products, same product can be added multiple times with different variants
    final hasVariantSupport = _enableVariants;

    // Load variants if enabled
    List<ProductVariant> variants = [];
    if (hasVariantSupport && p.firestoreId != null) {
      variants = await _variantService.getVariantsByProduct(p.firestoreId!);
    }

    ProductVariant? selectedVariant;

    // If product has variants, show variant selector dialog
    if (variants.isNotEmpty && mounted) {
      selectedVariant = await showDialog<ProductVariant>(
        context: context,
        builder: (ctx) => VariantSelectionDialog(
          productId: p.firestoreId!,
          productName: p.name,
          productPrice: p.price,
        ),
      );

      // User cancelled variant selection
      if (selectedVariant == null) return;

      // Check if this exact variant is already in cart
      final alreadyInCart = _selectedItems.any((item) {
        final itemVariant = item['variant'] as ProductVariant?;
        return itemVariant?.firestoreId == selectedVariant?.firestoreId;
      });

      if (alreadyInCart) {
        NotificationService.showSnackBar(
          'Biến thể này đã có trong giỏ hàng!',
          color: Colors.orange,
        );
        return;
      }
    } else {
      // Non-variant product: check if already added
      if (_selectedItems.any(
        (item) => item['product'].id == p.id && item['variant'] == null,
      )) {
        return;
      }
    }

    final productId = p.id;
    final imeiController = TextEditingController(text: p.imei ?? '');
    final imeiFocusNode = FocusNode();

    final itemPrice = selectedVariant?.salePrice ?? p.price;
    setState(() {
      _selectedItems.add({
        'product': p,
        'variant': selectedVariant, // null for non-variant products
        'isGift': false,
        'sellPrice': itemPrice,
        'originalPrice': itemPrice,
        'quantity': 1,
        'imei': p.imei ?? '',
        // Store variant display name for UI
        'variantName': selectedVariant?.displayName,
      });

      _imeiControllers[productId.toString()] = imeiController;
      _imeiFocusNodes[productId.toString()] = imeiFocusNode;

      _calculateTotal();
    });

    // Tự động focus vào IMEI field (only for phones, skip accessories)
    if (_enableSerial && p.type == 'DIEN_THOAI') {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && _imeiFocusNodes[productId.toString()]?.context != null) {
          FocusScope.of(
            context,
          ).requestFocus(_imeiFocusNodes[productId.toString()]);
        }
      });
    }
  }

  Future<void> _revertOldSaleChanges() async {
    final oldSale = widget.editSale!;
    debugPrint('Reverting changes for old sale: ${oldSale.firestoreId}');

    // 1. Hoàn trả inventory dựa trên IMEI của đơn hàng cũ
    final imeis = oldSale.productImeis.split(', ');
    final names = oldSale.productNames.split(', ');
    for (int i = 0; i < imeis.length; i++) {
      final imei = imeis[i].trim();
      if (imei.isEmpty) continue;

      Product? product;
      int qtyToRestore = 1;

      if (imei.toUpperCase().startsWith("PKX") || imei == "NO_IMEI") {
        // Phụ kiện (PKxN) hoặc sản phẩm không có IMEI → tìm theo tên
        if (imei.toUpperCase().startsWith("PKX")) {
          qtyToRestore =
              int.tryParse(imei.toUpperCase().replaceAll('PKX', '')) ?? 1;
        }
        if (i < names.length) {
          final nameEntry = names[i].trim();
          // Regex case-insensitive: match "Tên SP x2" hoặc "Tên SP X2"
          final nameMatch = RegExp(r'^(.+?)\s+[xX]\d+').firstMatch(nameEntry);
          var productName = nameMatch != null
              ? nameMatch.group(1)!.trim()
              : nameEntry;
          // Bỏ hậu tố (TẶNG) hoặc (GIẢM ...) nếu còn dính
          productName = productName.replaceAll(
            RegExp(r'\s*\(TẶNG\)\s*$', caseSensitive: false),
            '',
          );
          productName = productName.replaceAll(
            RegExp(r'\s*\(GIẢM\s+[\d,.]+\)\s*$', caseSensitive: false),
            '',
          );
          productName = productName.trim();
          debugPrint(
            '🔍 Tìm sản phẩm theo tên: "$productName" (từ: "$nameEntry")',
          );
          product = await db.getProductByName(productName);
          if (product == null) {
            debugPrint('⚠️ Không tìm thấy sản phẩm theo tên: $productName');
          }
        }
      } else {
        // Điện thoại có IMEI → tìm theo IMEI
        product = await db.getProductByImei(imei);
      }

      if (product != null) {
        await db.addProductQuantity(product.id!, qtyToRestore);
        product.quantity += qtyToRestore;
        if (product.status == 0 && product.quantity > 0) {
          product.status = 1;
          await db.updateProductStatus(product.id!, 1);
        }
        // Sync trực tiếp lên cloud (tránh real-time listener ghi đè)
        if (product.firestoreId != null && product.firestoreId!.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('products')
                .doc(product.firestoreId)
                .update({
                  'quantity': product.quantity,
                  'status': product.status,
                  'updatedAt': FieldValue.serverTimestamp(),
                });
          } catch (e) {
            debugPrint('⚠️ Cloud sync failed, queueing: $e');
            await SyncOrchestrator().enqueue(
              entityType: SyncEntityType.product,
              entityId: product.id!,
              firestoreId: product.firestoreId,
              operation: SyncOperation.update,
              data: product.toMap(),
            );
          }
        }
        debugPrint(
          '✅ Restored inventory: ${product.name} +$qtyToRestore (total: ${product.quantity})',
        );
      }
    }

    // 2. Xóa debt cũ nếu có
    if (oldSale.firestoreId != null) {
      final existingDebts = await db.getAllDebts();
      final linkedDebts = existingDebts
          .where((d) => d['linkedId'] == oldSale.firestoreId)
          .toList();
      for (final linkedDebt in linkedDebts) {
        final debtFId = linkedDebt['firestoreId'] as String?;
        if (debtFId != null) {
          await db.deleteDebtByFirestoreId(debtFId);
          // Enqueue soft delete lên cloud
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.debt,
            entityId: linkedDebt['id'] as int,
            firestoreId: debtFId,
            operation: SyncOperation.delete,
            data: {...linkedDebt, 'deleted': true},
          );
          debugPrint(
            'Marked old debt as deleted for sale: ${oldSale.firestoreId}',
          );
        }
      }
    }

    // 3. Xóa PaymentIntents cũ liên quan
    try {
      final saleRef = oldSale.firestoreId ?? 'sale_${oldSale.soldAt}';
      final deleted = await db.deletePaymentIntentsByReferenceId(saleRef);
      if (deleted > 0) {
        debugPrint(
          '🗑️ Deleted $deleted old payment intents for sale $saleRef',
        );
      }
    } catch (e) {
      debugPrint('⚠️ Failed to delete old payment intents: $e');
    }

    // 4. Trừ lại chi tiêu khách hàng cũ (sẽ cộng lại khi lưu đơn mới)
    try {
      final phone = oldSale.walkInPhone ?? oldSale.phone;
      if (phone.isNotEmpty) {
        final customerService = CustomerService();
        final customer = await customerService.getCustomerByPhone(phone);
        if (customer != null && oldSale.finalPrice > 0) {
          final newTotal = (customer.totalSpent - oldSale.finalPrice)
              .clamp(0, double.maxFinite)
              .toInt();
          final updated = customer.copyWith(totalSpent: newTotal);
          await customerService.updateCustomer(updated);
          debugPrint(
            '📊 Reverted old sale customer totalSpent: ${customer.totalSpent} → $newTotal',
          );
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to revert customer stats: $e');
    }
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
        "VUI LÒNG CHỌN ${_terms.productLabel.toUpperCase()}",
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
          : (nameCtrl.text.isNotEmpty
                ? nameCtrl.text.trim().toUpperCase()
                : 'walkin');
      final String uniqueId =
          widget.editSale?.firestoreId ?? "sale_${now}_$safeTail";
        final currentUser = FirebaseAuth.instance.currentUser;
      String seller =
          widget.editSale?.sellerName.isNotEmpty == true
          ? widget.editSale!.sellerName
          : currentUser?.email?.split('@').first.toUpperCase() ?? "NV";
        final sellerUid = widget.editSale?.sellerUid ?? currentUser?.uid;
      int totalPrice = _parseCurrency(priceCtrl.text);

      // Parse discount và tính finalPrice (thành tiền sau giảm giá)
      int discount = _parseCurrency(discountCtrl.text);
      int finalPrice = totalPrice - discount;
      if (finalPrice < 0) finalPrice = 0;

      // FIX: paidAmount phải dựa trên finalPrice (sau giảm giá), không phải totalPrice
      int paidAmount = _parseCurrency(downPaymentCtrl.text);
      if (_isCombined) {
        // Kết hợp: paidAmount = tiền mặt + chuyển khoản
        paidAmount =
            _parseCurrency(cashAmountCtrl.text) +
            _parseCurrency(transferAmountCtrl.text);
      } else if (_paymentMethod != "CÔNG NỢ" &&
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
            .map((e) {
              final name = (e['product'] as Product).name;
              final qty = e['quantity'] as int;
              final isGift = e['isGift'] as bool? ?? false;
              final origPrice = e['originalPrice'] as int? ?? 0;
              final curPrice = e['sellPrice'] as int? ?? origPrice;
              final isDisc = !isGift && curPrice < origPrice;
              if (isGift) {
                return "$name x$qty (Tặng)";
              } else if (isDisc) {
                return "$name x$qty (Giảm ${MoneyUtils.formatCurrency(origPrice - curPrice)})";
              }
              return "$name x$qty";
            })
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
        sellerUid: sellerUid,
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
        gifts: _buildGiftsString(),
        cashAmount: _isCombined ? _parseCurrency(cashAmountCtrl.text) : 0,
        transferAmount: _isCombined
            ? _parseCurrency(transferAmountCtrl.text)
            : 0,
        productCosts: _selectedItems
            .map((e) =>
                '${(e['product'] as Product).cost * (e['quantity'] as int)}')
            .join(', '),
        phoneRevenue: _selectedItems
            .where((e) => (e['product'] as Product).type == 'DIEN_THOAI')
            .fold(0, (sum, e) {
              final qty = e['quantity'] as int;
              final sellPrice = e['sellPrice'] as int? ?? (e['product'] as Product).price;
              return sum + (sellPrice * qty);
            }),
        phoneCost: _selectedItems
            .where((e) => (e['product'] as Product).type == 'DIEN_THOAI')
            .fold(0, (sum, e) {
              final qty = e['quantity'] as int;
              return sum + ((e['product'] as Product).cost * qty);
            }),
      );

      // Validate IMEI trước khi thực hiện transaction
      for (var item in _selectedItems) {
        final p = item['product'] as Product;
        final customImei = item['imei'] as String?;
        if (p.type == 'DIEN_THOAI' &&
            (customImei == null || customImei.isEmpty) &&
            (p.imei == null || p.imei!.isEmpty)) {
          NotificationService.showSnackBar(
            "Không thể bán ${_terms.productLabel.toLowerCase()} chưa có ${_terms.specialField1Label}: ${p.name}",
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
        debugPrint(
          '⚠️ Some products missing firestoreId, sale cannot be confirmed on cloud yet',
        );
        if (mounted) {
          final shouldContinue = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sản phẩm chưa đồng bộ'),
              content: const Text(
                'Có sản phẩm chưa có mã đồng bộ cloud nên nếu tiếp tục, đơn bán chỉ lưu trên máy này tạm thời.\n\n'
                'Chủ shop và các tài khoản khác sẽ chưa thấy đơn cho tới khi đồng bộ xong. Bạn có muốn tiếp tục bán offline không?',
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
                  child: const Text('Bán offline'),
                ),
              ],
            ),
          );

          if (shouldContinue == true) {
            transactionResult = {'success': true, 'localOnly': true};
          } else {
            setState(() => _isSaving = false);
            return;
          }
        } else {
          transactionResult = {'success': false, 'error': 'Màn hình đã đóng'};
        }
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
        final variant = item['variant'] as ProductVariant?;

        // Handle variant stock deduction for fashion shops
        if (variant != null) {
          // Deduct from variant stock
          await _variantService.decreaseQuantity(variant.firestoreId, quantity);
          debugPrint(
            '👗 Variant sale: Deducted ${p.name} - ${variant.displayName} by $quantity',
          );
        } else if (isLocalOnly) {
          // Chỉ cập nhật local database khi bán offline (non-variant products)
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

      // Log sale vào nhật ký tài chính (nếu không phải công nợ)
      if (_paymentMethod != 'CÔNG NỢ') {
        try {
          await FinancialActivityService.logSale(
            firestoreId: sale.firestoreId ?? 'sale_${sale.soldAt}',
            totalPrice: finalPrice,
            paymentMethod: _paymentMethod,
            customerName: sale.walkInName ?? sale.customerName,
            phone: sale.walkInPhone ?? sale.phone,
            productNames: sale.productNames,
            sellerName: sale.sellerName,
            soldAt: sale.soldAt,
            isInstallment: _isInstallment,
            downPayment: _parseCurrency(downPaymentCtrl.text),
            downPaymentMethod: _downPaymentMethod,
            bankName: bankCtrl.text.toUpperCase(),
          );
          debugPrint('📝 Logged sale to financial activity');
        } catch (e) {
          debugPrint('⚠️ Failed to log sale activity: $e');
        }
      }

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
        } else if (_isCombined) {
          // Kết hợp tiền mặt + chuyển khoản - tạo 2 PaymentIntent
          final cashAmt = _parseCurrency(cashAmountCtrl.text);
          final transferAmt = _parseCurrency(transferAmountCtrl.text);

          if (cashAmt > 0) {
            final intentCash = PaymentIntent(
              id: 'pi_sale_cash_${saleRef}_$now',
              type: PaymentIntentType.salePayment,
              amount: cashAmt,
              description:
                  'Bán hàng (tiền mặt): $payerName - ${_selectedItems.length} SP',
              referenceId: saleRef,
              referenceType: 'sale',
              status: PaymentIntentStatus.completed,
              createdBy: userName,
              createdAt: now,
              paidAt: now,
              paymentMethod: PaymentMethod.cash,
              personName: payerName,
              personPhone: payerPhone,
              metadata: {
                'customerName': payerName,
                'phone': payerPhone,
                'productNames': sale.productNames,
                'isCombined': true,
                'combinedCash': cashAmt,
                'combinedTransfer': transferAmt,
              },
            );
            await PaymentIntentService.createIntent(intentCash);
            debugPrint(
              '✅ Created PaymentIntent for combined CASH: ${intentCash.id}',
            );
          }

          if (transferAmt > 0) {
            final intentTransfer = PaymentIntent(
              id: 'pi_sale_transfer_${saleRef}_$now',
              type: PaymentIntentType.salePayment,
              amount: transferAmt,
              description:
                  'Bán hàng (chuyển khoản): $payerName - ${_selectedItems.length} SP',
              referenceId: saleRef,
              referenceType: 'sale',
              status: PaymentIntentStatus.completed,
              createdBy: userName,
              createdAt: now + 1, // +1ms to avoid duplicate
              paidAt: now,
              paymentMethod: PaymentMethod.transfer,
              personName: payerName,
              personPhone: payerPhone,
              metadata: {
                'customerName': payerName,
                'phone': payerPhone,
                'productNames': sale.productNames,
                'isCombined': true,
                'combinedCash': cashAmt,
                'combinedTransfer': transferAmt,
              },
            );
            await PaymentIntentService.createIntent(intentTransfer);
            debugPrint(
              '✅ Created PaymentIntent for combined TRANSFER: ${intentTransfer.id}',
            );
          }
        } else {
          // Tiền mặt / Chuyển khoản - đã nhận đủ tiền
          final intent = PaymentIntent(
            id: 'pi_sale_${saleRef}_$now',
            type: PaymentIntentType.salePayment,
            amount: finalPrice,
            description: 'Bán hàng: $payerName - ${_selectedItems.length} SP',
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

      // Create/update customer only for non-walk-in with non-empty phone.
      final normalizedPhoneForCustomer = phoneCtrl.text.trim();
      if (!_isWalkIn && normalizedPhoneForCustomer.isNotEmpty) {
        final customerService = CustomerService();
        final existingCustomers = await customerService.getCustomers();
        final existing = existingCustomers
            .where((c) => c.phone == normalizedPhoneForCustomer)
            .toList();
        if (existing.isEmpty) {
          final newCustomer = Customer(
            name: nameCtrl.text.trim().toUpperCase(),
            phone: normalizedPhoneForCustomer,
            address: addressCtrl.text.trim().toUpperCase(),
            createdAt: DateTime.now().millisecondsSinceEpoch,
            totalSpent: finalPrice,
          );
          await customerService.addCustomer(newCustomer);
        } else {
          await customerService.updateCustomerStatsAfterSale(
            normalizedPhoneForCustomer,
            finalPrice,
            address: addressCtrl.text.trim().toUpperCase(),
            name: nameCtrl.text.trim().toUpperCase(),
          );
        }
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

      // Chỉ gửi chat "đã bán" khi đơn đã được xác nhận trên cloud.
      if (!isLocalOnly) {
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
      } else {
        debugPrint('ℹ️ Skipped cloud sale chat because sale is local-only');
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
        isLocalOnly
            ? "ĐÃ LƯU BÁN OFFLINE - CHƯA ĐỒNG BỘ CLOUD"
            : "ĐÃ BÁN HÀNG THÀNH CÔNG!",
        color: isLocalOnly ? Colors.orange : Colors.green,
      );
      _clearDraft();
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
                colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
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
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
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
              : "Chọn ${_terms.productLabel.toLowerCase()}, nhập thông tin khách và hoàn tất đơn bán.",
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
                '${_selectedItems.length} ${_terms.productLabel.toLowerCase()} đã chọn',
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
          : ResponsiveCenter(
              maxWidth: 800,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                                  color: Colors.blue.shade700,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _terms.productLabel.toUpperCase(),
                                  style: AppTextStyles.caption.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  "${_selectedItems.length} đã chọn",
                                  style: AppTextStyles.caption.copyWith(
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            DebouncedSearchField(
                              controller: searchProdCtrl,
                              hint:
                                  "Tìm ${_terms.productLabel.toLowerCase()} hoặc ${_terms.specialField1Label}...",
                              onSearch: (v) => setState(
                                () => _filteredInStock = _allInStock
                                    .where(
                                      (p) =>
                                          VietnameseUtils.containsVietnamese(
                                            p.name,
                                            v,
                                          ) ||
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
                              title: const Text(
                                'Khách vãng lai (không lưu danh bạ)',
                              ),
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
                                  if (_isWalkIn &&
                                      nameCtrl.text.trim().isEmpty) {
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
                                      labelText: _isWalkIn
                                          ? "TÊN (tùy chọn)"
                                          : "TÊN",
                                      prefixIcon: const Icon(
                                        Icons.person_outline,
                                        size: 18,
                                      ),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
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
                                      prefixIcon: const Icon(
                                        Icons.phone,
                                        size: 18,
                                      ),
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
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
                                    icon: const Icon(
                                      Icons.person_add,
                                      size: 18,
                                    ),
                                    color: AppColors.success,
                                    constraints: const BoxConstraints(),
                                    padding: const EdgeInsets.only(left: 4),
                                    tooltip: 'Thêm nhanh KH',
                                  ),
                              ],
                            ),
                            // Địa chỉ khách hàng
                            const SizedBox(height: 6),
                            TextFormField(
                              controller: addressCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Địa chỉ KH (tùy chọn)',
                                prefixIcon: Icon(Icons.location_on, size: 18),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              textCapitalization: TextCapitalization.characters,
                              style: AppTextStyles.body2,
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

                    // === NÚT LƯU TẠM + HOÀN TẤT ===
                    if (widget.editSale == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          height: 44,
                          child: OutlinedButton.icon(
                            onPressed: _isSaving ? null : _saveDraft,
                            icon: const Icon(Icons.save_outlined, size: 18),
                            label: const Text('LƯU TẠM', style: TextStyle(fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.blue.shade700,
                              side: BorderSide(color: Colors.blue.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
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
                                    ? "CHƯA CHỌN ${_terms.productLabel.toUpperCase()}"
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

        // Tổng tiền (1 dòng riêng)
        Row(
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
              onPressed: () => setState(() => _autoCalcTotal = !_autoCalcTotal),
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
        const SizedBox(height: 6),
        // Giảm giá (1 dòng riêng)
        Row(
          children: [
            const Icon(Icons.discount, size: 16, color: Colors.orange),
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
          children:
              ["TIỀN MẶT", "CHUYỂN KHOẢN", "KẾT HỢP", "CÔNG NỢ", "TRẢ GÓP (NH)"]
                  .map(
                    (e) => ChoiceChip(
                      label: Text(
                        e,
                        style: AppTextStyles.caption.copyWith(fontSize: 13),
                      ),
                      selected: _paymentMethod == e,
                      onSelected: (v) => setState(() {
                        _paymentMethod = e;
                        _isInstallment = (e == "TRẢ GÓP (NH)");
                        _isCombined = (e == "KẾT HỢP");
                        if (!_isInstallment) _hasSecondBank = false;
                        if (_isCombined) {
                          // Auto-fill cash + transfer = total
                          _recalcCombinedPayment();
                        }
                      }),
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                  )
                  .toList(),
        ),

        const Divider(height: 12),

        // Số tiền thu thực tế (ẩn khi KẾT HỢP vì có UI riêng)
        if (!_isCombined)
          _moneyInput(
            downPaymentCtrl,
            _isInstallment ? "KHÁCH TRẢ" : "SỐ TIỀN",
            AppColors.secondary,
          ),

        // === KẾT HỢP THANH TOÁN (TIỀN MẶT + CHUYỂN KHOẢN) ===
        if (_isCombined)
          Card(
            margin: const EdgeInsets.only(top: 6),
            color: Colors.teal.shade50,
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8),
              dense: true,
              initiallyExpanded: true,
              leading: Icon(
                Icons.swap_horiz,
                color: Colors.teal.shade700,
                size: 18,
              ),
              title: Text(
                "TIỀN MẶT + CHUYỂN KHOẢN",
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                  fontSize: 14,
                ),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  child: Column(
                    children: [
                      _moneyInput(
                        cashAmountCtrl,
                        "💵 TIỀN MẶT",
                        Colors.green,
                        onChanged: (_) => _onCombinedAmountChanged(),
                      ),
                      const SizedBox(height: 6),
                      _moneyInput(
                        transferAmountCtrl,
                        "🏦 CHUYỂN KHOẢN",
                        Colors.blue,
                        onChanged: (_) => _onCombinedAmountChanged(),
                      ),
                      const SizedBox(height: 8),
                      // Hiển thị tổng và so sánh với giá trị đơn hàng
                      Builder(
                        builder: (context) {
                          final cashAmt = _parseCurrency(cashAmountCtrl.text);
                          final transferAmt = _parseCurrency(
                            transferAmountCtrl.text,
                          );
                          final total = cashAmt + transferAmt;
                          final finalPrice =
                              _parseCurrency(priceCtrl.text) -
                              _parseCurrency(discountCtrl.text);
                          final diff = total - finalPrice;
                          return Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: diff == 0
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: diff == 0
                                    ? Colors.green.shade300
                                    : Colors.red.shade300,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "TỔNG: ${MoneyUtils.formatCurrency(total)}",
                                  style: AppTextStyles.caption.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: diff == 0
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                    fontSize: 14,
                                  ),
                                ),
                                if (diff != 0)
                                  Text(
                                    diff > 0
                                        ? "(Dư ${MoneyUtils.formatCurrency(diff)})"
                                        : "(Thiếu ${MoneyUtils.formatCurrency(-diff)})",
                                    style: AppTextStyles.caption.copyWith(
                                      color: Colors.red.shade700,
                                      fontSize: 13,
                                    ),
                                  ),
                                if (diff == 0)
                                  Icon(
                                    Icons.check_circle,
                                    color: Colors.green.shade700,
                                    size: 16,
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
                  fontSize: 14,
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
                              fontSize: 13,
                            ),
                          ),
                          ...["T.MẶT", "C.KHOẢN"].map(
                            (m) => ChoiceChip(
                              label: Text(
                                m,
                                style: AppTextStyles.caption.copyWith(
                                  fontSize: 12,
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
                        children:
                            ["FE", "HOME", "MIRAE", "HD", "MB", "F83", "T86"]
                                .map(
                                  (b) => ActionChip(
                                    label: Text(
                                      b,
                                      style: AppTextStyles.caption.copyWith(
                                        fontSize: 12,
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
                          children:
                              ["FE", "HOME", "MIRAE", "HD", "MB", "F83", "T86"]
                                  .map(
                                    (b) => ActionChip(
                                      label: Text(
                                        b,
                                        style: AppTextStyles.caption.copyWith(
                                          fontSize: 12,
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
            // Multi-Industry: Only show warranty for electronics
            if (_enableWarranty)
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  value: _saleWarranty,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: _terms.specialField2Label,
                    prefixIcon: const Icon(Icons.verified_user, size: 16),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
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
                  onChanged: (v) =>
                      setState(() => _saleWarranty = v ?? "KO BH"),
                ),
              ),
            if (_enableWarranty) const SizedBox(width: 12),
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
            children: ["FE", "HOME", "MIRAE", "HD", "MB", "F83", "T86"]
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
              children: ["FE", "HOME", "MIRAE", "HD", "MB", "F83", "T86"]
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
          items: ["KO BH", "1 THÁNG", "3 THÁNG", "6 THÁNG", "12 THÁNG"]
              .map(
                (e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
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
    Function(String)? onChanged,
  }) {
    return CurrencyTextField(
      controller: ctrl,
      label: label,
      icon: Icons.money,
      enabled: enabled,
      onChanged: (val) {
        _calculateInstallment();
        if (onChanged != null) onChanged(val);
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
              "${_terms.specialField1Label}: ${p.imei ?? 'PK'} - Giá: ${MoneyUtils.formatCurrency(p.price)}",
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
                  "${_terms.productLabel} '${p.name}' chưa có trong kho!\nVui lòng tạo nhà cung cấp và nhập kho trước khi bán.",
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

  /// Show bottom sheet for gift/discount options — single overlay, no chaining
  Future<void> _showGiftDiscountSheet(Map<String, dynamic> item) async {
    final product = item['product'] as Product;
    final isGift = item['isGift'] as bool;
    final originalPrice = item['originalPrice'] as int;
    final sellPrice = item['sellPrice'] as int;
    final hasPromotion = isGift || sellPrice < originalPrice;

    // Result: {'action': 'gift'|'discount'|'reset', 'price': int?}
    final result = await showAppBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true, // allow resize when keyboard opens
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return _GiftDiscountSheetContent(
          productName: product.name,
          originalPrice: originalPrice,
          currentSellPrice: sellPrice,
          isGift: isGift,
          hasPromotion: hasPromotion,
          formatCurrency: _formatCurrency,
          parseCurrency: _parseCurrency,
        );
      },
    );

    if (!mounted || result == null) return;

    final action = result['action'] as String;
    switch (action) {
      case 'gift':
        setState(() {
          item['isGift'] = true;
          item['sellPrice'] = 0;
          _calculateTotal();
        });
        break;
      case 'discount':
        final newPrice = result['price'] as int;
        setState(() {
          item['isGift'] = false;
          item['sellPrice'] = newPrice;
          _calculateTotal();
        });
        break;
      case 'reset':
        setState(() {
          item['isGift'] = false;
          item['sellPrice'] = originalPrice;
          _calculateTotal();
        });
        break;
    }
  }

  Widget _buildSelectedItemsList() {
    return Column(
      children: _selectedItems.map((item) {
        final product = item['product'] as Product;
        final quantity = item['quantity'] as int? ?? 1;
        final variant = item['variant'] as ProductVariant?;
        final variantName = item['variantName'] as String?;
        final isGift = item['isGift'] as bool? ?? false;
        final originalPrice = item['originalPrice'] as int? ?? product.price;
        final sellPrice = item['sellPrice'] as int? ?? originalPrice;
        final isDiscounted = !isGift && sellPrice < originalPrice;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: isGift
              ? Colors.green.shade50
              : (isDiscounted ? Colors.orange.shade50 : null),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isGift) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'TẶNG',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ] else if (isDiscounted) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.orange,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '-${MoneyUtils.formatCurrency(originalPrice - sellPrice)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // Show variant info if available
                          if (variantName != null) ...[
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Text(
                                variantName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.card_giftcard,
                        color: isGift
                            ? Colors.green
                            : (isDiscounted ? Colors.orange : Colors.grey),
                      ),
                      tooltip: 'Tặng / Giảm giá',
                      onPressed: () => _showGiftDiscountSheet(item),
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
                // Show variant stock if available
                if (variant != null) ...[
                  Text(
                    "Tồn kho: ${variant.quantity}",
                    style: TextStyle(
                      fontSize: 14,
                      color: variant.quantity > 0 ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (isGift)
                  Text(
                    'Giá gốc: ${MoneyUtils.formatCurrency(originalPrice)} → MIỄN PHÍ',
                    style: TextStyle(
                      color: Colors.green.shade700,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: Colors.green.shade700,
                    ),
                  )
                else if (isDiscounted)
                  Row(
                    children: [
                      Text(
                        '${MoneyUtils.formatCurrency(originalPrice)}',
                        style: TextStyle(
                          color: Colors.grey,
                          decoration: TextDecoration.lineThrough,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Giá bán: ${MoneyUtils.formatCurrency(sellPrice)}',
                        style: TextStyle(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                else
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
                // Multi-Industry: Only show serial field if enabled
                // Hide IMEI for accessories (PHU_KIEN) - only show for phones
                if (_enableSerial && product.type == 'DIEN_THOAI')
                  Row(
                    children: [
                      Text("${_terms.specialField1Label}: "),
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
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            hintText: _terms.specialField1Hint,
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
      padding: const EdgeInsets.all(12),
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
          return VietnameseUtils.containsVietnamese(customer.name, query) ||
              customer.phone.contains(query) ||
              VietnameseUtils.containsVietnamese(customer.address ?? '', query);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: responsiveDialogWidth(context),
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

/// Stateful bottom sheet content for gift/discount — avoids chaining overlays
class _GiftDiscountSheetContent extends StatefulWidget {
  final String productName;
  final int originalPrice;
  final int currentSellPrice;
  final bool isGift;
  final bool hasPromotion;
  final String Function(int) formatCurrency;
  final int Function(String) parseCurrency;

  const _GiftDiscountSheetContent({
    required this.productName,
    required this.originalPrice,
    required this.currentSellPrice,
    required this.isGift,
    required this.hasPromotion,
    required this.formatCurrency,
    required this.parseCurrency,
  });

  @override
  State<_GiftDiscountSheetContent> createState() =>
      _GiftDiscountSheetContentState();
}

class _GiftDiscountSheetContentState extends State<_GiftDiscountSheetContent> {
  bool _showDiscountInput = false;
  late TextEditingController _priceController;

  @override
  void initState() {
    super.initState();
    final initialPrice =
        widget.currentSellPrice > 0 &&
            widget.currentSellPrice < widget.originalPrice
        ? widget.currentSellPrice
        : widget.originalPrice;
    _priceController = TextEditingController(
      text: widget.formatCurrency(initialPrice),
    );
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Ưu đãi: ${widget.productName}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
            ),
            const Divider(height: 1),
            if (!_showDiscountInput) ...[
              // --- Menu options ---
              ListTile(
                leading: const Icon(Icons.card_giftcard, color: Colors.green),
                title: const Text('Tặng miễn phí (0đ)'),
                subtitle: const Text('Không tính tiền sản phẩm này'),
                selected: widget.isGift,
                onTap: () => Navigator.pop(context, {'action': 'gift'}),
              ),
              ListTile(
                leading: const Icon(Icons.discount, color: Colors.orange),
                title: const Text('Giảm giá sản phẩm'),
                subtitle: Text(
                  'Giá gốc: ${MoneyUtils.formatCurrency(widget.originalPrice)}',
                ),
                selected:
                    !widget.isGift &&
                    widget.currentSellPrice < widget.originalPrice &&
                    widget.currentSellPrice > 0,
                onTap: () => setState(() => _showDiscountInput = true),
              ),
              if (widget.hasPromotion)
                ListTile(
                  leading: const Icon(Icons.undo, color: Colors.grey),
                  title: const Text('Bỏ ưu đãi'),
                  subtitle: Text(
                    'Khôi phục giá ${MoneyUtils.formatCurrency(widget.originalPrice)}',
                  ),
                  onTap: () => Navigator.pop(context, {'action': 'reset'}),
                ),
              const SizedBox(height: 8),
            ] else ...[
              // --- Inline discount input ---
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Giá gốc: ${MoneyUtils.formatCurrency(widget.originalPrice)}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá bán mới',
                        suffixText: 'đ',
                        border: OutlineInputBorder(),
                      ),
                      autofocus: true,
                      onChanged: (value) {
                        final parsed = widget.parseCurrency(value);
                        final formatted = widget.formatCurrency(parsed);
                        if (formatted != value) {
                          _priceController.value = TextEditingValue(
                            text: formatted,
                            selection: TextSelection.collapsed(
                              offset: formatted.length,
                            ),
                          );
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () =>
                              setState(() => _showDiscountInput = false),
                          child: const Text('QUAY LẠI'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _onConfirmDiscount,
                          child: const Text('XÁC NHẬN'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _onConfirmDiscount() {
    final price = widget.parseCurrency(_priceController.text);
    if (price < 0) {
      NotificationService.showSnackBar('Giá không hợp lệ', color: Colors.red);
      return;
    }
    if (price >= widget.originalPrice) {
      NotificationService.showSnackBar(
        'Giá ưu đãi phải thấp hơn giá gốc (${MoneyUtils.formatCurrency(widget.originalPrice)})',
        color: Colors.orange,
      );
      return;
    }
    Navigator.pop(context, {'action': 'discount', 'price': price});
  }
}
