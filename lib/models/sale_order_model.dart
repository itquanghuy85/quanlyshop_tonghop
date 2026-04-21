import '../services/encryption_service.dart';

class SaleOrder {
  int? id;
  String? firestoreId;
  String customerName;
  String phone;
  bool isWalkIn;
  String? walkInName;
  String? walkInPhone;
  String address;
  String productNames;
  String productImeis;
  int totalPrice;
  int totalCost;
  int discount; // Số tiền giảm trừ trực tiếp
  String paymentMethod;
  String sellerName;
  String? sellerUid;
  int soldAt;
  String? notes;
  String? gifts;
  String warranty;
  bool isSynced;

  // --- TRƯỜNG TRẢ GÓP MỚI ---
  bool isInstallment; // Có phải trả góp không
  int downPayment; // Số tiền khách trả trước
  String? downPaymentMethod; // Phương thức trả trước: TIỀN MẶT / CHUYỂN KHOẢN
  int loanAmount; // Số tiền vay ngân hàng
  String? installmentTerm; // Kỳ hạn vay (6, 12 tháng...)
  String? bankName; // Tên ngân hàng hỗ trợ
  String? bankName2; // Ngân hàng thứ 2 (nếu có)
  int loanAmount2; // Số tiền vay NH thứ 2
  int? settlementPlannedAt; // Ngày dự kiến ngân hàng tất toán
  int? settlementReceivedAt; // Ngày đã nhận tiền từ NH
  int settlementAmount; // Số tiền thực nhận từ NH
  int settlementFee; // Phí/hoa hồng NH giữ lại
  String? settlementNote; // Ghi chú tất toán
  String? settlementCode; // Mã hồ sơ/biên nhận từ NH

  // --- TRƯỜNG KẾT HỢP THANH TOÁN (TIỀN MẶT + CHUYỂN KHOẢN) ---
  int cashAmount; // Phần tiền mặt (khi paymentMethod = KẾT HỢP)
  int transferAmount; // Phần chuyển khoản (khi paymentMethod = KẾT HỢP)

  SaleOrder({
    this.id,
    this.firestoreId,
    required this.customerName,
    required this.phone,
    this.isWalkIn = false,
    this.walkInName,
    this.walkInPhone,
    this.address = "",
    required this.productNames,
    required this.productImeis,
    this.totalPrice = 0,
    this.totalCost = 0,
    this.discount = 0,
    this.paymentMethod = "TIỀN MẶT",
    required this.sellerName,
    this.sellerUid,
    required this.soldAt,
    this.notes,
    this.gifts,
    this.warranty = "KO BH",
    this.isInstallment = false,
    this.downPayment = 0,
    this.downPaymentMethod,
    this.loanAmount = 0,
    this.installmentTerm,
    this.bankName,
    this.bankName2,
    this.loanAmount2 = 0,
    this.settlementPlannedAt,
    this.settlementReceivedAt,
    this.settlementAmount = 0,
    this.settlementFee = 0,
    this.settlementNote,
    this.settlementCode,
    this.cashAmount = 0,
    this.transferAmount = 0,
    this.isSynced = false,
  });

  /// Giá cuối sau giảm giá
  int get finalPrice => totalPrice - discount > 0 ? totalPrice - discount : 0;
  
  /// Số tiền còn nợ thực tế (không tính tiền vay NH vì NH sẽ tất toán)
  /// = Giá cuối - Trả trước - Vay NH1 - Vay NH2
  int get remainingDebt {
    final debt = finalPrice - downPayment - loanAmount - loanAmount2;
    return debt > 0 ? debt : 0;
  }
  
