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
        return '🛒';
      case 'PURCHASE':
        return '📦';
      case 'EXPENSE':
        return '💸';
      case 'DEBT_COLLECT':
        return '💰';
      case 'DEBT_PAY':
        return '💳';
      case 'SETTLEMENT':
        return '🏦';
      case 'REPAIR':
        return '🔧';
      case 'REFUND':
        return '↩️';
      case 'ADJUSTMENT':
        return '⚙️';
      default:
        return '📝';
    }
  }

  /// Tên hiển thị của loại activity
  String get activityTypeName {
    switch (activityType) {
      case 'SALE':
        return 'Bán hàng';
      case 'PURCHASE':
        return 'Nhập hàng';
      case 'EXPENSE':
        return 'Chi phí';
      case 'DEBT_COLLECT':
        return 'Thu nợ';
      case 'DEBT_PAY':
        return 'Trả nợ NCC';
      case 'SETTLEMENT':
        return 'Tất toán NH';
      case 'REPAIR':
        return 'Sửa chữa';
      case 'REFUND':
        return 'Hoàn tiền';
      case 'ADJUSTMENT':
        return 'Điều chỉnh';
      default:
        return 'Khác';
    }
  }
}
