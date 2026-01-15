import 'package:flutter_test/flutter_test.dart';

/// Định nghĩa SaleOrder đơn giản cho test (tránh phụ thuộc database)
class TestSaleOrder {
  final String customerName;
  final String phone;
  final String productNames;
  final String productImeis;
  final int totalPrice;
  final int totalCost;
  final String paymentMethod;
  final String sellerName;
  final int soldAt;
  final bool isInstallment;
  final int downPayment;
  final String? downPaymentMethod;
  final int loanAmount;

  TestSaleOrder({
    required this.customerName,
    required this.phone,
    required this.productNames,
    required this.productImeis,
    required this.totalPrice,
    required this.totalCost,
    required this.paymentMethod,
    required this.sellerName,
    required this.soldAt,
    this.isInstallment = false,
    this.downPayment = 0,
    this.downPaymentMethod,
    this.loanAmount = 0,
  });
}

/// Unit test kiểm tra logic tính toán dòng tiền (Cash Flow Analysis)
/// Mô phỏng logic trong cash_closing_view.dart:_analyzeTransactions()
/// 
/// QUAN TRỌNG: Đây là test logic tính toán, không test database hay Firestore
void main() {
  group('Cash Flow Analysis Logic Tests', () {
    late List<TestSaleOrder> sales;
    late List<Map<String, dynamic>> expenses;
    late List<Map<String, dynamic>> debtPayments;
    late DateTime testDate;

    setUp(() {
      sales = [];
      expenses = [];
      debtPayments = [];
      testDate = DateTime(2026, 1, 15);
    });

    bool isSameDay(int timestamp, DateTime target) {
      final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return d.year == target.year &&
          d.month == target.month &&
          d.day == target.day;
    }

    /// Tính toán dòng tiền giống như _analyzeTransactions trong cash_closing_view.dart
    Map<String, int> analyzeTransactions(DateTime now) {
      int cashIn = 0, cashOut = 0, bankIn = 0, bankOut = 0;
      int saleIncome = 0, saleCost = 0;
      int saleDebt = 0;
      int debtCollected = 0;
      int expenseOut = 0;

      // ===== SALES (ACCRUAL BASIS) =====
      for (var s in sales.where((s) => isSameDay(s.soldAt, now))) {
        if (s.paymentMethod == 'CÔNG NỢ') {
          // K3: Công nợ - tính vào doanh thu và giá vốn (accrual basis)
          // Nhưng KHÔNG tăng quỹ tiền mặt/ngân hàng
          saleIncome += s.totalPrice;
          saleCost += s.totalCost;
          saleDebt += s.totalPrice;
          continue;
        }

        if (s.isInstallment) {
          // Trả góp: chỉ tính phần down vào cashIn/bankIn hôm nay
          final paidToday = s.downPayment;
          saleIncome += paidToday;
          
          // Giá vốn theo tỷ lệ đã thu
          final ratio = s.totalPrice > 0 ? paidToday / s.totalPrice : 0.0;
          saleCost += (s.totalCost * ratio).round();

          if (s.paymentMethod == 'TIỀN MẶT' || s.downPaymentMethod == 'TIỀN MẶT') {
            cashIn += paidToday;
          } else {
            bankIn += paidToday;
          }
        } else {
          // Bán thường - tính đầy đủ
          saleIncome += s.totalPrice;
          saleCost += s.totalCost;

          if (s.paymentMethod == 'TIỀN MẶT') {
            cashIn += s.totalPrice;
          } else {
            bankIn += s.totalPrice;
          }
        }
      }

      // ===== EXPENSES =====
      for (var e in expenses.where(
        (e) => e['date'] != null && isSameDay(e['date'] as int, now),
      )) {
        final amount = e['amount'] as int? ?? 0;
        final method = e['paymentMethod'] as String? ?? 'TIỀN MẶT';
        final category = (e['category'] ?? '').toString().toUpperCase();

        final isImport =
            category.contains('NHẬP') ||
            category.contains('LINH KIỆN') ||
            category.contains('PURCHASE');

        if (method == 'TIỀN MẶT') {
          cashOut += amount;
        } else {
          bankOut += amount;
        }

        if (!isImport) {
          expenseOut += amount;
        }
      }

      // ===== DEBTS =====
      for (var p in debtPayments.where(
        (p) => p['paidAt'] != null && isSameDay(p['paidAt'] as int, now),
      )) {
        final amount = p['amount'] as int? ?? 0;
        final method = p['paymentMethod'] as String? ?? 'TIỀN MẶT';

        if (p['debtType'] == 'SHOP_OWES') {
          // Thanh toán NCC - tính vào chi tiền
          if (method == 'TIỀN MẶT') {
            cashOut += amount;
          } else {
            bankOut += amount;
          }
        } else {
          // Thu nợ khách hàng - CHỈ tăng quỹ tiền
          debtCollected += amount;
          if (method == 'TIỀN MẶT') {
            cashIn += amount;
          } else {
            bankIn += amount;
          }
        }
      }

      // Lợi nhuận = Doanh thu - Chi phí - Giá vốn (ACCRUAL BASIS)
      // debtCollected KHÔNG ảnh hưởng lợi nhuận vì doanh thu đã tính ở K3
      final profit = saleIncome - expenseOut - saleCost;

      return {
        'cashIn': cashIn,
        'cashOut': cashOut,
        'bankIn': bankIn,
        'bankOut': bankOut,
        'saleIncome': saleIncome,
        'saleCost': saleCost,
        'saleDebt': saleDebt,
        'debtCollected': debtCollected,
        'expenseOut': expenseOut,
        'profit': profit,
      };
    }

    test('K1: Bán hàng tiền mặt - tăng cashIn', () {
      // Bán iPhone 5 triệu, giá vốn 3 triệu, thanh toán tiền mặt
      sales.add(TestSaleOrder(
        customerName: 'KHACH TEST',
        phone: '0912345678',
        productNames: 'IPHONE TEST',
        productImeis: '111111111111111',
        totalPrice: 5000000,
        totalCost: 3000000,
        paymentMethod: 'TIỀN MẶT',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      final result = analyzeTransactions(testDate);

      expect(result['cashIn'], 5000000, reason: 'Tiền mặt thu vào = giá bán');
      expect(result['bankIn'], 0, reason: 'Ngân hàng không đổi');
      expect(result['saleIncome'], 5000000, reason: 'Doanh thu = giá bán');
      expect(result['saleCost'], 3000000, reason: 'Giá vốn = 3tr');
      expect(result['profit'], 2000000, reason: 'Lợi nhuận = 5tr - 3tr = 2tr');
    });

    test('K2: Bán hàng chuyển khoản - tăng bankIn', () {
      sales.add(TestSaleOrder(
        customerName: 'KHACH TEST',
        phone: '0912345678',
        productNames: 'IPHONE TEST',
        productImeis: '111111111111111',
        totalPrice: 5000000,
        totalCost: 3000000,
        paymentMethod: 'CHUYỂN KHOẢN',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      final result = analyzeTransactions(testDate);

      expect(result['cashIn'], 0, reason: 'Tiền mặt không đổi');
      expect(result['bankIn'], 5000000, reason: 'Ngân hàng thu vào = giá bán');
      expect(result['profit'], 2000000, reason: 'Lợi nhuận = 5tr - 3tr = 2tr');
    });

    test('K3: Bán công nợ - KHÔNG tăng quỹ nhưng VẪN tính doanh thu và giá vốn', () {
      sales.add(TestSaleOrder(
        customerName: 'KHACH NO',
        phone: '0987654321',
        productNames: 'IPHONE TEST',
        productImeis: '222222222222222',
        totalPrice: 6000000,
        totalCost: 4000000,
        paymentMethod: 'CÔNG NỢ',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      final result = analyzeTransactions(testDate);

      expect(result['cashIn'], 0, reason: 'Tiền mặt KHÔNG tăng khi bán công nợ');
      expect(result['bankIn'], 0, reason: 'Ngân hàng KHÔNG tăng khi bán công nợ');
      expect(result['saleIncome'], 6000000, reason: 'Doanh thu VẪN TÍNH = 6tr (Accrual)');
      expect(result['saleCost'], 4000000, reason: 'Giá vốn VẪN TÍNH = 4tr');
      expect(result['saleDebt'], 6000000, reason: 'Công nợ = 6tr');
      expect(result['profit'], 2000000, reason: 'Lợi nhuận = 6tr - 4tr = 2tr');
    });

    test('K4: Chi phí điện nước - giảm bankOut', () {
      expenses.add({
        'title': 'TIỀN ĐIỆN',
        'amount': 500000,
        'date': testDate.millisecondsSinceEpoch,
        'category': 'ĐIỆN NƯỚC',
        'paymentMethod': 'CHUYỂN KHOẢN',
      });

      final result = analyzeTransactions(testDate);

      expect(result['cashOut'], 0, reason: 'Tiền mặt không đổi');
      expect(result['bankOut'], 500000, reason: 'Ngân hàng chi ra = 500k');
      expect(result['expenseOut'], 500000, reason: 'Chi phí = 500k');
      expect(result['profit'], -500000, reason: 'Lỗ 500k vì chỉ có chi phí');
    });

    test('K5: Thu nợ - CHỈ tăng quỹ, KHÔNG tăng doanh thu/lợi nhuận', () {
      // Đầu tiên bán công nợ (K3) - tính vào doanh thu
      sales.add(TestSaleOrder(
        customerName: 'KHACH NO',
        phone: '0987654321',
        productNames: 'IPHONE TEST',
        productImeis: '222222222222222',
        totalPrice: 6000000,
        totalCost: 4000000,
        paymentMethod: 'CÔNG NỢ',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      // Sau đó thu nợ (K5) - CHỈ tăng quỹ
      debtPayments.add({
        'amount': 3000000,
        'paidAt': testDate.millisecondsSinceEpoch,
        'paymentMethod': 'CHUYỂN KHOẢN',
        'debtType': 'CUSTOMER_OWES',
      });

      final result = analyzeTransactions(testDate);

      // K3: Bán công nợ → cashIn = 0, bankIn = 0, nhưng doanh thu = 6tr
      // K5: Thu nợ → bankIn = 3tr (CHỈ tăng quỹ)
      expect(result['cashIn'], 0, reason: 'Tiền mặt = 0');
      expect(result['bankIn'], 3000000, reason: 'Ngân hàng thu nợ = 3tr');
      expect(result['debtCollected'], 3000000, reason: 'Thu nợ = 3tr');
      expect(result['saleIncome'], 6000000, reason: 'Doanh thu = 6tr (từ K3)');
      expect(result['profit'], 2000000, reason: 'Lợi nhuận = 6tr - 4tr = 2tr (thu nợ KHÔNG tăng thêm)');
    });

    test('K6: Nhập hàng tiền mặt - giảm cashOut (expense category NHẬP HÀNG)', () {
      expenses.add({
        'title': 'NHẬP IPHONE',
        'amount': 3000000,
        'date': testDate.millisecondsSinceEpoch,
        'category': 'NHẬP HÀNG',
        'paymentMethod': 'TIỀN MẶT',
      });

      final result = analyzeTransactions(testDate);

      expect(result['cashOut'], 3000000, reason: 'Tiền mặt chi ra = 3tr');
      expect(result['bankOut'], 0, reason: 'Ngân hàng không đổi');
      // NHẬP HÀNG không tính vào expenseOut
      expect(result['expenseOut'], 0, reason: 'Chi phí = 0 (nhập hàng không phải expense)');
      expect(result['profit'], 0, reason: 'Lợi nhuận = 0 (chưa bán)');
    });

    test('FULL SCENARIO: Kịch bản test hoàn chỉnh', () {
      // BƯỚC 2: Bán hàng tiền mặt 5tr (giá vốn 3tr)
      sales.add(TestSaleOrder(
        customerName: 'KHACH TEST',
        phone: '0912345678',
        productNames: 'IPHONE TEST 01',
        productImeis: '111111111111111',
        totalPrice: 5000000,
        totalCost: 3000000,
        paymentMethod: 'TIỀN MẶT',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      // BƯỚC 3: Chi phí điện 500k (chuyển khoản)
      expenses.add({
        'title': 'TIỀN ĐIỆN',
        'amount': 500000,
        'date': testDate.millisecondsSinceEpoch,
        'category': 'ĐIỆN NƯỚC',
        'paymentMethod': 'CHUYỂN KHOẢN',
      });

      // BƯỚC 4: Bán công nợ 6tr (giá vốn 4tr)
      sales.add(TestSaleOrder(
        customerName: 'KHACH NO',
        phone: '0987654321',
        productNames: 'IPHONE TEST 02',
        productImeis: '222222222222222',
        totalPrice: 6000000,
        totalCost: 4000000,
        paymentMethod: 'CÔNG NỢ',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      // BƯỚC 5: Thu nợ 3tr (chuyển khoản)
      debtPayments.add({
        'amount': 3000000,
        'paidAt': testDate.millisecondsSinceEpoch,
        'paymentMethod': 'CHUYỂN KHOẢN',
        'debtType': 'CUSTOMER_OWES',
      });

      final result = analyzeTransactions(testDate);

      // Kiểm tra quỹ tiền mặt
      // cashIn = 5tr (bán hàng), cashOut = 0
      expect(result['cashIn'], 5000000, reason: 'TM thu vào: 5tr từ bán hàng');
      expect(result['cashOut'], 0, reason: 'TM chi ra: 0');

      // Kiểm tra quỹ ngân hàng
      // bankIn = 3tr (thu nợ), bankOut = 500k (chi phí điện)
      expect(result['bankIn'], 3000000, reason: 'NH thu vào: 3tr từ thu nợ');
      expect(result['bankOut'], 500000, reason: 'NH chi ra: 500k tiền điện');

      // Kiểm tra doanh thu (ACCRUAL BASIS - bao gồm cả công nợ)
      // saleIncome = 5tr (K2) + 6tr (K4) = 11tr
      expect(result['saleIncome'], 11000000, reason: 'Doanh thu: 5tr + 6tr = 11tr');

      // Kiểm tra giá vốn
      // saleCost = 3tr + 4tr = 7tr
      expect(result['saleCost'], 7000000, reason: 'Giá vốn: 3tr + 4tr = 7tr');

      // Kiểm tra chi phí
      expect(result['expenseOut'], 500000, reason: 'Chi phí: 500k');

      // Kiểm tra lợi nhuận (ACCRUAL BASIS)
      // profit = 11tr (doanh thu) - 500k (chi phí) - 7tr (giá vốn) = 3.5tr
      expect(result['profit'], 3500000, reason: 'Lợi nhuận: 11tr - 500k - 7tr = 3.5tr');

      // Kiểm tra thu nợ KHÔNG tăng thêm lợi nhuận
      expect(result['debtCollected'], 3000000, reason: 'Thu nợ: 3tr');
    });

    test('Trả góp - chỉ tính phần trả trước vào cashIn/bankIn', () {
      sales.add(TestSaleOrder(
        customerName: 'KHACH TRA GOP',
        phone: '0911222333',
        productNames: 'IPHONE TRA GOP',
        productImeis: '333333333333333',
        totalPrice: 10000000,
        totalCost: 7000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 3000000,
        downPaymentMethod: 'TIỀN MẶT',
        loanAmount: 7000000,
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      final result = analyzeTransactions(testDate);

      // Chỉ tính phần down payment
      expect(result['cashIn'], 3000000, reason: 'TM thu vào: 3tr (down payment)');
      expect(result['bankIn'], 0, reason: 'NH thu vào: 0');
      expect(result['saleIncome'], 3000000, reason: 'Doanh thu hôm nay: 3tr');
      
      // Giá vốn theo tỷ lệ: 7tr * (3tr / 10tr) = 2.1tr
      expect(result['saleCost'], 2100000, reason: 'Giá vốn tỷ lệ: 7tr * 30% = 2.1tr');
      
      // Lợi nhuận = 3tr - 2.1tr = 900k
      expect(result['profit'], 900000, reason: 'Lợi nhuận: 3tr - 2.1tr = 900k');
    });
  });
}
