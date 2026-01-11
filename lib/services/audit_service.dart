import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../services/user_service.dart';

class AuditService {
  static final _db = DBHelper();
  
  /// Ghi nhật ký hoạt động vào cả local DB và Firestore
  static Future<void> logAction({
    required String action,
    required String entityType,
    required String entityId,
    String? summary,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final shopId = await UserService.getCurrentShopId();
      final role = user != null ? await UserService.getUserRole(user.uid) : null;
      final userName = user?.email?.split('@').first.toUpperCase() ?? 'SYSTEM';
      final now = DateTime.now().millisecondsSinceEpoch;
      final firestoreId = 'audit_${now}_${entityType}_$entityId';
      
      // 1. Ghi vào local DB trước (để hiển thị ngay lập tức)
      final localData = {
        'firestoreId': firestoreId,
        'shopId': shopId,
        'userId': user?.uid,
        'userName': userName,
        'action': action,
        'targetType': entityType,
        'targetId': entityId,
        'description': summary ?? '',
        'createdAt': now,
        'isSynced': 0,
      };
      await _db.insertAuditLog(localData);
      
      // 2. Ghi lên Firestore (async, không chặn)
      FirebaseFirestore.instance.collection('audit_logs').doc(firestoreId).set({
        'shopId': shopId,
        'userId': user?.uid,
        'email': user?.email,
        'userName': userName,
        'role': role,
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'summary': summary,
        'payload': payload,
        'createdAt': FieldValue.serverTimestamp(),
      }).then((_) async {
        // Đánh dấu đã sync
        await _db.updateAuditLogSynced(firestoreId);
      }).catchError((_) {
        // best-effort: bỏ qua lỗi sync
      });
    } catch (_) {
      // best-effort: không chặn luồng chính nếu log lỗi
    }
  }
}
