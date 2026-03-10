import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/payment_request_model.dart';
import 'user_service.dart';

/// Service quản lý yêu cầu đóng tiền - chat-like workflow
class PaymentRequestService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;

  static const String _collection = 'payment_requests';

  // ============== CREATE ==============

  /// Nhân viên tạo yêu cầu đóng tiền
  static Future<String?> createRequest({
    required String customerName,
    required String customerPhone,
    String? customerNote,
    required PaymentType paymentType,
    String? paymentTypeLabel,
    required double amount,
    String? accountNumber,
    String? bankName,
    String? description,
    List<File>? images,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;

      final userName = user.email?.split('@').first.toUpperCase() ?? 'NV';

      // Upload images if any
      final List<String> imageUrls = [];
      if (images != null && images.isNotEmpty) {
        for (int i = 0; i < images.length; i++) {
          final fileName = 'pr_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
          final ref = _storage.ref().child('payment_requests/$shopId/$fileName');
          await ref.putFile(images[i]);
          final url = await ref.getDownloadURL();
          imageUrls.add(url);
        }
      }

      final request = PaymentRequest(
        shopId: shopId,
        senderId: user.uid,
        senderName: userName,
        customerName: customerName,
        customerPhone: customerPhone,
        customerNote: customerNote,
        paymentType: paymentType,
        paymentTypeLabel: paymentTypeLabel,
        amount: amount,
        accountNumber: accountNumber,
        bankName: bankName,
        description: description,
        imageUrls: imageUrls,
        createdAt: DateTime.now(),
      );

      final docRef = await _db.collection(_collection).add(request.toMap());
      debugPrint('✅ PaymentRequest created: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ PaymentRequest create error: $e');
      return null;
    }
  }

  // ============== UPDATE STATUS ==============

  /// Chủ shop cập nhật trạng thái
  static Future<bool> updateStatus(
    String requestId,
    PaymentRequestStatus newStatus, {
    String? rejectReason,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final userName = user.email?.split('@').first.toUpperCase() ?? 'OWNER';

      final Map<String, dynamic> update = {
        'status': newStatus.name,
        'processedBy': user.uid,
        'processedByName': userName,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (newStatus == PaymentRequestStatus.completed ||
          newStatus == PaymentRequestStatus.rejected) {
        update['processedAt'] = FieldValue.serverTimestamp();
      }

      if (newStatus == PaymentRequestStatus.rejected && rejectReason != null) {
        update['rejectReason'] = rejectReason;
      }

      await _db.collection(_collection).doc(requestId).update(update);
      debugPrint('✅ PaymentRequest $requestId → ${newStatus.name}');
      return true;
    } catch (e) {
      debugPrint('❌ PaymentRequest updateStatus error: $e');
      return false;
    }
  }

  /// Soft delete
  static Future<bool> deleteRequest(String requestId) async {
    try {
      await _db.collection(_collection).doc(requestId).update({
        'deleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('❌ PaymentRequest delete error: $e');
      return false;
    }
  }

  // ============== STREAMS ==============

  /// Stream tất cả yêu cầu trong shop (realtime, giống chat)
  static Stream<List<PaymentRequest>> requestsStream({
    PaymentRequestStatus? statusFilter,
    int limit = 50,
  }) async* {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      yield [];
      return;
    }

    Query<Map<String, dynamic>> query = _db
        .collection(_collection)
        .where('shopId', isEqualTo: shopId)
        .where('deleted', isEqualTo: false);

    if (statusFilter != null) {
      query = query.where('status', isEqualTo: statusFilter.name);
    }

    query = query.orderBy('createdAt', descending: true).limit(limit);

    yield* query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => PaymentRequest.fromSnapshot(doc))
          .toList();
    });
  }

  /// Đếm yêu cầu chờ xử lý
  static Stream<int> pendingCountStream() async* {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      yield 0;
      return;
    }

    yield* _db
        .collection(_collection)
        .where('shopId', isEqualTo: shopId)
        .where('deleted', isEqualTo: false)
        .where('status', isEqualTo: PaymentRequestStatus.pending.name)
        .snapshots()
        .map((s) => s.size);
  }

  // ============== QUERIES ==============

  /// Lấy 1 request theo ID
  static Future<PaymentRequest?> getById(String requestId) async {
    try {
      final doc = await _db.collection(_collection).doc(requestId).get();
      if (!doc.exists) return null;
      return PaymentRequest.fromSnapshot(doc);
    } catch (e) {
      debugPrint('❌ PaymentRequest getById error: $e');
      return null;
    }
  }

  /// Upload thêm hình ảnh vào request đã có
  static Future<List<String>?> uploadImages(
    String requestId,
    List<File> images,
  ) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;

      final List<String> urls = [];
      for (int i = 0; i < images.length; i++) {
        final fileName = 'pr_${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final ref = _storage.ref().child('payment_requests/$shopId/$fileName');
        await ref.putFile(images[i]);
        final url = await ref.getDownloadURL();
        urls.add(url);
      }

      await _db.collection(_collection).doc(requestId).update({
        'imageUrls': FieldValue.arrayUnion(urls),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return urls;
    } catch (e) {
      debugPrint('❌ PaymentRequest uploadImages error: $e');
      return null;
    }
  }
}
