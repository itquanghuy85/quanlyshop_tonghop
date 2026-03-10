import 'package:cloud_firestore/cloud_firestore.dart';

/// Loại thanh toán mà nhân viên yêu cầu chủ shop đóng hộ
enum PaymentType {
  electricity,    // Tiền điện
  water,          // Tiền nước
  internet,       // Tiền mạng
  bankLoan,       // Khoản vay ngân hàng
  bankInstallment,// Trả góp ngân hàng
  insurance,      // Bảo hiểm
  other,          // Khác
}

/// Trạng thái xử lý
enum PaymentRequestStatus {
  pending,    // Chờ xử lý
  processing, // Đang xử lý
  completed,  // Đã thanh toán
  rejected,   // Từ chối
}

/// Model yêu cầu đóng tiền - giống tin nhắn chat
class PaymentRequest {
  String? id;
  String shopId;

  // Người gửi (nhân viên)
  String senderId;
  String senderName;

  // Thông tin khách hàng
  String customerName;
  String customerPhone;
  String? customerNote;

  // Loại thanh toán
  PaymentType paymentType;
  String? paymentTypeLabel; // Tên tùy chỉnh nếu type == other

  // Số tiền & chi tiết
  double amount;
  String? accountNumber;  // Số tài khoản / mã hợp đồng
  String? bankName;       // Ngân hàng / đơn vị
  String? description;    // Mô tả thêm

  // Hình ảnh đính kèm (hóa đơn, biên nhận...)
  List<String> imageUrls;

  // Trạng thái
  PaymentRequestStatus status;
  String? processedBy;     // UID người xử lý (chủ shop)
  String? processedByName;
  String? rejectReason;
  DateTime? processedAt;

  // Timestamps
  DateTime createdAt;
  DateTime? updatedAt;

  // Soft delete
  bool deleted;

  PaymentRequest({
    this.id,
    required this.shopId,
    required this.senderId,
    required this.senderName,
    required this.customerName,
    required this.customerPhone,
    this.customerNote,
    required this.paymentType,
    this.paymentTypeLabel,
    required this.amount,
    this.accountNumber,
    this.bankName,
    this.description,
    this.imageUrls = const [],
    this.status = PaymentRequestStatus.pending,
    this.processedBy,
    this.processedByName,
    this.rejectReason,
    this.processedAt,
    required this.createdAt,
    this.updatedAt,
    this.deleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'shopId': shopId,
      'senderId': senderId,
      'senderName': senderName,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerNote': customerNote,
      'paymentType': paymentType.name,
      'paymentTypeLabel': paymentTypeLabel,
      'amount': amount,
      'accountNumber': accountNumber,
      'bankName': bankName,
      'description': description,
      'imageUrls': imageUrls,
      'status': status.name,
      'processedBy': processedBy,
      'processedByName': processedByName,
      'rejectReason': rejectReason,
      'processedAt': processedAt != null ? Timestamp.fromDate(processedAt!) : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'deleted': deleted,
    };
  }

  factory PaymentRequest.fromMap(Map<String, dynamic> map, {String? docId}) {
    return PaymentRequest(
      id: docId ?? map['id'],
      shopId: map['shopId'] ?? '',
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      customerName: map['customerName'] ?? '',
      customerPhone: map['customerPhone'] ?? '',
      customerNote: map['customerNote'],
      paymentType: _parsePaymentType(map['paymentType']),
      paymentTypeLabel: map['paymentTypeLabel'],
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      accountNumber: map['accountNumber'],
      bankName: map['bankName'],
      description: map['description'],
      imageUrls: (map['imageUrls'] as List?)?.cast<String>() ?? [],
      status: _parseStatus(map['status']),
      processedBy: map['processedBy'],
      processedByName: map['processedByName'],
      rejectReason: map['rejectReason'],
      processedAt: (map['processedAt'] as Timestamp?)?.toDate(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      deleted: map['deleted'] ?? false,
    );
  }

  factory PaymentRequest.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return PaymentRequest.fromMap(doc.data() ?? {}, docId: doc.id);
  }

  static PaymentType _parsePaymentType(dynamic val) {
    if (val is String) {
      return PaymentType.values.firstWhere(
        (e) => e.name == val,
        orElse: () => PaymentType.other,
      );
    }
    return PaymentType.other;
  }

  static PaymentRequestStatus _parseStatus(dynamic val) {
    if (val is String) {
      return PaymentRequestStatus.values.firstWhere(
        (e) => e.name == val,
        orElse: () => PaymentRequestStatus.pending,
      );
    }
    return PaymentRequestStatus.pending;
  }

  /// Label hiển thị loại thanh toán
  String get paymentTypeDisplay {
    switch (paymentType) {
      case PaymentType.electricity: return 'Tiền điện';
      case PaymentType.water: return 'Tiền nước';
      case PaymentType.internet: return 'Tiền mạng';
      case PaymentType.bankLoan: return 'Khoản vay NH';
      case PaymentType.bankInstallment: return 'Trả góp NH';
      case PaymentType.insurance: return 'Bảo hiểm';
      case PaymentType.other: return paymentTypeLabel ?? 'Khác';
    }
  }

  /// Icon theo loại
  String get paymentTypeIcon {
    switch (paymentType) {
      case PaymentType.electricity: return '⚡';
      case PaymentType.water: return '💧';
      case PaymentType.internet: return '🌐';
      case PaymentType.bankLoan: return '🏦';
      case PaymentType.bankInstallment: return '💳';
      case PaymentType.insurance: return '🛡️';
      case PaymentType.other: return '📋';
    }
  }

  /// Label trạng thái
  String get statusDisplay {
    switch (status) {
      case PaymentRequestStatus.pending: return 'Chờ xử lý';
      case PaymentRequestStatus.processing: return 'Đang xử lý';
      case PaymentRequestStatus.completed: return 'Đã thanh toán';
      case PaymentRequestStatus.rejected: return 'Từ chối';
    }
  }

  PaymentRequest copyWith({
    String? id,
    String? shopId,
    String? senderId,
    String? senderName,
    String? customerName,
    String? customerPhone,
    String? customerNote,
    PaymentType? paymentType,
    String? paymentTypeLabel,
    double? amount,
    String? accountNumber,
    String? bankName,
    String? description,
    List<String>? imageUrls,
    PaymentRequestStatus? status,
    String? processedBy,
    String? processedByName,
    String? rejectReason,
    DateTime? processedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return PaymentRequest(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerNote: customerNote ?? this.customerNote,
      paymentType: paymentType ?? this.paymentType,
      paymentTypeLabel: paymentTypeLabel ?? this.paymentTypeLabel,
      amount: amount ?? this.amount,
      accountNumber: accountNumber ?? this.accountNumber,
      bankName: bankName ?? this.bankName,
      description: description ?? this.description,
      imageUrls: imageUrls ?? this.imageUrls,
      status: status ?? this.status,
      processedBy: processedBy ?? this.processedBy,
      processedByName: processedByName ?? this.processedByName,
      rejectReason: rejectReason ?? this.rejectReason,
      processedAt: processedAt ?? this.processedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }
}
