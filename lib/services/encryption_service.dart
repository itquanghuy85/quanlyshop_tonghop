import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt_lib;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service mã hóa AES-256 cho dữ liệu đưa lên cloud
/// - Mã hóa các trường nhạy cảm trước khi upload Firestore
/// - Giải mã khi download từ Firestore
/// - Key được tạo từ shopId + master secret
class EncryptionService {
  static const String _masterSecret = 'HuLuCa_Shop_2024_Secure_Key_@!#';
  static const String _enabledKey = 'encryption_enabled';
  
  static encrypt_lib.Encrypter? _encrypter;
  static encrypt_lib.IV? _iv;
  static encrypt_lib.Encrypter? _fallbackEncrypter;
  static encrypt_lib.IV? _fallbackIv;
  static String? _currentShopId;
  static bool _initialized = false;
  static bool _enabled = true;
  static DateTime? _decryptErrorWindowStart;
  static int _decryptErrorCountInWindow = 0;
  
  /// Các trường cần mã hóa (dữ liệu nhạy cảm)
  static const List<String> sensitiveFields = [
    'customerName',
    'phone',
    'address',
    'email',
    'notes',
    'note',
    'issue',
    'password',
    'screenPassword',
    'imei',
    'productImeis',
    'sellerName',
    'receiverName',
    'personName',
    'staffName',
    'name',
    'bankName',
    'settlementCode',
    'settlementNote',
    'description',
    'accessories',
    'warranty',
  ];

