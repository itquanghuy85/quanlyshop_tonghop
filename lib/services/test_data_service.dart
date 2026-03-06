import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/sale_order_model.dart';
import '../models/sales_return_model.dart';
import 'firestore_service.dart';
import 'sales_return_service.dart';
import 'user_service.dart';

/// Service to seed realistic test data for debugging finance flow.
/// Creates products → sales → returns → expenses in the correct order.
class TestDataService {
  static final _db = DBHelper();

  /// Seed a full set of test data for today.
  /// Returns a summary string.
  static Future<String> seedTestData() async {
    final log = StringBuffer();
    final now = DateTime.now();
    final todayMs = now.millisecondsSinceEpoch;
    final shopId = UserService.getShopIdSync() ?? '';
    final userName = await UserService.getCurrentUserName();

    debugPrint('🧪 TEST DATA: Starting seed for shop $shopId...');

    // ========== 1. PRODUCTS ==========
    final products = <Product>[];
    final productData = [
      {'name': 'IPHONE 15 PRO MAX 256GB', 'imei': '350111222333441', 'cost': 28000000, 'price': 32000000, 'type': 'DIEN_THOAI', 'brand': 'APPLE', 'color': 'ĐEN', 'capacity': '256GB'},
      {'name': 'IPHONE 14 128GB', 'imei': '350111222333442', 'cost': 16000000, 'price': 19500000, 'type': 'DIEN_THOAI', 'brand': 'APPLE', 'color': 'TRẮNG', 'capacity': '128GB'},
      {'name': 'SAMSUNG GALAXY S24 ULTRA', 'imei': '350111222333443', 'cost': 25000000, 'price': 29900000, 'type': 'DIEN_THOAI', 'brand': 'SAMSUNG', 'color': 'TÍM', 'capacity': '256GB'},
      {'name': 'OPPO RENO 11 5G', 'imei': '350111222333444', 'cost': 7500000, 'price': 9990000, 'type': 'DIEN_THOAI', 'brand': 'OPPO', 'color': 'XANH', 'capacity': '256GB'},
      {'name': 'ỐP LƯNG IPHONE 15', 'imei': 'PKX5', 'cost': 50000, 'price': 150000, 'type': 'PHU_KIEN', 'brand': 'KHÁC', 'qty': 5},
      {'name': 'CÁP SẠC TYPE-C', 'imei': 'PKX10', 'cost': 30000, 'price': 80000, 'type': 'PHU_KIEN', 'brand': 'KHÁC', 'qty': 10},
      {'name': 'TAI NGHE BLUETOOTH', 'imei': 'PKX3', 'cost': 200000, 'price': 450000, 'type': 'PHU_KIEN', 'brand': 'KHÁC', 'qty': 3},
      {'name': 'KÍNH CƯỜNG LỰC IPHONE 15', 'imei': 'PKX20', 'cost': 15000, 'price': 80000, 'type': 'PHU_KIEN', 'brand': 'KHÁC', 'qty': 20},
    ];

    for (final pd in productData) {
      final p = Product(
        name: pd['name'] as String,
        brand: pd['brand'] as String,
        imei: pd['imei'] as String,
        cost: pd['cost'] as int,
        price: pd['price'] as int,
        type: pd['type'] as String,
        color: pd['color'] as String? ?? '',
        capacity: pd['capacity'] as String? ?? '',
        condition: 'Mới',
        status: 1,
        quantity: (pd['qty'] as int?) ?? 1,
        description: '',
        createdAt: todayMs - 86400000, // yesterday
      );
      // Add to Firestore first → get firestoreId
      final fsId = await FirestoreService.addProduct(p);
      p.firestoreId = fsId;
      // Upsert to local DB (void return)
      await _db.upsertProduct(p);
      // Query back to get local ID
      final dbProduct = await _db.getProductByImei(p.imei ?? '');
      if (dbProduct != null) {
        p.id = dbProduct.id;
      }
      products.add(p);
      debugPrint('🧪 Created product: ${p.name} (${p.imei})');
    }
    log.writeln('✅ ${products.length} sản phẩm');

    // ========== 2. SALES (diverse payment methods) ==========
    // Sale 1: iPhone 15 Pro + Ốp lưng x2 — Tiền mặt
    final sale1At = todayMs - 3600000 * 5; // 5 hours ago
    final sale1 = SaleOrder(
      customerName: 'NGUYỄN VĂN ANH',
      phone: '0901234567',
      isWalkIn: false,
      address: 'Q1 TPHCM',
      productNames: 'IPHONE 15 PRO MAX 256GB x1, ỐP LƯNG IPHONE 15 x2',
      productImeis: '350111222333441, PKx2',
      totalPrice: 32300000,
      totalCost: 28100000,
      discount: 0,
      paymentMethod: 'TIỀN MẶT',
      sellerName: userName,
      soldAt: sale1At,
      warranty: '12 tháng',
    );
    final sale1Id = await FirestoreService.addSale(sale1);
    if (sale1Id != null) {
      sale1.firestoreId = sale1Id;
      await _db.insertSale(sale1);
      // Query back to get local ID
      final dbSale = await _db.getSaleByFirestoreId(sale1Id);
      if (dbSale != null) sale1.id = dbSale.id;
      // Reduce stock
      products[0].quantity = 0; products[0].status = 0;
      await _db.updateProduct(products[0]);
      products[4].quantity -= 2;
      await _db.updateProduct(products[4]);
    }
    log.writeln('✅ Đơn 1: iPhone 15 Pro + ốp — 32.3tr tiền mặt');

    // Sale 2: Samsung S24 — Chuyển khoản
    final sale2At = todayMs - 3600000 * 4;
    final sale2 = SaleOrder(
      customerName: 'TRẦN THỊ MAI',
      phone: '0912345678',
      isWalkIn: false,
      address: 'Q7 TPHCM',
      productNames: 'SAMSUNG GALAXY S24 ULTRA x1',
      productImeis: '350111222333443',
      totalPrice: 29900000,
      totalCost: 25000000,
      discount: 500000,
      paymentMethod: 'CHUYỂN KHOẢN',
      sellerName: userName,
      soldAt: sale2At,
      warranty: '12 tháng',
    );
    final sale2Id = await FirestoreService.addSale(sale2);
    if (sale2Id != null) {
      sale2.firestoreId = sale2Id;
      await _db.insertSale(sale2);
      final dbSale2 = await _db.getSaleByFirestoreId(sale2Id);
      if (dbSale2 != null) sale2.id = dbSale2.id;
      products[2].quantity = 0; products[2].status = 0;
      await _db.updateProduct(products[2]);
    }
    log.writeln('✅ Đơn 2: Samsung S24 — 29.4tr chuyển khoản');

    // Sale 3: Oppo + cáp x3 + kính x2 — Tiền mặt
    final sale3At = todayMs - 3600000 * 3;
    final sale3 = SaleOrder(
      customerName: 'LÊ HOÀNG NAM',
      phone: '0923456789',
      isWalkIn: false,
      address: 'THỦ ĐỨC',
      productNames: 'OPPO RENO 11 5G x1, CÁP SẠC TYPE-C x3, KÍNH CƯỜNG LỰC IPHONE 15 x2',
      productImeis: '350111222333444, PKx3, PKx2',
      totalPrice: 10390000,
      totalCost: 7620000,
      discount: 100000,
      paymentMethod: 'TIỀN MẶT',
      sellerName: userName,
      soldAt: sale3At,
      warranty: '12 tháng',
    );
    final sale3Id = await FirestoreService.addSale(sale3);
    if (sale3Id != null) {
      sale3.firestoreId = sale3Id;
      await _db.insertSale(sale3);
      final dbSale3 = await _db.getSaleByFirestoreId(sale3Id);
      if (dbSale3 != null) sale3.id = dbSale3.id;
      products[3].quantity = 0; products[3].status = 0;
      await _db.updateProduct(products[3]);
      products[5].quantity -= 3;
      await _db.updateProduct(products[5]);
      products[7].quantity -= 2;
      await _db.updateProduct(products[7]);
    }
    log.writeln('✅ Đơn 3: Oppo + phụ kiện — 10.29tr tiền mặt');

    // Sale 4: iPhone 14 + tai nghe — Công nợ
    final sale4At = todayMs - 3600000 * 2;
    final sale4 = SaleOrder(
      customerName: 'PHẠM MINH TUẤN',
      phone: '0934567890',
      isWalkIn: false,
      address: 'BÌNH THẠNH',
      productNames: 'IPHONE 14 128GB x1, TAI NGHE BLUETOOTH x1',
      productImeis: '350111222333442, PKx1',
      totalPrice: 19950000,
      totalCost: 16200000,
      discount: 0,
      paymentMethod: 'CÔNG NỢ',
      sellerName: userName,
      soldAt: sale4At,
      warranty: '12 tháng',
    );
    final sale4Id = await FirestoreService.addSale(sale4);
    if (sale4Id != null) {
      sale4.firestoreId = sale4Id;
      await _db.insertSale(sale4);
      final dbSale4 = await _db.getSaleByFirestoreId(sale4Id);
      if (dbSale4 != null) sale4.id = dbSale4.id;
      products[1].quantity = 0; products[1].status = 0;
      await _db.updateProduct(products[1]);
      products[6].quantity -= 1;
      await _db.updateProduct(products[6]);
    }
    log.writeln('✅ Đơn 4: iPhone 14 + tai nghe — 19.95tr công nợ');

    // ========== 3. EXPENSES ==========
    final expenses = [
      {'title': 'TIỀN ĐIỆN THÁNG 3', 'amount': 2500000, 'category': 'Tiện ích', 'method': 'CHUYỂN KHOẢN', 'type': 'CHI'},
      {'title': 'MUA BÀN LÀM VIỆC', 'amount': 3000000, 'category': 'Trang thiết bị', 'method': 'TIỀN MẶT', 'type': 'CHI'},
      {'title': 'TRÀ SỮA TIẾP KHÁCH', 'amount': 150000, 'category': 'Tiếp khách', 'method': 'TIỀN MẶT', 'type': 'CHI'},
      {'title': 'THU TIỀN SỬA MÀN HÌNH IPAD', 'amount': 500000, 'category': 'Thu khác', 'method': 'TIỀN MẶT', 'type': 'THU'},
    ];
    for (final exp in expenses) {
      final expDate = todayMs - 3600000;
      final expData = {
        'title': exp['title'],
        'amount': exp['amount'],
        'category': exp['category'],
        'date': expDate,
        'paymentMethod': exp['method'],
        'type': exp['type'],
        'note': 'Test data',
        'shopId': shopId,
        'createdAt': todayMs,
        'isSynced': 0,
      };
      // Cloud first → gets firestoreId assigned to expData map
      await FirestoreService.addExpenseCloud(expData);
      // Remove Firestore sentinel before local insert
      expData.remove('updatedAt');
      expData['isSynced'] = 1;
      await _db.insertExpense(expData);
    }
    log.writeln('✅ ${expenses.length} khoản thu/chi');

    // ========== 4. SALES RETURN (partial return from sale 3) ==========
    // Return the Oppo phone from sale 3, keep the accessories
    if (sale3.id != null && sale3.id! > 0) {
      final returnResult = await SalesReturnService.processReturn(
        salesOrderId: sale3.id!,
        salesOrderFirestoreId: sale3.firestoreId,
        customerName: sale3.customerName,
        customerPhone: sale3.phone,
        refundMethod: 'TIỀN MẶT',
        items: [
          SalesReturnItem(
            productId: products[3].id,
            productFirestoreId: products[3].firestoreId,
            productName: 'OPPO RENO 11 5G',
            productImei: '350111222333444',
            quantity: 1,
            price: 9990000,
            cost: 7500000,
            amount: 9990000,
          ),
        ],
        note: 'Khách đổi ý, muốn mua Samsung',
      );
      if (returnResult['success'] == true) {
        log.writeln('✅ Trả hàng: Oppo từ đơn 3 — 9.99tr hoàn tiền mặt');
      }
    }

    debugPrint('🧪 TEST DATA: Seed complete!');
    log.writeln('\n📊 Kết quả mong đợi:');
    log.writeln('  THU (📥): ~71.99tr (bán hàng) + 0.5tr (thu khác) = ~72.49tr');
    log.writeln('  CHI (📤): ~5.65tr (chi phí) + 9.99tr (trả hàng) = ~15.64tr');
    log.writeln('  LÃI: ~7.38tr (doanh thu - giá vốn - chi phí + thu khác)');
    log.writeln('  Công nợ: 19.95tr (iPhone 14 + tai nghe)');
    log.writeln('  Kho: 8 SP tạo, 4 bán, 1 trả lại (Oppo)');

    return log.toString();
  }
}
