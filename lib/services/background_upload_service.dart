import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../data/db_helper.dart';
import '../services/storage_service.dart';
import '../services/encryption_service.dart';
import 'firestore_write_helper.dart';

/// Service to upload images in the background after saving records.
/// Allows screens to pop immediately while uploads continue.
class BackgroundUploadService {
  BackgroundUploadService._();

  static final _db = FirebaseFirestore.instance;

  /// Upload repair images in background, then update local DB + Firestore.
  static void uploadRepairImages({
    required int localRepairId,
    required String firestoreId,
    required List<XFile> images,
  }) {
    if (images.isEmpty) return;
    unawaited(_uploadRepairImages(localRepairId, firestoreId, images));
  }

  static Future<void> _uploadRepairImages(
    int localRepairId,
    String firestoreId,
    List<XFile> images,
  ) async {
    try {
      debugPrint('📸 BackgroundUpload: Starting ${images.length} repair image(s)...');
      final uploadedUrls = <String>[];
      for (final picked in images) {
        final url = await StorageService.uploadXFileAndGetUrl(picked, 'repairs');
        if (url != null && url.isNotEmpty) {
          uploadedUrls.add(url);
        }
      }

      if (uploadedUrls.isEmpty) {
        debugPrint('📸 BackgroundUpload: No repair images uploaded');
        return;
      }

      final cloudPaths = uploadedUrls.join(',');

      // Update local DB
      final dbHelper = DBHelper();
      final dbConn = await dbHelper.database;
      await dbConn.update(
        'repairs',
        {'imagePath': cloudPaths, 'isSynced': 0},
        where: 'id = ?',
        whereArgs: [localRepairId],
      );

      // Update Firestore directly
      try {
        final encData = EncryptionService.encryptMap({
          'imagePath': cloudPaths,
          'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
        });
        await _db.collection('repairs').doc(firestoreId).update(encData);
      } catch (e) {
        debugPrint('📸 BackgroundUpload: Firestore update failed (will sync later): $e');
      }

      debugPrint('📸 BackgroundUpload: Repair images done (${uploadedUrls.length})');
    } catch (e) {
      debugPrint('📸 BackgroundUpload: Error uploading repair images: $e');
    }
  }

  /// Upload attendance photo in background, then update local DB + Firestore.
  static void uploadAttendancePhoto({
    required String firestoreId,
    required XFile photo,
    required bool isCheckIn,
    required String? shopId,
  }) {
    unawaited(_uploadAttendancePhoto(firestoreId, photo, isCheckIn, shopId));
  }

  static Future<void> _uploadAttendancePhoto(
    String firestoreId,
    XFile photo,
    bool isCheckIn,
    String? shopId,
  ) async {
    try {
      debugPrint('📸 BackgroundUpload: Starting attendance photo...');
      final cloudUrl = await StorageService.uploadXFileAndGetUrl(photo, 'attendance');
      if (cloudUrl == null) {
        debugPrint('📸 BackgroundUpload: Attendance photo upload failed');
        return;
      }

      final field = isCheckIn ? 'photoIn' : 'photoOut';

      // Update local DB
      final dbHelper = DBHelper();
      final dbConn = await dbHelper.database;
      await dbConn.update(
        'attendance',
        {field: cloudUrl},
        where: 'firestoreId = ?',
        whereArgs: [firestoreId],
      );

      // Update Firestore
      try {
        await _db.collection('attendance').doc(firestoreId).update({
          field: cloudUrl,
          'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
          'syncedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        debugPrint('📸 BackgroundUpload: Firestore attendance update failed: $e');
      }

      debugPrint('📸 BackgroundUpload: Attendance photo done');
    } catch (e) {
      debugPrint('📸 BackgroundUpload: Error uploading attendance photo: $e');
    }
  }
}
