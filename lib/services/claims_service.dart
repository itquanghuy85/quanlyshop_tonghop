import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Service quản lý Custom Claims cho Firebase Auth
/// 
/// Custom Claims structure:
/// - role: owner | manager | employee | technician | user
/// - shopId: ID của shop user thuộc về
/// - isSuperAdmin: true nếu email == admin@huluca.com
class ClaimsService {
  static final ClaimsService _instance = ClaimsService._internal();
  factory ClaimsService() => _instance;
  ClaimsService._internal();

  final _functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
  final _auth = FirebaseAuth.instance;

  /// Cache claims để tránh gọi lại liên tục
  Map<String, dynamic>? _cachedClaims;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(minutes: 5);

  /// ══════════════════════════════════════════════════════════════════════════
  /// 1. BATCH SYNC ALL CLAIMS (Chỉ Super Admin)
  /// ══════════════════════════════════════════════════════════════════════════
  /// 
  /// Đồng bộ Custom Claims cho TOÀN BỘ user cũ.
  /// Chỉ admin@huluca.com được gọi function này.
  /// 
  /// Returns: { success, message, stats: {total, success, skipped, failed}, errors, details }
  Future<Map<String, dynamic>> batchSyncAllClaims() async {
    try {
      final callable = _functions.httpsCallable('batchSyncAllClaims');
      final result = await callable.call();
      
      // Force refresh token để lấy claims mới
      await _auth.currentUser?.getIdToken(true);
      _clearCache();
      
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      return {
        'success': false,
        'error': e.message ?? 'Lỗi không xác định',
        'code': e.code,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// ══════════════════════════════════════════════════════════════════════════
  /// 2. SYNC SINGLE USER CLAIMS (Super Admin hoặc Owner)
  /// ══════════════════════════════════════════════════════════════════════════
  /// 
  /// Sync claims cho 1 user cụ thể.
  /// 
  /// [uid] - UID của user cần sync
  Future<Map<String, dynamic>> syncUserClaims(String uid) async {
    try {
      final callable = _functions.httpsCallable('syncUserClaimsV2');
      final result = await callable.call({'uid': uid});
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      return {
        'success': false,
        'error': e.message ?? 'Lỗi không xác định',
        'code': e.code,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// ══════════════════════════════════════════════════════════════════════════
  /// 3. REFRESH MY CLAIMS (Bất kỳ user nào)
  /// ══════════════════════════════════════════════════════════════════════════
  /// 
  /// User tự refresh claims của mình.
  /// Dùng sau khi role/shopId được thay đổi bởi admin.
  /// 
  /// QUAN TRỌNG: Sau khi gọi, user cần logout và login lại để áp dụng.
  Future<Map<String, dynamic>> refreshMyClaims() async {
    try {
      final callable = _functions.httpsCallable('refreshMyClaimsV2');
      final result = await callable.call();
      
      // Force refresh token để lấy claims mới
      await _auth.currentUser?.getIdToken(true);
      _clearCache();
      
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      return {
        'success': false,
        'error': e.message ?? 'Lỗi không xác định',
        'code': e.code,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// ══════════════════════════════════════════════════════════════════════════
  /// 4. GET MY CLAIMS
  /// ══════════════════════════════════════════════════════════════════════════
  /// 
  /// Xem claims hiện tại và kiểm tra cần sync không.
  /// 
  /// Returns: { currentClaims, firestoreData, needsSync }
  Future<Map<String, dynamic>> getMyClaims() async {
    try {
      final callable = _functions.httpsCallable('getMyClaimsV2');
      final result = await callable.call();
      return Map<String, dynamic>.from(result.data);
    } on FirebaseFunctionsException catch (e) {
      return {
        'success': false,
        'error': e.message ?? 'Lỗi không xác định',
        'code': e.code,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// ══════════════════════════════════════════════════════════════════════════
  /// 5. GET CLAIMS FROM TOKEN (Local - không cần Cloud Function)
  /// ══════════════════════════════════════════════════════════════════════════
  /// 
  /// Đọc claims trực tiếp từ ID token.
  /// Nhanh hơn vì không cần network call.
  Future<Map<String, dynamic>?> getClaimsFromToken({bool forceRefresh = false}) async {
    // Check cache
    if (!forceRefresh && _cachedClaims != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _cachedClaims;
      }
    }

    final user = _auth.currentUser;
    if (user == null) return null;

    try {
      final idTokenResult = await user.getIdTokenResult(forceRefresh);
      final claims = idTokenResult.claims;
      
      if (claims != null) {
        _cachedClaims = {
          'role': claims['role'] ?? 'user',
          'shopId': claims['shopId'] ?? user.uid,
          'isSuperAdmin': claims['isSuperAdmin'] == true,
        };
        _cacheTime = DateTime.now();
      }
      
      return _cachedClaims;
    } catch (e) {
      print('Error getting claims from token: $e');
      return null;
    }
  }

  /// ══════════════════════════════════════════════════════════════════════════
  /// HELPER METHODS
  /// ══════════════════════════════════════════════════════════════════════════

  /// Lấy role từ claims (cached)
  Future<String> getRoleFromClaims() async {
    final claims = await getClaimsFromToken();
    return claims?['role'] ?? 'user';
  }

  /// Lấy shopId từ claims (cached)
  Future<String?> getShopIdFromClaims() async {
    final claims = await getClaimsFromToken();
    return claims?['shopId'];
  }

  /// Kiểm tra có phải Super Admin không
  Future<bool> isSuperAdmin() async {
    final claims = await getClaimsFromToken();
    return claims?['isSuperAdmin'] == true;
  }

  /// Kiểm tra có phải Owner không
  Future<bool> isOwner() async {
    final claims = await getClaimsFromToken();
    return claims?['isSuperAdmin'] == true || claims?['role'] == 'owner';
  }

  /// Kiểm tra có phải Manager trở lên không
  Future<bool> isManagerOrAbove() async {
    final claims = await getClaimsFromToken();
    if (claims?['isSuperAdmin'] == true) return true;
    final role = claims?['role'];
    return role == 'owner' || role == 'manager';
  }

  /// Kiểm tra có phải Staff không (employee hoặc technician)
  Future<bool> isStaff() async {
    final claims = await getClaimsFromToken();
    if (claims?['isSuperAdmin'] == true) return true;
    final role = claims?['role'];
    return ['owner', 'manager', 'employee', 'technician'].contains(role);
  }

  /// Clear cache (dùng sau khi refresh claims)
  void _clearCache() {
    _cachedClaims = null;
    _cacheTime = null;
  }

  /// Force clear cache và refresh token
  Future<void> forceRefresh() async {
    _clearCache();
    await _auth.currentUser?.getIdToken(true);
    await getClaimsFromToken(forceRefresh: true);
  }
}
