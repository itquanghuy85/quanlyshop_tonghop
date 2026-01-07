import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/utils/money_utils.dart';
import 'bluetooth_printer_service.dart';
import 'wifi_printer_service.dart';
import '../models/repair_model.dart';

import '../models/printer_types.dart';

class UnifiedPrinterService {
  static String _removeDiacritics(String str) {
    const vietnamese = 'aAeEoOuUiIdDyY';
    final vietnameseRegex = [
      RegExp(r'à|á|ạ|ả|ã|â|ầ|ấ|ậ|ẩ|ẫ|ă|ằ|ắ|ặ|ẳ|ẵ'), RegExp(r'À|Á|Ạ|Ả|Ã|Â|Ầ|Ấ|Ậ|Ẩ|Ẫ|Ă|Ằ|Ắ|Ặ|Ẳ|Ẵ'),
      RegExp(r'è|é|ẹ|ẻ|ẽ|ê|ề|ế|ệ|ể|ễ'), RegExp(r'È|É|Ạ|Ẻ|Ẽ|Ê|Ề|Ế|Ệ|Ể|Ễ'),
      RegExp(r'ò|ó|ọ|ỏ|õ|ô|ồ|ố|ộ|ổ|ỗ|ơ|ờ|ớ|ợ|ở|ỡ'), RegExp(r'Ò|Ó|Ọ|Ỏ|Õ|Ô|Ồ|Ố|Ộ|Ổ|Ỗ|Ơ|Ờ|Ớ|Ợ|Ở|Ỡ'),
      RegExp(r'ù|ú|ụ|ủ|ũ|ư|ừ|ứ|ự|ử|ữ'), RegExp(r'Ù|Ú|Ụ|Ủ|Ũ|Ư|Ừ|Ứ|Ự|Ử|Ữ'),
      RegExp(r'ì|í|ị|ỉ|ĩ'), RegExp(r'Ì|Í|Ị|Ỉ|Ĩ'),
      RegExp(r'đ'), RegExp(r'Đ'), RegExp(r'ỳ|ý|ỵ|ỷ|ỹ'), RegExp(r'Ỳ|Ý|Ỵ|Ỷ|Ỹ'),
    ];
    for (var i = 0; i < vietnameseRegex.length; i++) {
      str = str.replaceAll(vietnameseRegex[i], vietnamese[i]);
    }
    return str;
  }

  static Future<bool> _sendToPrinter(
    List<int> bytes, {
    PrinterType? printerType, 
    String? wifiIp,
    dynamic bluetoothPrinter,
  }) async {
    try {
      if (printerType == PrinterType.wifi || (printerType == null && wifiIp != null)) {
        await WifiPrinterService.instance.connect(ip: wifiIp ?? "192.168.1.100", port: 9100);
        await WifiPrinterService.instance.printBytes(bytes);
        return true;
      }
      if (bluetoothPrinter != null) {
        final mac = bluetoothPrinter is Map ? bluetoothPrinter['macAddress'] : bluetoothPrinter.macAddress;
        final ok = await BluetoothPrinterService.connect(mac);
        if (ok) return await BluetoothPrinterService.printBytes(bytes);
      }
      final hasBt = await BluetoothPrinterService.ensureConnection();
      if (hasBt) return await BluetoothPrinterService.printBytes(bytes);
      
      // Nếu không có Bluetooth, thử WiFi với IP từ settings
      final prefs = await SharedPreferences.getInstance();
      final savedIp = prefs.getString('printer_ip') ?? prefs.getString('thermal_printer_ip');
      if (savedIp != null && savedIp.isNotEmpty) {
        await WifiPrinterService.instance.connect(ip: savedIp, port: 9100);
        await WifiPrinterService.instance.printBytes(bytes);
        return true;
      }
      
      return false;
    } catch (_) { return false; }
  }

