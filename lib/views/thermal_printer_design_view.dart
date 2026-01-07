import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../services/notification_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/thermal_printer_service.dart';

class ThermalPrinterDesignView extends StatefulWidget {
  const ThermalPrinterDesignView({super.key});
  @override
  State<ThermalPrinterDesignView> createState() => _ThermalPrinterDesignViewState();
}

class _ThermalPrinterDesignViewState extends State<ThermalPrinterDesignView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 1. KẾT NỐI
  final _ipCtrl = TextEditingController();
  final _backupIpCtrl = TextEditingController();
  String _logoPath = "";
  BluetoothPrinterConfig? _selectedBT;
  bool _isScanning = false;

  // 2. THIẾT KẾ TEM (LABEL)
  String _paperSize = "80mm";
  double _labelFontScale = 1.0; // 1.0: Normal, 2.0: Large, 3.0: Extra Large
  bool _showLabelName = true;
  bool _showLabelDetail = true; 
  bool _showLabelPriceKPK = true;
  bool _showLabelPriceCPK = true;
  bool _showLabelIMEI = true;
  bool _showLabelQR = true;
  final _labelCustomCtrl = TextEditingController();

  // 3. THIẾT KẾ HÓA ĐƠN
  bool _showRcLogo = true;
  bool _showRcPhone = true;
  bool _showRcQR = true;
  final _rcNoteCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAll();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _ipCtrl.text = prefs.getString('printer_ip') ?? "";
      _backupIpCtrl.text = prefs.getString('backup_printer_ip') ?? "";
      _logoPath = prefs.getString('shop_logo_path') ?? "";
      _paperSize = prefs.getString('paper_size') ?? "80mm";
      _labelFontScale = prefs.getDouble('label_font_scale') ?? 1.0;
      _showLabelName = prefs.getBool('label_show_name') ?? true;
      _showLabelDetail = prefs.getBool('label_show_detail') ?? true;
      _showLabelPriceKPK = prefs.getBool('label_show_price_kpk') ?? true;
      _showLabelPriceCPK = prefs.getBool('label_show_price_cpk') ?? true;
      _showLabelIMEI = prefs.getBool('label_show_imei') ?? true;
      _showLabelQR = prefs.getBool('label_show_qr') ?? true;
      _labelCustomCtrl.text = prefs.getString('label_custom_text') ?? "";
      _showRcLogo = prefs.getBool('receipt_show_logo') ?? true;
      _showRcPhone = prefs.getBool('receipt_show_phone') ?? true;
      _showRcQR = prefs.getBool('receipt_show_qr') ?? true;
      _rcNoteCtrl.text = prefs.getString('receipt_note') ?? "Cảm ơn quý khách!";
    });
    final savedBT = await BluetoothPrinterService.getSavedPrinter();
    if (mounted) setState(() => _selectedBT = savedBT);
  }

  Future<void> _saveAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_ip', _ipCtrl.text.trim());
    await prefs.setString('backup_printer_ip', _backupIpCtrl.text.trim());
    await prefs.setString('paper_size', _paperSize);
    await prefs.setDouble('label_font_scale', _labelFontScale);
    await prefs.setBool('label_show_name', _showLabelName);
    await prefs.setBool('label_show_detail', _showLabelDetail);
    await prefs.setBool('label_show_price_kpk', _showLabelPriceKPK);
    await prefs.setBool('label_show_price_cpk', _showLabelPriceCPK);
    await prefs.setBool('label_show_imei', _showLabelIMEI);
    await prefs.setBool('label_show_qr', _showLabelQR);
    await prefs.setString('label_custom_text', _labelCustomCtrl.text);
    await prefs.setBool('receipt_show_logo', _showRcLogo);
    await prefs.setBool('receipt_show_phone', _showRcPhone);
    await prefs.setBool('receipt_show_qr', _showRcQR);
    await prefs.setString('receipt_note', _rcNoteCtrl.text);
    NotificationService.showSnackBar("ĐÃ LƯU & ÁP DỤNG CỠ CHỮ MỚI", color: Colors.green);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text("CẤU HÌNH IN SIÊU CẤP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        automaticallyImplyLeading: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: const Color(0xFF2962FF),
          tabs: const [Tab(text: "KẾT NỐI"), Tab(text: "MẪU TEM"), Tab(text: "HÓA ĐƠN")],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _wrapScroll(_buildConnectTab()),
          _wrapScroll(_buildLabelTab()),
          _wrapScroll(_buildReceiptTab()),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: ElevatedButton.icon(
          onPressed: _saveAll,
          icon: const Icon(Icons.save_rounded, color: Colors.white),
          label: const Text("LƯU & CẬP NHẬT CỠ CHỮ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF), minimumSize: const Size(double.infinity, 55), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
        ),
      ),
    );
  }

  Widget _wrapScroll(Widget child) => SingleChildScrollView(child: child);

  Widget _buildConnectTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _sectionCard("LOẠI GIẤY / TEM", [
             DropdownButtonFormField<String>(
              initialValue: _paperSize,
              items: const [
                DropdownMenuItem(value: "80mm", child: Text("Khổ 80mm (Mặc định)")),
                DropdownMenuItem(value: "58mm", child: Text("Khổ 58mm / Tem nhỏ")),
              ],
              onChanged: (v) => setState(() => _paperSize = v!),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ]),
          const SizedBox(height: 15),
          _sectionCard("MÁY IN WIFI/LAN", [
            TextField(controller: _ipCtrl, decoration: const InputDecoration(hintText: "192.168.1.XXX", prefixIcon: Icon(Icons.lan))),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _testWifiConnection,
              icon: const Icon(Icons.wifi_tethering, color: Colors.white),
              label: const Text("TEST KẾT NỐI WIFI"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 45),
              ),
            ),
          ], color: Colors.blue),
          const SizedBox(height: 15),
          _sectionCard("MÁY IN BLUETOOTH", [
            if (_selectedBT != null) ListTile(title: Text(_selectedBT!.name), subtitle: Text(_selectedBT!.macAddress), trailing: const Icon(Icons.check_circle, color: Colors.green), contentPadding: EdgeInsets.zero),
            ElevatedButton.icon(
              onPressed: _scanBT,
              icon: _isScanning ? const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.bluetooth_searching),
              label: Text(_isScanning ? "ĐANG TÌM..." : "QUÉT MÁY IN BLUETOOTH"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _testBTConnection,
              icon: const Icon(Icons.bluetooth_connected, color: Colors.white),
              label: const Text("TEST KẾT NỐI BLUETOOTH"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueGrey,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                minimumSize: const Size(double.infinity, 45),
              ),
            ),
          ], color: Colors.blueGrey),
        ],
      ),
    );
  }

  Widget _buildLabelTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _labelPreview(),
          const SizedBox(height: 20),
          _sectionCard("ĐỘ PHÓNG ĐẠI CHỮ (QUAN TRỌNG)", [
            Slider(
              value: _labelFontScale,
              min: 1.0, max: 3.0, divisions: 2,
              label: _labelFontScale == 1.0 ? "Bình thường" : (_labelFontScale == 2.0 ? "Lớn" : "Rất lớn"),
              onChanged: (v) => setState(() => _labelFontScale = v),
            ),
            Center(child: Text(_labelFontScale == 1.0 ? "Cỡ chữ: BÌNH THƯỜNG" : (_labelFontScale == 2.0 ? "Cỡ chữ: LỚN (Gợi ý)" : "Cỡ chữ: RẤT LỚN"), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))),
          ]),
          const SizedBox(height: 15),
          _sectionCard("HIỂN THỊ NỘI DUNG", [
            _checkItem("Hiện Tên máy (TO)", _showLabelName, (v) => setState(() => _showLabelName = v!)),
            _checkItem("Hiện Chi tiết gộp (Màu-DL-TT)", _showLabelDetail, (v) => setState(() => _showLabelDetail = v!)),
            _checkItem("Hiện Giá KPK (TO)", _showLabelPriceKPK, (v) => setState(() => _showLabelPriceKPK = v!)),
            _checkItem("Hiện Giá CPK (Vừa)", _showLabelPriceCPK, (v) => setState(() => _showLabelPriceCPK = v!)),
            _checkItem("Hiện IMEI", _showLabelIMEI, (v) => setState(() => _showLabelIMEI = v!)),
            _checkItem("Hiện Mã QR", _showLabelQR, (v) => setState(() => _showLabelQR = v!)),
            TextField(controller: _labelCustomCtrl, onChanged: (v)=>setState(() {}), decoration: const InputDecoration(labelText: "Chữ tùy biến cuối tem")),
          ]),
        ],
      ),
    );
  }

  Widget _buildReceiptTab() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _receiptPreview(),
          const SizedBox(height: 20),
          _sectionCard("CẤU HÌNH HÓA ĐƠN", [
            _checkItem("Hiện Logo Shop", _showRcLogo, (v) => setState(() => _showRcLogo = v!)),
            _checkItem("Hiện SĐT & Địa chỉ", _showRcPhone, (v) => setState(() => _showRcPhone = v!)),
            _checkItem("Hiện QR Tra cứu", _showRcQR, (v) => setState(() => _showRcQR = v!)),
            TextField(controller: _rcNoteCtrl, onChanged: (v)=>setState(() {}), decoration: const InputDecoration(labelText: "Lời chúc cuối hóa đơn")),
          ]),
        ],
      ),
    );
  }

  Widget _labelPreview() {
    double scale = _labelFontScale;
    return Container(
      width: 220, padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)]),
      child: Column(children: [
        if (_showLabelName) Text("IPHONE 13 PRO MAX", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14 * scale)),
        if (_showLabelDetail) Text("256GB XANH 99%", textAlign: TextAlign.center, style: TextStyle(fontSize: 10 * scale, fontWeight: FontWeight.bold)),
        if (_showLabelPriceKPK) Text("GIÁ KPK: 15.590", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12 * scale)),
        if (_showLabelPriceCPK) Text("GIÁ CPK: 15.990", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 11 * scale)),
        if (_showLabelIMEI || _showLabelQR) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (_showLabelIMEI) Expanded(child: Text("IMEI: 35890123...", style: TextStyle(fontSize: 8 * scale, fontWeight: FontWeight.bold))),
          if (_showLabelQR) Icon(Icons.qr_code_2, size: 30 * scale),
        ]),
        if (_labelCustomCtrl.text.isNotEmpty) Text(_labelCustomCtrl.text.toUpperCase(), style: TextStyle(fontSize: 8 * scale, color: Colors.grey, fontWeight: FontWeight.bold))
      ]),
    );
  }

  Widget _receiptPreview() {
    return Container(
      width: 240, padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300)),
      child: Column(children: [
        if (_showRcLogo) const Icon(Icons.store, color: Colors.blue),
        const Text("SHOP NEW", style: TextStyle(fontWeight: FontWeight.bold)),
        if (_showRcPhone) const Text("0123.456.789", style: TextStyle(fontSize: 9)),
        const Divider(),
        const Text("HOA DON BAN HANG", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10)),
        const Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text("Sản phẩm x1", style: TextStyle(fontSize: 8)), Text("15.500", style: TextStyle(fontSize: 8))]),
        if (_showRcQR) const Icon(Icons.qr_code_scanner, size: 40),
        Text(_rcNoteCtrl.text, style: const TextStyle(fontSize: 8, fontStyle: FontStyle.italic))
      ]),
    );
  }

  Widget _sectionCard(String title, List<Widget> children, {Color color = Colors.blueGrey}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 5)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 11)),
        const SizedBox(height: 12),
        ...children
      ]),
    );
  }

  Widget _checkItem(String l, bool v, Function(bool?) o) => CheckboxListTile(title: Text(l, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)), value: v, onChanged: o, dense: true, contentPadding: EdgeInsets.zero);

  Future<void> _pickLogo() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('shop_logo_path', picked.path);
      if (mounted) setState(() => _logoPath = picked.path);
    }
  }

  Future<void> _scanBT() async {
    setState(() => _isScanning = true);
    final list = await BluetoothPrinterService.getPairedPrinters();
    if (!mounted) return;
    setState(() { _isScanning = false; });
    
    if (list.isNotEmpty) {
      showModalBottomSheet(context: context, builder: (ctx) => ListView.builder(itemCount: list.length, itemBuilder: (c, i) => ListTile(title: Text(list[i].name), subtitle: Text(list[i].macAdress), onTap: () async {
        final navigator = Navigator.of(ctx);
        final config = BluetoothPrinterConfig(name: list[i].name, macAddress: list[i].macAdress);
        await BluetoothPrinterService.savePrinter(config);
        if (!mounted) return;
        setState(() => _selectedBT = config);
        navigator.pop();
      })));
    } else {
      NotificationService.showSnackBar("Không tìm thấy máy in Bluetooth nào đã ghép đôi", color: Colors.orange);
    }
  }

  Future<void> _testWifiConnection() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) {
      NotificationService.showSnackBar("Vui lòng nhập địa chỉ IP của máy in", color: Colors.orange);
      return;
    }

    NotificationService.showSnackBar("Đang test kết nối WiFi...", color: Colors.blue);

    final success = await ThermalPrinterService.testWifiConnection(ip);

    if (success) {
      NotificationService.showSnackBar("✅ Kết nối WiFi thành công! Máy in đã sẵn sàng.", color: Colors.green);
    } else {
      NotificationService.showSnackBar("❌ Kết nối WiFi thất bại. Kiểm tra IP và kết nối mạng.", color: Colors.red);
    }
  }

  Future<void> _testBTConnection() async {
    if (_selectedBT == null) {
      NotificationService.showSnackBar("Vui lòng quét và chọn máy in Bluetooth trước", color: Colors.orange);
      return;
    }

    NotificationService.showSnackBar("Đang test kết nối Bluetooth...", color: Colors.blue);

    final success = await ThermalPrinterService.testConnection();

    if (success) {
      NotificationService.showSnackBar("✅ Kết nối Bluetooth thành công! Máy in đã sẵn sàng.", color: Colors.green);
    } else {
      NotificationService.showSnackBar("❌ Kết nối Bluetooth thất bại. Kiểm tra máy in.", color: Colors.red);
    }
  }
}
