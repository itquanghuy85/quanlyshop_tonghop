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

  // ─── GOOGLE ────────────────────────────────────

  /// Đăng nhập bằng Google (hoặc link nếu email đã có tài khoản)
  static Future<UserCredential?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
      if (gUser == null) return null; // user cancelled

      final gAuth = await gUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken,
      );

      return await _signInOrLink(credential);
    } catch (e) {
      debugPrint('❌ SocialAuth: Google sign-in error: $e');
      rethrow;
    }
  }

  /// Liên kết Google vào tài khoản hiện tại
  static Future<UserCredential?> linkGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Chưa đăng nhập');

    final GoogleSignInAccount? gUser = await GoogleSignIn().signIn();
    if (gUser == null) return null;

    final gAuth = await gUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: gAuth.accessToken,
      idToken: gAuth.idToken,
    );

    try {
      return await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'provider-already-linked') {
        debugPrint('⚠️ Google already linked');
        return null;
      }
      rethrow;
    }
  }

  /// Hủy liên kết Google
  static Future<void> unlinkGoogle() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.unlink(GoogleAuthProvider.PROVIDER_ID);
  }

  // ─── APPLE ─────────────────────────────────────

  /// Đăng nhập bằng Apple (hoặc link nếu email đã có tài khoản)
  static Future<UserCredential?> signInWithApple() async {
    try {
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
    } catch (e) {
      debugPrint('❌ SocialAuth: Apple sign-in error: $e');
      rethrow;
    }
  }

  /// Liên kết Apple vào tài khoản hiện tại
  static Future<UserCredential?> linkApple() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Chưa đăng nhập');

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

    try {
      return await user.linkWithCredential(oauthCredential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'provider-already-linked') {
        debugPrint('⚠️ Apple already linked');
        return null;
      }
      rethrow;
    }
  }

  /// Hủy liên kết Apple
  static Future<void> unlinkApple() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.unlink('apple.com');
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
