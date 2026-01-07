import 'dart:convert';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothPrinterConfig {
  final String name;
  final String macAddress;

  BluetoothPrinterConfig({required this.name, required this.macAddress});

  Map<String, dynamic> toJson() => {'name': name, 'macAddress': macAddress};

  factory BluetoothPrinterConfig.fromJson(Map<String, dynamic> json) =>
      BluetoothPrinterConfig(
        name: json['name'] as String,
        macAddress: json['macAddress'] as String,
      );
}

class BluetoothPrinterService {
  static const String _savedPrinterKey = 'saved_printer';

  // Helper function for logging
  static void _addLog(String message) {
    print('BluetoothPrinterService: $message');
  }

  static Future<BluetoothPrinterConfig?> getSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_savedPrinterKey);
    if (jsonString != null) {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return BluetoothPrinterConfig.fromJson(json);
    }
    return null;
  }

  static Future<void> savePrinter(BluetoothPrinterConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(config.toJson());
    await prefs.setString(_savedPrinterKey, jsonString);
  }

  static Future<void> clearSavedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_savedPrinterKey);
  }

  static Future<bool> isPermissionBluetoothGranted() async {
    return await PrintBluetoothThermal.isPermissionBluetoothGranted;
  }

  static Future<Map<String, dynamic>>
  requestBluetoothPermissionsOptimized() async {
    try {
      Map<String, dynamic> results = {
        'success': true,
        'permissions': <String, bool>{},
        'errors': <String>[],  
        'warnings': <String>[],
      };

      final locationStatus = await Permission.location.request();
      results['permissions']['location'] = locationStatus.isGranted;

      final bluetoothConnectStatus = await Permission.bluetoothConnect.request();
      results['permissions']['bluetoothConnect'] = bluetoothConnectStatus.isGranted;

      final bluetoothScanStatus = await Permission.bluetoothScan.request();
      results['permissions']['bluetoothScan'] = bluetoothScanStatus.isGranted;

      final bluetoothStatus = await Permission.bluetooth.request();
      results['permissions']['bluetooth'] = bluetoothStatus.isGranted;

      // Thử yêu cầu quyền advertise (cho Android 12+)
      try {
        final bluetoothAdvertiseStatus = await Permission.bluetoothAdvertise.request();
        results['permissions']['bluetoothAdvertise'] = bluetoothAdvertiseStatus.isGranted;
      } catch (e) {
        results['warnings'].add('Không thể yêu cầu quyền bluetoothAdvertise: $e');
      }

      // Kiểm tra quyền quan trọng
      final hasEssentialPermissions = bluetoothConnectStatus.isGranted && bluetoothScanStatus.isGranted;
      
      if (!hasEssentialPermissions) {
        results['errors'].add('Thiếu quyền bluetoothConnect hoặc bluetoothScan');
      }

      results['success'] = hasEssentialPermissions;
      return results;
    } catch (e) {
      return {'success': false, 'errors': [e.toString()]};
    }
  }

  static Future<bool> requestBluetoothPermissions() async {
    final result = await requestBluetoothPermissionsOptimized();
    return result['success'] as bool;
  }

  static Future<bool> isBluetoothEnabled() async {
    return await PrintBluetoothThermal.bluetoothEnabled;
  }

  static Future<bool> isConnected() async {
    return await PrintBluetoothThermal.connectionStatus;
  }

  static Future<List<BluetoothInfo>> getPairedPrinters() async {
    return await PrintBluetoothThermal.pairedBluetooths;
  }

  static Future<bool> connect(String macAddress) async {
    return await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
  }

  static Future<Map<String, dynamic>> connectWithStatus(String macAddress) async {
    try {
      final success = await connect(macAddress);
      return {
        'success': success,
        'error': success ? null : 'Không thể kết nối với máy in',
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  static Future<bool> printBytes(List<int> bytes) async {
    return await PrintBluetoothThermal.writeBytes(bytes);
  }

  // IN TEM ĐIỆN THOẠI VỚI CẤU HÌNH SIZE CHỮ TỐI ƯU
  static Future<bool> printPhoneLabel(Map<String, dynamic> labelData, [String? macAddress]) async {
    try {
      bool connected = await ensureConnection();
      if (!connected && macAddress != null) {
        connected = await connect(macAddress);
      }
      if (!connected) return false;

      final prefs = await SharedPreferences.getInstance();
      
      // Lấy cấu hình từ Design View
      final showName = prefs.getBool('label_show_name') ?? true;
      final showDetail = prefs.getBool('label_show_detail') ?? true;
      final showKPK = prefs.getBool('label_show_price_kpk') ?? true;
      final showCPK = prefs.getBool('label_show_price_cpk') ?? true;
      final showIMEI = prefs.getBool('label_show_imei') ?? true;
      final showQR = prefs.getBool('label_show_qr') ?? true;
      final customText = prefs.getString('label_custom_text') ?? "";

      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];
      bytes.addAll(generator.reset());

      // 1. TÊN SẢN PHẨM (TO - SIZE 2)
      if (showName) {
        bytes.addAll(generator.text(
          (labelData['name'] ?? 'N/A').toString().toUpperCase(),
          styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2),
        ));
      }

      // 2. CHI TIẾT (VỪA - SIZE 1)
      if (showDetail) {
        final detail = "${labelData['capacity'] ?? ''} ${labelData['color'] ?? ''} ${labelData['condition'] ?? ''}".trim();
        if (detail.isNotEmpty) {
          bytes.addAll(generator.text(detail.toUpperCase(), styles: const PosStyles(align: PosAlign.center, bold: true)));
        }
      }

      // 3. GIÁ BÁN
      bytes.addAll(generator.text(
        "GIA BAN: ${labelData['price'] ?? '0'}",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ));

      // 5. IMEI (VỪA)
      if (showIMEI) {
        bytes.addAll(generator.text(
          "IMEI: ${labelData['imei'] ?? 'N/A'}",
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ));
      }

      // 6. QR CODE (NẾU CÓ)
      if (showQR) {
        bytes.addAll(generator.feed(1));
        // Generate QR in unified format: type=PHONE&imei=...&code=...
        final qrData = 'type=PHONE&imei=${labelData['imei'] ?? 'N/A'}&code=${labelData['code'] ?? labelData['name'] ?? 'N/A'}';
        bytes.addAll(generator.qrcode(qrData, size: QRSize.Size4));
      }

      // 7. CHỮ TÙY BIẾN
      if (customText.isNotEmpty) {
        bytes.addAll(generator.text(customText.toUpperCase(), styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)));
      }

      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());
      return await printBytes(bytes);
    } catch (e) {
      print("Lỗi in tem: $e");
      return false;
    }
  }

  static Future<bool> ensureConnection() async {
    final connected = await isConnected();
    if (!connected) {
      final savedPrinter = await getSavedPrinter();
      if (savedPrinter != null) {
        return await connect(savedPrinter.macAddress);
      }
    }
    return connected;
  }
}
