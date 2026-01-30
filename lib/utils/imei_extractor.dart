// ============================================================
// IMEI EXTRACTOR UTILITY
// ============================================================
// Purpose: Extract IMEI from complex QR codes (multi-line, mixed data)
// Handles: Apple, Samsung, Xiaomi, and other manufacturers' QR formats
// ============================================================

/// Kết quả trích xuất IMEI
class IMEIExtractResult {
  final String? imei;
  final String? serial;
  final String? model;
  final List<String> allLines;
  final List<String> candidates;
  final String rawData;
  final bool isMultiLine;

  IMEIExtractResult({
    this.imei,
    this.serial,
    this.model,
    required this.allLines,
    required this.candidates,
    required this.rawData,
    this.isMultiLine = false,
  });

  bool get hasIMEI => imei != null && imei!.isNotEmpty;
  bool get hasMultipleCandidates => candidates.length > 1;
}

/// Utility class để trích xuất IMEI từ các dạng QR phức tạp
class IMEIExtractor {
  // IMEI patterns - 15 digits, sometimes with prefixes
  static final RegExp _imeiPattern = RegExp(
    r'(?:IMEI[:\s]*)?(\d{15})(?:\s|$|/)',
    caseSensitive: false,
  );

  // IMEI2 pattern - for dual SIM phones
  static final RegExp _imei2Pattern = RegExp(
    r'(?:IMEI2[:\s]*)?(\d{15})',
    caseSensitive: false,
  );

  // Short IMEI pattern - 4-5 digits (internal code)
  static final RegExp _shortImeiPattern = RegExp(r'^(\d{4,5})$');

  // Serial number patterns
  static final RegExp _serialPattern = RegExp(
    r'(?:S/?N|Serial)[:\s]*([A-Z0-9]{8,20})',
    caseSensitive: false,
  );

  // Model patterns
  static final RegExp _modelPattern = RegExp(
    r'(?:Model|P/?N)[:\s]*([A-Z0-9\-]+)',
    caseSensitive: false,
  );

  // Pure 15-digit number (likely IMEI)
  static final RegExp _pureIMEI = RegExp(r'^(\d{15})$');

  // Pure 4-5 digit number (short IMEI code)
  static final RegExp _pureShortIMEI = RegExp(r'^(\d{4,5})$');

  // 8-20 alphanumeric (could be serial)
  static final RegExp _pureSerial = RegExp(r'^([A-Z0-9]{8,20})$');

  /// Trích xuất IMEI và thông tin từ QR data
  static IMEIExtractResult extract(String rawData) {
    if (rawData.isEmpty) {
      return IMEIExtractResult(allLines: [], candidates: [], rawData: rawData);
    }

    // Split by common delimiters
    final lines = _splitQRData(rawData);
    final isMultiLine = lines.length > 1;

    String? imei;
    String? serial;
    String? model;
    final List<String> candidates = [];

    // First pass: Look for labeled IMEI
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Check for IMEI with label
      final imeiMatch = _imeiPattern.firstMatch(trimmed);
      if (imeiMatch != null) {
        final candidate = imeiMatch.group(1)!;
        if (_isValidIMEI(candidate)) {
          imei ??= candidate;
          if (!candidates.contains(candidate)) {
            candidates.add(candidate);
          }
        }
      }

      // Check for IMEI2
      final imei2Match = _imei2Pattern.firstMatch(trimmed);
      if (imei2Match != null) {
        final candidate = imei2Match.group(1)!;
        if (_isValidIMEI(candidate) && !candidates.contains(candidate)) {
          candidates.add(candidate);
        }
      }

      // Check for Serial
      final serialMatch = _serialPattern.firstMatch(trimmed);
      if (serialMatch != null) {
        serial ??= serialMatch.group(1);
      }

      // Check for Model
      final modelMatch = _modelPattern.firstMatch(trimmed);
      if (modelMatch != null) {
        model ??= modelMatch.group(1);
      }
    }

    // Second pass: Look for unlabeled 15-digit numbers
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Pure 15-digit number
      final pureMatch = _pureIMEI.firstMatch(trimmed);
      if (pureMatch != null) {
        final candidate = pureMatch.group(1)!;
        if (_isValidIMEI(candidate)) {
          imei ??= candidate;
          if (!candidates.contains(candidate)) {
            candidates.add(candidate);
          }
        }
      }

