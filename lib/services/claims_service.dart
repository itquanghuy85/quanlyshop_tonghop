// ============================================================
// CUSTOM CLAIMS SERVICE
// ============================================================
// Purpose: Manage Firebase Custom Claims from Flutter client
// Author: Firebase Cloud Functions Expert
// Date: 2026-01-10
// ============================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// Service để quản lý Custom Claims trong Firebase Auth
class ClaimsService {
  static final ClaimsService _instance = ClaimsService._internal();
  factory ClaimsService() => _instance;
  ClaimsService._internal();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instanceFor(
    region: 'asia-southeast1',
  );
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  StreamSubscription<DocumentSnapshot>? _claimsSubscription;

  // ==================== GETTERS ====================

  /// Get current user's claims from ID token
  Future<Map<String, dynamic>?> getCurrentClaims() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final idTokenResult = await user.getIdTokenResult();
    return idTokenResult.claims;
  }

  /// Get shopId from claims (fast, no Firestore read)
  Future<String?> getShopIdFromClaims() async {
    final claims = await getCurrentClaims();
    return claims?['shopId'] as String?;
  }

  /// Get role from claims
  Future<String> getRoleFromClaims() async {
    final claims = await getCurrentClaims();
    return claims?['role'] as String? ?? 'user';
  }

  /// Check if current user is super admin
  Future<bool> isSuperAdmin() async {
    final claims = await getCurrentClaims();
    return claims?['isSuperAdmin'] == true;
  }

  // ==================== TOKEN REFRESH ====================

  /// Force refresh ID token to get latest claims
  /// Call this after:
  /// - User joins a shop
  /// - User's role changes
  /// - claimsSyncedAt in Firestore updates
  Future<void> forceRefreshToken() async {
    final user = _auth.currentUser;
    if (user == null) return;

    await user.getIdToken(true); // force refresh
    debugPrint('🔄 Token refreshed');
  }

  /// Call Cloud Function to refresh claims manually
  Future<Map<String, dynamic>> refreshMyClaims() async {
    try {
      final callable = _functions.httpsCallable('refreshMyClaims');
      final result = await callable.call();
      
      // Force token refresh to get new claims
      await forceRefreshToken();
      
      debugPrint('✅ Claims refreshed: ${result.data}');
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Error refreshing claims: ${e.message}');
      rethrow;
    }
  }

  // ==================== AUTO-SYNC LISTENER ====================

  /// Listen to claimsSyncedAt changes and auto-refresh token
  /// Call this once after login
  void startClaimsSync() {
    final user = _auth.currentUser;
    if (user == null) return;

    _claimsSubscription?.cancel();
    
    _claimsSubscription = _firestore
        .doc('users/${user.uid}')
        .snapshots()
        .listen((snapshot) async {
      final data = snapshot.data();
      if (data == null) return;

      // Check if claims were just synced
      final claimsSyncedAt = data['claimsSyncedAt'] as Timestamp?;
      if (claimsSyncedAt != null) {
        final syncTime = claimsSyncedAt.toDate();
        final now = DateTime.now();
        
        // If synced within last 5 seconds, refresh token
        if (now.difference(syncTime).inSeconds < 5) {
          debugPrint('🔄 Claims synced, refreshing token...');
          await forceRefreshToken();
        }
      }
    });

    debugPrint('👂 Started claims sync listener');
  }

  /// Stop listening for claims changes
  void stopClaimsSync() {
    _claimsSubscription?.cancel();
    _claimsSubscription = null;
    debugPrint('🛑 Stopped claims sync listener');
  }

  // ==================== ADMIN FUNCTIONS ====================

  /// Update user's role (owner/manager only)
  /// 
  /// Example:
  /// ```dart
  /// await ClaimsService().updateUserRole(
  ///   userId: 'abc123',
  ///   role: 'employee',
  /// );
  /// ```
  Future<Map<String, dynamic>> updateUserRole({
    required String userId,
    required String role,
  }) async {
    try {
      final callable = _functions.httpsCallable('updateUserRole');
      final result = await callable.call({
        'userId': userId,
        'role': role,
      });
      
      debugPrint('✅ Role updated: $userId -> $role');
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Error updating role: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Add user to shop (owner/manager only)
  /// 
  /// Example:
  /// ```dart
  /// await ClaimsService().addUserToShop(
  ///   userId: 'abc123',
  ///   shopId: 'shop456',
  ///   role: 'employee',
  /// );
  /// ```
  Future<Map<String, dynamic>> addUserToShop({
    required String userId,
    required String shopId,
    String role = 'employee',
  }) async {
    try {
      final callable = _functions.httpsCallable('addUserToShop');
      final result = await callable.call({
        'userId': userId,
        'shopId': shopId,
        'role': role,
      });
      
      debugPrint('✅ User added to shop: $userId -> $shopId as $role');
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Error adding user to shop: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Remove user from shop (owner/manager only)
  Future<Map<String, dynamic>> removeUserFromShop({
    required String userId,
  }) async {
    try {
      final callable = _functions.httpsCallable('removeUserFromShop');
      final result = await callable.call({
        'userId': userId,
      });
      
      debugPrint('✅ User removed from shop: $userId');
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Error removing user: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  /// Get user's claims (super admin can view others)
  Future<Map<String, dynamic>> getUserClaims({String? userId}) async {
    try {
      final callable = _functions.httpsCallable('getUserClaims');
      final result = await callable.call({
        if (userId != null) 'userId': userId,
      });
      
      return Map<String, dynamic>.from(result.data as Map);
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ Error getting claims: ${e.code} - ${e.message}');
      rethrow;
    }
  }

  // ==================== ROLE HELPERS ====================

  /// Check if current user is owner or above
  Future<bool> isOwnerOrAbove() async {
    if (await isSuperAdmin()) return true;
    final role = await getRoleFromClaims();
    return role == 'owner' || role == 'admin';
  }

  /// Check if current user is manager or above
  Future<bool> isManagerOrAbove() async {
    if (await isSuperAdmin()) return true;
    final role = await getRoleFromClaims();
    return ['admin', 'owner', 'manager'].contains(role);
  }

  /// Check if current user is employee or above
  Future<bool> isEmployeeOrAbove() async {
    if (await isSuperAdmin()) return true;
    final role = await getRoleFromClaims();
    return ['admin', 'owner', 'manager', 'employee'].contains(role);
  }

  /// Check if current user belongs to a specific shop
  Future<bool> belongsToShop(String shopId) async {
    if (await isSuperAdmin()) return true;
    final userShopId = await getShopIdFromClaims();
    return userShopId == shopId;
  }
}

// ============================================================
// USAGE EXAMPLES
// ============================================================
/*

// 1. AFTER LOGIN - Start listening for claims changes
void onLogin() {
  ClaimsService().startClaimsSync();
}

// 2. AFTER LOGOUT - Stop listening
void onLogout() {
  ClaimsService().stopClaimsSync();
}

// 3. GET CURRENT ROLE (fast, from token)
Future<void> checkRole() async {
  final role = await ClaimsService().getRoleFromClaims();
  print('Current role: $role');
}

// 4. CHECK PERMISSIONS
Future<void> checkPermissions() async {
  final claims = ClaimsService();
  
  if (await claims.isManagerOrAbove()) {
    // Show manager features
  }
  
  if (await claims.isSuperAdmin()) {
    // Show super admin features
  }
}

// 5. UPDATE USER ROLE (requires owner/manager)
Future<void> promoteUser() async {
  try {
    await ClaimsService().updateUserRole(
      userId: 'targetUserId',
      role: 'manager',
    );
    print('Role updated!');
  } on FirebaseFunctionsException catch (e) {
    print('Error: ${e.message}');
  }
}

// 6. ADD USER TO SHOP (requires owner/manager)
Future<void> inviteUser() async {
  try {
    await ClaimsService().addUserToShop(
      userId: 'newUserId',
      shopId: 'myShopId',
      role: 'employee',
    );
    print('User added!');
  } on FirebaseFunctionsException catch (e) {
    print('Error: ${e.message}');
  }
}

// 7. FORCE REFRESH CLAIMS (after role change)
Future<void> onRoleChanged() async {
  await ClaimsService().refreshMyClaims();
  // Now token has latest claims
}

// 8. DEBUG - View current claims
Future<void> debugClaims() async {
  final claims = await ClaimsService().getCurrentClaims();
  print('Current claims: $claims');
  // Output: {shopId: "abc", role: "manager", isSuperAdmin: false}
}

*/
