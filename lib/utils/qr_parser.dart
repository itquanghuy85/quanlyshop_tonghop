import 'dart:convert';

class QRParser {
  /// Parse QR string into key-value map
  /// Format: key1=value1&key2=value2&...
  static Map<String, String> parse(String qrData) {
    final Map<String, String> result = {};

    if (qrData.isEmpty) return result;

    final pairs = qrData.split('&');
    for (final pair in pairs) {
      final parts = pair.split('=');
      if (parts.length >= 2) {
        final key = parts[0].trim();
        // Join all parts after the first '=' in case value contains '='
        final value = parts.sublist(1).join('=').trim();
        if (key.isNotEmpty) {
          // URL decode the value
          try {
            result[key] = Uri.decodeComponent(value);
          } catch (e) {
            // If decoding fails, use the original value
            result[key] = value;
          }
        }
      } else if (parts.length == 1 && parts[0].trim().isNotEmpty) {
        // Handle malformed pairs like "invalid" by treating them as key-only
        result[parts[0].trim()] = '';
      }
    }

    return result;
  }

  /// Validate that QR contains required fields
  static bool isValidQR(Map<String, String> qrMap) {
    return qrMap.containsKey('type') && qrMap['type']!.isNotEmpty;
  }

  /// Get QR type
  static String? getType(Map<String, String> qrMap) {
    return qrMap['type'];
  }
}