import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firestore_write_helper.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import '../models/payment_request_model.dart';
import '../models/expense_model.dart';
import '../data/db_helper.dart';
import '../services/financial_activity_service.dart';
import '../services/firestore_service.dart';
import '../services/event_bus.dart';
import 'user_service.dart';
import 'storage_service.dart';

/// Service quản lý yêu cầu đóng tiền - chat-like workflow
class PaymentRequestService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static const String _collection = 'payment_requests';
  static int _requestsFetchCount = 0;
  static int _pendingFetchCount = 0;

  static void _warmNetworkImageCache(List<String> urls) {
    for (final raw in urls) {
      final url = raw.trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      unawaited(_warmSingleNetworkImage(url));
    }
  }

  static Future<void> _warmSingleNetworkImage(String url) async {
    try {
      final provider = NetworkImage(url);
      final stream = provider.resolve(const ImageConfiguration());
      final completer = Completer<void>();
      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (_, __) {
          if (!completer.isCompleted) completer.complete();
          stream.removeListener(listener);
        },
        onError: (_, __) {
          if (!completer.isCompleted) completer.complete();
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      await completer.future.timeout(
        const Duration(seconds: 4),
        onTimeout: () {
          stream.removeListener(listener);
        },
      );
    } catch (_) {
      // Best-effort cache warmup, ignore failures.
    }
  }

  static bool _isRefreshEvent(String event) {
    return event == 'payment_requests_changed' ||
        event == EventBus.dataRefresh ||
        event == EventBus.shopChanged ||
        event == 'sync_now_completed' ||
        event == 'app_resumed';
  }

  // ============== CREATE ==============

  /// Nhân viên tạo yêu cầu đóng tiền
  static Future<String?> createRequest({
    required String customerName,
    String? customerPhone,
    String? customerAddress,
    String? customerNote,
    required PaymentType paymentType,
    String? paymentTypeLabel,
    required double amount,
    String? accountNumber,
    String? bankName,
    String? description,
    List<File>? images,
    String? customerPaymentMethod,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;

      final userName = user.email?.split('@').first.toUpperCase() ?? 'NV';

      // Create doc FIRST so it appears in list immediately
      final request = PaymentRequest(
        shopId: shopId,
        senderId: user.uid,
        senderName: userName,
        customerName: customerName,
        customerPhone: customerPhone ?? '',
        customerAddress: customerAddress,
        customerNote: customerNote,
        paymentType: paymentType,
        paymentTypeLabel: paymentTypeLabel,
        amount: amount,
        accountNumber: accountNumber,
        bankName: bankName,
        description: description,
        imageUrls: [],
        customerPaymentMethod: customerPaymentMethod,
        createdAt: DateTime.now(),
      );

      final map = request.toMap();
      // Keep a client timestamp so new requests appear immediately in ordered queries.
      // Server timestamp is stored separately for audit/reconciliation if needed.
      map['createdAt'] = Timestamp.fromDate(DateTime.now());
      map['createdAtServer'] = FieldValue.serverTimestamp();

      final docRef = await _db.collection(_collection).add(map);
      debugPrint('✅ PaymentRequest created: ${docRef.id}');
      EventBus().emit('payment_requests_changed');

      // Upload images AFTER doc is created (non-blocking for list appearance)
      if (images != null && images.isNotEmpty) {
        _uploadImagesInBackground(docRef.id, shopId, images);
      }

      // Log income: NV thu tiền từ khách hàng (await to ensure it completes)
      await _logIncomeFromCustomer(
        requestId: docRef.id,
        customerName: customerName,
        customerPhone: customerPhone ?? '',
        paymentType: paymentType,
        paymentTypeLabel: paymentTypeLabel,
        amount: amount,
        bankName: bankName,
        accountNumber: accountNumber,
        description: description,
        customerPaymentMethod: customerPaymentMethod ?? 'TIỀN MẶT',
      );

      return docRef.id;
    } catch (e) {
      debugPrint('❌ PaymentRequest create error: $e');
      return null;
    }
  }

  /// Log thu nhập khi NV thu tiền từ khách hàng
  static Future<void> _logIncomeFromCustomer({
    required String requestId,
    required String customerName,
    required String customerPhone,
    required PaymentType paymentType,
    String? paymentTypeLabel,
    required double amount,
    String? bankName,
    String? accountNumber,
    String? description,
    required String customerPaymentMethod,
  }) async {
    try {
      final intAmount = amount.toInt();
      if (intAmount <= 0) return;

      String typeDisplay;
      switch (paymentType) {
        case PaymentType.electricity:
          typeDisplay = 'Tiền điện';
          break;
        case PaymentType.water:
          typeDisplay = 'Tiền nước';
          break;
        case PaymentType.internet:
          typeDisplay = 'Tiền mạng';
          break;
        case PaymentType.bankLoan:
          typeDisplay = 'Vay NH';
          break;
        case PaymentType.bankInstallment:
          typeDisplay = 'Trả góp NH';
          break;
        case PaymentType.insurance:
          typeDisplay = 'Bảo hiểm';
          break;
        case PaymentType.other:
          typeDisplay = (paymentTypeLabel?.isNotEmpty == true)
              ? paymentTypeLabel!
              : 'Đóng tiền';
          break;
      }

      final incTitle = 'THU ĐÓNG TIỀN: $typeDisplay - $customerName';
      final now = DateTime.now().millisecondsSinceEpoch;
      final incFirestoreId = 'inc_pr_$requestId';

      final noteParts = <String>[];
      if (customerPhone.isNotEmpty) noteParts.add('SĐT: $customerPhone');
      if (bankName != null && bankName.isNotEmpty)
        noteParts.add('NH: $bankName');
      if (accountNumber != null && accountNumber.isNotEmpty)
        noteParts.add('TK: $accountNumber');
      if (description != null && description.isNotEmpty)
        noteParts.add(description);
      noteParts.add('KH trả: $customerPaymentMethod');
      final noteStr = noteParts.join(' · ');

      // 1. Tạo bản ghi THU vào expenses → hiển thị trong sổ quỹ
      final incData = {
        'firestoreId': incFirestoreId,
        'title': incTitle,
        'amount': intAmount,
        'category': 'THU ĐÓNG TIỀN',
        'date': now,
        'note': noteStr,
        'paymentMethod': customerPaymentMethod,
        'type': 'THU',
      };
      await FirestoreService.addExpenseCloud(incData);

      // 1b. Ghi vào SQLite local để hiển thị ngay (không chờ sync)
      try {
        final localExpense = Expense(
          firestoreId: incFirestoreId,
          title: incTitle,
          amount: intAmount,
          category: 'THU ĐÓNG TIỀN',
          date: now,
          note: noteStr,
          paymentMethod: customerPaymentMethod,
          type: 'THU',
          isSynced: true,
        );
        await DBHelper().upsertExpense(localExpense);
      } catch (e) {
        debugPrint('⚠️ PaymentRequest local expense write error: $e');
      }

      // 2. Ghi log tài chính THU (financial activity)
      await FinancialActivityService.logCustomActivity(
        activityType: 'PAYMENT_REQUEST_IN',
        amount: intAmount,
        direction: 'IN',
        paymentMethod: customerPaymentMethod,
        title: incTitle,
        description: noteStr,
        customerName: customerName,
        phone: customerPhone,
        referenceType: 'payment_request',
        referenceId: requestId,
      );

      debugPrint(
        '✅ PaymentRequest $requestId: Income logged ($customerPaymentMethod)',
      );
      EventBus().emit('expenses_changed');
    } catch (e) {
      debugPrint('❌ PaymentRequest _logIncomeFromCustomer error: $e');
    }
  }

  /// Upload images in background and update the existing doc
  static Future<void> _uploadImagesInBackground(
    String docId,
    String shopId,
    List<File> images,
  ) async {
    try {
      final uploadedResults = await Future.wait<String?>(
        images.map(
          (file) => StorageService.uploadAndGetUrl(
            file.path,
            'payment_requests/$shopId',
          ),
        ),
      );
      final urls = uploadedResults
          .whereType<String>()
          .map((u) => u.trim())
          .where((u) => u.isNotEmpty)
          .toList();

      if (urls.length != images.length) {
        throw Exception(
          StorageService.lastUploadErrorMessage ??
              'Không thể tải toàn bộ ảnh yêu cầu thanh toán lên máy chủ',
        );
      }
      _warmNetworkImageCache(urls);
      if (urls.isNotEmpty) {
        await _db.collection(_collection).doc(docId).update({
          'imageUrls': FieldValue.arrayUnion(urls),
          'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
        });
        debugPrint('✅ PaymentRequest $docId: ${urls.length} images uploaded');
        EventBus().emit('payment_requests_changed');
      }
    } catch (e) {
      debugPrint('❌ PaymentRequest image upload error: $e');
    }
  }

  // ============== UPDATE STATUS ==============

  /// Chủ shop cập nhật trạng thái
  static Future<bool> updateStatus(
    String requestId,
    PaymentRequestStatus newStatus, {
    String? rejectReason,
    String?
    paymentMethod, // 'TIỀN MẶT' or 'CHUYỂN KHOẢN' (required when completing)
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final userName = user.email?.split('@').first.toUpperCase() ?? 'OWNER';

      final Map<String, dynamic> update = {
        'status': newStatus.name,
        'processedBy': user.uid,
        'processedByName': userName,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      };

      if (newStatus == PaymentRequestStatus.completed ||
          newStatus == PaymentRequestStatus.rejected) {
        update['processedAt'] = FieldValue.serverTimestamp();
      }

      if (newStatus == PaymentRequestStatus.rejected && rejectReason != null) {
        update['rejectReason'] = rejectReason;
      }

      if (newStatus == PaymentRequestStatus.completed &&
          paymentMethod != null) {
        update['paymentMethod'] = paymentMethod;
      }

      await _db.collection(_collection).doc(requestId).update(update);
      debugPrint('✅ PaymentRequest $requestId → ${newStatus.name}');
      EventBus().emit('payment_requests_changed');

      // Khi hoàn thành: tạo chi phí + ghi log tài chính (chủ shop luôn chuyển khoản cho ngân hàng)
      if (newStatus == PaymentRequestStatus.completed) {
        await _logFinancialOnCompleted(requestId, 'CHUYỂN KHOẢN');
      }

      // Khi từ chối: xóa bản ghi THU đã tạo lúc gửi yêu cầu
      if (newStatus == PaymentRequestStatus.rejected) {
        await _reverseIncomeOnRejected(requestId);
      }

      return true;
    } catch (e) {
      debugPrint('❌ PaymentRequest updateStatus error: $e');
      return false;
    }
  }

  /// Xóa bản ghi THU khi yêu cầu đóng tiền bị từ chối
  static Future<void> _reverseIncomeOnRejected(String requestId) async {
    try {
      final incFirestoreId = 'inc_pr_$requestId';
      // Soft delete in Firestore
      await FirestoreService.deleteExpenseCloud(incFirestoreId);
      // Delete from local SQLite
      await DBHelper().deleteExpenseByFirestoreId(incFirestoreId);
      debugPrint('✅ PaymentRequest $requestId: THU record reversed (rejected)');
      EventBus().emit('expenses_changed');
    } catch (e) {
      debugPrint('⚠️ PaymentRequest _reverseIncomeOnRejected error: $e');
    }
  }

  /// Tạo bản ghi chi phí (expenses) + log tài chính khi đóng tiền hoàn thành
  static Future<void> _logFinancialOnCompleted(
    String requestId,
    String paymentMethod,
  ) async {
    try {
      // Lấy thông tin payment request
      final doc = await _db.collection(_collection).doc(requestId).get();
      if (!doc.exists) return;
      final data = doc.data()!;

      final amount = (data['amount'] as num?)?.toInt() ?? 0;
      if (amount <= 0) return;

      final customerName = data['customerName'] ?? '';
      final customerPhone = data['customerPhone'] ?? '';
      final paymentTypeLabel = data['paymentTypeLabel'] ?? '';
      final paymentType = data['paymentType'] ?? '';
      final bankName = data['bankName'] ?? '';
      final description = data['description'] ?? '';
      final accountNumber = data['accountNumber'] ?? '';

      // Build title cho expense
      String typeDisplay;
      switch (paymentType) {
        case 'electricity':
          typeDisplay = 'Tiền điện';
          break;
        case 'water':
          typeDisplay = 'Tiền nước';
          break;
        case 'internet':
          typeDisplay = 'Tiền mạng';
          break;
        case 'bankLoan':
          typeDisplay = 'Vay NH';
          break;
        case 'bankInstallment':
          typeDisplay = 'Trả góp NH';
          break;
        case 'insurance':
          typeDisplay = 'Bảo hiểm';
          break;
        default:
          typeDisplay = paymentTypeLabel.isNotEmpty
              ? paymentTypeLabel
              : 'Đóng tiền';
      }

      final expTitle = 'ĐÓNG TIỀN: $typeDisplay - $customerName';
      final now = DateTime.now().millisecondsSinceEpoch;
      final expFirestoreId = 'exp_pr_$requestId';

      // Build note
      final noteParts = <String>[];
      if (customerPhone.isNotEmpty) noteParts.add('SĐT: $customerPhone');
      if (bankName.isNotEmpty) noteParts.add('NH: $bankName');
      if (accountNumber.isNotEmpty) noteParts.add('TK: $accountNumber');
      if (description.isNotEmpty) noteParts.add(description);
      final noteStr = noteParts.join(' · ');

      // Map payment type to expense category
      String expCategory;
      switch (paymentType) {
        case 'electricity':
        case 'water':
        case 'internet':
          expCategory = 'ĐIỆN NƯỚC';
          break;
        default:
          expCategory = 'ĐÓNG TIỀN';
      }

      // 1. Tạo chi phí (expense) → hiển thị trong chốt quỹ
      final expData = {
        'firestoreId': expFirestoreId,
        'title': expTitle,
        'description': expTitle,
        'amount': amount,
        'category': expCategory,
        'date': now,
        'note': noteStr,
        'paymentMethod': paymentMethod,
        'type': 'CHI',
      };
      await FirestoreService.addExpenseCloud(expData);

      // 1b. Ghi vào SQLite local để hiển thị ngay
      try {
        final localExpense = Expense(
          firestoreId: expFirestoreId,
          title: expTitle,
          amount: amount,
          category: expCategory,
          date: now,
          note: noteStr,
          paymentMethod: paymentMethod,
          type: 'CHI',
          isSynced: true,
        );
        await DBHelper().upsertExpense(localExpense);
      } catch (e) {
        debugPrint('⚠️ PaymentRequest local expense write error: $e');
      }

      // 2. Ghi log tài chính CHI (chủ shop CK cho ngân hàng)
      await FinancialActivityService.logCustomActivity(
        activityType: 'PAYMENT_REQUEST_OUT',
        amount: amount,
        direction: 'OUT',
        paymentMethod: paymentMethod,
        title: expTitle,
        description: noteStr,
        customerName: customerName,
        phone: customerPhone,
        referenceType: 'payment_request',
        referenceId: requestId,
      );

      debugPrint(
        '✅ PaymentRequest $requestId: Expense + FinancialActivity logged ($paymentMethod)',
      );
      EventBus().emit('expenses_changed');
    } catch (e) {
      debugPrint('❌ PaymentRequest _logFinancialOnCompleted error: $e');
    }
  }

  /// Soft delete
  static Future<bool> deleteRequest(String requestId) async {
    try {
      await _db.collection(_collection).doc(requestId).update({
        'deleted': true,
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });
      EventBus().emit('payment_requests_changed');
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
    final effectiveLimit = limit.clamp(1, 200);
    List<PaymentRequest> lastData = const <PaymentRequest>[];

    Future<List<PaymentRequest>> fetchOnce(String reason) async {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return <PaymentRequest>[];

      _requestsFetchCount += 1;
      debugPrint(
        '[SYNC][FETCH] collection=payment_requests count=$_requestsFetchCount reason=$reason shopId=$shopId limit=$effectiveLimit',
      );

      Query<Map<String, dynamic>> orderedQuery = _db
          .collection(_collection)
          .where('shopId', isEqualTo: shopId);
      if (statusFilter != null) {
        orderedQuery = orderedQuery.where(
          'status',
          isEqualTo: statusFilter.name,
        );
      }
      orderedQuery = orderedQuery
          .orderBy('createdAt', descending: true)
          .limit(effectiveLimit);

      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
      try {
        docs = (await orderedQuery.get()).docs;
      } catch (e) {
        final msg = e.toString().toLowerCase();
        final canFallback =
            msg.contains('failed-precondition') ||
            msg.contains('permission-denied') ||
            msg.contains('permission denied');
        if (!canFallback) rethrow;

        debugPrint('⚠️ PaymentRequest ordered query failed ($reason): $e');

        // Fallback query avoids orderBy index dependency; data is sorted client-side below.
        Query<Map<String, dynamic>> fallbackQuery = _db
            .collection(_collection)
            .where('shopId', isEqualTo: shopId)
            .limit(effectiveLimit);
        if (statusFilter != null) {
          fallbackQuery = fallbackQuery.where(
            'status',
            isEqualTo: statusFilter.name,
          );
        }
        docs = (await fallbackQuery.get()).docs;
      }

      final parsed = <PaymentRequest>[];
      for (final doc in docs) {
        try {
          final req = PaymentRequest.fromSnapshot(doc);
          if (req.deleted) continue;
          parsed.add(req);
        } catch (e) {
          debugPrint('❌ PaymentRequest parse error (${doc.id}): $e');
        }
      }

      if (statusFilter != null) {
        parsed.removeWhere((r) => r.status != statusFilter);
      }

      parsed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (parsed.length > effectiveLimit) {
        return parsed.take(effectiveLimit).toList();
      }
      return parsed;
    }

    try {
      lastData = await fetchOnce('initial_open');
      yield lastData;
    } catch (e) {
      debugPrint('❌ PaymentRequest requestsStream initial fetch error: $e');
      yield lastData;
    }

    await for (final event in EventBus().stream.where(_isRefreshEvent)) {
      try {
        lastData = await fetchOnce(event);
        yield lastData;
      } catch (e) {
        debugPrint('❌ PaymentRequest requestsStream refresh error: $e');
        yield lastData;
      }
    }
  }

  /// Đếm yêu cầu chờ xử lý
  static Stream<int> pendingCountStream() async* {
    int lastCount = 0;

    Future<int> fetchCount(String reason) async {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return 0;

      _pendingFetchCount += 1;
      debugPrint(
        '[SYNC][FETCH] collection=payment_requests_pending_count count=$_pendingFetchCount reason=$reason shopId=$shopId limit=200',
      );
      final snapshot = await _db
          .collection(_collection)
          .where('shopId', isEqualTo: shopId)
          .where('status', isEqualTo: PaymentRequestStatus.pending.name)
          .limit(200)
          .get();
      var count = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if ((data['deleted'] ?? false) == true) continue;
        count++;
      }
      return count;
    }

    try {
      lastCount = await fetchCount('initial_open');
      yield lastCount;
    } catch (e) {
      debugPrint('❌ PaymentRequest pendingCount initial fetch error: $e');
      yield lastCount;
    }

    await for (final event in EventBus().stream.where(_isRefreshEvent)) {
      try {
        lastCount = await fetchCount(event);
        yield lastCount;
      } catch (e) {
        debugPrint('❌ PaymentRequest pendingCount refresh error: $e');
        yield lastCount;
      }
    }
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
        final url = await StorageService.uploadAndGetUrl(
          images[i].path,
          'payment_requests/$shopId',
        );
        if (url == null || url.trim().isEmpty) {
          throw Exception(
            StorageService.lastUploadErrorMessage ??
                'Không thể tải ảnh yêu cầu thanh toán lên máy chủ',
          );
        }
        urls.add(url);
      }

      await _db.collection(_collection).doc(requestId).update({
        'imageUrls': FieldValue.arrayUnion(urls),
        'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
      });

      return urls;
    } catch (e) {
      debugPrint('❌ PaymentRequest uploadImages error: $e');
      return null;
    }
  }

}
