import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bluetooth_printer_service.dart';

class BluetoothPrinterTestView extends StatefulWidget {
  const BluetoothPrinterTestView({super.key});

  @override
  State<BluetoothPrinterTestView> createState() => _BluetoothPrinterTestViewState();
}

class _BluetoothPrinterTestViewState extends State<BluetoothPrinterTestView> {
  String _status = "Chưa kiểm tra";
  bool _isTesting = false;
  final List<String> _logs = [];

  void _addLog(String message) {
    setState(() {
      _logs.add("${DateTime.now().toString().substring(11, 19)}: $message");
    });
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isTesting = true;
      _logs.clear();
      _status = "Đang yêu cầu quyền...";
    });

    try {
      _addLog("Bắt đầu yêu cầu quyền Bluetooth tối ưu");

      final permissionResult = await BluetoothPrinterService.requestBluetoothPermissionsOptimized();

      if (permissionResult['success'] as bool) {
        _addLog("✅ Quyền Bluetooth quan trọng đã được cấp");
        final permissions = permissionResult['permissions'] as Map<String, bool>;
        permissions.forEach((key, granted) {
          if (granted) _addLog("  - $key: ✅");
        });
        setState(() => _status = "Thành công: Quyền đã được cấp");
      } else {
        _addLog("❌ Quyền Bluetooth quan trọng chưa được cấp:");
        final errors = permissionResult['errors'] as List<String>;
        for (var error in errors) {
          _addLog("  - $error");
        }

        final permissions = permissionResult['permissions'] as Map<String, bool>;
        _addLog("Trạng thái quyền:");
        permissions.forEach((key, granted) {
          _addLog("  - $key: ${granted ? '✅' : '❌'}");
        });

        setState(() => _status = "Lỗi: Thiếu quyền Bluetooth quan trọng");
      }

      // Hiển thị cảnh báo nếu có
      final warnings = permissionResult['warnings'] as List<String>;
      if (warnings.isNotEmpty) {
        _addLog("⚠️ Cảnh báo:");
        for (var warning in warnings) {
          _addLog("  - $warning");
        }
      }
    } catch (e) {
      _addLog("❌ Lỗi khi yêu cầu quyền: $e");
      setState(() => _status = "Lỗi: $e");
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _runFullTest() async {
    setState(() {
      _isTesting = true;
      _logs.clear();
      _status = "Đang kiểm tra...";
    });

    try {
      _addLog("Bắt đầu kiểm tra máy in Bluetooth");

      // 1. Kiểm tra và yêu cầu quyền chi tiết
      _addLog("Kiểm tra quyền Bluetooth chi tiết...");
      final permissionResult = await BluetoothPrinterService.requestBluetoothPermissionsOptimized();

      if (!(permissionResult['success'] as bool)) {
        _addLog("❌ Quyền Bluetooth quan trọng chưa được cấp:");
        final errors = permissionResult['errors'] as List<String>;
        for (var error in errors) {
          _addLog("  - $error");
        }

        final permissions = permissionResult['permissions'] as Map<String, bool>;
        _addLog("Trạng thái quyền:");
        permissions.forEach((key, granted) {
          _addLog("  - $key: ${granted ? '✅' : '❌'}");
        });

        setState(() => _status = "Lỗi: Thiếu quyền Bluetooth quan trọng");
        return;
      }

      _addLog("✅ Quyền Bluetooth quan trọng đã được cấp");
      final permissions = permissionResult['permissions'] as Map<String, bool>;
      permissions.forEach((key, granted) {
        if (granted) _addLog("  - $key: ✅");
      });

      // Hiển thị cảnh báo nếu có
      final warnings = permissionResult['warnings'] as List<String>;
      if (warnings.isNotEmpty) {
        _addLog("⚠️ Cảnh báo:");
        for (var warning in warnings) {
          _addLog("  - $warning");
        }
      }

      // 2. Kiểm tra Bluetooth có bật
      _addLog("Kiểm tra Bluetooth có bật...");
      final isEnabled = await BluetoothPrinterService.isBluetoothEnabled();
      if (!isEnabled) {
        _addLog("❌ Bluetooth chưa bật");
        setState(() => _status = "Lỗi: Bluetooth chưa bật");
        return;
      }
      _addLog("✅ Bluetooth đã bật");

      // 3. Lấy danh sách máy in đã pair
      _addLog("Lấy danh sách máy in đã pair...");
      final pairedPrinters = await BluetoothPrinterService.getPairedPrinters();
      _addLog("Tìm thấy ${pairedPrinters.length} máy in đã pair");
      for (var printer in pairedPrinters) {
        _addLog("  - ${printer.name} (${printer.macAdress})");
      }

      if (pairedPrinters.isEmpty) {
        _addLog("❌ Không có máy in nào đã pair");
        setState(() => _status = "Lỗi: Không có máy in đã pair");
        return;
      }

      // 4. Thử kết nối máy in đầu tiên
      final firstPrinter = pairedPrinters.first;
      _addLog("Thử kết nối với ${firstPrinter.name}...");
      final connectionResult = await BluetoothPrinterService.connectWithStatus(firstPrinter.macAdress);

      if (connectionResult['success'] == true) {
        _addLog("✅ Kết nối thành công!");
        
        // Thử in test đơn giản
        _addLog("Thử in test...");
        try {
          final testBytes = [0x1B, 0x40, 0x1B, 0x61, 0x01, 0x1B, 0x21, 0x20]; // ESC/POS commands
          testBytes.addAll("TEST IN\n\n\n\n\n".codeUnits);
          testBytes.addAll([0x1D, 0x56, 0x42, 0x00]); // Cut paper
          
          final printResult = await BluetoothPrinterService.printBytes(testBytes);
          if (printResult) {
            _addLog("✅ In test thành công!");
            setState(() => _status = "Thành công: Máy in hoạt động bình thường");
          } else {
            _addLog("❌ In test thất bại");
            setState(() => _status = "Lỗi: Kết nối OK nhưng in thất bại");
          }
        } catch (e) {
          _addLog("❌ Lỗi khi in test: $e");
          setState(() => _status = "Lỗi: Kết nối OK nhưng in lỗi - $e");
        }
      } else {
        final error = connectionResult['error'] ?? 'Unknown error';
        _addLog("❌ Kết nối thất bại: $error");
        setState(() => _status = "Lỗi: $error");
      }

    } catch (e) {
      _addLog("❌ Lỗi không mong muốn: $e");
      setState(() => _status = "Lỗi: $e");
    } finally {
      setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("KIỂM TRA MÁY IN BLUETOOTH")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trạng thái
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: _status.contains("Thành công") ? Colors.green.shade50 :
                       _status.contains("Lỗi") ? Colors.red.shade50 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _status.contains("Thành công") ? Colors.green :
                         _status.contains("Lỗi") ? Colors.red : Colors.grey,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _status.contains("Thành công") ? Icons.check_circle :
                    _status.contains("Lỗi") ? Icons.error : Icons.info,
                    color: _status.contains("Thành công") ? Colors.green :
                           _status.contains("Lỗi") ? Colors.red : Colors.grey,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_status, style: const TextStyle(fontWeight: FontWeight.bold))),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // Hướng dẫn
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "HƯỚNG DẪN:",
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "1. Nhấn 'YÊU CẦU QUYỀN BLUETOOTH' để cấp quyền cần thiết\n"
                    "2. Đảm bảo Bluetooth đã bật trong cài đặt thiết bị\n"
                    "3. Pair máy in Bluetooth với điện thoại trước\n"
                    "4. Nhấn 'CHẠY KIỂM TRA ĐẦY ĐỦ' để kiểm tra kết nối",
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Nút yêu cầu quyền
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isTesting ? null : _requestPermissions,
                icon: const Icon(Icons.security),
                label: const Text("YÊU CẦU QUYỀN BLUETOOTH"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                ),
              ),
            ),

            const SizedBox(height: 10),

            // Nút kiểm tra
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isTesting ? null : _runFullTest,
                icon: _isTesting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.science),
                label: Text(_isTesting ? "ĐANG KIỂM TRA..." : "CHẠY KIỂM TRA ĐẦY ĐỦ"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Logs
            const Text("NHẬT KÝ KIỂM TRA", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Text(
                      _logs[index],
                      style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 12),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 10),
            const Text(
              "HƯỚNG DẪN:\n"
              "1. Đảm bảo máy in đã bật và có giấy\n"
              "2. Vào Cài đặt > Bluetooth và pair máy in\n"
              "3. Chạy kiểm tra để xem vấn đề ở đâu\n"
              "4. Nếu vẫn lỗi, thử khởi động lại máy in và điện thoại",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
