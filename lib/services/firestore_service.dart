import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/repair_model.dart';
import '../models/product_model.dart';
import '../models/sale_order_model.dart';
import '../models/purchase_order_model.dart';
import '../models/attendance_model.dart';
import '../models/quick_input_code_model.dart';
import '../models/repair_partner_model.dart';
import '../models/partner_repair_history_model.dart';
import 'user_service.dart';
import 'notification_service.dart';

class FirestoreService {
  static final _db = FirebaseFirestore.instance;

  // --- THÔNG BÁO HỆ THỐNG ---
  static Future<void> _notifyAll(String title, String body, {String? type, String? id, String? summary}) async {
    try {
      await NotificationService.sendCloudNotification(title: title, body: body, type: 'system');
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
      final shopId = await UserService.getCurrentShopId();
      final docId = order.firestoreId ?? "po_${order.createdAt}_${order.orderCode}";
      final docRef = _db.collection('purchase_orders').doc(docId);

      Map<String, dynamic> data = order.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docId;

      await docRef.set(data, SetOptions(merge: true));

      // CẬP NHẬT INVENTORY SAU KHI NHẬP HÀNG
      await _updateInventoryFromPurchaseOrder(order, shopId!);

      _notifyAll(
        "📦 ĐƠN NHẬP MỚI",
        "Vừa nhập hàng từ NCC: ${order.supplierName} - Mã: ${order.orderCode}",
        type: 'purchase_order',
        id: docId,
        summary: "${order.supplierName} - ${order.orderCode}"
      );

      return docId;
    } catch (e) {
      return null;
    }
  }

  // CẬP NHẬT INVENTORY KHI NHẬP HÀNG
  static Future<void> _updateInventoryFromPurchaseOrder(PurchaseOrder order, String shopId) async {
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
          final averageCost = ((totalCurrentValue + totalNewValue) / newQuantity).round();

          await existingProduct.reference.update({
            'quantity': newQuantity,
            'cost': averageCost,
            'price': item.unitPrice, // Cập nhật giá bán nếu cần
            'updatedAt': FieldValue.serverTimestamp(),
          });

          debugPrint('Cập nhật sản phẩm: ${item.productName}, SL: $currentQuantity -> $newQuantity, Chi phí TB: $averageCost');
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
            'type': 'PHONE',
            'quantity': item.quantity,
            'color': item.color,
            'capacity': item.capacity,
            'shopId': shopId,
            'isSynced': true,
          };