  /// Kiểm tra đã thanh toán đủ chưa
  bool get isPaid => remainingDebt == 0;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'customerName': customerName.toUpperCase(),
      'phone': phone,
      'isWalkIn': isWalkIn ? 1 : 0,
      'walkInName': walkInName?.toUpperCase(),
      'walkInPhone': walkInPhone,
      'address': address.toUpperCase(),
      'productNames': productNames.toUpperCase(),
      'productImeis': productImeis.toUpperCase(),
      'totalPrice': totalPrice,
      'totalCost': totalCost,
      'discount': discount,
      'paymentMethod': paymentMethod.toUpperCase(),
      'sellerName': sellerName.toUpperCase(),
      'sellerUid': sellerUid,
      'soldAt': soldAt,
      'notes': notes,
      'gifts': gifts?.toUpperCase(),
      'warranty': warranty.toUpperCase(),
      'isInstallment': isInstallment ? 1 : 0,
      'downPayment': downPayment,
      'downPaymentMethod': downPaymentMethod?.toUpperCase(),
      'loanAmount': loanAmount,
      'installmentTerm': installmentTerm,
      'bankName': bankName?.toUpperCase(),
      'bankName2': bankName2?.toUpperCase(),
      'loanAmount2': loanAmount2,
      'settlementPlannedAt': settlementPlannedAt,
      'settlementReceivedAt': settlementReceivedAt,
      'settlementAmount': settlementAmount,
      'settlementFee': settlementFee,
      'settlementNote': settlementNote,
      'settlementCode': settlementCode?.toUpperCase(),
      'cashAmount': cashAmount,
      'transferAmount': transferAmount,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory SaleOrder.fromMap(Map<String, dynamic> map) {
    final m = EncryptionService.decryptMap(Map<String, dynamic>.from(map));

    int toSafeInt(dynamic value) {
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    int? toNullableInt(dynamic value) {
      if (value == null) return null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
      return null;
    }

    // Validate và sanitize các giá trị số
    final totalPriceRaw = toSafeInt(m['totalPrice']);
    final totalCostRaw = toSafeInt(m['totalCost']);
    final discountRaw = toSafeInt(m['discount']);
    final downPaymentRaw = toSafeInt(m['downPayment']);
    final loanAmountRaw = toSafeInt(m['loanAmount']);
    final loanAmount2Raw = toSafeInt(m['loanAmount2']);
    final settlementAmountRaw = toSafeInt(m['settlementAmount']);
    final settlementFeeRaw = toSafeInt(m['settlementFee']);

    // Đảm bảo các giá trị không âm
    final totalPrice = totalPriceRaw < 0 ? 0 : totalPriceRaw;
    final totalCost = totalCostRaw < 0 ? 0 : totalCostRaw;
    final discount = discountRaw < 0 ? 0 : discountRaw;
    final downPayment = downPaymentRaw < 0 ? 0 : downPaymentRaw;
    final loanAmount = loanAmountRaw < 0 ? 0 : loanAmountRaw;
    final loanAmount2 = loanAmount2Raw < 0 ? 0 : loanAmount2Raw;
    final settlementAmount = settlementAmountRaw < 0 ? 0 : settlementAmountRaw;
    final settlementFee = settlementFeeRaw < 0 ? 0 : settlementFeeRaw;
    final cashAmountRaw = toSafeInt(m['cashAmount']);
    final transferAmountRaw = toSafeInt(m['transferAmount']);
    final cashAmount = cashAmountRaw < 0 ? 0 : cashAmountRaw;
    final transferAmount = transferAmountRaw < 0 ? 0 : transferAmountRaw;

    return SaleOrder(
      id: m['id'],
      firestoreId: m['firestoreId'],
      customerName: m['customerName'] ?? "",
      phone: m['phone'] ?? "",
      isWalkIn: m['isWalkIn'] == 1 || m['isWalkIn'] == true,
      walkInName: m['walkInName'],
      walkInPhone: m['walkInPhone'],
      address: m['address'] ?? "",
      productNames: m['productNames'] ?? "",
      productImeis: m['productImeis'] ?? "",
      totalPrice: totalPrice,
      totalCost: totalCost,
      discount: discount,
      paymentMethod: m['paymentMethod'] ?? "TIỀN MẶT",
      sellerName: m['sellerName'] ?? "",
      sellerUid: m['sellerUid'],
      soldAt: toSafeInt(m['soldAt']),
      notes: m['notes'],
      gifts: m['gifts'],
      warranty: m['warranty'] ?? "KO BH",
      isInstallment: m['isInstallment'] == 1 || m['isInstallment'] == true,
      downPayment: downPayment,
      downPaymentMethod: m['downPaymentMethod']?.toString(),
      loanAmount: loanAmount,
      installmentTerm: m['installmentTerm']?.toString(),
      bankName: m['bankName']?.toString(),
      bankName2: m['bankName2']?.toString(),
      loanAmount2: loanAmount2,
      settlementPlannedAt: toNullableInt(m['settlementPlannedAt']),
      settlementReceivedAt: toNullableInt(m['settlementReceivedAt']),
      settlementAmount: settlementAmount,
      settlementFee: settlementFee,
      settlementNote: m['settlementNote']?.toString(),
      settlementCode: m['settlementCode']?.toString(),
      cashAmount: cashAmount,
      transferAmount: transferAmount,
      isSynced: m['isSynced'] == 1 || m['isSynced'] == true,
    );
  }
}
