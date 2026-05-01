import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:barcode/barcode.dart' as bc;
import 'package:barcode_image/barcode_image.dart' hide Barcode;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/money_utils.dart';
import 'bluetooth_printer_service.dart';
import 'wifi_printer_service.dart';
import 'web_print_bridge_service.dart';
import 'label_settings_service.dart';
import 'user_service.dart';
import '../models/label_template_model.dart';
import '../models/product_model.dart';
import '../models/repair_model.dart';
import '../constants/product_constants.dart';

import '../models/printer_types.dart';

/// Model cho element từ Label Designer
class _LabelElementConfig {
  final String id;
  final bool visible;
  final double fontSize;
  final bool bold;
  final String fontType;
  final String align;
  final String prefix;
  final int row;
  final int col;
  final double flex;
  final double spacing;

  _LabelElementConfig({
    required this.id,
    this.visible = true,
    this.fontSize = 1.0,
    this.bold = true,
    this.fontType = 'A',
    this.align = 'center',
    this.prefix = '',
    this.row = 0,
    this.col = 0,
    this.flex = 1.0,
    this.spacing = 4.0,
  });

  factory _LabelElementConfig.fromJson(Map<String, dynamic> json) =>
      _LabelElementConfig(
        id: json['id'] ?? '',
        visible: json['visible'] ?? true,
        fontSize: (json['fontSize'] ?? 1.0).toDouble(),
        bold: json['bold'] ?? true,
        fontType: json['fontType'] ?? 'A',
        align: json['align'] ?? 'center',
        prefix: json['prefix'] ?? '',
        row: json['row'] ?? 0,
        col: json['col'] ?? 0,
        flex: (json['flex'] ?? 1.0).toDouble(),
        spacing: (json['spacing'] ?? 4.0).toDouble(),
      );
}

class UnifiedPrinterService {
  static Future<Map<String, String>> _loadReceiptPolicies() async {
    final prefs = await SharedPreferences.getInstance();
    // Policies are synced from Firestore shop doc to SharedPreferences
    // by SyncService's real-time shop listener. Just read local cache.
    String warrantyPolicy = (prefs.getString('warranty_policy') ?? '').trim();
    String returnPolicy = (prefs.getString('return_policy') ?? '').trim();

    // Fallback: fetch directly from Firestore if local cache is empty
    // (first launch before sync_service has run)
    if (warrantyPolicy.isEmpty && returnPolicy.isEmpty) {
      try {
        final shopId = await UserService.getCurrentShopId();
        if (shopId != null && shopId.isNotEmpty) {
          final shopDoc = await FirebaseFirestore.instance
              .collection('shops')
              .doc(shopId)
              .get();
          final data = shopDoc.data();
          warrantyPolicy = (data?['warrantyPolicy'] ?? '').toString().trim();
          returnPolicy = (data?['returnPolicy'] ?? '').toString().trim();

          if (warrantyPolicy.isNotEmpty || returnPolicy.isNotEmpty) {
            await prefs.setString('warranty_policy', warrantyPolicy);
            await prefs.setString('return_policy', returnPolicy);
          }
        }
      } catch (_) {}
    }

    return {
      'warranty': warrantyPolicy,
      'return': returnPolicy,
    };
  }

  static String _applyTemplate(String template, Map<String, String> data) {
    var result = template;
    data.forEach((key, value) {
      result = result.replaceAll('{$key}', value);
    });
    return result;
  }

  /// Public wrapper for printing raw text via ESC/POS thermal printer.
  static Future<bool> printTextReceipt(
    String text, {
    PaperSize paper = PaperSize.mm80,
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
  }) {
    return _printTextReceipt(
      text,
      paper: paper,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
  }

  static Future<bool> _printTextReceipt(
    String text, {
    PaperSize paper = PaperSize.mm80,
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
  }) async {
    try {
    final policies = await _loadReceiptPolicies();
      final profile = await CapabilityProfile.load();
      final generator = Generator(paper, profile);
      final bytes = <int>[];
      bytes.addAll(generator.reset());

      final lines = text.split('\n');
      for (final line in lines) {
        var working = line;
        if (working.trim().isEmpty) {
          bytes.addAll(generator.feed(1));
          continue;
        }

        var align = PosAlign.left;
        var bold = false;
        var size = PosTextSize.size1;
        var isQr = false;
        var lineFeedOnly = false;

        while (working.startsWith('[')) {
          final end = working.indexOf(']');
          if (end <= 0) break;
          final tag = working.substring(1, end).toUpperCase().trim();
          working = working.substring(end + 1);

          switch (tag) {
            case 'C':
              align = PosAlign.center;
              break;
            case 'L':
              align = PosAlign.left;
              break;
            case 'R':
              align = PosAlign.right;
              break;
            case 'B':
              bold = true;
              break;
            case 'S2':
              size = PosTextSize.size2;
              break;
            case 'S1':
              size = PosTextSize.size1;
              break;
            case 'QR':
              isQr = true;
              break;
            case 'BR':
              lineFeedOnly = true;
              break;
            default:
              break;
          }
        }

        if (lineFeedOnly && working.trim().isEmpty) {
          bytes.addAll(generator.feed(1));
          continue;
        }

        if (isQr) {
          final qrData = working.trim();
          if (qrData.isNotEmpty) {
            bytes.addAll(generator.qrcode(qrData));
          } else {
            bytes.addAll(generator.feed(1));
          }
          continue;
        }

        final textLine = _removeDiacritics(working);
        bytes.addAll(
          generator.text(
            textLine,
            styles: PosStyles(
              align: align,
              bold: bold,
              height: size,
              width: size,
            ),
          ),
        );
      }

      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());

      return _sendToPrinter(
        bytes,
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
      );
    } catch (e) {
      print('PRINT_DEBUG: _printTextReceipt error: $e');
      return false;
    }
  }

  static String _repairStatusText(int status) {
    switch (status) {
      case 1:
        return 'Tiếp nhận';
      case 2:
        return 'Đang sửa';
      case 3:
        return 'Sửa xong';
      case 4:
        return 'Đã giao';
      default:
        return 'Không xác định';
    }
  }
  /// Đọc cài đặt từng element từ Label Designer
  static Future<Map<String, _LabelElementConfig>>
  _loadLabelDesignerConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('label_designer_elements');
    final Map<String, _LabelElementConfig> config = {};

