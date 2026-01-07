import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/customer_model.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';

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
    customerMap['shopId'] = await UserService.getCurrentShopId();
    customerMap['createdAt'] = DateTime.now().millisecondsSinceEpoch;
    customerMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    final id = await db.insertCustomer(customerMap);
    if (id > 0) {
      final firestoreId = await FirestoreService.addCustomer(customerMap);
      if (firestoreId != null) {
        await db.updateCustomer(id, {'firestoreId': firestoreId});
        return customer.copyWith(id: id, firestoreId: firestoreId);
      }
    }
    return null;
  }

  Future<bool> updateCustomer(Customer customer) async {
    final customerMap = customer.toMap();
    customerMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;

    final result = await db.updateCustomer(customer.id!, customerMap);
    if (result > 0) {
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
  Future<void> updateCustomerStatsAfterSale(String phone, int saleAmount) async {
    final customer = await getCustomerByPhone(phone);
    if (customer != null) {
      final updatedCustomer = customer.copyWith(
        totalSpent: customer.totalSpent + saleAmount,
        lastVisitAt: DateTime.now().millisecondsSinceEpoch,
      );
      await updateCustomer(updatedCustomer);
    } else {
      // Create new customer if not exists
      final newCustomer = Customer(
        name: 'Khách hàng mới',
        phone: phone,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        totalSpent: saleAmount,
        lastVisitAt: DateTime.now().millisecondsSinceEpoch,
      );
      await addCustomer(newCustomer);
    }
  }

  Future<void> updateCustomerStatsAfterRepair(String phone, int repairCost) async {
    final customer = await getCustomerByPhone(phone);
    if (customer != null) {
      final updatedCustomer = customer.copyWith(
        totalRepairs: customer.totalRepairs + 1,
        totalRepairCost: customer.totalRepairCost + repairCost,
        lastVisitAt: DateTime.now().millisecondsSinceEpoch,
      );
      await updateCustomer(updatedCustomer);
    } else {
      // Create new customer if not exists
      final newCustomer = Customer(
        name: 'Khách hàng mới',
        phone: phone,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        totalRepairs: 1,
        totalRepairCost: repairCost,
        lastVisitAt: DateTime.now().millisecondsSinceEpoch,
      );
      await addCustomer(newCustomer);
    }
  }

  // Get customer history (sales and repairs)
  Future<Map<String, dynamic>> getCustomerHistory(String phone) async {
    final shopId = await UserService.getCurrentShopId();

    // Get sales history
    final salesData = await db.getCustomerSalesHistory(phone, shopId);
    final sales = salesData.map((s) => {
      'type': 'sale',
      'date': s['soldAt'],
      'amount': s['totalPrice'],
      'description': s['productNames'],
      'paymentMethod': s['paymentMethod'],
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

    // Combine and sort by date
    final history = [...sales, ...repairs];
    history.sort((a, b) => (b['date'] as int).compareTo(a['date'] as int));

    return {
      'history': history,
      'totalSales': sales.length,
      'totalRepairs': repairs.length,
      'totalSpent': sales.fold(0, (sum, s) => sum + (s['amount'] as int)),
      'totalRepairCost': repairs.fold(0, (sum, r) => sum + (r['amount'] as int)),
    };
  }
}