  /// Khởi tạo service với shopId
  static Future<void> init(String shopId) async {
    final normalizedShopId = shopId.trim();
    if (normalizedShopId.isEmpty) {
      debugPrint('EncryptionService init skipped: empty shopId');
      return;
    }

    if (_initialized && _encrypter != null && _currentShopId == normalizedShopId) {
      return;
    }
    
    try {
      // Keep the previous key/iv as fallback for transitional decrypts.
      if (_encrypter != null &&
          _iv != null &&
          _currentShopId != null &&
          _currentShopId != normalizedShopId) {
        _fallbackEncrypter = _encrypter;
        _fallbackIv = _iv;
      }

      // Tạo key từ shopId + master secret
      final keySource = '$normalizedShopId$_masterSecret';
      final keyBytes = sha256.convert(utf8.encode(keySource)).bytes;
      final key = encrypt_lib.Key(Uint8List.fromList(keyBytes));
      
      // IV cố định từ shopId (16 bytes)
      final ivSource = 'IV_$normalizedShopId';
      final ivBytes = md5.convert(utf8.encode(ivSource)).bytes;
      _iv = encrypt_lib.IV(Uint8List.fromList(ivBytes));
      
      _encrypter = encrypt_lib.Encrypter(encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc));
      _currentShopId = normalizedShopId;
      _initialized = true;
      
      // Load trạng thái enabled
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;
      
      debugPrint('EncryptionService: Initialized for shop $normalizedShopId, enabled=$_enabled');
    } catch (e) {
      debugPrint('EncryptionService init error: $e');
      _initialized = false;
    }
  }

  static void _logDecryptError(Object error) {
    final now = DateTime.now();
    final windowStart = _decryptErrorWindowStart;
    if (windowStart == null || now.difference(windowStart).inSeconds >= 10) {
      _decryptErrorWindowStart = now;
      _decryptErrorCountInWindow = 0;
    }

    if (_decryptErrorCountInWindow < 5) {
      debugPrint('Decryption error: $error');
    } else if (_decryptErrorCountInWindow == 5) {
      debugPrint('Decryption error: too many failures, suppressing logs for 10s');
    }
    _decryptErrorCountInWindow++;
  }

  static String _tryDecryptWith(
    encrypt_lib.Encrypter encrypter,
    encrypt_lib.IV iv,
    String base64Text,
  ) {
    final encrypted = encrypt_lib.Encrypted.fromBase64(base64Text);
    return encrypter.decrypt(encrypted, iv: iv);
  }

  /// Bật/tắt mã hóa
  static Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    debugPrint('EncryptionService: enabled=$_enabled');
  }

  /// Kiểm tra trạng thái mã hóa
  static bool get isEnabled => _enabled && _initialized;

  /// Mã hóa một chuỗi
  static String encrypt(String plainText) {
    if (!isEnabled || _encrypter == null || _iv == null) {
      return plainText;
    }
    if (plainText.isEmpty) return plainText;
    
    try {
      final encrypted = _encrypter!.encrypt(plainText, iv: _iv);
      // Prefix với marker để nhận biết dữ liệu đã mã hóa
      return 'ENC:${encrypted.base64}';
    } catch (e) {
      debugPrint('Encryption error: $e');
      return plainText;
    }
  }

  /// Giải mã một chuỗi
  static String decrypt(String encryptedText) {
    if (_encrypter == null || _iv == null) return encryptedText;
    if (encryptedText.isEmpty) return encryptedText;
    
    // Kiểm tra marker mã hóa
    if (!encryptedText.startsWith('ENC:')) {
      return encryptedText; // Dữ liệu chưa được mã hóa
    }
    
    try {
      final base64Text = encryptedText.substring(4); // Bỏ prefix 'ENC:'
      return _tryDecryptWith(_encrypter!, _iv!, base64Text);
    } catch (e) {
      // Fallback: try previous shop key during switch-shop transitions.
      if (_fallbackEncrypter != null && _fallbackIv != null) {
        try {
          final base64Text = encryptedText.substring(4);
          return _tryDecryptWith(_fallbackEncrypter!, _fallbackIv!, base64Text);
        } catch (_) {
          // fall through to original text
        }
      }
      _logDecryptError(e);
      return encryptedText; // Trả về nguyên bản nếu lỗi
    }
  }

  /// Mã hóa Map data trước khi upload
  static Map<String, dynamic> encryptMap(Map<String, dynamic> data) {
    if (!isEnabled) return data;
    
    final encrypted = Map<String, dynamic>.from(data);
    
    for (final field in sensitiveFields) {
      if (encrypted.containsKey(field) && encrypted[field] != null) {
        final value = encrypted[field];
        if (value is String && value.isNotEmpty) {
          encrypted[field] = encrypt(value);
        }
      }
    }
    
    // Thêm marker để biết data đã được mã hóa
    encrypted['_encrypted'] = true;
    
    return encrypted;
  }

  /// Giải mã Map data sau khi download
  static Map<String, dynamic> decryptMap(Map<String, dynamic> data) {
    if (_encrypter == null || _iv == null) return data;
    
    // Kiểm tra xem data có được mã hóa không
    if (data['_encrypted'] != true) {
      return data; // Data chưa được mã hóa
    }
    
    final decrypted = Map<String, dynamic>.from(data);
    decrypted.remove('_encrypted'); // Xóa marker
    
    for (final field in sensitiveFields) {
      if (decrypted.containsKey(field) && decrypted[field] != null) {
        final value = decrypted[field];
        if (value is String && value.isNotEmpty) {
          decrypted[field] = decrypt(value);
        }
      }
    }
    
    return decrypted;
  }

  /// Mã hóa List<Map> data
  static List<Map<String, dynamic>> encryptList(List<Map<String, dynamic>> dataList) {
    if (!isEnabled) return dataList;
    return dataList.map((data) => encryptMap(data)).toList();
  }

  /// Giải mã List<Map> data
  static List<Map<String, dynamic>> decryptList(List<Map<String, dynamic>> dataList) {
    return dataList.map((data) => decryptMap(data)).toList();
  }

  /// Reset service (khi logout)
  static void reset() {
    _fallbackEncrypter = null;
    _fallbackIv = null;
    _encrypter = null;
    _iv = null;
    _currentShopId = null;
    _initialized = false;
    debugPrint('EncryptionService: Reset');
  }
}
