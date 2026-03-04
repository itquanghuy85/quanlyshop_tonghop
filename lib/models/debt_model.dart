class Debt {
  int? id;
  String? firestoreId;
  String personName;
  String phone;
  int totalAmount;
  int paidAmount;
  String type; // 'OWE' or 'OWED'
  String status; // 'ACTIVE', 'PAID', 'CANCELLED'
  int createdAt;
  String? note;
  String? linkedId; // Link to related record (product, sale, etc.)
  bool isSynced;

  Debt({
    this.id,
    this.firestoreId,
    required this.personName,
    required this.phone,
    required this.totalAmount,
    this.paidAmount = 0,
    required this.type,
    this.status = 'ACTIVE',
    required this.createdAt,
    this.note,
    this.linkedId,
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'personName': personName,
      'phone': phone,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'type': type,
      'status': status,
      'createdAt': createdAt,
      'note': note,
      'linkedId': linkedId,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory Debt.fromMap(Map<String, dynamic> map) {
    final totalAmount = map['totalAmount'] is int ? map['totalAmount'] : 0;
    final totalAmountSafe = totalAmount < 0 ? 0 : totalAmount;
    final paidAmountRaw = map['paidAmount'] is int ? map['paidAmount'] : 0;
    // Đảm bảo paidAmount không âm và không vượt quá totalAmount
    final paidAmountSafe = paidAmountRaw < 0 ? 0 : paidAmountRaw;
    final paidAmount = paidAmountSafe > totalAmountSafe ? totalAmountSafe : paidAmountSafe;
    
    // Validate type: chấp nhận các type hợp lệ
    // - CUSTOMER_OWES: Khách nợ shop (phải thu)
    // - SHOP_OWES: Shop nợ nhà cung cấp (phải trả)
    // - OTHER_CUSTOMER_OWES: Nợ khác - phải thu
    // - OTHER_SHOP_OWES: Nợ khác - phải trả
    // - OWE/OWED: Legacy types (backward compatibility)
    final typeRaw = map['type']?.toString() ?? 'CUSTOMER_OWES';
    final validTypes = ['CUSTOMER_OWES', 'SHOP_OWES', 'OTHER_CUSTOMER_OWES', 'OTHER_SHOP_OWES', 'OWE', 'OWED'];
    final type = validTypes.contains(typeRaw) ? typeRaw : 'CUSTOMER_OWES';
    
    // Validate status: chấp nhận 'ACTIVE', 'PAID', 'CANCELLED', 'paid', 'unpaid'  
    final statusRaw = map['status']?.toString().toUpperCase() ?? 'ACTIVE';
    final validStatuses = ['ACTIVE', 'PAID', 'CANCELLED', 'UNPAID'];
    final status = validStatuses.contains(statusRaw) ? statusRaw : 'ACTIVE';
    
    return Debt(
      id: map['id'],
      firestoreId: map['firestoreId'],
      personName: map['personName'] ?? '',
      phone: map['phone'] ?? '',
      totalAmount: totalAmountSafe,
      paidAmount: paidAmount,
      type: type,
      status: status,
      createdAt: map['createdAt'] is int ? map['createdAt'] : 0,
      note: map['note'],
      linkedId: map['linkedId'],
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'personName': personName,
      'phone': phone,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'type': type,
      'status': status,
      'createdAt': createdAt,
      'note': note,
      'linkedId': linkedId,
    };
  }

  factory Debt.fromFirestore(Map<String, dynamic> data, String id) {
    // Validate type like fromMap() for consistency
    final typeRaw = data['type']?.toString() ?? 'CUSTOMER_OWES';
    final validTypes = ['CUSTOMER_OWES', 'SHOP_OWES', 'OTHER_CUSTOMER_OWES', 'OTHER_SHOP_OWES', 'OWE', 'OWED'];
    final type = validTypes.contains(typeRaw) ? typeRaw : 'CUSTOMER_OWES';

    // Validate status like fromMap()
    final statusRaw = data['status']?.toString().toUpperCase() ?? 'ACTIVE';
    final validStatuses = ['ACTIVE', 'PAID', 'CANCELLED', 'UNPAID'];
    final status = validStatuses.contains(statusRaw) ? statusRaw : 'ACTIVE';

    // Validate amounts
    final totalAmount = (data['totalAmount'] is num) ? (data['totalAmount'] as num).toInt() : 0;
    final paidAmountRaw = (data['paidAmount'] is num) ? (data['paidAmount'] as num).toInt() : 0;
    final paidAmount = paidAmountRaw.clamp(0, totalAmount > 0 ? totalAmount : paidAmountRaw);

    return Debt(
      firestoreId: id,
      personName: data['personName'] ?? '',
      phone: data['phone'] ?? '',
      totalAmount: totalAmount,
      paidAmount: paidAmount,
      type: type,
      status: status,
      createdAt: data['createdAt'] ?? 0,
      note: data['note'],
      linkedId: data['linkedId'],
      isSynced: true,
    );
  }
}
