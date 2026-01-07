import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'bluetooth_printer_service.dart';

class ThermalPrinterService {
  static Future<String?> getPrinterIP() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('thermal_printer_ip');
  }

  static Future<Map<String, dynamic>> getDesignSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'size': prefs.getString('thermal_label_size') ?? '3x4',
      'showColor': prefs.getBool('thermal_show_color') ?? true,
      'showIMEI': prefs.getBool('thermal_show_imei') ?? true,
      'showCondition': prefs.getBool('thermal_show_condition') ?? true,
      'showPrice': prefs.getBool('thermal_show_price') ?? true,
      'showAccessories': prefs.getBool('thermal_show_accessories') ?? true,
      'fontSize': prefs.getString('thermal_font_size') ?? 'medium',
    };
  }

  static Future<bool> printDeviceLabel({
    required String deviceName,
    String? color,
    String? imei,
    String? condition,
    String? price,
    String? accessories,
  }) async {
    final printer = await BluetoothPrinterService.getSavedPrinter();
    if (printer == null) return false;

    final settings = await getDesignSettings();

    // Kết nối máy in
    final connected = await BluetoothPrinterService.connect(printer.macAddress);
    if (!connected) return false;

    const PaperSize paper = PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);

    List<int> bytes = [];

    // In tiêu đề
    bytes += generator.text(deviceName, styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.feed(1);

    // In thông tin theo cài đặt
    if (settings['showColor'] == true && color != null && color.isNotEmpty) {
      bytes += generator.text('Mau: $color');
    }
    if (settings['showIMEI'] == true && imei != null && imei.isNotEmpty) {
      bytes += generator.text('IMEI: $imei');
    }
    if (settings['showCondition'] == true && condition != null && condition.isNotEmpty) {
      bytes += generator.text('Tinh trang: $condition');
    }
    if (settings['showPrice'] == true && price != null && price.isNotEmpty) {
      bytes += generator.text('Gia: $price');
    }
    if (settings['showAccessories'] == true && accessories != null && accessories.isNotEmpty) {
      bytes += generator.text('Phu kien: $accessories');
    }

    bytes += generator.feed(2);
    bytes += generator.cut();

    return await BluetoothPrinterService.printBytes(bytes);
  }

  static Future<bool> printDeviceLabelWifi({
    required String deviceName,
    String? color,
    String? imei,
    String? condition,
    String? price,
    String? accessories,
  }) async {
    final ipAddress = await getPrinterIP();
    if (ipAddress == null || ipAddress.isEmpty) return false;

    final settings = await getDesignSettings();

    const PaperSize paper = PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);

    List<int> bytes = [];

    // In tiêu đề
    bytes += generator.text(deviceName, styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.feed(1);

    // In thông tin theo cài đặt
    if (settings['showColor'] == true && color != null && color.isNotEmpty) {
      bytes += generator.text('Mau: $color');
    }
    if (settings['showIMEI'] == true && imei != null && imei.isNotEmpty) {
      bytes += generator.text('IMEI: $imei');
    }
    if (settings['showCondition'] == true && condition != null && condition.isNotEmpty) {
      bytes += generator.text('Tinh trang: $condition');
    }
    if (settings['showPrice'] == true && price != null && price.isNotEmpty) {
      bytes += generator.text('Gia: $price');
    }
    if (settings['showAccessories'] == true && accessories != null && accessories.isNotEmpty) {
      bytes += generator.text('Phu kien: $accessories');
    }

    bytes += generator.feed(2);
    bytes += generator.cut();

    return await printWifi(bytes, ipAddress);
  }

  static Future<bool> testWifiConnection(String ipAddress) async {
    if (ipAddress.isEmpty) return false;

    try {
      // Test basic connection
      final socket = await Socket.connect(ipAddress, 9100, timeout: const Duration(seconds: 5));
      socket.destroy();

      // If connection successful, try to print test
      final socket2 = await Socket.connect(ipAddress, 9100, timeout: const Duration(seconds: 5));

      const PaperSize paper = PaperSize.mm58;
      final profile = await CapabilityProfile.load();
      final generator = Generator(paper, profile);

      List<int> bytes = [];
      bytes += generator.text('TEST KET NOI WIFI', styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text('IP: $ipAddress', styles: const PosStyles(align: PosAlign.center));
      bytes += generator.feed(2);
      bytes += generator.cut();

      socket2.add(Uint8List.fromList(bytes));
      await socket2.flush();
      await socket2.close();

      return true;
    } catch (e) {
      print('WiFi printer test error: $e');
      return false;
    }
  }

  static Future<bool> testConnection() async {
    final printer = await BluetoothPrinterService.getSavedPrinter();
    if (printer == null) return false;

    final connected = await BluetoothPrinterService.connect(printer.macAddress);
    if (!connected) return false;

    const PaperSize paper = PaperSize.mm58;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);

    List<int> bytes = [];
    bytes += generator.text('TEST KET NOI BLUETOOTH', styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.feed(2);
    bytes += generator.cut();

    return await BluetoothPrinterService.printBytes(bytes);
  }

  static Future<bool> printWifi(List<int> bytes, String ipAddress) async {
    if (ipAddress.isEmpty) return false;

    try {
      final socket = await Socket.connect(ipAddress, 9100, timeout: const Duration(seconds: 5));
      socket.add(Uint8List.fromList(bytes));
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      print('WiFi printer error: $e');
      return false;
    }
  }
}