          await _db.collection('products').add(newProduct);
          debugPrint('Tạo sản phẩm mới: ${item.productName}, SL: ${item.quantity}, Chi phí: ${item.unitCost}');
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
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception('Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.');
      }
      final docId = r.firestoreId ?? "rep_${r.createdAt}_${r.phone}";
      final docRef = _db.collection('repairs').doc(docId);
      Map<String, dynamic> data = r.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docRef.id;
      await docRef.set(data, SetOptions(merge: true));
      _notifyAll("🔧 MÁY NHẬN MỚI", "${r.createdBy} nhận ${r.model} của khách ${r.customerName}", type: 'repair', id: docRef.id, summary: "${r.customerName} - ${r.model}");
      return docRef.id;
    } catch (e) { 
      debugPrint('Firestore addRepair error: $e');
      return null; 
    }
  }

  static Future<void> upsertRepair(Repair r) async {
    if (r.firestoreId == null) return;
    try {
      await _db.collection('repairs').doc(r.firestoreId).set(r.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore upsertRepair error: $e');
    }
  }

  static Future<void> deleteRepair(String firestoreId) async {
    try {
      await _db.collection('repairs').doc(firestoreId).update({'deleted': true});
    } catch (e) {
      debugPrint('Firestore deleteRepair error: $e');
    }
  }

  static Future<String?> addSale(SaleOrder s) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception('Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.');
      }
      if (s.totalPrice <= 0 || s.totalCost < 0) {
        throw Exception('Số tiền bán hàng không hợp lệ');
      }
      final docId = s.firestoreId ?? "sale_${s.soldAt}";
      final docRef = _db.collection('sales').doc(docId);
      Map<String, dynamic> data = s.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docRef.id;
      await docRef.set(data, SetOptions(merge: true));
      _notifyAll("🎉 BÁN HÀNG THÀNH CÔNG", "${s.sellerName} vừa bán ${s.productNames} cho ${s.customerName}", type: 'sale', id: docRef.id, summary: "${s.customerName} - ${s.productNames}");
      return docRef.id;
    } catch (e) { return null; }
  }

  static Future<void> updateSaleCloud(SaleOrder s) async {
    if (s.firestoreId == null) return;
    try {
      final shopId = await UserService.getCurrentShopId();
      Map<String, dynamic> data = s.toMap();
      data['shopId'] = shopId;
      await _db.collection('sales').doc(s.firestoreId).set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore updateSaleCloud error: $e');
    }
  }

  static Future<void> deleteSale(String firestoreId) async {
    try {
      await _db.collection('sales').doc(firestoreId).update({'deleted': true});
    } catch (e) {
      debugPrint('Firestore deleteSale error: $e');
    }
  }

  static Future<String?> addProduct(Product p) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final docId = p.firestoreId ?? "prod_${p.createdAt}";
      final docRef = _db.collection('products').doc(docId);
      Map<String, dynamic> data = p.toMap();
      data['shopId'] = shopId;
      // Remove firestoreId from data since it's already in docId
      data.remove('firestoreId');
      await docRef.set(data, SetOptions(merge: true));
      return docRef.id;
    } catch (e) { return null; }
  }

  static Future<void> updateProductCloud(Product p) async {
    if (p.firestoreId == null) return;
    try {
      await _db.collection('products').doc(p.firestoreId).set(p.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore updateProductCloud error: $e');
    }
  }

  static Future<void> deleteProduct(String firestoreId) async {
    try {
      await _db.collection('products').doc(firestoreId).update({'status': 0});
    } catch (e) {
      debugPrint('Firestore deleteProduct error: $e');
    }
  }

  static Future<void> sendChat({required String message, required String senderId, required String senderName, String? linkedType, String? linkedKey, String? linkedSummary}) async {
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

  static Stream<QuerySnapshot<Map<String, dynamic>>> chatStream({String? shopId, int limit = 100}) {
    Query<Map<String, dynamic>> q = _db.collection('chats');
    if (shopId != null) q = q.where('shopId', isEqualTo: shopId);
    return q.orderBy('createdAt', descending: true).limit(limit).snapshots();
  }

  static Future<void> addAuditLogCloud(Map<String, dynamic> logData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final String docId = "log_${logData['createdAt']}_${logData['userId']}";
      logData['shopId'] = shopId;
      logData['firestoreId'] = docId;
      await _db.collection('audit_logs').doc(docId).set(logData, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> addDebtCloud(Map<String, dynamic> debtData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final String docId = debtData['firestoreId'] ?? "debt_${debtData['createdAt']}_${debtData['phone'] ?? 'ncc'}";
      debtData['shopId'] = shopId;
      debtData['firestoreId'] = docId;
      await _db.collection('debts').doc(docId).set(debtData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error adding debt to cloud: $e');
      rethrow; // Re-throw để caller biết có lỗi
    }
  }

  static Future<void> addDebtPaymentCloud(Map<String, dynamic> paymentData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final String docId = paymentData['firestoreId'] ?? "pay_${paymentData['paidAt']}_${paymentData['debtId'] ?? 'debt'}";
      paymentData['shopId'] = shopId;
      paymentData['firestoreId'] = docId;
      await _db.collection('debt_payments').doc(docId).set(paymentData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error adding debt payment to cloud: $e');
    }
  }

  static Future<void> addExpenseCloud(Map<String, dynamic> expData) async {
    try {
      if (((expData['amount'] as int?) ?? 0) <= 0) return;
      final shopId = await UserService.getCurrentShopId();
      final String docId = "exp_${expData['date']}_${expData['title'].hashCode}";
      expData['shopId'] = shopId;
      expData['firestoreId'] = docId;
      await _db.collection('expenses').doc(docId).set(expData, SetOptions(merge: true));
    } catch (_) {}
  }

  static Future<void> updateExpenseCloud(Map<String, dynamic> expData) async {
    if (expData['firestoreId'] == null) return;
    try {
      final shopId = await UserService.getCurrentShopId();
      expData['shopId'] = shopId;
      await _db.collection('expenses').doc(expData['firestoreId']).set(expData, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore updateExpenseCloud error: $e');
    }
  }

  static Future<void> deleteExpenseCloud(String firestoreId) async {
    try {
      await _db.collection('expenses').doc(firestoreId).update({'deleted': true});
    } catch (e) {
      debugPrint('Firestore deleteExpenseCloud error: $e');
    }
  }

  static Stream<QuerySnapshot> getExpenseStream() async* {
    try {
      final shopId = await UserService.getCurrentShopId();
      Query query = _db.collection('expenses');

      if (shopId != null) {
        query = query.where('shopId', isEqualTo: shopId);
      }

      yield* query.orderBy('date', descending: true).snapshots();
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
        throw Exception('Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.');
      }
      final docId = attendance.firestoreId ?? "att_${attendance.dateKey}_${attendance.userId}";
      final docRef = _db.collection('attendance').doc(docId);
      Map<String, dynamic> data = attendance.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docId;
      await docRef.set(data, SetOptions(merge: true));
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
      await _db.collection('attendance').doc(attendance.firestoreId).set(data, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Firestore updateAttendanceCloud error: $e');
    }
  }

  static Future<void> deleteAttendance(String firestoreId) async {
    try {
      await _db.collection('attendance').doc(firestoreId).update({'deleted': true});
    } catch (e) {
      debugPrint('Firestore deleteAttendance error: $e');
    }
  }

  static Stream<QuerySnapshot> getAttendanceStream({String? userId, String? dateKey}) async* {
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

      yield* query.orderBy('createdAt', descending: true).snapshots();
    } catch (e) {
      debugPrint('Firestore getAttendanceStream error: $e');
      yield* const Stream.empty();
    }
  }

  static Future<String?> resetEntireShopData() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) {
        return 'Không tìm thấy shopId. Vui lòng đăng xuất và đăng nhập lại để đồng bộ dữ liệu shop.';
      }
      final collections = ['repairs', 'sales', 'products', 'debts', 'expenses', 'audit_logs', 'attendance', 'chats', 'inventory_checks', 'cash_closings', 'purchase_orders', 'quick_input_codes', 'debt_payments', 'payroll_settings', 'work_schedules', 'suppliers', 'customers'];
      
      for (var colName in collections) {
        try {
          List<Query<Map<String, dynamic>>> queries = [];
          if (colName == 'debts') {
            queries.add(_db.collection(colName).where('shopId', isEqualTo: shopId));
            if (UserService.isCurrentUserSuperAdmin()) {
              queries.add(_db.collection(colName).where('shopId', isNull: true));
              queries.add(_db.collection(colName).where('type', isEqualTo: 'OWE'));
              queries.add(_db.collection(colName).where('type', isEqualTo: 'SHOP_OWES'));
            }
          } else {
            queries.add(_db.collection(colName).where('shopId', isEqualTo: shopId));
          }

          for (var query in queries) {
            final snapshots = await query.get();
            if (snapshots.docs.isNotEmpty) {
              // Delete in batches of 400 to stay under Firestore limit of 500
              const batchSize = 400;
              for (int i = 0; i < snapshots.docs.length; i += batchSize) {
                final batch = _db.batch();
                final end = (i + batchSize < snapshots.docs.length) ? i + batchSize : snapshots.docs.length;
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
    try { await _db.collection('customers').doc(firestoreId).delete(); } catch (_) {}
  }

  static Future<void> deleteSupplier(String firestoreId) async {
    try { await _db.collection('suppliers').doc(firestoreId).delete(); } catch (_) {}
  }

  // --- QUẢN LÝ MÃ NHẬP NHANH (Đồng bộ giữa các thiết bị trong shop) ---
  static Future<String?> addQuickInputCode(QuickInputCode code) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final docId = code.firestoreId ?? "qic_${code.createdAt}_${code.name.replaceAll(' ', '_')}";
      final docRef = _db.collection('quick_input_codes').doc(docId);

      Map<String, dynamic> data = code.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docId;

      await docRef.set(data, SetOptions(merge: true));
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
      data['updatedAt'] = FieldValue.serverTimestamp();

      await docRef.update(data);
    } catch (e) {
      debugPrint('Error updating quick input code: $e');
    }
  }

  static Future<void> deleteQuickInputCode(String firestoreId) async {
    try {
      await _db.collection('quick_input_codes').doc(firestoreId).delete();
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
        'senderName': currentUser?.email?.split('@').first.toUpperCase() ?? 'SYSTEM',
        'data': data ?? {},
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 30))),
      };

      await _db.collection('notifications').add(notificationData);

      // Đồng thời gửi FCM push
      await NotificationService.sendCloudNotification(
        title: title,
        body: body,
        type: type,
        targetUserId: userId,
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
        .collection('notifications')
        .where('shopId', isEqualTo: shopId)
        .where(Filter.or(
          Filter('userId', isEqualTo: user.uid),
          Filter('userId', isNull: true)
        ))
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {
          ...doc.data(),
          'id': doc.id,
        }).toList())
        .handleError((error) {
          debugPrint('Error in notifications stream: $error');
          return [];
        });
    });
  }

  static Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _db.collection('notifications').doc(notificationId).update({
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
        .collection('notifications')
        .where('shopId', isEqualTo: shopId)
        .where('isRead', isEqualTo: false)
        .where(Filter.or(
          Filter('userId', isEqualTo: user.uid),
          Filter('userId', isNull: true)
        ))
        .snapshots()
        .map((snapshot) => snapshot.docs.length)
        .handleError((error) {
          debugPrint('Error in unread count stream: $error');
          return 0;
        });
    });
  }

  // --- REPAIR PARTNERS ---
  static Future<String?> addRepairPartner(Map<String, dynamic> partnerData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception('Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.');
      }
      final docId = partnerData['firestoreId'] ?? "partner_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('repair_partners').doc(docId);
      partnerData['shopId'] = shopId;
      partnerData['firestoreId'] = docRef.id;
      await docRef.set(partnerData, SetOptions(merge: true));
      return docRef.id;
    } catch (e) {
      debugPrint('Firestore addRepairPartner error: $e');
      return null;
    }
  }

  static Future<void> updateRepairPartner(Map<String, dynamic> partnerData) async {
    try {
      final firestoreId = partnerData['firestoreId'];
      if (firestoreId == null) return;
      await _db.collection('repair_partners').doc(firestoreId).update(partnerData);
    } catch (e) {
      debugPrint('Firestore updateRepairPartner error: $e');
    }
  }

  static Future<void> deleteRepairPartner(int partnerId) async {
    try {
      // Note: We need to get the firestoreId from the local DB first
      // This method assumes the caller has the firestoreId
      // In practice, this would be called from the service layer
      debugPrint('Firestore deleteRepairPartner not implemented - needs firestoreId');
    } catch (e) {
      debugPrint('Firestore deleteRepairPartner error: $e');
    }
  }

  // --- PARTNER REPAIR HISTORY ---
  static Future<String?> addPartnerRepairHistory(Map<String, dynamic> historyData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception('Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.');
      }
      final docId = historyData['firestoreId'] ?? "partner_history_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('partner_repair_history').doc(docId);
      historyData['shopId'] = shopId;
      historyData['firestoreId'] = docRef.id;
      await docRef.set(historyData, SetOptions(merge: true));
      return docRef.id;
    } catch (e) {
      debugPrint('Firestore addPartnerRepairHistory error: $e');
      return null;
    }
  }

  // --- SUPPLIERS ---
  static Future<String?> addSupplier(Map<String, dynamic> supplierData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception('Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.');
      }
      final docId = supplierData['firestoreId'] ?? "supplier_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('suppliers').doc(docId);
      supplierData['shopId'] = shopId;
      supplierData['firestoreId'] = docRef.id;
      await docRef.set(supplierData, SetOptions(merge: true));
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
      await _db.collection('suppliers').doc(firestoreId).update(supplierData);
    } catch (e) {
      debugPrint('Firestore updateSupplier error: $e');
    }
  }

  // --- SUPPLIER IMPORT HISTORY ---
  static Future<String?> addSupplierImportHistory(Map<String, dynamic> historyData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception('Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.');
      }
      final docId = historyData['firestoreId'] ?? "supplier_import_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('supplier_import_history').doc(docId);
      historyData['shopId'] = shopId;
      historyData['firestoreId'] = docRef.id;
      await docRef.set(historyData, SetOptions(merge: true));
      return docRef.id;
    } catch (e) {
      debugPrint('Firestore addSupplierImportHistory error: $e');
      return null;
    }
  }

  // --- SUPPLIER PRODUCT PRICES ---
  static Future<String?> addSupplierProductPrices(Map<String, dynamic> pricesData) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null && !UserService.isCurrentUserSuperAdmin()) {
        throw Exception('Không tìm thấy thông tin cửa hàng. Vui lòng liên hệ quản trị viên.');
      }
      final docId = pricesData['firestoreId'] ?? "supplier_prices_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('supplier_product_prices').doc(docId);
      pricesData['shopId'] = shopId;
      pricesData['firestoreId'] = docRef.id;
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
      final docId = customerData['firestoreId'] ?? "customer_${DateTime.now().millisecondsSinceEpoch}";
      final docRef = _db.collection('customers').doc(docId);
      customerData['shopId'] = shopId;
      customerData['firestoreId'] = docRef.id;
      await docRef.set(customerData, SetOptions(merge: true));
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
      await _db.collection('customers').doc(firestoreId).update(customerData);
      return true;
    } catch (e) {
      debugPrint('Firestore updateCustomer error: $e');
      return false;
    }
  }

  static Future<bool> deleteCustomerById(int customerId) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      await _db.collection('customers')
          .where('shopId', isEqualTo: shopId)
          .where('id', isEqualTo: customerId)
          .get()
          .then((snapshot) {
            for (var doc in snapshot.docs) {
              doc.reference.update({'deleted': true, 'updatedAt': FieldValue.serverTimestamp()});
            }
          });
      return true;
    } catch (e) {
      debugPrint('Firestore deleteCustomer error: $e');
      return false;
    }
  }
}
