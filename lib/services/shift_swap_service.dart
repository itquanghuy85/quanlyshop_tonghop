import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/shift_swap_model.dart';
import '../services/user_service.dart';
import '../services/encryption_service.dart';

/// Service for managing shift swap requests between employees
/// Flow: requester creates → target accepts/declines → manager approves/rejects
class ShiftSwapService {
  static final DBHelper _dbHelper = DBHelper();
  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static String? _getCurrentUid() => FirebaseAuth.instance.currentUser?.uid;

  // ========================
  // CREATE
  // ========================

  /// Create a new shift swap request
  static Future<bool> createSwapRequest(ShiftSwap swap) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      swap.shopId = shopId ?? '';
      swap.firestoreId ??=
          'ss_${swap.requesterId}_${swap.swapDate}_${swap.createdAt}';
      await _dbHelper.upsertShiftSwap(swap);
      await _syncToCloud(swap);
      return true;
    } catch (e) {
      debugPrint('Error creating shift swap: $e');
      return false;
    }
  }

  // ========================
  // TARGET RESPONSE
  // ========================

  /// Target employee accepts the swap request
  static Future<bool> acceptSwap(ShiftSwap swap) async {
    try {
      swap.status = 'pending_manager';
      swap.targetRespondedAt = DateTime.now().millisecondsSinceEpoch;
      swap.updatedAt = DateTime.now().millisecondsSinceEpoch;
      swap.isSynced = false;
      await _dbHelper.upsertShiftSwap(swap);
      await _syncToCloud(swap);
      return true;
    } catch (e) {
      debugPrint('Error accepting shift swap: $e');
      return false;
    }
  }

  /// Target employee declines the swap request
  static Future<bool> declineSwap(ShiftSwap swap, String reason) async {
    try {
      swap.status = 'rejected';
      swap.rejectedBy = 'target';
      swap.rejectReason = reason;
      swap.targetRespondedAt = DateTime.now().millisecondsSinceEpoch;
      swap.updatedAt = DateTime.now().millisecondsSinceEpoch;
      swap.isSynced = false;
      await _dbHelper.upsertShiftSwap(swap);
      await _syncToCloud(swap);
      return true;
    } catch (e) {
      debugPrint('Error declining shift swap: $e');
      return false;
    }
  }

  // ========================
  // MANAGER RESPONSE
  // ========================

  /// Manager approves the swap request
  static Future<bool> approveSwap(ShiftSwap swap) async {
    try {
      final uid = _getCurrentUid();
      if (uid == null) return false;

      swap.status = 'approved';
      swap.approvedBy = uid;
      swap.approvedAt = DateTime.now().millisecondsSinceEpoch;
      swap.updatedAt = DateTime.now().millisecondsSinceEpoch;
      swap.isSynced = false;

      await _dbHelper.upsertShiftSwap(swap);
      await _syncToCloud(swap);
      return true;
    } catch (e) {
      debugPrint('Error approving shift swap: $e');
      return false;
    }
  }

  /// Manager rejects the swap request
  static Future<bool> rejectSwap(ShiftSwap swap, String reason) async {
    try {
      final uid = _getCurrentUid();
      if (uid == null) return false;

      swap.status = 'rejected';
      swap.rejectedBy = uid;
      swap.rejectReason = reason;
      swap.approvedAt = DateTime.now().millisecondsSinceEpoch;
      swap.updatedAt = DateTime.now().millisecondsSinceEpoch;
      swap.isSynced = false;

      await _dbHelper.upsertShiftSwap(swap);
      await _syncToCloud(swap);
      return true;
    } catch (e) {
      debugPrint('Error rejecting shift swap: $e');
      return false;
    }
  }

  // ========================
  // CANCEL
  // ========================

  /// Requester cancels their swap request (only if still pending)
  static Future<bool> cancelSwap(ShiftSwap swap) async {
    try {
      if (!swap.canCancel) return false;

      swap.status = 'cancelled';
      swap.updatedAt = DateTime.now().millisecondsSinceEpoch;
      swap.isSynced = false;

      await _dbHelper.upsertShiftSwap(swap);
      await _syncToCloud(swap);
      return true;
    } catch (e) {
      debugPrint('Error cancelling shift swap: $e');
      return false;
    }
  }

  // ========================
  // QUERIES
  // ========================

  /// Get all shift swaps for current shop
  static Future<List<ShiftSwap>> getAllSwaps() async {
    return _dbHelper.getAllShiftSwaps();
  }

  /// Get swaps involving a specific user (as requester or target)
  static Future<List<ShiftSwap>> getSwapsForUser(String userId) async {
    return _dbHelper.getShiftSwapsForUser(userId);
  }

  /// Get pending swaps waiting for this user to respond
  static Future<List<ShiftSwap>> getPendingForTarget(String userId) async {
    return _dbHelper.getPendingShiftSwapsForTarget(userId);
  }

  /// Get swaps waiting for manager approval
  static Future<List<ShiftSwap>> getPendingForManager() async {
    return _dbHelper.getPendingShiftSwapsForManager();
  }

  /// Get approved swaps for a specific date
  static Future<List<ShiftSwap>> getApprovedForDate(String dateKey) async {
    return _dbHelper.getApprovedSwapsForDate(dateKey);
  }

  // ========================
  // CLOUD SYNC
  // ========================

  static Future<void> _syncToCloud(ShiftSwap swap) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      final docId = swap.firestoreId ??
          'ss_${swap.requesterId}_${swap.swapDate}_${swap.createdAt}';
      Map<String, dynamic> data = swap.toMap();
      data['shopId'] = shopId;
      data['firestoreId'] = docId;
      data['updatedAt'] = FieldValue.serverTimestamp();
      data.remove('id'); // Remove SQLite auto-increment id
      data.remove('isSynced');
      final encryptedData = EncryptionService.encryptMap(data);
      await _db
          .collection('shift_swaps')
          .doc(docId)
          .set(encryptedData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      debugPrint('Error syncing shift swap to cloud: $e');
    }
  }
}