      // Look for 15-digit sequences within the line
      final digitSequences = RegExp(r'\d{15}').allMatches(trimmed);
      for (final match in digitSequences) {
        final candidate = match.group(0)!;
        if (_isValidIMEI(candidate) && !candidates.contains(candidate)) {
          candidates.add(candidate);
        }
      }
    }

    // Third pass: Look for short IMEI codes (4-5 digits)
    if (imei == null) {
      for (final line in lines) {
        final trimmed = line.trim();
        final shortMatch = _pureShortIMEI.firstMatch(trimmed);
        if (shortMatch != null) {
          final candidate = shortMatch.group(1)!;
          imei ??= candidate;
          if (!candidates.contains(candidate)) {
            candidates.add(candidate);
          }
          break; // Chỉ lấy mã ngắn đầu tiên
        }
      }
    }

    // If no IMEI found, check for serial-like patterns
    if (serial == null) {
      for (final line in lines) {
        final trimmed = line.trim();
        final pureSerialMatch = _pureSerial.firstMatch(trimmed);
        if (pureSerialMatch != null) {
          serial ??= pureSerialMatch.group(1);
          break;
        }
      }
    }

    return IMEIExtractResult(
      imei: imei,
      serial: serial,
      model: model,
      allLines: lines,
      candidates: candidates,
      rawData: rawData,
      isMultiLine: isMultiLine,
    );
  }

  /// Validate IMEI using Luhn algorithm (for 15-digit IMEI)
  /// Short codes (4-5 digits) are always considered valid
  static bool _isValidIMEI(String imei) {
    // Short IMEI code (4-5 digits) - always valid
    if (imei.length >= 4 && imei.length <= 5) {
      return RegExp(r'^\d{4,5}$').hasMatch(imei);
    }
    
    // Standard IMEI must be 15 digits
    if (imei.length != 15) return false;
    if (!RegExp(r'^\d{15}$').hasMatch(imei)) return false;

    // Luhn algorithm check
    int sum = 0;
    for (int i = 0; i < 15; i++) {
      int digit = int.parse(imei[i]);
      if (i % 2 == 1) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
    }
    return sum % 10 == 0;
  }

  /// Split QR data by common delimiters
  static List<String> _splitQRData(String data) {
    // Common delimiters in manufacturer QR codes
    // - Newline (\n, \r\n)
    // - Tab (\t)
    // - Pipe (|)
    // - Comma (,) - but be careful with decimal numbers
    // - Semicolon (;)

    // First split by newlines
    List<String> lines = data.split(RegExp(r'[\r\n]+'));

    // If single line, try other delimiters
    if (lines.length == 1) {
      // Try pipe
      if (data.contains('|')) {
        lines = data.split('|');
      }
      // Try semicolon
      else if (data.contains(';')) {
        lines = data.split(';');
      }
      // Try tab
      else if (data.contains('\t')) {
        lines = data.split('\t');
      }
    }

    // Clean up empty lines
    return lines.where((line) => line.trim().isNotEmpty).toList();
  }

  /// Lấy 5 số cuối của IMEI (cho nhập nhanh)
  static String getLast5Digits(String imei) {
    final digitsOnly = imei.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length >= 5) {
      return digitsOnly.substring(digitsOnly.length - 5);
    }
    return digitsOnly;
  }

  /// Format IMEI cho hiển thị (thêm space để dễ đọc)
  static String formatIMEI(String imei) {
    if (imei.length != 15) return imei;
    // Format: AAAAA BBB CCC CC C
    // TAC (8) + FAC (6) + Check (1)
    return '${imei.substring(0, 8)} ${imei.substring(8, 14)} ${imei.substring(14)}';
  }

  /// Kiểm tra xem có phải IMEI không (quick check without Luhn)
  /// Hỗ trợ: 4-5 số (mã ngắn) hoặc 15 số (IMEI chuẩn)
  static bool looksLikeIMEI(String text) {
    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
    // Chấp nhận 4-5 số (mã ngắn) hoặc 15 số (IMEI chuẩn)
    return (digitsOnly.length >= 4 && digitsOnly.length <= 5) || 
           digitsOnly.length == 15;
  }

  /// Kiểm tra xem mã có phải là mã ngắn (4-5 số) không
  static bool isShortCode(String text) {
    final digitsOnly = text.replaceAll(RegExp(r'[^0-9]'), '');
    return digitsOnly.length >= 4 && digitsOnly.length <= 5;
  }

  /// Lấy n số cuối của IMEI (mặc định 5, có thể 4)
  static String getLastNDigits(String imei, [int n = 5]) {
    final digitsOnly = imei.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length >= n) {
      return digitsOnly.substring(digitsOnly.length - n);
    }
    return digitsOnly;
  }

  /// So sánh 2 IMEI - hỗ trợ mã ngắn và mã dài
  static bool matchIMEI(String imei1, String imei2) {
    final clean1 = imei1.replaceAll(RegExp(r'[^0-9]'), '');
    final clean2 = imei2.replaceAll(RegExp(r'[^0-9]'), '');

    if (clean1.isEmpty || clean2.isEmpty) return false;

    // Match chính xác
    if (clean1 == clean2) return true;

    // So sánh theo suffix (mã ngắn)
    final shorter = clean1.length <= clean2.length ? clean1 : clean2;
    final longer = clean1.length > clean2.length ? clean1 : clean2;

    if (shorter.length >= 4 && shorter.length <= 5) {
      return longer.endsWith(shorter);
    }

    return false;
  }
}