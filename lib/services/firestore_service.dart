import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/repair_model.dart';
import '../models/product_model.dart';
import '../models/sale_order_model.dart';
import '../models/purchase_order_model.dart';
import '../models/attendance_model.dart';
import '../models/quick_input_code_model.dart';
import 'user_service.dart';
import 'notification_service.dart';
import 'encryption_service.dart';
import 'financial_activity_service.dart';
import 'money_validation_service.dart';
import 'firestore_write_helper.dart';
import 'event_bus.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;
  static int _expenseFetchCount = 0;
  static int _attendanceFetchCount = 0;

  static String _formatNotifyClock([DateTime? dt]) {
    final t = dt ?? DateTime.now();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${hh}H$mm';
  }

  static bool _isRefreshEvent(String event) {
    return event == EventBus.dataRefresh ||
        event == EventBus.shopChanged ||
        event == 'sync_now_completed' ||
        event == 'app_resumed' ||
        event == 'expenses_changed' ||
        event == 'attendance_changed';
  }

  static DocumentReference<Map<String, dynamic>> repairDocRef(
    String firestoreId,
  ) {
    return _db.collection('repairs').doc(firestoreId);
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watchRepairDoc(
    String firestoreId,
  ) {
    return repairDocRef(firestoreId).snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchRepairsByShop(
    String shopId, {
    required bool useIndexedQuery,
    int indexedLimit = 50,
  }) {
    Query<Map<String, dynamic>> query = _db
        .collection('repairs')
        .where('shopId', isEqualTo: shopId);

    if (useIndexedQuery) {
      query = query.orderBy('updatedAt', descending: true).limit(indexedLimit.clamp(20, 500));
    }

    return query.snapshots();
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>> getRepairDoc(
    String firestoreId,
  ) {
    return repairDocRef(firestoreId).get();
  }

  static Future<void> upsertRepairPatchByFirestoreId(
    String firestoreId,
    Map<String, dynamic> payload,
  ) {
    return repairDocRef(firestoreId).set(payload, SetOptions(merge: true));
  }

  // --- THÔNG BÁO HỆ THỐNG ---
  static Future<void> _notifyAll(
    String title,
    String body, {
    String? type,
    String? id,
    String? summary,
  }) async {
    try {
      await NotificationService.sendCloudNotification(
        title: title,
        body: body,
        type: 'system',
      );
      final shopId = await UserService.getCurrentShopId();
      await _db.collection('chats').add({
        'shopId': shopId,
        'message': "$title: $body",
        'senderId': 'SYSTEM',
        'senderName': 'HỆ THỐNG',
        'linkedType': type,
        'linkedKey': id,
        'linkedSummary': summary,
        'readBy': ['SYSTEM'],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  // --- QUẢN LÝ ĐƠN NHẬP HÀNG (MỚI BỔ SUNG ĐỂ SỬA LỖI BUILD) ---
  static Future<String?> addPurchaseOrder(PurchaseOrder order) async {
    try {
      // --- MONEY VALIDATION ---
      try {
        MoneyValidationService.validateAmount(order.totalAmount);
      } catch (e) {
        debugPrint('❌ addPurchaseOrder: MoneyValidationService failed: $e');
        return null;
      }
      final shopId = await UserService.getCurrentShopId();
      final docId =
          order.firestoreId ?? "po_${order.createdAt}_${order.orderCode}";
      final docRef = _db.collection('purchase_orders').doc(docId);

      Map<String, dynamic> data = order.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();

      await docRef.set(data, SetOptions(merge: true));

      // CẬP NHẬT INVENTORY SAU KHI NHẬP HÀNG
      await _updateInventoryFromPurchaseOrder(order, shopId!);

      _notifyAll(
        "📦 ĐƠN NHẬP MỚI",
        "Vừa nhập hàng từ NCC: ${order.supplierName} - Mã: ${order.orderCode}",
        type: 'purchase_order',
        id: docId,
        summary: "${order.supplierName} - ${order.orderCode}",
      );

      return docId;
    } catch (e) {
      return null;
    }
  }

  // CẬP NHẬT INVENTORY KHI NHẬP HÀNG
  static Future<void> _updateInventoryFromPurchaseOrder(
    PurchaseOrder order,
    String shopId,
  ) async {
    try {
      for (final item in order.items) {
        // Tìm sản phẩm trong inventory dựa trên tên, màu, dung lượng
        final productQuery = await _db
            .collection('products')
            .where('shopId', isEqualTo: shopId)
            .where('name', isEqualTo: item.productName)
            .get();

        // Tìm sản phẩm khớp với color, capacity, condition
        final matchingProducts = productQuery.docs.where((doc) {
          final data = doc.data();
          return data['color'] == item.color &&
              data['capacity'] == item.capacity &&
              data['condition'] == item.condition;
        }).toList();

        if (matchingProducts.isNotEmpty) {
          // Sản phẩm đã tồn tại - cập nhật số lượng và chi phí trung bình
          final existingProduct = matchingProducts.first;
          final productData = existingProduct.data();

          final currentQuantity = productData['quantity'] ?? 0;
          final currentCost = productData['cost'] ?? 0;
          final newQuantity = currentQuantity + item.quantity;

          // Tính chi phí trung bình
          final totalCurrentValue = currentQuantity * currentCost;
          final totalNewValue = item.quantity * item.unitCost;
          final averageCost =
              ((totalCurrentValue + totalNewValue) / newQuantity).round();

          await existingProduct.reference.update({
            'quantity': newQuantity,
            'cost': averageCost,
            'price': item.unitPrice, // Cập nhật giá bán nếu cần
            'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
          });

          debugPrint(
            'Cập nhật sản phẩm: ${item.productName}, SL: $currentQuantity -> $newQuantity, Chi phí TB: $averageCost',
          );
        } else {
          // Sản phẩm chưa tồn tại - tạo mới
          final newProduct = {
            'name': item.productName ?? '',
            'brand': 'KHÁC',
            'imei': item.imei,
            'cost': item.unitCost,
            'price': item.unitPrice,
            'condition': item.condition,
            'status': 1,
            'description': 'Nhập từ đơn: ${order.orderCode}',
            'createdAt': FieldValue.serverTimestamp(),
            'supplier': order.supplierName,
            'type': 'DIEN_THOAI',
            'quantity': item.quantity,
            'color': item.color,
            'capacity': item.capacity,
            'shopId': shopId,
            'isSynced': true,
          };

          await _db.collection('products').add(newProduct);
          debugPrint(
            'Tạo sản phẩm mới: ${item.productName}, SL: ${item.quantity}, Chi phí: ${item.unitCost}',
          );
        }
      }
    } catch (e) {
      debugPrint('Lỗi cập nhật inventory: $e');
      // Không throw error để không làm fail purchase order
    }
  }

  // --- CÁC HÀM CỐ LÕI KHÁC (KHÔNG THAY ĐỔI LOGIC) ---
  static Future<String?> addRepair(Repair r) async {
    try {
      // --- MONEY VALIDATION ---
      try {
        MoneyValidationService.validateAmount(r.price);
        MoneyValidationService.validateAmount(r.cost);
      } catch (e) {
        debugPrint('❌ addRepair: MoneyValidationService failed: $e');
        return null;
      }
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception(
          'Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.',
        );
      }
      final docId = r.firestoreId ?? "rep_${r.createdAt}_${r.phone}";
      final docRef = _db.collection('repairs').doc(docId);
      Map<String, dynamic> data = r.toMap();
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      data['shopId'] = shopId;
      data['firestoreId'] = docRef.id;
      // Mã hóa dữ liệu nhạy cảm trước khi upload
      final encryptedData = EncryptionService.encryptMap(data);
      await docRef.set(encryptedData, SetOptions(merge: true));
      _notifyAll(
        "🔧 MÁY NHẬN MỚI",
        "${r.createdBy} nhận ${r.model} của khách ${r.customerName}",
        type: 'repair',
        id: docRef.id,
        summary: "${r.customerName} - ${r.model}",
      );
      return docRef.id;
    } catch (e) {
      debugPrint('Firestore addRepair error: $e');
      return null;
    }
  }

  static Future<void> upsertRepair(Repair r) async {
    if (r.firestoreId == null) return;
    try {
      // --- MONEY VALIDATION ---
      try {
        MoneyValidationService.validateAmount(r.price);
        MoneyValidationService.validateAmount(r.cost);
      } catch (e) {
        debugPrint('❌ upsertRepair: MoneyValidationService failed: $e');
        return;
      }
      final data = r.toMap();
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);
      await _db
          .collection('repairs')
          .doc(r.firestoreId)
          .set(encryptedData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore upsertRepair error: $e');
    }
  }

  static Future<void> deleteRepair(String firestoreId) async {
    try {
      await _db.collection('repairs').doc(firestoreId).update({
        'deleted': true,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
    } catch (e) {
      debugPrint('Firestore deleteRepair error: $e');
    }
  }

  static Future<String?> addSale(SaleOrder s) async {
    try {
      var shopId = await UserService.getCurrentShopId();
      debugPrint('📤 addSale: shopId=$shopId');

      // Nếu chưa có shopId, thử sync user info để tạo shop mới
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        debugPrint(
          '📤 addSale: shopId is null, attempting to sync user info...',
        );
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await UserService.syncUserInfo(user.uid, user.email ?? '');
          shopId = await UserService.getCurrentShopId();
          debugPrint('📤 addSale: after sync, shopId=$shopId');
        }
      }

      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        debugPrint('❌ addSale: shopId is still null after sync');
        throw Exception(
          'Không tìm thấy thông tin cửa hàng. Vui lòng đăng xuất và đăng nhập lại.',
        );
      }

      // --- MONEY VALIDATION ---
      try {
        MoneyValidationService.validateSale(
          totalPrice: s.totalPrice,
          totalCost: s.totalCost,
          discount: s.discount,
          isInstallment: s.isInstallment,
          downPayment: s.downPayment,
          loanAmount: s.loanAmount,
          loanAmount2: s.loanAmount2,
          // products: ... (add if available)
        );
      } catch (e) {
        debugPrint('❌ addSale: MoneyValidationService failed: $e');
        return null;
      }

      final docId = s.firestoreId ?? "sale_${s.soldAt}";
      final docRef = _db.collection('sales').doc(docId);
      Map<String, dynamic> data = s.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docRef.id;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();

      // Mã hóa dữ liệu nhạy cảm trước khi upload
      final encryptedData = EncryptionService.encryptMap(data);
      debugPrint('📤 addSale: writing to Firestore docId=$docId');

      await docRef.set(encryptedData, SetOptions(merge: true));
      debugPrint('✅ addSale: success docId=$docId');
      EventBus().emit('sales_changed');

      final sellerName = s.sellerName.trim().isNotEmpty
          ? s.sellerName.trim().toUpperCase()
          : 'NV';
      final soldClock = _formatNotifyClock(
        DateTime.fromMillisecondsSinceEpoch(s.soldAt),
      );

      _notifyAll(
        "🎉 $sellerName ĐÃ BÁN LÚC $soldClock",
        "${s.productNames} • KH: ${s.customerName}",
        type: 'sale',
        id: docRef.id,
        summary: "${s.customerName} - ${s.productNames}",
      );
      return docRef.id;
    } catch (e, stackTrace) {
      debugPrint('❌ addSale ERROR: $e');
      debugPrint('Stack: $stackTrace');
      return null;
    }
  }

  static Future<void> updateSaleCloud(SaleOrder s) async {
    if (s.firestoreId == null) return;
    try {
      // --- MONEY VALIDATION ---
      try {
        MoneyValidationService.validateSale(
          totalPrice: s.totalPrice,
          totalCost: s.totalCost,
          discount: s.discount,
          isInstallment: s.isInstallment,
          downPayment: s.downPayment,
          loanAmount: s.loanAmount,
          loanAmount2: s.loanAmount2,
        );
      } catch (e) {
        debugPrint('❌ updateSaleCloud: MoneyValidationService failed: $e');
        return;
      }
      final shopId = await UserService.getCurrentShopId();
      Map<String, dynamic> data = s.toMap();
      data['shopId'] = shopId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);
      await _db
          .collection('sales')
          .doc(s.firestoreId)
          .set(encryptedData, SetOptions(merge: true));
      EventBus().emit('sales_changed');
    } catch (e) {
      debugPrint('Firestore updateSaleCloud error: $e');
    }
  }

  static Future<void> deleteSale(String firestoreId) async {
    try {
      await _db.collection('sales').doc(firestoreId).update({
        'deleted': true,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
      EventBus().emit('sales_changed');
    } catch (e) {
      debugPrint('Firestore deleteSale error: $e');
    }
  }

  static Future<String?> addProduct(Product p) async {
    try {
      // --- MONEY VALIDATION ---
      try {
        MoneyValidationService.validateAmount(p.price);
        MoneyValidationService.validateAmount(p.cost);
      } catch (e) {
        debugPrint('❌ addProduct: MoneyValidationService failed: $e');
        return null;
      }
      final shopId = await UserService.getCurrentShopId();
      final docId = p.firestoreId ?? "prod_${p.createdAt}";
      final docRef = _db.collection('products').doc(docId);
      Map<String, dynamic> data = p.toMap();
      data['shopId'] = shopId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      // Remove firestoreId from data since it's already in docId
      data.remove('firestoreId');
      final encryptedData = EncryptionService.encryptMap(data);
      await docRef.set(encryptedData, SetOptions(merge: true));
      return docRef.id;
    } catch (e) {
      return null;
    }
  }

  static Future<void> updateProductCloud(Product p) async {
    if (p.firestoreId == null) return;
    try {
      // --- MONEY VALIDATION ---
      try {
        MoneyValidationService.validateAmount(p.price);
        MoneyValidationService.validateAmount(p.cost);
      } catch (e) {
        debugPrint('❌ updateProductCloud: MoneyValidationService failed: $e');
        return;
      }
      final data = p.toMap();
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);
      await _db
          .collection('products')
          .doc(p.firestoreId)
          .set(encryptedData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore updateProductCloud error: $e');
    }
  }

  static Future<void> deleteProduct(String firestoreId) async {
    try {
      await _db.collection('products').doc(firestoreId).update({
        'status': 0,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
    } catch (e) {
      debugPrint('Firestore deleteProduct error: $e');
    }
  }

  static Future<void> sendChat({
    required String message,
    required String senderId,
    required String senderName,
    String? linkedType,
    String? linkedKey,
    String? linkedSummary,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      await _db.collection('chats').add({
        'shopId': shopId,
        'message': message,
        'senderId': senderId,
        'senderName': senderName,
        'linkedType': linkedType,
        'linkedKey': linkedKey,
        'linkedSummary': linkedSummary,
        'readBy': [senderId],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> chatStream({
    String? shopId,
    int limit = 20,
  }) {
    Query<Map<String, dynamic>> q = _db.collection('chats');
    if (shopId != null) q = q.where('shopId', isEqualTo: shopId);
    return q
        .orderBy('createdAt', descending: true)
        .limit(limit.clamp(1, 20))
        .snapshots();
  }

  static Future<void> addAuditLogCloud(Map<String, dynamic> logData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final String docId = "log_${logData['createdAt']}_${logData['userId']}";
      logData['shopId'] = shopId;
      logData['firestoreId'] = docId;
      logData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      await _db
          .collection('audit_logs')
          .doc(docId)
          .set(logData, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> addDebtCloud(Map<String, dynamic> debtData) async {
    try {
      // --- MONEY VALIDATION ---
      try {
        MoneyValidationService.validateAmount(debtData['totalAmount'] ?? 0);
      } catch (e) {
        debugPrint('❌ addDebtCloud: MoneyValidationService failed: $e');
        rethrow;
      }
      final shopId = await UserService.getCurrentShopId();
      final String docId =
          debtData['firestoreId'] ??
          "debt_${debtData['createdAt']}_${debtData['phone'] ?? 'ncc'}";
      debtData['shopId'] = shopId;
      debtData['firestoreId'] = docId;
      debtData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(debtData);
      await _db
          .collection('debts')
          .doc(docId)
          .set(encryptedData, SetOptions(merge: true));
      EventBus().emit('debts_changed');
    } catch (e) {
      debugPrint('Error adding debt to cloud: $e');
      rethrow; // Re-throw để caller biết có lỗi
    }
  }

  static Future<void> addDebtPaymentCloud(
    Map<String, dynamic> paymentData,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final String docId =
          paymentData['firestoreId'] ??
          "pay_${paymentData['paidAt']}_${paymentData['debtId'] ?? 'debt'}";

      // --- MONEY VALIDATION ---
      try {
        // Extract required fields for validation
        final paymentAmount = paymentData['amount'] ?? 0;
        final totalDebt = paymentData['totalDebt'] ?? 0;
        final alreadyPaid = paymentData['alreadyPaid'] ?? 0;
        MoneyValidationService.validateDebtPayment(
          paymentAmount: paymentAmount,
          totalDebt: totalDebt,
          alreadyPaid: alreadyPaid,
        );
      } catch (e) {
        debugPrint('❌ addDebtPaymentCloud: MoneyValidationService failed: $e');
        return;
      }

      paymentData['shopId'] = shopId;
      paymentData['firestoreId'] = docId;
      paymentData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(paymentData);
      await _db
          .collection('debt_payments')
          .doc(docId)
          .set(encryptedData, SetOptions(merge: true));
      EventBus().emit('debt_payments_changed');
      EventBus().emit('debts_changed');
    } catch (e) {
      debugPrint('Error adding debt payment to cloud: $e');
    }
  }

  static Future<void> addExpenseCloud(Map<String, dynamic> expData) async {
    try {
      if (((expData['amount'] as int?) ?? 0) <= 0) return;
      final shopId = await UserService.getCurrentShopId();
      // Sử dụng firestoreId đã có trong expData nếu có, không tạo lại
      final String docId =
          expData['firestoreId'] ??
          "exp_${expData['date']}_${expData['title'].hashCode}";
      expData['shopId'] = shopId;
      expData['firestoreId'] = docId;
      expData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(expData);
      await _db
          .collection('expenses')
          .doc(docId)
          .set(encryptedData, SetOptions(merge: true));
      EventBus().emit('expenses_changed');
    } catch (_) {}
  }

  static Future<void> updateExpenseCloud(Map<String, dynamic> expData) async {
    if (expData['firestoreId'] == null) return;
    try {
      final shopId = await UserService.getCurrentShopId();
      expData['shopId'] = shopId;
      expData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(expData);
      await _db
          .collection('expenses')
          .doc(expData['firestoreId'])
          .set(encryptedData, SetOptions(merge: true));
      EventBus().emit('expenses_changed');
    } catch (e) {
      debugPrint('Firestore updateExpenseCloud error: $e');
    }
  }

  static Future<void> deleteExpenseCloud(String firestoreId) async {
    try {
      await _db.collection('expenses').doc(firestoreId).update({
        'deleted': true,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
      EventBus().emit('expenses_changed');
    } catch (e) {
      debugPrint('Firestore deleteExpenseCloud error: $e');
    }
  }

  // --- SALVAGE PHONES (Kho máy xác) ---
  static Future<void> addSalvagePhoneCloud(Map<String, dynamic> data) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final String docId =
          data['firestoreId'] ??
          'sp_${data['createdAt']}_${data['deviceName'].hashCode}';
      data['shopId'] = shopId;
      data['firestoreId'] = docId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);
      await _db
          .collection('salvage_phones')
          .doc(docId)
          .set(encryptedData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore addSalvagePhoneCloud error: $e');
    }
  }

  static Future<void> updateSalvagePhoneCloud(Map<String, dynamic> data) async {
    if (data['firestoreId'] == null) return;
    try {
      final shopId = await UserService.getCurrentShopId();
      data['shopId'] = shopId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);
      await _db
          .collection('salvage_phones')
          .doc(data['firestoreId'])
          .set(encryptedData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore updateSalvagePhoneCloud error: $e');
    }
  }

  static Future<void> deleteSalvagePhoneCloud(String firestoreId) async {
    try {
      await _db.collection('salvage_phones').doc(firestoreId).update({
        'deleted': true,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
    } catch (e) {
      debugPrint('Firestore deleteSalvagePhoneCloud error: $e');
    }
  }

  static Stream<QuerySnapshot> getExpenseStream() async* {
    try {
      final shopId = await UserService.getCurrentShopId();
      Query query = _db.collection('expenses');

      if (shopId != null) {
        query = query.where('shopId', isEqualTo: shopId);
      }

      QuerySnapshot? lastSnapshot;

      Future<QuerySnapshot> fetchOnce(String reason) async {
        _expenseFetchCount += 1;
        debugPrint(
          '[SYNC][FETCH] collection=expenses count=$_expenseFetchCount reason=$reason limit=20',
        );
        return query.orderBy('date', descending: true).limit(20).get();
      }

      try {
        lastSnapshot = await fetchOnce('initial_open');
        yield lastSnapshot;
      } catch (e) {
        debugPrint('Firestore getExpenseStream initial fetch error: $e');
        if (lastSnapshot != null) {
          yield lastSnapshot;
        }
      }

      await for (final event in EventBus().stream.where(_isRefreshEvent)) {
        try {
          lastSnapshot = await fetchOnce(event);
          yield lastSnapshot;
        } catch (e) {
          debugPrint('Firestore getExpenseStream refresh error: $e');
          if (lastSnapshot != null) {
            yield lastSnapshot;
          }
        }
      }
    } catch (e) {
      debugPrint('Firestore getExpenseStream error: $e');
      yield* const Stream.empty();
    }
  }

  // --- ATTENDANCE CRUD METHODS ---
  static Future<String?> addAttendance(Attendance attendance) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception(
          'Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.',
        );
      }
      final docId =
          attendance.firestoreId ??
          "att_${attendance.dateKey}_${attendance.userId}";
      final docRef = _db.collection('attendance').doc(docId);
      Map<String, dynamic> data = attendance.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);
      await docRef.set(encryptedData, SetOptions(merge: true));
      EventBus().emit('attendance_changed');
      return docId;
    } catch (e) {
      debugPrint('Firestore addAttendance error: $e');
      return null;
    }
  }

  static Future<void> updateAttendanceCloud(Attendance attendance) async {
    if (attendance.firestoreId == null) return;
    try {
      final shopId = await UserService.getCurrentShopId();
      Map<String, dynamic> data = attendance.toMap();
      data['shopId'] = shopId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);
      await _db
          .collection('attendance')
          .doc(attendance.firestoreId)
          .set(encryptedData, SetOptions(merge: true));
      EventBus().emit('attendance_changed');
    } catch (e) {
      debugPrint('Firestore updateAttendanceCloud error: $e');
    }
  }

  static Future<void> deleteAttendance(String firestoreId) async {
    try {
      await _db.collection('attendance').doc(firestoreId).update({
        'deleted': true,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
      EventBus().emit('attendance_changed');
    } catch (e) {
      debugPrint('Firestore deleteAttendance error: $e');
    }
  }

  // --- CASH CLOSINGS CRUD METHODS ---
  static Future<void> upsertCashClosingCloud(
    Map<String, dynamic> closingData,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final dateKey = closingData['dateKey'] as String;
      final docId = closingData['firestoreId'] ?? "closing_${shopId}_$dateKey";

      closingData['shopId'] = shopId;
      closingData['firestoreId'] = docId;
      closingData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();

      await _db
          .collection('cash_closings')
          .doc(docId)
          .set(closingData, SetOptions(merge: true));
      debugPrint('Cash closing synced to cloud: $docId');
    } catch (e) {
      debugPrint('Error syncing cash closing to cloud: $e');
    }
  }

  static Future<Map<String, dynamic>?> getCashClosingFromCloud(
    String dateKey,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final docId = "closing_${shopId}_$dateKey";
      final doc = await _db.collection('cash_closings').doc(docId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      debugPrint('Error getting cash closing from cloud: $e');
      return null;
    }
  }

  static Stream<DocumentSnapshot> getCashClosingStream(String dateKey) async* {
    try {
      final shopId = await UserService.getCurrentShopId();
      final docId = "closing_${shopId}_$dateKey";
      yield* _db.collection('cash_closings').doc(docId).snapshots();
    } catch (e) {
      debugPrint('Error streaming cash closing: $e');
    }
  }

  static Stream<QuerySnapshot> getAttendanceStream({
    String? userId,
    String? dateKey,
  }) async* {
    try {
      final shopId = await UserService.getCurrentShopId();
      Query query = _db.collection('attendance');

      if (shopId != null) {
        query = query.where('shopId', isEqualTo: shopId);
      }

      if (userId != null) {
        query = query.where('userId', isEqualTo: userId);
      }

      if (dateKey != null) {
        query = query.where('dateKey', isEqualTo: dateKey);
      }

      QuerySnapshot? lastSnapshot;

      Future<QuerySnapshot> fetchOnce(String reason) async {
        _attendanceFetchCount += 1;
        debugPrint(
          '[SYNC][FETCH] collection=attendance count=$_attendanceFetchCount reason=$reason limit=20',
        );
        return query.orderBy('createdAt', descending: true).limit(20).get();
      }

      try {
        lastSnapshot = await fetchOnce('initial_open');
        yield lastSnapshot;
      } catch (e) {
        debugPrint('Firestore getAttendanceStream initial fetch error: $e');
        if (lastSnapshot != null) {
          yield lastSnapshot;
        }
      }

      await for (final event in EventBus().stream.where(_isRefreshEvent)) {
        try {
          lastSnapshot = await fetchOnce(event);
          yield lastSnapshot;
        } catch (e) {
          debugPrint('Firestore getAttendanceStream refresh error: $e');
          if (lastSnapshot != null) {
            yield lastSnapshot;
          }
        }
      }
    } catch (e) {
      debugPrint('Firestore getAttendanceStream error: $e');
      yield* const Stream.empty();
    }
  }

  static Future<String?> resetEntireShopData({String? shopIdOverride}) async {
    try {
      final shopId = (shopIdOverride ?? await UserService.getCurrentShopId())?.trim();
      if (shopId == null || shopId.isEmpty) {
        return 'Không tìm thấy shopId. Vui lòng đăng xuất và đăng nhập lại để đồng bộ dữ liệu shop.';
      }
      final collections = [
        'repairs',
        'sales',
        'products',
        'debts',
        'expenses',
        'audit_logs',
        'attendance',
        'chats',
        'inventory_checks',
        'cash_closings',
        'purchase_orders',
        'quick_input_codes',
        'debt_payments',
        'payroll_settings',
        'work_schedules',
        'suppliers',
        'customers',
      ];

      for (var colName in collections) {
        try {
          final queries = <Query<Map<String, dynamic>>>[
            _db.collection(colName).where('shopId', isEqualTo: shopId),
          ];

          for (var query in queries) {
            final snapshots = await query.get();
            if (snapshots.docs.isNotEmpty) {
              // Delete in batches of 400 to stay under Firestore limit of 500
              const batchSize = 400;
              for (int i = 0; i < snapshots.docs.length; i += batchSize) {
                final batch = _db.batch();
                final end = (i + batchSize < snapshots.docs.length)
                    ? i + batchSize
                    : snapshots.docs.length;
                for (int j = i; j < end; j++) {
                  batch.delete(snapshots.docs[j].reference);
                }
                await batch.commit();
              }
              debugPrint('Deleted ${snapshots.docs.length} docs from $colName');
            } else {
              debugPrint('No docs to delete in $colName');
            }
          }
        } catch (e) {
          debugPrint('Error deleting from $colName: $e');
          return 'Lỗi khi xóa collection $colName: $e';
        }
      }
      return null; // Success
    } catch (e) {
      debugPrint('Reset shop data error: $e');
      return 'Lỗi tổng quát: $e';
    }
  }

  static Future<void> deleteCustomer(String firestoreId) async {
    try {
      await _db.collection('customers').doc(firestoreId).delete();
      EventBus().emit('customers_changed');
    } catch (_) {}
  }

  /// Xóa supplier theo firestoreId - soft delete với deleted: true để tránh sync lại
  static Future<void> deleteSupplier(String firestoreId) async {
    try {
      // Soft delete: đánh dấu deleted = true thay vì xóa hẳn
      await _db.collection('suppliers').doc(firestoreId).update({
        'deleted': true,
        'active': 0,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
      debugPrint('Firestore deleteSupplier: $firestoreId soft deleted');
    } catch (e) {
      // Nếu doc không tồn tại hoặc lỗi update, thử xóa hẳn
      try {
        await _db.collection('suppliers').doc(firestoreId).delete();
      } catch (_) {}
      debugPrint('Firestore deleteSupplier error: $e');
    }
  }

  // --- QUẢN LÝ MÃ NHẬP NHANH (Đồng bộ giữa các thiết bị trong shop) ---
  static Future<String?> addQuickInputCode(QuickInputCode code) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final docId =
          code.firestoreId ??
          "qic_${code.createdAt}_${code.name.replaceAll(' ', '_')}";
      final docRef = _db.collection('quick_input_codes').doc(docId);

      Map<String, dynamic> data = code.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docId;
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);

      await docRef.set(encryptedData, SetOptions(merge: true));
      return docId;
    } catch (e) {
      debugPrint('Error adding quick input code: $e');
      return null;
    }
  }

  static Future<void> updateQuickInputCode(QuickInputCode code) async {
    try {
      if (code.firestoreId == null) return;
      final docRef = _db.collection('quick_input_codes').doc(code.firestoreId);

      Map<String, dynamic> data = code.toMap();
      data['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(data);

      await docRef.update(encryptedData);
    } catch (e) {
      debugPrint('Error updating quick input code: $e');
    }
  }

  static Future<void> deleteQuickInputCode(String firestoreId) async {
    try {
      await _db.collection('quick_input_codes').doc(firestoreId).update({
        'deleted': true,
        'isActive': false,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
    } catch (e) {
      debugPrint('Error deleting quick input code: $e');
    }
  }

  static Future<List<QuickInputCode>> getQuickInputCodesForShop() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];

      final querySnapshot = await _db
          .collection('quick_input_codes')
          .where('shopId', isEqualTo: shopId)
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        data['firestoreId'] = doc.id;
        return QuickInputCode.fromMap(data);
      }).toList();
    } catch (e) {
      debugPrint('Error getting quick input codes: $e');
      return [];
    }
  }

  // --- NOTIFICATIONS ---
  static Future<void> createNotification({
    required String title,
    required String body,
    required String type,
    String? userId,
    Map<String, dynamic>? data,
    String priority = 'normal',
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final currentUser = FirebaseAuth.instance.currentUser;

      if (shopId == null) return;

      final notificationData = {
        'shopId': shopId,
        'userId': userId,
        'title': title,
        'body': body,
        'type': type,
        'priority': priority,
        'isRead': false,
        'senderId': currentUser?.uid ?? 'system',
        'senderName':
            currentUser?.email?.split('@').first.toUpperCase() ?? 'SYSTEM',
        'data': data ?? {},
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30)),
        ),
      };

      await _db.collection('notifications').add(notificationData);

      // Đồng thời gửi FCM push
      await NotificationService.sendCloudNotification(
        title: title,
        body: body,
        type: type,
        targetUserId: userId,
        data: data,
      );
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  static Stream<List<Map<String, dynamic>>> getUserNotifications() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value([]);

    return UserService.getCurrentShopId().asStream().asyncExpand((shopId) {
      if (shopId == null) return Stream.value([]);

      return _db
          .collection('shop_notifications')
          .where('shopId', isEqualTo: shopId)
          .where(
            Filter.or(
              Filter('targetUserId', isEqualTo: user.uid),
              Filter('targetUserId', isNull: true),
            ),
          )
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) => {...doc.data(), 'id': doc.id})
                .toList(),
          )
          .handleError((error) {
            debugPrint('Error in notifications stream: $error');
            return [];
          });
    });
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _db.collection('shop_notifications').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  static Stream<int> getUnreadCount() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return Stream.value(0);

    return UserService.getCurrentShopId().asStream().asyncExpand((shopId) {
      if (shopId == null) return Stream.value(0);

      return _db
          .collection('shop_notifications')
          .where('shopId', isEqualTo: shopId)
          .where('isRead', isEqualTo: false)
          .where(
            Filter.or(
              Filter('targetUserId', isEqualTo: user.uid),
              Filter('targetUserId', isNull: true),
            ),
          )
          .limit(20)
          .snapshots()
          .map((snapshot) => snapshot.docs.length)
          .handleError((error) {
            debugPrint('Error in unread count stream: $error');
            return 0;
          });
    });
  }

  // --- REPAIR PARTNERS ---
  static Future<String?> addRepairPartner(
    Map<String, dynamic> partnerData,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception(
          'Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.',
        );
      }

      // Sử dụng firestoreId đã có sẵn từ local (tránh duplicate từ realtime sync)
      final existingFirestoreId = partnerData['firestoreId'];
      if (existingFirestoreId == null ||
          existingFirestoreId.toString().isEmpty) {
        throw Exception('firestoreId is required for addRepairPartner');
      }

      final docRef = _db.collection('repair_partners').doc(existingFirestoreId);
      partnerData['shopId'] = shopId;
      partnerData['firestoreId'] = existingFirestoreId;
      partnerData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(partnerData);
      await docRef.set(encryptedData, SetOptions(merge: true));
      return existingFirestoreId;
    } catch (e) {
      debugPrint('Firestore addRepairPartner error: $e');
      return null;
    }
  }

  static Future<void> updateRepairPartner(
    Map<String, dynamic> partnerData,
  ) async {
    try {
      final firestoreId = partnerData['firestoreId'];
      if (firestoreId == null) return;
      partnerData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(partnerData);
      await _db
          .collection('repair_partners')
          .doc(firestoreId)
          .update(encryptedData);
    } catch (e) {
      debugPrint('Firestore updateRepairPartner error: $e');
    }
  }

  static Future<void> deleteRepairPartner(int partnerId) async {
    try {
      // Note: We need to get the firestoreId from the local DB first
      // This method assumes the caller has the firestoreId
      // In practice, this would be called from the service layer
      debugPrint(
        'Firestore deleteRepairPartner not implemented - needs firestoreId',
      );
    } catch (e) {
      debugPrint('Firestore deleteRepairPartner error: $e');
    }
  }

  /// Xóa repair partner theo firestoreId - soft delete với deleted: true
  static Future<void> deleteRepairPartnerByFirestoreId(
    String firestoreId,
  ) async {
    try {
      // Soft delete: đánh dấu deleted = true thay vì xóa hẳn để tránh sync lại
      await _db.collection('repair_partners').doc(firestoreId).update({
        'deleted': true,
        'active': 0,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
      debugPrint(
        'Firestore deleteRepairPartnerByFirestoreId: $firestoreId deleted',
      );
    } catch (e) {
      // Nếu doc không tồn tại, thử xóa hẳn
      try {
        await _db.collection('repair_partners').doc(firestoreId).delete();
      } catch (_) {}
      debugPrint('Firestore deleteRepairPartnerByFirestoreId error: $e');
    }
  }

  // --- PARTNER REPAIR HISTORY ---
  static Future<String?> addPartnerRepairHistory(
    Map<String, dynamic> historyData,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception(
          'Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.',
        );
      }
      final docId =
          historyData['firestoreId'] ??
          "partner_history_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('partner_repair_history').doc(docId);
      historyData['shopId'] = shopId;
      historyData['firestoreId'] = docRef.id;
      historyData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(historyData);
      await docRef.set(encryptedData, SetOptions(merge: true));
      return docRef.id;
    } catch (e) {
      debugPrint('Firestore addPartnerRepairHistory error: $e');
      return null;
    }
  }

  static Future<void> deletePartnerRepairHistoryByFirestoreId(
    String firestoreId,
  ) async {
    try {
      await _db.collection('partner_repair_history').doc(firestoreId).update({
        'deleted': true,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
    } catch (e) {
      try {
        await _db
            .collection('partner_repair_history')
            .doc(firestoreId)
            .delete();
      } catch (_) {}
      debugPrint('Firestore deletePartnerRepairHistoryByFirestoreId error: $e');
    }
  }

  // --- SUPPLIERS ---
  static Future<String?> addSupplier(Map<String, dynamic> supplierData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception(
          'Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.',
        );
      }
      final docId =
          supplierData['firestoreId'] ??
          "supplier_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('suppliers').doc(docId);
      supplierData['shopId'] = shopId;
      supplierData['firestoreId'] = docRef.id;
      supplierData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(supplierData);
      await docRef.set(encryptedData, SetOptions(merge: true));
      return docRef.id;
    } catch (e) {
      debugPrint('Firestore addSupplier error: $e');
      return null;
    }
  }

  static Future<void> updateSupplier(Map<String, dynamic> supplierData) async {
    try {
      final firestoreId = supplierData['firestoreId'];
      if (firestoreId == null) return;
      supplierData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      final encryptedData = EncryptionService.encryptMap(supplierData);
      await _db.collection('suppliers').doc(firestoreId).update(encryptedData);
    } catch (e) {
      debugPrint('Firestore updateSupplier error: $e');
    }
  }

  // --- SUPPLIER IMPORT HISTORY ---
  static Future<String?> addSupplierImportHistory(
    Map<String, dynamic> historyData,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception(
          'Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.',
        );
      }
      final docId =
          historyData['firestoreId'] ??
          "supplier_import_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('supplier_import_history').doc(docId);
      historyData['shopId'] = shopId;
      historyData['firestoreId'] = docRef.id;
      historyData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      await docRef.set(historyData, SetOptions(merge: true));
      return docRef.id;
    } catch (e) {
      debugPrint('Firestore addSupplierImportHistory error: $e');
      return null;
    }
  }

  // --- SUPPLIER PRODUCT PRICES ---
  static Future<String?> addSupplierProductPrices(
    Map<String, dynamic> pricesData,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception(
          'Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.',
        );
      }
      final docId =
          pricesData['firestoreId'] ??
          "supplier_prices_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('supplier_product_prices').doc(docId);
      pricesData['shopId'] = shopId;
      pricesData['firestoreId'] = docRef.id;
      pricesData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      await docRef.set(pricesData, SetOptions(merge: true));
      return docRef.id;
    } catch (e) {
      debugPrint('Firestore addSupplierProductPrices error: $e');
      return null;
    }
  }

  // ========== CUSTOMER METHODS ==========
  static Future<String?> addCustomer(Map<String, dynamic> customerData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final docId =
          customerData['firestoreId'] ??
          "customer_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('customers').doc(docId);
      customerData['shopId'] = shopId;
      customerData['firestoreId'] = docRef.id;
      customerData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      await docRef.set(customerData, SetOptions(merge: true));
      EventBus().emit('customers_changed');
      return docRef.id;
    } catch (e) {
      debugPrint('Firestore addCustomer error: $e');
      return null;
    }
  }

  static Future<bool> updateCustomer(Map<String, dynamic> customerData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final firestoreId = customerData['firestoreId'];
      if (firestoreId == null) return false;

      customerData['shopId'] = shopId;
      customerData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      await _db.collection('customers').doc(firestoreId).update(customerData);
      EventBus().emit('customers_changed');
      return true;
    } catch (e) {
      debugPrint('Firestore updateCustomer error: $e');
      return false;
    }
  }

  static Future<bool> deleteCustomerById(int customerId) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      await _db
          .collection('customers')
          .where('shopId', isEqualTo: shopId)
          .where('id', isEqualTo: customerId)
          .get()
          .then((snapshot) {
            for (var doc in snapshot.docs) {
              doc.reference.update({
                'deleted': true,
                'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
              });
            }
          });
      EventBus().emit('customers_changed');
      return true;
    } catch (e) {
      debugPrint('Firestore deleteCustomer error: $e');
      return false;
    }
  }

  /// TRANSACTION THANH TOÁN CÔNG NỢ - Fix BUG-001 race condition
  ///
  /// Thực hiện atomic: đọc debt + validate + update paidAmount + tạo payment record
  /// Nếu 2 user thanh toán cùng lúc, chỉ 1 user thành công (transaction retry)
  ///
  /// Returns: {success: bool, newPaidAmount: int?, error: String?}
  static Future<Map<String, dynamic>> executeDebtPaymentTransaction({
    required String debtFirestoreId,
    required int payAmount,
    required String paymentMethod,
    required String createdBy,
    String? note,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) {
        return {'success': false, 'error': 'Không tìm thấy thông tin shop'};
      }

      int newPaidAmount = 0;
      String? paymentDocId;
      String debtType = 'CUSTOMER_OWES';
      String personName = 'Không rõ';
      String phone = '';
      int paidAt = DateTime.now().millisecondsSinceEpoch;

      await _db.runTransaction((transaction) async {
        // PHASE 1: Đọc debt document
        final debtRef = _db.collection('debts').doc(debtFirestoreId);
        final debtSnapshot = await transaction.get(debtRef);

        if (!debtSnapshot.exists) {
          throw Exception('DEBT_NOT_FOUND:Công nợ không tồn tại');
        }

        final debtData = EncryptionService.decryptMap(debtSnapshot.data()!);
        final totalAmount = (debtData['totalAmount'] ?? 0) as int;
        final currentPaid = (debtData['paidAmount'] ?? 0) as int;
        final remain = totalAmount - currentPaid;

        // PHASE 2: Validate payment amount
        if (payAmount <= 0) {
          throw Exception('INVALID_AMOUNT:Số tiền phải lớn hơn 0');
        }

        if (payAmount > remain) {
          throw Exception(
            'OVER_PAYMENT:Số tiền ($payAmount) vượt quá số nợ còn lại ($remain)',
          );
        }

        // PHASE 3: Update debt
        newPaidAmount = currentPaid + payAmount;
        final newStatus = newPaidAmount >= totalAmount ? 'PAID' : 'ACTIVE';

        transaction.update(debtRef, {
          'paidAmount': newPaidAmount,
          'status': newStatus,
          'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
        });

        // PHASE 4: Create payment record
        final now = DateTime.now().millisecondsSinceEpoch;
        paidAt = now;
        paymentDocId = 'pay_${now}_$createdBy';
        final paymentRef = _db.collection('debt_payments').doc(paymentDocId);

        // Lấy debtType từ debt để cash_closing có thể phân biệt thu nợ KH vs trả nợ shop
        debtType = debtData['type'] as String? ?? 'CUSTOMER_OWES';
        personName =
            (debtData['personName'] ??
                    debtData['customerName'] ??
                    debtData['supplierName'] ??
                    debtData['name'] ??
                    'Không rõ')
                .toString();
        phone = (debtData['phone'] ?? debtData['phoneNumber'] ?? '').toString();

        final paymentData = {
          'firestoreId': paymentDocId,
          'debtFirestoreId': debtFirestoreId,
          'debtType': debtType,
          'amount': payAmount,
          'paidAt': now,
          'paymentMethod': paymentMethod,
          'createdBy': createdBy,
          'note': note ?? '',
          'shopId': shopId,
          'createdAt': FieldValue.serverTimestamp(),
        };

        transaction.set(paymentRef, EncryptionService.encryptMap(paymentData));
      });

      debugPrint(
        '✅ Debt payment transaction completed: $debtFirestoreId, paid: $payAmount, total paid: $newPaidAmount',
      );

      final isSupplierDebt =
          debtType == 'SHOP_OWES' ||
          debtType == 'OTHER_SHOP_OWES' ||
          debtType == 'OWED';
      if (paymentDocId != null) {
        if (isSupplierDebt) {
          await FinancialActivityService.logSupplierPayment(
            firestoreId: paymentDocId!,
            amount: payAmount,
            paymentMethod: paymentMethod,
            supplierName: personName,
            createdAt: paidAt,
            createdBy: createdBy,
            note: note,
          );
        } else {
          await FinancialActivityService.logDebtCollection(
            firestoreId: paymentDocId!,
            amount: payAmount,
            paymentMethod: paymentMethod,
            customerName: personName,
            phone: phone,
            createdAt: paidAt,
            createdBy: createdBy,
            note: note,
          );
        }
      }

      return {
        'success': true,
        'newPaidAmount': newPaidAmount,
        'paymentDocId': paymentDocId,
      };
    } catch (e) {
      final errorMsg = e.toString();
      debugPrint('❌ Debt payment transaction failed: $errorMsg');

      // Parse custom errors
      if (errorMsg.contains('DEBT_NOT_FOUND:')) {
        return {'success': false, 'error': 'Công nợ không tồn tại trên cloud'};
      }
      if (errorMsg.contains('INVALID_AMOUNT:')) {
        return {'success': false, 'error': 'Số tiền không hợp lệ'};
      }
      if (errorMsg.contains('OVER_PAYMENT:')) {
        final parts = errorMsg.split('OVER_PAYMENT:');
        return {
          'success': false,
          'error': parts.length > 1
              ? parts[1].trim()
              : 'Số tiền vượt quá nợ còn lại',
        };
      }

      return {'success': false, 'error': errorMsg};
    }
  }

  /// TRANSACTION BÁN HÀNG - Fix race condition
  ///
  /// Thực hiện atomic: kiểm tra stock + trừ stock + tạo sale trong 1 Firestore transaction
  /// Nếu 2 user bán cùng lúc, chỉ 1 user thành công (người còn lại bị abort)
  ///
  /// Returns: {success: bool, saleDocId: String?, error: String?, outOfStockItems: List<String>?}
  static Future<Map<String, dynamic>> executeSaleTransaction({
    required List<Map<String, dynamic>>
    items, // [{firestoreId, quantity, productName}]
    required Map<String, dynamic> saleData,
    Map<String, dynamic>? debtData,
  }) async {
    try {
      var shopId = await UserService.getCurrentShopId();
      final currentUser = FirebaseAuth.instance.currentUser;

      // Auto-sync nếu chưa có shopId
      if (shopId == null && currentUser != null) {
        debugPrint(
          '🔄 executeSaleTransaction: shopId is null, syncing user info...',
        );
        await UserService.syncUserInfo(
          currentUser.uid,
          currentUser.email ?? '',
        );
        shopId = await UserService.getCurrentShopId();
        debugPrint('🔄 executeSaleTransaction: after sync, shopId=$shopId');
      }

      if (shopId == null) {
        return {
          'success': false,
          'error':
              'Không tìm thấy thông tin shop. Vui lòng đăng xuất và đăng nhập lại.',
          'needRelogin': true,
        };
      }

      debugPrint(
        '🛒 executeSaleTransaction: shopId=$shopId, userId=${currentUser?.uid}',
      );

      String? saleDocId;
      List<String> outOfStockItems = [];

      await _db.runTransaction((transaction) async {
        // PHASE 1: Đọc tất cả products và kiểm tra stock
        Map<String, DocumentSnapshot> productDocs = {};

        for (var item in items) {
          final firestoreId = item['firestoreId'] as String?;
          if (firestoreId == null || firestoreId.isEmpty) {
            throw Exception(
              'Product ${item['productName']} chưa được đồng bộ lên cloud',
            );
          }

          final docRef = _db.collection('products').doc(firestoreId);
          final docSnapshot = await transaction.get(docRef);

          if (!docSnapshot.exists) {
            throw Exception(
              'Product ${item['productName']} không tồn tại trên cloud',
            );
          }

          productDocs[firestoreId] = docSnapshot;

          // Kiểm tra stock và shopId
          final data = docSnapshot.data() as Map<String, dynamic>;
          final productShopId = data['shopId'] as String?;
          final cloudStock = (data['quantity'] ?? 0) as int;
          final requestedQty = item['quantity'] as int;

          // Debug log để kiểm tra shopId mismatch
          debugPrint('📦 Product: ${item['productName']}');
          debugPrint('   - Product shopId: $productShopId');
          debugPrint('   - User shopId: $shopId');
          debugPrint('   - Match: ${productShopId == shopId}');

          // Kiểm tra sản phẩm có thuộc shop của user không
          if (productShopId != null && productShopId != shopId) {
            throw Exception(
              'SHOP_MISMATCH:Sản phẩm "${item['productName']}" thuộc shop khác',
            );
          }

          if (cloudStock < requestedQty) {
            outOfStockItems.add(
              '${item['productName']} (còn: $cloudStock, cần: $requestedQty)',
            );
          }
        }

        // Nếu có item hết hàng → abort transaction
        if (outOfStockItems.isNotEmpty) {
          throw Exception('OUT_OF_STOCK:${outOfStockItems.join('|')}');
        }

        // PHASE 2: Trừ stock cho tất cả products
        for (var item in items) {
          final firestoreId = item['firestoreId'] as String;
          final docRef = _db.collection('products').doc(firestoreId);
          final docSnapshot = productDocs[firestoreId]!;
          final data = docSnapshot.data() as Map<String, dynamic>;

          final currentQty = (data['quantity'] ?? 0) as int;
          final requestedQty = item['quantity'] as int;
          final newQty = currentQty - requestedQty;
          final isPhone = (data['type'] ?? 'DIEN_THOAI') == 'DIEN_THOAI';

          transaction.update(docRef, {
            'quantity': newQty,
            'status': (isPhone || newQty <= 0) ? 0 : data['status'],
            'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
          });
        }

        // PHASE 3: Tạo sale document
        final saleDocRef = _db.collection('sales').doc(saleData['firestoreId']);
        saleData['shopId'] = shopId;
        saleData['createdAt'] = FieldValue.serverTimestamp();
        saleData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
        final encryptedSaleData = EncryptionService.encryptMap(saleData);
        transaction.set(saleDocRef, encryptedSaleData);
        saleDocId = saleDocRef.id;

        // PHASE 4: Tạo debt nếu có
        if (debtData != null) {
          final debtDocId =
              debtData['firestoreId'] ??
              'debt_${DateTime.now().millisecondsSinceEpoch}';
          final debtDocRef = _db.collection('debts').doc(debtDocId);
          debtData['shopId'] = shopId;
          debtData['firestoreId'] = debtDocId;
          debtData['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
          final encryptedDebtData = EncryptionService.encryptMap(debtData);
          transaction.set(debtDocRef, encryptedDebtData);
        }
      });

      debugPrint('✅ Sale transaction completed successfully: $saleDocId');
      return {'success': true, 'saleDocId': saleDocId};
    } catch (e) {
      final errorMsg = e.toString();
      debugPrint('❌ Sale transaction failed: $errorMsg');

      // Parse lỗi hết hàng
      if (errorMsg.contains('OUT_OF_STOCK:')) {
        final parts = errorMsg.split('OUT_OF_STOCK:');
        if (parts.length > 1) {
          final itemsStr = parts[1].replaceAll('Exception: ', '').trim();
          return {
            'success': false,
            'error': 'Hết hàng',
            'outOfStockItems': itemsStr.split('|'),
          };
        }
      }

      // Parse lỗi shop mismatch
      if (errorMsg.contains('SHOP_MISMATCH:')) {
        final parts = errorMsg.split('SHOP_MISMATCH:');
        if (parts.length > 1) {
          final msg = parts[1].replaceAll('Exception: ', '').trim();
          return {'success': false, 'error': msg, 'shopMismatch': true};
        }
      }

      // Lỗi permission-denied thường do shopId trong claims không khớp
      if (errorMsg.contains('permission-denied')) {
        return {
          'success': false,
          'error':
              'Không có quyền truy cập. Vui lòng đăng xuất và đăng nhập lại.',
          'needRelogin': true,
        };
      }

      return {'success': false, 'error': errorMsg};
    }
  }

  // ========================
  // EMPLOYEE SALARY SETTINGS
  // ========================

  /// Lấy tất cả cài đặt lương nhân viên của shop
  static Future<List<Map<String, dynamic>>> getEmployeeSalarySettings() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];

      final snapshot = await _db
          .collection('employee_salary_settings')
          .where('shopId', isEqualTo: shopId)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('❌ Error getting employee salary settings: $e');
      return [];
    }
  }

  /// Lấy cài đặt lương của một nhân viên
  static Future<Map<String, dynamic>?> getEmployeeSalarySettingByStaffId(
    String staffId,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;

      final snapshot = await _db
          .collection('employee_salary_settings')
          .where('shopId', isEqualTo: shopId)
          .where('staffId', isEqualTo: staffId)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final doc = snapshot.docs.first;
      final data = doc.data();
      data['id'] = doc.id;
      return data;
    } catch (e) {
      debugPrint('❌ Error getting employee salary setting: $e');
      return null;
    }
  }

  /// Lưu hoặc cập nhật cài đặt lương nhân viên
  static Future<String?> saveEmployeeSalarySettings(
    Map<String, dynamic> settings,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;

      final staffId = settings['staffId'] as String?;
      if (staffId == null || staffId.isEmpty) {
        debugPrint('❌ staffId is required');
        return null;
      }

      // Tìm document hiện có
      final existing = await _db
          .collection('employee_salary_settings')
          .where('shopId', isEqualTo: shopId)
          .where('staffId', isEqualTo: staffId)
          .limit(1)
          .get();

      String docId;
      if (existing.docs.isNotEmpty) {
        // Update existing
        docId = existing.docs.first.id;
      } else {
        // Create new
        docId = 'salary_${staffId}_${DateTime.now().millisecondsSinceEpoch}';
      }

      settings['shopId'] = shopId;
      settings['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      settings['updatedBy'] =
          FirebaseAuth.instance.currentUser?.email ?? 'unknown';

      if (existing.docs.isEmpty) {
        settings['createdAt'] = FieldValue.serverTimestamp();
        settings['isActive'] = true;
      }

      await _db
          .collection('employee_salary_settings')
          .doc(docId)
          .set(settings, SetOptions(merge: true));

      EventBus().emit('employee_salary_settings_changed');
      debugPrint('✅ Saved employee salary settings for $staffId');
      return docId;
    } catch (e) {
      debugPrint('❌ Error saving employee salary settings: $e');
      return null;
    }
  }

  /// Xóa cài đặt lương (soft delete)
  static Future<bool> deleteEmployeeSalarySettings(String staffId) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return false;

      final snapshot = await _db
          .collection('employee_salary_settings')
          .where('shopId', isEqualTo: shopId)
          .where('staffId', isEqualTo: staffId)
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.update({
          'isActive': false,
          'deletedAt': FieldValue.serverTimestamp(),
        });
      }

      EventBus().emit('employee_salary_settings_changed');
      debugPrint('✅ Deleted employee salary settings for $staffId');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting employee salary settings: $e');
      return false;
    }
  }

  /// Lấy cài đặt mặc định của shop (cho nhân viên mới)
  static Future<Map<String, dynamic>?> getShopDefaultSalarySettings() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;

      final snapshot = await _db
          .collection('shop_salary_defaults')
          .doc(shopId)
          .get();

      if (!snapshot.exists) return null;
      return snapshot.data();
    } catch (e) {
      debugPrint('❌ Error getting shop default salary settings: $e');
      return null;
    }
  }

  /// Lưu cài đặt mặc định của shop
  static Future<bool> saveShopDefaultSalarySettings(
    Map<String, dynamic> settings,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return false;

      settings['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      settings['updatedBy'] =
          FirebaseAuth.instance.currentUser?.email ?? 'unknown';

      await _db
          .collection('shop_salary_defaults')
          .doc(shopId)
          .set(settings, SetOptions(merge: true));

      EventBus().emit('employee_salary_settings_changed');
      debugPrint('✅ Saved shop default salary settings');
      return true;
    } catch (e) {
      debugPrint('❌ Error saving shop default salary settings: $e');
      return false;
    }
  }

  /// Lấy danh sách nhân viên theo shopId
  static Future<List<Map<String, dynamic>>?> getStaffByShopId(
    String shopId,
  ) async {
    try {
      // Lấy từ collection users với shopId
      final snapshot = await _db
          .collection('users')
          .where('shopId', isEqualTo: shopId)
          .get();

      final staffList = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['uid'] = doc.id;
        // Hide super admin from staff lists
        if (data['email'] == 'admin@huluca.com') continue;
        staffList.add(data);
      }

      // Sort by name
      staffList.sort((a, b) {
        final nameA = (a['name'] ?? a['displayName'] ?? '')
            .toString()
            .toLowerCase();
        final nameB = (b['name'] ?? b['displayName'] ?? '')
            .toString()
            .toLowerCase();
        return nameA.compareTo(nameB);
      });

      debugPrint('✅ Found ${staffList.length} staff for shop $shopId');
      return staffList;
    } catch (e) {
      debugPrint('❌ Error getting staff by shopId: $e');
      return null;
    }
  }

  /// Alias cho getStaffByShopId - dùng trong SalaryCalculationService
  static Future<List<Map<String, dynamic>>> getShopStaffList(
    String shopId,
  ) async {
    return await getStaffByShopId(shopId) ?? [];
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CÀI ĐẶT KHẤU TRỪ/THUẾ CỦA SHOP
  // ═══════════════════════════════════════════════════════════════════════════

  /// Lấy cài đặt khấu trừ/thuế của shop
  static Future<Map<String, dynamic>?> getShopDeductionSettings(
    String shopId,
  ) async {
    try {
      final snapshot = await _db
          .collection('shop_deduction_settings')
          .doc(shopId)
          .get();

      if (!snapshot.exists) return null;
      return snapshot.data();
    } catch (e) {
      debugPrint('❌ Error getting shop deduction settings: $e');
      return null;
    }
  }

  /// Lưu cài đặt khấu trừ/thuế của shop
  static Future<bool> saveShopDeductionSettings(
    String shopId,
    Map<String, dynamic> settings,
  ) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      debugPrint(
        '💾 saveShopDeductionSettings: shopId=$shopId, uid=${currentUser?.uid}, email=${currentUser?.email}',
      );

      // Remove updatedAt from toMap() - will be replaced by serverTimestamp
      settings.remove('updatedAt');
      settings['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      settings['updatedBy'] = currentUser?.email ?? 'unknown';

      await _db
          .collection('shop_deduction_settings')
          .doc(shopId)
          .set(settings, SetOptions(merge: true));

      debugPrint('✅ Saved shop deduction settings for shop: $shopId');
      return true;
    } catch (e) {
      debugPrint(
        '❌ Error saving shop deduction settings: shopId=$shopId, error=$e',
      );
      rethrow; // Propagate error to caller for better UX
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // KHOẢN THƯỞNG/TRỪ TÙY CHỈNH
  // ═══════════════════════════════════════════════════════════════════════════

  /// Lấy danh sách khoản thưởng/trừ tùy chỉnh của một nhân viên trong tháng
  static Future<List<Map<String, dynamic>>> getCustomSalaryAdjustments({
    required String shopId,
    required String staffId,
    required int month,
    required int year,
  }) async {
    try {
      final snapshot = await _db
          .collection('shops')
          .doc(shopId)
          .collection('custom_salary_adjustments')
          .where('staffId', isEqualTo: staffId)
          .where('month', isEqualTo: month)
          .where('year', isEqualTo: year)
          .get();

      final results = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['firestoreId'] = doc.id;
        results.add(data);
      }
      return results;
    } catch (e) {
      debugPrint('❌ Error getting custom salary adjustments: $e');
      return [];
    }
  }

  /// Lấy tất cả khoản thưởng/trừ tùy chỉnh của shop trong tháng
  static Future<List<Map<String, dynamic>>> getAllCustomSalaryAdjustments({
    required String shopId,
    required int month,
    required int year,
  }) async {
    try {
      final snapshot = await _db
          .collection('shops')
          .doc(shopId)
          .collection('custom_salary_adjustments')
          .where('month', isEqualTo: month)
          .where('year', isEqualTo: year)
          .get();

      final results = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        data['firestoreId'] = doc.id;
        results.add(data);
      }
      return results;
    } catch (e) {
      debugPrint('❌ Error getting all custom salary adjustments: $e');
      return [];
    }
  }

  /// Thêm khoản thưởng/trừ tùy chỉnh
  static Future<bool> addCustomSalaryAdjustment(
    String shopId,
    Map<String, dynamic> adjustment,
  ) async {
    try {
      adjustment['createdAt'] = FieldValue.serverTimestamp();
      adjustment['createdBy'] =
          FirebaseAuth.instance.currentUser?.email ?? 'unknown';

      await _db
          .collection('shops')
          .doc(shopId)
          .collection('custom_salary_adjustments')
          .add(adjustment);

      debugPrint('✅ Added custom salary adjustment');
      return true;
    } catch (e) {
      debugPrint('❌ Error adding custom salary adjustment: $e');
      return false;
    }
  }

  /// Cập nhật khoản thưởng/trừ tùy chỉnh
  static Future<bool> updateCustomSalaryAdjustment(
    String shopId,
    String adjustmentId,
    Map<String, dynamic> adjustment,
  ) async {
    try {
      adjustment['updatedAt'] = FirestoreWriteHelper.serverUpdatedAt();
      adjustment['updatedBy'] =
          FirebaseAuth.instance.currentUser?.email ?? 'unknown';

      await _db
          .collection('shops')
          .doc(shopId)
          .collection('custom_salary_adjustments')
          .doc(adjustmentId)
          .update(adjustment);

      debugPrint('✅ Updated custom salary adjustment');
      return true;
    } catch (e) {
      debugPrint('❌ Error updating custom salary adjustment: $e');
      return false;
    }
  }

  /// Xóa khoản thưởng/trừ tùy chỉnh
  static Future<bool> deleteCustomSalaryAdjustment(
    String shopId,
    String adjustmentId,
  ) async {
    try {
      await _db
          .collection('shops')
          .doc(shopId)
          .collection('custom_salary_adjustments')
          .doc(adjustmentId)
          .delete();

      debugPrint('✅ Deleted custom salary adjustment');
      return true;
    } catch (e) {
      debugPrint('❌ Error deleting custom salary adjustment: $e');
      return false;
    }
  }
}
