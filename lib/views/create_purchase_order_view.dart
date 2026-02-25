import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/money_utils.dart';
import '../theme/app_text_styles.dart';
import '../data/db_helper.dart';
import '../models/purchase_order_model.dart';
import '../models/debt_model.dart';
import '../models/shop_settings_model.dart';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../services/supplier_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/payment_intent_service.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../models/payment_intent_model.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';

class CreatePurchaseOrderView extends StatefulWidget {
  const CreatePurchaseOrderView({super.key});

  @override
  State<CreatePurchaseOrderView> createState() => _CreatePurchaseOrderViewState();
}

class _CreatePurchaseOrderViewState extends State<CreatePurchaseOrderView> {
  final db = DBHelper();
  final supplierService = SupplierService();
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final supplierNameCtrl = TextEditingController();
  final supplierPhoneCtrl = TextEditingController();
  final supplierAddressCtrl = TextEditingController();
  final notesCtrl = TextEditingController();

  // Data
  List<Map<String, dynamic>> _suppliers = [];
  final List<PurchaseItem> _items = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String _currentUserName = '';
  String _paymentMethod = 'TIỀN MẶT';

  // Shop settings for dynamic terminology
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);
  
  // Multi-industry getters
  String get _businessType => _shopSettings?.businessType ?? 'electronics';
  bool get _isFashion => _businessType == 'fashion';
  bool get _isElectronics => _businessType == 'electronics';
  bool get _enableSerial => _shopSettings?.enableSerial ?? true;

  // Item form
  final itemNameCtrl = TextEditingController();
  final itemImeiCtrl = TextEditingController();
  final itemQuantityCtrl = TextEditingController();
  final itemCostCtrl = TextEditingController();
  final itemPriceCtrl = TextEditingController();
  final itemColorCtrl = TextEditingController();
  final itemCapacityCtrl = TextEditingController();
  String itemCondition = 'Mới';

  @override
  void initState() {
    super.initState();
    _loadShopSettings();
    _loadData();
    itemCostCtrl.addListener(_formatCost);
    itemPriceCtrl.addListener(_formatPrice);
  }

  Future<void> _loadShopSettings() async {
    try {
      final settings = await CategoryService().getShopSettings();
      if (mounted) {
        setState(() => _shopSettings = settings);
      }
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
    }
  }

  Future<void> _loadData() async {
    try {
      final suppliers = await supplierService.getSuppliers();
      final user = FirebaseAuth.instance.currentUser;
      final userData = await UserService.getUserInfo(user?.uid ?? '');

      setState(() {
        _suppliers = suppliers.map((s) => s.toMap()).toList();
        _currentUserName = userData['name'] ?? 'Unknown';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Lỗi load data: $e");
      setState(() => _isLoading = false);
    }
  }

  void _formatCost() {
    final text = itemCostCtrl.text;
    if (text.isEmpty) return;
    final clean = text.replaceAll(',', '').split('.').first;
    final num = int.tryParse(clean);
    if (num != null) {
      final formatted = MoneyUtils.formatVND(MoneyUtils.inputToVND(num));
      if (formatted != text) {
        itemCostCtrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
  }

  void _formatPrice() {
    final text = itemPriceCtrl.text;
    if (text.isEmpty) return;
    final clean = text.replaceAll(',', '').split('.').first;
    final num = int.tryParse(clean);
    if (num != null) {
      final formatted = MoneyUtils.formatVND(MoneyUtils.inputToVND(num));
      if (formatted != text) {
        itemPriceCtrl.value = TextEditingValue(
          text: formatted,
          selection: TextSelection.collapsed(offset: formatted.length),
        );
      }
    }
  }

  void _addItem() {
    if (itemNameCtrl.text.isEmpty || itemQuantityCtrl.text.isEmpty ||
        itemCostCtrl.text.isEmpty || itemPriceCtrl.text.isEmpty) {
      NotificationService.showSnackBar("Vui lòng nhập đầy đủ thông tin ${_terms.productLabel.toLowerCase()}!", color: Colors.red);
      return;
    }

    final item = PurchaseItem(
      productName: itemNameCtrl.text.trim(),
      imei: itemImeiCtrl.text.isNotEmpty ? itemImeiCtrl.text.trim() : null,
      quantity: int.tryParse(itemQuantityCtrl.text) ?? 0,
      unitCost: int.tryParse(itemCostCtrl.text) ?? 0,
      unitPrice: int.tryParse(itemPriceCtrl.text) ?? 0,
      color: itemColorCtrl.text.isNotEmpty ? itemColorCtrl.text.trim() : null,
      capacity: itemCapacityCtrl.text.isNotEmpty ? itemCapacityCtrl.text.trim() : null,
      condition: itemCondition,
    );

    setState(() {
      _items.add(item);
      _clearItemForm();
    });
  }

  void _clearItemForm() {
    itemNameCtrl.clear();
    itemImeiCtrl.clear();
    itemQuantityCtrl.clear();
    itemCostCtrl.clear();
    itemPriceCtrl.clear();
    itemColorCtrl.clear();
    itemCapacityCtrl.clear();
    itemCondition = 'Mới';
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _savePurchaseOrder() async {
    // Finalize currency fields trước khi xử lý
    CurrencyTextField.finalizeAll();
    
    if (!_formKey.currentState!.validate()) return;
    if (_items.isEmpty) {
      NotificationService.showSnackBar("Vui lòng thêm ít nhất 1 ${_terms.productLabel.toLowerCase()}!", color: Colors.red);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final orderCode = await db.generateNextOrderCode();
      final order = PurchaseOrder(
        orderCode: orderCode,
        supplierName: supplierNameCtrl.text.trim(),
        supplierPhone: supplierPhoneCtrl.text.trim(),
        supplierAddress: supplierAddressCtrl.text.isNotEmpty ? supplierAddressCtrl.text.trim() : null,
        items: _items,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        createdBy: _currentUserName,
        notes: notesCtrl.text.isNotEmpty ? notesCtrl.text.trim() : null,
        paymentMethod: _paymentMethod,
      );

      order.calculateTotals();

      // Save to local DB
      await db.insertPurchaseOrder(order);

      // If payment method is debt, create a debt record - ĐƠN GIẢN
      if (_paymentMethod == 'CÔNG NỢ') {
        final supplierData = _suppliers.firstWhere((s) => s['name'] == supplierNameCtrl.text.trim(), orElse: () => {});

        final debt = Debt(
          personName: supplierNameCtrl.text.trim(),
          phone: supplierPhoneCtrl.text.trim(),
          totalAmount: order.totalCost,
          paidAmount: 0,
          type: "SHOP_OWES",
          status: "ACTIVE",
          createdAt: DateTime.now().millisecondsSinceEpoch,
          note: 'Đơn nhập hàng ${order.orderCode}',
          linkedId: order.orderCode,
        );

        // Set firestoreId to prevent duplicates
        debt.firestoreId = "debt_${debt.createdAt}_${supplierPhoneCtrl.text.trim()}";

        debugPrint('Creating purchase order debt: $debt');
        await db.upsertDebt(debt);
        debugPrint('Purchase order debt created successfully');

        // Queue sync to Firestore via SyncOrchestrator
        final debtId = await db.getDebtIdByFirestoreId(debt.firestoreId!);
        if (debtId != null) {
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.debt,
            entityId: debtId,
            firestoreId: debt.firestoreId,
            operation: SyncOperation.create,
            data: debt.toMap(),
          );
        }

        // Tạo PaymentIntent cho việc trả nợ NCC sau này (CHỜ CHI)
        final user = FirebaseAuth.instance.currentUser;
        final intent = PaymentIntent(
          id: 'pi_purchase_debt_${DateTime.now().millisecondsSinceEpoch}_${order.orderCode}',
          type: PaymentIntentType.supplierDebt,
          amount: order.totalCost,
          description: 'Trả nợ NCC: ${supplierNameCtrl.text.trim()} - Đơn ${order.orderCode}',
          referenceId: debt.firestoreId,
          referenceType: 'purchase_debt',
          personName: supplierNameCtrl.text.trim(),
          personPhone: supplierPhoneCtrl.text.trim(),
          createdBy: user?.uid ?? 'unknown',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          metadata: {
            'orderCode': order.orderCode,
            'orderFirestoreId': order.firestoreId,
            'debtId': debtId,
            'debtFirestoreId': debt.firestoreId,
            'debtType': 'SHOP_OWES',
            'supplierName': supplierNameCtrl.text.trim(),
          },
        );
        await PaymentIntentService.createIntent(intent);
        debugPrint('💳 Created PaymentIntent for purchase debt: ${intent.id}');

        // Notify UI update
        EventBus().emit('debts_changed');
      } else {
        // Thanh toán tiền mặt/chuyển khoản → Tạo PaymentIntent để xác nhận thanh toán (CHỜ CHI)
        final user = FirebaseAuth.instance.currentUser;
        final intent = PaymentIntent(
          id: 'pi_purchase_${DateTime.now().millisecondsSinceEpoch}_${order.orderCode}',
          type: PaymentIntentType.supplierDebt,
          amount: order.totalCost,
          description: 'Chi nhập hàng: ${supplierNameCtrl.text.trim()} - Đơn ${order.orderCode}',
          referenceId: order.orderCode,
          referenceType: 'purchase_order',
          personName: supplierNameCtrl.text.trim(),
          personPhone: supplierPhoneCtrl.text.trim(),
          createdBy: user?.uid ?? 'unknown',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          metadata: {
            'orderCode': order.orderCode,
            'orderFirestoreId': order.firestoreId,
            'supplierName': supplierNameCtrl.text.trim(),
            'paymentMethod': _paymentMethod,
          },
        );
        await PaymentIntentService.createIntent(intent);
        debugPrint('💳 Created PaymentIntent for purchase payment: ${intent.id}');
      }
      // NOTE: Direct insertExpense for PURCHASE BLOCKED
      // Payment for purchase orders must go through PaymentIntentService
      // The order is saved but payment execution requires UnifiedPaymentPage

      // Generate firestoreId and save to local DB
      final firestoreId = order.firestoreId ?? "po_${order.createdAt}_${order.orderCode}";
      order.firestoreId = firestoreId;
      await db.updatePurchaseOrder(order);

      // Queue sync via SyncOrchestrator
      final orderId = await db.getPurchaseOrderIdByFirestoreId(firestoreId);
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.purchaseOrder,
        entityId: orderId ?? 0,
        firestoreId: firestoreId,
        operation: SyncOperation.create,
        data: order.toMap(),
      );

      // CẬP NHẬT INVENTORY TRONG LOCAL DB
      // await _updateLocalInventoryFromPurchaseOrder(order);

      // THÊM CHI PHÍ NHẬP HÀNG VÀO TRANG CHI PHÍ
      await _addPurchaseExpense(order);

      if (mounted) {
        Navigator.pop(context);
        NotificationService.showSnackBar("Đã tạo đơn nhập hàng: ${order.orderCode}", color: Colors.green);
      }
    } catch (e) {
      debugPrint("Lỗi tạo đơn nhập: $e");
      NotificationService.showSnackBar("Lỗi tạo đơn nhập hàng!", color: Colors.red);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Widget _buildItemForm() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("THÊM ${_terms.productLabel.toUpperCase()}", style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ValidatedTextField(
              controller: itemNameCtrl,
              label: "TÊN ${_terms.productLabel.toUpperCase()}",
              icon: Icons.inventory,
              required: true,
              uppercase: true,
            ),
            const SizedBox(height: 8),
            // IMEI/Serial - only for electronics shops
            if (_enableSerial)
              ValidatedTextField(
                controller: itemImeiCtrl,
                label: _terms.specialField1Label.toUpperCase(),
                icon: Icons.qr_code,
                uppercase: true,
              ),
            if (_enableSerial) const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: itemQuantityCtrl,
                    decoration: const InputDecoration(labelText: "Số lượng *", border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: (v) => v?.isEmpty ?? true ? "Bắt buộc" : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CurrencyTextField(
                    controller: itemCostCtrl,
                    label: "ĐƠN GIÁ NHẬP",
                    icon: Icons.attach_money,
                    required: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: CurrencyTextField(
                    controller: itemPriceCtrl,
                    label: "ĐƠN GIÁ BÁN",
                    icon: Icons.sell,
                    required: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: itemCondition,
                    decoration: const InputDecoration(labelText: "Tình trạng", border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: "Mới", child: Text("Mới")),
                      DropdownMenuItem(value: "Cũ", child: Text("Cũ")),
                      DropdownMenuItem(value: "Hỏng", child: Text("Hỏng")),
                    ],
                    onChanged: (v) => setState(() => itemCondition = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ValidatedTextField(
                    controller: itemColorCtrl,
                    label: "MÀU SẮC",
                    icon: Icons.color_lens,
                    uppercase: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ValidatedTextField(
                    controller: itemCapacityCtrl,
                    label: _isFashion ? "SIZE" : "DUNG LƯỢNG",
                    icon: _isFashion ? Icons.straighten : Icons.memory,
                    uppercase: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: Text("THÊM ${_terms.productLabel.toUpperCase()}"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemsList() {
    if (_items.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text("DANH SÁCH ${_terms.productLabel.toUpperCase()}", style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold)),
          ),
          ..._items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.productName ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _removeItem(index),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text("Giá nhập: ${MoneyUtils.formatVND(item.unitCost)}đ"),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text("Số lượng: "),
                        IconButton(
                          icon: const Icon(Icons.remove, size: 20),
                          onPressed: () {
                            if (item.quantity > 1) {
                              setState(() {
                                _items[index] = item.copyWith(quantity: item.quantity - 1);
                              });
                            }
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        SizedBox(
                          width: 50,
                          child: TextFormField(
                            initialValue: item.quantity.toString(),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            onChanged: (value) {
                              final newQuantity = int.tryParse(value) ?? 1;
                              if (newQuantity > 0) {
                                setState(() {
                                  _items[index] = item.copyWith(quantity: newQuantity);
                                });
                              }
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
                              _items[index] = item.copyWith(quantity: item.quantity + 1);
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
                        Text("${_terms.specialField1Label}: "),
                        Expanded(
                          child: TextFormField(
                            initialValue: item.imei ?? '',
                            onChanged: (value) {
                              setState(() {
                                _items[index] = item.copyWith(imei: value.trim().isNotEmpty ? value.trim() : null);
                              });
                            },
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              hintText: "Nhập ${_terms.specialField1Label.toLowerCase()} (tùy chọn)",
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Thành tiền: ${MoneyUtils.formatVND(item.quantity * item.unitCost)}đ",
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              "Tổng: ${_items.fold(0, (sum, item) => sum + item.quantity)} ${_terms.productLabel.toLowerCase()} - ${MoneyUtils.formatVND(_items.fold(0, (sum, item) => sum + (item.unitCost * item.quantity)))}đ",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline3.fontSize),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
        title: const Text("TẠO ĐƠN NHẬP HÀNG", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          children: [
            Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("THÔNG TIN NHÀ CUNG CẤP", style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    ValidatedTextField(
                      controller: supplierNameCtrl,
                      label: "TÊN NHÀ CUNG CẤP",
                      icon: Icons.business,
                      required: true,
                      uppercase: true,
                    ),
                    const SizedBox(height: 8),
                    ValidatedTextField(
                      controller: supplierPhoneCtrl,
                      label: "SỐ DIEN_THOAI",
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                      uppercase: true,
                    ),
                    const SizedBox(height: 8),
                    ValidatedTextField(
                      controller: supplierAddressCtrl,
                      label: "ĐỊA CHỈ",
                      icon: Icons.location_on,
                      uppercase: true,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: notesCtrl,
                      decoration: const InputDecoration(labelText: "Ghi chú", border: OutlineInputBorder()),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _paymentMethod,
                      decoration: const InputDecoration(labelText: "Phương thức thanh toán", border: OutlineInputBorder()),
                      items: const [
                        DropdownMenuItem(value: "TIỀN MẶT", child: Text("TIỀN MẶT")),
                        DropdownMenuItem(value: "CHUYỂN KHOẢN", child: Text("CHUYỂN KHOẢN")),
                        DropdownMenuItem(value: "CÔNG NỢ", child: Text("CÔNG NỢ")),
                      ],
                      onChanged: (v) => setState(() => _paymentMethod = v!),
                    ),
                  ],
                ),
              ),
            ),
            _buildItemForm(),
            _buildItemsList(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: _isSaving ? null : _savePurchaseOrder,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: _isSaving
            ? const CircularProgressIndicator(color: Colors.white)
            : Text("LƯU ĐƠN NHẬP", style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  // THÊM CHI PHÍ NHẬP HÀNG VÀO TRANG CHI PHÍ
  // NOTE: Method BLOCKED - must use PaymentIntentService for purchase expenses
  Future<void> _addPurchaseExpense(PurchaseOrder order) async {
    // BLOCKED: Direct insertExpense for purchases must go through PaymentIntent flow
    // Use PaymentIntentService.createIntent() -> UnifiedPaymentPage instead
    debugPrint('⛔ _addPurchaseExpense BLOCKED - Use PaymentIntentService for purchase payments');
    throw UnsupportedError(
      '_addPurchaseExpense blocked. Use PaymentIntentService.createIntent() -> UnifiedPaymentPage'
    );
  }

  // Future<void> _updateLocalInventoryFromPurchaseOrder(PurchaseOrder order) async {
  //   try {
  //     for (final item in order.items) {
  //       // Tìm sản phẩm trong local DB
  //       final existingProducts = await db.rawQuery(
  //         'SELECT * FROM products WHERE name = ? AND color = ? AND capacity = ? AND condition = ?',
  //         [item.productName, item.color, item.capacity, item.condition],
  //       );

  //       if (existingProducts.isNotEmpty) {
  //         // Sản phẩm đã tồn tại - cập nhật số lượng và chi phí trung bình
  //         final existingProduct = Product.fromMap(existingProducts.first);
  //         final currentQuantity = existingProduct.quantity;
  //         final currentCost = existingProduct.cost;
  //         final newQuantity = currentQuantity + item.quantity;

  //         // Tính chi phí trung bình
  //         final totalCurrentValue = currentQuantity * currentCost;
  //         final totalNewValue = item.quantity * item.unitCost;
  //         final averageCost = ((totalCurrentValue + totalNewValue) / newQuantity).round();

  //         existingProduct.quantity = newQuantity;
  //         existingProduct.cost = averageCost;
  //         existingProduct.price = item.unitPrice; // Cập nhật giá bán

  //         await db.upsertProduct(existingProduct.toMap());
  //         debugPrint('Local: Cập nhật sản phẩm ${item.productName}, SL: $currentQuantity -> $newQuantity, Chi phí TB: $averageCost');
  //       } else {
  //         // Sản phẩm chưa tồn tại - tạo mới
  //         final newProduct = Product(
  //           name: item.productName ?? '',
  //           brand: 'KHÁC',
  //           imei: item.imei,
  //           cost: item.unitCost,
  //           price: item.unitPrice,
  //           condition: item.condition,
  //           status: 1,
  //           description: 'Nhập từ đơn: ${order.orderCode}',
  //           createdAt: DateTime.now().millisecondsSinceEpoch,
  //           supplier: order.supplierName,
  //           type: 'DIEN_THOAI',
  //           quantity: item.quantity,
  //           color: item.color,
  //           capacity: item.capacity,
  //           isSynced: false,
  //         );

  //         await db.upsertProduct(newProduct.toMap());
  //         debugPrint('Local: Tạo sản phẩm mới ${item.productName}, SL: ${item.quantity}, Chi phí: ${item.unitCost}');
  //       }
  //     }
  //   } catch (e) {
  //     debugPrint('Lỗi cập nhật local inventory: $e');
  //     // Không throw error để không làm fail purchase order
  //   }
  // }

  @override
  void dispose() {
    itemCostCtrl.removeListener(_formatCost);
    itemPriceCtrl.removeListener(_formatPrice);
    super.dispose();
  }
}
