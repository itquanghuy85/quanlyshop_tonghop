import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/payment_intent_model.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/product_model.dart';
import '../services/payment_intent_service.dart';
import '../services/user_service.dart';
import 'package:uuid/uuid.dart';

/// Test screen để test PaymentIntent + Dashboard với real data
/// 
/// KỊCH BẢN TEST ĐẦY ĐỦ:
/// 1. TẠO SALES: Doanh thu bán hàng → THU HÔM NAY
/// 2. TẠO REPAIRS: Doanh thu sửa chữa → THU HÔM NAY
/// 3. TẠO DEBTS + PAYMENTINTENT: Công nợ chờ thanh toán
/// 
/// DASHBOARD SẼ HIỂN THỊ:
/// - THU HÔM NAY = salesIncome + repairsIncome (KHÔNG cộng debtCollected vì accrual basis)
/// - debtCollected = thu nợ chỉ ảnh hưởng quỹ, không ảnh hưởng doanh thu
class PaymentIntentTestView extends StatefulWidget {
  const PaymentIntentTestView({super.key});

  @override
  State<PaymentIntentTestView> createState() => _PaymentIntentTestViewState();
}

class _PaymentIntentTestViewState extends State<PaymentIntentTestView> {
  final DBHelper _db = DBHelper();
  final Uuid _uuid = const Uuid();

  List<String> _logs = [];
  bool _isRunning = false;
  List<PaymentIntent> _createdIntents = [];

  // Stats
  int _totalIncome = 0; // CHỜ THU
  int _totalExpense = 0; // CHỜ CHI
  int _incomeCount = 0;
  int _expenseCount = 0;
  
  // Dashboard preview
  int _salesIncome = 0;
  int _repairsIncome = 0;
  int _salesCount = 0;
  int _repairsCount = 0;
  int _expensesTotal = 0;
  int _expensesCount = 0;

