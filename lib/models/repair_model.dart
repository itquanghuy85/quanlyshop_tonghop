import 'dart:convert';
import 'repair_service_model.dart';

/// Safely parse int from dynamic value (handles int, double, num, String)
int _parseIntSafe(dynamic value) {
  if (value == null) return 0;
  if (value is int) return value < 0 ? 0 : value;
  if (value is double) return value < 0 ? 0 : value.toInt();
  if (value is num) return value < 0 ? 0 : value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value) ?? double.tryParse(value)?.toInt();
    return (parsed != null && parsed >= 0) ? parsed : 0;
  }
  return 0;
}

class Repair {
  int? id;
  String? firestoreId;
  String customerName;
  String phone;
  bool isWalkIn;
  String? walkInName;
  String? walkInPhone;
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

  // Chi phí vốn đã ghi vào sổ quỹ
  bool costRecordedInFund;
  String? costPaymentMethod; // TIỀN MẶT or CHUYỂN KHOẢN
  int? costRecordedAt; // timestamp when recorded
  int? costRecordedAmount; // fixed amount recorded into fund at record time

  // Getter for receive images
  List<String> get receiveImages {
    if (imagePath == null || imagePath!.trim().isEmpty) return [];

    final raw = imagePath!.trim();
    final output = <String>[];

    void addCandidate(String? value) {
      if (value == null) return;
      var s = value.trim();
      if (s.isEmpty) return;

      // Normalize wrappers from legacy storage formats.
      if ((s.startsWith('"') && s.endsWith('"')) ||
          (s.startsWith("'") && s.endsWith("'"))) {
        s = s.substring(1, s.length - 1).trim();
      }
      if (s.startsWith('[') && s.endsWith(']')) {
        s = s.substring(1, s.length - 1).trim();
      }
      if (s.isEmpty) return;

      if (!output.contains(s)) {
        output.add(s);
      }
    }

    // Case 1: JSON array string (common in older migrations)
    if (raw.startsWith('[') && raw.endsWith(']')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            addCandidate(item?.toString());
          }
          if (output.isNotEmpty) return output;
        }
      } catch (_) {
        // Fallback to delimiter parsing below.
      }
    }

    // Case 2: Delimited list (comma/semicolon/newline)
    final parts = raw
        .split(RegExp(r'[,;\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty);

    for (final part in parts) {
      addCandidate(part);
    }

    return output;
  }

  Repair({
    this.id,
    this.firestoreId,
    required this.customerName,
    required this.phone,
    this.isWalkIn = false,
    this.walkInName,
    this.walkInPhone,
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
    this.costRecordedInFund = false,
    this.costPaymentMethod,
    this.costRecordedAt,
    this.costRecordedAmount,
  });

  int get servicesCost => services.fold(0, (sum, s) => sum + s.cost);

  /// Tổng chi phí canonical của đơn sửa.
  /// Ưu tiên trường cost vì đây là nơi đang lưu tổng chi phí thực tế
  /// gồm cả dịch vụ và linh kiện. Với dữ liệu cũ chưa đồng bộ đúng,
  /// fallback sang tổng dịch vụ nếu cost đang bằng 0.
  int get totalCost {
    if (cost > 0) return cost;
    final calc = servicesCost;
    if (calc > 0) return calc;
    return 0;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'customerName': customerName,
      'phone': phone,
      'isWalkIn': isWalkIn ? 1 : 0,
      'walkInName': walkInName,
      'walkInPhone': walkInPhone,
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
      'costRecordedInFund': costRecordedInFund ? 1 : 0,
      'costPaymentMethod': costPaymentMethod,
      'costRecordedAt': costRecordedAt,
      'costRecordedAmount': costRecordedAmount,
    };
  }

  factory Repair.fromMap(Map<String, dynamic> map) {
    return Repair(
      id: map['id'],
      firestoreId: map['firestoreId'],
      customerName: map['customerName'] ?? "",
      phone: map['phone'] ?? "",
      isWalkIn: map['isWalkIn'] == 1 || map['isWalkIn'] == true,
      walkInName: map['walkInName'],
      walkInPhone: map['walkInPhone'],
      model: map['model'] ?? "",
      issue: map['issue'] ?? "",
      accessories: map['accessories'] ?? "Không có",
      address: map['address'] ?? "",
      imagePath: map['imagePath'],
      deliveredImage: map['deliveredImage'],
      warranty: map['warranty'] ?? "Không bảo hành",
      partsUsed: map['partsUsed'] ?? "",
      status: map['status'] ?? 1,
      price: _parseIntSafe(map['price']),
      cost: _parseIntSafe(map['cost']),
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
      costRecordedInFund:
          map['costRecordedInFund'] == 1 ||
          map['costRecordedInFund'] == true,
      costPaymentMethod: map['costPaymentMethod'],
      costRecordedAt: map['costRecordedAt'],
      costRecordedAmount: _parseIntSafe(map['costRecordedAmount']),
    );
  }

  Repair copyWith({
    int? id,
    String? firestoreId,
    String? customerName,
    String? phone,
    bool? isWalkIn,
    String? walkInName,
    String? walkInPhone,
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
    bool? costRecordedInFund,
    String? costPaymentMethod,
    int? costRecordedAt,
    int? costRecordedAmount,
  }) {
    return Repair(
      id: id ?? this.id,
      firestoreId: firestoreId ?? this.firestoreId,
      customerName: customerName ?? this.customerName,
      phone: phone ?? this.phone,
      isWalkIn: isWalkIn ?? this.isWalkIn,
      walkInName: walkInName ?? this.walkInName,
      walkInPhone: walkInPhone ?? this.walkInPhone,
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
      costRecordedInFund:
          costRecordedInFund ?? this.costRecordedInFund,
      costPaymentMethod:
          costPaymentMethod ?? this.costPaymentMethod,
      costRecordedAt:
          costRecordedAt ?? this.costRecordedAt,
        costRecordedAmount:
          costRecordedAmount ?? this.costRecordedAmount,
    );
  }
}
