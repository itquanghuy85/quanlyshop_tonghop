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

  static List<String> _splitPaths(String? csv) {
    if (csv == null) return const [];
    return csv
        .split(RegExp(r'[,;\n]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static bool _isCloudPath(String path) {
    final p = path.trim().toLowerCase();
    return p.startsWith('http://') ||
        p.startsWith('https://') ||
        p.startsWith('gs://') ||
        p.startsWith('blob:') ||
        p.startsWith('data:');
  }

  static Future<bool> _hasPendingRepairQueue(
    DatabaseExecutor dbConn,
    int localRepairId,
  ) async {
    final rows = await dbConn.rawQuery(
      "SELECT 1 FROM sync_queue WHERE entityType = 'repair' AND entityId = ? AND status IN ('pending', 'processing', 'failed') LIMIT 1",
      [localRepairId],
    );
    return rows.isNotEmpty;
  }

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
      final dbHelper = DBHelper();
      final dbConn = await dbHelper.database;

      final currentRows = await dbConn.query(
        'repairs',
        columns: ['imagePath', 'isSynced'],
        where: 'id = ?',
        whereArgs: [localRepairId],
        limit: 1,
      );

      if (currentRows.isNotEmpty) {
        final current = currentRows.first;
        final alreadySynced = (current['isSynced'] as int? ?? 0) == 1;
        if (alreadySynced) {
          debugPrint(
            '📸 BackgroundUpload: Skip upload because repair is already synced',
          );
          return;
        }

        final currentPaths = _splitPaths((current['imagePath'] ?? '').toString());
        final hasLocalPath = currentPaths.any((p) => !_isCloudPath(p));
        if (!hasLocalPath && currentPaths.isNotEmpty) {
          debugPrint(
            '📸 BackgroundUpload: Skip upload because local paths are already replaced',
          );
          return;
        }
      }

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

      // Always persist cloud paths locally.
      await dbConn.update(
        'repairs',
        {'imagePath': cloudPaths},
        where: 'id = ?',
        whereArgs: [localRepairId],
      );

      // Update Firestore directly
      var cloudUpdated = false;
      try {
        final encData = EncryptionService.encryptMap({
          'imagePath': cloudPaths,
          'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
        });
        await _db.collection('repairs').doc(firestoreId).update(encData);
        cloudUpdated = true;
      } catch (e) {
        debugPrint('📸 BackgroundUpload: Firestore update failed (will sync later): $e');
      }

      final hasPendingQueue = await _hasPendingRepairQueue(dbConn, localRepairId);
      await dbConn.update(
        'repairs',
        {
          'isSynced': cloudUpdated && !hasPendingQueue ? 1 : 0,
        },
        where: 'id = ?',
        whereArgs: [localRepairId],
      );

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
