import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/db_helper.dart';
import '../models/supplier_payment_model.dart';
import '../services/user_service.dart';

class SupplierPaymentService {
  final DBHelper _db = DBHelper();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<SupplierPayment>> getSupplierPayments(int supplierId) async {
    final shopId = await UserService.getCurrentShopId();
    final maps = await _db.database.then((db) => db.query(
      'supplier_payments',
      where: 'supplierId = ? AND shopId = ? AND deleted = 0',
      whereArgs: [supplierId, shopId],
      orderBy: 'paidAt DESC',
    ));
    return maps.map((map) => SupplierPayment.fromMap(map)).toList();
  }

  Future<int> addSupplierPayment(SupplierPayment payment) async {
    final id = await _db.database.then((db) => db.insert('supplier_payments', payment.toMap()));
    payment.id = id;
    await _syncToCloud(payment);
    return id;
  }

  Future<void> updateSupplierPayment(SupplierPayment payment) async {
    await _db.database.then((db) => db.update(
      'supplier_payments',
      payment.toMap(),
      where: 'id = ?',
      whereArgs: [payment.id],
    ));
    await _syncToCloud(payment);
  }

  Future<void> deleteSupplierPayment(int id) async {
    await _db.database.then((db) => db.update(
      'supplier_payments',
      {'deleted': 1},
      where: 'id = ?',
      whereArgs: [id],
    ));
    // Soft delete in cloud
    final shopId = await UserService.getCurrentShopId();
    final docId = 'sup_pay_${DateTime.now().millisecondsSinceEpoch}';
    await _firestore.collection('supplier_payments').doc(docId).set({
      'supplierId': id,
      'deleted': true,
      'shopId': shopId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _syncToCloud(SupplierPayment payment) async {
    final shopId = await UserService.getCurrentShopId();
    final docId = payment.firestoreId ?? 'sup_pay_${DateTime.now().millisecondsSinceEpoch}';
    payment.firestoreId = docId;
    await _db.database.then((db) => db.update(
      'supplier_payments',
      {'firestoreId': docId, 'isSynced': 1},
      where: 'id = ?',
      whereArgs: [payment.id],
    ));
    await _firestore.collection('supplier_payments').doc(docId).set({
      ...payment.toMap(),
      'shopId': shopId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, int>> getPaymentStats(int supplierId) async {
    final payments = await getSupplierPayments(supplierId);
    final stats = <String, int>{};
    for (var payment in payments) {
      stats[payment.paymentMethod] = (stats[payment.paymentMethod] ?? 0) + payment.amount;
    }
    return stats;
  }
}