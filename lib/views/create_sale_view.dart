import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/money_utils.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/customer_model.dart';
import '../models/sale_order_model.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/customer_service.dart';
import '../services/sync_service.dart';
import '../services/user_service.dart';
import '../services/event_bus.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/debounced_search_field.dart';
import '../widgets/currency_text_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart'; 
import 'stock_in_view.dart'; // Restored stock_in_view import

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
  
  bool _isInstallment = false;
  final downPaymentCtrl = TextEditingController(text: "0");
  final loanAmountCtrl = TextEditingController(text: "0");
  final bankCtrl = TextEditingController();
  
  String _paymentMethod = "TIỀN MẶT";
  String _saleWarranty = "12 THÁNG";
  bool _autoCalcTotal = true; 

  List<Map<String, dynamic>> _selectedItems = []; 
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
    priceCtrl.addListener(_formatPrice);
    loanAmountCtrl.addListener(_formatLoanAmount);
    // Refresh UI for add customer button when name/phone changes
    nameCtrl.addListener(() => setState(() {}));
    phoneCtrl.addListener(() => setState(() {}));
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = perms['allowViewSales'] ?? false);
  }

  @override
  void dispose() {
    downPaymentCtrl.removeListener(_calculateInstallment);
    priceCtrl.removeListener(_formatPrice);
    loanAmountCtrl.removeListener(_formatLoanAmount);
    nameCtrl.dispose(); phoneCtrl.dispose(); addressCtrl.dispose();
    priceCtrl.dispose(); noteCtrl.dispose(); searchProdCtrl.dispose();
    downPaymentCtrl.dispose(); loanAmountCtrl.dispose(); bankCtrl.dispose();
    
    // Dispose IMEI controllers và focus nodes
    _imeiControllers.forEach((_, controller) => controller.dispose());
    _imeiFocusNodes.forEach((_, focusNode) => focusNode.dispose());
    
    super.dispose();
  }

  Future<void> _selectCustomer() async {
    debugPrint("_selectCustomer: bắt đầu chọn khách hàng");
    final customerService = CustomerService();
    
    // Sync customers from cloud first
    debugPrint("_selectCustomer: bắt đầu sync từ cloud");
    await SyncService.syncCustomersFromCloud();
    debugPrint("_selectCustomer: đã sync xong từ cloud");
    
    final customers = await customerService.getCustomers();
    debugPrint("_selectCustomer: lấy được ${customers.length} customers từ local DB");

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
    final phoneError = UserService.validatePhone(phone);
    if (phoneError != null) {
      NotificationService.showSnackBar(phoneError, color: Colors.red);
      return;
    }

    try {
      final customerService = CustomerService();
      // Kiểm tra khách hàng đã tồn tại chưa
      final existingCustomers = await customerService.getCustomers();
      final existing = existingCustomers.where((c) => c.phone == phone).toList();
      
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

  void _formatPrice() {
    final text = priceCtrl.text;
    if (text.isEmpty) return;
    final clean = text.replaceAll(',', '').split('.').first;
    final num = int.tryParse(clean);
    if (num != null) {
      final formatted = MoneyUtils.formatVND(MoneyUtils.inputToVND(num));
      if (formatted != text) {
        priceCtrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length - 4),
        );
      }
    }
  }

  void _formatLoanAmount() {
    final text = loanAmountCtrl.text;
    if (text.isEmpty) return;
    final clean = text.replaceAll(',', '').split('.').first;
    final num = int.tryParse(clean);
    if (num != null) {
      final formatted = MoneyUtils.formatVND(MoneyUtils.inputToVND(num));
      if (formatted != text) {
        loanAmountCtrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length - 4),
        );
      }
    }
  }

  Future<void> _loadData() async {
    final prods = await db.getInStockProducts();
    final suggests = await db.getCustomerSuggestions();
    if (!mounted) return;
    setState(() { _allInStock = prods; _filteredInStock = prods; _suggestCustomers = suggests; _isLoading = false; });
    if (widget.preSelectedProduct != null) { 
      _addProductToSale(widget.preSelectedProduct!); 
    }
    if (widget.editSale != null) {
      _loadEditData();
    }
  }

  void _loadEditData() {
    final sale = widget.editSale!;
    nameCtrl.text = sale.customerName;
    phoneCtrl.text = sale.phone;
    addressCtrl.text = sale.address;
    priceCtrl.text = _formatCurrency(sale.totalPrice);
    noteCtrl.text = sale.notes ?? '';
    _paymentMethod = sale.paymentMethod;
    _saleWarranty = sale.warranty;
    _isInstallment = sale.isInstallment;
    if (_isInstallment) {
      downPaymentCtrl.text = _formatCurrency(sale.downPayment);
      loanAmountCtrl.text = _formatCurrency(sale.loanAmount);
      bankCtrl.text = sale.bankName ?? '';
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
          type: 'PHONE',
          createdAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      
      _addProductToSale(product);
    }
  }

  void _calculateInstallment() {
    int total = _parseCurrency(priceCtrl.text);
    int down = _parseCurrency(downPaymentCtrl.text);
    int loan = total - down;
    loanAmountCtrl.text = _formatCurrency(loan > 0 ? loan : 0);
  }

  void _calculateTotal() {
    if (!_autoCalcTotal) return;
    int total = _selectedItems.fold(0, (sum, item) => sum + (item['isGift'] ? 0 : ((item['sellPrice'] as int) * (item['quantity'] as int))));
    priceCtrl.text = _formatCurrency(total);
    _calculateInstallment();
  }

  int _parseCurrency(String s) {
    return MoneyUtils.parseInputToVND(s);
  }

  String _formatCurrency(int amount) => MoneyUtils.formatVND(amount);

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
        FocusScope.of(context).requestFocus(_imeiFocusNodes[productId.toString()]);
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
        FocusScope.of(context).requestFocus(_imeiFocusNodes[productId.toString()]);
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
          if (product.type == 'PHONE' && product.status == 0 && product.quantity > 0) {
            product.status = 1; // Đánh dấu là available
            await db.updateProductStatus(product.id!, 1);
          }
          // Sync lên cloud
          await FirestoreService.updateProductCloud(product);
          debugPrint('Restored inventory for product: ${product.name}, new quantity: ${product.quantity}');
        }
      }
    }

    // 2. Xóa debt cũ nếu có
    if (oldSale.firestoreId != null) {
      final existingDebts = await db.getAllDebts();
      final linkedDebt = existingDebts.where((d) => d['linkedId'] == oldSale.firestoreId).firstOrNull;
      if (linkedDebt != null) {
        await db.deleteDebtByFirestoreId(linkedDebt['firestoreId']);
        // Mark as deleted in cloud instead of deleting
        await FirestoreService.addDebtCloud({...linkedDebt, 'deleted': true});
        debugPrint('Marked old debt as deleted for sale: ${oldSale.firestoreId}');
      }
    }

    // 3. Xóa expense records liên quan đến đơn hàng cũ (nếu có)
    // Note: Logic này có thể cần điều chỉnh tùy theo cách lưu expense
  }

  Future<void> _processSale() async {
    if (_isSaving) return;
    if (_selectedItems.isEmpty) { NotificationService.showSnackBar("VUI LÒNG CHỌN SẢN PHẨM", color: Colors.red); return; }
    if (nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty) { NotificationService.showSnackBar("NHẬP ĐỦ THÔNG TIN KHÁCH", color: Colors.red); return; }

    // Validate phone format
    final phoneError = UserService.validatePhone(phoneCtrl.text.trim());
    if (phoneError != null) { NotificationService.showSnackBar(phoneError, color: Colors.red); return; }

    setState(() => _isSaving = true);
    try {
      // XỬ LÝ EDIT MODE: Hoàn trả inventory và xóa debt cũ trước khi áp dụng thay đổi mới
      if (widget.editSale != null) {
        await _revertOldSaleChanges();
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final String uniqueId = widget.editSale?.firestoreId ?? "sale_${now}_${phoneCtrl.text}";
      String seller = FirebaseAuth.instance.currentUser?.email?.split('@').first.toUpperCase() ?? "NV";
      int totalPrice = _parseCurrency(priceCtrl.text);
      int paidAmount = _parseCurrency(downPaymentCtrl.text);
      if (_paymentMethod != "CÔNG NỢ" && _paymentMethod != "TRẢ GÓP (NH)" && paidAmount == 0) paidAmount = totalPrice;
      
      int totalCost = _selectedItems.fold(0, (sum, item) => sum + ((item['product'] as Product).cost * (item['quantity'] as int)));
      
      // Debug logging
      debugPrint("Sale debug - totalPrice: $totalPrice, totalCost: $totalCost, selectedItems: ${_selectedItems.length}");
      
      // Validate totals
      if (totalPrice <= 0) {
        NotificationService.showSnackBar("TỔNG TIỀN PHẢI LỚN HƠN 0", color: Colors.red);
        setState(() => _isSaving = false);
        return;
      }
      if (totalCost < 0) {
        NotificationService.showSnackBar("TỔNG GIÁ VỐN KHÔNG ĐƯỢC ÂM", color: Colors.red);
        setState(() => _isSaving = false);
        return;
      }
      
      final sale = SaleOrder(
        firestoreId: uniqueId, 
        customerName: nameCtrl.text.trim().toUpperCase(), 
        phone: phoneCtrl.text.trim(), 
        address: addressCtrl.text.trim().toUpperCase(), 
        productNames: _selectedItems.map((e) => "${(e['product'] as Product).name} x${e['quantity']}").join(', '), 
        productImeis: _selectedItems.map((e) {
          final product = e['product'] as Product;
          final quantity = e['quantity'] as int;
          final customImei = e['imei'] as String?;
          if (customImei != null && customImei.isNotEmpty) {
            return customImei;
          }
          // Logic cũ nếu không nhập IMEI tùy chọn
          if (product.type == 'PHONE') {
            return product.imei ?? "NO_IMEI";
          } else {
            return "PKx${quantity}";
          }
        }).join(', '), 
        totalPrice: totalPrice, 
        totalCost: _selectedItems.fold(0, (sum, item) => sum + ((item['product'] as Product).cost * (item['quantity'] as int))), 
        paymentMethod: _paymentMethod, 
        sellerName: seller, 
        soldAt: now, 
        isInstallment: _isInstallment, 
        downPayment: paidAmount, 
        loanAmount: _isInstallment ? _parseCurrency(loanAmountCtrl.text) : 0, 
        bankName: bankCtrl.text.toUpperCase(), 
        notes: noteCtrl.text, 
        warranty: _saleWarranty
      );
      
      if (_paymentMethod == "CÔNG NỢ" || (_paymentMethod != "TRẢ GÓP (NH)" && paidAmount < totalPrice)) {
        final debtData = {
          'personName': nameCtrl.text.trim().toUpperCase(), 
          'phone': phoneCtrl.text.trim(), 
          'totalAmount': totalPrice, 
          'paidAmount': paidAmount, 
          'type': "CUSTOMER_OWES", 
          'status': "ACTIVE", 
          'createdAt': now, 
          'note': "Nợ mua máy: ${sale.productNames}", 
          'linkedId': uniqueId
        };
        await db.insertDebt(debtData);
        // Sync debt lên cloud
        await FirestoreService.addDebtCloud(debtData);
      }
      
      // KIỂM TRA TỒN KHO REAL-TIME TRƯỚC KHI BÁN (tránh 2 nhân viên bán cùng 1 món)
      for (var item in _selectedItems) {
        final p = item['product'] as Product;
        final quantity = item['quantity'] as int;
        
        // Lấy số lượng tồn kho mới nhất từ database
        final currentStock = await db.getProductQuantityById(p.id!);
        if (currentStock < quantity) {
          NotificationService.showSnackBar(
            "⚠️ ${p.name} đã được bán bởi nhân viên khác! Còn lại: $currentStock", 
            color: Colors.red
          );
          // Refresh lại danh sách sản phẩm
          await _loadData();
          setState(() => _isSaving = false);
          return;
        }
      }
      
      for (var item in _selectedItems) {
        final p = item['product'] as Product;
        final quantity = item['quantity'] as int;
        
        // Chỉ kiểm tra IMEI cho sản phẩm PHONE nếu không nhập IMEI tùy chọn
        final customImei = item['imei'] as String?;
        if (p.type == 'PHONE' && (customImei == null || customImei.isEmpty) && (p.imei == null || p.imei!.isEmpty)) {
          NotificationService.showSnackBar("Không thể bán máy chưa có IMEI: ${p.name}", color: Colors.red);
          setState(() => _isSaving = false);
          return;
        }
        
        // Cập nhật trạng thái và số lượng
        if (p.type == 'PHONE') {
          // Phone: đánh dấu đã bán (status = 0)
          await db.updateProductStatus(p.id!, 0);
        }
        // Giảm số lượng cho cả PHONE và ACCESSORY
        await db.deductProductQuantity(p.id!, quantity);
        
        // Cập nhật local object
        p.quantity -= quantity;
        if (p.type == 'PHONE') {
          p.status = 0;
        }
        
        // Check for low inventory after stock reduction
        try {
          await NotificationService.checkAndNotifyLowInventory(p.firestoreId ?? p.id.toString(), p.name, p.quantity, 5);
        } catch (e) {
          debugPrint('Failed to check low inventory: $e');
        }
        
        // Sync lên cloud
        await FirestoreService.updateProductCloud(p);
      }
      await db.upsertSale(sale); await FirestoreService.addSale(sale);

      // Create customer if not exists
      final customerService = CustomerService();
      final existingCustomers = await customerService.getCustomers();
      final existing = existingCustomers.where((c) => c.phone == phoneCtrl.text.trim()).toList();
      if (existing.isEmpty) {
        final newCustomer = Customer(
          name: nameCtrl.text.trim().toUpperCase(),
          phone: phoneCtrl.text.trim(),
          address: addressCtrl.text.trim().toUpperCase(),
          createdAt: DateTime.now().millisecondsSinceEpoch,
        );
        await customerService.addCustomer(newCustomer);
      }
      
      // Trigger payment notification if payment is completed
      if (_paymentMethod != "CÔNG NỢ" && !_isInstallment) {
        try {
          await NotificationService.notifyPaymentCompleted(
            sale.firestoreId ?? 'SALE_${sale.soldAt}_${sale.sellerName}',
            totalPrice.toDouble(),
            _paymentMethod
          );
        } catch (e) {
          debugPrint('Failed to send payment notification: $e');
          // Don't fail the sale if notification fails
        }
      }
      
      // Notify other views about the new sale
      debugPrint('CreateSaleView: Emitting sales_changed event');
      EventBus().emit('sales_changed');
      
      NotificationService.showSnackBar("ĐÃ BÁN HÀNG THÀNH CÔNG!", color: Colors.green);
      if (mounted) Navigator.pop(context, true);
    } catch (e) { 
      setState(() => _isSaving = false); 
      NotificationService.showSnackBar("LỖI KHI LƯU ĐƠN BÁN: ${e.toString()}", color: Colors.red);
      debugPrint("Sale save error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text("TẠO ĐƠN BÁN HÀNG"),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
        ),
        body: const Center(
          child: Text(
            "Bạn không có quyền truy cập tính năng này",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Tooltip(message: widget.editSale != null ? "Chỉnh sửa thông tin đơn bán hàng" : "Chọn sản phẩm, nhập thông tin khách và hoàn tất đơn bán.", child: Text(widget.editSale != null ? "SỬA ĐƠN BÁN HÀNG" : "TẠO ĐƠN BÁN HÀNG", style: AppTextStyles.headline6.copyWith(color: AppColors.onPrimary))), 
        backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary,
        automaticallyImplyLeading: true,
      ),
      body: _isLoading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionTitle("1. CHỌN SẢN PHẨM TRONG KHO"),
          DebouncedSearchField(controller: searchProdCtrl, hint: "Tìm máy hoặc IMEI...", onSearch: (v) => setState(() => _filteredInStock = _allInStock.where((p) => p.name.contains(v.toUpperCase()) || (p.imei ?? "").contains(v)).toList())),
          
          // Hiển thị hướng dẫn nếu kho trống
          if (_allInStock.isEmpty) _buildEmptyStockGuidance(),
          
          if (searchProdCtrl.text.isNotEmpty) _buildSearchResults(),
          _buildSelectedItemsList(),
          const SizedBox(height: 20),
          _sectionTitle("2. THÔNG TIN KHÁCH HÀNG"),
          Row(
            children: [
              Expanded(
                child: ValidatedTextField(controller: nameCtrl, label: "TÊN KHÁCH HÀNG", icon: Icons.person, uppercase: true),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.search),
                onPressed: _selectCustomer,
                tooltip: 'Chọn khách hàng',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  foregroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
          _buildCustomerSuggestions(),
          Row(
            children: [
              Expanded(
                child: ValidatedTextField(controller: phoneCtrl, label: "SỐ ĐIỆN THOẠI", icon: Icons.phone, keyboardType: TextInputType.phone),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: 'Thêm nhanh khách hàng vào danh sách',
                child: IconButton(
                  onPressed: (nameCtrl.text.trim().isNotEmpty && phoneCtrl.text.trim().isNotEmpty)
                      ? _addCustomerQuick
                      : null,
                  icon: Icon(
                    Icons.person_add,
                    color: (nameCtrl.text.trim().isNotEmpty && phoneCtrl.text.trim().isNotEmpty)
                        ? AppColors.success
                        : AppColors.grey600,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: (nameCtrl.text.trim().isNotEmpty && phoneCtrl.text.trim().isNotEmpty)
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.grey600.withOpacity(0.1),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionTitle("3. THANH TOÁN & BẢO HÀNH"),
          _buildPaymentSection(),
          const SizedBox(height: 30),
          SizedBox(width: double.infinity, height: 55, child: ElevatedButton(onPressed: (_isSaving || _selectedItems.isEmpty) ? null : _processSale, style: AppButtonStyles.successElevatedButtonStyle, child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : Text(_selectedItems.isEmpty ? "CHƯA CHỌN SẢN PHẨM" : "HOÀN TẤT ĐƠN HÀNG", style: AppTextStyles.button.copyWith(color: AppColors.onSuccess)))),
        ]),
      ),
    );
  }

  Widget _buildPaymentSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(15), border: Border.all(color: AppColors.outline)),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("TỔNG TIỀN:", style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)), Row(children: [IconButton(icon: Icon(_autoCalcTotal ? Icons.lock_outline : Icons.edit, size: 18, color: AppColors.primary), onPressed: () => setState(() => _autoCalcTotal = !_autoCalcTotal)), SizedBox(width: 150, child: CurrencyTextField(controller: priceCtrl, label: "", enabled: !_autoCalcTotal, autoMultiply1000: false, onChanged: (_) { _calculateInstallment(); })), Text(" Đ", style: AppTextStyles.body1.copyWith(color: AppColors.error, fontWeight: FontWeight.bold))])]),
        const SizedBox(height: 15),
        Wrap(spacing: 8, children: ["TIỀN MẶT", "CHUYỂN KHOẢN", "CÔNG NỢ", "TRẢ GÓP (NH)"].map((e) => ChoiceChip(label: Text(e, style: AppTextStyles.caption), selected: _paymentMethod == e, onSelected: (v) => setState(() { _paymentMethod = e; _isInstallment = (e == "TRẢ GÓP (NH)"); }))).toList()),
        const Divider(height: 30),
        _moneyInput(downPaymentCtrl, _isInstallment ? "KHÁCH TRẢ TRƯỚC (k)" : "SỐ TIỀN THU THỰC TẾ (k)", AppColors.secondary),
        if (_isInstallment) ...[const SizedBox(height: 10), _moneyInput(loanAmountCtrl, "NGÂN HÀNG CHO VAY", AppColors.grey600, enabled: false), const SizedBox(height: 10), ValidatedTextField(controller: bankCtrl, label: "TÊN CÔNG TY TÀI CHÍNH", icon: Icons.account_balance, uppercase: true), const SizedBox(height: 8), Wrap(spacing: 8, children: ["FE", "HOME", "MIRAE", "HD", "F83", "T86"].map((b) => ActionChip(label: Text(b, style: AppTextStyles.caption), onPressed: () => setState(() => bankCtrl.text = b))).toList())],
        const Divider(height: 30),
        // KHÔI PHỤC TAB BẢO HÀNH: Cho phép chọn bảo hành bất kể trạng thái nợ
        DropdownButtonFormField<String>(
          initialValue: _saleWarranty, 
          decoration: const InputDecoration(labelText: "CHỌN THỜI GIAN BẢO HÀNH", prefixIcon: Icon(Icons.verified_user)), 
          items: ["KO BH", "1 THÁNG", "3 THÁNG", "6 THÁNG", "12 THÁNG"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(), 
          onChanged: (v) => setState(() => _saleWarranty = v ?? "KO BH")
        )
      ]),
    );
  }

  Widget _moneyInput(TextEditingController ctrl, String label, Color color, {bool enabled = true, Function()? onChanged}) {
    return CurrencyTextField(controller: ctrl, label: label, icon: Icons.money, enabled: enabled, onChanged: (_) { _calculateInstallment(); if (onChanged != null) onChanged(); });
  }

  Widget _sectionTitle(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(t, style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)));

  Widget _buildSearchResults() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 250), 
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: AppColors.shadow, blurRadius: 10)]), 
      child: ListView.builder(shrinkWrap: true, itemCount: _filteredInStock.length, itemBuilder: (ctx, i) { 
        final p = _filteredInStock[i]; 
        return ListTile(
          title: Text(p.name, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)), 
          subtitle: Text("IMEI: ${p.imei ?? 'PK'} - Giá: ${MoneyUtils.formatVND(p.price)}"), 
          // HIỂN THỊ SỐ LƯỢNG TỒN TRONG LIST CHỌN
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(p.quantity > 0 ? Icons.add_circle : Icons.warning, color: p.quantity > 0 ? AppColors.success : AppColors.error),
              Text("Tồn: ${p.quantity}", style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.bold, color: p.quantity > 0 ? AppColors.warning : AppColors.error)),
            ],
          ),
          onTap: () {
            if (p.quantity == 0) {
              NotificationService.showSnackBar(
                "Sản phẩm '${p.name}' chưa có trong kho!\nVui lòng tạo nhà cung cấp và nhập kho trước khi bán.",
                color: AppColors.error
              );
              return;
            }
            _addItem(p);
          }
        ); 
      })
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
                      icon: Icon(Icons.delete, color: AppColors.error),
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
                Text("Giá bán: ${MoneyUtils.formatVND(item['sellPrice'])}"),
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
                          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
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
                        controller: _imeiControllers[product.id.toString()] ?? TextEditingController(text: item['imei'] ?? ''),
                        focusNode: _imeiFocusNodes[product.id.toString()],
                        onChanged: (value) {
                          setState(() {
                            item['imei'] = value.trim();
                          });
                        },
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    return SizedBox(height: 40, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: _suggestCustomers.length, itemBuilder: (ctx, i) => Padding(padding: const EdgeInsets.only(right: 8), child: ActionChip(label: Text(_suggestCustomers[i]['customerName']), onPressed: () { nameCtrl.text = _suggestCustomers[i]['customerName']; phoneCtrl.text = _suggestCustomers[i]['phone']; setState(() => _suggestCustomers = []); }))));
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
              Icon(Icons.inventory_2_outlined, color: AppColors.warning, size: 28),
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
                      MaterialPageRoute(builder: (_) => const StockInView()),
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
  State<CustomerSelectionDialog> createState() => _CustomerSelectionDialogState();
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
                const Text(
                  'Chọn khách hàng',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                              customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                              style: TextStyle(
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
                                  customer.address!,
                                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
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
