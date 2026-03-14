/// Model for salvage phones (Kho máy xác) - phones purchased from customers for parts/resale.
class SalvagePhone {
  int? id;
  String? firestoreId;
  String? shopId;
  String deviceName; // Tên thiết bị (e.g. "iPhone 8 Plus")
  String? customerName; // Tên khách bán
  String? customerPhone; // SĐT khách
  int cost; // Giá mua (VNĐ)
  String? notes; // Ghi chú
  String? images; // Comma-separated URLs
  String status; // STORED / USED / SOLD / DISCARDED
  int createdAt; // epoch ms
  int? updatedAt;
  String? createdBy; // email or name of staff
  bool isSynced;
  bool deleted;

  SalvagePhone({
    this.id,
    this.firestoreId,
    this.shopId,
    required this.deviceName,
    this.customerName,
    this.customerPhone,
    required this.cost,
    this.notes,
    this.images,
    this.status = 'STORED',
    required this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.isSynced = false,
    this.deleted = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'shopId': shopId,
      'deviceName': deviceName,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'cost': cost,
      'notes': notes,
      'images': images,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'createdBy': createdBy,
      'isSynced': isSynced ? 1 : 0,
      'deleted': deleted ? 1 : 0,
    };
  }

  factory SalvagePhone.fromMap(Map<String, dynamic> map) {
    final costRaw = map['cost'];
    final cost = (costRaw is int) ? costRaw : (int.tryParse('$costRaw') ?? 0);
    return SalvagePhone(
      id: map['id'],
      firestoreId: map['firestoreId']?.toString(),
      shopId: map['shopId']?.toString(),
      deviceName: map['deviceName']?.toString() ?? '',
      customerName: map['customerName']?.toString(),
      customerPhone: map['customerPhone']?.toString(),
      cost: cost < 0 ? 0 : cost,
      notes: map['notes']?.toString(),
      images: map['images']?.toString(),
      status: map['status']?.toString() ?? 'STORED',
      createdAt: map['createdAt'] is int
          ? map['createdAt']
          : (int.tryParse('${map['createdAt']}') ?? 0),
      updatedAt: map['updatedAt'] is int
          ? map['updatedAt']
          : (int.tryParse('${map['updatedAt']}') ?? null),
      createdBy: map['createdBy']?.toString(),
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
      deleted: map['deleted'] == 1 || map['deleted'] == true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'deviceName': deviceName,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'cost': cost,
      'notes': notes,
      'images': images,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'createdBy': createdBy,
    };
  }

  SalvagePhone copyWith({
    int? id,
    String? firestoreId,
    String? shopId,
    String? deviceName,
    String? customerName,
    String? customerPhone,
    int? cost,
    String? notes,
    String? images,
    String? status,
    int? createdAt,
    int? updatedAt,
    String? createdBy,
    bool? isSynced,
    bool? deleted,
  }) {
    return SalvagePhone(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      shopId: shopId ?? this.shopId,
      deviceName: deviceName ?? this.deviceName,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      cost: cost ?? this.cost,
      notes: notes ?? this.notes,
      images: images ?? this.images,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      isSynced: isSynced ?? this.isSynced,
      deleted: deleted ?? this.deleted,
    );
  }

  /// Status display label in Vietnamese
  String get statusLabel {
    switch (status) {
      case 'STORED':
        return 'Đang lưu kho';
      case 'USED':
        return 'Đã dùng linh kiện';
      case 'SOLD':
        return 'Đã bán';
      case 'DISCARDED':
        return 'Đã hủy';
      default:
        return status;
    }
  }

  /// Status color for UI badges
  static int statusColor(String status) {
    switch (status) {
      case 'STORED':
        return 0xFF2196F3; // blue
      case 'USED':
        return 0xFFFF9800; // orange
      case 'SOLD':
        return 0xFF4CAF50; // green
      case 'DISCARDED':
        return 0xFF9E9E9E; // grey
      default:
        return 0xFF9E9E9E;
    }
  }

  List<String> get imageList {
    if (images == null || images!.isEmpty) return [];
    return images!.split(',').where((s) => s.trim().isNotEmpty).toList();
  }
}