    if (jsonStr != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(jsonStr);
        for (final el in jsonList) {
          final element = _LabelElementConfig.fromJson(el);
          config[element.id] = element;
        }
      } catch (_) {}
    }

    return config;
  }

  /// In tem theo cài đặt từ THIẾT KẾ TEM (LabelDesignerView)
  /// Hỗ trợ: gộp dòng (row), khoảng cách (spacing), cỡ chữ riêng từng element
  Future<bool> _printLabelWithDesignerConfig({
    required Generator generator,
    required List<int> bytes,
    required Map<String, dynamic> product,
    required Map<String, _LabelElementConfig> designerConfig,
    required List<String> customLines,
    required dynamic printData,
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Lấy khổ giấy để tính maxChars cho wrap text
    final paperSizeStr = prefs.getString('label_paper_size') ?? '80';
    final int baseMaxChars;
    switch (paperSizeStr) {
      case '58':
        baseMaxChars = 22; // 58mm ~ 22 ký tự
        break;
      case '72':
        baseMaxChars = 28; // 72mm ~ 28 ký tự
        break;
      case '2x3':
        baseMaxChars = 16; // 2cm ~ 20mm ~ 16 ký tự
        break;
      case '3x4':
        baseMaxChars = 24; // 3cm ~ 30mm ~ 24 ký tự
        break;
      case '4x6':
        baseMaxChars = 32; // 4cm ~ 40mm ~ 32 ký tự
        break;
      default:
        baseMaxChars = 32; // 80mm ~ 32 ký tự
    }

    // Lấy loại mã (QR hoặc Barcode)
    final codeType = prefs.getString('label_code_type') ?? 'qr';

    final forceRasterQr = await _shouldForceRasterQr(
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
    );

    // Lấy thông tin shop từ LabelSettingsService
    final labelService = LabelSettingsService();
    final shopSettings = await labelService.getShopLabelSettings();
    final shopName = shopSettings.shopName;
    final hotline = shopSettings.hotline;

    // Nhóm elements theo row
    final visibleElements = designerConfig.values
        .where((e) => e.visible)
        .toList();
    final rowMap = <int, List<_LabelElementConfig>>{};
    for (final el in visibleElements) {
      rowMap.putIfAbsent(el.row, () => []);
      rowMap[el.row]!.add(el);
    }
    final sortedRows = rowMap.keys.toList()..sort();

    // Lấy giá từ printData nếu có
    final priceKPK = printData?.customPriceKPK ?? product['price'] ?? 0;
    final priceCPK =
        printData?.customPriceCPK ??
        printData?.calculatedCPK ??
        (priceKPK is int ? priceKPK + 500000 : priceKPK);

    // In từng row
    for (final rowIndex in sortedRows) {
      final rowElements = rowMap[rowIndex]!;
      rowElements.sort((a, b) => a.col.compareTo(b.col));

      // Tính khoảng cách dưới từ element đầu tiên
      final spacing = rowElements.first.spacing;

      // Nếu row có nhiều element (gộp dòng), xử lý đặc biệt
      if (rowElements.length > 1) {
        // In 2 element trên cùng 1 dòng (VD: IMEI + QR)
        final leftEl = rowElements.first;
        final rightEl = rowElements.last;

        // Lấy text cho mỗi bên
        final leftText = _getElementText(
          leftEl,
          product,
          priceKPK,
          priceCPK,
          shopName,
          hotline,
        );
        final rightText = _getElementText(
          rightEl,
          product,
          priceKPK,
          priceCPK,
          shopName,
          hotline,
        );

        // Nếu là QR code ở bên phải
        if (rightEl.id == 'qr_code') {
          final simpleId =
              product['id']?.toString() ??
              product['firestoreId']?.split('_').last ??
              'unknown';

          // In IMEI và QR cùng hàng bằng cách in text trước, QR sau (căn phải)
          if (leftText.isNotEmpty) {
            // In IMEI (text bên trái)
            bytes.addAll(
              generator.text(
                _labelSingleLine(
                  leftText,
                  leftEl.fontSize,
                  uppercaseWhenLarge: leftEl.fontSize >= 1.0,
                ),
                styles: _labelTextStyle(
                  leftEl.fontSize,
                  bold: leftEl.bold,
                  secondary: leftEl.fontSize < 1.0,
                  fontTypeKey: leftEl.fontType,
                ),
              ),
            );
          }

          // In QR code hoặc Barcode tùy theo cài đặt
          if (codeType == 'barcode') {
            // In 4 số cuối IMEI dưới dạng text lớn (máy PT-50DC không hỗ trợ barcode ESC/POS)
            final imei = product['imei']?.toString() ?? simpleId;
            final numericOnly = imei.replaceAll(RegExp(r'[^0-9]'), '');
            final last4 = numericOnly.length >= 4 
                ? numericOnly.substring(numericOnly.length - 4) 
                : numericOnly.padLeft(4, '0');
            // In mã số với font lớn, đậm để dễ nhận diện
            bytes.addAll(
              generator.text(
                '[$last4]',
                styles: const PosStyles(
                  align: PosAlign.center,
                  bold: true,
                  height: PosTextSize.size2,
                  width: PosTextSize.size2,
                ),
              ),
            );
          } else {
            // In QR code
            QRSize qrSize;
            if (rightEl.fontSize <= 0.7) {
              qrSize = QRSize.size2;
            } else if (rightEl.fontSize <= 1.0) {
              qrSize = QRSize.size3;
            } else {
              qrSize = QRSize.size4;
            }
            _addQrCode(
              generator: generator,
              bytes: bytes,
              data: "check_inv:$simpleId",
              size: qrSize,
              forceRaster: forceRasterQr,
            );
          }
        } else if (leftEl.id == 'qr_code') {
          final simpleId =
              product['id']?.toString() ??
              product['firestoreId']?.split('_').last ??
              'unknown';

          // In QR code hoặc Barcode ở bên trái
          if (codeType == 'barcode') {
            final imei = product['imei']?.toString() ?? simpleId;
            final numericOnly = imei.replaceAll(RegExp(r'[^0-9]'), '');
            final last4 = numericOnly.length >= 4 
                ? numericOnly.substring(numericOnly.length - 4) 
                : numericOnly.padLeft(4, '0');
            // In mã số với font lớn
            bytes.addAll(
              generator.text(
                '[$last4]',
                styles: const PosStyles(
                  align: PosAlign.center,
                  bold: true,
                  height: PosTextSize.size2,
                  width: PosTextSize.size2,
                ),
              ),
            );
          } else {
            QRSize qrSize;
            if (leftEl.fontSize <= 0.7) {
              qrSize = QRSize.size2;
            } else if (leftEl.fontSize <= 1.0) {
              qrSize = QRSize.size3;
            } else {
              qrSize = QRSize.size4;
            }
            _addQrCode(
              generator: generator,
              bytes: bytes,
              data: "check_inv:$simpleId",
              size: qrSize,
              forceRaster: forceRasterQr,
            );
          }

          // In text bên phải
          if (rightText.isNotEmpty) {
            bytes.addAll(
              generator.text(
                _labelSingleLine(
                  rightText,
                  rightEl.fontSize,
                  uppercaseWhenLarge: rightEl.fontSize >= 1.0,
                ),
                styles: _labelTextStyle(
                  rightEl.fontSize,
                  bold: rightEl.bold,
                  secondary: rightEl.fontSize < 1.0,
                  fontTypeKey: rightEl.fontType,
                ),
              ),
            );
          }
        } else {
          // 2 text elements cùng dòng - dùng row
          final leftWidth = (leftEl.flex * 12).round().clamp(1, 11);
          final rightWidth = 12 - leftWidth;

          final leftAlign = leftEl.align == 'left'
              ? PosAlign.left
              : leftEl.align == 'right'
              ? PosAlign.right
              : PosAlign.center;
          final rightAlign = rightEl.align == 'left'
              ? PosAlign.left
              : rightEl.align == 'right'
              ? PosAlign.right
              : PosAlign.center;
          bytes.addAll(
            generator.row([
              PosColumn(
                text: _labelSingleLine(
                  leftText,
                  leftEl.fontSize,
                  uppercaseWhenLarge: leftEl.fontSize >= 1.0,
                ),
                width: leftWidth,
                styles: _labelTextStyle(
                  leftEl.fontSize,
                  align: leftAlign,
                  bold: leftEl.bold,
                  secondary: leftEl.fontSize < 1.0,
                  fontTypeKey: leftEl.fontType,
                ),
              ),
              PosColumn(
                text: _labelSingleLine(
                  rightText,
                  rightEl.fontSize,
                  uppercaseWhenLarge: rightEl.fontSize >= 1.0,
                ),
                width: rightWidth,
                styles: _labelTextStyle(
                  rightEl.fontSize,
                  align: rightAlign,
                  bold: rightEl.bold,
                  secondary: rightEl.fontSize < 1.0,
                  fontTypeKey: rightEl.fontType,
                ),
              ),
            ]),
          );
        }
      } else {
        // Chỉ 1 element trong row
        final el = rowElements.first;

        if (el.id == 'qr_code') {
          final simpleId =
              product['id']?.toString() ??
              product['firestoreId']?.split('_').last ??
              'unknown';

          // In QR code hoặc Barcode tùy theo cài đặt
          if (codeType == 'barcode') {
            // In 4 số cuối IMEI dưới dạng text lớn (máy PT-50DC không hỗ trợ barcode ESC/POS)
            final imei = product['imei']?.toString() ?? simpleId;
            final numericOnly = imei.replaceAll(RegExp(r'[^0-9]'), '');
            final last4 = numericOnly.length >= 4 
                ? numericOnly.substring(numericOnly.length - 4) 
                : numericOnly.padLeft(4, '0');
            bytes.addAll(
              generator.text(
                '[$last4]',
                styles: const PosStyles(
                  align: PosAlign.center,
                  bold: true,
                  height: PosTextSize.size2,
                  width: PosTextSize.size2,
                ),
              ),
            );
          } else {
            // In QR code
            QRSize qrSize;
            if (el.fontSize <= 0.7) {
              qrSize = QRSize.size2;
            } else if (el.fontSize <= 1.0) {
              qrSize = QRSize.size3;
            } else {
              qrSize = QRSize.size4;
            }
            _addQrCode(
              generator: generator,
              bytes: bytes,
              data: "check_inv:$simpleId",
              size: qrSize,
              forceRaster: forceRasterQr,
            );
          }
        } else {
          final text = _getElementText(
            el,
            product,
            priceKPK,
            priceCPK,
            shopName,
            hotline,
          );
          if (text.isNotEmpty) {
            // Tự động xuống dòng nếu text dài
            // Tính maxChars theo fontSize và khổ giấy
            final adjustedMax = el.fontSize >= 1.5
                ? max(baseMaxChars - 8, 14) // chữ to -> ít ký tự
                : el.fontSize <= 0.7
                ? baseMaxChars +
                      8 // chữ nhỏ -> nhiều ký tự
                : baseMaxChars;

            final cleanText = _labelSingleLine(text, el.fontSize);
            final linesToPrint = cleanText.length > adjustedMax
                ? _labelLines(text, el.fontSize, baseMaxChars: baseMaxChars)
                : [cleanText];

            for (final line in linesToPrint) {
              bytes.addAll(
                generator.text(
                  line,
                  styles: _labelTextStyle(
                    el.fontSize,
                    bold: el.bold,
                    emphasize: el.fontSize >= 1.3,
                    fontTypeKey: el.fontType,
                  ),
                ),
              );
            }
          }
        }
      }

      // Thêm spacing nếu > 0 (convert từ pixel sang feed lines)
      if (spacing > 4) {
        bytes.addAll(generator.feed(1));
      }
    }

    // In custom lines nếu có
    if (customLines.isNotEmpty) {
      bytes.addAll(generator.feed(1));
      for (final line in customLines) {
        if (line.trim().isNotEmpty) {
          bytes.addAll(
            generator.text(
              _labelSingleLine(line, 1.0),
              styles: _labelTextStyle(1.0, secondary: true),
            ),
          );
        }
      }
    }

    bytes.addAll(generator.feed(1));
    // Không dùng cut() cho máy in tem vì sẽ gây thừa 1 tem trắng
    // bytes.addAll(generator.cut());

    return _sendToPrinter(
      bytes,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
  }

  /// Lấy text cho từng element ID
  String _getElementText(
    _LabelElementConfig el,
    Map<String, dynamic> product,
    dynamic priceKPK,
    dynamic priceCPK,
    String shopName,
    String hotline,
  ) {
    switch (el.id) {
      case 'name':
        return (product['name']?.toString() ?? '').toUpperCase();
      case 'detail':
        return "${product['capacity'] ?? ''} ${product['color'] ?? ''} ${product['condition'] ?? ''}"
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toUpperCase();
      case 'label_info':
        final labelInfo = product['labelInfo']?.toString() ?? '';
        return labelInfo.isNotEmpty ? "${el.prefix}${labelInfo.toUpperCase()}" : '';
      case 'price_kpk':
        return "${el.prefix}${MoneyUtils.formatVND(priceKPK is int ? priceKPK : 0)}";
      case 'price_cpk':
        return "${el.prefix}${MoneyUtils.formatVND(priceCPK is int ? priceCPK : 0)}";
      case 'imei':
        final imei = product['imei']?.toString() ?? '';
        return imei.isNotEmpty ? "${el.prefix}$imei" : '';
      case 'shop_info':
        final parts = <String>[];
        if (shopName.isNotEmpty) parts.add(shopName.toUpperCase());
        if (hotline.isNotEmpty) parts.add(hotline);
        return parts.join(' - ');
      default:
        return '';
    }
  }

  static String _removeDiacritics(String str) {
    const vietnamese = 'aAeEoOuUiIdDyY';
    final vietnameseRegex = [
      RegExp(r'à|á|ạ|ả|ã|â|ầ|ấ|ậ|ẩ|ẫ|ă|ằ|ắ|ặ|ẳ|ẵ'),
      RegExp(r'À|Á|Ạ|Ả|Ã|Â|Ầ|Ấ|Ậ|Ẩ|Ẫ|Ă|Ằ|Ắ|Ặ|Ẳ|Ẵ'),
      RegExp(r'è|é|ẹ|ẻ|ẽ|ê|ề|ế|ệ|ể|ễ'),
      RegExp(r'È|É|Ạ|Ẻ|Ẽ|Ê|Ề|Ế|Ệ|Ể|Ễ'),
      RegExp(r'ò|ó|ọ|ỏ|õ|ô|ồ|ố|ộ|ổ|ỗ|ơ|ờ|ớ|ợ|ở|ỡ'),
      RegExp(r'Ò|Ó|Ọ|Ỏ|Õ|Ô|Ồ|Ố|Ộ|Ổ|Ỗ|Ơ|Ờ|Ớ|Ợ|Ở|Ỡ'),
      RegExp(r'ù|ú|ụ|ủ|ũ|ư|ừ|ứ|ự|ử|ữ'),
      RegExp(r'Ù|Ú|Ụ|Ủ|Ũ|Ư|Ừ|Ứ|Ự|Ử|Ữ'),
      RegExp(r'ì|í|ị|ỉ|ĩ'),
      RegExp(r'Ì|Í|Ị|Ỉ|Ĩ'),
      RegExp(r'đ'),
      RegExp(r'Đ'),
      RegExp(r'ỳ|ý|ỵ|ỷ|ỹ'),
      RegExp(r'Ỳ|Ý|Ỵ|Ỷ|Ỹ'),
    ];
    for (var i = 0; i < vietnameseRegex.length; i++) {
      str = str.replaceAll(vietnameseRegex[i], vietnamese[i]);
    }
    return str;
  }

  static List<String> _wrapPrinterText(String text, {int maxChars = 24}) {
    final clean = text.trim();
    if (clean.isEmpty) return const [];

    final words = clean.split(RegExp(r'\s+'));
    final lines = <String>[];
    var current = '';

    List<String> splitLongWord(String word) {
      final chunks = <String>[];
      for (var i = 0; i < word.length; i += maxChars) {
        chunks.add(word.substring(i, min(i + maxChars, word.length)));
      }
      return chunks;
    }

    for (final word in words) {
      if (word.length > maxChars) {
        if (current.isNotEmpty) {
          lines.add(current);
          current = '';
        }
        final chunks = splitLongWord(word);
        for (var i = 0; i < chunks.length; i++) {
          final chunk = chunks[i];
          final isLast = i == chunks.length - 1;
          if (isLast && chunk.length < maxChars) {
            current = chunk;
          } else {
            lines.add(chunk);
            current = '';
          }
        }
        continue;
      }

      if (current.isEmpty) {
        current = word;
        continue;
      }

      final candidate = '$current $word';
      if (candidate.length <= maxChars) {
        current = candidate;
      } else {
        lines.add(current);
        current = word;
      }
    }

    if (current.isNotEmpty) {
      lines.add(current);
    }

    return lines;
  }

  static int _maxCharsForLabel(
    LabelSize size, {
    bool emphasize = false,
    double fontScale = 1.0,
  }) {
    int base;
    switch (size) {
      case LabelSize.small:
        base = 20;
        break;
      case LabelSize.medium:
        base = 26;
        break;
      case LabelSize.large:
        base = 32;
        break;
      case LabelSize.custom:
        base = 26;
        break;
    }
    if (fontScale <= 0.85) {
      base += 6;
    } else if (fontScale >= 1.75) {
      base -= 4;
    }
    base = max(14, base);
    if (!emphasize) {
      return base;
    }
    final reduced = base - 4;
    return reduced >= 16 ? reduced : base;
  }

  static PosStyles _labelTextStyle(
    double fontScale, {
    PosAlign align = PosAlign.center,
    bool bold = false,
    bool emphasize = false,
    bool secondary = false,
    String? fontTypeKey,
  }) {
    // Logic đơn giản cho máy in nhiệt ESC/POS:
    // - fontB: chữ nhỏ hơn (~50%)
    // - fontA: chữ bình thường (100%)
    // - size2: to gấp đôi (200%)

    // Quy tắc:
    // fontSize <= 0.85: dùng fontB (chữ nhỏ)
    // fontSize > 0.85 && < 2.0: dùng fontA + size1 (chữ bình thường)
    // fontSize >= 2.0: dùng fontA + size2 (chữ to gấp đôi)

    final useSmallFont = fontScale <= 0.85;
    final useLargeFont = fontScale >= 2.0;

    final fontType = (fontTypeKey == 'B')
      ? PosFontType.fontB
      : fontTypeKey == 'A'
      ? PosFontType.fontA
      : (secondary || useSmallFont)
      ? PosFontType.fontB
      : PosFontType.fontA;

    final textSize = useLargeFont ? PosTextSize.size2 : PosTextSize.size1;

    // Bold khi fontSize > 1.0 hoặc được yêu cầu
    final effectiveBold = bold || (fontScale > 1.0 && !useSmallFont);

    return PosStyles(
      align: align,
      bold: effectiveBold,
      fontType: fontType,
      height: textSize,
      width: textSize,
    );
  }

  static List<String> _labelLines(
    String? raw,
    double fontScale, {
    int baseMaxChars = 24,
    bool uppercaseWhenLarge = true,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }
    final normalized = _removeDiacritics(raw.trim());
    final content = uppercaseWhenLarge && fontScale >= 0.95
        ? normalized.toUpperCase()
        : normalized;
    final adjustedMax = fontScale <= 0.85
        ? baseMaxChars + 6
        : fontScale >= 1.75
        ? max(baseMaxChars - 4, 16)
        : baseMaxChars;
    return _wrapPrinterText(content, maxChars: adjustedMax);
  }

  static String _labelSingleLine(
    String? raw,
    double fontScale, {
    bool uppercaseWhenLarge = true,
  }) {
    if (raw == null || raw.trim().isEmpty) {
      return '';
    }
    final normalized = _removeDiacritics(raw.trim());
    return uppercaseWhenLarge && fontScale >= 0.95
        ? normalized.toUpperCase()
        : normalized;
  }

  static Future<bool> _shouldForceRasterQr({
    PrinterType? printerType,
    dynamic bluetoothPrinter,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('pt50dc_force_raster_qr') ?? false) {
      return true;
    }

    final paperSize = prefs.getString('label_paper_size');
    if (paperSize == '50') {
      return true;
    }

    String? name;
    if (bluetoothPrinter != null) {
      if (bluetoothPrinter is Map) {
        name = bluetoothPrinter['name']?.toString();
      } else {
        name = bluetoothPrinter.name?.toString();
      }
    }
    name ??= (await BluetoothPrinterService.getSavedPrinter())?.name;
    return name?.toUpperCase().contains('PT-50DC') ?? false;
  }

  static int _qrPixelSize(QRSize size) {
    switch (size) {
      case QRSize.size2:
        return 140;
      case QRSize.size3:
        return 180;
      case QRSize.size4:
        return 220;
      case QRSize.size6:
        return 280;
      default:
        return 220;
    }
  }

  static img.Image _buildQrImage(String data, int sizePx) {
    final qr = bc.Barcode.qrCode(
      errorCorrectLevel: bc.BarcodeQRCorrectionLevel.medium,
    );
    final image = img.Image(width: sizePx, height: sizePx);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));
    drawBarcode(
      image,
      qr,
      data,
      x: 0,
      y: 0,
      width: sizePx,
      height: sizePx,
    );
    return image;
  }

  static void _addQrCode({
    required Generator generator,
    required List<int> bytes,
    required String data,
    required QRSize size,
    bool forceRaster = false,
  }) {
    if (!forceRaster) {
      bytes.addAll(generator.qrcode(data, size: size));
      return;
    }
    final image = _buildQrImage(data, _qrPixelSize(size));
    bytes.addAll(generator.imageRaster(image, align: PosAlign.center));
  }

  static Future<bool> _sendToPrinter(
    List<int> bytes, {
    PrinterType? printerType,
    String? wifiIp,
    dynamic bluetoothPrinter,
  }) async {
    try {
      print('PRINT_DEBUG: === _sendToPrinter START ===');
      print('PRINT_DEBUG: bytes length = ${bytes.length}');
      print('PRINT_DEBUG: printerType = $printerType');
      print('PRINT_DEBUG: wifiIp = $wifiIp');
      print('PRINT_DEBUG: bluetoothPrinter = $bluetoothPrinter');
      print('PRINT_DEBUG: bluetoothPrinter type = ${bluetoothPrinter?.runtimeType}');

      // Browser cannot print to BT/WiFi sockets directly.
      // Route web print through local/LAN bridge server.
      if (kIsWeb) {
        final bridgeOk = await WebPrintBridgeService.sendBytes(
          bytes,
          wifiIp: wifiIp,
          printerType: printerType,
          jobType: 'receipt',
        );
        print('PRINT_DEBUG: [WEB_BRIDGE] result: $bridgeOk');
        return bridgeOk;
      }
      
      // WiFi printer - chỉ khi chọn explicit WiFi
      if (printerType == PrinterType.wifi) {
        print('PRINT_DEBUG: [WIFI] Trying WiFi printer (explicit)...');
        final prefs = await SharedPreferences.getInstance();
        final ip = wifiIp ?? prefs.getString('printer_ip') ?? prefs.getString('thermal_printer_ip') ?? "192.168.1.100";
        print('PRINT_DEBUG: [WIFI] Connecting to IP: $ip');
        final connected = await WifiPrinterService.instance.connect(
          ip: ip,
          port: 9100,
        );
        print('PRINT_DEBUG: [WIFI] Connection result: $connected');
        if (connected) {
          final printResult = await WifiPrinterService.instance.printBytes(bytes);
          print('PRINT_DEBUG: [WIFI] printBytes result: $printResult');
          return printResult;
        }
        print('PRINT_DEBUG: [WIFI] Connection failed');
        return false;
      }
      
      // Bluetooth explicit hoặc Auto mode - thử Bluetooth trước
      if (printerType == PrinterType.bluetooth || printerType == PrinterType.auto || printerType == null) {
        // Nếu có bluetooth printer object cụ thể
        if (bluetoothPrinter != null) {
          print('PRINT_DEBUG: [BT] Trying with provided printer object...');
          String? mac;
          if (bluetoothPrinter is Map) {
            mac = bluetoothPrinter['macAddress'] as String?;
          } else if (bluetoothPrinter is BluetoothPrinterConfig) {
            mac = bluetoothPrinter.macAddress;
          } else {
            // Try dynamic access
            try {
              mac = bluetoothPrinter.macAddress as String?;
            } catch (e) {
              print('PRINT_DEBUG: [BT] Cannot get macAddress: $e');
            }
          }
          print('PRINT_DEBUG: [BT] Extracted MAC: $mac');
          
          if (mac != null && mac.isNotEmpty) {
            final ok = await BluetoothPrinterService.connect(mac);
            print('PRINT_DEBUG: [BT] Connect result: $ok');
            if (ok) {
              final printOk = await BluetoothPrinterService.printBytes(bytes);
              print('PRINT_DEBUG: [BT] printBytes result: $printOk');
              if (printOk) return true;
            }
          } else {
            print('PRINT_DEBUG: [BT] MAC address is null or empty');
          }
        }
        
        // Thử với saved Bluetooth printer
        print('PRINT_DEBUG: [BT] Trying with ensureConnection (saved printer)...');
        final hasBt = await BluetoothPrinterService.ensureConnection();
        print('PRINT_DEBUG: [BT] ensureConnection result: $hasBt');
        if (hasBt) {
          final printOk = await BluetoothPrinterService.printBytes(bytes);
          print('PRINT_DEBUG: [BT] printBytes with saved printer result: $printOk');
          if (printOk) return true;
        }
        
        // Nếu chọn explicit Bluetooth mà không kết nối được
        if (printerType == PrinterType.bluetooth) {
          print('PRINT_DEBUG: [BT] Explicitly selected but all attempts failed');
          return false;
        }
      }
      
      // Auto mode fallback: thử WiFi sau khi Bluetooth fail
      if (printerType == PrinterType.auto || printerType == null) {
        print('PRINT_DEBUG: [AUTO] Trying WiFi fallback...');
        final prefs = await SharedPreferences.getInstance();
        final savedIp = wifiIp ?? prefs.getString('printer_ip') ?? prefs.getString('thermal_printer_ip');
        print('PRINT_DEBUG: [AUTO] WiFi fallback IP: $savedIp');
        if (savedIp != null && savedIp.isNotEmpty) {
          final connected = await WifiPrinterService.instance.connect(ip: savedIp, port: 9100);
          print('PRINT_DEBUG: [AUTO] WiFi connection result: $connected');
          if (connected) {
            final printResult = await WifiPrinterService.instance.printBytes(bytes);
            print('PRINT_DEBUG: [AUTO] WiFi printBytes result: $printResult');
            return printResult;
          }
        } else {
          print('PRINT_DEBUG: [AUTO] No saved WiFi IP for fallback');
        }
      }

      print('PRINT_DEBUG: === _sendToPrinter END: No printer available ===');
      return false;
    } catch (e, stackTrace) {
      print('PRINT_DEBUG: Exception in _sendToPrinter: $e');
      print('PRINT_DEBUG: Stack trace: $stackTrace');
      return false;
    }
  }

  static Future<bool> printLabelBitmap(
    Uint8List pngBytes, {
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
    int feedLines = 2,
    bool cut = true,
    String? qrData,
    QRSize? qrSize,
    String? barcodeData,
  }) async {
    try {
      print('PRINT_DEBUG: printLabelBitmap called');
      print('PRINT_DEBUG: pngBytes length = ${pngBytes.length}');
      print('PRINT_DEBUG: printerType = $printerType');
      print('PRINT_DEBUG: wifiIp = $wifiIp');
      print('PRINT_DEBUG: bluetoothPrinter = $bluetoothPrinter');
      
      var decoded = img.decodeImage(pngBytes);
      if (decoded == null) {
        print('PRINT_DEBUG: Failed to decode image - trying decodePng');
        decoded = img.decodePng(pngBytes);
      }
      if (decoded == null) {
        print('PRINT_DEBUG: Failed to decode image with both methods');
        return false;
      }
      print('PRINT_DEBUG: Image decoded: ${decoded.width}x${decoded.height}');

      final prefs = await SharedPreferences.getInstance();
      final paperSizeStr = prefs.getString('label_paper_size') ?? '80';
      print('PRINT_DEBUG: Paper size setting = $paperSizeStr');
      
      PaperSize paperSize;
      int maxWidth;
      switch (paperSizeStr) {
        case '50':
          paperSize = PaperSize.mm58;
          maxWidth = 384; // 58mm thermal printer width in dots
          break;
        case '58':
          paperSize = PaperSize.mm58;
          maxWidth = 384;
          break;
        case '72':
          paperSize = PaperSize.mm72;
          maxWidth = 512;
          break;
        default:
          paperSize = PaperSize.mm80;
          maxWidth = 576; // 80mm thermal printer width in dots
      }
      
      // Resize hình ảnh nếu quá lớn
      if (decoded.width > maxWidth) {
        print('PRINT_DEBUG: Resizing image from ${decoded.width} to $maxWidth width');
        final ratio = maxWidth / decoded.width;
        final newHeight = (decoded.height * ratio).round();
        decoded = img.copyResize(decoded, width: maxWidth, height: newHeight);
        print('PRINT_DEBUG: Image resized to: ${decoded.width}x${decoded.height}');
      }

      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);
      final bytes = <int>[];
      bytes.addAll(generator.reset());
      
      // Sử dụng imageRaster với imageFn để đảm bảo tương thích
      try {
        bytes.addAll(generator.imageRaster(decoded, align: PosAlign.center));
      } catch (rasterError) {
        print('PRINT_DEBUG: imageRaster failed: $rasterError - trying image method');
        // Fallback: thử method image() thay vì imageRaster()
        bytes.addAll(generator.image(decoded, align: PosAlign.center));
      }
      
      if (qrData != null && qrData.trim().isNotEmpty) {
        bytes.addAll(generator.feed(1));
        _addQrCode(
          generator: generator,
          bytes: bytes,
          data: qrData.trim(),
          size: qrSize ?? QRSize.size4,
          forceRaster: false,
        );
      }

      if (barcodeData != null && barcodeData.trim().isNotEmpty) {
        bytes.addAll(generator.feed(1));
        try {
          bytes.addAll(
            generator.barcode(
              Barcode.code128(barcodeData.trim().codeUnits),
              align: PosAlign.center,
            ),
          );
        } catch (e) {
          bytes.addAll(
            generator.text(
              _removeDiacritics(barcodeData.trim()),
              styles: const PosStyles(align: PosAlign.center, bold: true),
            ),
          );
        }
      }

      if (feedLines > 0) {
        bytes.addAll(generator.feed(feedLines));
      }
      if (cut) {
        bytes.addAll(generator.cut());
      }
      
      print('PRINT_DEBUG: ESC/POS bytes generated, length = ${bytes.length}');

      final result = await _sendToPrinter(
        bytes,
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
      );
      print('PRINT_DEBUG: _sendToPrinter result = $result');
      return result;
    } catch (e, stackTrace) {
      print('PRINT_DEBUG: printLabelBitmap Exception: $e');
      print('PRINT_DEBUG: Stack: $stackTrace');
      return false;
    }
  }

  // --- PHIẾU TIẾP NHẬN SỬA CHỮA CHUYÊN NGHIỆP ---
  static Future<bool> printRepairReceiptFromRepair(
    Repair repair,
    Map<String, dynamic> shopInfo, {
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final useTemplate = prefs.getBool('repair_invoice_use_template') ?? false;
    final templateHeader = prefs.getString('repair_invoice_header') ?? '';
    final templateBody = prefs.getString('repair_invoice_body') ?? '';
    final templateFooter = prefs.getString('repair_invoice_footer') ?? '';
    final hasTemplate =
        templateHeader.trim().isNotEmpty ||
        templateBody.trim().isNotEmpty ||
        templateFooter.trim().isNotEmpty;

    if (useTemplate && hasTemplate) {
      final createdAt = DateTime.fromMillisecondsSinceEpoch(repair.createdAt);
      final data = <String, String>{
        'shopName': shopInfo['shopName']?.toString() ?? 'SHOP NEW',
        'shopAddr': shopInfo['shopAddr']?.toString() ?? '',
        'shopPhone': shopInfo['shopPhone']?.toString() ?? '',
        'code': repair.firestoreId?.toString() ?? repair.createdAt.toString(),
        'date': DateFormat('dd/MM/yyyy').format(createdAt),
        'time': DateFormat('HH:mm').format(createdAt),
        'customerName': repair.customerName ?? '',
        'customerPhone': repair.phone ?? '',
        'model': repair.model ?? '',
        'imei': repair.imei ?? '',
        'issue': repair.issue ?? '',
        'warranty': repair.warranty ?? '',
        'accessories': repair.accessories ?? '',
        'partsUsed': repair.partsUsed ?? '',
        'color': repair.color ?? '',
        'condition': repair.condition ?? '',
        'notes': repair.notes ?? '',
        'createdBy': repair.createdBy ?? '',
        'repairedBy': repair.repairedBy ?? '',
        'deliveredBy': repair.deliveredBy ?? '',
        'services': repair.services.map((s) => s.serviceName).join(', '),
        'price': MoneyUtils.formatVND(repair.price),
        'paymentMethod': repair.paymentMethod ?? '',
        'status': _repairStatusText(repair.status),
        'qrData': 'repair_check:${repair.firestoreId ?? repair.createdAt}',
      };

      final templateText = [
        templateHeader,
        templateBody,
        templateFooter,
      ].where((s) => s.trim().isNotEmpty).join('\n');

      final text = _applyTemplate(templateText, data);
      final ok = await _printTextReceipt(
        text,
        paper: PaperSize.mm80,
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
      );
      if (ok) return true;
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());

    bytes.addAll(
      generator.text(
        _removeDiacritics(shopInfo['shopName'] ?? 'SHOP NEW'),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(
      generator.text(
        _removeDiacritics(shopInfo['shopAddr'] ?? 'Chuyen Smartphone & Laptop'),
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(
      generator.text(
        "Hotline: ${shopInfo['shopPhone'] ?? '0123.456.789'}",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(generator.hr());

    bytes.addAll(
      generator.text(
        'PHIEU TIEP NHAN MAY',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(
      generator.text(
        "Ma don: ${repair.firestoreId ?? repair.createdAt}",
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(
      generator.text(
        "Ngay nhan: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(repair.createdAt))}",
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.text(
        _removeDiacritics("KHACH HANG: ${repair.customerName}"),
        styles: const PosStyles(bold: true),
      ),
    );
    bytes.addAll(generator.text("SDT: ${repair.phone}"));
    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.text(
        _removeDiacritics("MAY: ${repair.model}"),
        styles: const PosStyles(bold: true),
      ),
    );
    if (repair.imei != null && repair.imei!.isNotEmpty) {
      bytes.addAll(generator.text("IMEI/SN: ${repair.imei}"));
    }
    bytes.addAll(
      generator.text(_removeDiacritics("TINH TRANG: ${repair.issue}")),
    );

    String subInfo = "";
    if (repair.color != null) subInfo += "Mau: ${repair.color} | ";
    if (repair.condition != null) subInfo += "Vo: ${repair.condition}";
    if (subInfo.isNotEmpty) {
      bytes.addAll(
        generator.text(
          _removeDiacritics(subInfo),
          styles: const PosStyles(fontType: PosFontType.fontB),
        ),
      );
    }

    bytes.addAll(
      generator.text(_removeDiacritics("PHU KIEN: ${repair.accessories}")),
    );
    bytes.addAll(generator.feed(1));

    final priceStr = MoneyUtils.formatVND(repair.price);
    bytes.addAll(
      generator.text(
        "GIA DU KIEN: $priceStr VND",
        styles: const PosStyles(bold: true, height: PosTextSize.size2),
      ),
    );
    bytes.addAll(
      generator.text(_removeDiacritics("Hinh thuc: ${repair.paymentMethod}")),
    );
    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.text(
        _removeDiacritics("Quet ma de tra cuu don hang:"),
        styles: const PosStyles(
          align: PosAlign.center,
          fontType: PosFontType.fontB,
        ),
      ),
    );
    // Đã sửa lỗi: Gỡ bỏ tham số size: QRSize.size4 gây lỗi
    bytes.addAll(
      generator.qrcode(
        "repair_check:${repair.firestoreId ?? repair.createdAt}",
      ),
    );
    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.text(
        _removeDiacritics("- Quy khach vui long giu phieu de nhan may."),
        styles: const PosStyles(fontType: PosFontType.fontB),
      ),
    );
    bytes.addAll(
      generator.text(
        _removeDiacritics(
          "- Shop khong chiu trach nhiem ve du lieu trong may.",
        ),
        styles: const PosStyles(fontType: PosFontType.fontB),
      ),
    );
    bytes.addAll(generator.feed(1));

    bytes.addAll(
      generator.row([
        PosColumn(
          text: 'Khach hang',
          width: 6,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
        PosColumn(
          text: 'Nhan vien',
          width: 6,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      ]),
    );
    bytes.addAll(generator.feed(3));

    bytes.addAll(
      generator.text(
        'CAM ON QUY KHACH!',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return _sendToPrinter(
      bytes,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
  }

  static Future<bool> printProductQRLabel(
    Map<String, dynamic> product, {
    String? customMac,
    PrinterType? printerType,
    String? wifiIp,
    dynamic bluetoothPrinter,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final resolvedBluetoothPrinter = bluetoothPrinter ??
          (customMac != null ? {'macAddress': customMac} : null);

      final forceRasterQr = await _shouldForceRasterQr(
        printerType: printerType,
        bluetoothPrinter: resolvedBluetoothPrinter,
      );

      // Đọc size giấy từ cài đặt THIẾT KẾ TEM
      final paperSizeStr = prefs.getString('label_paper_size') ?? '80';
      PaperSize paperSize;
      switch (paperSizeStr) {
        case '50':
          paperSize = PaperSize.mm58;
          break;
        case '58':
          paperSize = PaperSize.mm58;
          break;
        case '72':
          paperSize = PaperSize.mm72;
          break;
        default:
          paperSize = PaperSize.mm80;
      }

      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);
      List<int> bytes = [];
      bytes.addAll(generator.reset());

      // Kiểm tra chế độ tùy chỉnh từ PrintLabelDialog
      final isCustomMode = product['_isCustomMode'] == true;

      // ĐỌC CẤU HÌNH TỪ LABEL DESIGNER PRO (nếu có)
      final designerConfig = await _loadLabelDesignerConfig();
      final hasDesignerConfig = designerConfig.isNotEmpty;
      final hasVisibleDesignerElements = designerConfig.values.any(
        (e) => e.visible,
      );

      // Nếu có cài đặt từ Label Designer và KHÔNG phải custom mode -> Dùng layout từ Designer
      if (hasDesignerConfig && hasVisibleDesignerElements && !isCustomMode) {
        final service = UnifiedPrinterService();
        final ok = await service._printLabelWithDesignerConfig(
          generator: generator,
          bytes: bytes,
          product: product,
          designerConfig: designerConfig,
          customLines: [],
          printData: null,
          printerType: printerType,
          bluetoothPrinter: resolvedBluetoothPrinter,
          wifiIp: wifiIp,
        );
        if (ok) return true;
      }

      // ========== FALLBACK: In theo cách cũ nếu chưa có Label Designer config ==========

      // Tính maxChars dựa trên khổ giấy
      final int fallbackMaxChars;
      switch (paperSizeStr) {
        case '50':
          fallbackMaxChars = 20;
          break;
        case '58':
          fallbackMaxChars = 22;
          break;
        case '72':
          fallbackMaxChars = 28;
          break;
        default:
          fallbackMaxChars = 32;
      }

      // Lấy cấu hình từ Design View hoặc Custom Mode
      bool showName,
          showDetail,
          showKPK,
          showCPK,
          showIMEI,
          showQR,
          showShopInfo;
      double nameScale,
          detailScale,
          kpkScale,
          cpkScale,
          imeiScale,
          shopInfoScale;
      String kpkPrefix, cpkPrefix, imeiPrefix;

      if (isCustomMode) {
        // Dùng cấu hình từ PrintLabelDialog
        showName = product['_customShowName'] ?? true;
        showDetail = product['_customShowDetail'] ?? true;
        showKPK = product['_customShowKPK'] ?? true;
        showCPK = product['_customShowCPK'] ?? true;
        showIMEI = product['_customShowIMEI'] ?? true;
        showQR = product['_customShowQR'] ?? true;
        showShopInfo = false;

        nameScale = detailScale = kpkScale = cpkScale = imeiScale =
            shopInfoScale = prefs.getDouble('label_font_scale') ?? 1.0;
        kpkPrefix = 'Giá KPK: ';
        cpkPrefix = 'Giá CPK: ';
        imeiPrefix = 'IMEI: ';
      } else {
        // Fallback: Cấu hình cơ bản từ Design View (khi chưa có Label Designer)
        showName = prefs.getBool('label_show_name') ?? true;
        showDetail = prefs.getBool('label_show_detail') ?? true;
        showKPK = prefs.getBool('label_show_price_kpk') ?? true;
        showCPK = prefs.getBool('label_show_price_cpk') ?? true;
        showIMEI = prefs.getBool('label_show_imei') ?? true;
        showQR = prefs.getBool('label_show_qr') ?? true;
        showShopInfo = prefs.getBool('label_show_shop_info') ?? true;

        final globalScale = prefs.getDouble('label_font_scale') ?? 1.0;
        nameScale = globalScale * 1.3;
        detailScale = globalScale;
        kpkScale = globalScale * 1.2;
        cpkScale = globalScale * 1.2;
        imeiScale = globalScale * 0.9;
        shopInfoScale = globalScale * 0.8;

        kpkPrefix = 'GIA KPK: ';
        cpkPrefix = 'GIA CPK: ';
        imeiPrefix = 'IMEI: ';
      }

      final customText = prefs.getString('label_custom_text') ?? "";
      final fontScale = prefs.getDouble('label_font_scale') ?? 1.0;

      // Lấy nội dung tùy biến từ dialog (nếu có)
      final customLines = (product['_customLines'] as List<dynamic>?) ?? [];

      // 1. TÊN SẢN PHẨM (SIZE theo nameScale) - Tự động xuống dòng
      if (showName) {
        final rawName = product['name']?.toString() ?? 'N/A';
        final cleanName = _labelSingleLine(rawName, nameScale);
        // Tính maxChars theo khổ giấy và fontSize
        final adjustedMax = nameScale >= 1.5
            ? max(fallbackMaxChars - 8, 14)
            : fallbackMaxChars;
        final linesToPrint = cleanName.length > adjustedMax
            ? _labelLines(rawName, nameScale, baseMaxChars: fallbackMaxChars)
            : [cleanName];
        for (final line in linesToPrint) {
          bytes.addAll(
            generator.text(
              line,
              styles: _labelTextStyle(nameScale, bold: true, emphasize: true),
            ),
          );
        }
      }

      // 2. CHI TIẾT (SIZE theo detailScale) - Tự động xuống dòng
      if (showDetail) {
        final detail =
            "${product['capacity'] ?? ''} ${product['color'] ?? ''} ${product['condition'] ?? ''}"
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
        if (detail.isNotEmpty) {
          final cleanDetail = _labelSingleLine(detail, detailScale);
          final adjustedDetailMax = detailScale >= 1.5
              ? max(fallbackMaxChars - 6, 16)
              : fallbackMaxChars + 4;
          final detailLines = cleanDetail.length > adjustedDetailMax
              ? _labelLines(
                  detail,
                  detailScale,
                  baseMaxChars: fallbackMaxChars + 4,
                )
              : [cleanDetail];
          for (final line in detailLines) {
            bytes.addAll(
              generator.text(
                line,
                styles: _labelTextStyle(
                  detailScale,
                  bold: true,
                  secondary: detailScale < 1.0,
                ),
              ),
            );
          }
        }
      }

      // 3. GIÁ BÁN KPK (SIZE theo kpkScale)
      final price = product['price'] ?? 0;
      if (showKPK) {
        final label = "$kpkPrefix${MoneyUtils.formatVND(price)}";
        bytes.addAll(
          generator.text(
            _labelSingleLine(
              label,
              kpkScale,
              uppercaseWhenLarge: kpkScale >= 1.0,
            ),
            styles: _labelTextStyle(kpkScale, bold: true),
          ),
        );
      }

      // 4. GIÁ BÁN CPK (SIZE theo cpkScale)
      if (showCPK) {
        final priceCPK =
            product['priceCPK'] ?? (price is int ? price + 500000 : price);
        final label = "$cpkPrefix${MoneyUtils.formatVND(priceCPK)}";
        bytes.addAll(
          generator.text(
            _labelSingleLine(
              label,
              cpkScale,
              uppercaseWhenLarge: cpkScale >= 1.0,
            ),
            styles: _labelTextStyle(cpkScale, bold: true),
          ),
        );
      }

      // 5. IMEI (SIZE theo imeiScale)
      if (showIMEI) {
        final imeiLine = _labelSingleLine(
          "$imeiPrefix${product['imei'] ?? 'N/A'}",
          imeiScale,
          uppercaseWhenLarge: false,
        );
        bytes.addAll(
          generator.text(
            imeiLine,
            styles: _labelTextStyle(
              imeiScale,
              bold: true,
              secondary: imeiScale < 1.0,
            ),
          ),
        );
      }

      // 6. NỘI DUNG TÙY BIẾN TỪ DIALOG (cho giấy lớn)
      if (customLines.isNotEmpty) {
        bytes.addAll(generator.feed(1));
        for (final line in customLines) {
          if (line.toString().trim().isNotEmpty) {
            bytes.addAll(
              generator.text(
                _labelSingleLine(line.toString(), fontScale),
                styles: _labelTextStyle(fontScale, secondary: true),
              ),
            );
          }
        }
      }

      // 7. QR CODE (NẾU CÓ)
      if (showQR) {
        bytes.addAll(generator.feed(1));
        // Dùng ID số đơn giản để QR code dễ scan hơn
        final simpleId =
            product['id']?.toString() ??
            product['firestoreId']?.split('_').last ??
            'unknown';
        _addQrCode(
          generator: generator,
          bytes: bytes,
          data: "check_inv:$simpleId",
          size: QRSize.size4,
          forceRaster: forceRasterQr,
        );
      }

      // 8. THÔNG TIN SHOP (nếu bật)
      if (showShopInfo) {
        final labelService = LabelSettingsService();
        final shopSettings = await labelService.getShopLabelSettings();
        final shopInfoParts = <String>[];
        if (shopSettings.shopName.isNotEmpty) {
          shopInfoParts.add(shopSettings.shopName);
        }
        if (shopSettings.hotline.isNotEmpty) {
          shopInfoParts.add(shopSettings.hotline);
        }
        if (shopInfoParts.isNotEmpty) {
          final shopInfoLine = _labelSingleLine(
            shopInfoParts.join(' - '),
            shopInfoScale,
          );
          bytes.addAll(
            generator.text(
              shopInfoLine,
              styles: _labelTextStyle(shopInfoScale, secondary: true),
            ),
          );
        }
      }

      // 9. CHỮ TÙY BIẾN TỪ CẤU HÌNH (Design View)
      if (customText.isNotEmpty) {
        final footerLine = _labelSingleLine(customText, fontScale);
        bytes.addAll(
          generator.text(
            footerLine,
            styles: _labelTextStyle(fontScale, secondary: true),
          ),
        );
      }

      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());
      return _sendToPrinter(
        bytes,
        printerType: printerType,
        bluetoothPrinter: customMac != null ? {'macAddress': customMac} : null,
        wifiIp: wifiIp,
      );
    } catch (e) {
      print("Lỗi in tem sản phẩm: $e");
      return false;
    }
  }

  /// In QR/Barcode IMEI hàng loạt (Bluetooth/WiFi)
  static Future<bool> printImeiQrBatch(
    List<Product> items, {
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
    bool showName = true,
    bool showDetail = true,
    bool showImei = true,
    int paddingLines = 1,
    String qrSize = 'medium',
    int columns = 1,
    String codeType = 'qr',
    String defaultProductName = 'Sản phẩm',
    String imeiPrefix = 'IMEI',
    String imeiLabel = 'IMEI',
    bool preferRasterForBluetooth = true,
  }) async {
    if (items.isEmpty) return false;

    final prefs = await SharedPreferences.getInstance();
    final paperSizeStr = prefs.getString('label_paper_size') ?? '80';
    PaperSize paperSize;
    switch (paperSizeStr) {
      case '50':
        paperSize = PaperSize.mm58;
        break;
      case '58':
        paperSize = PaperSize.mm58;
        break;
      case '72':
        paperSize = PaperSize.mm72;
        break;
      default:
        paperSize = PaperSize.mm80;
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    final List<int> bytes = [];
    bytes.addAll(generator.reset());

    final forceRasterQr = preferRasterForBluetooth &&
        await _shouldForceRasterQr(
          printerType: printerType,
          bluetoothPrinter: bluetoothPrinter,
        );

    QRSize qrSizeEnum;
    switch (qrSize) {
      case 'xsmall':
        qrSizeEnum = QRSize.size2;
        break;
      case 'small':
        qrSizeEnum = QRSize.size3;
        break;
      case 'large':
        qrSizeEnum = QRSize.size6;
        break;
      default:
        qrSizeEnum = QRSize.size4;
    }

    int printed = 0;
    for (final p in items) {
      final imei = p.imei?.trim();
      if (imei == null || imei.isEmpty) continue;
      printed++;

      final name = p.name.isNotEmpty ? p.name : defaultProductName;
      if (showName) {
        bytes.addAll(
          generator.text(
            _removeDiacritics(name),
            styles: const PosStyles(bold: true),
          ),
        );
      }

      if (showDetail) {
        final detailParts = <String>[
          if ((p.model ?? '').trim().isNotEmpty) p.model!.trim(),
          if ((p.capacity ?? '').trim().isNotEmpty) p.capacity!.trim(),
          if ((p.color ?? '').trim().isNotEmpty) p.color!.trim(),
        ].join(' | ');
        if (detailParts.isNotEmpty) {
          bytes.addAll(generator.text(_removeDiacritics(detailParts)));
        }
      }

      if (showImei) {
        bytes.addAll(
          generator.text(_removeDiacritics('$imeiLabel: $imei')),
        );
      }

      if (codeType == 'barcode') {
        try {
          bytes.addAll(
            generator.barcode(
              Barcode.code128(imei.codeUnits),
              align: PosAlign.center,
            ),
          );
        } catch (_) {
          bytes.addAll(
            generator.text(
              _removeDiacritics(imei),
              styles: const PosStyles(align: PosAlign.center, bold: true),
            ),
          );
        }
      } else {
        final qrContent = imeiPrefix.trim().isNotEmpty
            ? '${imeiPrefix.trim()}$imei'
            : imei;
        _addQrCode(
          generator: generator,
          bytes: bytes,
          data: qrContent,
          size: qrSizeEnum,
          forceRaster: forceRasterQr,
        );
      }

      if (paddingLines > 0) {
        bytes.addAll(generator.feed(paddingLines));
      }

      if (columns > 1) {
        bytes.addAll(generator.feed(1));
      }
    }

    if (printed == 0) return false;
    bytes.addAll(generator.cut());
    return _sendToPrinter(
      bytes,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
  }

  static Future<bool> printRepairReceiptLegacy(
    Map<String, dynamic> data,
    PaperSize paper, {
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());

    // Header thông tin shop
    bytes.addAll(
      generator.text(
        _removeDiacritics(data['shopName']?.toString() ?? 'SHOP NEW'),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(
      generator.text(
        _removeDiacritics(
          data['shopAddr']?.toString() ?? 'Chuyen Smartphone & Laptop',
        ),
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(
      generator.text(
        "Hotline: ${data['shopPhone']?.toString() ?? '0123.456.789'}",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(generator.hr());

    // Tiêu đề phiếu tiếp nhận
    bytes.addAll(
      generator.text(
        'PHIEU TIEP NHAN SUA CHUA',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(
      generator.text(
        "Ma phieu: ${data['receiptCode']?.toString() ?? data['docId']?.toString() ?? 'N/A'}",
        styles: const PosStyles(align: PosAlign.center),
      ),
    );

    // Xử lý ngày nhận an toàn
    String receivedDateStr = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(DateTime.now());
    try {
      final receivedDate = data['receivedDate'];
      if (receivedDate != null && receivedDate.toString().isNotEmpty) {
        receivedDateStr = receivedDate.toString();
      }
    } catch (e) {
      // Giữ giá trị mặc định
    }
    bytes.addAll(
      generator.text(
        "Ngay nhan: $receivedDateStr",
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(generator.feed(1));

    // Thông tin khách hàng
    bytes.addAll(
      generator.text(
        _removeDiacritics(
          "KHACH HANG: ${data['customerName']?.toString() ?? 'N/A'}",
        ),
        styles: const PosStyles(bold: true),
      ),
    );
    if (data['customerPhone'] != null &&
        data['customerPhone'].toString().isNotEmpty) {
      bytes.addAll(generator.text("SDT: ${data['customerPhone']}"));
    }
    if (data['customerAddress'] != null &&
        data['customerAddress'].toString().isNotEmpty) {
      bytes.addAll(
        generator.text(
          _removeDiacritics("Dia chi: ${data['customerAddress']}"),
        ),
      );
    }
    bytes.addAll(generator.feed(1));

    // Thông tin thiết bị
    bytes.addAll(
      generator.text(
        _removeDiacritics(
          "THIET BI: ${data['deviceModel']?.toString() ?? 'N/A'}",
        ),
        styles: const PosStyles(bold: true),
      ),
    );
    bytes.addAll(
      generator.text(
        _removeDiacritics("TINH TRANG: ${data['issue']?.toString() ?? 'N/A'}"),
      ),
    );
    if (data['accessories'] != null &&
        data['accessories'].toString().isNotEmpty) {
      bytes.addAll(
        generator.text(_removeDiacritics("PHU KIEN: ${data['accessories']}")),
      );
    }
    bytes.addAll(generator.feed(1));

    // Giá dự kiến
    if (data['estimatedCost'] != null) {
      final costValue = data['estimatedCost'] is num
          ? data['estimatedCost'].toInt()
          : int.tryParse(data['estimatedCost'].toString()) ?? 0;
      if (costValue > 0) {
        final costStr = MoneyUtils.formatVND(costValue);
        bytes.addAll(
          generator.text(
            "GIA DU KIEN: $costStr VND",
            styles: const PosStyles(bold: true, height: PosTextSize.size2),
          ),
        );
        bytes.addAll(generator.feed(1));
      }
    }

    // QR code để tra cứu
    bytes.addAll(
      generator.text(
        _removeDiacritics("Quet ma de tra cuu phieu sua:"),
        styles: const PosStyles(
          align: PosAlign.center,
          fontType: PosFontType.fontB,
        ),
      ),
    );
    bytes.addAll(
      generator.qrcode(
        "repair_receipt:${data['docId']?.toString() ?? data['receiptCode']?.toString() ?? 'N/A'}",
      ),
    );
    bytes.addAll(generator.feed(1));

    // Lưu ý
    bytes.addAll(
      generator.text(
        _removeDiacritics("- Quy khach vui long giu phieu de nhan may."),
        styles: const PosStyles(fontType: PosFontType.fontB),
      ),
    );
    bytes.addAll(
      generator.text(
        _removeDiacritics("- Thoi gian sua chua khoang 3-7 ngay."),
        styles: const PosStyles(fontType: PosFontType.fontB),
      ),
    );
    bytes.addAll(
      generator.text(
        _removeDiacritics("- Shop se lien he khi co thong tin."),
        styles: const PosStyles(fontType: PosFontType.fontB),
      ),
    );
    bytes.addAll(generator.feed(1));

    // Chữ ký
    bytes.addAll(
      generator.row([
        PosColumn(
          text: 'Khach hang',
          width: 6,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
        PosColumn(
          text: 'Nhan vien',
          width: 6,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      ]),
    );
    bytes.addAll(generator.feed(3));

    bytes.addAll(
      generator.text(
        'CAM ON QUY KHACH!',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return _sendToPrinter(
      bytes,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
  }

  static Future<bool> printSaleReceipt(
    Map<String, dynamic> saleData,
    PaperSize paper, {
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final policies = await _loadReceiptPolicies();
    final useTemplate = prefs.getBool('sale_invoice_use_template') ?? false;
    final templateHeader = prefs.getString('sale_invoice_header') ?? '';
    final templateBody = prefs.getString('sale_invoice_body') ?? '';
    final templateFooter = prefs.getString('sale_invoice_footer') ?? '';
    final hasTemplate =
        templateHeader.trim().isNotEmpty ||
        templateBody.trim().isNotEmpty ||
        templateFooter.trim().isNotEmpty;

    if (useTemplate && hasTemplate) {
      final soldAtRaw = saleData['soldAt'];
      int soldAt = 0;
      if (soldAtRaw != null) {
        soldAt = soldAtRaw is int
            ? soldAtRaw
            : int.tryParse(soldAtRaw.toString()) ?? 0;
      }
      final soldAtDate = soldAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(soldAt)
          : DateTime.now();

      final productNames = saleData['productNames'];
      final productImeis = saleData['productImeis'];
      final names = productNames is List
          ? productNames.map((e) => e?.toString() ?? 'N/A').toList()
          : <String>[];
      final imeis = productImeis is List
          ? productImeis.map((e) => e?.toString() ?? '').toList()
          : <String>[];

      final totalPrice = saleData['totalPrice'];
      final priceValue = totalPrice is num
          ? totalPrice.toInt()
          : int.tryParse(totalPrice?.toString() ?? '0') ?? 0;

      final data = <String, String>{
        'shopName': saleData['shopName']?.toString() ?? 'SHOP NEW',
        'shopAddr': saleData['shopAddr']?.toString() ?? '',
        'shopPhone': saleData['shopPhone']?.toString() ?? '',
        'code': saleData['firestoreId']?.toString() ?? 'N/A',
        'date': DateFormat('dd/MM/yyyy').format(soldAtDate),
        'time': DateFormat('HH:mm').format(soldAtDate),
        'customerName': saleData['customerName']?.toString() ?? 'Khach le',
        'customerPhone': saleData['customerPhone']?.toString() ?? '',
        'customerAddress': saleData['customerAddress']?.toString() ?? '',
        'products': ProductConstants.cleanCompositeProductNames(
          names.join(', '),
        ),
        'imeis': imeis.where((e) => e.trim().isNotEmpty).join(', '),
        'warranty': saleData['warranty']?.toString() ?? '',
        'sellerName': saleData['sellerName']?.toString() ?? '',
        'total': MoneyUtils.formatVND(priceValue),
        'paymentMethod': saleData['paymentMethod']?.toString() ?? '',
        'discount': MoneyUtils.formatVND(
          saleData['discount'] is num
              ? (saleData['discount'] as num).toInt()
              : int.tryParse(saleData['discount']?.toString() ?? '0') ?? 0,
        ),
        'finalTotal': MoneyUtils.formatVND(
          saleData['finalTotal'] is num
              ? (saleData['finalTotal'] as num).toInt()
              : int.tryParse(saleData['finalTotal']?.toString() ?? '0') ??
                  priceValue,
        ),
        'downPayment': MoneyUtils.formatVND(
          saleData['downPayment'] is num
              ? (saleData['downPayment'] as num).toInt()
              : int.tryParse(saleData['downPayment']?.toString() ?? '0') ?? 0,
        ),
        'downPaymentMethod': saleData['downPaymentMethod']?.toString() ?? '',
        'loanAmount': MoneyUtils.formatVND(
          saleData['loanAmount'] is num
              ? (saleData['loanAmount'] as num).toInt()
              : int.tryParse(saleData['loanAmount']?.toString() ?? '0') ?? 0,
        ),
        'loanAmount2': MoneyUtils.formatVND(
          saleData['loanAmount2'] is num
              ? (saleData['loanAmount2'] as num).toInt()
              : int.tryParse(saleData['loanAmount2']?.toString() ?? '0') ?? 0,
        ),
        'installmentTerm': saleData['installmentTerm']?.toString() ?? '',
        'bankName': saleData['bankName']?.toString() ?? '',
        'bankName2': saleData['bankName2']?.toString() ?? '',
        'remainingDebt': MoneyUtils.formatVND(
          saleData['remainingDebt'] is num
              ? (saleData['remainingDebt'] as num).toInt()
              : int.tryParse(saleData['remainingDebt']?.toString() ?? '0') ?? 0,
        ),
        'qrData': 'sale_check:${saleData['firestoreId']?.toString() ?? 'N/A'}',
      };

      final templateText = [
        templateHeader,
        templateBody,
        templateFooter,
      ].where((s) => s.trim().isNotEmpty).join('\n');

      final text = _applyTemplate(templateText, data);
      final ok = await _printTextReceipt(
        text,
        paper: paper,
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
      );
      if (ok) return true;
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());

    // Header thông tin shop
    bytes.addAll(
      generator.text(
        _removeDiacritics(saleData['shopName']?.toString() ?? 'SHOP NEW'),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(
      generator.text(
        _removeDiacritics(
          saleData['shopAddr']?.toString() ?? 'Chuyen Smartphone & Laptop',
        ),
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(
      generator.text(
        "Hotline: ${saleData['shopPhone']?.toString() ?? '0123.456.789'}",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(generator.hr());

    // Tiêu đề hóa đơn
    bytes.addAll(
      generator.text(
        'HOA DON BAN HANG',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
        ),
      ),
    );
    bytes.addAll(
      generator.text(
        "Ma HD: ${saleData['firestoreId']?.toString() ?? 'N/A'}",
        styles: const PosStyles(align: PosAlign.center),
      ),
    );

    // Xử lý ngày bán an toàn
    String soldDateStr = 'N/A';
    try {
      final soldAt = saleData['soldAt'];
      if (soldAt != null) {
        final timestamp = soldAt is int
            ? soldAt
            : int.tryParse(soldAt.toString()) ?? 0;
        if (timestamp > 0) {
          soldDateStr = DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(DateTime.fromMillisecondsSinceEpoch(timestamp));
        }
      }
    } catch (e) {
      soldDateStr = 'N/A';
    }
    bytes.addAll(
      generator.text(
        "Ngay ban: $soldDateStr",
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    bytes.addAll(generator.feed(1));

    // Thông tin khách hàng
    bytes.addAll(
      generator.text(
        _removeDiacritics(
          "KHACH HANG: ${saleData['customerName']?.toString() ?? 'Khach le'}",
        ),
        styles: const PosStyles(bold: true),
      ),
    );
    if (saleData['customerPhone'] != null &&
        saleData['customerPhone'].toString().isNotEmpty) {
      bytes.addAll(generator.text("SDT: ${saleData['customerPhone']}"));
    }
    if (saleData['customerAddress'] != null &&
        saleData['customerAddress'].toString().isNotEmpty) {
      bytes.addAll(
        generator.text(
          _removeDiacritics("Dia chi: ${saleData['customerAddress']}"),
        ),
      );
    }
    final pricingTierLabel = saleData['pricingTierLabel']?.toString() ?? '';
    if (pricingTierLabel.trim().isNotEmpty) {
      bytes.addAll(
        generator.text(
          _removeDiacritics('Nhom gia: $pricingTierLabel'),
          styles: const PosStyles(bold: true),
        ),
      );
    }
    bytes.addAll(generator.feed(1));

    // Thông tin sản phẩm
    bytes.addAll(
      generator.text('SAN PHAM:', styles: const PosStyles(bold: true)),
    );
    final productNames = saleData['productNames'];
    final productImeis = saleData['productImeis'];

    List<String> names = [];
    List<String> imeis = [];

    if (productNames is List) {
      names = productNames.map((e) => e?.toString() ?? 'N/A').toList();
      } else if (productNames is String) {
        names = productNames
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    }
    if (productImeis is List) {
      imeis = productImeis.map((e) => e?.toString() ?? '').toList();
      } else if (productImeis is String) {
        imeis = productImeis
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
    }

    for (int i = 0; i < names.length; i++) {
      final productName = ProductConstants.cleanProductNameWithSuffix(names[i]);
      final imei = i < imeis.length ? imeis[i] : '';

      bytes.addAll(
        generator.text(
          _removeDiacritics("- $productName"),
          styles: const PosStyles(fontType: PosFontType.fontB),
        ),
      );
      if (imei.isNotEmpty) {
        bytes.addAll(
          generator.text(
            "  IMEI: $imei",
            styles: const PosStyles(fontType: PosFontType.fontB),
          ),
        );
      }
    }
    bytes.addAll(generator.feed(1));

    // Bảo hành
    if (saleData['warranty'] != null) {
      bytes.addAll(
        generator.text(
          _removeDiacritics("BAO HANH: ${saleData['warranty']}"),
          styles: const PosStyles(bold: true),
        ),
      );
      bytes.addAll(generator.feed(1));
    }

    // Giảm giá (nếu có)
    final discountRaw = saleData['discount'];
    final discountValue = discountRaw is num
        ? discountRaw.toInt()
        : int.tryParse(discountRaw?.toString() ?? '0') ?? 0;
    if (discountValue > 0) {
      bytes.addAll(
        generator.text(
          "GIAM GIA: -${MoneyUtils.formatVND(discountValue)} VND",
          styles: const PosStyles(
            align: PosAlign.center,
            fontType: PosFontType.fontB,
          ),
        ),
      );
      bytes.addAll(generator.feed(1));
    }

    // Tổng tiền (sau giảm giá)
    final finalTotal = saleData['finalTotal'] ?? saleData['totalPrice'];
    final priceValue = finalTotal is num
        ? finalTotal.toInt()
        : int.tryParse(finalTotal?.toString() ?? '0') ?? 0;
    final priceStr = MoneyUtils.formatVND(priceValue);
    bytes.addAll(
      generator.text(
        "TONG TIEN: $priceStr VND",
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          align: PosAlign.center,
        ),
      ),
    );
    bytes.addAll(generator.feed(1));

    // Nhân viên bán hàng
    if (saleData['sellerName'] != null) {
      bytes.addAll(
        generator.text(
          _removeDiacritics("NV Ban hang: ${saleData['sellerName']}"),
          styles: const PosStyles(align: PosAlign.center),
        ),
      );
    }
    bytes.addAll(generator.feed(1));

    // QR code để tra cứu
    bytes.addAll(
      generator.text(
        _removeDiacritics("Quet ma de tra cuu hoa don:"),
        styles: const PosStyles(
          align: PosAlign.center,
          fontType: PosFontType.fontB,
        ),
      ),
    );
    bytes.addAll(
      generator.qrcode(
        "sale_check:${saleData['firestoreId']?.toString() ?? 'N/A'}",
      ),
    );
    bytes.addAll(generator.feed(1));

    // Lưu ý + chính sách
    bytes.addAll(
      generator.text(
        _removeDiacritics("- Cam on quy khach da tin dung shop."),
        styles: const PosStyles(fontType: PosFontType.fontB),
      ),
    );
    final warrantyPolicy = policies['warranty'] ?? '';
    final returnPolicy = policies['return'] ?? '';
    if (warrantyPolicy.isNotEmpty) {
      bytes.addAll(
        generator.text(
          _removeDiacritics("- BAO HANH: $warrantyPolicy"),
          styles: const PosStyles(fontType: PosFontType.fontB),
        ),
      );
    }
    if (returnPolicy.isNotEmpty) {
      bytes.addAll(
        generator.text(
          _removeDiacritics("- DOI TRA: $returnPolicy"),
          styles: const PosStyles(fontType: PosFontType.fontB),
        ),
      );
    } else {
      bytes.addAll(
        generator.text(
          _removeDiacritics("- Hang da ban khong duoc doi tra."),
          styles: const PosStyles(fontType: PosFontType.fontB),
        ),
      );
    }
    bytes.addAll(generator.feed(1));

    // Chữ ký
    bytes.addAll(
      generator.row([
        PosColumn(
          text: 'Khach hang',
          width: 6,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
        PosColumn(
          text: 'Nhan vien',
          width: 6,
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      ]),
    );
    bytes.addAll(generator.feed(3));

    bytes.addAll(
      generator.text(
        'CAM ON QUY KHACH!',
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ),
    );
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return _sendToPrinter(
      bytes,
      printerType: printerType,
      bluetoothPrinter: bluetoothPrinter,
      wifiIp: wifiIp,
    );
  }

  static Future<bool> printPhoneLabelToWifi(
    Map<String, dynamic> labelData,
    String ipAddress,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final paperSizeStr = prefs.getString('label_paper_size') ?? '80';
    PaperSize paperSize;
    switch (paperSizeStr) {
      case '50':
        paperSize = PaperSize.mm58;
        break;
      case '58':
        paperSize = PaperSize.mm58;
        break;
      case '72':
        paperSize = PaperSize.mm72;
        break;
      default:
        paperSize = PaperSize.mm80;
    }

    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());
    bytes.addAll(
      generator.text(
        _removeDiacritics(labelData['name'] ?? 'TEM MAY'),
        styles: const PosStyles(bold: true),
      ),
    );
    bytes.addAll(generator.cut());
    return _sendToPrinter(bytes, wifiIp: ipAddress);
  }

  static Future<bool> printRepairReceipt(
    Map<String, dynamic> receiptData,
    PaperSize paperSize, {
    PrinterType? printerType,
    BluetoothPrinterConfig? bluetoothPrinter,
    String? wifiIp,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final policies = await _loadReceiptPolicies();
    final fontScale = prefs.getDouble('label_font_scale') ?? 1.0;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());

    PosTextSize headerSize = fontScale >= 2.0
        ? PosTextSize.size2
        : PosTextSize.size1;

    // Header
    if (prefs.getBool('receipt_show_logo') ?? true) {
      bytes.addAll(
        generator.text(
          _removeDiacritics(receiptData['shopName'] ?? 'SHOP NEW'),
          styles: PosStyles(
            align: PosAlign.center,
            bold: true,
            height: headerSize,
          ),
        ),
      );
    }
    bytes.addAll(
      generator.text(
        _removeDiacritics(receiptData['shopAddress'] ?? ''),
        styles: const PosStyles(align: PosAlign.center),
      ),
    );
    if (prefs.getBool('receipt_show_phone') ?? true) {
      bytes.addAll(
        generator.text(
          "HOTLINE: ${receiptData['shopPhone'] ?? ''}",
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ),
      );
    }
    bytes.addAll(generator.hr());
    bytes.addAll(
      generator.text(
        'PHIEU SUA CHUA',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: headerSize,
        ),
      ),
    );
    bytes.addAll(generator.feed(1));

    // Customer info
    bytes.addAll(
      generator.text(
        _removeDiacritics("KHACH: ${receiptData['customerName'] ?? ''}"),
      ),
    );
    bytes.addAll(generator.text("SDT: ${receiptData['phone'] ?? ''}"));
    bytes.addAll(
      generator.text(_removeDiacritics("MAY: ${receiptData['model'] ?? ''}")),
    );
    bytes.addAll(
      generator.text(_removeDiacritics("LOI: ${receiptData['issue'] ?? ''}")),
    );
    bytes.addAll(
      generator.text(
        "GIA: ${_fmt(receiptData['estimatedCost'] ?? 0)} VND",
        styles: const PosStyles(bold: true),
      ),
    );
    bytes.addAll(
      generator.text(
        "NGAY NHAN: ${receiptData['receivedDate'] ?? ''}",
        styles: const PosStyles(bold: true),
      ),
    );

    if (prefs.getBool('receipt_show_qr') ?? true) {
      bytes.addAll(
        generator.qrcode(
          "repair:${receiptData['repairId'] ?? ''}",
          align: PosAlign.center,
        ),
      );
    }

    // Thêm lời chúc cuối hóa đơn
    final receiptNote = prefs.getString('receipt_note') ?? "Cam on quy khach!";
    if (receiptNote.isNotEmpty) {
      bytes.addAll(
        generator.text(
          _removeDiacritics(receiptNote),
          styles: const PosStyles(
            align: PosAlign.center,
            fontType: PosFontType.fontB,
          ),
        ),
      );
    }

    final warrantyPolicy = policies['warranty'] ?? '';
    final returnPolicy = policies['return'] ?? '';
    if (warrantyPolicy.isNotEmpty) {
      bytes.addAll(
        generator.text(
          _removeDiacritics("BAO HANH: $warrantyPolicy"),
          styles: const PosStyles(fontType: PosFontType.fontB),
        ),
      );
    }
    if (returnPolicy.isNotEmpty) {
      bytes.addAll(
        generator.text(
          _removeDiacritics("DOI TRA: $returnPolicy"),
          styles: const PosStyles(fontType: PosFontType.fontB),
        ),
      );
    }

    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    // Send to specific printer if provided
    if (printerType == PrinterType.bluetooth && bluetoothPrinter != null) {
      final ok = await BluetoothPrinterService.connect(
        bluetoothPrinter.macAddress,
      );
      if (ok) return await BluetoothPrinterService.printBytes(bytes);
    } else if (printerType == PrinterType.wifi && wifiIp != null) {
      try {
        final ok = await WifiPrinterService.instance.connect(
          ip: wifiIp,
          port: 9100,
        );
        if (ok) {
          await WifiPrinterService.instance.printBytes(bytes);
          return true;
        }
      } catch (_) {}
    }

    return _sendToPrinter(bytes);
  }

  static String _fmt(dynamic value) {
    if (value is int) return MoneyUtils.formatVND(value);
    if (value is double) return MoneyUtils.formatVND(value.toInt());
    return value.toString();
  }

  /// In tem sản phẩm nâng cao với LabelPrintData
  /// Luôn ưu tiên đọc cài đặt từ THIẾT KẾ TEM (LabelDesignerView)
  Future<bool> printProductLabelAdvanced(
    dynamic printData, {
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Đọc size giấy từ cài đặt THIẾT KẾ TEM
      final paperSizeStr = prefs.getString('label_paper_size') ?? '80';
      PaperSize paperSize;
      switch (paperSizeStr) {
        case '50':
          paperSize = PaperSize.mm58;
          break;
        case '58':
          paperSize = PaperSize.mm58;
          break;
        case '72':
          paperSize = PaperSize.mm72;
          break;
        default:
          paperSize = PaperSize.mm80;
      }

      final profile = await CapabilityProfile.load();
      final generator = Generator(paperSize, profile);
      List<int> bytes = [];
      bytes.addAll(generator.reset());

      // Kiểm tra loại dữ liệu
      if (printData is Map<String, dynamic>) {
        // Fallback về cách cũ - SỬ DỤNG CÀI ĐẶT TỪ LABEL DESIGNER
        return printProductQRLabel(
          printData,
          printerType: printerType,
          bluetoothPrinter: bluetoothPrinter,
          customMac: bluetoothPrinter is Map
              ? bluetoothPrinter['macAddress']
              : null,
          wifiIp: wifiIp,
        );
      }

      // === ĐỌC CÀI ĐẶT TỪ THIẾT KẾ TEM (LABEL DESIGNER) ===
      final designerConfig = await _loadLabelDesignerConfig();
      final hasDesignerConfig = designerConfig.isNotEmpty;
      final hasVisibleDesignerElements = designerConfig.values.any(
        (e) => e.visible,
      );

      // LabelPrintData từ model mới
      final product = printData.product as Map<String, dynamic>;
      final customLines = printData.additionalLines as List<String>? ?? [];

      // Nếu có cài đặt từ Label Designer, sử dụng nó!
      if (hasDesignerConfig && hasVisibleDesignerElements) {
        return _printLabelWithDesignerConfig(
          generator: generator,
          bytes: bytes,
          product: product,
          designerConfig: designerConfig,
          customLines: customLines,
          printData: printData,
          printerType: printerType,
          bluetoothPrinter: bluetoothPrinter,
          wifiIp: wifiIp,
        );
      }

      // Fallback: Dùng template từ dialog nếu chưa có Label Designer config
      final template = printData.template;
      final fields = template.fields;
      final shopInfo = template.shopInfo;
      final fontScale = prefs.getDouble('label_font_scale') ?? 1.0;

      // === HEADER SHOP ===
      if (shopInfo.showShopName || shopInfo.showHotline) {
        if (shopInfo.showShopName) {
          final shopName = shopInfo.customShopName ?? '';
          if (shopName.isNotEmpty) {
            bytes.addAll(
              generator.text(
                _labelSingleLine(shopName, fontScale),
                styles: _labelTextStyle(fontScale, bold: true, emphasize: true),
              ),
            );
          }
        }
        if (shopInfo.showHotline) {
          final hotline = shopInfo.customHotline ?? '';
          if (hotline.isNotEmpty) {
            bytes.addAll(
              generator.text(
                _labelSingleLine(
                  "Hotline: $hotline",
                  fontScale,
                  uppercaseWhenLarge: false,
                ),
                styles: _labelTextStyle(fontScale, secondary: true),
              ),
            );
          }
        }
        bytes.addAll(generator.hr(ch: '-'));
      }

      // === TÊN SẢN PHẨM ===
      if (fields.showProductName) {
        final rawName = product['name']?.toString() ?? 'N/A';
        final nameLines = _labelLines(
          rawName,
          fontScale,
          baseMaxChars: _maxCharsForLabel(
            template.size,
            emphasize: true,
            fontScale: fontScale,
          ),
        );
        final linesToPrint = nameLines.isNotEmpty
            ? nameLines
            : [_labelSingleLine(rawName, fontScale)];
        for (final line in linesToPrint) {
          bytes.addAll(
            generator.text(
              line,
              styles: _labelTextStyle(fontScale, bold: true, emphasize: true),
            ),
          );
        }
      }

      // === THÔNG SỐ: Dung lượng | Màu | Tình trạng ===
      final specs = <String>[];
      if (fields.showStorage && product['capacity'] != null) {
        specs.add(product['capacity']);
      }
      if (fields.showColor && product['color'] != null) {
        specs.add(product['color']);
      }
      if (fields.showCondition && product['condition'] != null) {
        specs.add(product['condition']);
      }
      if (specs.isNotEmpty) {
        bytes.addAll(
          generator.text(
            _labelSingleLine(specs.join(' | '), fontScale),
            styles: _labelTextStyle(fontScale, bold: true, secondary: true),
          ),
        );
      }

      // === GIÁ KPK / CPK ===
      if (fields.showPriceKPK || fields.showPriceCPK) {
        bytes.addAll(generator.feed(1));

        if (fields.showPriceKPK) {
          final kpk = printData.priceKPK ?? product['price'] ?? 0;
          bytes.addAll(
            generator.text(
              _labelSingleLine(
                fontScale >= 0.95
                    ? "GIA KPK: ${MoneyUtils.formatVND(kpk)}"
                    : "Gia KPK: ${MoneyUtils.formatVND(kpk)}",
                fontScale,
                uppercaseWhenLarge: false,
              ),
              styles: _labelTextStyle(fontScale, bold: true, secondary: true),
            ),
          );
        }

        if (fields.showPriceCPK) {
          final cpk =
              printData.calculatedCPK ?? (product['price'] ?? 0) + 500000;
          bytes.addAll(
            generator.text(
              _labelSingleLine(
                fontScale >= 0.95
                    ? "GIA CPK: ${MoneyUtils.formatVND(cpk)}"
                    : "Gia CPK: ${MoneyUtils.formatVND(cpk)}",
                fontScale,
                uppercaseWhenLarge: false,
              ),
              styles: _labelTextStyle(fontScale, bold: true, secondary: true),
            ),
          );
        }
      }

      // === GIÁ GỐC + % GIẢM (cho tem khuyến mãi) ===
      if (fields.showOriginalPrice &&
          printData.originalPrice != null &&
          printData.originalPrice > 0) {
        bytes.addAll(
          generator.text(
            _labelSingleLine(
              "Gia goc: ${MoneyUtils.formatVND(printData.originalPrice)}",
              fontScale,
              uppercaseWhenLarge: false,
            ),
            styles: _labelTextStyle(fontScale, secondary: true),
          ),
        );
      }
      if (fields.showDiscountPercent &&
          printData.discountPercent != null &&
          printData.discountPercent > 0) {
        bytes.addAll(
          generator.text(
            _labelSingleLine(
              fontScale >= 0.95
                  ? ">>> GIAM ${printData.discountPercent}% <<<"
                  : "Giam ${printData.discountPercent}%",
              fontScale,
              uppercaseWhenLarge: false,
            ),
            styles: _labelTextStyle(fontScale, bold: true, secondary: true),
          ),
        );
      }

      // === BẢO HÀNH ===
      if (fields.showWarranty) {
        final warranty = product['warranty'] ?? '6 thang';
        bytes.addAll(
          generator.text(
            _labelSingleLine(
              "Bao hanh: ${warranty.toString()}",
              fontScale,
              uppercaseWhenLarge: false,
            ),
            styles: _labelTextStyle(fontScale, secondary: true),
          ),
        );
      }

      // === IMEI ===
      if (fields.showImei && product['imei'] != null) {
        bytes.addAll(
          generator.text(
            _labelSingleLine(
              "IMEI: ${product['imei']}",
              fontScale,
              uppercaseWhenLarge: false,
            ),
            styles: _labelTextStyle(fontScale, secondary: true),
          ),
        );
      }

      // === NGÀY BÁN + NGÀY HẾT BH (cho tem bảo hành) ===
      if (fields.showSaleDate && printData.saleDate != null) {
        final dateStr =
            "${printData.saleDate.day}/${printData.saleDate.month}/${printData.saleDate.year}";
        bytes.addAll(
          generator.text(
            _labelSingleLine(
              "Ngay ban: $dateStr",
              fontScale,
              uppercaseWhenLarge: false,
            ),
            styles: _labelTextStyle(fontScale, secondary: true),
          ),
        );
      }
      if (fields.showWarrantyEndDate && printData.warrantyEndDate != null) {
        final endStr =
            "${printData.warrantyEndDate.day}/${printData.warrantyEndDate.month}/${printData.warrantyEndDate.year}";
        bytes.addAll(
          generator.text(
            _labelSingleLine(
              "Het han BH: $endStr",
              fontScale,
              uppercaseWhenLarge: false,
            ),
            styles: _labelTextStyle(fontScale, bold: true, secondary: true),
          ),
        );
      }

      // === QR CODE + MÃ SẢN PHẨM ===
      if (fields.showQrCode) {
        bytes.addAll(generator.feed(1));
        final productId =
            product['id']?.toString() ??
            product['firestoreId']?.toString() ??
            'unknown';
        bytes.addAll(
          generator.qrcode(
            "check_product:$productId",
            size: QRSize.size4,
            align: PosAlign.center,
          ),
        );
      }
      if (fields.showProductCode) {
        final code = product['productCode'] ?? product['id'] ?? 'N/A';
        bytes.addAll(
          generator.text(
            _labelSingleLine("Ma: $code", fontScale, uppercaseWhenLarge: false),
            styles: _labelTextStyle(fontScale, secondary: true),
          ),
        );
      }

      // === NỘI DUNG TÙY BIẾN ===
      if (customLines.isNotEmpty) {
        bytes.addAll(generator.feed(1));
        for (final line in customLines) {
          if (line.trim().isNotEmpty) {
            bytes.addAll(
              generator.text(
                _labelSingleLine(line, fontScale),
                styles: _labelTextStyle(fontScale, secondary: true),
              ),
            );
          }
        }
      }

      // === SLOGAN ===
      if (shopInfo.showSlogan) {
        final slogan = shopInfo.customSlogan ?? '';
        if (slogan.isNotEmpty) {
          bytes.addAll(generator.feed(1));
          bytes.addAll(
            generator.text(
              _labelSingleLine(
                '"$slogan"',
                fontScale,
                uppercaseWhenLarge: false,
              ),
              styles: _labelTextStyle(fontScale, secondary: true),
            ),
          );
        }
      }

      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());

      return _sendToPrinter(
        bytes,
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
      );
    } catch (e) {
      print("Lỗi in tem nâng cao: $e");
      return false;
    }
  }
}
