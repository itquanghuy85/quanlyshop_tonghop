class InventoryZone {
  final String id;
  final String name;
  final String description;
  final List<String> expectedProductCodes;
  final Map<String, int> scannedCounts; // scanned count per product code
  final DateTime? completedAt;
  final bool isActive;

  InventoryZone({
    required this.id,
    required this.name,
    this.description = '',
    required this.expectedProductCodes,
    Map<String, int>? scannedCounts,
    this.completedAt,
    this.isActive = false,
  }) : scannedCounts = scannedCounts ?? {};

  int get totalExpected => expectedProductCodes.length;
  int get totalScanned => scannedCounts.values.fold(0, (sum, count) => sum + count);
  double get progress => totalExpected > 0 ? (totalScanned / totalExpected).clamp(0.0, 1.0) : 0.0;
  bool get isCompleted => progress >= 1.0 && completedAt != null;

  InventoryZone copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? expectedProductCodes,
    Map<String, int>? scannedCounts,
    DateTime? completedAt,
    bool? isActive,
  }) {
    return InventoryZone(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      expectedProductCodes: expectedProductCodes ?? this.expectedProductCodes,
      scannedCounts: scannedCounts ?? this.scannedCounts,
      completedAt: completedAt ?? this.completedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'expectedProductCodes': expectedProductCodes,
      'scannedCounts': scannedCounts,
      'completedAt': completedAt?.toIso8601String(),
      'isActive': isActive,
    };
  }

  factory InventoryZone.fromMap(Map<String, dynamic> map) {
    return InventoryZone(
      id: map['id'],
      name: map['name'],
      description: map['description'] ?? '',
      expectedProductCodes: List<String>.from(map['expectedProductCodes'] ?? []),
      scannedCounts: Map<String, int>.from(map['scannedCounts'] ?? {}),
      completedAt: map['completedAt'] != null ? DateTime.parse(map['completedAt']) : null,
      isActive: map['isActive'] ?? false,
    );
  }
}