import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import '../services/notification_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/thermal_printer_service.dart';
import '../services/wifi_printer_service.dart';
import '../theme/app_text_styles.dart';
import 'label_designer_view.dart';
import 'imei_qr_printer_view.dart';
import 'pty_print_designer_view.dart';
import 'repair_invoice_template_view.dart';
import 'sale_invoice_template_view.dart';

/// Màn hình cài đặt máy in - Đơn giản, tập trung vào kết nối
class PrinterSettingsView extends StatefulWidget {
  const PrinterSettingsView({super.key});

  @override
  State<PrinterSettingsView> createState() => _PrinterSettingsViewState();
}

class _PrinterSettingsViewState extends State<PrinterSettingsView> {
  // Wifi printer
  final _ipCtrl = TextEditingController();
  final _backupIpCtrl = TextEditingController();
  
  // Bluetooth printer
  BluetoothPrinterConfig? _selectedBT;
  bool _isScanning = false;
  List<BluetoothInfo> _btDevices = [];
  
  // Receipt settings
  final _rcNoteCtrl = TextEditingController();
  bool _showRcLogo = true;
  bool _showRcPhone = true;
  bool _showRcQR = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final savedBT = await BluetoothPrinterService.getSavedPrinter();
    
    if (!mounted) return;
    setState(() {
      _ipCtrl.text = prefs.getString('printer_ip') ?? '';
      _backupIpCtrl.text = prefs.getString('backup_printer_ip') ?? '';
      _selectedBT = savedBT;
      _showRcLogo = prefs.getBool('receipt_show_logo') ?? true;
      _showRcPhone = prefs.getBool('receipt_show_phone') ?? true;
      _showRcQR = prefs.getBool('receipt_show_qr') ?? true;
      _rcNoteCtrl.text = prefs.getString('receipt_note') ?? 'Cảm ơn quý khách!';
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_ip', _ipCtrl.text.trim());
    await prefs.setString('backup_printer_ip', _backupIpCtrl.text.trim());
    await prefs.setBool('receipt_show_logo', _showRcLogo);
    await prefs.setBool('receipt_show_phone', _showRcPhone);
    await prefs.setBool('receipt_show_qr', _showRcQR);
    await prefs.setString('receipt_note', _rcNoteCtrl.text);
    NotificationService.showSnackBar(AppLocalizations.of(context)!.printerSettingsSaved, color: Colors.green);
  }

  Future<void> _scanBluetooth() async {
    setState(() => _isScanning = true);
    
    try {
      final hasPermission = await BluetoothPrinterService.requestBluetoothPermissions();
      if (!hasPermission) {
        NotificationService.showSnackBar(AppLocalizations.of(context)!.bluetoothPermissionRequired, color: Colors.orange);
        setState(() => _isScanning = false);
        return;
      }

      final isEnabled = await BluetoothPrinterService.isBluetoothEnabled();
      if (!isEnabled) {
        NotificationService.showSnackBar(AppLocalizations.of(context)!.enableBluetoothToScan, color: Colors.orange);
        setState(() => _isScanning = false);
        return;
      }

      final devices = await BluetoothPrinterService.getPairedPrinters();
      
      if (!mounted) return;
      setState(() {
        _btDevices = devices;
        _isScanning = false;
      });

      if (devices.isEmpty) {
        NotificationService.showSnackBar(AppLocalizations.of(context)!.noDevicesFound, color: Colors.orange);
      } else {
        _showBluetoothDevicesDialog();
      }
    } catch (e) {
      setState(() => _isScanning = false);
      NotificationService.showSnackBar(AppLocalizations.of(context)!.bluetoothScanError(e.toString()), color: Colors.red);
    }
  }

  void _showBluetoothDevicesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.selectBluetoothPrinter),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _btDevices.length,
            itemBuilder: (_, i) {
              final device = _btDevices[i];
              final isSelected = _selectedBT?.macAddress == device.macAdress;
              return ListTile(
                leading: Icon(
                  Icons.print,
                  color: isSelected ? Colors.green : Colors.grey,
                ),
                title: Text(device.name),
                subtitle: Text(device.macAdress),
                trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                onTap: () async {
                  Navigator.pop(ctx);
                  final config = BluetoothPrinterConfig(
                    name: device.name,
                    macAddress: device.macAdress,
                  );
                  await BluetoothPrinterService.savePrinter(config);
                  if (device.name.toUpperCase().contains('PT-50DC')) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setString('label_paper_size', '50');
                    await prefs.setString('paper_size', '50mm');
                    await prefs.setBool('pt50dc_force_raster_qr', true);
                    await prefs.setString('label_code_type', 'qr');
                    NotificationService.showSnackBar(
                      'Đã áp dụng preset PT-50DC (khổ 50mm).',
                      color: Colors.green,
                    );
                  }
                  setState(() => _selectedBT = config);
                  NotificationService.showSnackBar(AppLocalizations.of(context)!.selected(device.name), color: Colors.green);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.of(context)!.close),
          ),
        ],
      ),
    );
  }

  Future<void> _testWifiPrinter() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) {
      NotificationService.showSnackBar(AppLocalizations.of(context)!.enterIpFirst, color: Colors.orange);
      return;
    }
    
    NotificationService.showSnackBar(AppLocalizations.of(context)!.testingConnection, color: Colors.blue);
    try {
      print('WIFI_TEST: Connecting to $ip:9100...');
      // Test connection by trying to connect to printer port
      final socket = await Socket.connect(ip, 9100, timeout: const Duration(seconds: 8));
      print('WIFI_TEST: Socket connected, sending test print...');
      
      // Tạo lệnh ESC/POS test
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      final bytes = <int>[];
      bytes.addAll(generator.reset());
      bytes.addAll(generator.text('=== TEST WIFI PRINTER ===', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
      bytes.addAll(generator.text('Shop Manager', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text('IP: $ip', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text('Time: ${DateTime.now().toString().substring(0, 19)}', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text('------------------------', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text('Ket noi WiFi thanh cong!', styles: const PosStyles(align: PosAlign.center, bold: true)));
      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());
      
      // Gửi dữ liệu
      socket.add(bytes);
      await socket.flush();
      print('WIFI_TEST: Data sent, ${bytes.length} bytes');
      
      await Future.delayed(const Duration(milliseconds: 500));
      await socket.close();
      print('WIFI_TEST: Socket closed');
      
      NotificationService.showSnackBar('✅ In thử WiFi thành công!', color: Colors.green);
    } on SocketException catch (e) {
      print('WIFI_TEST: SocketException: $e');
      NotificationService.showSnackBar('❌ Lỗi kết nối: ${e.message}', color: Colors.red);
    } on TimeoutException catch (e) {
      print('WIFI_TEST: Timeout: $e');
      NotificationService.showSnackBar('❌ Timeout: Không kết nối được $ip', color: Colors.red);
    } catch (e) {
      print('WIFI_TEST: Error: $e');
      NotificationService.showSnackBar(AppLocalizations.of(context)!.connectionFailed(e.toString()), color: Colors.red);
    }
  }

  Future<void> _testBluetoothPrinter() async {
    if (_selectedBT == null) {
      NotificationService.showSnackBar(AppLocalizations.of(context)!.selectBluetoothPrinterFirst, color: Colors.orange);
      return;
    }
    
    NotificationService.showSnackBar(AppLocalizations.of(context)!.testingConnection, color: Colors.blue);
    print('BT_TEST: Connecting to ${_selectedBT!.macAddress}...');
    
    final success = await BluetoothPrinterService.connect(_selectedBT!.macAddress);
    print('BT_TEST: Connect result: $success');
    
    if (success) {
      // Tạo lệnh ESC/POS test
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm80, profile);
      final bytes = <int>[];
      bytes.addAll(generator.reset());
      bytes.addAll(generator.text('=== TEST BLUETOOTH ===', styles: const PosStyles(align: PosAlign.center, bold: true, height: PosTextSize.size2)));
      bytes.addAll(generator.text('Shop Manager', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text('Printer: ${_selectedBT!.name}', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text('MAC: ${_selectedBT!.macAddress}', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text('Time: ${DateTime.now().toString().substring(0, 19)}', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text('------------------------', styles: const PosStyles(align: PosAlign.center)));
      bytes.addAll(generator.text('Ket noi Bluetooth OK!', styles: const PosStyles(align: PosAlign.center, bold: true)));
      bytes.addAll(generator.feed(2));
      bytes.addAll(generator.cut());
      
      print('BT_TEST: Sending ${bytes.length} bytes...');
      final printResult = await BluetoothPrinterService.printBytes(bytes);
      print('BT_TEST: Print result: $printResult');
      
      if (printResult) {
        NotificationService.showSnackBar('✅ In thử Bluetooth thành công!', color: Colors.green);
      } else {
        NotificationService.showSnackBar('❌ Kết nối OK nhưng gửi dữ liệu thất bại!', color: Colors.orange);
      }
    } else {
      NotificationService.showSnackBar(AppLocalizations.of(context)!.bluetoothConnectionFailed, color: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(AppLocalizations.of(context)!.printerSettings, style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline3.fontSize)),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: AppLocalizations.of(context)!.saveSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // THIẾT KẾ TEM - Card nổi bật
            _buildLabelDesignCard(),
            const SizedBox(height: 16),
            
            // KẾT NỐI MÁY IN WIFI
            _buildWifiPrinterCard(),
            const SizedBox(height: 16),
            
            // KẾT NỐI MÁY IN BLUETOOTH
            _buildBluetoothPrinterCard(),
            const SizedBox(height: 16),
            
            // CÀI ĐẶT HÓA ĐƠN
            _buildReceiptSettingsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildLabelDesignCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 3,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.pink.shade50],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Colors.blue.shade400, Colors.pink.shade400]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.design_services, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(AppLocalizations.of(context)!.productLabelDesign, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
                      Text(AppLocalizations.of(context)!.customizeContentAndFontSize, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Thiết kế tem PRO
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune, color: Colors.blue, size: 20),
              ),
              title: Text(AppLocalizations.of(context)!.labelDesignTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(AppLocalizations.of(context)!.layoutShopInfoFormula),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(AppLocalizations.of(context)!.hot, style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LabelDesignerView()),
              ),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.print, color: Colors.black, size: 20),
              ),
              title: const Text('PTY 1:1 Designer', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Thiết kế tem 1:1, kéo thả và in bitmap'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PtyPrintDesignerView()),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.receipt_long, color: Colors.blue.shade600, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'MẪU IN HÓA ĐƠN',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.build_circle, color: Colors.blue, size: 18),
                    ),
                    title: const Text('Mẫu phiếu sửa', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Chỉnh sửa mẫu in phiếu sửa chữa'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RepairInvoiceTemplateView()),
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.shopping_bag, color: Colors.green, size: 18),
                    ),
                    title: const Text('Mẫu hóa đơn bán', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Chỉnh sửa mẫu in hóa đơn bán hàng'),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SaleInvoiceTemplateView()),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.qr_code_2, color: Colors.green, size: 20),
              ),
              title: const Text(
                'In tem QR/Barcode IMEI hàng loạt',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Chọn IMEI và in hàng loạt qua Bluetooth/WiFi'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ImeiQrPrinterView()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWifiPrinterCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.wifi, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.wifiPrinter, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _ipCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.printerIpAddress,
                hintText: '192.168.1.xxx',
                prefixIcon: const Icon(Icons.router),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _backupIpCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.backupIpOptional,
                hintText: '192.168.1.xxx',
                prefixIcon: const Icon(Icons.router_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _testWifiPrinter,
                icon: const Icon(Icons.wifi_find),
                label: Text(AppLocalizations.of(context)!.testWifiConnection),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBluetoothPrinterCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bluetooth, color: Colors.indigo.shade600),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.bluetoothPrinter, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            
            // Máy in đã chọn
            if (_selectedBT != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_selectedBT!.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(_selectedBT!.macAddress, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () async {
                        await BluetoothPrinterService.clearSavedPrinter();
                        setState(() => _selectedBT = null);
                      },
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.grey),
                    const SizedBox(width: 12),
                    Text(AppLocalizations.of(context)!.noBluetoothPrinterSelected, style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isScanning ? null : _scanBluetooth,
                    icon: _isScanning 
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.bluetooth_searching),
                    label: Text(_isScanning ? AppLocalizations.of(context)!.scanning : AppLocalizations.of(context)!.scanBluetooth),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                if (_selectedBT != null) ...[
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _testBluetoothPrinter,
                    icon: const Icon(Icons.print),
                    label: Text(AppLocalizations.of(context)!.test),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptSettingsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_long, color: Colors.orange.shade600),
                const SizedBox(width: 8),
                Text(AppLocalizations.of(context)!.receiptSettings, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.showShopLogo),
              value: _showRcLogo,
              onChanged: (v) => setState(() => _showRcLogo = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.showPhoneAndAddress),
              value: _showRcPhone,
              onChanged: (v) => setState(() => _showRcPhone = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppLocalizations.of(context)!.showQrCodeLookup),
              value: _showRcQR,
              onChanged: (v) => setState(() => _showRcQR = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rcNoteCtrl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.receiptClosingMessage,
                hintText: AppLocalizations.of(context)!.thankYou,
                prefixIcon: const Icon(Icons.message),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ipCtrl.dispose();
    _backupIpCtrl.dispose();
    _rcNoteCtrl.dispose();
    super.dispose();
  }
}
