import 'dart:io';
import 'dart:async';

class WifiPrinterService {
  WifiPrinterService._private();
  static final WifiPrinterService instance = WifiPrinterService._private();

  Socket? _socket;
  String? _connectedIp;
  int? _connectedPort;

  // HÀM KẾT NỐI THỰC TẾ QUA IP VÀ PORT
  Future<bool> connect({required String ip, required int port}) async {
    try {
      print("WIFI_PRINTER: Đang thử kết nối tới $ip:$port...");
      
      // Luôn ngắt kết nối cũ và tạo kết nối mới để đảm bảo socket còn hoạt động
      await disconnect();

      // Mở kết nối Socket với Timeout 8 giây
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      
      if (_socket != null) {
        _connectedIp = ip;
        _connectedPort = port;
        print("WIFI_PRINTER: Kết nối THÀNH CÔNG tới $ip");
        return true;
      }
      print("WIFI_PRINTER: Socket null sau khi connect");
      return false;
    } on SocketException catch (e) {
      print("WIFI_PRINTER: SocketException: $e");
      _socket = null;
      _connectedIp = null;
      _connectedPort = null;
      return false;
    } on TimeoutException catch (e) {
      print("WIFI_PRINTER: Timeout kết nối: $e");
      _socket = null;
      _connectedIp = null;
      _connectedPort = null;
      return false;
    } catch (e) {
      print("WIFI_PRINTER: Lỗi kết nối: $e");
      _socket = null;
      _connectedIp = null;
      _connectedPort = null;
      return false;
    }
  }

  // HÀM GỬI LỆNH IN THỰC TẾ
  Future<bool> printBytes(List<int> bytes) async {
    if (_socket == null) {
      print("WIFI_PRINTER: Chưa có kết nối Socket!");
      return false;
    }

    try {
      print("WIFI_PRINTER: Đang gửi ${bytes.length} bytes đến máy in...");
      _socket!.add(bytes);
      await _socket!.flush(); // Đẩy dữ liệu đi ngay lập tức
      print("WIFI_PRINTER: Đã gửi dữ liệu in thành công.");
      
      // Đợi ngắn để máy in xử lý
      await Future.delayed(const Duration(milliseconds: 300));
      
      // Đóng kết nối ngay sau khi in xong
      await disconnect();
      return true;
    } on SocketException catch (e) {
      print("WIFI_PRINTER: SocketException khi gửi: $e");
      await disconnect();
      return false;
    } catch (e) {
      print("WIFI_PRINTER: Lỗi khi gửi dữ liệu in: $e");
      await disconnect();
      return false;
    }
  }

  // HÀM TIỆN ÍCH DÙNG TRONG UNIFIED_SERVICE
  static Future<void> writeBytes(List<int> bytes) async {
    return instance.printBytes(bytes).then((_) {});
  }

  // HÀM NGẮT KẾT NỐI AN TOÀN
  Future<void> disconnect() async {
    try {
      if (_socket != null) {
        await _socket!.close();
        print("WIFI_PRINTER: Đã ngắt kết nối an toàn.");
      }
    } catch (e) {
      print("WIFI_PRINTER: Lỗi khi đóng kết nối: $e");
    } finally {
      _socket = null;
      _connectedIp = null;
      _connectedPort = null;
    }
  }
  
  // Kiểm tra trạng thái kết nối
  bool get isConnected => _socket != null;
  String? get connectedIp => _connectedIp;
}
