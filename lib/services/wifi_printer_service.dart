import 'dart:io';
import 'dart:async';

class WifiPrinterService {
  WifiPrinterService._private();
  static final WifiPrinterService instance = WifiPrinterService._private();

  Socket? _socket;

  // HÀM KẾT NỐI THỰC TẾ QUA IP VÀ PORT
  Future<bool> connect({required String ip, required int port}) async {
    try {
      print("WIFI_PRINTER: Đang thử kết nối tới $ip:$port...");
      
      // Ngắt kết nối cũ nếu có
      await disconnect();

      // Mở kết nối Socket với Timeout 5 giây
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
      
      if (_socket != null) {
        print("WIFI_PRINTER: Kết nối THÀNH CÔNG tới $ip");
        return true;
      }
      return false;
    } catch (e) {
      print("WIFI_PRINTER: Lỗi kết nối: $e");
      return false;
    }
  }

  // HÀM GỬI LỆNH IN THỰC TẾ
  Future<void> printBytes(List<int> bytes) async {
    if (_socket == null) {
      print("WIFI_PRINTER: Chưa có kết nối Socket!");
      return;
    }

    try {
      _socket!.add(bytes);
      await _socket!.flush(); // Đẩy dữ liệu đi ngay lập tức
      print("WIFI_PRINTER: Đã gửi dữ liệu in thành công.");
      
      // Tự động ngắt kết nối sau khi in xong 1 giây để giải phóng máy in
      Future.delayed(const Duration(seconds: 1), () => disconnect());
    } catch (e) {
      print("WIFI_PRINTER: Lỗi khi gửi dữ liệu in: $e");
      await disconnect();
    }
  }

  // HÀM TIỆN ÍCH DÙNG TRONG UNIFIED_SERVICE
  static Future<void> writeBytes(List<int> bytes) async {
    return instance.printBytes(bytes);
  }

  // HÀM NGẮT KẾT NỐI AN TOÀN
  Future<void> disconnect() async {
    try {
      if (_socket != null) {
        await _socket!.close();
        _socket = null;
        print("WIFI_PRINTER: Đã ngắt kết nối an toàn.");
      }
    } catch (e) {
      print("WIFI_PRINTER: Lỗi khi đóng kết nối: $e");
      _socket = null;
    }
  }
}
