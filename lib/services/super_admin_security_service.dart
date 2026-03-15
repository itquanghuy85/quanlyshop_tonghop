import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Security service for super admin account.
/// Provides:
/// - PIN protection (secondary verification after login)
/// - Session timeout (auto-lock after inactivity)
/// - Login audit logging to Firestore
class SuperAdminSecurityService {
  static final _db = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  // Session management
  static DateTime? _lastActivityTime;
  static bool _isSessionVerified = false;
  static const Duration _sessionTimeout = Duration(minutes: 30);

  static const String _pinHashKey = 'super_admin_pin_hash';
  static const String _pinSetKey = 'super_admin_pin_set';

  /// Check if PIN has been set up
  static Future<bool> isPinSetup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_pinSetKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Set up or change PIN (4-6 digits)
  static Future<bool> setupPin(String pin) async {
    if (pin.length < 4 || pin.length > 6 || !RegExp(r'^\d+$').hasMatch(pin)) {
      return false;
    }
    try {
      final hash = _hashPin(pin);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinHashKey, hash);
      await prefs.setBool(_pinSetKey, true);

      // Also store in Firestore for cross-device sync
      final user = _auth.currentUser;
      if (user != null) {
        await _db.collection('admin_security').doc(user.uid).set({
          'pinHash': hash,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      debugPrint('✅ Super admin PIN set up successfully');
      return true;
    } catch (e) {
      debugPrint('❌ Error setting up PIN: $e');
      return false;
    }
  }

  /// Verify PIN
  static Future<bool> verifyPin(String pin) async {
    try {
      final hash = _hashPin(pin);
      final prefs = await SharedPreferences.getInstance();
      final storedHash = prefs.getString(_pinHashKey);

      if (storedHash == null) {
        // Try Firestore
        final user = _auth.currentUser;
        if (user != null) {
          final doc = await _db.collection('admin_security').doc(user.uid).get();
          if (doc.exists) {
            final firestoreHash = doc.data()?['pinHash'] as String?;
            if (firestoreHash != null) {
              // Sync to local
              await prefs.setString(_pinHashKey, firestoreHash);
              await prefs.setBool(_pinSetKey, true);
              if (hash == firestoreHash) {
                _markSessionVerified();
                await _logAdminAction('pin_verified', success: true);
                return true;
              }
            }
          }
        }
        await _logAdminAction('pin_verify_failed', success: false);
        return false;
      }

      final verified = hash == storedHash;
      if (verified) {
        _markSessionVerified();
        await _logAdminAction('pin_verified', success: true);
      } else {
        await _logAdminAction('pin_verify_failed', success: false);
      }
      return verified;
    } catch (e) {
      debugPrint('❌ Error verifying PIN: $e');
      return false;
    }
  }

  /// Remove PIN
  static Future<bool> removePin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_pinHashKey);
      await prefs.setBool(_pinSetKey, false);

      final user = _auth.currentUser;
      if (user != null) {
        await _db.collection('admin_security').doc(user.uid).set({
          'pinHash': FieldValue.delete(),
          'pinRemoved': true,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      return true;
    } catch (e) {
      debugPrint('❌ Error removing PIN: $e');
      return false;
    }
  }

  // ─── SESSION ─────────────────────────────────

  /// Mark session as verified (after PIN entry)
  static void _markSessionVerified() {
    _isSessionVerified = true;
    _lastActivityTime = DateTime.now();
  }

  /// Update activity timestamp (call on user interaction)
  static void touchActivity() {
    if (_isSessionVerified) {
      _lastActivityTime = DateTime.now();
    }
  }

  /// Check if current session is still valid
  static bool isSessionValid() {
    if (!_isSessionVerified) return false;
    if (_lastActivityTime == null) return false;
    return DateTime.now().difference(_lastActivityTime!) < _sessionTimeout;
  }

  /// Lock the session (require PIN again)
  static void lockSession() {
    _isSessionVerified = false;
    _lastActivityTime = null;
  }

  /// Clear all session state (on logout)
  static void clearSession() {
    _isSessionVerified = false;
    _lastActivityTime = null;
  }

  // ─── AUDIT LOG ───────────────────────────────

  /// Log super admin action to Firestore
  static Future<void> _logAdminAction(String action, {bool success = true}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return;
      await _db.collection('admin_audit_log').add({
        'uid': user.uid,
        'email': user.email,
        'action': action,
        'success': success,
        'timestamp': FieldValue.serverTimestamp(),
        'platform': kIsWeb ? 'web' : 'mobile',
      });
    } catch (e) {
      debugPrint('Audit log error (non-fatal): $e');
    }
  }

  /// Log shop selection
  static Future<void> logShopAccess(String shopId, String? shopName) async {
    await _logAdminAction('shop_access: $shopId ($shopName)');
  }

  /// Log super admin login
  static Future<void> logLogin() async {
    await _logAdminAction('super_admin_login');
  }

  /// Get recent audit logs
  static Future<List<Map<String, dynamic>>> getRecentAuditLogs({int limit = 50}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];
      final snap = await _db.collection('admin_audit_log')
          .where('uid', isEqualTo: user.uid)
          .orderBy('timestamp', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) {
        final data = Map<String, dynamic>.from(d.data());
        data['id'] = d.id;
        return data;
      }).toList();
    } catch (e) {
      debugPrint('getRecentAuditLogs error: $e');
      return [];
    }
  }

  // ─── HELPERS ─────────────────────────────────

  static String _hashPin(String pin) {
    final bytes = utf8.encode('super_admin_salt_huluca_$pin');
    return sha256.convert(bytes).toString();
  }
}
