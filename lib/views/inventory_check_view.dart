import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/inventory_check_model.dart';
import '../services/notification_service.dart';

class InventoryCheckView extends StatefulWidget {
  const InventoryCheckView({super.key});
  @override
  State<InventoryCheckView> createState() => _InventoryCheckViewState();
}

class _InventoryCheckViewState extends State<InventoryCheckView> {
  final _dbHelper = DBHelper();
  final _scannerController = MobileScannerController();
  
  String _selectedType = 'PHONE'; // PHONE hoặc ACCESSORY
  List<Map<String, dynamic>> _items = [];
  List<InventoryCheckItem> _checkItems = [];
  bool _isLoading = true;
  bool _isScanning = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _items = await _dbHelper.getItemsForInventoryCheck(_selectedType);
      _checkItems = _items.map((item) => InventoryCheckItem(
        itemId: item['id'].toString(),
        itemName: item['name'] ?? '',
        itemType: _selectedType,
        imei: item['imei'],
        quantity: 0, // SL kiểm được ban đầu là 0
        isChecked: false,
      )).toList();
    } catch (e) {
      NotificationService.showSnackBar('Lỗi tải danh sách: $e', color: Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _updateQuantity(int index, int delta) {
    setState(() {
      int newVal = _checkItems[index].quantity + delta;
      if (newVal < 0) newVal = 0;
      _checkItems[index] = InventoryCheckItem(
        itemId: _checkItems[index].itemId,
        itemName: _checkItems[index].itemName,
        itemType: _checkItems[index].itemType,
        imei: _checkItems[index].imei,
        quantity: newVal,
        isChecked: newVal > 0,
        checkedAt: newVal > 0 ? DateTime.now().millisecondsSinceEpoch : 0,
      );
    });
    HapticFeedback.lightImpact();
  }

  void _onDetect(BarcodeCapture capture) {
    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;
    
    final String code = barcode.rawValue!;
    int foundIdx = _checkItems.indexWhere((item) => item.imei == code || item.itemId == code);
    
    if (foundIdx != -1) {
      _updateQuantity(foundIdx, 1);
      NotificationService.showSnackBar('Đã kiểm: ${_checkItems[foundIdx].itemName}', color: Colors.green);
    } else {
      NotificationService.showSnackBar('Không tìm thấy mã: $code', color: Colors.orange);
    }
  }

  Future<void> _handleSave() async {
    if (_checkItems.every((item) => !item.isChecked)) {
      NotificationService.showSnackBar("Chưa có mặt hàng nào được kiểm!", color: Colors.orange);
      return;
    }

    final newCheck = InventoryCheck(
      checkType: _selectedType,
      checkDate: DateTime.now().millisecondsSinceEpoch,
      checkedBy: FirebaseAuth.instance.currentUser?.email?.split('@').first.toUpperCase() ?? 'ADMIN',
      items: _checkItems.where((i) => i.isChecked).toList(),
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    await _dbHelper.insertInventoryCheck(newCheck);
    HapticFeedback.heavyImpact();
    NotificationService.showSnackBar("ĐÃ LƯU KẾT QUẢ KIỂM KHO", color: Colors.blue);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text("KIỂM KHO CHUYÊN NGHIỆP", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        actions: [
          IconButton(onPressed: () => setState(() => _isScanning = !_isScanning), icon: Icon(_isScanning ? Icons.list_alt : Icons.qr_code_scanner, color: Colors.blueAccent))
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          if (_isScanning) _buildScannerArea() else Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : _buildItemList()),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          const Text("LOẠI HÀNG:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(width: 15),
          Expanded(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'PHONE', label: Text('Máy'), icon: Icon(Icons.phone_android, size: 16)),
                ButtonSegment(value: 'ACCESSORY', label: Text('Phụ kiện'), icon: Icon(Icons.headset, size: 16)),
              ],
              selected: {_selectedType},
              onSelectionChanged: (val) {
                setState(() => _selectedType = val.first);
                _loadData();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerArea() {
    return Expanded(
      child: Stack(
        children: [
          MobileScanner(controller: _scannerController, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(20)),
            ),
          ),
          const Positioned(bottom: 40, left: 0, right: 0, child: Text("Đưa mã máy/QR vào khung để kiểm nhanh", textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, backgroundColor: Colors.black45)))
        ],
      ),
    );
  }

  Widget _buildItemList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _checkItems.length,
      itemBuilder: (ctx, i) {
        final item = _checkItems[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: item.isChecked ? Colors.green.shade200 : Colors.transparent)),
          child: ListTile(
            title: Text(item.itemName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text(item.imei ?? "Mã phụ kiện", style: const TextStyle(fontSize: 11, color: Colors.grey)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(onPressed: () => _updateQuantity(i, -1), icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent)),
                Text("${item.quantity}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                IconButton(onPressed: () => _updateQuantity(i, 1), icon: const Icon(Icons.add_circle_outline, color: Colors.green)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    int checkedCount = _checkItems.where((i) => i.isChecked).length;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [const Text("ĐÃ KIỂM", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), Text("$checkedCount / ${_checkItems.length} mặt hàng", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))])),
            const SizedBox(width: 15),
            ElevatedButton(onPressed: _handleSave, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF), padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)), child: const Text("XÁC NHẬN CHỐT KHO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ],
        ),
      ),
    );
  }
}
