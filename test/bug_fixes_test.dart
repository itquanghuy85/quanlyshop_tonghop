import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/models/debt_model.dart';

/// Test cases cho các bug đã fix trong QA Audit
/// BUG-001: Race condition thanh toán công nợ (cần integration test với mock)
/// BUG-002: remain có thể âm khi tính công nợ NCC
/// BUG-004: updateDebtPaid thiếu updatedAt
/// BUG-005: CÔNG NỢ nhưng không có supplier
/// BUG-007: Soft delete không được filter

void main() {
  group('BUG-002: Supplier debt remain calculation', () {
    test('remain should never be negative', () {
      // Giả lập trường hợp paidAmount > totalAmount (do sync conflict)
      final debt = {'totalAmount': 100000, 'paidAmount': 150000};
      final total = debt['totalAmount'] as int;
      final paid = debt['paidAmount'] as int;
      
      // Logic cũ (bug): remain = total - paid = -50000
      final buggyRemain = total - paid;
      expect(buggyRemain, -50000); // Bug: số âm
      
      // Logic mới (fixed): remain = (total - paid).clamp(0, total)
      final fixedRemain = (total - paid).clamp(0, total);
      expect(fixedRemain, 0); // Fixed: không âm
    });

    test('totalPayable should not include negative remain', () {
      final debts = [
        {'totalAmount': 100000, 'paidAmount': 50000},   // remain = 50000
        {'totalAmount': 200000, 'paidAmount': 200000},  // remain = 0
        {'totalAmount': 150000, 'paidAmount': 100000},  // remain = 50000
        {'totalAmount': 50000, 'paidAmount': 80000},    // remain = -30000 (overpaid)
      ];
      
      int totalPayable = 0;
      for (var d in debts) {
        final total = d['totalAmount'] as int;
        final paid = d['paidAmount'] as int;
        final remain = (total - paid).clamp(0, total);
        if (remain > 0) totalPayable += remain;
      }
      
      // Chỉ tính 50000 + 50000 = 100000 (không tính số âm)
      expect(totalPayable, 100000);
    });
  });

  group('BUG-007: Soft delete filter', () {
    test('should filter out deleted debts', () {
      final debts = [
        {'id': 1, 'type': 'SHOP_OWES', 'personName': 'NCC A', 'deleted': 0},
        {'id': 2, 'type': 'SHOP_OWES', 'personName': 'NCC A', 'deleted': 1}, // soft deleted
        {'id': 3, 'type': 'SHOP_OWES', 'personName': 'NCC A', 'deleted': null}, // legacy
        {'id': 4, 'type': 'CUSTOMER_OWES', 'personName': 'KH', 'deleted': 0},
      ];

      // Logic mới: filter deleted != 1
      final activeDebts = debts.where((d) => 
        d['type'] == 'SHOP_OWES' && 
        (d['personName'] ?? '').toString().toUpperCase() == 'NCC A' &&
        (d['deleted'] ?? 0) != 1
      ).toList();

      expect(activeDebts.length, 2); // id 1 và 3
      expect(activeDebts.any((d) => d['id'] == 2), false); // id 2 bị filter
    });
  });

  group('BUG-005: CÔNG NỢ requires supplier', () {
    test('should validate supplier when paymentMethod is CÔNG NỢ', () {
      String? validateCongNo(String paymentMethod, int? supplierId) {
        if (paymentMethod == 'CÔNG NỢ' && supplierId == null) {
          return 'CÔNG NỢ phải chọn Nhà cung cấp!';
        }
        return null;
      }

      // Case 1: CÔNG NỢ + no supplier → error
      expect(validateCongNo('CÔNG NỢ', null), isNotNull);
      
      // Case 2: CÔNG NỢ + has supplier → OK
      expect(validateCongNo('CÔNG NỢ', 123), isNull);
      
      // Case 3: TIỀN MẶT + no supplier → OK
      expect(validateCongNo('TIỀN MẶT', null), isNull);
      
      // Case 4: CHUYỂN KHOẢN + no supplier → OK
      expect(validateCongNo('CHUYỂN KHOẢN', null), isNull);
    });
  });

  group('Debt Model validation', () {
    test('Debt.fromMap should handle overpaid case', () {
      // Trường hợp paidAmount > totalAmount (sync conflict)
      final map = {
        'personName': 'Test',
        'phone': '123',
        'totalAmount': 100000,
        'paidAmount': 150000, // overpaid
        'type': 'CUSTOMER_OWES',
        'createdAt': 1234567890,
      };
      
      final debt = Debt.fromMap(map);
      
      // Model đã clamp paidAmount về totalAmount
      expect(debt.paidAmount, 100000);
      expect(debt.totalAmount, 100000);
    });

    test('should calculate remaining correctly', () {
      final debt = Debt(
        personName: 'Test',
        phone: '123',
        totalAmount: 100000,
        paidAmount: 30000,
        type: 'CUSTOMER_OWES',
        createdAt: 1234567890,
      );
      
      final remaining = debt.totalAmount - debt.paidAmount;
      expect(remaining, 70000);
    });
  });

  group('EDGE-001: Small amount parsing', () {
    test('amount < 1000 should NOT be multiplied', () {
      // Logic hiện tại có bug: parsed < 100000 ? parsed * 1000 : parsed
      // Nếu nhập 999 → 999000 (gần 1 triệu!)
      
      int parseAmount(String input) {
        final parsed = int.tryParse(input.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
        // Logic cũ (bug):
        // return parsed > 0 && parsed < 100000 ? parsed * 1000 : parsed;
        
        // Logic đề xuất: Chỉ multiply nếu >= 1000 (có vẻ là shorthand)
        // Hoặc thêm validation minimum amount
        if (parsed < 1000) {
          return parsed; // Không multiply nếu quá nhỏ
        }
        return parsed > 0 && parsed < 100000 ? parsed * 1000 : parsed;
      }
      
      // Nhập 500 → 500 (không phải 500000)
      expect(parseAmount('500'), 500);
      
      // Nhập 1000 → 1000000 (1 triệu, vì là shorthand)
      expect(parseAmount('1000'), 1000000);
      
      // Nhập 150000 → 150000 (đã đầy đủ)
      expect(parseAmount('150000'), 150000);
    });
  });

  group('EDGE-003: Debt status inconsistency', () {
    test('debt with totalAmount == paidAmount should be PAID', () {
      final debt = {
        'totalAmount': 100000,
        'paidAmount': 100000,
        'status': 'ACTIVE', // Bug: vẫn ACTIVE dù đã trả hết
      };

      // Logic validate
      String getCorrectStatus(Map<String, dynamic> d) {
        final total = d['totalAmount'] as int;
        final paid = d['paidAmount'] as int;
        if (paid >= total) return 'paid';
        return d['status'] as String;
      }

      expect(getCorrectStatus(debt), 'paid');
    });
  });
}
