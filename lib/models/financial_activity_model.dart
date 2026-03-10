/// Model lưu trữ nhật ký hoạt động tài chính
/// Ghi lại mọi thay đổi về tiền: bán hàng, nhập hàng, chi phí, thu nợ, tất toán...
class FinancialActivity {
  int? id;
  String? firestoreId;

  // Loại hoạt động
  String
  activityType; // SALE, PURCHASE, EXPENSE, DEBT_COLLECT, DEBT_PAY, SETTLEMENT, REFUND, ADJUSTMENT

  // Thông tin giao dịch
  int amount; // Số tiền (dương = thu, âm = chi)
  String direction; // IN (thu) / OUT (chi)
  String paymentMethod; // TIỀN MẶT, CHUYỂN KHOẢN, CÔNG NỢ, TRẢ GÓP (NH)

  // Tham chiếu đến giao dịch gốc
  String? referenceType; // sale, repair, expense, debt, supplier_payment...
  String? referenceId; // firestoreId của giao dịch gốc

  // Thông tin chi tiết
  String title; // Tiêu đề ngắn gọn
  String? description; // Mô tả chi tiết
  String? customerName; // Tên khách hàng / NCC
  String? phone;
  String? productInfo; // Thông tin sản phẩm (nếu có)

  // Số dư sau giao dịch (để theo dõi)
  int? balanceAfterCash; // Số dư tiền mặt sau giao dịch
  int? balanceAfterBank; // Số dư ngân hàng sau giao dịch

  // Metadata
  int createdAt;
  String? createdBy; // User thực hiện
  String? shopId;
  bool isSynced;

  // Thông tin bổ sung dạng JSON
  String? extraData; // JSON chứa thông tin bổ sung tùy loại giao dịch

  FinancialActivity({
    this.id,
    this.firestoreId,
    required this.activityType,
    required this.amount,
    required this.direction,
    required this.paymentMethod,
    this.referenceType,
    this.referenceId,
    required this.title,
    this.description,
    this.customerName,
    this.phone,
    this.productInfo,
    this.balanceAfterCash,
    this.balanceAfterBank,
    required this.createdAt,
    this.createdBy,
    this.shopId,
    this.isSynced = false,
    this.extraData,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'activityType': activityType,
      'amount': amount,
      'direction': direction,
      'paymentMethod': paymentMethod,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'title': title,
      'description': description,
      'customerName': customerName,
      'phone': phone,
      'productInfo': productInfo,
      'balanceAfterCash': balanceAfterCash,
      'balanceAfterBank': balanceAfterBank,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'shopId': shopId,
      'isSynced': isSynced ? 1 : 0,
      'extraData': extraData,
    };
  }

