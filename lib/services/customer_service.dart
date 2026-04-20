import '../data/db_helper.dart';
import '../models/customer_model.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import 'event_bus.dart';

class CustomerService {
  final db = DBHelper();

  // Customer CRUD
  Future<List<Customer>> getCustomers() async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getCustomers();
    return data
        .where((c) => c['shopId'] == shopId && (c['deleted'] ?? 0) != 1)
        .map((c) => Customer.fromMap(c))
        .toList();
  }

  Future<Customer?> addCustomer(Customer customer) async {
    final customerMap = customer.toMap();
    final shopId = await UserService.getCurrentShopId();
    customerMap['shopId'] = shopId;
    customerMap['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    customerMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    final phone = (customerMap['phone'] ?? '').toString().trim();

    try {
      final id = await db.insertCustomer(customerMap);
      if (id > 0) {
        EventBus().emit('customers_changed');
        final firestoreId = await FirestoreService.addCustomer(customerMap);
        if (firestoreId != null) {
          await db.updateCustomer(id, {'firestoreId': firestoreId});
          EventBus().emit('customers_changed');
          return customer.copyWith(id: id, firestoreId: firestoreId);
        }
        return customer.copyWith(id: id);
      }
    } catch (e) {
      final errorMsg = e.toString();
      final isUniquePhoneError = errorMsg.contains('UNIQUE constraint failed: customers.phone');
      if (!isUniquePhoneError) rethrow;

      // Fallback cho DB cũ còn UNIQUE(phone): lấy bản ghi cũ theo phone rồi update.
      if (phone.isNotEmpty) {
        final existing = await db.getCustomerByPhone(phone, shopId);
        if (existing.isNotEmpty) {
          final existingId = (existing.first['id'] as num?)?.toInt();
          if (existingId != null) {
            await db.updateCustomer(existingId, {
              'name': customerMap['name'],
              'address': customerMap['address'],
              'updatedAt': customerMap['updatedAt'],
              'deleted': 0,
            });
            EventBus().emit('customers_changed');
            return customer.copyWith(id: existingId, firestoreId: existing.first['firestoreId'] as String?);
          }
        }
      }
      return null;
    }

    return null;
  }

  Future<bool> updateCustomer(Customer customer) async {
    final customerMap = customer.toMap();
    customerMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    final result = await db.updateCustomer(customer.id!, customerMap);
    if (result > 0) {
      EventBus().emit('customers_changed');
      await FirestoreService.updateCustomer(customerMap);
      return true;
    }
    return false;
  }

  Future<bool> deleteCustomer(int customerId) async {
    final result = await db.updateCustomer(customerId, {
      'deleted': 1,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    if (result > 0) {
      EventBus().emit('customers_changed');
      await FirestoreService.deleteCustomerById(customerId);
      return true;
    }
    return false;
  }

  // Search customers
  Future<List<Customer>> searchCustomers(String query) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.searchCustomers(query, shopId);
    return data.map((c) => Customer.fromMap(c)).toList();
  }

  // Get customer by phone
  Future<Customer?> getCustomerByPhone(String phone) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getCustomerByPhone(phone, shopId);
    if (data.isNotEmpty) {
      return Customer.fromMap(data.first);
    }
    return null;
  }

  // Update customer stats after sale/repair
  Future<void> updateCustomerStatsAfterSale(String phone, int saleAmount, {String? address, String? name}) async {
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isEmpty) return;
    final customer = await getCustomerByPhone(normalizedPhone);
    if (customer != null) {
      final updatedCustomer = customer.copyWith(
        totalSpent: customer.totalSpent + saleAmount,
        lastVisitAt: DateTime.now().millisecondsSinceEpoch,
        // Luôn cập nhật địa chỉ nếu có dữ liệu mới
        address: (address != null && address.isNotEmpty)
            ? address
            : customer.address,
        // Update name if provided and customer has generic name
        name: (name != null && name.isNotEmpty && (customer.name == 'Khách hàng mới' || customer.name.isEmpty))
            ? name
            : customer.name,
      );
      await updateCustomer(updatedCustomer);
    } else {
      // Create new customer if not exists
      final newCustomer = Customer(
        name: 'Khách hàng mới',
        phone: normalizedPhone,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        totalSpent: saleAmount,
        lastVisitAt: DateTime.now().millisecondsSinceEpoch,
      );
      await addCustomer(newCustomer);
    }
  }

  Future<void> updateCustomerStatsAfterRepair(String phone, int repairCost, {String? address, String? name}) async {
    final normalizedPhone = phone.trim();
    if (normalizedPhone.isEmpty) return;
    final customer = await getCustomerByPhone(normalizedPhone);
    if (customer != null) {
      final updatedCustomer = customer.copyWith(
        totalRepairs: customer.totalRepairs + 1,
        totalRepairCost: customer.totalRepairCost + repairCost,
        lastVisitAt: DateTime.now().millisecondsSinceEpoch,
        // Luôn cập nhật địa chỉ nếu có dữ liệu mới
        address: (address != null && address.isNotEmpty)
            ? address
            : customer.address,
        // Update name if provided and customer has generic name
        name: (name != null && name.isNotEmpty && (customer.name == 'Khách hàng mới' || customer.name.isEmpty))
            ? name
            : customer.name,
      );
      await updateCustomer(updatedCustomer);
    } else {
      // Create new customer if not exists
      final newCustomer = Customer(
        name: 'Khách hàng mới',
        phone: normalizedPhone,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        totalRepairs: 1,
        totalRepairCost: repairCost,
        lastVisitAt: DateTime.now().millisecondsSinceEpoch,
      );
      await addCustomer(newCustomer);
    }
  }

  // Get customer history (sales, repairs and payment requests)
  Future<Map<String, dynamic>> getCustomerHistory(String phone) async {
    final shopId = await UserService.getCurrentShopId();

    // Get sales history
    final salesData = await db.getCustomerSalesHistory(phone, shopId);
    final sales = salesData.map((s) {
      final totalPrice = (s['totalPrice'] as num?)?.toInt() ?? 0;
      final discount = (s['discount'] as num?)?.toInt() ?? 0;
      final finalPrice = totalPrice - discount > 0 ? totalPrice - discount : 0;
      return {
        'type': 'sale',
        'date': s['soldAt'],
        'amount': finalPrice,
        'description': s['productNames'],
        'paymentMethod': s['paymentMethod'],
      };
    }).toList();

    // Get repairs history
    final repairsData = await db.getCustomerRepairsHistory(phone, shopId);
    final repairs = repairsData.map((r) => {
      'type': 'repair',
      'date': r['createdAt'],
      'amount': r['price'],
      'description': '${r['model']} - ${r['issue']}',
      'status': r['status'],
    }).toList();

    // Get payment requests history
    final paymentData = await db.getPaymentRequestsByPhone(phone, shopId);
    final payments = paymentData.map((p) {
      final amount = (p['amount'] as num?)?.toInt() ?? 0;
      final typeLabel = p['paymentTypeLabel'] ?? p['paymentType'] ?? '';
      final bankName = p['bankName'] ?? '';
      final desc = p['description'] ?? '';
      final displayParts = [if (typeLabel.toString().isNotEmpty) typeLabel, if (bankName.toString().isNotEmpty) bankName, if (desc.toString().isNotEmpty) desc];
      return {
        'type': 'payment',
        'date': p['createdAt'] ?? DateTime.now().millisecondsSinceEpoch,
        'amount': amount,
        'description': displayParts.isNotEmpty ? displayParts.join(' · ') : 'Đóng tiền',
        'status': p['status'],
      };
    }).toList();

    // Combine and sort by date
    final history = [...sales, ...repairs, ...payments];
    history.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));

    return {
      'history': history,
      'totalSales': sales.length,
      'totalRepairs': repairs.length,
      'totalPayments': payments.length,
      'totalSpent': sales.fold(0, (sum, s) => sum + (s['amount'] as int)),
      'totalRepairCost': repairs.fold(0, (sum, r) => sum + (r['amount'] as int)),
      'totalPaymentAmount': payments.fold(0, (sum, p) => sum + (p['amount'] as int)),
    };
  }
}