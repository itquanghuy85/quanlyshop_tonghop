import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/printer_types.dart';

/// Web print bridge: gửi bytes in từ browser tới LAN bridge server.
class WebPrintBridgeService {
  static const String _enabledKey = 'web_print_bridge_enabled';
  static const String _urlKey = 'web_print_bridge_url';
  static const String _tokenKey = 'web_print_bridge_token';
  static const String _timeoutMsKey = 'web_print_bridge_timeout_ms';

  static const String _defaultUrl = 'http://127.0.0.1:19191/print';

  static Future<bool> sendBytes(
    List<int> bytes, {
    String? wifiIp,
    PrinterType? printerType,
    String? jobType,
  }) async {
    if (!kIsWeb) return false;
    if (bytes.isEmpty) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_enabledKey) ?? true;
      if (!enabled) return false;

        final queryBridgeUrl =
          (Uri.base.queryParameters['bridgeUrl'] ?? '').trim();
        final bridgeUrl = (queryBridgeUrl.isNotEmpty
            ? queryBridgeUrl
            : (prefs.getString(_urlKey) ?? _defaultUrl))
          .trim();
      if (bridgeUrl.isEmpty) return false;

        final queryToken = (Uri.base.queryParameters['bridgeToken'] ?? '').trim();
        final token =
          (queryToken.isNotEmpty ? queryToken : (prefs.getString(_tokenKey) ?? ''))
            .trim();
      final timeoutMs = prefs.getInt(_timeoutMsKey) ?? 12000;

      final fallbackIp =
          wifiIp ?? prefs.getString('printer_ip') ?? prefs.getString('thermal_printer_ip');

      final payload = <String, dynamic>{
        'bytesBase64': base64Encode(bytes),
        'printerIp': fallbackIp,
        'port': 9100,
        'jobType': jobType ?? 'receipt',
        'printerType': printerType?.name,
        'sentAt': DateTime.now().millisecondsSinceEpoch,
      };

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (token.isNotEmpty) {
        headers['x-bridge-token'] = token;
      }

      final response = await http
          .post(
            Uri.parse(bridgeUrl),
            headers: headers,
            body: jsonEncode(payload),
          )
          .timeout(Duration(milliseconds: timeoutMs));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'WEB_PRINT_BRIDGE: HTTP ${response.statusCode} ${response.body}',
        );
        return false;
      }

      if (response.body.isEmpty) return true;

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded['ok'] == true || decoded['success'] == true;
      }

      return true;
    } catch (e) {
      debugPrint('WEB_PRINT_BRIDGE: send error: $e');
      return false;
    }
  }
}
