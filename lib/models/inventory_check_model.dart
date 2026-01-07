class InventoryCheck {
  int? id;
  String? firestoreId;
  String checkType; // 'PHONE' hoặc 'ACCESSORY'
  int checkDate;
  String checkedBy;
  List<InventoryCheckItem> items;
  bool isCompleted;
  bool isSynced;
  int createdAt;

  InventoryCheck({
    this.id,
    this.firestoreId,
    required this.checkType,
    required this.checkDate,
    required this.checkedBy,
    required this.items,
    this.isCompleted = false,
    this.isSynced = false,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId ?? "inv_check_$createdAt",
      'type': checkType,
      'checkDate': checkDate,
      'checkedBy': checkedBy,
      'itemsJson': items.map((item) => item.toMap()).toList(),
      'isCompleted': isCompleted ? 1 : 0,
      'isSynced': isSynced ? 1 : 0,
      'createdAt': createdAt,
    };
  }

  factory InventoryCheck.fromMap(Map<String, dynamic> map) {
    return InventoryCheck(
      id: map['id'],
      firestoreId: map['firestoreId'],
      checkType: map['type'] ?? map['checkType'] ?? 'PHONE',
      checkDate: map['checkDate'] ?? 0,
      checkedBy: map['checkedBy'] ?? '',
      items: (map['itemsJson'] as List<dynamic>?)
          ?.map((item) => InventoryCheckItem.fromMap(item as Map<String, dynamic>))
          .toList() ?? (map['items'] as List<dynamic>?) // fallback for old data
          ?.map((item) => InventoryCheckItem.fromMap(item as Map<String, dynamic>))
          .toList() ?? [],
      isCompleted: map['isCompleted'] == 1 || map['isCompleted'] == true,
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
      createdAt: map['createdAt'] ?? 0,
    );
  }
}

class InventoryCheckItem {
  String itemId; // firestoreId của Product hoặc Part
  String itemName;
  String itemType; // 'PHONE' hoặc 'ACCESSORY'
  String? imei;
  String? color;
  int quantity;
  bool isChecked;
  int checkedAt;

  InventoryCheckItem({
    required this.itemId,
    required this.itemName,
    required this.itemType,
    this.imei,
    this.color,
    required this.quantity,
    this.isChecked = false,
    this.checkedAt = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'itemId': itemId,
      'itemName': itemName,
      'itemType': itemType,
      'imei': imei,
      'color': color,
      'quantity': quantity,
      'isChecked': isChecked ? 1 : 0,
      'checkedAt': checkedAt,
    };
  }

  factory InventoryCheckItem.fromMap(Map<String, dynamic> map) {
    return InventoryCheckItem(
      itemId: map['itemId'] ?? '',
      itemName: map['itemName'] ?? '',
      itemType: map['itemType'] ?? 'PHONE',
      imei: map['imei'],
      color: map['color'],
      quantity: map['quantity'] ?? 1,
      isChecked: map['isChecked'] == 1 || map['isChecked'] == true,
      checkedAt: map['checkedAt'] ?? 0,
    );
  }
}
