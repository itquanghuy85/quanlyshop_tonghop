import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_service.dart';

class AuditService {
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
      await FirebaseFirestore.instance.collection('audit_logs').add({
        'shopId': shopId,
        'userId': user?.uid,
        'email': user?.email,
        'role': role,
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'summary': summary,
        'payload': payload,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // best-effort: không chặn luồng chính nếu log lỗi
    }
  }
}
