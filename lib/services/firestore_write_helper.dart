import 'package:cloud_firestore/cloud_firestore.dart';

/// Centralized helper for Firestore write timestamps.
class FirestoreWriteHelper {
  const FirestoreWriteHelper._();

  static Object serverUpdatedAt() => FieldValue.serverTimestamp();

  static void applyUpdatedAt(Map<String, dynamic> data) {
    data['updatedAt'] = serverUpdatedAt();
  }

  static Map<String, dynamic> withUpdatedAt(Map<String, dynamic> source) {
    final data = Map<String, dynamic>.from(source);
    applyUpdatedAt(data);
    return data;
  }

  static Map<String, dynamic> softDeletePayload({
    Map<String, dynamic>? extra,
  }) {
    final payload = <String, dynamic>{
      'deleted': true,
      'updatedAt': serverUpdatedAt(),
    };
    if (extra != null && extra.isNotEmpty) {
      payload.addAll(extra);
    }
    return payload;
  }
}
