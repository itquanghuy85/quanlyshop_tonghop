import 'dart:convert';
import 'repair_service_model.dart';

class Repair {
  int? id;
  String? firestoreId;
  String customerName;
  String phone;
  String model;
  String issue;
  String accessories;
  String address;
  String? imagePath;
  String? deliveredImage;
  String warranty;
  String partsUsed;
  int status; // 1: Nhận, 2: Sửa, 3: Xong, 4: Giao
  int price;
  int cost;
  String paymentMethod;
  int createdAt;
  int? startedAt;
  int? finishedAt;
  int? deliveredAt;
  String? createdBy;
  String? repairedBy;
  String? deliveredBy;
  int? lastCaredAt;
  bool isSynced;
  bool deleted;

  // Thông tin máy cho tem nhiệt
  String? color;
  String? imei;
  String? condition;

  // Dịch vụ sửa chữa với đối tác
  List<RepairService> services;

  // Ghi chú đơn sửa
  String? notes;

  // Chờ duyệt giao máy (status 3 + pendingDeliveryApproval = true)
  bool pendingDeliveryApproval;

  // Getter for receive images
  List<String> get receiveImages {
    if (imagePath == null || imagePath!.isEmpty) return [];
    return imagePath!
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Repair({
    this.id,
    this.firestoreId,
    required this.customerName,
    required this.phone,
    required this.model,
    required this.issue,
    this.accessories = "Không có",
    this.address = "",
    this.imagePath,
    this.deliveredImage,
    this.warranty = "Không bảo hành",
    this.partsUsed = "",
    this.status = 1,
    this.price = 0,
    this.cost = 0,
    this.paymentMethod = "TIỀN MẶT",
    required this.createdAt,
    this.startedAt,
    this.finishedAt,
    this.deliveredAt,
    this.createdBy,
    this.repairedBy,
    this.deliveredBy,
    this.lastCaredAt,
    this.isSynced = false,
    this.deleted = false,
    this.color,
    this.imei,
    this.condition,
    this.services = const [],
    this.notes,
    this.pendingDeliveryApproval = false,
  });

  /// Tổng chi phí = cost (linh kiện + dịch vụ đã lưu)
  /// Luôn dùng trường cost vì nó đã được cập nhật khi thêm linh kiện/dịch vụ
  int get totalCost => cost;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'customerName': customerName,
      'phone': phone,
      'model': model,
      'issue': issue,
      'accessories': accessories,
      'address': address,
      'imagePath': imagePath,
      'deliveredImage': deliveredImage,
      'warranty': warranty,
      'partsUsed': partsUsed,
      'status': status,
      'price': price,
      'cost': cost,
      'paymentMethod': paymentMethod,
      'createdAt': createdAt,
      'startedAt': startedAt,
      'finishedAt': finishedAt,
      'deliveredAt': deliveredAt,
      'createdBy': createdBy,
      'repairedBy': repairedBy,
      'deliveredBy': deliveredBy,
      'lastCaredAt': lastCaredAt,
      'isSynced': isSynced ? 1 : 0,
      'deleted': deleted ? 1 : 0,
      'color': color,
      'imei': imei,
      'condition': condition,
      'services': jsonEncode(services.map((s) => s.toMap()).toList()),
      'notes': notes,
      'pendingDeliveryApproval': pendingDeliveryApproval ? 1 : 0,
    };
  }

  factory Repair.fromMap(Map<String, dynamic> map) {
    return Repair(
      id: map['id'],
      firestoreId: map['firestoreId'],
      customerName: map['customerName'] ?? "",
      phone: map['phone'] ?? "",
      model: map['model'] ?? "",
      issue: map['issue'] ?? "",
      accessories: map['accessories'] ?? "Không có",
      address: map['address'] ?? "",
      imagePath: map['imagePath'],
      deliveredImage: map['deliveredImage'],
      warranty: map['warranty'] ?? "Không bảo hành",
      partsUsed: map['partsUsed'] ?? "",
      status: map['status'] ?? 1,
      price: map['price'] is int ? (map['price'] < 0 ? 0 : map['price']) : 0,
      cost: map['cost'] is int ? (map['cost'] < 0 ? 0 : map['cost']) : 0,
      paymentMethod: map['paymentMethod'] ?? "TIỀN MẶT",
      createdAt: map['createdAt'] ?? 0,
      startedAt: map['startedAt'],
      finishedAt: map['finishedAt'],
      deliveredAt: map['deliveredAt'],
      createdBy: map['createdBy'],
      repairedBy: map['repairedBy'],
      deliveredBy: map['deliveredBy'],
      lastCaredAt: map['lastCaredAt'],
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
      deleted: map['deleted'] == 1 || map['deleted'] == true,
      color: map['color'],
      imei: map['imei'],
      condition: map['condition'],
      services: map['services'] != null
          ? (jsonDecode(map['services']) as List)
                .map((s) => RepairService.fromMap(s))
                .toList()
          : [],
      notes: map['notes'],
      pendingDeliveryApproval:
          map['pendingDeliveryApproval'] == 1 ||
          map['pendingDeliveryApproval'] == true,
    );
  }

  Repair copyWith({
    int? id,
    String? firestoreId,
    String? customerName,
    String? phone,
    String? model,
    String? issue,
    String? accessories,
    String? address,
    String? imagePath,
    String? deliveredImage,
    String? warranty,
    String? partsUsed,
    int? status,
    int? price,
    int? cost,
    String? paymentMethod,
    int? createdAt,
    int? startedAt,
    int? finishedAt,
    int? deliveredAt,
    String? createdBy,
    String? repairedBy,
    String? deliveredBy,
    int? lastCaredAt,
    bool? isSynced,
    bool? deleted,
    String? color,
    String? imei,
    String? condition,
    List<RepairService>? services,
    String? notes,
    bool? pendingDeliveryApproval,
  }) {
    return Repair(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      customerName: customerName ?? this.customerName,
      phone: phone ?? this.phone,
      model: model ?? this.model,
      issue: issue ?? this.issue,
      accessories: accessories ?? this.accessories,
      address: address ?? this.address,
      imagePath: imagePath ?? this.imagePath,
      deliveredImage: deliveredImage ?? this.deliveredImage,
      warranty: warranty ?? this.warranty,
      partsUsed: partsUsed ?? this.partsUsed,
      status: status ?? this.status,
      price: price ?? this.price,
      cost: cost ?? this.cost,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      createdAt: createdAt ?? this.createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      deliveredAt: deliveredAt ?? this.deliveredAt,
      createdBy: createdBy ?? this.createdBy,
      repairedBy: repairedBy ?? this.repairedBy,
      deliveredBy: deliveredBy ?? this.deliveredBy,
      lastCaredAt: lastCaredAt ?? this.lastCaredAt,
      isSynced: isSynced ?? this.isSynced,
      deleted: deleted ?? this.deleted,
      color: color ?? this.color,
      imei: imei ?? this.imei,
      condition: condition ?? this.condition,
      services: services ?? this.services,
      notes: notes ?? this.notes,
      pendingDeliveryApproval:
          pendingDeliveryApproval ?? this.pendingDeliveryApproval,
    );
  }
}