  factory FinancialActivity.fromMap(Map<String, dynamic> map) {
    return FinancialActivity(
      id: map['id'] as int?,
      firestoreId: map['firestoreId'] as String?,
      activityType: map['activityType'] as String? ?? 'UNKNOWN',
      amount: map['amount'] as int? ?? 0,
      direction: map['direction'] as String? ?? 'IN',
      paymentMethod: map['paymentMethod'] as String? ?? 'TIỀN MẶT',
      referenceType: map['referenceType'] as String?,
      referenceId: map['referenceId'] as String?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String?,
      customerName: map['customerName'] as String?,
      phone: map['phone'] as String?,
      productInfo: map['productInfo'] as String?,
      balanceAfterCash: map['balanceAfterCash'] as int?,
      balanceAfterBank: map['balanceAfterBank'] as int?,
      createdAt:
          map['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      createdBy: map['createdBy'] as String?,
      shopId: map['shopId'] as String?,
      isSynced: (map['isSynced'] as int? ?? 0) == 1,
      extraData: map['extraData'] as String?,
    );
  }

  /// Helper để tạo activity từ đơn bán hàng
  static FinancialActivity fromSale({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String customerName,
    required String phone,
    required String productNames,
    required String sellerName,
    required int createdAt,
    String? shopId,
    bool isInstallment = false,
    int downPayment = 0,
    String? downPaymentMethod,
    String? bankName,
  }) {
    String title;
    String direction;
    int actualAmount;
    String actualPaymentMethod;

    if (paymentMethod == 'CÔNG NỢ') {
      title = 'BÁN CÔNG NỢ: $productNames';
      direction = 'DEBT'; // Không ảnh hưởng quỹ ngay
      actualAmount = amount;
      actualPaymentMethod = 'CÔNG NỢ';
    } else if (isInstallment) {
      title = 'BÁN TRẢ GÓP: $productNames (Down: ${_formatMoney(downPayment)})';
      direction = 'IN';
      actualAmount = downPayment;
      actualPaymentMethod = downPaymentMethod ?? 'TIỀN MẶT';
    } else {
      title = 'BÁN: $productNames';
      direction = 'IN';
      actualAmount = amount;
      actualPaymentMethod = paymentMethod;
    }

    return FinancialActivity(
      firestoreId: 'fa_sale_$firestoreId',
      activityType: 'SALE',
      amount: actualAmount,
      direction: direction,
      paymentMethod: actualPaymentMethod,
      referenceType: 'sale',
      referenceId: firestoreId,
      title: title,
      description: isInstallment
          ? 'Trả góp qua $bankName, vay ${_formatMoney(amount - downPayment)}'
          : null,
      customerName: customerName,
      phone: phone,
      productInfo: productNames,
      createdAt: createdAt,
      createdBy: sellerName,
      shopId: shopId,
    );
  }

  /// Helper để tạo activity từ chi phí
  static FinancialActivity fromExpense({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String title,
    required String category,
    String? note,
    required int createdAt,
    String? createdBy,
    String? shopId,
  }) {
    return FinancialActivity(
      firestoreId: 'fa_expense_$firestoreId',
      activityType: 'EXPENSE',
      amount: amount,
      direction: 'OUT',
      paymentMethod: paymentMethod,
      referenceType: 'expense',
      referenceId: firestoreId,
      title: 'CHI: $title',
      description: '[$category] $note',
      createdAt: createdAt,
      createdBy: createdBy,
      shopId: shopId,
    );
  }

  /// Helper để tạo activity từ nhập hàng
  static FinancialActivity fromPurchase({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String productName,
    required String supplierName,
    required int quantity,
    required int createdAt,
    String? createdBy,
    String? shopId,
  }) {
    return FinancialActivity(
      firestoreId: 'fa_purchase_$firestoreId',
      activityType: 'PURCHASE',
      amount: amount,
      direction: paymentMethod == 'CÔNG NỢ' ? 'DEBT' : 'OUT',
      paymentMethod: paymentMethod,
      referenceType: 'supplier_import',
      referenceId: firestoreId,
      title: 'NHẬP: $productName x$quantity',
      description: 'NCC: $supplierName',
      customerName: supplierName,
      productInfo: productName,
      createdAt: createdAt,
      createdBy: createdBy,
      shopId: shopId,
    );
  }

  /// Helper để tạo activity từ thu nợ
  static FinancialActivity fromDebtCollection({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String customerName,
    required String phone,
    required int createdAt,
    String? createdBy,
    String? shopId,
    String? note,
  }) {
    return FinancialActivity(
      firestoreId: 'fa_debt_collect_$firestoreId',
      activityType: 'DEBT_COLLECT',
      amount: amount,
      direction: 'IN',
      paymentMethod: paymentMethod,
      referenceType: 'debt_payment',
      referenceId: firestoreId,
      title: 'THU NỢ: $customerName',
      description: note,
      customerName: customerName,
      phone: phone,
      createdAt: createdAt,
      createdBy: createdBy,
      shopId: shopId,
    );
  }

  /// Helper để tạo activity từ tất toán NH
  static FinancialActivity fromSettlement({
    required String saleFirestoreId,
    required int amount,
    required String bankName,
    required String customerName,
    required String productNames,
    required int createdAt,
    int settlementFee = 0,
    String? createdBy,
    String? shopId,
  }) {
    return FinancialActivity(
      firestoreId: 'fa_settlement_${saleFirestoreId}_$createdAt',
      activityType: 'SETTLEMENT',
      amount: amount,
      direction: 'IN',
      paymentMethod: 'CHUYỂN KHOẢN',
      referenceType: 'sale',
      referenceId: saleFirestoreId,
      title: 'TẤT TOÁN: $bankName',
      description: settlementFee > 0
          ? 'Phí NH: ${_formatMoney(settlementFee)}'
          : 'Nhận đủ từ NH',
      customerName: customerName,
      productInfo: productNames,
      createdAt: createdAt,
      createdBy: createdBy,
      shopId: shopId,
    );
  }

  /// Helper để tạo activity từ thanh toán NCC
  static FinancialActivity fromSupplierPayment({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String supplierName,
    required int createdAt,
    String? note,
    String? createdBy,
    String? shopId,
  }) {
    return FinancialActivity(
      firestoreId: 'fa_supplier_pay_$firestoreId',
      activityType: 'DEBT_PAY',
      amount: amount,
      direction: 'OUT',
      paymentMethod: paymentMethod,
      referenceType: 'supplier_payment',
      referenceId: firestoreId,
      title: 'TRẢ NCC: $supplierName',
      description: note,
      customerName: supplierName,
      createdAt: createdAt,
      createdBy: createdBy,
      shopId: shopId,
    );
  }

  /// Helper để tạo activity từ sửa chữa
  static FinancialActivity fromRepair({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String customerName,
    required String phone,
    required String deviceModel,
    required int createdAt,
    String? createdBy,
    String? shopId,
  }) {
    return FinancialActivity(
      firestoreId: 'fa_repair_$firestoreId',
      activityType: 'REPAIR',
      amount: amount,
      direction: paymentMethod == 'CÔNG NỢ' ? 'DEBT' : 'IN',
      paymentMethod: paymentMethod,
      referenceType: 'repair',
      referenceId: firestoreId,
      title: 'SỬA: $deviceModel',
      description: 'Thu tiền sửa chữa',
      customerName: customerName,
      phone: phone,
      productInfo: deviceModel,
      createdAt: createdAt,
      createdBy: createdBy,
      shopId: shopId,
    );
  }

  /// Helper để tạo activity từ thanh toán đối tác sửa chữa
  static FinancialActivity fromRepairPartnerPayment({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String partnerName,
    required int createdAt,
    String? note,
    String? createdBy,
    String? shopId,
  }) {
    return FinancialActivity(
      firestoreId: 'fa_partner_pay_$firestoreId',
      activityType: 'REPAIR_PARTNER_DEBT',
      amount: amount,
      direction: paymentMethod == 'CÔNG NỢ' ? 'DEBT' : 'OUT',
      paymentMethod: paymentMethod,
      referenceType: 'repair_partner_payment',
      referenceId: firestoreId,
      title: 'TRẢ ĐỐI TÁC SC: $partnerName',
      description: note,
      customerName: partnerName,
      createdAt: createdAt,
      createdBy: createdBy,
      shopId: shopId,
    );
  }

  /// Helper để tạo activity từ chi phí vốn linh kiện sửa chữa đã ghi sổ quỹ
  static FinancialActivity fromRepairPartsCost({
    required String firestoreId,
    required int amount,
    required String paymentMethod,
    required String customerName,
    required String phone,
    required String deviceModel,
    required int createdAt,
    String? createdBy,
    String? shopId,
  }) {
    return FinancialActivity(
      firestoreId: 'fa_repair_parts_$firestoreId',
      activityType: 'REPAIR_PARTS_COST',
      amount: amount,
      direction: 'OUT',
      paymentMethod: paymentMethod,
      referenceType: 'repair',
      referenceId: firestoreId,
      title: 'VỐN LK: $deviceModel',
      description: 'Chi phí vốn linh kiện — ${customerName.isNotEmpty ? customerName : "KH vãng lai"}',
      customerName: customerName,
      phone: phone,
      productInfo: deviceModel,
      createdAt: createdAt,
      createdBy: createdBy,
      shopId: shopId,
    );
  }

  /// Tạo FinancialActivity từ phiếu trả hàng
  static FinancialActivity fromSalesReturn({
    required String firestoreId,
    required int amount,
    required String refundMethod,
    required String customerName,
    required String customerPhone,
    required String productInfo,
    required int createdAt,
    String? note,
    String? createdBy,
    String? shopId,
  }) {
    final isDebt = refundMethod == 'CÔNG NỢ';
    return FinancialActivity(
      firestoreId: 'fa_return_$firestoreId',
      activityType: 'REFUND',
      amount: amount,
      direction: isDebt ? 'DEBT' : 'OUT',
      paymentMethod: refundMethod,
      referenceType: 'sales_return',
      referenceId: firestoreId,
      title: 'HOÀN TIỀN TRẢ HÀNG: $productInfo',
      description: 'KH: ${customerName.isNotEmpty ? customerName : "Vãng lai"}${note != null && note.isNotEmpty ? ". Lý do: $note" : ""}',
      customerName: customerName,
      phone: customerPhone,
      productInfo: productInfo,
      createdAt: createdAt,
      createdBy: createdBy,
      shopId: shopId,
    );
  }

  static String _formatMoney(int amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)}tr';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)}k';
    }
    return amount.toString();
  }

  /// Icon theo loại activity
  String get icon {
    switch (activityType) {
      case 'SALE':
      case 'SALE_PAYMENT':
      case 'SALE_INSTALLMENT':
        return '🛒';
      case 'PURCHASE':
      case 'INVENTORY_PURCHASE':
      case 'SUPPLIER_PURCHASE':
      case 'PARTS_STOCK_IN':
        return '📦';
      case 'EXPENSE':
      case 'OPERATING_EXPENSE':
      case 'UTILITY_EXPENSE':
      case 'OTHER_EXPENSE':
        return '💸';
      case 'DEBT_COLLECT':
      case 'CUSTOMER_DEBT_COLLECT':
        return '💰';
      case 'DEBT_PAY':
      case 'SUPPLIER_DEBT':
      case 'REPAIR_PARTNER_DEBT':
      case 'OTHER_DEBT':
        return '💳';
      case 'SETTLEMENT':
        return '🏦';
      case 'REPAIR':
      case 'REPAIR_SERVICE':
        return '🔧';
      case 'REPAIR_PARTS_COST':
        return '🔩';
      case 'REFUND':
      case 'CUSTOMER_REFUND':
        return '↩️';
      case 'ADJUSTMENT':
        return '⚙️';
      case 'SALARY_PAYMENT':
      case 'BONUS_PAYMENT':
        return '👷';
      case 'OTHER_INCOME':
        return '💵';
      default:
        return '📝';
    }
  }

  /// Tên hiển thị của loại activity
  String get activityTypeName {
    switch (activityType) {
      case 'SALE':
      case 'SALE_PAYMENT':
        return 'Bán hàng';
      case 'SALE_INSTALLMENT':
        return 'Trả góp';
      case 'PURCHASE':
      case 'INVENTORY_PURCHASE':
      case 'SUPPLIER_PURCHASE':
        return 'Nhập hàng';
      case 'PARTS_STOCK_IN':
        return 'Nhập linh kiện';
      case 'EXPENSE':
      case 'OPERATING_EXPENSE':
        return 'Chi phí';
      case 'UTILITY_EXPENSE':
        return 'Tiện ích';
      case 'OTHER_EXPENSE':
        return 'Chi khác';
      case 'DEBT_COLLECT':
      case 'CUSTOMER_DEBT_COLLECT':
        return 'Thu nợ';
      case 'DEBT_PAY':
      case 'SUPPLIER_DEBT':
        return 'Trả nợ NCC';
      case 'REPAIR_PARTNER_DEBT':
        return 'Trả nợ đ.tác';
      case 'OTHER_DEBT':
        return 'Trả nợ khác';
      case 'SETTLEMENT':
        return 'Tất toán NH';
      case 'REPAIR':
      case 'REPAIR_SERVICE':
        return 'Sửa chữa';
      case 'REPAIR_PARTS_COST':
        return 'Vốn LK SC';
      case 'REFUND':
      case 'CUSTOMER_REFUND':
        return 'Hoàn tiền';
      case 'ADJUSTMENT':
        return 'Điều chỉnh';
      case 'SALARY_PAYMENT':
        return 'Lương';
      case 'BONUS_PAYMENT':
        return 'Thưởng';
      case 'OTHER_INCOME':
        return 'Thu khác';
      case 'PAYMENT_REQUEST_IN':
        return 'Thu đóng tiền';
      case 'PAYMENT_REQUEST_OUT':
        return 'CK cho NH';
      default:
        return 'Khác';
    }
  }
}
