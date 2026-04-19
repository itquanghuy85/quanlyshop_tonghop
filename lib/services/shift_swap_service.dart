import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/shift_swap_request_model.dart';
import 'event_bus.dart';
import 'user_service.dart';

class ShiftSwapService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static int _myRequestsFetchCount = 0;
  static int _pendingRequestsFetchCount = 0;

  static bool _isRefreshEvent(String event) {
    return event == 'shift_swap_requests_changed' ||
        event == EventBus.dataRefresh ||
        event == EventBus.shopChanged ||
        event == 'sync_now_completed' ||
        event == 'app_resumed';
  }

  static Future<String> createRequest({
    required String requestedDate,
    required String currentShift,
    required String desiredShift,
    String? targetUserId,
    String? targetUserName,
    String? note,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Vui lòng đăng nhập lại để gửi yêu cầu đổi ca.');
    }

    final shopId = await UserService.getCurrentShopId();
    if (shopId == null || shopId.isEmpty) {
      throw Exception('Không tìm thấy shopId hiện tại.');
    }

    final requesterName = await UserService.getCurrentUserName();
    final now = DateTime.now().millisecondsSinceEpoch;
    final docRef = _db.collection('shift_swap_requests').doc();

    await docRef.set({
      'firestoreId': docRef.id,
      'shopId': shopId,
      'requesterId': user.uid,
      'requesterName': requesterName.isEmpty ? 'Nhân viên' : requesterName,
      'requesterEmail': user.email ?? '',
      'requestedDate': requestedDate,
      'currentShift': currentShift,
      'desiredShift': desiredShift,
      'targetUserId': targetUserId,
      'targetUserName': targetUserName,
      'note': note,
      'status': 'pending',
      'reviewedBy': null,
      'reviewedByName': null,
      'createdAt': now,
      'updatedAt': now,
      'reviewedAt': null,
      'rejectReason': null,
      'deleted': false,
      'serverUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    EventBus().emit('shift_swap_requests_changed');

    return docRef.id;
  }

  static Stream<List<ShiftSwapRequest>> watchMyRequests({int limit = 100}) {
    return (() async* {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        yield <ShiftSwapRequest>[];
        return;
      }

      final shopId = await UserService.getCurrentShopId();
      if (shopId == null || shopId.isEmpty) {
        yield <ShiftSwapRequest>[];
        return;
      }

      final effectiveLimit = limit.clamp(1, 20);
      List<ShiftSwapRequest> lastData = const <ShiftSwapRequest>[];

      Future<List<ShiftSwapRequest>> fetchOnce(String reason) async {
        _myRequestsFetchCount += 1;
        debugPrint(
          '[SYNC][FETCH] collection=shift_swap_requests_my count=$_myRequestsFetchCount reason=$reason limit=$effectiveLimit',
        );
        final snap = await _db
            .collection('shift_swap_requests')
            .where('shopId', isEqualTo: shopId)
            .where('requesterId', isEqualTo: user.uid)
            .where('deleted', isEqualTo: false)
            .orderBy('createdAt', descending: true)
            .limit(effectiveLimit)
            .get();

        return snap.docs.map((doc) {
          final map = doc.data();
          map['firestoreId'] = doc.id;
          return ShiftSwapRequest.fromMap(map);
        }).toList();
      }

      try {
        lastData = await fetchOnce('initial_open');
        yield lastData;
      } catch (e) {
        debugPrint('ShiftSwapService watchMyRequests initial fetch error: $e');
        yield lastData;
      }

      await for (final event in EventBus().stream.where(_isRefreshEvent)) {
        try {
          lastData = await fetchOnce(event);
          yield lastData;
        } catch (e) {
          debugPrint('ShiftSwapService watchMyRequests refresh error: $e');
          yield lastData;
        }
      }
    })();
  }

  static Stream<List<ShiftSwapRequest>> watchPendingRequests({
    int limit = 120,
  }) {
    return (() async* {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null || shopId.isEmpty) {
        yield <ShiftSwapRequest>[];
        return;
      }

      final effectiveLimit = limit.clamp(1, 20);
      List<ShiftSwapRequest> lastData = const <ShiftSwapRequest>[];

      Future<List<ShiftSwapRequest>> fetchOnce(String reason) async {
        _pendingRequestsFetchCount += 1;
        debugPrint(
          '[SYNC][FETCH] collection=shift_swap_requests_pending count=$_pendingRequestsFetchCount reason=$reason limit=$effectiveLimit',
        );
        final snap = await _db
            .collection('shift_swap_requests')
            .where('shopId', isEqualTo: shopId)
            .where('status', isEqualTo: 'pending')
            .where('deleted', isEqualTo: false)
            .orderBy('createdAt', descending: true)
            .limit(effectiveLimit)
            .get();

        return snap.docs.map((doc) {
          final map = doc.data();
          map['firestoreId'] = doc.id;
          return ShiftSwapRequest.fromMap(map);
        }).toList();
      }

      try {
        lastData = await fetchOnce('initial_open');
        yield lastData;
      } catch (e) {
        debugPrint(
          'ShiftSwapService watchPendingRequests initial fetch error: $e',
        );
        yield lastData;
      }

      await for (final event in EventBus().stream.where(_isRefreshEvent)) {
        try {
          lastData = await fetchOnce(event);
          yield lastData;
        } catch (e) {
          debugPrint('ShiftSwapService watchPendingRequests refresh error: $e');
          yield lastData;
        }
      }
    })();
  }

  static Future<void> approveRequest(ShiftSwapRequest request) async {
    await _updateStatus(request: request, status: 'approved');
  }

  static Future<void> rejectRequest(
    ShiftSwapRequest request, {
    required String reason,
  }) async {
    await _updateStatus(
      request: request,
      status: 'rejected',
      rejectReason: reason.trim().isEmpty ? 'Không nêu lý do' : reason.trim(),
    );
  }

  static Future<void> cancelRequest(ShiftSwapRequest request) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != request.requesterId) {
      throw Exception('Bạn không có quyền huỷ yêu cầu này.');
    }
    if (request.status != 'pending') {
      throw Exception('Yêu cầu đã xử lý, không thể huỷ.');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.collection('shift_swap_requests').doc(request.firestoreId).set({
      'status': 'cancelled',
      'updatedAt': now,
      'serverUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    EventBus().emit('shift_swap_requests_changed');
  }

  static Future<List<Map<String, String>>> getShopStaffOptions() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null || shopId.isEmpty) return const [];

    final snap = await _db
        .collection('users')
        .where('shopId', isEqualTo: shopId)
        .get();

    final out = <Map<String, String>>[];
    for (final doc in snap.docs) {
      final data = doc.data();
      final name = (data['name']?.toString().trim() ?? '');
      final email = (data['email']?.toString().trim() ?? '');
      out.add({
        'uid': doc.id,
        'name': name.isEmpty ? (email.isEmpty ? 'Nhân viên' : email) : name,
        'email': email,
      });
    }

    out.sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));
    return out;
  }

  static Future<void> _updateStatus({
    required ShiftSwapRequest request,
    required String status,
    String? rejectReason,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Vui lòng đăng nhập lại để duyệt yêu cầu.');
    }

    final role = await UserService.getUserRole(user.uid);
    final isSuperAdmin = UserService.isCurrentUserSuperAdmin();
    final canReview = isSuperAdmin || role == 'owner' || role == 'manager';
    if (!canReview) {
      throw Exception('Bạn không có quyền duyệt yêu cầu đổi ca.');
    }

    if (request.status != 'pending') {
      throw Exception('Yêu cầu đã được xử lý trước đó.');
    }

    final reviewerName = await UserService.getCurrentUserName();
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.collection('shift_swap_requests').doc(request.firestoreId).set({
      'status': status,
      'reviewedBy': user.uid,
      'reviewedByName': reviewerName.isEmpty
          ? (user.email ?? 'Quản lý')
          : reviewerName,
      'reviewedAt': now,
      'rejectReason': rejectReason,
      'updatedAt': now,
      'serverUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    EventBus().emit('shift_swap_requests_changed');
  }

  static void debugLog(Object message) {
    debugPrint('ShiftSwapService: $message');
  }
}
