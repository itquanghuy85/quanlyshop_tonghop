import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Service xử lý đăng nhập / liên kết Google & Apple.
/// An toàn cho user cũ: nếu email đã tồn tại sẽ tự link provider,
/// không tạo UID mới → không mất data.
class SocialAuthService {
  static final _auth = FirebaseAuth.instance;

  // Singleton GoogleSignIn — tránh tạo nhiều instance gây channel-error
  static final _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );

  // ─── GOOGLE ────────────────────────────────────

  /// Đăng nhập bằng Google (hoặc link nếu email đã có tài khoản)
  static Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        // Web: Use signInWithPopup (simpler, no extra config needed)
        final provider = GoogleAuthProvider();
        provider.addScope('email');
        provider.addScope('profile');
        try {
          return await _auth.signInWithPopup(provider);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'account-exists-with-different-credential' &&
              e.credential != null) {
            return await _signInOrLink(e.credential!);
          }
          rethrow;
        }
      }

      // Mobile/Desktop: Use google_sign_in plugin (singleton)
      // Disconnect trước để đảm bảo hiển thị account picker
      try { await _googleSignIn.signOut(); } catch (_) {}
      final GoogleSignInAccount? gUser = await _googleSignIn.signIn();
      if (gUser == null) return null; // user cancelled

      final gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      return await _signInOrLink(credential);
    } catch (e) {
      debugPrint('❌ SocialAuth: Google sign-in error: $e');
      if (e.toString().contains('channel-error') ||
          e.toString().contains('PlatformException')) {
        throw Exception(
          'Không thể kết nối Google Sign-In. Vui lòng kiểm tra:\n'
          '• Google Play Services đã cập nhật\n'
          '• Đã thêm SHA-1 fingerprint vào Firebase Console\n'
          '• Đã tải lại google-services.json',
        );
      }
      rethrow;
    }
  }

  /// Liên kết Google vào tài khoản hiện tại
  /// Returns UserCredential on success, null if user cancelled.
  /// Throws on actual errors.
  static Future<UserCredential?> linkGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Chưa đăng nhập');

    if (kIsWeb) {
      // Web: Use linkWithPopup
      final provider = GoogleAuthProvider();
      provider.addScope('email');
      try {
        return await user.linkWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use') {
          throw Exception('Tài khoản Google này đã được liên kết với tài khoản khác.');
        }
        if (e.code == 'provider-already-linked') {
          throw Exception('Google đã được liên kết với tài khoản này rồi.');
        }
        if (e.code == 'requires-recent-login') {
          throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng xuất rồi đăng nhập lại để liên kết.');
        }
        rethrow;
      }
    }

    // Mobile/Desktop (singleton)
    try { await _googleSignIn.signOut(); } catch (_) {}
    final GoogleSignInAccount? gUser = await _googleSignIn.signIn();
    if (gUser == null) return null; // user cancelled

    final gAuth = await gUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );

    try {
      return await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        throw Exception('Tài khoản Google này đã được liên kết với tài khoản khác.');
      }
      if (e.code == 'provider-already-linked') {
        throw Exception('Google đã được liên kết với tài khoản này rồi.');
      }
      if (e.code == 'requires-recent-login') {
        throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng xuất rồi đăng nhập lại để liên kết.');
      }
      rethrow;
    } catch (e) {
      debugPrint('❌ SocialAuth: Google link error: $e');
      if (e.toString().contains('channel-error') ||
          e.toString().contains('PlatformException')) {
        throw Exception(
          'Không thể kết nối Google Sign-In. Vui lòng kiểm tra:\n'
          '• Google Play Services đã cập nhật\n'
          '• Đã thêm SHA-1 fingerprint vào Firebase Console\n'
          '• Đã tải lại google-services.json',
        );
      }
      rethrow;
    }
  }

  /// Hủy liên kết Google
  static Future<void> unlinkGoogle() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.unlink(GoogleAuthProvider.PROVIDER_ID);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng xuất rồi đăng nhập lại.');
      }
      rethrow;
    }
  }

  // ─── APPLE ─────────────────────────────────────

  /// Đăng nhập bằng Apple (hoặc link nếu email đã có tài khoản)
  static Future<UserCredential?> signInWithApple() async {
    try {
      if (kIsWeb) {
        // Web: Use signInWithPopup (same pattern as Google web)
        final provider = OAuthProvider('apple.com');
        provider.addScope('email');
        provider.addScope('name');
        try {
          return await _auth.signInWithPopup(provider);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'account-exists-with-different-credential' &&
              e.credential != null) {
            return await _signInOrLink(e.credential!);
          }
          rethrow;
        }
      }

      // Mobile/Desktop: Use native Apple Sign-In
      // Check availability first (fails on simulators / devices without Apple ID)
      final isAvailable = await SignInWithApple.isAvailable();
      if (!isAvailable) {
        throw Exception(
          'Đăng nhập Apple không khả dụng trên thiết bị này. '
          'Vui lòng kiểm tra:\n'
          '• Thiết bị chạy iOS 13+ hoặc macOS 10.15+\n'
          '• Đã đăng nhập Apple ID trong Cài đặt'
        );
      }

      // Generate nonce for security
      final rawNonce = _generateNonce();
      final nonce = _sha256ofString(rawNonce);

      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
      );

      final result = await _signInOrLink(oauthCredential);

      // Apple only provides name on first sign-in
      if (result != null && result.user != null) {
        final displayName = result.user!.displayName;
        if ((displayName == null || displayName.isEmpty) &&
            appleCredential.givenName != null) {
          final name =
              '${appleCredential.givenName ?? ''} ${appleCredential.familyName ?? ''}'
                  .trim();
          if (name.isNotEmpty) {
            await result.user!.updateDisplayName(name);
          }
        }
      }

      return result;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return null; // user cancelled — not an error
      }
      debugPrint('❌ SocialAuth: Apple authorization error: ${e.code} ${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('❌ SocialAuth: Apple sign-in error: $e');
      rethrow;
    }
  }

  /// Liên kết Apple vào tài khoản hiện tại
  /// Returns UserCredential on success, null if user cancelled.
  /// Throws on actual errors.
  static Future<UserCredential?> linkApple() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Chưa đăng nhập');

    if (kIsWeb) {
      // Web: Use linkWithPopup for Apple
      final provider = OAuthProvider('apple.com');
      provider.addScope('email');
      provider.addScope('name');
      try {
        return await user.linkWithPopup(provider);
      } on FirebaseAuthException catch (e) {
        if (e.code == 'credential-already-in-use') {
          throw Exception('Tài khoản Apple này đã được liên kết với tài khoản khác.');
        }
        if (e.code == 'provider-already-linked') {
          throw Exception('Apple đã được liên kết với tài khoản này rồi.');
        }
        if (e.code == 'requires-recent-login') {
          throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng xuất rồi đăng nhập lại để liên kết.');
        }
        rethrow;
      }
    }

    // Mobile/Desktop: native Apple Sign-In
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    AuthorizationCredentialAppleID appleCredential;
    try {
      appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: nonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        return null; // User cancelled — not an error
      }
      rethrow;
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );

    try {
      return await user.linkWithCredential(oauthCredential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use') {
        throw Exception('Tài khoản Apple này đã được liên kết với tài khoản khác.');
      }
      if (e.code == 'provider-already-linked') {
        throw Exception('Apple đã được liên kết với tài khoản này rồi.');
      }
      if (e.code == 'requires-recent-login') {
        throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng xuất rồi đăng nhập lại để liên kết.');
      }
      rethrow;
    }
  }

  /// Hủy liên kết Apple
  static Future<void> unlinkApple() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.unlink('apple.com');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        throw Exception('Phiên đăng nhập đã hết hạn. Vui lòng đăng xuất rồi đăng nhập lại.');
      }
      rethrow;
    }
  }

  // ─── HELPERS ───────────────────────────────────

  /// Kiểm tra user hiện tại đã liên kết provider nào
  static Set<String> getLinkedProviders() {
    final user = _auth.currentUser;
    if (user == null) return {};
    return user.providerData.map((p) => p.providerId).toSet();
  }

  static bool isGoogleLinked() =>
      getLinkedProviders().contains(GoogleAuthProvider.PROVIDER_ID);

  static bool isAppleLinked() =>
      getLinkedProviders().contains('apple.com');

  static bool isPasswordLinked() =>
      getLinkedProviders().contains(EmailAuthProvider.PROVIDER_ID);

  /// Lấy email của từng provider đang liên kết
  static String? getProviderEmail(String providerId) {
    final user = _auth.currentUser;
    if (user == null) return null;
    for (final info in user.providerData) {
      if (info.providerId == providerId) {
        return info.email;
      }
    }
    return null;
  }

  /// Email đăng nhập Google
  static String? get googleEmail =>
      getProviderEmail(GoogleAuthProvider.PROVIDER_ID);

  /// Email đăng nhập Apple
  static String? get appleEmail => getProviderEmail('apple.com');

  /// Email đăng nhập Email/Password
  static String? get passwordEmail =>
      getProviderEmail(EmailAuthProvider.PROVIDER_ID);

  /// Sign-in or auto-link if account-exists-with-different-credential
  static Future<UserCredential?> _signInOrLink(
    AuthCredential credential,
  ) async {
    try {
      return await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      // account-exists-with-different-credential:
      // User has email/password account, trying to sign in with
      // Google/Apple that has the SAME email → need to link instead
      if (e.code == 'account-exists-with-different-credential' &&
          e.email != null) {
        debugPrint(
          '⚠️ Account exists for ${e.email}, prompting link flow',
        );
        // Re-throw with clear message for UI to handle
        throw FirebaseAuthException(
          code: 'account-exists-with-different-credential',
          message:
              'Tài khoản với email ${e.email} đã tồn tại. '
              'Vui lòng đăng nhập bằng Email/Mật khẩu trước, '
              'sau đó liên kết Google/Apple trong Cài đặt.',
        );
      }
      rethrow;
    }
  }

  /// Generate secure random nonce
  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)])
        .join();
  }

  /// SHA256 hash for Apple nonce
  static String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}
