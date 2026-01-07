class Expense {
  int? id;
  String? firestoreId;
  String title;
  int amount;
  String category;
  int date;
  String? note;
  String paymentMethod;
  bool isSynced;

  Expense({
    this.id,
    this.firestoreId,
    required this.title,
    required this.amount,
    required this.category,
    required this.date,
    this.note,
    this.paymentMethod = "TIỀN MẶT",
    this.isSynced = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firestoreId': firestoreId,
      'title': title,
      'amount': amount,
      'category': category,
      'date': date,
      'note': note,
      'paymentMethod': paymentMethod,
      'isSynced': isSynced ? 1 : 0,
    };
  }

  factory Expense.fromMap(Map<String, dynamic> map) {
    // Validate amount không âm
    final amountRaw = map['amount'] is int ? map['amount'] : 0;
    final amount = amountRaw < 0 ? 0 : amountRaw;
    
    // Validate date
    final dateRaw = map['date'] is int ? map['date'] : 0;
    final date = dateRaw < 0 ? 0 : dateRaw;
    
    return Expense(
      id: map['id'],
      firestoreId: map['firestoreId'],
      title: map['title'] ?? '',
      amount: amount,
      category: map['category'] ?? '',
      date: date,
      note: map['note'],
      paymentMethod: map['paymentMethod'] ?? "TIỀN MẶT",
      isSynced: map['isSynced'] == 1 || map['isSynced'] == true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'title': title,
      'amount': amount,
      'category': category,
      'date': date,
      'note': note,
      'paymentMethod': paymentMethod,
    };
  }

  factory Expense.fromFirestore(Map<String, dynamic> data, String id) {
    // Validate amount không âm
    final amountRaw = data['amount'] is int ? data['amount'] : 0;
    final amount = amountRaw < 0 ? 0 : amountRaw;
    
    return Expense(
      firestoreId: id,
      title: data['title'] ?? '',
      amount: amount,
      category: data['category'] ?? '',
      date: data['date'] ?? 0,
      note: data['note'],
      paymentMethod: data['paymentMethod'] ?? "TIỀN MẶT",
      isSynced: true,
    );
  }
}
