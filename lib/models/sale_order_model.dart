class SaleOrder {
  int? id;
  String? firestoreId;
  String customerName;
  String phone;
  String address;
  String productNames;
  String productImeis;
  int totalPrice;
  int totalCost;
  String paymentMethod;
  String sellerName;
  int soldAt;
  String? notes;
  String? gifts;
  String warranty;
  bool isSynced;

  // --- TRƯỜNG TRẢ GÓP MỚI ---
  bool isInstallment;    // Có phải trả góp không
  int downPayment;       // Số tiền khách trả trước
  int loanAmount;        // Số tiền vay ngân hàng
  String? installmentTerm; // Kỳ hạn vay (6, 12 tháng...)
  String? bankName;      // Tên ngân hàng hỗ trợ
  int? settlementPlannedAt; // Ngày dự kiến ngân hàng tất toán
  int? settlementReceivedAt; // Ngày đã nhận tiền từ NH
  int settlementAmount;   // Số tiền thực nhận từ NH
  int settlementFee;      // Phí/hoa hồng NH giữ lại
  String? settlementNote; // Ghi chú tất toán
  String? settlementCode; // Mã hồ sơ/biên nhận từ NH

  SaleOrder({
    this.id,
    this.firestoreId,
    required this.customerName,
    required this.phone,
    this.address = "",
    required this.productNames,
    required this.productImeis,
    this.totalPrice = 0,
    this.totalCost = 0,
    this.paymentMethod = "TIỀN MẶT",
    required this.sellerName,
    required this.soldAt,
    this.notes,
    this.gifts,
    this.warranty = "KO BH",
    this.isInstallment = false,
    this.downPayment = 0,
    this.loanAmount = 0,
    this.installmentTerm,
    this.bankName,
    this.settlementPlannedAt,
    this.settlementReceivedAt,
    this.settlementAmount = 0,
    this.settlementFee = 0,
    this.settlementNote,
    this.settlementCode,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'customerName': customerName.toUpperCase(),
      'phone': phone,
      'address': address.toUpperCase(),
      'productNames': productNames.toUpperCase(),
      'productImeis': productImeis.toUpperCase(),
      'totalPrice': totalPrice,
      'totalCost': totalCost,
      'paymentMethod': paymentMethod.toUpperCase(),
      'sellerName': sellerName.toUpperCase(),
      'soldAt': soldAt,
      'notes': notes,
      'gifts': gifts?.toUpperCase(),
      'warranty': warranty.toUpperCase(),
      'isInstallment': isInstallment ? 1 : 0,
      'downPayment': downPayment,
      'loanAmount': loanAmount,
      'installmentTerm': installmentTerm,
      'bankName': bankName?.toUpperCase(),
      'settlementPlannedAt': settlementPlannedAt,
      'settlementReceivedAt': settlementReceivedAt,
      'settlementAmount': settlementAmount,
      'settlementFee': settlementFee,
      'settlementNote': settlementNote,
      'settlementCode': settlementCode?.toUpperCase(),
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory SaleOrder.fromMap(Map<String, dynamic> map) {
    // Validate và sanitize các giá trị số
    final totalPriceRaw = map['totalPrice'] is int ? map['totalPrice'] : 0;
    final totalCostRaw = map['totalCost'] is int ? map['totalCost'] : 0;
    final downPaymentRaw = map['downPayment'] is int ? map['downPayment'] : 0;
    final loanAmountRaw = map['loanAmount'] is int ? map['loanAmount'] : 0;
    final settlementAmountRaw = map['settlementAmount'] is int ? map['settlementAmount'] : 0;
    final settlementFeeRaw = map['settlementFee'] is int ? map['settlementFee'] : 0;
    
    // Đảm bảo các giá trị không âm
    final totalPrice = totalPriceRaw < 0 ? 0 : totalPriceRaw;
    final totalCost = totalCostRaw < 0 ? 0 : totalCostRaw;
    final downPayment = downPaymentRaw < 0 ? 0 : downPaymentRaw;
    final loanAmount = loanAmountRaw < 0 ? 0 : loanAmountRaw;
    final settlementAmount = settlementAmountRaw < 0 ? 0 : settlementAmountRaw;
    final settlementFee = settlementFeeRaw < 0 ? 0 : settlementFeeRaw;
    
    return SaleOrder(
      id: map['id'],
      firestoreId: map['firestoreId'],
      customerName: map['customerName'] ?? "",
      phone: map['phone'] ?? "",
      address: map['address'] ?? "",
      productNames: map['productNames'] ?? "",
      productImeis: map['productImeis'] ?? "",
      totalPrice: totalPrice,
      totalCost: totalCost,
      paymentMethod: map['paymentMethod'] ?? "TIỀN MẶT",
      sellerName: map['sellerName'] ?? "",
      soldAt: map['soldAt'] is int ? map['soldAt'] : 0,
      notes: map['notes'],
      gifts: map['gifts'],
      warranty: map['warranty'] ?? "KO BH",
      isInstallment: map['isInstallment'] == 1 || map['isInstallment'] == true,
      downPayment: downPayment,
      loanAmount: loanAmount,
      installmentTerm: map['installmentTerm'],
      bankName: map['bankName'],
      settlementPlannedAt: map['settlementPlannedAt'],
      settlementReceivedAt: map['settlementReceivedAt'],
      settlementAmount: settlementAmount,
      settlementFee: settlementFee,
      settlementNote: map['settlementNote'],
      settlementCode: map['settlementCode'],
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
    );
  }
}
