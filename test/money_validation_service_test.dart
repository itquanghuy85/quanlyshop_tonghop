// Unit Tests for MoneyValidationService
//
// PURPOSE:
// - Lock down money validation logic
// - Any incorrect change will immediately fail tests
// - Cover all dirty cases: negative, exceed stock, exceed debt
//
// Created: 2026-01-22
// Author: AI Assistant (Phase 5 - Unit Tests)

import 'package:flutter_test/flutter_test.dart';
import 'package:quanlyshop/services/money_validation_service.dart';

void main() {
  // ==========================================================================
  // validateAmount TESTS
  // ==========================================================================
  group('validateAmount', () {
    group('✅ Valid cases', () {
      test('accepts positive amount', () {
        expect(
          () => MoneyValidationService.validateAmount(1000),
          returnsNormally,
        );
      });

      test('accepts zero when allowZero=true', () {
        expect(
          () => MoneyValidationService.validateAmount(0, allowZero: true),
          returnsNormally,
        );
      });

      test('accepts negative when allowNegative=true', () {
        expect(
          () => MoneyValidationService.validateAmount(-500, allowNegative: true),
          returnsNormally,
        );
      });

      test('accepts amount at maxValue boundary', () {
        expect(
          () => MoneyValidationService.validateAmount(1000, maxValue: 1000),
          returnsNormally,
        );
      });

      test('accepts large valid amount (999 billion)', () {
        expect(
          () => MoneyValidationService.validateAmount(999999999999),
          returnsNormally,
        );
      });
    });

    group('❌ Invalid cases - NEGATIVE', () {
      test('rejects negative amount by default', () {
        expect(
          () => MoneyValidationService.validateAmount(-1),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.amountNegative,
            ),
          ),
        );
      });

      test('rejects -1000', () {
        expect(
          () => MoneyValidationService.validateAmount(-1000),
          throwsA(isA<MoneyValidationException>()),
        );
      });

      test('rejects large negative', () {
        expect(
          () => MoneyValidationService.validateAmount(-999999999),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.amountNegative,
            ),
          ),
        );
      });
    });

    group('❌ Invalid cases - ZERO', () {
      test('rejects zero by default', () {
        expect(
          () => MoneyValidationService.validateAmount(0),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.amountZero,
            ),
          ),
        );
      });
    });

    group('❌ Invalid cases - EXCEEDS MAX', () {
      test('rejects amount exceeding default max (999 billion)', () {
        expect(
          () => MoneyValidationService.validateAmount(1000000000000), // 1 trillion
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.amountExceedsMax,
            ),
          ),
        );
      });

      test('rejects amount exceeding custom maxValue', () {
        expect(
          () => MoneyValidationService.validateAmount(101, maxValue: 100),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.amountExceedsMax,
            ),
          ),
        );
      });
    });

    group('validateAmountResult (non-throwing)', () {
      test('returns valid for positive amount', () {
        final result = MoneyValidationService.validateAmountResult(1000);
        expect(result.isValid, isTrue);
        expect(result.error, isNull);
      });

      test('returns invalid for negative amount', () {
        final result = MoneyValidationService.validateAmountResult(-100);
        expect(result.isValid, isFalse);
        expect(result.error, isNotNull);
        expect(result.error!.code, MoneyValidationErrorCode.amountNegative);
      });

      test('throwIfInvalid throws for invalid result', () {
        final result = MoneyValidationService.validateAmountResult(-1);
        expect(() => result.throwIfInvalid(), throwsA(isA<MoneyValidationException>()));
      });

      test('throwIfInvalid does nothing for valid result', () {
        final result = MoneyValidationService.validateAmountResult(100);
        expect(() => result.throwIfInvalid(), returnsNormally);
      });
    });
  });

  // ==========================================================================
  // validateSale TESTS
  // ==========================================================================
  group('validateSale', () {
    group('✅ Valid cases', () {
      test('accepts valid sale with positive price and cost', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 5000000,
            totalCost: 3000000,
          ),
          returnsNormally,
        );
      });

      test('accepts sale with zero cost (gift/promo)', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 1000000,
            totalCost: 0,
          ),
          returnsNormally,
        );
      });

      test('accepts sale with discount less than price', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 5000000,
            totalCost: 3000000,
            discount: 500000,
          ),
          returnsNormally,
        );
      });

      test('accepts sale with discount equal to price (100% off)', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 1000000,
            totalCost: 500000,
            discount: 1000000,
          ),
          returnsNormally,
        );
      });

      test('accepts sale with valid product stock', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 10000000,
            totalCost: 8000000,
            products: [
              const SaleProductValidation(
                id: 'prod_1',
                name: 'iPhone 15',
                requestedQuantity: 1,
                availableQuantity: 5,
              ),
            ],
          ),
          returnsNormally,
        );
      });

      test('accepts sale requesting exact available stock', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 10000000,
            totalCost: 8000000,
            products: [
              const SaleProductValidation(
                id: 'prod_1',
                name: 'iPhone 15',
                requestedQuantity: 3,
                availableQuantity: 3,
              ),
            ],
          ),
          returnsNormally,
        );
      });

      test('accepts installment sale with valid down payment', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 20000000,
            totalCost: 15000000,
            discount: 0,
            isInstallment: true,
            downPayment: 5000000,
            loanAmount: 15000000,
          ),
          returnsNormally,
        );
      });
    });

    group('❌ Invalid cases - PRICE', () {
      test('rejects zero price', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 0,
            totalCost: 0,
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.salePriceZero,
            ),
          ),
        );
      });

      test('rejects negative price', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: -1000000,
            totalCost: 500000,
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.salePriceZero,
            ),
          ),
        );
      });
    });

    group('❌ Invalid cases - COST', () {
      test('rejects negative cost', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 5000000,
            totalCost: -1000000,
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.saleCostNegative,
            ),
          ),
        );
      });
    });

    group('❌ Invalid cases - DISCOUNT', () {
      test('rejects negative discount', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 5000000,
            totalCost: 3000000,
            discount: -100000,
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.amountNegative,
            ),
          ),
        );
      });

      test('rejects discount exceeding total price', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 5000000,
            totalCost: 3000000,
            discount: 6000000,
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.saleDiscountExceedsPrice,
            ),
          ),
        );
      });

      test('rejects discount = price + 1', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 1000000,
            totalCost: 500000,
            discount: 1000001,
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.saleDiscountExceedsPrice,
            ),
          ),
        );
      });
    });

    group('❌ Invalid cases - STOCK (VƯỢT KHO)', () {
      test('rejects product with zero stock (out of stock)', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 10000000,
            totalCost: 8000000,
            products: [
              const SaleProductValidation(
                id: 'prod_1',
                name: 'iPhone 15',
                requestedQuantity: 1,
                availableQuantity: 0,
              ),
            ],
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.saleProductOutOfStock,
            ),
          ),
        );
      });

      test('rejects product with negative stock', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 10000000,
            totalCost: 8000000,
            products: [
              const SaleProductValidation(
                id: 'prod_1',
                name: 'Galaxy S24',
                requestedQuantity: 1,
                availableQuantity: -5,
              ),
            ],
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.saleProductOutOfStock,
            ),
          ),
        );
      });

      test('rejects when requested quantity exceeds available stock', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 50000000,
            totalCost: 40000000,
            products: [
              const SaleProductValidation(
                id: 'prod_1',
                name: 'MacBook Pro',
                requestedQuantity: 10,
                availableQuantity: 3,
              ),
            ],
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.saleQuantityExceedsStock,
            ),
          ),
        );
      });

      test('rejects when one product in list is out of stock', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 30000000,
            totalCost: 25000000,
            products: [
              const SaleProductValidation(
                id: 'prod_1',
                name: 'iPhone 15',
                requestedQuantity: 1,
                availableQuantity: 5,
              ),
              const SaleProductValidation(
                id: 'prod_2',
                name: 'AirPods Pro',
                requestedQuantity: 1,
                availableQuantity: 0, // Out of stock!
              ),
            ],
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.saleProductOutOfStock,
            ),
          ),
        );
      });

      test('error context contains product name and available quantity', () {
        try {
          MoneyValidationService.validateSale(
            totalPrice: 10000000,
            totalCost: 8000000,
            products: [
              const SaleProductValidation(
                id: 'prod_123',
                name: 'iPhone 15 Pro Max',
                requestedQuantity: 5,
                availableQuantity: 2,
              ),
            ],
          );
          fail('Expected MoneyValidationException');
        } on MoneyValidationException catch (e) {
          expect(e.context?['productName'], 'iPhone 15 Pro Max');
          expect(e.context?['available'], 2);
          expect(e.context?['requested'], 5);
        }
      });
    });

    group('❌ Invalid cases - INSTALLMENT', () {
      test('rejects down payment exceeding final price', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 10000000,
            totalCost: 8000000,
            discount: 1000000, // Final = 9M
            isInstallment: true,
            downPayment: 10000000, // > 9M
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.saleDownPaymentExceedsTotal,
            ),
          ),
        );
      });

      test('rejects negative loan amount', () {
        expect(
          () => MoneyValidationService.validateSale(
            totalPrice: 20000000,
            totalCost: 15000000,
            isInstallment: true,
            downPayment: 5000000,
            loanAmount: -1000000,
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.saleLoanAmountInvalid,
            ),
          ),
        );
      });
    });

    group('validateSaleResult (non-throwing)', () {
      test('returns valid for correct sale', () {
        final result = MoneyValidationService.validateSaleResult(
          totalPrice: 5000000,
          totalCost: 3000000,
        );
        expect(result.isValid, isTrue);
      });

      test('returns invalid for zero price', () {
        final result = MoneyValidationService.validateSaleResult(
          totalPrice: 0,
          totalCost: 0,
        );
        expect(result.isValid, isFalse);
        expect(result.error!.code, MoneyValidationErrorCode.salePriceZero);
      });
    });
  });

  // ==========================================================================
  // validateDebtPayment TESTS
  // ==========================================================================
  group('validateDebtPayment', () {
    group('✅ Valid cases', () {
      test('accepts payment less than remaining debt', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 500000,
            totalDebt: 1000000,
            alreadyPaid: 0,
          ),
          returnsNormally,
        );
      });

      test('accepts payment equal to remaining debt (pay off)', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 1000000,
            totalDebt: 1000000,
            alreadyPaid: 0,
          ),
          returnsNormally,
        );
      });

      test('accepts partial payment on partially paid debt', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 300000,
            totalDebt: 1000000,
            alreadyPaid: 500000, // Remaining = 500k
          ),
          returnsNormally,
        );
      });

      test('accepts exact remaining payment', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 200000,
            totalDebt: 1000000,
            alreadyPaid: 800000, // Remaining = 200k
          ),
          returnsNormally,
        );
      });

      test('accepts minimum payment of 1 VND', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 1,
            totalDebt: 1000000,
            alreadyPaid: 0,
          ),
          returnsNormally,
        );
      });
    });

    group('❌ Invalid cases - ZERO PAYMENT', () {
      test('rejects zero payment', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 0,
            totalDebt: 1000000,
            alreadyPaid: 0,
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.debtPaymentZero,
            ),
          ),
        );
      });

      test('rejects negative payment', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: -100000,
            totalDebt: 1000000,
            alreadyPaid: 0,
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.debtPaymentZero,
            ),
          ),
        );
      });
    });

    group('❌ Invalid cases - ALREADY PAID (VƯỢT NỢ)', () {
      test('rejects payment when debt is already fully paid', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 100000,
            totalDebt: 1000000,
            alreadyPaid: 1000000, // Fully paid, remaining = 0
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.debtAlreadyPaid,
            ),
          ),
        );
      });

      test('rejects payment when already overpaid (negative remaining)', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 100000,
            totalDebt: 1000000,
            alreadyPaid: 1500000, // Overpaid, remaining = -500k
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.debtAlreadyPaid,
            ),
          ),
        );
      });
    });

    group('❌ Invalid cases - EXCEEDS REMAINING (VƯỢT NỢ)', () {
      test('rejects payment exceeding remaining debt', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 600000,
            totalDebt: 1000000,
            alreadyPaid: 500000, // Remaining = 500k, paying 600k
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.debtPaymentExceedsRemaining,
            ),
          ),
        );
      });

      test('rejects payment exceeding remaining by 1 VND', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 500001,
            totalDebt: 1000000,
            alreadyPaid: 500000, // Remaining = 500k
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.debtPaymentExceedsRemaining,
            ),
          ),
        );
      });

      test('rejects payment double the remaining debt', () {
        expect(
          () => MoneyValidationService.validateDebtPayment(
            paymentAmount: 400000,
            totalDebt: 1000000,
            alreadyPaid: 800000, // Remaining = 200k, paying 400k
          ),
          throwsA(
            isA<MoneyValidationException>().having(
              (e) => e.code,
              'code',
              MoneyValidationErrorCode.debtPaymentExceedsRemaining,
            ),
          ),
        );
      });

      test('error context contains remaining debt amount', () {
        try {
          MoneyValidationService.validateDebtPayment(
            paymentAmount: 1000000,
            totalDebt: 5000000,
            alreadyPaid: 4500000, // Remaining = 500k
          );
          fail('Expected MoneyValidationException');
        } on MoneyValidationException catch (e) {
          expect(e.context?['remaining'], 500000);
          expect(e.context?['paymentAmount'], 1000000);
          expect(e.context?['totalDebt'], 5000000);
          expect(e.context?['alreadyPaid'], 4500000);
        }
      });
    });

    group('validateDebtPaymentResult (non-throwing)', () {
      test('returns valid for correct payment', () {
        final result = MoneyValidationService.validateDebtPaymentResult(
          paymentAmount: 500000,
          totalDebt: 1000000,
          alreadyPaid: 0,
        );
        expect(result.isValid, isTrue);
      });

      test('returns invalid for exceeding payment', () {
        final result = MoneyValidationService.validateDebtPaymentResult(
          paymentAmount: 1500000,
          totalDebt: 1000000,
          alreadyPaid: 0,
        );
        expect(result.isValid, isFalse);
        expect(
          result.error!.code,
          MoneyValidationErrorCode.debtPaymentExceedsRemaining,
        );
      });
    });
  });

  // ==========================================================================
  // validateDebtCreation TESTS
  // ==========================================================================
  group('validateDebtCreation', () {
    test('accepts positive debt amount', () {
      expect(
        () => MoneyValidationService.validateDebtCreation(totalAmount: 1000000),
        returnsNormally,
      );
    });

    test('rejects zero debt amount', () {
      expect(
        () => MoneyValidationService.validateDebtCreation(totalAmount: 0),
        throwsA(
          isA<MoneyValidationException>().having(
            (e) => e.code,
            'code',
            MoneyValidationErrorCode.debtAmountNegative,
          ),
        ),
      );
    });

    test('rejects negative debt amount', () {
      expect(
        () => MoneyValidationService.validateDebtCreation(totalAmount: -500000),
        throwsA(
          isA<MoneyValidationException>().having(
            (e) => e.code,
            'code',
            MoneyValidationErrorCode.debtAmountNegative,
          ),
        ),
      );
    });
  });

  // ==========================================================================
  // validateStockChange TESTS
  // ==========================================================================
  group('validateStockChange', () {
    test('accepts increase in stock', () {
      expect(
        () => MoneyValidationService.validateStockChange(
          currentQuantity: 10,
          changeAmount: 5,
        ),
        returnsNormally,
      );
    });

    test('accepts decrease within available stock', () {
      expect(
        () => MoneyValidationService.validateStockChange(
          currentQuantity: 10,
          changeAmount: -5,
        ),
        returnsNormally,
      );
    });

    test('accepts decrease to exactly zero', () {
      expect(
        () => MoneyValidationService.validateStockChange(
          currentQuantity: 10,
          changeAmount: -10,
        ),
        returnsNormally,
      );
    });

    test('rejects decrease below zero', () {
      expect(
        () => MoneyValidationService.validateStockChange(
          currentQuantity: 5,
          changeAmount: -10,
        ),
        throwsA(
          isA<MoneyValidationException>().having(
            (e) => e.code,
            'code',
            MoneyValidationErrorCode.stockInsufficientQuantity,
          ),
        ),
      );
    });
  });

  // ==========================================================================
  // validateExpense TESTS
  // ==========================================================================
  group('validateExpense', () {
    test('accepts positive expense', () {
      expect(
        () => MoneyValidationService.validateExpense(amount: 500000),
        returnsNormally,
      );
    });

    test('rejects zero expense', () {
      expect(
        () => MoneyValidationService.validateExpense(amount: 0),
        throwsA(
          isA<MoneyValidationException>().having(
            (e) => e.code,
            'code',
            MoneyValidationErrorCode.expenseAmountZero,
          ),
        ),
      );
    });

    test('rejects negative expense', () {
      expect(
        () => MoneyValidationService.validateExpense(amount: -100000),
        throwsA(
          isA<MoneyValidationException>().having(
            (e) => e.code,
            'code',
            MoneyValidationErrorCode.expenseAmountZero,
          ),
        ),
      );
    });
  });

  // ==========================================================================
  // validateRefund TESTS
  // ==========================================================================
  group('validateRefund', () {
    test('accepts refund less than original', () {
      expect(
        () => MoneyValidationService.validateRefund(
          refundAmount: 500000,
          originalAmount: 1000000,
        ),
        returnsNormally,
      );
    });

    test('accepts refund equal to original (full refund)', () {
      expect(
        () => MoneyValidationService.validateRefund(
          refundAmount: 1000000,
          originalAmount: 1000000,
        ),
        returnsNormally,
      );
    });

    test('rejects refund exceeding original', () {
      expect(
        () => MoneyValidationService.validateRefund(
          refundAmount: 1500000,
          originalAmount: 1000000,
        ),
        throwsA(
          isA<MoneyValidationException>().having(
            (e) => e.code,
            'code',
            MoneyValidationErrorCode.refundExceedsOriginal,
          ),
        ),
      );
    });

    test('rejects zero refund', () {
      expect(
        () => MoneyValidationService.validateRefund(
          refundAmount: 0,
          originalAmount: 1000000,
        ),
        throwsA(
          isA<MoneyValidationException>().having(
            (e) => e.code,
            'code',
            MoneyValidationErrorCode.amountZero,
          ),
        ),
      );
    });
  });

  // ==========================================================================
  // toUserMessage TESTS (Vietnamese messages)
  // ==========================================================================
  group('toUserMessage', () {
    test('returns Vietnamese message for amountNegative', () {
      const e = MoneyValidationException(
        code: MoneyValidationErrorCode.amountNegative,
        message: 'test',
      );
      expect(e.toUserMessage(), 'Số tiền không được âm');
    });

    test('returns Vietnamese message for debtPaymentExceedsRemaining with context', () {
      const e = MoneyValidationException(
        code: MoneyValidationErrorCode.debtPaymentExceedsRemaining,
        message: 'test',
        context: {'remaining': 500000},
      );
      expect(e.toUserMessage(), contains('500000'));
    });

    test('returns Vietnamese message for saleProductOutOfStock with context', () {
      const e = MoneyValidationException(
        code: MoneyValidationErrorCode.saleProductOutOfStock,
        message: 'test',
        context: {'productName': 'iPhone 15'},
      );
      expect(e.toUserMessage(), contains('iPhone 15'));
    });
  });

  // ==========================================================================
  // SaleProductValidation TESTS
  // ==========================================================================
  group('SaleProductValidation', () {
    test('fromProductData creates correct instance', () {
      final product = SaleProductValidation.fromProductData(
        id: 'prod_1',
        name: 'Test Product',
        availableQuantity: 10,
        requestedQuantity: 2,
      );
      expect(product.id, 'prod_1');
      expect(product.name, 'Test Product');
      expect(product.availableQuantity, 10);
      expect(product.requestedQuantity, 2);
    });

    test('fromProductData uses default requestedQuantity of 1', () {
      final product = SaleProductValidation.fromProductData(
        id: 'prod_1',
        name: 'Test Product',
        availableQuantity: 10,
      );
      expect(product.requestedQuantity, 1);
    });
  });
}
