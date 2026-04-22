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
  static const Duration _decryptLogCooldown = Duration(seconds: 30);
  static final RegExp _base64Pattern = RegExp(r'^[A-Za-z0-9+/=]+$');

  static encrypt_lib.Encrypter? _encrypter;
  static encrypt_lib.IV? _iv;
  static bool _initialized = false;
  static bool _enabled = true;
  static DateTime? _lastDecryptErrorLogAt;

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
    if (_initialized && _encrypter != null) return;

    try {
      // Tạo key từ shopId + master secret
      final keySource = '$shopId$_masterSecret';
      final keyBytes = sha256.convert(utf8.encode(keySource)).bytes;
      final key = encrypt_lib.Key(Uint8List.fromList(keyBytes));

      // IV cố định từ shopId (16 bytes)
      final ivSource = 'IV_$shopId';
      final ivBytes = md5.convert(utf8.encode(ivSource)).bytes;
      _iv = encrypt_lib.IV(Uint8List.fromList(ivBytes));

      _encrypter = encrypt_lib.Encrypter(
        encrypt_lib.AES(key, mode: encrypt_lib.AESMode.cbc),
      );
      _initialized = true;

      // Load trạng thái enabled
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_enabledKey) ?? true;

      debugPrint(
        'EncryptionService: Initialized for shop $shopId, enabled=$_enabled',
      );
    } catch (e) {
      debugPrint('EncryptionService init error: $e');
      _initialized = false;
    }
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

  static bool _looksEncryptedString(String value) {
    return value.startsWith('ENC:') || value.startsWith('ENC2:');
  }

  static bool _looksEncryptedPayload(String value) {
    if (!_looksEncryptedString(value)) return false;
    final payload = value.startsWith('ENC2:')
        ? value.substring(5)
        : value.substring(4);
    if (payload.isEmpty || payload.length < 8 || payload.length % 4 != 0) {
      return false;
    }
    return _base64Pattern.hasMatch(payload);
  }

  static bool _shouldLogDecryptError() {
    final now = DateTime.now();
    if (_lastDecryptErrorLogAt == null ||
        now.difference(_lastDecryptErrorLogAt!) >= _decryptLogCooldown) {
      _lastDecryptErrorLogAt = now;
      return true;
    }
    return false;
  }

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
    final isEncV1 = encryptedText.startsWith('ENC:');
    final isEncV2 = encryptedText.startsWith('ENC2:');
    if (!isEncV1 && !isEncV2) {
      return encryptedText; // Dữ liệu chưa được mã hóa
    }

    if (!_looksEncryptedPayload(encryptedText)) {
      return encryptedText;
    }

    try {
      final base64Text = encryptedText.substring(isEncV2 ? 5 : 4);
      final encrypted = encrypt_lib.Encrypted.fromBase64(base64Text);
      return _encrypter!.decrypt(encrypted, iv: _iv);
    } catch (e) {
      if (_shouldLogDecryptError()) {
        debugPrint('Decryption error: $e');
      }
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

    try {
      // Cho phép giải mã cả dữ liệu cũ thiếu marker nhưng vẫn có giá trị ENC/ENC2.
      final hasEncryptedMarker = data['_encrypted'] == true;
      final hasEncryptedValue = sensitiveFields.any((field) {
        final value = data[field];
        return value is String &&
            value.isNotEmpty &&
            _looksEncryptedString(value);
      });

      if (!hasEncryptedMarker && !hasEncryptedValue) {
        return data; // Data chưa được mã hóa
      }

      final decrypted = Map<String, dynamic>.from(data);
      decrypted.remove('_encrypted'); // Xóa marker

      for (final field in sensitiveFields) {
        if (decrypted.containsKey(field) && decrypted[field] != null) {
          final value = decrypted[field];
          if (value is String &&
              value.isNotEmpty &&
              _looksEncryptedString(value)) {
            decrypted[field] = decrypt(value);
          }
        }
      }

      return decrypted;
    } catch (e) {
      if (_shouldLogDecryptError()) {
        debugPrint('decryptMap fallback to raw data: $e');
      }
      return data;
    }
  }

  /// Mã hóa List<Map> data
  static List<Map<String, dynamic>> encryptList(
    List<Map<String, dynamic>> dataList,
  ) {
    if (!isEnabled) return dataList;
    return dataList.map((data) => encryptMap(data)).toList();
  }

  /// Giải mã List<Map> data
  static List<Map<String, dynamic>> decryptList(
    List<Map<String, dynamic>> dataList,
  ) {
    return dataList.map((data) => decryptMap(data)).toList();
  }

  /// Reset service (khi logout)
  static void reset() {
    _encrypter = null;
    _iv = null;
    _initialized = false;
    debugPrint('EncryptionService: Reset');
  }
}
