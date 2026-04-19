import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_write_helper.dart';
import 'package:flutter/foundation.dart';
import '../services/user_service.dart';
import '../services/encryption_service.dart';

/// Script tạo dữ liệu test thật cho tất cả chỉ số tài chính.
/// Chạy 1 lần duy nhất qua SeedTestData.run() khi đăng nhập bằng tài khoản test.
class SeedTestData {
  static final _db = FirebaseFirestore.instance;
  static final _rand = Random();

  static Future<void> run() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      debugPrint('❌ SeedTestData: No shopId');
      return;
    }

    debugPrint('🌱 SeedTestData: Bắt đầu tạo dữ liệu cho shopId=$shopId');

    final now = DateTime.now();
    final todayMs = now.millisecondsSinceEpoch;

    // --- PRODUCTS (10 sản phẩm) ---
    final products = [
      {'name': 'IPHONE 15 PRO MAX 256GB', 'brand': 'APPLE', 'cost': 28000000, 'price': 32000000, 'type': 'DIEN_THOAI'},
      {'name': 'IPHONE 14 PRO 128GB', 'brand': 'APPLE', 'cost': 18000000, 'price': 21500000, 'type': 'DIEN_THOAI'},
      {'name': 'SAMSUNG S24 ULTRA 256GB', 'brand': 'SAMSUNG', 'cost': 24000000, 'price': 28000000, 'type': 'DIEN_THOAI'},
      {'name': 'OPPO RENO 11 PRO', 'brand': 'OPPO', 'cost': 8000000, 'price': 10500000, 'type': 'DIEN_THOAI'},
      {'name': 'XIAOMI 14 ULTRA', 'brand': 'XIAOMI', 'cost': 15000000, 'price': 18000000, 'type': 'DIEN_THOAI'},
      {'name': 'ỐP LƯNG IPHONE 15', 'brand': 'KHÁC', 'cost': 50000, 'price': 150000, 'type': 'PHU_KIEN', 'qty': 20},
      {'name': 'SẠC NHANH 65W TYPE-C', 'brand': 'ANKER', 'cost': 200000, 'price': 450000, 'type': 'PHU_KIEN', 'qty': 15},
      {'name': 'TAI NGHE AIRPODS PRO 2', 'brand': 'APPLE', 'cost': 4500000, 'price': 5800000, 'type': 'PHU_KIEN'},
      {'name': 'MÀN HÌNH IPHONE 13', 'brand': 'LINH KIỆN', 'cost': 800000, 'price': 0, 'type': 'LINH_KIEN', 'qty': 5},
      {'name': 'PIN IPHONE 12', 'brand': 'LINH KIỆN', 'cost': 250000, 'price': 0, 'type': 'LINH_KIEN', 'qty': 10},
    ];

    for (var p in products) {
      final ts = todayMs - _rand.nextInt(7 * 86400000); // Random trong 7 ngày
      final data = {
        'name': p['name'],
        'brand': p['brand'],
        'cost': p['cost'],
        'price': p['price'],
        'type': p['type'],
        'condition': 'Mới',
        'quantity': p['qty'] ?? 1,
        'status': 'IN_STOCK',
        'createdAt': ts,
        'shopId': shopId,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      };
      await _db.collection('products').add(EncryptionService.encryptMap(data));
    }
    debugPrint('✅ SeedTestData: 10 products created');

    // --- SALES (8 đơn bán - mix các loại thanh toán) ---
    final customers = ['NGUYỄN VĂN ANH', 'TRẦN THỊ BÍCH', 'LÊ HOÀNG NAM', 'PHẠM MINH TUẤN', 'VÕ THỊ HƯƠNG'];
    final phones = ['0901234567', '0912345678', '0923456789', '0934567890', '0945678901'];
    final salesData = [
      // Đơn tiền mặt
      {'customer': 0, 'product': 'IPHONE 15 PRO MAX 256GB', 'total': 32000000, 'cost': 28000000, 'method': 'TIỀN MẶT', 'daysAgo': 0},
      {'customer': 1, 'product': 'SAMSUNG S24 ULTRA 256GB', 'total': 28000000, 'cost': 24000000, 'method': 'CHUYỂN KHOẢN', 'daysAgo': 0},
      // Đơn công nợ
      {'customer': 2, 'product': 'IPHONE 14 PRO 128GB', 'total': 21500000, 'cost': 18000000, 'method': 'CÔNG NỢ', 'daysAgo': 1},
      // Đơn trả góp
      {'customer': 3, 'product': 'XIAOMI 14 ULTRA', 'total': 18000000, 'cost': 15000000, 'method': 'TRẢ GÓP', 'daysAgo': 1, 'down': 5000000, 'loan': 13000000, 'bank': 'HD SAISON'},
      // Đơn phụ kiện
      {'customer': 4, 'product': 'TAI NGHE AIRPODS PRO 2, ỐP LƯNG IPHONE 15', 'total': 5950000, 'cost': 4550000, 'method': 'TIỀN MẶT', 'daysAgo': 0},
      {'customer': 0, 'product': 'SẠC NHANH 65W TYPE-C', 'total': 450000, 'cost': 200000, 'method': 'TIỀN MẶT', 'daysAgo': 2},
      {'customer': 1, 'product': 'OPPO RENO 11 PRO', 'total': 10500000, 'cost': 8000000, 'method': 'CHUYỂN KHOẢN', 'daysAgo': 3},
      {'customer': 2, 'product': 'IPHONE 15 PRO MAX 256GB, ỐP LƯNG IPHONE 15', 'total': 32150000, 'cost': 28050000, 'method': 'KẾT HỢP', 'daysAgo': 0, 'cash': 20000000, 'transfer': 12150000},
    ];

    for (var s in salesData) {
      final ci = s['customer'] as int;
      final daysAgo = s['daysAgo'] as int;
      final soldAt = todayMs - daysAgo * 86400000 - _rand.nextInt(43200000);
      final data = <String, dynamic>{
        'customerName': customers[ci],
        'phone': phones[ci],
        'productNames': s['product'],
        'productImeis': '',
        'totalPrice': s['total'],
        'totalCost': s['cost'],
        'discount': 0,
        'paymentMethod': s['method'],
        'sellerName': 'TUẤN',
        'soldAt': soldAt,
        'warranty': '12 tháng',
        'isWalkIn': 0,
        'address': '',
        'notes': '',
        'gifts': '',
        'shopId': shopId,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      };
      if (s['method'] == 'TRẢ GÓP') {
        data['isInstallment'] = 1;
        data['downPayment'] = s['down'];
        data['downPaymentMethod'] = 'TIỀN MẶT';
        data['loanAmount'] = s['loan'];
        data['bankName'] = s['bank'];
      }
      if (s['method'] == 'KẾT HỢP') {
        data['cashAmount'] = s['cash'];
        data['transferAmount'] = s['transfer'];
      }
      await _db.collection('sales').add(EncryptionService.encryptMap(data));
    }
    debugPrint('✅ SeedTestData: 8 sales created');

    // --- REPAIRS (5 đơn sửa chữa - các trạng thái khác nhau) ---
    final repairsData = [
      {'name': 'PHẠM VĂN DŨNG', 'phone': '0956789012', 'model': 'iPhone 13', 'issue': 'Thay màn hình vỡ', 'price': 1500000, 'cost': 800000, 'status': 4, 'daysAgo': 0},
      {'name': 'NGUYỄN THỊ LAN', 'phone': '0967890123', 'model': 'Samsung S23', 'issue': 'Thay pin chai', 'price': 500000, 'cost': 250000, 'status': 4, 'daysAgo': 1},
      {'name': 'TRẦN VĂN HẢI', 'phone': '0978901234', 'model': 'iPhone 14 Pro', 'issue': 'Lỗi Face ID', 'price': 2000000, 'cost': 1200000, 'status': 3, 'daysAgo': 0},
      {'name': 'LÊ THỊ MAI', 'phone': '0989012345', 'model': 'Oppo Find X5', 'issue': 'Thay loa ngoài + mic', 'price': 800000, 'cost': 350000, 'status': 2, 'daysAgo': 1},
      {'name': 'VÕ MINH QUÂN', 'phone': '0990123456', 'model': 'Xiaomi 13T', 'issue': 'Sạc không vào', 'price': 300000, 'cost': 100000, 'status': 1, 'daysAgo': 0},
    ];

    for (var r in repairsData) {
      final daysAgo = r['daysAgo'] as int;
      final createdAt = todayMs - (daysAgo + 1) * 86400000;
      final data = <String, dynamic>{
        'customerName': r['name'],
        'phone': r['phone'],
        'model': r['model'],
        'issue': r['issue'],
        'price': r['price'],
        'cost': r['cost'],
        'status': r['status'],
        'paymentMethod': 'TIỀN MẶT',
        'warranty': '3 tháng',
        'createdAt': createdAt,
        'createdBy': 'TUẤN',
        'shopId': shopId,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      };
      if ((r['status'] as int) >= 2) data['startedAt'] = createdAt + 3600000;
      if ((r['status'] as int) >= 3) data['finishedAt'] = createdAt + 7200000;
      if ((r['status'] as int) == 4) {
        data['deliveredAt'] = todayMs - daysAgo * 86400000;
        data['deliveredBy'] = 'TUẤN';
      }
      await _db.collection('repairs').add(EncryptionService.encryptMap(data));
    }
    debugPrint('✅ SeedTestData: 5 repairs created');

    // --- EXPENSES (6 chi phí) ---
    final expensesData = [
      {'title': 'TIỀN ĐIỆN THÁNG 3', 'amount': 2500000, 'category': 'ĐIỆN NƯỚC', 'method': 'CHUYỂN KHOẢN', 'daysAgo': 0},
      {'title': 'MUA VĂN PHÒNG PHẨM', 'amount': 350000, 'category': 'VĂN PHÒNG', 'method': 'TIỀN MẶT', 'daysAgo': 0},
      {'title': 'TIỀN INTERNET', 'amount': 500000, 'category': 'INTERNET', 'method': 'CHUYỂN KHOẢN', 'daysAgo': 1},
      {'title': 'SỬA MÁY LẠNH', 'amount': 1200000, 'category': 'SỬA CHỮA', 'method': 'TIỀN MẶT', 'daysAgo': 2},
      {'title': 'GỬI XE THÁNG', 'amount': 200000, 'category': 'KHÁC', 'method': 'TIỀN MẶT', 'daysAgo': 3},
      {'title': 'QUẢNG CÁO FB', 'amount': 3000000, 'category': 'QUẢNG CÁO', 'method': 'CHUYỂN KHOẢN', 'daysAgo': 1},
    ];

    for (var e in expensesData) {
      final daysAgo = e['daysAgo'] as int;
      final date = todayMs - daysAgo * 86400000 - _rand.nextInt(43200000);
      final data = {
        'title': e['title'],
        'amount': e['amount'],
        'category': e['category'],
        'paymentMethod': e['method'],
        'date': date,
        'createdAt': date,
        'shopId': shopId,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      };
      await _db.collection('expenses').add(EncryptionService.encryptMap(data));
    }
    debugPrint('✅ SeedTestData: 6 expenses created');

    // --- DEBTS (3 công nợ: 2 khách nợ + 1 nợ NCC) ---
    final debtsData = [
      {'person': 'LÊ HOÀNG NAM', 'phone': '0923456789', 'total': 21500000, 'paid': 0, 'type': 'CUSTOMER_OWES'},
      {'person': 'VŨ THỊ TUYẾT', 'phone': '0911223344', 'total': 5000000, 'paid': 2000000, 'type': 'CUSTOMER_OWES'},
      {'person': 'NCC PHÚC AN MOBILE', 'phone': 'ncc', 'total': 15000000, 'paid': 8000000, 'type': 'SHOP_OWES'},
    ];

    final debtIds = <String>[];
    for (var d in debtsData) {
      final data = {
        'personName': d['person'],
        'phone': d['phone'],
        'totalAmount': d['total'],
        'paidAmount': d['paid'],
        'type': d['type'],
        'status': 'ACTIVE',
        'createdAt': todayMs - 3 * 86400000,
        'shopId': shopId,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      };
      final ref = await _db.collection('debts').add(EncryptionService.encryptMap(data));
      debtIds.add(ref.id);
    }
    debugPrint('✅ SeedTestData: 3 debts created');

    // --- DEBT_PAYMENTS (2 lần thu nợ) ---
    if (debtIds.length >= 2) {
      // Thu nợ VŨ THỊ TUYẾT - đã thu 2 triệu
      final payData1 = {
        'amount': 2000000,
        'debtId': debtIds[1],
        'paidAt': todayMs - 1 * 86400000,
        'paymentMethod': 'TIỀN MẶT',
        'totalDebt': 5000000,
        'alreadyPaid': 0,
        'receivedBy': 'TUẤN',
        'personName': 'VŨ THỊ TUYẾT',
        'debtType': 'CUSTOMER_OWES',
        'shopId': shopId,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      };
      await _db.collection('debt_payments').add(EncryptionService.encryptMap(payData1));

      // Trả NCC 8 triệu
      final payData2 = {
        'amount': 8000000,
        'debtId': debtIds[2],
        'paidAt': todayMs - 2 * 86400000,
        'paymentMethod': 'CHUYỂN KHOẢN',
        'totalDebt': 15000000,
        'alreadyPaid': 0,
        'receivedBy': 'TUẤN',
        'personName': 'NCC PHÚC AN MOBILE',
        'debtType': 'SHOP_OWES',
        'shopId': shopId,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      };
      await _db.collection('debt_payments').add(EncryptionService.encryptMap(payData2));
    }
    debugPrint('✅ SeedTestData: 2 debt_payments created');

    // --- SUPPLIER_IMPORT_HISTORY (2 lần nhập hàng) ---
    final imports = [
      {'supplier': 'NCC PHÚC AN MOBILE', 'products': 'IPHONE 15 PRO MAX 256GB x2', 'total': 56000000, 'method': 'CHUYỂN KHOẢN', 'daysAgo': 3},
      {'supplier': 'NCC LINH KIỆN TÂN BÌNH', 'products': 'MÀN HÌNH IPHONE 13 x5, PIN IPHONE 12 x10', 'total': 6500000, 'method': 'TIỀN MẶT', 'daysAgo': 5},
    ];

    for (var imp in imports) {
      final daysAgo = imp['daysAgo'] as int;
      final data = {
        'supplierName': imp['supplier'],
        'productNames': imp['products'],
        'totalCost': imp['total'],
        'paymentMethod': imp['method'],
        'importDate': todayMs - daysAgo * 86400000,
        'createdAt': todayMs - daysAgo * 86400000,
        'createdBy': 'TUẤN',
        'shopId': shopId,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      };
      await _db.collection('supplier_import_history').add(EncryptionService.encryptMap(data));
    }
    debugPrint('✅ SeedTestData: 2 supplier imports created');

    // --- CASH CLOSINGS (chốt quỹ 2 ngày gần nhất) ---
    final yesterday = DateTime(now.year, now.month, now.day - 1);
    final dayBefore = DateTime(now.year, now.month, now.day - 2);

    await _db.collection('cash_closings').doc('${_fmt(dayBefore)}_$shopId').set({
      'dateKey': _fmt(dayBefore),
      'cashEnd': 25000000,
      'bankEnd': 45000000,
      'note': 'Chốt quỹ ngày ${_fmt(dayBefore)}',
      'isLocked': true,
      'closedBy': 'TUẤN',
      'closedAt': dayBefore.millisecondsSinceEpoch + 72000000,
      'shopId': shopId,
      'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
    });

    await _db.collection('cash_closings').doc('${_fmt(yesterday)}_$shopId').set({
      'dateKey': _fmt(yesterday),
      'cashEnd': 52000000,
      'bankEnd': 38000000,
      'note': 'Chốt quỹ ngày ${_fmt(yesterday)}',
      'isLocked': true,
      'closedBy': 'TUẤN',
      'closedAt': yesterday.millisecondsSinceEpoch + 72000000,
      'shopId': shopId,
      'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
    });
    debugPrint('✅ SeedTestData: 2 cash closings created');

    debugPrint('🎉 SeedTestData: HOÀN TẤT - Tất cả dữ liệu test đã được tạo!');
    debugPrint('📊 Tổng: 10 SP + 8 đơn bán + 5 SC + 6 CP + 3 CN + 2 thu nợ + 2 nhập hàng + 2 chốt quỹ');
  }

  static String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