  void _log(String message) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $message');
    });
    debugPrint('TEST: $message');
  }

  Future<void> _runAllTests() async {
    setState(() {
      _isRunning = true;
      _logs.clear();
      _createdIntents.clear();
      _totalIncome = 0;
      _totalExpense = 0;
      _incomeCount = 0;
      _expenseCount = 0;
      _salesIncome = 0;
      _repairsIncome = 0;
      _salesCount = 0;
      _repairsCount = 0;
      _expensesTotal = 0;
      _expensesCount = 0;
    });

    try {
      _log('🚀 Bắt đầu tạo data test ĐẦY ĐỦ');
      _log('─' * 50);

      // Clear old test data
      await _clearOldTestData();

      // === PHẦN 0: TẠO MASTER DATA ===
      _log('');
      _log('🏢 PHẦN 0: TẠO MASTER DATA');
      _log('─' * 50);
      await _createCustomers(); // 3 khách hàng
      await _createSuppliers(); // 2 nhà cung cấp
      await _createRepairPartners(); // 2 đối tác sửa chữa
      await _createProducts(); // 3 sản phẩm trong kho
      await _createRepairParts(); // 3 linh kiện sửa chữa

      // === PHẦN 1: TẠO DOANH THU THẬT (ảnh hưởng Dashboard) ===
      _log('');
      _log('📊 PHẦN 1: TẠO DOANH THU (Dashboard THU HÔM NAY)');
      _log('─' * 50);
      await _createSaleOrder1(); // Bán iPhone - 15M - thanh toán đủ
      await _createSaleOrder2(); // Bán phụ kiện - 500k - thanh toán đủ
      await _createInstallmentSale1(); // Trả góp NH1 - 20M
      await _createInstallmentSale2(); // Trả góp 2 NH - 25M
      await _createRepair1(); // Sửa thay pin - 350k
      await _createRepair2(); // Sửa thay màn - 2.5M

      // === PHẦN 1.5: TẠO CHI PHÍ (ảnh hưởng Chốt quỹ CHI) ===
      _log('');
      _log('💸 PHẦN 1.5: TẠO CHI PHÍ (Chốt quỹ CHI HÔM NAY)');
      _log('─' * 50);
      await _createExpense1(); // Tiền điện - 500k
      await _createExpense2(); // Tiền ship - 300k
      
      // === PHẦN 2: TẠO CÔNG NỢ + PAYMENTINTENT (chờ thanh toán) ===
      _log('');
      _log('💳 PHẦN 2: TẠO CÔNG NỢ + PAYMENTINTENT');
      _log('─' * 50);
      await _test1_CreateSaleDebt(); // 500k - THU (customerDebtCollection)
      await _test2_CreatePurchaseDebt(); // 2M - CHI (supplierDebt)
      await _test3_CreateStockInDebt(); // 1.5M - CHI (inventoryPurchase)
      await _test4_CreatePartsDebt(); // 800k - CHI (partsStockIn)
      await _test5_CreateRepairDelivery(); // 1M - THU (repairService)
      
      // === PHẦN 3: TẠO NỢ NCC VÀ ĐỐI TÁC ===
      _log('');
      _log('🏦 PHẦN 3: TẠO NỢ NCC VÀ ĐỐI TÁC');
      _log('─' * 50);
      await _createSupplierDebt(); // Nợ NCC - 3M
      await _createPartnerDebt(); // Nợ đối tác - 1.5M

      // Summary
      _log('');
      _log('─' * 50);
      _log('📊 KẾT QUẢ TẠO DATA:');
      _log('');
      _log('🟢 DASHBOARD (THU HÔM NAY từ doanh thu):');
      _log('   Bán hàng: $_salesCount đơn = ${_formatCurrency(_salesIncome)}');
      _log('   Sửa chữa: $_repairsCount đơn = ${_formatCurrency(_repairsIncome)}');
      _log('   → THU HÔM NAY = ${_formatCurrency(_salesIncome + _repairsIncome)}');
      _log('');
      _log('� CHI PHÍ (CHI HÔM NAY):');
      _log('   Chi phí: $_expensesCount khoản = ${_formatCurrency(_expensesTotal)}');
      _log('');
      _log('🔵 THANH TOÁN CHỜ (PaymentIntents):');
      _log('   CHỜ THU: $_incomeCount items = ${_formatCurrency(_totalIncome)}');
      _log('   CHỜ CHI: $_expenseCount items = ${_formatCurrency(_totalExpense)}');
      _log('   TỔNG: ${_createdIntents.length} PaymentIntents');
      _log('─' * 50);
      _log('');
      _log('📋 KỊCH BẢN THANH TOÁN:');
      _log('─' * 50);
      _log('🟢 CHỜ THU (1.5M tổng):');
      _log('   1️⃣ Thu nợ KH bán hàng: 500k → TIỀN MẶT');
      _log('   2️⃣ Thu nợ KH sửa chữa: 1M → CHUYỂN KHOẢN');
      _log('');
      _log('🔴 CHỜ CHI (4.3M tổng):');
      _log('   3️⃣ Trả nợ NCC nhập hàng: 2M → CHUYỂN KHOẢN');
      _log('   4️⃣ Trả nợ NCC nhập kho: 1.5M → TIỀN MẶT');
      _log('   5️⃣ Trả nợ NCC linh kiện: 800k → TIỀN MẶT');
      _log('─' * 50);
      _log('');
      _log('📦 DATA ĐÃ TẠO:');
      _log('   • 3 Khách hàng (Quản lý KH)');
      _log('   • 2 Nhà cung cấp (NCC)');
      _log('   • 2 Đối tác sửa chữa');
      _log('   • 3 Sản phẩm (Kho)');
      _log('   • 3 Linh kiện sửa chữa');
      _log('   • 2 Đơn trả góp (1NH + 2NH)');
      _log('   • Nợ NCC: 3M, Nợ đối tác: 1.5M');
      _log('─' * 50);
      _log('✅ Hoàn thành! Kiểm tra các màn hình.');
    } catch (e, stack) {
      _log('❌ LỖI: $e');
      _log('Stack: $stack');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _clearOldTestData() async {
    _log('🧹 Xóa data test cũ...');

    final db = await _db.database;
    final shopId = await UserService.getCurrentShopId();
    final firestore = FirebaseFirestore.instance;
    
    // ===== XÓA TẤT CẢ TEST DATA TỪ FIRESTORE TRƯỚC =====
    _log('   🔥 Xóa ALL test data từ Firestore...');
    
    // Helper function để xóa test docs từ một collection
    Future<int> deleteTestDocsFromCollection(String collectionName, List<String> testFields) async {
      try {
        final ref = firestore.collection(collectionName);
        final snapshot = await ref.where('shopId', isEqualTo: shopId).get();
        
        int deleted = 0;
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final docId = doc.id;
          
          // Kiểm tra nếu là test data
          bool isTestData = docId.contains('test_');
          for (final field in testFields) {
            final value = data[field]?.toString() ?? '';
            if (value.contains('[TEST]') || value.contains('(Test)') || value.contains('TEST -')) {
              isTestData = true;
              break;
            }
          }
          
          if (isTestData) {
            await ref.doc(docId).delete();
            deleted++;
          }
        }
        return deleted;
      } catch (e) {
        _log('   ⚠️ Lỗi xóa Firestore $collectionName: $e');
        return 0;
      }
    }
    
    // Xóa từng collection
    int deletedDebts = await deleteTestDocsFromCollection('debts', ['personName', 'note']);
    _log('   ✓ Đã xóa $deletedDebts debts test từ Firestore');
    
    int deletedSales = await deleteTestDocsFromCollection('sales', ['notes', 'customerName']);
    _log('   ✓ Đã xóa $deletedSales sales test từ Firestore');
    
    int deletedRepairs = await deleteTestDocsFromCollection('repairs', ['notes', 'customerName']);
    _log('   ✓ Đã xóa $deletedRepairs repairs test từ Firestore');
    
    int deletedExpenses = await deleteTestDocsFromCollection('expenses', ['note', 'title']);
    _log('   ✓ Đã xóa $deletedExpenses expenses test từ Firestore');
    
    int deletedSuppliers = await deleteTestDocsFromCollection('suppliers', ['name', 'note']);
    _log('   ✓ Đã xóa $deletedSuppliers suppliers test từ Firestore');
    
    int deletedPartners = await deleteTestDocsFromCollection('repair_partners', ['name', 'note']);
    _log('   ✓ Đã xóa $deletedPartners repair_partners test từ Firestore');
    
    int deletedProducts = await deleteTestDocsFromCollection('products', ['name', 'description']);
    _log('   ✓ Đã xóa $deletedProducts products test từ Firestore');
    
    _log('   🔥 Tổng đã xóa từ Firestore: ${deletedDebts + deletedSales + deletedRepairs + deletedExpenses + deletedSuppliers + deletedPartners + deletedProducts} docs');
    
    // XÓA TẤT CẢ DEBTS có dấu hiệu test (mở rộng điều kiện)
    // Tìm theo: note chứa [TEST], personName chứa Test/(Test)/[TEST], hoặc firestoreId chứa test_
    final testDebts = await db.query(
      'debts',
      where: '''
        note LIKE ? OR 
        personName LIKE ? OR 
        personName LIKE ? OR 
        personName LIKE ? OR
        firestoreId LIKE ?
      ''',
      whereArgs: ['%[TEST]%', '%Test%', '%(Test)%', '%[TEST]%', '%test_%'],
    );

    // Delete test debts and related payments
    for (final debt in testDebts) {
      final debtId = debt['id'] as int;
      await db.delete('debt_payments', where: 'debtId = ?', whereArgs: [debtId]);
      await db.delete('debts', where: 'id = ?', whereArgs: [debtId]);
    }
    _log('   Đã xóa ${testDebts.length} debts test');

    // Delete test payment intents (bảng có thể không tồn tại)
    try {
      final testIntents = await db.query(
        'payment_intents',
        where: 'description LIKE ? OR personName LIKE ? OR firestoreId LIKE ?',
        whereArgs: ['%[TEST]%', '%Test%', '%test_%'],
      );
      for (final intent in testIntents) {
        await db.delete('payment_intents', where: 'id = ?', whereArgs: [intent['id']]);
      }
      _log('   Đã xóa ${testIntents.length} intents test');
    } catch (e) {
      _log('   (Bỏ qua payment_intents - bảng không tồn tại)');
    }
    
    // Delete test sales
    final testSales = await db.query(
      'sales',
      where: 'notes LIKE ?',
      whereArgs: ['%[TEST]%'],
    );
    for (final sale in testSales) {
      await db.delete('sales', where: 'id = ?', whereArgs: [sale['id']]);
    }
    _log('   Đã xóa ${testSales.length} sales test');
    
    // Delete test repairs
    final testRepairs = await db.query(
      'repairs',
      where: 'notes LIKE ?',
      whereArgs: ['%[TEST]%'],
    );
    for (final repair in testRepairs) {
      await db.delete('repairs', where: 'id = ?', whereArgs: [repair['id']]);
    }
    _log('   Đã xóa ${testRepairs.length} repairs test');
    
    // Delete test expenses
    final testExpenses = await db.query(
      'expenses',
      where: 'note LIKE ? OR title LIKE ?',
      whereArgs: ['%[TEST]%', '%[TEST]%'],
    );
    for (final expense in testExpenses) {
      await db.delete('expenses', where: 'id = ?', whereArgs: [expense['id']]);
    }
    _log('   Đã xóa ${testExpenses.length} expenses test');
    
    // Delete test customers
    final testCustomers = await db.query(
      'customers',
      where: 'name LIKE ? OR notes LIKE ?',
      whereArgs: ['%[TEST]%', '%[TEST]%'],
    );
    for (final c in testCustomers) {
      await db.delete('customers', where: 'id = ?', whereArgs: [c['id']]);
    }
    _log('   Đã xóa ${testCustomers.length} customers test');
    
    // Delete test suppliers
    final testSuppliers = await db.query(
      'suppliers',
      where: 'name LIKE ? OR note LIKE ?',
      whereArgs: ['%[TEST]%', '%[TEST]%'],
    );
    for (final s in testSuppliers) {
      await db.delete('suppliers', where: 'id = ?', whereArgs: [s['id']]);
    }
    _log('   Đã xóa ${testSuppliers.length} suppliers test');
    
    // Delete test repair partners
    final testPartners = await db.query(
      'repair_partners',
      where: 'name LIKE ? OR note LIKE ?',
      whereArgs: ['%[TEST]%', '%[TEST]%'],
    );
    for (final p in testPartners) {
      await db.delete('repair_partners', where: 'id = ?', whereArgs: [p['id']]);
    }
    _log('   Đã xóa ${testPartners.length} partners test');
    
    // Delete test products
    final testProducts = await db.query(
      'products',
      where: 'name LIKE ? OR description LIKE ?',
      whereArgs: ['%[TEST]%', '%[TEST]%'],
    );
    for (final p in testProducts) {
      await db.delete('products', where: 'id = ?', whereArgs: [p['id']]);
    }
    _log('   Đã xóa ${testProducts.length} products test');
    
    // Delete test repair parts
    final testParts = await db.query(
      'repair_parts',
      where: 'partName LIKE ?',
      whereArgs: ['%[TEST]%'],
    );
    for (final p in testParts) {
      await db.delete('repair_parts', where: 'id = ?', whereArgs: [p['id']]);
    }
    _log('   Đã xóa ${testParts.length} repair parts test');
  }

  String _genIntentId() => 'pi_test_${DateTime.now().millisecondsSinceEpoch}_${_uuid.v4().substring(0, 8)}';

  // ========== PHẦN 1: TẠO DOANH THU THẬT ==========
  
  /// Tạo đơn bán hàng test - iPhone
  Future<void> _createSaleOrder1() async {
    _log('📱 Tạo bán hàng: iPhone 15 Pro Max - 15M');
    
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';
    
    final sale = SaleOrder(
      firestoreId: 'test_sale_iphone_${_uuid.v4()}',
      customerName: 'TEST - Khách mua iPhone',
      phone: '0901111111',
      productNames: 'iPhone 15 Pro Max 256GB',
      productImeis: 'TEST_IMEI_001',
      totalPrice: 15000000,
      totalCost: 12000000,
      discount: 0,
      downPayment: 15000000, // ĐÃ THANH TOÁN ĐỦ
      downPaymentMethod: 'TIỀN MẶT',
      paymentMethod: 'TIỀN MẶT',
      sellerName: createdBy,
      soldAt: now.millisecondsSinceEpoch,
      notes: '[TEST] Đơn bán iPhone test',
      warranty: '12 tháng',
      isSynced: false,
    );
    
    await _db.insertSale(sale);
    _salesIncome += 15000000;
    _salesCount++;
    _log('   ✓ Đã tạo sale 15M (iPhone)');
  }
  
  /// Tạo đơn bán hàng test - Phụ kiện
  Future<void> _createSaleOrder2() async {
    _log('🔌 Tạo bán hàng: Phụ kiện - 500k');
    
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';
    
    final sale = SaleOrder(
      firestoreId: 'test_sale_accessory_${_uuid.v4()}',
      customerName: 'TEST - Khách mua phụ kiện',
      phone: '0902222222',
      productNames: 'Ốp lưng, Cường lực, Sạc nhanh',
      productImeis: '',
      totalPrice: 500000,
      totalCost: 200000,
      discount: 0,
      downPayment: 500000, // ĐÃ THANH TOÁN ĐỦ
      downPaymentMethod: 'CHUYỂN KHOẢN',
      paymentMethod: 'CHUYỂN KHOẢN',
      sellerName: createdBy,
      soldAt: now.millisecondsSinceEpoch,
      notes: '[TEST] Đơn bán phụ kiện test',
      warranty: '1 tháng',
      isSynced: false,
    );
    
    await _db.insertSale(sale);
    _salesIncome += 500000;
    _salesCount++;
    _log('   ✓ Đã tạo sale 500k (phụ kiện)');
  }
  
  /// Tạo phiếu sửa test - Thay pin
  Future<void> _createRepair1() async {
    _log('🔋 Tạo sửa chữa: Thay pin iPhone - 350k');
    
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';
    
    final repair = Repair(
      firestoreId: 'test_repair_battery_${_uuid.v4()}',
      customerName: 'TEST - KH thay pin',
      phone: '0903333333',
      model: 'iPhone 12',
      issue: 'Pin chai, cần thay mới',
      status: 4, // Đã giao
      price: 350000,
      cost: 150000,
      paymentMethod: 'TIỀN MẶT',
      createdAt: now.millisecondsSinceEpoch,
      deliveredAt: now.millisecondsSinceEpoch,
      createdBy: createdBy,
      deliveredBy: createdBy,
      notes: '[TEST] Phiếu sửa thay pin test',
      isSynced: false,
    );
    
    await _db.insertRepair(repair);
    _repairsIncome += 350000;
    _repairsCount++;
    _log('   ✓ Đã tạo repair 350k (thay pin)');
  }
  
  /// Tạo phiếu sửa test - Thay màn
  Future<void> _createRepair2() async {
    _log('📱 Tạo sửa chữa: Thay màn Samsung - 2.5M');
    
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';
    
    final repair = Repair(
      firestoreId: 'test_repair_screen_${_uuid.v4()}',
      customerName: 'TEST - KH thay màn',
      phone: '0904444444',
      model: 'Samsung S23 Ultra',
      issue: 'Màn vỡ, cần thay màn zin',
      status: 4, // Đã giao
      price: 2500000,
      cost: 1800000,
      paymentMethod: 'CHUYỂN KHOẢN',
      createdAt: now.millisecondsSinceEpoch,
      deliveredAt: now.millisecondsSinceEpoch,
      createdBy: createdBy,
      deliveredBy: createdBy,
      notes: '[TEST] Phiếu sửa thay màn test',
      isSynced: false,
    );
    
    await _db.insertRepair(repair);
    _repairsIncome += 2500000;
    _repairsCount++;
    _log('   ✓ Đã tạo repair 2.5M (thay màn)');
  }

  // ========== PHẦN 1.5: TẠO CHI PHÍ ==========
  
  /// Tạo chi phí test - Tiền điện
  Future<void> _createExpense1() async {
    _log('💡 Tạo chi phí: Tiền điện tháng 1 - 500k');
    
    final now = DateTime.now();
    final shopId = await UserService.getCurrentShopId();
    
    await _db.insertExpense({
      'firestoreId': 'test_expense_electric_${_uuid.v4()}',
      'title': '[TEST] Tiền điện tháng 1',
      'amount': 500000,
      'category': 'Điện nước',
      'date': now.millisecondsSinceEpoch,
      'note': '[TEST] Chi phí tiền điện test',
      'paymentMethod': 'TIỀN MẶT',
      'shopId': shopId,
      'isSynced': 0,
    });
    
    _expensesTotal += 500000;
    _expensesCount++;
    _log('   ✓ Đã tạo expense 500k (tiền điện)');
  }
  
  /// Tạo chi phí test - Tiền ship
  Future<void> _createExpense2() async {
    _log('🚚 Tạo chi phí: Tiền ship hàng - 300k');
    
    final now = DateTime.now();
    final shopId = await UserService.getCurrentShopId();
    
    await _db.insertExpense({
      'firestoreId': 'test_expense_shipping_${_uuid.v4()}',
      'title': '[TEST] Tiền ship hàng',
      'amount': 300000,
      'category': 'Vận chuyển',
      'date': now.millisecondsSinceEpoch,
      'note': '[TEST] Chi phí ship hàng test',
      'paymentMethod': 'CHUYỂN KHOẢN',
      'shopId': shopId,
      'isSynced': 0,
    });
    
    _expensesTotal += 300000;
    _expensesCount++;
    _log('   ✓ Đã tạo expense 300k (tiền ship)');
  }

  // ========== PHẦN 2: TẠO CÔNG NỢ + PAYMENTINTENT ==========

  /// Test 1: Tạo công nợ khách hàng (THU) - bán hàng còn nợ
  Future<void> _test1_CreateSaleDebt() async {
    _log('📝 Test 1: Công nợ bán hàng (KH còn nợ 500k)');

    final shopId = await UserService.getCurrentShopId();
    final firestoreId = 'test_debt_sale_${_uuid.v4()}';
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';

    // 1. Tạo debt trong DB - dùng đúng schema: personName, phone, totalAmount, paidAmount
    final debtId = await _db.insertDebt({
      'firestoreId': firestoreId,
      'type': 'CUSTOMER_OWES', // KH nợ shop -> THU
      'personName': 'Nguyễn Văn A (Test)',
      'phone': '0901234567',
      'totalAmount': 500000,
      'paidAmount': 0,
      'note': '[TEST] Công nợ bán hàng test',
      'status': 'pending',
      'shopId': shopId,
      'createdBy': createdBy,
      'createdAt': now.millisecondsSinceEpoch,
      'linkedId': 'test_sale_001',
      'isSynced': 0,
    });

    _log('   ✓ Đã tạo debt id=$debtId');

    // 2. Tạo PaymentIntent liên kết debt - THU (income)
    final intent = PaymentIntent(
      id: _genIntentId(),
      type: PaymentIntentType.customerDebtCollection, // THU - thu nợ khách
      amount: 500000,
      description: '[TEST] Thu tiền bán hàng - Nguyễn Văn A',
      referenceId: debtId.toString(),
      referenceType: 'debt',
      personName: 'Nguyễn Văn A (Test)',
      personPhone: '0901234567',
      createdBy: createdBy,
      createdAt: now.millisecondsSinceEpoch,
      metadata: {
        'test': true,
        'debtId': debtId,
        'debtFirestoreId': firestoreId,
        'customerName': 'Nguyễn Văn A (Test)',
        'customerPhone': '0901234567',
      },
    );

    final created = await PaymentIntentService.createIntent(intent);
    _createdIntents.add(created);
    _totalIncome += 500000;
    _incomeCount++;
    _log('   ✓ Đã tạo PaymentIntent id=${created.id} (THU 500k)');
  }

  /// Test 2: Tạo công nợ nhập hàng (CHI) - nợ NCC
  Future<void> _test2_CreatePurchaseDebt() async {
    _log('📝 Test 2: Công nợ nhập hàng (Nợ NCC 2M)');

    final shopId = await UserService.getCurrentShopId();
    final firestoreId = 'test_debt_purchase_${_uuid.v4()}';
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';

    final debtId = await _db.insertDebt({
      'firestoreId': firestoreId,
      'type': 'SHOP_OWES', // Shop nợ NCC -> CHI
      'personName': '[TEST] NCC Điện Thoại ABC',
      'phone': '02812345678',
      'totalAmount': 2000000,
      'paidAmount': 0,
      'note': '[TEST] Công nợ nhập hàng test',
      'status': 'pending',
      'shopId': shopId,
      'createdBy': createdBy,
      'createdAt': now.millisecondsSinceEpoch,
      'linkedId': 'test_purchase_001',
      'isSynced': 0,
    });

    _log('   ✓ Đã tạo debt id=$debtId');

    // CHI - trả nợ NCC
    final intent = PaymentIntent(
      id: _genIntentId(),
      type: PaymentIntentType.supplierDebt, // CHI - trả nợ NCC
      amount: 2000000,
      description: '[TEST] Trả tiền nhập hàng - NCC ABC',
      referenceId: debtId.toString(),
      referenceType: 'debt',
      personName: '[TEST] NCC Điện Thoại ABC',
      personPhone: '02812345678',
      createdBy: createdBy,
      createdAt: now.millisecondsSinceEpoch,
      metadata: {
        'test': true,
        'debtId': debtId,
        'debtFirestoreId': firestoreId,
        'supplierName': 'NCC Linh Kiện ABC (Test)',
        'supplierPhone': '0987654321',
      },
    );

    final created = await PaymentIntentService.createIntent(intent);
    _createdIntents.add(created);
    _totalExpense += 2000000;
    _expenseCount++;
    _log('   ✓ Đã tạo PaymentIntent id=${created.id} (CHI 2M)');
  }

  /// Test 3: Công nợ nhập kho (CHI)
  Future<void> _test3_CreateStockInDebt() async {
    _log('📝 Test 3: Công nợ nhập kho (Nợ NCC 1.5M)');

    final shopId = await UserService.getCurrentShopId();
    final firestoreId = 'test_debt_stockin_${_uuid.v4()}';
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';

    final debtId = await _db.insertDebt({
      'firestoreId': firestoreId,
      'type': 'SHOP_OWES', // Shop nợ NCC -> CHI
      'personName': '[TEST] NCC Linh Kiện XYZ',
      'phone': '02887654321',
      'totalAmount': 1500000,
      'paidAmount': 0,
      'note': '[TEST] Công nợ nhập kho test',
      'status': 'pending',
      'shopId': shopId,
      'createdBy': createdBy,
      'createdAt': now.millisecondsSinceEpoch,
      'linkedId': 'test_stockin_001',
      'isSynced': 0,
    });

    _log('   ✓ Đã tạo debt id=$debtId');

    // CHI - thanh toán nhập kho
    final intent = PaymentIntent(
      id: _genIntentId(),
      type: PaymentIntentType.inventoryPurchase, // CHI - nhập kho
      amount: 1500000,
      description: '[TEST] Trả tiền nhập kho - NCC XYZ',
      referenceId: debtId.toString(),
      referenceType: 'debt',
      personName: '[TEST] NCC Linh Kiện XYZ',
      personPhone: '02887654321',
      createdBy: createdBy,
      createdAt: now.millisecondsSinceEpoch,
      metadata: {
        'test': true,
        'debtId': debtId,
        'debtFirestoreId': firestoreId,
        'supplierName': '[TEST] NCC Linh Kiện XYZ',
        'supplierPhone': '02887654321',
      },
    );

    final created = await PaymentIntentService.createIntent(intent);
    _createdIntents.add(created);
    _totalExpense += 1500000;
    _expenseCount++;
    _log('   ✓ Đã tạo PaymentIntent id=${created.id} (CHI 1.5M)');
  }

  /// Test 4: Công nợ mua linh kiện sửa chữa (CHI)
  Future<void> _test4_CreatePartsDebt() async {
    _log('📝 Test 4: Công nợ linh kiện (Nợ NCC 800k)');

    final shopId = await UserService.getCurrentShopId();
    final firestoreId = 'test_debt_parts_${_uuid.v4()}';
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';

    final debtId = await _db.insertDebt({
      'firestoreId': firestoreId,
      'type': 'SHOP_OWES', // Shop nợ NCC -> CHI
      'personName': '[TEST] NCC Điện Thoại ABC',
      'phone': '02812345678',
      'totalAmount': 800000,
      'paidAmount': 0,
      'note': '[TEST] Công nợ linh kiện sửa chữa',
      'status': 'pending',
      'shopId': shopId,
      'createdBy': createdBy,
      'createdAt': now.millisecondsSinceEpoch,
      'linkedId': 'test_parts_001',
      'relatedPartId': 'test_parts_001',
      'isSynced': 0,
    });

    _log('   ✓ Đã tạo debt id=$debtId');

    // CHI - nhập linh kiện sửa chữa
    final intent = PaymentIntent(
      id: _genIntentId(),
      type: PaymentIntentType.partsStockIn, // CHI - nhập linh kiện
      amount: 800000,
      description: '[TEST] Trả tiền linh kiện - NCC ABC',
      referenceId: debtId.toString(),
      referenceType: 'debt',
      personName: '[TEST] NCC Điện Thoại ABC',
      personPhone: '02812345678',
      createdBy: createdBy,
      createdAt: now.millisecondsSinceEpoch,
      metadata: {
        'test': true,
        'debtId': debtId,
        'debtFirestoreId': firestoreId,
        'supplierName': '[TEST] NCC Điện Thoại ABC',
        'supplierPhone': '02812345678',
      },
    );

    final created = await PaymentIntentService.createIntent(intent);
    _createdIntents.add(created);
    _totalExpense += 800000;
    _expenseCount++;
    _log('   ✓ Đã tạo PaymentIntent id=${created.id} (CHI 800k)');
  }

  /// Test 5: Công nợ sửa chữa giao máy (THU)
  Future<void> _test5_CreateRepairDelivery() async {
    _log('📝 Test 5: Công nợ sửa chữa (KH nợ 1M)');

    final shopId = await UserService.getCurrentShopId();
    final firestoreId = 'test_debt_repair_${_uuid.v4()}';
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';

    final debtId = await _db.insertDebt({
      'firestoreId': firestoreId,
      'type': 'CUSTOMER_OWES', // KH nợ shop -> THU
      'personName': 'Trần Thị B (Test)',
      'phone': '0934567890',
      'totalAmount': 1000000,
      'paidAmount': 0,
      'note': '[TEST] Công nợ sửa chữa - thay màn iPhone',
      'status': 'pending',
      'shopId': shopId,
      'createdBy': createdBy,
      'createdAt': now.millisecondsSinceEpoch,
      'linkedId': 'test_repair_001',
      'isSynced': 0,
    });

    _log('   ✓ Đã tạo debt id=$debtId');

    // THU - thu tiền sửa chữa
    final intent = PaymentIntent(
      id: _genIntentId(),
      type: PaymentIntentType.repairService, // THU - thu tiền sửa chữa
      amount: 1000000,
      description: '[TEST] Thu tiền sửa chữa - Trần Thị B',
      referenceId: debtId.toString(),
      referenceType: 'debt',
      personName: 'Trần Thị B (Test)',
      personPhone: '0934567890',
      createdBy: createdBy,
      createdAt: now.millisecondsSinceEpoch,
      metadata: {
        'test': true,
        'debtId': debtId,
        'debtFirestoreId': firestoreId,
        'customerName': 'Trần Thị B (Test)',
        'customerPhone': '0934567890',
      },
    );

    final created = await PaymentIntentService.createIntent(intent);
    _createdIntents.add(created);
    _totalIncome += 1000000;
    _incomeCount++;
    _log('   ✓ Đã tạo PaymentIntent id=${created.id} (THU 1M)');
  }

  /// Verify data đã tạo
  Future<void> _verifyData() async {
    setState(() {
      _isRunning = true;
    });

    try {
      _log('🔍 Kiểm tra data đã tạo...');
      _log('─' * 50);

      final db = await _db.database;
      
      // Count sales
      final sales = await db.query(
        'sales',
        where: 'notes LIKE ?',
        whereArgs: ['%[TEST]%'],
      );
      int totalSalesIncome = 0;
      for (final s in sales) {
        totalSalesIncome += (s['totalPrice'] as num?)?.toInt() ?? 0;
      }
      _log('🛒 Sales: ${sales.length} records = ${_formatCurrency(totalSalesIncome)}');
      
      // Count repairs (status = 4 = delivered)
      final repairs = await db.query(
        'repairs',
        where: 'notes LIKE ? AND status = ?',
        whereArgs: ['%[TEST]%', 4],
      );
      int totalRepairsIncome = 0;
      for (final r in repairs) {
        totalRepairsIncome += (r['price'] as num?)?.toInt() ?? 0;
      }
      _log('🔧 Repairs (đã giao): ${repairs.length} records = ${_formatCurrency(totalRepairsIncome)}');
      
      _log('');
      _log('📊 → THU HÔM NAY (dashboard) = ${_formatCurrency(totalSalesIncome + totalRepairsIncome)}');
      _log('');

      // Count debts
      final debts = await db.query(
        'debts',
        where: 'note LIKE ?',
        whereArgs: ['%[TEST]%'],
      );
      _log('📋 Debts: ${debts.length} records');
      for (final d in debts) {
        final totalAmount = (d['totalAmount'] as num?)?.toInt() ?? 0;
        _log('   - ${d['type']} | ${_formatCurrency(totalAmount)} | ${d['personName']}');
      }

      // Count payment intents
      final intents = await db.query(
        'payment_intents',
        where: 'description LIKE ?',
        whereArgs: ['%[TEST]%'],
      );
      _log('💳 PaymentIntents: ${intents.length} records');

      int income = 0;
      int expense = 0;
      for (final i in intents) {
        final type = i['type'] as String?;
        final amount = (i['amount'] as num?)?.toInt() ?? 0;
        final status = i['status'] as String?;
        
        // Check if income type
        final intentType = PaymentIntentType.fromCode(type);
        if (intentType.isIncome) {
          income += amount;
        } else {
          expense += amount;
        }
        _log('   - $type | ${_formatCurrency(amount)} | $status');
      }

      _log('─' * 50);
      _log('💰 TỔNG KẾT:');
      _log('   CHỜ THU: ${_formatCurrency(income)}');
      _log('   CHỜ CHI: ${_formatCurrency(expense)}');

      // Count debt payments
      final payments = await db.rawQuery('''
        SELECT dp.* FROM debt_payments dp
        INNER JOIN debts d ON dp.debtId = d.id
        WHERE d.note LIKE '%[TEST]%'
      ''');
      _log('💸 DebtPayments (từ debts test): ${payments.length}');
      for (final p in payments) {
        _log('   - ${_formatCurrency((p['amount'] as num?)?.toInt() ?? 0)} | ${p['paymentMethod']}');
      }
    } catch (e) {
      _log('❌ Lỗi verify: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  /// Clear tất cả test data
  Future<void> _clearAllTestData() async {
    setState(() => _isRunning = true);

    try {
      await _clearOldTestData();
      _log('✅ Đã xóa tất cả data test');
      _createdIntents.clear();
      _totalIncome = 0;
      _totalExpense = 0;
      _incomeCount = 0;
      _expenseCount = 0;
      _salesIncome = 0;
      _repairsIncome = 0;
      _salesCount = 0;
      _repairsCount = 0;
      _expensesTotal = 0;
      _expensesCount = 0;
    } catch (e) {
      _log('❌ Lỗi xóa: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  /// Clear DEEP - xóa tất cả data test cũ (bao gồm cả trên Firestore)
  Future<void> _clearDeepTestData() async {
    setState(() => _isRunning = true);
    _logs.clear();

    try {
      _log('🔥 XÓA SÂU - Tìm và xóa tất cả data test (Local + Cloud)...');
      _log('─' * 50);

      final db = await _db.database;
      final shopId = await UserService.getCurrentShopId();
      final firestore = FirebaseFirestore.instance;
      int totalDeleted = 0;
      int cloudDeleted = 0;

      // ========== 1. XÓA DEBTS ==========
      final testDebts = await db.query(
        'debts',
        where: 'note LIKE ? OR note LIKE ? OR personName LIKE ?',
        whereArgs: ['%[TEST]%', '%test%', '%Test%'],
      );
      
      for (final debt in testDebts) {
        final debtId = debt['id'] as int;
        final firestoreId = debt['firestoreId'] as String?;
        
        // Xóa local
        await db.delete('debt_payments', where: 'debtId = ?', whereArgs: [debtId]);
        await db.delete('debts', where: 'id = ?', whereArgs: [debtId]);
        
        // Xóa trên Firestore (hard delete)
        if (firestoreId != null && firestoreId.isNotEmpty) {
          try {
            await firestore.collection('shops').doc(shopId).collection('debts').doc(firestoreId).delete();
            cloudDeleted++;
          } catch (e) {
            // Ignore if doc not found or permission denied
          }
        }
      }
      _log('🗑️ Xóa ${testDebts.length} debts test (cloud: $cloudDeleted)');
      totalDeleted += testDebts.length;

      // ========== 2. XÓA DEBT_PAYMENTS trên Cloud ==========
      final testDebtPayments = await db.query('debt_payments');
      for (final dp in testDebtPayments) {
        final firestoreId = dp['firestoreId'] as String?;
        if (firestoreId != null && firestoreId.contains('test')) {
          try {
            await firestore.collection('shops').doc(shopId).collection('debt_payments').doc(firestoreId).delete();
          } catch (e) {}
        }
      }

      // ========== 3. XÓA PAYMENT_INTENTS ==========
      final testIntents = await db.query(
        'payment_intents',
        where: 'description LIKE ? OR description LIKE ? OR personName LIKE ? OR id LIKE ?',
        whereArgs: ['%[TEST]%', '%test%', '%Test%', '%pi_test_%'],
      );
      for (final intent in testIntents) {
        await db.delete('payment_intents', where: 'id = ?', whereArgs: [intent['id']]);
      }
      _log('🗑️ Xóa ${testIntents.length} payment_intents test');
      totalDeleted += testIntents.length;

      // ========== 4. XÓA SALES ==========
      cloudDeleted = 0;
      final testSales = await db.query(
        'sales',
        where: 'notes LIKE ? OR notes LIKE ? OR customerName LIKE ?',
        whereArgs: ['%[TEST]%', '%test%', '%TEST%'],
      );
      for (final sale in testSales) {
        final firestoreId = sale['firestoreId'] as String?;
        await db.delete('sales', where: 'id = ?', whereArgs: [sale['id']]);
        
        if (firestoreId != null && firestoreId.isNotEmpty) {
          try {
            await firestore.collection('shops').doc(shopId).collection('sales').doc(firestoreId).delete();
            cloudDeleted++;
          } catch (e) {}
        }
      }
      _log('🗑️ Xóa ${testSales.length} sales test (cloud: $cloudDeleted)');
      totalDeleted += testSales.length;

      // ========== 5. XÓA REPAIRS ==========
      cloudDeleted = 0;
      final testRepairs = await db.query(
        'repairs',
        where: 'notes LIKE ? OR notes LIKE ? OR customerName LIKE ?',
        whereArgs: ['%[TEST]%', '%test%', '%TEST%'],
      );
      for (final repair in testRepairs) {
        final firestoreId = repair['firestoreId'] as String?;
        await db.delete('repairs', where: 'id = ?', whereArgs: [repair['id']]);
        
        if (firestoreId != null && firestoreId.isNotEmpty) {
          try {
            await firestore.collection('shops').doc(shopId).collection('repairs').doc(firestoreId).delete();
            cloudDeleted++;
          } catch (e) {}
        }
      }
      _log('🗑️ Xóa ${testRepairs.length} repairs test (cloud: $cloudDeleted)');
      totalDeleted += testRepairs.length;

      // ========== 6. XÓA EXPENSES ==========
      cloudDeleted = 0;
      final testExpenses = await db.query(
        'expenses',
        where: 'note LIKE ? OR note LIKE ? OR title LIKE ?',
        whereArgs: ['%[TEST]%', '%test%', '%[TEST]%'],
      );
      for (final expense in testExpenses) {
        final firestoreId = expense['firestoreId'] as String?;
        await db.delete('expenses', where: 'id = ?', whereArgs: [expense['id']]);
        
        if (firestoreId != null && firestoreId.isNotEmpty) {
          try {
            await firestore.collection('shops').doc(shopId).collection('expenses').doc(firestoreId).delete();
            cloudDeleted++;
          } catch (e) {}
        }
      }
      _log('🗑️ Xóa ${testExpenses.length} expenses test (cloud: $cloudDeleted)');
      totalDeleted += testExpenses.length;

      _log('─' * 50);
      _log('✅ TỔNG: Đã xóa $totalDeleted records test (Local + Cloud)');
      _log('');
      _log('⚠️ QUAN TRỌNG: Khởi động lại app để sync lại data!');
      _log('💡 Quay về Dashboard để kiểm tra số liệu đã về ban đầu');

      // Reset stats
      _createdIntents.clear();
      _totalIncome = 0;
      _totalExpense = 0;
      _incomeCount = 0;
      _expenseCount = 0;
      _salesIncome = 0;
      _repairsIncome = 0;
      _salesCount = 0;
      _repairsCount = 0;
      _expensesTotal = 0;
      _expensesCount = 0;
    } catch (e) {
      _log('❌ Lỗi xóa sâu: $e');
    } finally {
      setState(() => _isRunning = false);
    }
  }

  String _formatCurrency(int amount) {
    final formatted = amount.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${formatted}đ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test PaymentIntent (Real Data)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isRunning ? null : _verifyData,
            tooltip: 'Verify Data',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header info
          Container(
            color: Colors.blue.shade50,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎯 Test Dashboard + PaymentIntent',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tạo data bán hàng, sửa chữa (ảnh hưởng Dashboard)\n'
                  '+ Công nợ với PaymentIntent (chờ thanh toán).',
                  style: TextStyle(fontSize: 13),
                ),
                const Divider(),
                // Dashboard preview
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('📊 DASHBOARD (THU HÔM NAY)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(child: Text('Bán hàng: ${_formatCurrency(_salesIncome)}', style: const TextStyle(fontSize: 12))),
                          Expanded(child: Text('Sửa chữa: ${_formatCurrency(_repairsIncome)}', style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                      Text('→ THU HÔM NAY = ${_formatCurrency(_salesIncome + _repairsIncome)}', 
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green.shade700)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                // PaymentIntent stats
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard('CHỜ THU', _totalIncome, _incomeCount, Colors.green),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStatCard('CHỜ CHI', _totalExpense, _expenseCount, Colors.red),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isRunning ? null : _runAllTests,
                    icon: _isRunning
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow),
                    label: const Text('TẠO DATA TEST'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isRunning ? null : _verifyData,
                    icon: const Icon(Icons.search),
                    label: const Text('VERIFY'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Logs
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: _logs.isEmpty
                  ? const Center(
                      child: Text(
                        'Nhấn "TẠO DATA TEST" để bắt đầu\n\n'
                        'Sau đó quay về Dashboard kiểm tra\n'
                        'THU HÔM NAY = bán hàng + sửa chữa',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        final log = _logs[index];
                        Color? color;
                        if (log.contains('✓') || log.contains('✅')) {
                          color = Colors.green.shade700;
                        } else if (log.contains('❌')) {
                          color = Colors.red;
                        } else if (log.contains('📝') || log.contains('🚀')) {
                          color = Colors.blue.shade700;
                        }
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            log,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: color,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),

          // Hint
          Container(
            padding: const EdgeInsets.all(12),
            child: const Text(
              '💡 THU HÔM NAY = doanh thu bán hàng + sửa chữa (accrual basis)\n'
              '   Thu nợ chỉ ảnh hưởng quỹ tiền, KHÔNG cộng thêm doanh thu.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int amount, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatCurrency(amount),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(
            '$count items',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  // ========== PHẦN 0: TẠO MASTER DATA ==========
  
  /// Tạo 3 khách hàng test
  Future<void> _createCustomers() async {
    _log('👤 Tạo 3 khách hàng test...');
    final shopId = await UserService.getCurrentShopId();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final customers = [
      {
        'firestoreId': 'test_customer_1_${_uuid.v4()}',
        'name': '[TEST] Nguyễn Văn An',
        'phone': '0901111111',
        'email': 'an@test.com',
        'address': '123 Nguyễn Trãi, Q1, HCM',
        'notes': '[TEST] Khách VIP',
        'createdAt': now,
        'totalSpent': 15000000,
        'totalRepairs': 1,
        'totalRepairCost': 350000,
        'shopId': shopId,
        'isSynced': 0,
        'deleted': 0,
      },
      {
        'firestoreId': 'test_customer_2_${_uuid.v4()}',
        'name': '[TEST] Trần Thị Bình',
        'phone': '0902222222',
        'email': 'binh@test.com',
        'address': '456 Lê Lợi, Q3, HCM',
        'notes': '[TEST] Khách mới',
        'createdAt': now,
        'totalSpent': 500000,
        'totalRepairs': 0,
        'totalRepairCost': 0,
        'shopId': shopId,
        'isSynced': 0,
        'deleted': 0,
      },
      {
        'firestoreId': 'test_customer_3_${_uuid.v4()}',
        'name': '[TEST] Lê Văn Cường',
        'phone': '0903333333',
        'email': 'cuong@test.com',
        'address': '789 Hai Bà Trưng, Q1, HCM',
        'notes': '[TEST] Khách trả góp',
        'createdAt': now,
        'totalSpent': 45000000,
        'totalRepairs': 2,
        'totalRepairCost': 2850000,
        'shopId': shopId,
        'isSynced': 0,
        'deleted': 0,
      },
    ];
    
    for (final c in customers) {
      await _db.insertCustomer(c);
    }
    _log('   ✓ Đã tạo 3 khách hàng');
  }
  
  /// Tạo 2 nhà cung cấp test
  Future<void> _createSuppliers() async {
    _log('🏭 Tạo 2 nhà cung cấp test...');
    final shopId = await UserService.getCurrentShopId();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final suppliers = [
      {
        'firestoreId': 'test_supplier_1_${_uuid.v4()}',
        'name': '[TEST] NCC Điện Thoại ABC',
        'phone': '02812345678',
        'email': 'abc@ncc.com',
        'address': '100 Nguyễn Huệ, Q1, HCM',
        'note': '[TEST] NCC điện thoại chính',
        'active': 1,
        'favorite': 1,
        'createdAt': now,
        'updatedAt': now,
        'shopId': shopId,
      },
      {
        'firestoreId': 'test_supplier_2_${_uuid.v4()}',
        'name': '[TEST] NCC Linh Kiện XYZ',
        'phone': '02887654321',
        'email': 'xyz@ncc.com',
        'address': '200 Lê Duẩn, Q1, HCM',
        'note': '[TEST] NCC linh kiện sửa chữa',
        'active': 1,
        'favorite': 0,
        'createdAt': now,
        'updatedAt': now,
        'shopId': shopId,
      },
    ];
    
    for (final s in suppliers) {
      await _db.insertSupplier(s);
    }
    _log('   ✓ Đã tạo 2 nhà cung cấp');
  }
  
  /// Tạo 2 đối tác sửa chữa test
  Future<void> _createRepairPartners() async {
    _log('🤝 Tạo 2 đối tác sửa chữa test...');
    final shopId = await UserService.getCurrentShopId();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final partners = [
      {
        'firestoreId': 'test_partner_1_${_uuid.v4()}',
        'name': '[TEST] Anh Minh Sửa Màn',
        'phone': '0909111222',
        'note': '[TEST] Chuyên thay màn iPhone',
        'active': 1,
        'createdAt': now,
        'updatedAt': now,
        'shopId': shopId,
      },
      {
        'firestoreId': 'test_partner_2_${_uuid.v4()}',
        'name': '[TEST] Chị Lan Sửa Main',
        'phone': '0909333444',
        'note': '[TEST] Chuyên sửa main Samsung',
        'active': 1,
        'createdAt': now,
        'updatedAt': now,
        'shopId': shopId,
      },
    ];
    
    for (final p in partners) {
      await _db.insertRepairPartner(p);
    }
    _log('   ✓ Đã tạo 2 đối tác sửa chữa');
  }
  
  /// Tạo 3 sản phẩm trong kho test
  Future<void> _createProducts() async {
    _log('📦 Tạo 3 sản phẩm trong kho test...');
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final products = [
      Product(
        firestoreId: 'test_product_1_${_uuid.v4()}',
        name: '[TEST] iPhone 15 Pro Max',
        brand: 'APPLE',
        model: 'iPhone 15 Pro Max',
        imei: 'TEST_IMEI_001',
        cost: 28000000,
        price: 32000000,
        condition: 'Mới 100%',
        status: 1, // Còn hàng
        description: '[TEST] Sản phẩm test',
        warranty: '12 tháng',
        createdAt: now,
        type: 'DIEN_THOAI',
        quantity: 2,
        color: 'Titan Đen',
        capacity: '256GB',
        paymentMethod: 'CÔNG NỢ',
        isSynced: false,
      ),
      Product(
        firestoreId: 'test_product_2_${_uuid.v4()}',
        name: '[TEST] Samsung Galaxy S24 Ultra',
        brand: 'SAMSUNG',
        model: 'Galaxy S24 Ultra',
        imei: 'TEST_IMEI_002',
        cost: 25000000,
        price: 29000000,
        condition: 'Mới 100%',
        status: 1,
        description: '[TEST] Sản phẩm test',
        warranty: '12 tháng',
        createdAt: now,
        type: 'DIEN_THOAI',
        quantity: 1,
        color: 'Xám',
        capacity: '512GB',
        paymentMethod: 'TIỀN MẶT',
        isSynced: false,
      ),
      Product(
        firestoreId: 'test_product_3_${_uuid.v4()}',
        name: '[TEST] Ốp lưng iPhone 15',
        brand: 'APPLE',
        model: 'iPhone 15',
        imei: '',
        cost: 100000,
        price: 200000,
        condition: 'Mới',
        status: 1,
        description: '[TEST] Phụ kiện test',
        warranty: '1 tháng',
        createdAt: now,
        type: 'PHU_KIEN',
        quantity: 10,
        paymentMethod: 'TIỀN MẶT',
        isSynced: false,
      ),
    ];
    
    for (final p in products) {
      await _db.upsertProduct(p);
    }
    _log('   ✓ Đã tạo 3 sản phẩm trong kho');
  }
  
  /// Tạo 3 linh kiện sửa chữa test
  Future<void> _createRepairParts() async {
    _log('🔧 Tạo 3 linh kiện sửa chữa test...');
    final shopId = await UserService.getCurrentShopId();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    final parts = [
      {
        'firestoreId': 'test_part_1_${_uuid.v4()}',
        'partName': '[TEST] Màn hình iPhone 15 Pro',
        'compatibleModels': 'iPhone 15 Pro, iPhone 15 Pro Max',
        'cost': 2500000,
        'price': 3500000,
        'quantity': 3,
        'createdAt': now,
        'updatedAt': now,
        'shopId': shopId,
        'isSynced': 0,
        'deleted': 0,
        'paymentMethod': 'CÔNG NỢ',
      },
      {
        'firestoreId': 'test_part_2_${_uuid.v4()}',
        'partName': '[TEST] Pin iPhone 12',
        'compatibleModels': 'iPhone 12, iPhone 12 Pro',
        'cost': 200000,
        'price': 350000,
        'quantity': 10,
        'createdAt': now,
        'updatedAt': now,
        'shopId': shopId,
        'isSynced': 0,
        'deleted': 0,
        'paymentMethod': 'TIỀN MẶT',
      },
      {
        'firestoreId': 'test_part_3_${_uuid.v4()}',
        'partName': '[TEST] Main Samsung S23',
        'compatibleModels': 'Samsung S23, Samsung S23+',
        'cost': 4000000,
        'price': 5500000,
        'quantity': 2,
        'createdAt': now,
        'updatedAt': now,
        'shopId': shopId,
        'isSynced': 0,
        'deleted': 0,
        'paymentMethod': 'CÔNG NỢ',
      },
    ];
    
    for (final p in parts) {
      await _db.insertPart(p);
    }
    _log('   ✓ Đã tạo 3 linh kiện sửa chữa');
  }
  
  /// Tạo đơn trả góp 1 ngân hàng
  Future<void> _createInstallmentSale1() async {
    _log('🏦 Tạo đơn trả góp 1 NH: Samsung S24 - 20M');
    
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';
    
    final sale = SaleOrder(
      firestoreId: 'test_sale_installment1_${_uuid.v4()}',
      customerName: '[TEST] Lê Văn Cường',
      phone: '0903333333',
      productNames: 'Samsung Galaxy S24 Ultra 256GB',
      productImeis: 'TEST_IMEI_INSTALL_001',
      totalPrice: 20000000,
      totalCost: 17000000,
      discount: 0,
      isInstallment: true,
      downPayment: 5000000, // Trả trước 5M
      downPaymentMethod: 'TIỀN MẶT',
      loanAmount: 15000000, // Vay 15M
      bankName: 'FE CREDIT',
      installmentTerm: '12 tháng',
      paymentMethod: 'TRẢ GÓP (NH)',
      sellerName: createdBy,
      soldAt: now.millisecondsSinceEpoch,
      notes: '[TEST] Đơn trả góp 1 ngân hàng test',
      warranty: '12 tháng',
      isSynced: false,
    );
    
    await _db.insertSale(sale);
    _salesIncome += 20000000;
    _salesCount++;
    _log('   ✓ Đã tạo sale trả góp 20M (FE CREDIT)');
  }
  
  /// Tạo đơn trả góp 2 ngân hàng
  Future<void> _createInstallmentSale2() async {
    _log('🏦 Tạo đơn trả góp 2 NH: iPhone 15 PM - 25M');
    
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';
    
    final sale = SaleOrder(
      firestoreId: 'test_sale_installment2_${_uuid.v4()}',
      customerName: '[TEST] Phạm Thị Dung',
      phone: '0904444444',
      productNames: 'iPhone 15 Pro Max 256GB',
      productImeis: 'TEST_IMEI_INSTALL_002',
      totalPrice: 25000000,
      totalCost: 21000000,
      discount: 0,
      isInstallment: true,
      downPayment: 8000000, // Trả trước 8M
      downPaymentMethod: 'CHUYỂN KHOẢN',
      loanAmount: 10000000, // Vay NH1: 10M
      bankName: 'HOME CREDIT',
      loanAmount2: 7000000, // Vay NH2: 7M
      bankName2: 'MCREDIT',
      installmentTerm: '6 tháng',
      paymentMethod: 'TRẢ GÓP (NH)',
      sellerName: createdBy,
      soldAt: now.millisecondsSinceEpoch,
      notes: '[TEST] Đơn trả góp 2 ngân hàng test',
      warranty: '12 tháng',
      isSynced: false,
    );
    
    await _db.insertSale(sale);
    _salesIncome += 25000000;
    _salesCount++;
    _log('   ✓ Đã tạo sale trả góp 25M (HOME CREDIT + MCREDIT)');
  }
  
  /// Tạo nợ NCC
  Future<void> _createSupplierDebt() async {
    _log('📝 Tạo nợ NCC: 3M');
    
    final shopId = await UserService.getCurrentShopId();
    final firestoreId = 'test_debt_supplier_main_${_uuid.v4()}';
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';
    
    await _db.insertDebt({
      'firestoreId': firestoreId,
      'type': 'SHOP_OWES', // Shop nợ NCC
      'personName': '[TEST] NCC Điện Thoại ABC',
      'phone': '02812345678',
      'totalAmount': 3000000,
      'paidAmount': 0,
      'note': '[TEST] Nợ nhập iPhone đợt 1',
      'status': 'pending',
      'shopId': shopId,
      'createdBy': createdBy,
      'createdAt': now.millisecondsSinceEpoch,
      'linkedId': 'test_purchase_main',
      'isSynced': 0,
    });
    
    _log('   ✓ Đã tạo nợ NCC 3M');
  }
  
  /// Tạo nợ đối tác sửa chữa
  Future<void> _createPartnerDebt() async {
    _log('📝 Tạo nợ đối tác: 1.5M');
    
    final shopId = await UserService.getCurrentShopId();
    final firestoreId = 'test_debt_partner_${_uuid.v4()}';
    final now = DateTime.now();
    final createdBy = FirebaseAuth.instance.currentUser?.uid ?? 'test_user';
    
    final debtId = await _db.insertDebt({
      'firestoreId': firestoreId,
      'type': 'REPAIR_PARTNER', // Shop nợ đối tác
      'personName': '[TEST] Anh Minh Sửa Màn',
      'phone': '0909111222',
      'totalAmount': 1500000,
      'paidAmount': 0,
      'note': '[TEST] Nợ tiền sửa màn 3 máy',
      'status': 'pending',
      'shopId': shopId,
      'createdBy': createdBy,
      'createdAt': now.millisecondsSinceEpoch,
      'linkedId': 'test_repair_partner',
      'isSynced': 0,
    });
    
    _log('   ✓ Đã tạo nợ đối tác 1.5M (id=$debtId, firestoreId=$firestoreId)');
    
    // Verify debt was created
    final db = await _db.database;
    final verify = await db.query('debts', where: 'type = ?', whereArgs: ['REPAIR_PARTNER']);
    _log('   → Verify: ${verify.length} REPAIR_PARTNER debts trong DB');
  }
}