  // --- PHIẾU TIẾP NHẬN SỬA CHỮA CHUYÊN NGHIỆP ---
  static Future<bool> printRepairReceiptFromRepair(
    Repair repair, 
    Map<String, dynamic> shopInfo, {
    PrinterType? printerType,
    dynamic bluetoothPrinter,
    String? wifiIp,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());

    bytes.addAll(generator.text(_removeDiacritics(shopInfo['shopName'] ?? 'SHOP NEW'), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(generator.text(_removeDiacritics(shopInfo['shopAddr'] ?? 'Chuyen Smartphone & Laptop'), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text("Hotline: ${shopInfo['shopPhone'] ?? '0123.456.789'}", styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.hr());

    bytes.addAll(generator.text('PHIEU TIEP NHAN MAY', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(generator.text("Ma don: ${repair.firestoreId ?? repair.createdAt}", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text("Ngay nhan: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(repair.createdAt))}", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(1));

    bytes.addAll(generator.text(_removeDiacritics("KHACH HANG: ${repair.customerName}"), styles: const PosStyles(bold: true)));
    bytes.addAll(generator.text("SDT: ${repair.phone}"));
    bytes.addAll(generator.feed(1));

    bytes.addAll(generator.text(_removeDiacritics("MAY: ${repair.model}"), styles: const PosStyles(bold: true)));
    if (repair.imei != null && repair.imei!.isNotEmpty) bytes.addAll(generator.text("IMEI/SN: ${repair.imei}"));
    bytes.addAll(generator.text(_removeDiacritics("TINH TRANG: ${repair.issue}")));
    
    String subInfo = "";
    if (repair.color != null) subInfo += "Mau: ${repair.color} | ";
    if (repair.condition != null) subInfo += "Vo: ${repair.condition}";
    if (subInfo.isNotEmpty) bytes.addAll(generator.text(_removeDiacritics(subInfo), styles: const PosStyles(fontType: PosFontType.fontB)));
    
    bytes.addAll(generator.text(_removeDiacritics("PHU KIEN: ${repair.accessories}")));
    bytes.addAll(generator.feed(1));

    final priceStr = MoneyUtils.formatVND(repair.price);
    bytes.addAll(generator.text("GIA DU KIEN: $priceStr VND", styles: const PosStyles(bold: true, height: PosTextSize.size2)));
    bytes.addAll(generator.text(_removeDiacritics("Hinh thuc: ${repair.paymentMethod}")));
    bytes.addAll(generator.feed(1));

    bytes.addAll(generator.text(_removeDiacritics("Quet ma de tra cuu don hang:"), styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)));
    // Đã sửa lỗi: Gỡ bỏ tham số size: QRSize.size4 gây lỗi
    bytes.addAll(generator.qrcode("repair_check:${repair.firestoreId ?? repair.createdAt}"));
    bytes.addAll(generator.feed(1));

    bytes.addAll(generator.text(_removeDiacritics("- Quy khach vui long giu phieu de nhan may."), styles: const PosStyles(fontType: PosFontType.fontB)));
    bytes.addAll(generator.text(_removeDiacritics("- Shop khong chiu trach nhiem ve du lieu trong may."), styles: const PosStyles(fontType: PosFontType.fontB)));
    bytes.addAll(generator.feed(1));
    
    bytes.addAll(generator.row([
      PosColumn(text: 'Khach hang', width: 6, styles: const PosStyles(align: PosAlign.center, bold: true)),
      PosColumn(text: 'Nhan vien', width: 6, styles: const PosStyles(align: PosAlign.center, bold: true)),
    ]));
    bytes.addAll(generator.feed(3));

    bytes.addAll(generator.text('CAM ON QUY KHACH!', styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return _sendToPrinter(bytes, printerType: printerType, bluetoothPrinter: bluetoothPrinter, wifiIp: wifiIp);
  }

  static Future<bool> printProductQRLabel(Map<String, dynamic> product, {String? customMac, PrinterType? printerType, String? wifiIp}) async {
    try {
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      List<int> bytes = [];
      bytes.addAll(generator.reset());

      final prefs = await SharedPreferences.getInstance();

      // Lấy cấu hình từ Design View
      final showName = prefs.getBool('label_show_name') ?? true;
      final showDetail = prefs.getBool('label_show_detail') ?? true;
      final showKPK = prefs.getBool('label_show_price_kpk') ?? true;
      final showCPK = prefs.getBool('label_show_price_cpk') ?? true;
      final showIMEI = prefs.getBool('label_show_imei') ?? true;
      final showQR = prefs.getBool('label_show_qr') ?? true;
      final customText = prefs.getString('label_custom_text') ?? "";
      final fontScale = prefs.getDouble('label_font_scale') ?? 1.0;

      // 1. TÊN SẢN PHẨM (TO - SIZE 2 nếu fontScale >= 2.0, SIZE 1 nếu < 2.0)
      if (showName) {
        final nameStyle = fontScale >= 2.0
            ? const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2, width: PosTextSize.size2)
            : const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size1, width: PosTextSize.size1);
        bytes.addAll(generator.text(
          _removeDiacritics(product['name'] ?? 'N/A').toUpperCase(),
          styles: nameStyle,
        ));
      }

      // 2. CHI TIẾT (VỪA - SIZE 1)
      if (showDetail) {
        final detail = "${product['capacity'] ?? ''} ${product['color'] ?? ''} ${product['condition'] ?? ''}".trim();
        if (detail.isNotEmpty) {
          bytes.addAll(generator.text(_removeDiacritics(detail).toUpperCase(), styles: const PosStyles(align: PosAlign.center, bold: true)));
        }
      }

      // 3. GIÁ BÁN
      final price = product['price'] ?? 0;
      bytes.addAll(generator.text(
        "GIA BAN: ${MoneyUtils.formatVND(price)}",
        styles: const PosStyles(align: PosAlign.center, bold: true),
      ));

      // 5. IMEI (VỪA)
      if (showIMEI) {
        bytes.addAll(generator.text(
          "IMEI: ${product['imei'] ?? 'N/A'}",
          styles: const PosStyles(align: PosAlign.center, bold: true),
        ));
      }

      // 6. QR CODE (NẾU CÓ)
      if (showQR) {
        bytes.addAll(generator.feed(1));
        // Dùng ID số đơn giản để QR code dễ scan hơn
        final simpleId = product['id']?.toString() ?? product['firestoreId']?.split('_').last ?? 'unknown';
        bytes.addAll(generator.qrcode("check_inv:$simpleId", size: QRSize.Size4));
      }

      // 7. CHỮ TÙY BIẾN
      if (customText.isNotEmpty) {
        bytes.addAll(generator.text(_removeDiacritics(customText).toUpperCase(), styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)));
      }

      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());
      return _sendToPrinter(bytes, printerType: printerType, bluetoothPrinter: customMac != null ? {'macAddress': customMac} : null, wifiIp: wifiIp);
    } catch (e) {
      print("Lỗi in tem sản phẩm: $e");
      return false;
    }
  }

  static Future<bool> printRepairReceiptLegacy(Map<String, dynamic> data, PaperSize paper, {PrinterType? printerType, dynamic bluetoothPrinter, String? wifiIp}) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());

    // Header thông tin shop
    bytes.addAll(generator.text(_removeDiacritics(data['shopName']?.toString() ?? 'SHOP NEW'), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(generator.text(_removeDiacritics(data['shopAddr']?.toString() ?? 'Chuyen Smartphone & Laptop'), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text("Hotline: ${data['shopPhone']?.toString() ?? '0123.456.789'}", styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.hr());

    // Tiêu đề phiếu tiếp nhận
    bytes.addAll(generator.text('PHIEU TIEP NHAN SUA CHUA', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(generator.text("Ma phieu: ${data['receiptCode']?.toString() ?? data['docId']?.toString() ?? 'N/A'}", styles: const PosStyles(align: PosAlign.center)));
    
    // Xử lý ngày nhận an toàn
    String receivedDateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());
    try {
      final receivedDate = data['receivedDate'];
      if (receivedDate != null && receivedDate.toString().isNotEmpty) {
        receivedDateStr = receivedDate.toString();
      }
    } catch (e) {
      // Giữ giá trị mặc định
    }
    bytes.addAll(generator.text("Ngay nhan: $receivedDateStr", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(1));

    // Thông tin khách hàng
    bytes.addAll(generator.text(_removeDiacritics("KHACH HANG: ${data['customerName']?.toString() ?? 'N/A'}"), styles: const PosStyles(bold: true)));
    if (data['customerPhone'] != null && data['customerPhone'].toString().isNotEmpty) {
      bytes.addAll(generator.text("SDT: ${data['customerPhone']}"));
    }
    if (data['customerAddress'] != null && data['customerAddress'].toString().isNotEmpty) {
      bytes.addAll(generator.text(_removeDiacritics("Dia chi: ${data['customerAddress']}")));
    }
    bytes.addAll(generator.feed(1));

    // Thông tin thiết bị
    bytes.addAll(generator.text(_removeDiacritics("THIET BI: ${data['deviceModel']?.toString() ?? 'N/A'}"), styles: const PosStyles(bold: true)));
    bytes.addAll(generator.text(_removeDiacritics("TINH TRANG: ${data['issue']?.toString() ?? 'N/A'}")));
    if (data['accessories'] != null && data['accessories'].toString().isNotEmpty) {
      bytes.addAll(generator.text(_removeDiacritics("PHU KIEN: ${data['accessories']}")));
    }
    bytes.addAll(generator.feed(1));

    // Giá dự kiến
    if (data['estimatedCost'] != null) {
      final costValue = data['estimatedCost'] is num ? data['estimatedCost'].toInt() : int.tryParse(data['estimatedCost'].toString()) ?? 0;
      if (costValue > 0) {
        final costStr = MoneyUtils.formatVND(costValue);
        bytes.addAll(generator.text("GIA DU KIEN: $costStr VND", styles: const PosStyles(bold: true, height: PosTextSize.size2)));
        bytes.addAll(generator.feed(1));
      }
    }

    // QR code để tra cứu
    bytes.addAll(generator.text(_removeDiacritics("Quet ma de tra cuu phieu sua:"), styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)));
    bytes.addAll(generator.qrcode("repair_receipt:${data['docId']?.toString() ?? data['receiptCode']?.toString() ?? 'N/A'}"));
    bytes.addAll(generator.feed(1));

    // Lưu ý
    bytes.addAll(generator.text(_removeDiacritics("- Quy khach vui long giu phieu de nhan may."), styles: const PosStyles(fontType: PosFontType.fontB)));
    bytes.addAll(generator.text(_removeDiacritics("- Thoi gian sua chua khoang 3-7 ngay."), styles: const PosStyles(fontType: PosFontType.fontB)));
    bytes.addAll(generator.text(_removeDiacritics("- Shop se lien he khi co thong tin."), styles: const PosStyles(fontType: PosFontType.fontB)));
    bytes.addAll(generator.feed(1));

    // Chữ ký
    bytes.addAll(generator.row([
      PosColumn(text: 'Khach hang', width: 6, styles: const PosStyles(align: PosAlign.center, bold: true)),
      PosColumn(text: 'Nhan vien', width: 6, styles: const PosStyles(align: PosAlign.center, bold: true)),
    ]));
    bytes.addAll(generator.feed(3));

    bytes.addAll(generator.text('CAM ON QUY KHACH!', styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return _sendToPrinter(bytes, printerType: printerType, bluetoothPrinter: bluetoothPrinter, wifiIp: wifiIp);
  }

  static Future<bool> printSaleReceipt(Map<String, dynamic> saleData, PaperSize paper, {PrinterType? printerType, dynamic bluetoothPrinter, String? wifiIp}) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paper, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());

    // Header thông tin shop
    bytes.addAll(generator.text(_removeDiacritics(saleData['shopName']?.toString() ?? 'SHOP NEW'), styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(generator.text(_removeDiacritics(saleData['shopAddr']?.toString() ?? 'Chuyen Smartphone & Laptop'), styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.text("Hotline: ${saleData['shopPhone']?.toString() ?? '0123.456.789'}", styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.hr());

    // Tiêu đề hóa đơn
    bytes.addAll(generator.text('HOA DON BAN HANG', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
    bytes.addAll(generator.text("Ma HD: ${saleData['firestoreId']?.toString() ?? 'N/A'}", styles: const PosStyles(align: PosAlign.center)));
    
    // Xử lý ngày bán an toàn
    String soldDateStr = 'N/A';
    try {
      final soldAt = saleData['soldAt'];
      if (soldAt != null) {
        final timestamp = soldAt is int ? soldAt : int.tryParse(soldAt.toString()) ?? 0;
        if (timestamp > 0) {
          soldDateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(timestamp));
        }
      }
    } catch (e) {
      soldDateStr = 'N/A';
    }
    bytes.addAll(generator.text("Ngay ban: $soldDateStr", styles: const PosStyles(align: PosAlign.center)));
    bytes.addAll(generator.feed(1));

    // Thông tin khách hàng
    bytes.addAll(generator.text(_removeDiacritics("KHACH HANG: ${saleData['customerName']?.toString() ?? 'Khach le'}"), styles: const PosStyles(bold: true)));
    if (saleData['customerPhone'] != null && saleData['customerPhone'].toString().isNotEmpty) {
      bytes.addAll(generator.text("SDT: ${saleData['customerPhone']}"));
    }
    if (saleData['customerAddress'] != null && saleData['customerAddress'].toString().isNotEmpty) {
      bytes.addAll(generator.text(_removeDiacritics("Dia chi: ${saleData['customerAddress']}")));
    }
    bytes.addAll(generator.feed(1));

    // Thông tin sản phẩm
    bytes.addAll(generator.text('SAN PHAM:', styles: const PosStyles(bold: true)));
    final productNames = saleData['productNames'];
    final productImeis = saleData['productImeis'];
    
    List<String> names = [];
    List<String> imeis = [];
    
    if (productNames is List) {
      names = productNames.map((e) => e?.toString() ?? 'N/A').toList();
    }
    if (productImeis is List) {
      imeis = productImeis.map((e) => e?.toString() ?? '').toList();
    }

    for (int i = 0; i < names.length; i++) {
      final productName = names[i];
      final imei = i < imeis.length ? imeis[i] : '';

      bytes.addAll(generator.text(_removeDiacritics("- $productName"), styles: const PosStyles(fontType: PosFontType.fontB)));
      if (imei.isNotEmpty) {
        bytes.addAll(generator.text("  IMEI: $imei", styles: const PosStyles(fontType: PosFontType.fontB)));
      }
    }
    bytes.addAll(generator.feed(1));

    // Bảo hành
    if (saleData['warranty'] != null) {
      bytes.addAll(generator.text(_removeDiacritics("BAO HANH: ${saleData['warranty']}"), styles: const PosStyles(bold: true)));
      bytes.addAll(generator.feed(1));
    }

    // Tổng tiền
    final totalPrice = saleData['totalPrice'];
    final priceValue = totalPrice is num ? totalPrice.toInt() : int.tryParse(totalPrice?.toString() ?? '0') ?? 0;
    final priceStr = MoneyUtils.formatVND(priceValue);
    bytes.addAll(generator.text("TONG TIEN: $priceStr VND", styles: const PosStyles(bold: true, height: PosTextSize.size2, align: PosAlign.center)));
    bytes.addAll(generator.feed(1));

    // Nhân viên bán hàng
    if (saleData['sellerName'] != null) {
      bytes.addAll(generator.text(_removeDiacritics("NV Ban hang: ${saleData['sellerName']}"), styles: const PosStyles(align: PosAlign.center)));
    }
    bytes.addAll(generator.feed(1));

    // QR code để tra cứu
    bytes.addAll(generator.text(_removeDiacritics("Quet ma de tra cuu hoa don:"), styles: const PosStyles(align: PosAlign.center, fontType: PosFontType.fontB)));
    bytes.addAll(generator.qrcode("sale_check:${saleData['firestoreId']?.toString() ?? 'N/A'}"));
    bytes.addAll(generator.feed(1));

    // Lưu ý
    bytes.addAll(generator.text(_removeDiacritics("- Cam on quy khach da tin dung shop."), styles: const PosStyles(fontType: PosFontType.fontB)));
    bytes.addAll(generator.text(_removeDiacritics("- Hang da ban khong duoc doi tra."), styles: const PosStyles(fontType: PosFontType.fontB)));
    bytes.addAll(generator.feed(1));

    // Chữ ký
    bytes.addAll(generator.row([
      PosColumn(text: 'Khach hang', width: 6, styles: const PosStyles(align: PosAlign.center, bold: true)),
      PosColumn(text: 'Nhan vien', width: 6, styles: const PosStyles(align: PosAlign.center, bold: true)),
    ]));
    bytes.addAll(generator.feed(3));

    bytes.addAll(generator.text('CAM ON QUY KHACH!', styles: const PosStyles(align: PosAlign.center, bold: true)));
    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    return _sendToPrinter(bytes, printerType: printerType, bluetoothPrinter: bluetoothPrinter, wifiIp: wifiIp);
  }

  static Future<bool> printPhoneLabelToWifi(Map<String, dynamic> labelData, String ipAddress) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm80, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());
    bytes.addAll(generator.text(_removeDiacritics(labelData['name'] ?? 'TEM MAY'), styles: const PosStyles(bold: true)));
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
    final fontScale = prefs.getDouble('label_font_scale') ?? 1.0;
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    List<int> bytes = [];
    bytes.addAll(generator.reset());

    PosTextSize headerSize = fontScale >= 2.0 ? PosTextSize.size2 : PosTextSize.size1;

    // Header
    if (prefs.getBool('receipt_show_logo') ?? true) {
      bytes.addAll(generator.text(_removeDiacritics(receiptData['shopName'] ?? 'SHOP NEW'), styles: PosStyles(align: PosAlign.center, bold: true, height: headerSize)));
    }
    bytes.addAll(generator.text(_removeDiacritics(receiptData['shopAddress'] ?? ''), styles: const PosStyles(align: PosAlign.center)));
    if (prefs.getBool('receipt_show_phone') ?? true) {
      bytes.addAll(generator.text("HOTLINE: ${receiptData['shopPhone'] ?? ''}", styles: const PosStyles(align: PosAlign.center, bold: true)));
    }
    bytes.addAll(generator.hr());
    bytes.addAll(generator.text('PHIEU SUA CHUA', styles: PosStyles(align: PosAlign.center, bold: true, height: headerSize)));
    bytes.addAll(generator.feed(1));

    // Customer info
    bytes.addAll(generator.text(_removeDiacritics("KHACH: ${receiptData['customerName'] ?? ''}")));
    bytes.addAll(generator.text("SDT: ${receiptData['phone'] ?? ''}"));
    bytes.addAll(generator.text(_removeDiacritics("MAY: ${receiptData['model'] ?? ''}")));
    bytes.addAll(generator.text(_removeDiacritics("LOI: ${receiptData['issue'] ?? ''}")));
    bytes.addAll(generator.text("GIA: ${_fmt(receiptData['estimatedCost'] ?? 0)} VND", styles: const PosStyles(bold: true)));
    bytes.addAll(generator.text("NGAY NHAN: ${receiptData['receivedDate'] ?? ''}", styles: const PosStyles(bold: true)));

    if (prefs.getBool('receipt_show_qr') ?? true) {
      bytes.addAll(generator.qrcode("repair:${receiptData['repairId'] ?? ''}", align: PosAlign.center));
    }

    bytes.addAll(generator.feed(2));
    bytes.addAll(generator.cut());

    // Send to specific printer if provided
    if (printerType == PrinterType.bluetooth && bluetoothPrinter != null) {
      final ok = await BluetoothPrinterService.connect(bluetoothPrinter.macAddress);
      if (ok) return await BluetoothPrinterService.printBytes(bytes);
    } else if (printerType == PrinterType.wifi && wifiIp != null) {
      try {
        final ok = await WifiPrinterService.instance.connect(ip: wifiIp, port: 9100);
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
}
