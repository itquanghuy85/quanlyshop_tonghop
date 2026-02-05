import 'package:flutter_test/flutter_test.dart';

/// Unit test kiểm tra logic dòng tiền TRẢ GÓP (Installment)
/// Mô phỏng logic trong cash_closing_view.dart:_analyzeTransactions()
/// 
/// CÁC TRƯỜNG HỢP TEST:
/// 1. Trả góp 1 NH - trả trước tiền mặt
/// 2. Trả góp 1 NH - trả trước chuyển khoản  
/// 3. Trả góp 2 NH - trả trước tiền mặt
/// 4. Ngân hàng tất toán (settlement)
/// 5. Tất toán từng phần
/// 6. Full scenario: Bán + Tất toán trong cùng ngày
void main() {
  group('Installment Cash Flow Tests', () {
    late List<TestSaleOrder> sales;
    late DateTime testDate;
    late DateTime nextDay;

    setUp(() {
      sales = [];
      testDate = DateTime(2026, 1, 15);
      nextDay = DateTime(2026, 1, 16);
    });

    bool isSameDay(int timestamp, DateTime target) {
      final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
      return d.year == target.year &&
          d.month == target.month &&
          d.day == target.day;
    }

    /// Tính toán dòng tiền giống như _analyzeTransactions
    Map<String, int> analyzeTransactions(DateTime now) {
      int cashIn = 0, cashOut = 0, bankIn = 0, bankOut = 0;
      int saleIncome = 0, saleCost = 0;
      int settlementIncome = 0;

      // ===== SALES =====
      for (var s in sales.where((s) => isSameDay(s.soldAt, now))) {
        if (s.paymentMethod == 'CÔNG NỢ') {
          saleIncome += s.totalPrice;
          saleCost += s.totalCost;
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
          // Bán thường
          saleIncome += s.totalPrice;
          saleCost += s.totalCost;
          if (s.paymentMethod == 'TIỀN MẶT') {
            cashIn += s.totalPrice;
          } else {
            bankIn += s.totalPrice;
          }
        }
      }

      // ===== BANK SETTLEMENT =====
      for (var s in sales.where(
        (s) =>
            s.isInstallment &&
            s.settlementReceivedAt != null &&
            isSameDay(s.settlementReceivedAt!, now),
      )) {
        // Clamp để không vượt quá loanAmount
        final amount = s.settlementAmount.clamp(0, s.loanAmount + s.loanAmount2);

        if (amount > 0) {
          settlementIncome += amount;
          bankIn += amount;

          // Giá vốn phần còn lại (khi tất toán)
          final downRatio = s.totalPrice > 0 ? s.downPayment / s.totalPrice : 0.0;
          final remainRatio = 1.0 - downRatio;
          saleCost += (s.totalCost * remainRatio).round();
        }
      }

      final profit = saleIncome + settlementIncome - saleCost;

      return {
        'cashIn': cashIn,
        'cashOut': cashOut,
        'bankIn': bankIn,
        'bankOut': bankOut,
        'saleIncome': saleIncome,
        'settlementIncome': settlementIncome,
        'saleCost': saleCost,
        'profit': profit,
      };
    }

    // ========================================
    // TEST 1: Trả góp 1 NH - trả trước TIỀN MẶT
    // ========================================
    test('T1: Trả góp 1 NH - trả trước tiền mặt', () {
      // Bán iPhone 10tr, giá vốn 7tr
      // Trả trước 3tr tiền mặt, vay NH 7tr
      sales.add(TestSaleOrder(
        customerName: 'KHACH TRA GOP',
        phone: '0911222333',
        productNames: 'IPHONE 15',
        productImeis: '111111111111111',
        totalPrice: 10000000,
        totalCost: 7000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 3000000,
        downPaymentMethod: 'TIỀN MẶT',
        loanAmount: 7000000,
        bankName: 'FE CREDIT',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      final result = analyzeTransactions(testDate);

      // Ngày bán: chỉ nhận 3tr tiền mặt
      expect(result['cashIn'], 3000000, reason: 'TM = 3tr (down payment)');
      expect(result['bankIn'], 0, reason: 'NH = 0 (chưa tất toán)');
      expect(result['saleIncome'], 3000000, reason: 'Doanh thu = 3tr');
      
      // Giá vốn tỷ lệ: 7tr * (3/10) = 2.1tr
      expect(result['saleCost'], 2100000, reason: 'Giá vốn = 2.1tr (tỷ lệ 30%)');
      expect(result['profit'], 900000, reason: 'Lợi nhuận = 3tr - 2.1tr = 900k');
    });

    // ========================================
    // TEST 2: Trả góp 1 NH - trả trước CHUYỂN KHOẢN
    // ========================================
    test('T2: Trả góp 1 NH - trả trước chuyển khoản', () {
      sales.add(TestSaleOrder(
        customerName: 'KHACH TRA GOP 2',
        phone: '0922333444',
        productNames: 'IPHONE 15 PRO',
        productImeis: '222222222222222',
        totalPrice: 20000000,
        totalCost: 15000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 5000000,
        downPaymentMethod: 'CHUYỂN KHOẢN', // Trả trước qua CK
        loanAmount: 15000000,
        bankName: 'HOME CREDIT',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      final result = analyzeTransactions(testDate);

      expect(result['cashIn'], 0, reason: 'TM = 0');
      expect(result['bankIn'], 5000000, reason: 'NH = 5tr (down CK)');
      expect(result['saleIncome'], 5000000, reason: 'Doanh thu = 5tr');
      
      // Giá vốn: 15tr * (5/20) = 3.75tr
      expect(result['saleCost'], 3750000, reason: 'Giá vốn = 3.75tr (25%)');
      expect(result['profit'], 1250000, reason: 'Lợi nhuận = 5tr - 3.75tr = 1.25tr');
    });

    // ========================================
    // TEST 3: Trả góp 2 NGÂN HÀNG
    // ========================================
    test('T3: Trả góp 2 ngân hàng - trả trước tiền mặt', () {
      // Bán iPhone 30tr, giá vốn 22tr
      // Trả trước 6tr tiền mặt
      // NH1 (FE Credit): 14tr
      // NH2 (Home Credit): 10tr
      sales.add(TestSaleOrder(
        customerName: 'KHACH 2 NH',
        phone: '0933444555',
        productNames: 'IPHONE 15 PRO MAX 256GB',
        productImeis: '333333333333333',
        totalPrice: 30000000,
        totalCost: 22000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 6000000,
        downPaymentMethod: 'TIỀN MẶT',
        loanAmount: 14000000,
        bankName: 'FE CREDIT',
        loanAmount2: 10000000,
        bankName2: 'HOME CREDIT',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      final result = analyzeTransactions(testDate);

      expect(result['cashIn'], 6000000, reason: 'TM = 6tr (down)');
      expect(result['bankIn'], 0, reason: 'NH = 0 (chưa tất toán)');
      expect(result['saleIncome'], 6000000, reason: 'Doanh thu = 6tr');
      
      // Giá vốn: 22tr * (6/30) = 4.4tr
      expect(result['saleCost'], 4400000, reason: 'Giá vốn = 4.4tr (20%)');
      expect(result['profit'], 1600000, reason: 'Lợi nhuận = 6tr - 4.4tr = 1.6tr');
    });

    // ========================================
    // TEST 4: Ngân hàng TẤT TOÁN (ngày sau)
    // ========================================
    test('T4: Ngân hàng tất toán - nhận đủ tiền vay', () {
      // Bán trả góp ngày hôm trước
      final sale = TestSaleOrder(
        customerName: 'KHACH TAT TOAN',
        phone: '0944555666',
        productNames: 'SAMSUNG S24',
        productImeis: '444444444444444',
        totalPrice: 20000000,
        totalCost: 14000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 5000000,
        downPaymentMethod: 'TIỀN MẶT',
        loanAmount: 15000000,
        bankName: 'FE CREDIT',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
        // Tất toán ngày hôm sau
        settlementReceivedAt: nextDay.millisecondsSinceEpoch,
        settlementAmount: 15000000, // Nhận đủ
      );
      sales.add(sale);

      // Ngày bán (testDate)
      final day1 = analyzeTransactions(testDate);
      expect(day1['cashIn'], 5000000, reason: 'Ngày 1: TM = 5tr');
      expect(day1['bankIn'], 0, reason: 'Ngày 1: NH = 0');
      expect(day1['saleIncome'], 5000000, reason: 'Ngày 1: Doanh thu = 5tr');
      // Giá vốn: 14tr * (5/20) = 3.5tr
      expect(day1['saleCost'], 3500000, reason: 'Ngày 1: Giá vốn = 3.5tr');
      expect(day1['profit'], 1500000, reason: 'Ngày 1: LN = 5tr - 3.5tr = 1.5tr');

      // Ngày tất toán (nextDay)
      final day2 = analyzeTransactions(nextDay);
      expect(day2['cashIn'], 0, reason: 'Ngày 2: TM = 0');
      expect(day2['bankIn'], 15000000, reason: 'Ngày 2: NH = 15tr (tất toán)');
      expect(day2['settlementIncome'], 15000000, reason: 'Ngày 2: Settlement = 15tr');
      // Giá vốn còn lại: 14tr * (1 - 5/20) = 14tr * 0.75 = 10.5tr
      expect(day2['saleCost'], 10500000, reason: 'Ngày 2: Giá vốn còn lại = 10.5tr');
      expect(day2['profit'], 4500000, reason: 'Ngày 2: LN = 15tr - 10.5tr = 4.5tr');

      // TỔNG 2 NGÀY
      final totalProfit = day1['profit']! + day2['profit']!;
      final totalSaleCost = day1['saleCost']! + day2['saleCost']!;
      // Lợi nhuận gộp = 20tr - 14tr = 6tr
      // Day1: 900k, Day2: 4.5tr + ... 
      // Thực tế profit = saleIncome + settlementIncome - saleCost
      // Day1: 5tr - 3.5tr = 1.5tr (không phải 900k vì giá vốn 3.5tr)
      // Wait, kiểm tra lại: 5tr * 0.25 = 1.25tr giá vốn? No...
      // ratio = 5/20 = 0.25, cost = 14tr * 0.25 = 3.5tr
      // Day1: profit = 5tr - 3.5tr = 1.5tr
      // Day2: profit = 15tr - 10.5tr = 4.5tr
      // Total = 6tr
      expect(totalProfit, 6000000, reason: 'Tổng LN = 1.5tr + 4.5tr = 6tr');
      expect(totalSaleCost, 14000000, reason: 'Tổng giá vốn = 14tr');
    });

    // ========================================
    // TEST 5: Tất toán từng phần (NH trừ phí)
    // ========================================
    test('T5: Tất toán từng phần - NH giữ lại phí', () {
      final sale = TestSaleOrder(
        customerName: 'KHACH PHI NH',
        phone: '0955666777',
        productNames: 'OPPO FIND X7',
        productImeis: '555555555555555',
        totalPrice: 15000000,
        totalCost: 10000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 3000000,
        downPaymentMethod: 'TIỀN MẶT',
        loanAmount: 12000000,
        bankName: 'HD SAISON',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
        // Tất toán cùng ngày nhưng NH giữ lại 500k phí
        settlementReceivedAt: testDate.millisecondsSinceEpoch,
        settlementAmount: 11500000, // Nhận 11.5tr (trừ 500k phí)
        settlementFee: 500000,
      );
      sales.add(sale);

      final result = analyzeTransactions(testDate);

      // Down payment: 3tr tiền mặt
      expect(result['cashIn'], 3000000, reason: 'TM = 3tr');
      
      // Settlement: 11.5tr (đã trừ phí)
      // Nhưng clamp theo loanAmount = 12tr nên chỉ tính 11.5tr
      expect(result['bankIn'], 11500000, reason: 'NH = 11.5tr (settlement - phí)');
      
      expect(result['saleIncome'], 3000000, reason: 'Doanh thu ngày bán = 3tr');
      expect(result['settlementIncome'], 11500000, reason: 'Settlement = 11.5tr');
      
      // Tổng giá vốn = 10tr (đầy đủ vì cả down và settlement cùng ngày)
      // Down: 10tr * 0.2 = 2tr
      // Settlement: 10tr * 0.8 = 8tr
      expect(result['saleCost'], 10000000, reason: 'Giá vốn = 10tr');
      
      // Lợi nhuận = 3tr + 11.5tr - 10tr = 4.5tr
      expect(result['profit'], 4500000, reason: 'LN = 14.5tr - 10tr = 4.5tr');
    });

    // ========================================
    // TEST 6: Full scenario - nhiều đơn trả góp
    // ========================================
    test('T6: Full scenario - 1NH tiền mặt, 1NH CK, 2NH, tất toán', () {
      // Đơn 1: Trả góp 1 NH, down tiền mặt 3tr, vay 7tr
      sales.add(TestSaleOrder(
        customerName: 'KHACH A',
        phone: '0901111111',
        productNames: 'IPHONE A',
        productImeis: 'AAAAAAAAAAAAA',
        totalPrice: 10000000,
        totalCost: 7000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 3000000,
        downPaymentMethod: 'TIỀN MẶT',
        loanAmount: 7000000,
        bankName: 'FE CREDIT',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      // Đơn 2: Trả góp 1 NH, down CK 5tr, vay 15tr
      sales.add(TestSaleOrder(
        customerName: 'KHACH B',
        phone: '0902222222',
        productNames: 'IPHONE B',
        productImeis: 'BBBBBBBBBBBBB',
        totalPrice: 20000000,
        totalCost: 14000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 5000000,
        downPaymentMethod: 'CHUYỂN KHOẢN',
        loanAmount: 15000000,
        bankName: 'HOME CREDIT',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      // Đơn 3: Trả góp 2 NH, down TM 10tr, NH1: 15tr, NH2: 5tr
      sales.add(TestSaleOrder(
        customerName: 'KHACH C',
        phone: '0903333333',
        productNames: 'IPHONE C',
        productImeis: 'CCCCCCCCCCCCC',
        totalPrice: 30000000,
        totalCost: 20000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 10000000,
        downPaymentMethod: 'TIỀN MẶT',
        loanAmount: 15000000,
        bankName: 'FE CREDIT',
        loanAmount2: 5000000,
        bankName2: 'HD SAISON',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      // Đơn 4: Đơn cũ được tất toán hôm nay (đã bán hôm qua)
      final yesterday = testDate.subtract(const Duration(days: 1));
      sales.add(TestSaleOrder(
        customerName: 'KHACH D',
        phone: '0904444444',
        productNames: 'SAMSUNG D',
        productImeis: 'DDDDDDDDDDDDD',
        totalPrice: 15000000,
        totalCost: 10000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 5000000,
        downPaymentMethod: 'TIỀN MẶT',
        loanAmount: 10000000,
        bankName: 'MCREDIT',
        sellerName: 'NV1',
        soldAt: yesterday.millisecondsSinceEpoch, // Bán hôm qua
        settlementReceivedAt: testDate.millisecondsSinceEpoch, // Tất toán hôm nay
        settlementAmount: 10000000,
      ));

      final result = analyzeTransactions(testDate);

      // === TIỀN MẶT ===
      // Đơn 1: 3tr (down TM)
      // Đơn 3: 10tr (down TM)
      // Tổng TM = 13tr
      expect(result['cashIn'], 13000000, reason: 'TM = 3tr + 10tr = 13tr');

      // === NGÂN HÀNG ===
      // Đơn 2: 5tr (down CK)
      // Đơn 4: 10tr (tất toán)
      // Tổng NH = 15tr
      expect(result['bankIn'], 15000000, reason: 'NH = 5tr + 10tr = 15tr');

      // === DOANH THU ===
      // Đơn 1: 3tr
      // Đơn 2: 5tr
      // Đơn 3: 10tr
      // Tổng = 18tr (chưa tính tất toán)
      expect(result['saleIncome'], 18000000, reason: 'DT = 3+5+10 = 18tr');

      // === SETTLEMENT ===
      // Đơn 4: 10tr
      expect(result['settlementIncome'], 10000000, reason: 'Settlement = 10tr');

      // === GIÁ VỐN ===
      // Đơn 1: 7tr * 30% = 2.1tr
      // Đơn 2: 14tr * 25% = 3.5tr
      // Đơn 3: 20tr * 33.33% = 6.67tr
      // Đơn 4 (tất toán): 10tr * (1 - 5/15) = 10tr * 66.67% = 6.67tr
      // Tổng ≈ 18.94tr (có làm tròn)
      const expectedCost = 2100000 + 3500000 + 6666667 + 6666667; // ~18.93tr
      expect(result['saleCost'], closeTo(expectedCost, 10), 
          reason: 'Giá vốn ≈ 18.93tr');

      // === LỢI NHUẬN ===
      // 18tr + 10tr - 18.93tr ≈ 9.07tr
      expect(result['profit'], closeTo(9066666, 10), reason: 'LN ≈ 9.07tr');
    });

    // ========================================
    // TEST 7: Không có down payment (100% vay)
    // ========================================
    test('T7: 100% vay NH - không trả trước', () {
      sales.add(TestSaleOrder(
        customerName: 'KHACH 100% VAY',
        phone: '0966777888',
        productNames: 'XIAOMI 14',
        productImeis: '666666666666666',
        totalPrice: 8000000,
        totalCost: 6000000,
        paymentMethod: 'TRẢ GÓP (NH)',
        isInstallment: true,
        downPayment: 0, // Không trả trước
        downPaymentMethod: null,
        loanAmount: 8000000, // Vay 100%
        bankName: 'FE CREDIT',
        sellerName: 'NV1',
        soldAt: testDate.millisecondsSinceEpoch,
      ));

      final result = analyzeTransactions(testDate);

      expect(result['cashIn'], 0, reason: 'TM = 0 (không down)');
      expect(result['bankIn'], 0, reason: 'NH = 0 (chưa tất toán)');
      expect(result['saleIncome'], 0, reason: 'Doanh thu = 0');
      expect(result['saleCost'], 0, reason: 'Giá vốn = 0');
      expect(result['profit'], 0, reason: 'LN = 0 (chờ tất toán)');
    });
  });
}

/// Định nghĩa SaleOrder đơn giản cho test trả góp
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
  final String? bankName;
  final int loanAmount2;
  final String? bankName2;
  final int? settlementReceivedAt;
  final int settlementAmount;
  final int settlementFee;

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
    this.bankName,
    this.loanAmount2 = 0,
    this.bankName2,
    this.settlementReceivedAt,
    this.settlementAmount = 0,
    this.settlementFee = 0,
  });
}
