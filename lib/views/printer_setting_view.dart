import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../services/notification_service.dart';

class PrinterSettingView extends StatefulWidget {
  const PrinterSettingView({super.key});
  @override
  State<PrinterSettingView> createState() => _PrinterSettingViewState();
}

class _PrinterSettingViewState extends State<PrinterSettingView> {
  final ipCtrl = TextEditingController();
  final labelIpCtrl = TextEditingController();
  final bool _isTesting = false;
  String _logoPath = "";
  bool _enableLabelPrinter = false;
  String _paperSize = "80mm";

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      ipCtrl.text = prefs.getString('printer_ip') ?? "";
      labelIpCtrl.text = prefs.getString('label_printer_ip') ?? "";
      _logoPath = prefs.getString('shop_logo_path') ?? "";
      _enableLabelPrinter = prefs.getBool('enable_label_printer') ?? false;
      _paperSize = prefs.getString('paper_size') ?? "80mm";
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_ip', ipCtrl.text.trim());
    await prefs.setString('label_printer_ip', labelIpCtrl.text.trim());
    await prefs.setBool('enable_label_printer', _enableLabelPrinter);
    await prefs.setString('paper_size', _paperSize);
    NotificationService.showSnackBar("Đã lưu cấu hình máy in!", color: Colors.green);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text("CẤU HÌNH MÁY IN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: Colors.white, elevation: 0,
        automaticallyImplyLeading: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildPrinterCard(
              title: "MÁY IN HÓA ĐƠN",
              desc: "In phiếu tiếp nhận & Hóa đơn bán hàng",
              icon: Icons.receipt_long_rounded,
              color: const Color(0xFF2962FF),
              controller: ipCtrl,
              isEnable: true,
            ),
            const SizedBox(height: 20),
            _buildPrinterCard(
              title: "MÁY IN TEM QR",
              desc: "In tem định danh dán lên máy & phụ kiện",
              icon: Icons.qr_code_2_rounded,
              color: Colors.orange,
              controller: labelIpCtrl,
              isEnable: _enableLabelPrinter,
              onToggle: (v) => setState(() => _enableLabelPrinter = v),
            ),
            const SizedBox(height: 30),
            _buildLogoSection(),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _saveConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2962FF),
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text("LƯU CẤU HÌNH HỆ THỐNG", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterCard({required String title, required String desc, required IconData icon, required Color color, required TextEditingController controller, required bool isEnable, Function(bool)? onToggle}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25), boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: color.withAlpha(25), child: Icon(icon, color: color)),
              const SizedBox(width: 15),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), Text(desc, style: const TextStyle(fontSize: 11, color: Colors.grey))])),
              if (onToggle != null) Switch(value: isEnable, onChanged: onToggle, activeThumbColor: color),
            ],
          ),
          if (isEnable) ...[
            const SizedBox(height: 20),
            const Text("ĐỊA CHỈ IP (WIFI/LAN)", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              decoration: InputDecoration(
                hintText: "192.168.1.XXX",
                prefixIcon: const Icon(Icons.lan_rounded, size: 18),
                filled: true, fillColor: const Color(0xFFF8FAFF),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildLogoSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(25)),
      child: Row(
        children: [
          Container(
            width: 60, height: 60,
            decoration: BoxDecoration(color: const Color(0xFFF8FAFF), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
            child: _logoPath.isEmpty ? const Icon(Icons.image_outlined, color: Colors.grey) : ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(_logoPath), fit: BoxFit.cover)),
          ),
          const SizedBox(width: 15),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("LOGO CỬA HÀNG", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text("Sẽ hiển thị trên đầu phiếu in", style: TextStyle(fontSize: 11, color: Colors.grey))])),
          TextButton(
            onPressed: () async {
              final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
              if (picked != null) {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('shop_logo_path', picked.path);
                setState(() => _logoPath = picked.path);
              }
            }, 
            child: const Text("CHỌN ẢNH")
          ),
        ],
      ),
    );
  }
}
