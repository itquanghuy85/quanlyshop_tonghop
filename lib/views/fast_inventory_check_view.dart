import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/inventory_zone_model.dart';
import '../services/notification_service.dart';
import '../utils/qr_parser.dart';

class FastInventoryCheckView extends StatefulWidget {
  const FastInventoryCheckView({super.key});

  @override
  State<FastInventoryCheckView> createState() => _FastInventoryCheckViewState();
}

class _FastInventoryCheckViewState extends State<FastInventoryCheckView> {
  final db = DBHelper();
  final MobileScannerController _scannerController = MobileScannerController();

  // Inventory data
  List<Product> _expectedPhones = [];
  List<Product> _expectedAccessories = [];

  // Zone management
  List<InventoryZone> _inventoryZones = [];
  InventoryZone? _currentZone;
  bool _showZoneSelector = false;

  // Check results
  final Set<String> _checkedPhoneImeis = {}; // IMEI-based for phones
  final Map<String, int> _scannedAccessoryCounts = {}; // Count-based for accessories
  final Map<String, int> _expectedAccessoryCounts = {}; // Expected counts

  // Scanned items checklist
  final List<Map<String, dynamic>> _scannedItems = []; // List of scanned items for display

  bool _isLoading = true;
  bool _isScanning = false;
  bool _showChecklist = true; // Toggle checklist visibility
  int _totalScanned = 0;

  // Debounce mechanism
  Timer? _scanDebounceTimer;
  bool _isProcessingScan = false;
  bool _isScanInProgress = false; // Track if async processing is running
  DateTime? _lastScanTime;
  static const Duration _scanDebounceDuration = Duration(seconds: 1); // Increased to 1 second to prevent multiple notifications
  static const Duration _duplicateScanWarningDuration = Duration(seconds: 2); // Reduced to 2 seconds

  // Duplicate scan tracking
  String? _lastScannedCode;
  Timer? _duplicateWarningTimer;
  final Map<String, DateTime> _recentlyProcessedQRs = {}; // Track processed QR codes to prevent duplicates

  // User preferences
  bool _enableSoundFeedback = true;
  bool _enableHapticFeedback = true;

  @override
  void initState() {
    super.initState();
    _loadInventoryData();
  }

  @override
  void dispose() {
    _scannerController.dispose();
    _scanDebounceTimer?.cancel();
    _duplicateWarningTimer?.cancel();
    _recentlyProcessedQRs.clear();
    super.dispose();
  }

  Future<void> _loadInventoryData() async {
    setState(() => _isLoading = true);
    try {
      // Load phones (IMEI-based inventory)
      final phones = await db.getInStockProducts();
      _expectedPhones = phones.where((p) => p.type == 'PHONE' && p.imei != null && p.imei!.isNotEmpty).toList();

      // Load accessories (quantity-based inventory)
      final accessories = await db.getInStockProducts();
      final accessoryProducts = accessories.where((p) => p.type == 'ACCESSORY').toList();

      // Group accessories by code and count quantities
      _expectedAccessoryCounts.clear();
      for (final accessory in accessoryProducts) {
        final code = accessory.firestoreId ?? accessory.id.toString();
        _expectedAccessoryCounts[code] = (_expectedAccessoryCounts[code] ?? 0) + 1;
      }
      _expectedAccessories = accessoryProducts;

      // Create default zones based on product types
      _createDefaultZones();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showSnackBar('Lỗi tải dữ liệu kho: $e', color: Colors.red);
        setState(() => _isLoading = false);
      }
    }
  }

  void _createDefaultZones() {
    _inventoryZones = [
      InventoryZone(
        id: 'phones',
        name: 'Điện thoại',
        description: 'Kiểm tra tất cả điện thoại trong kho',
        expectedProductCodes: _expectedPhones.map((p) => p.imei!).toList(),
        isActive: true,
      ),
      InventoryZone(
        id: 'accessories',
        name: 'Phụ kiện',
        description: 'Kiểm tra tất cả phụ kiện',
        expectedProductCodes: _expectedAccessoryCounts.keys.toList(),
      ),
      InventoryZone(
        id: 'special',
        name: 'Đặc biệt',
        description: 'Sản phẩm đặc biệt cần kiểm tra riêng',
        expectedProductCodes: [],
      ),
    ];

    // Set first zone as current if available
    if (_inventoryZones.isNotEmpty) {
      _currentZone = _inventoryZones.first;
    }
  }

  void _onQRDetected(BarcodeCapture capture) {
    // Cancel any existing debounce timer
    _scanDebounceTimer?.cancel();

    // If currently processing a scan, ignore new detections
    if (_isProcessingScan || _isScanInProgress) {
      return;
    }

    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null) return;

    final qrData = barcode.rawValue!.trim();
    if (qrData.isEmpty) return;

    // Check if this QR was processed recently (within 3 seconds)
    final now = DateTime.now();
    if (_recentlyProcessedQRs.containsKey(qrData)) {
      final timeSinceProcessed = now.difference(_recentlyProcessedQRs[qrData]!);
      if (timeSinceProcessed < const Duration(seconds: 3)) {
        return; // Ignore duplicate detection
      }
    }

    // Check for duplicate scan (same QR code scanned too quickly)
    if (_isDuplicateScan(qrData)) {
      _showDuplicateScanWarning(qrData);
      return;
    }

    // Set processing flags
    setState(() => _isProcessingScan = true);
    _isScanInProgress = true;
    _lastScanTime = DateTime.now();
    _lastScannedCode = qrData;

    // Add to recently processed map
    _recentlyProcessedQRs[qrData] = now;

    // Clean up old entries from the map (older than 5 seconds)
    _recentlyProcessedQRs.removeWhere((key, time) => now.difference(time) > const Duration(seconds: 5));

    // Process the scan asynchronously
    _processQRScan(qrData).then((_) {
      // Reset processing flags after successful processing
      if (mounted) {
        setState(() {
          _isProcessingScan = false;
          _isScanInProgress = false;
        });
      }
    }).catchError((error) {
      // Reset processing flags on error
      if (mounted) {
        setState(() {
          _isProcessingScan = false;
          _isScanInProgress = false;
        });
      }
    });

    // Set debounce timer to prevent rapid scanning
    _scanDebounceTimer = Timer(_scanDebounceDuration, () {
      // Timer just prevents new scans, flag is reset by the async completion above
    });
  }

  bool _isDuplicateScan(String qrData) {
    if (_lastScannedCode == null || _lastScanTime == null) return false;

    final timeSinceLastScan = DateTime.now().difference(_lastScanTime!);
    return _lastScannedCode == qrData && timeSinceLastScan < _duplicateScanWarningDuration;
  }

  void _showDuplicateScanWarning(String qrData) {
    _provideScanFeedback(isSuccess: false);

    // Cancel any existing warning timer
    _duplicateWarningTimer?.cancel();

    // Show warning notification
    NotificationService.showSnackBar(
      '⚠️ Đã scan mã này gần đây! Đợi 3 giây trước khi scan lại',
      color: Colors.orange,
    );

    // Set timer to clear the warning after 3 seconds
    _duplicateWarningTimer = Timer(_duplicateScanWarningDuration, () {
      // Warning automatically clears
    });
  }

  void _provideScanFeedback({bool isSuccess = true}) {
    if (_enableHapticFeedback) {
      if (isSuccess) {
        HapticFeedback.lightImpact();
      } else {
        HapticFeedback.vibrate();
      }
    }

    if (_enableSoundFeedback) {
      if (isSuccess) {
        SystemSound.play(SystemSoundType.click);
      } else {
        SystemSound.play(SystemSoundType.alert);
      }
    }
  }

  Future<void> _processQRScan(String qrData) async {
    try {
      // Parse QR using unified format
      final qrMap = QRParser.parse(qrData);
      final type = qrMap['type'];

      if (type == 'PHONE') {
        _handlePhoneScan(qrMap);
      } else if (type == 'ACCESSORY') {
        _handleAccessoryScan(qrMap);
      } else {
        // Try to handle legacy QR codes (just IMEI) or other formats
        await _handleLegacyQR(qrData, qrMap);
      }
    } catch (e) {
      // Reset processing flag on error
      if (mounted) {
        setState(() => _isProcessingScan = false);
      }
      HapticFeedback.vibrate();
      NotificationService.showSnackBar('❌ Lỗi xử lý QR: $e', color: Colors.red);
    }
  }

  void _handlePhoneScan(Map<String, String> qrMap) {
    final imei = qrMap['imei'];
    if (imei == null || imei.isEmpty) {
      _provideScanFeedback(isSuccess: false);
      NotificationService.showSnackBar('❌ QR điện thoại thiếu IMEI', color: Colors.red);
      return;
    }

    // Check if this IMEI exists in expected inventory
    final expectedProduct = _expectedPhones.firstWhere(
      (p) {
        if (p.imei == null || p.imei!.isEmpty) return false;
        // If QR IMEI is 5 digits, compare with last 5 digits of stored IMEI
        // If QR IMEI is longer, compare directly
        if (imei.length == 5) {
          return p.imei!.length >= 5 && p.imei!.substring(p.imei!.length - 5) == imei;
        } else {
          return p.imei == imei;
        }
      },
      orElse: () => Product(
        name: 'Không có trong kho',
        brand: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        type: 'PHONE',
        imei: imei,
      ),
    );

    if (expectedProduct.imei != null && expectedProduct.name != 'Không có trong kho') {
      // Valid phone found - use the stored IMEI for tracking
      final storedImei = expectedProduct.imei!;
      if (!_checkedPhoneImeis.contains(storedImei)) {
        setState(() {
          _checkedPhoneImeis.add(storedImei);
          _totalScanned++;
        });
        _provideScanFeedback(isSuccess: true);
        NotificationService.showSnackBar('✅ ${expectedProduct.name} (${storedImei.substring(storedImei.length - 5)})');

        // Update zone progress
        _updateZoneProgress(storedImei, 1);

        // Add to checklist
        _addToChecklist('📱', expectedProduct.name, storedImei.substring(storedImei.length - 5));
      }
    } else {
      // Unexpected phone
      _provideScanFeedback(isSuccess: false);
      NotificationService.showSnackBar('🚨 Thừa: ${imei.substring(imei.length - 5)}', color: Colors.red);

      // Add to checklist as extra
      _addToChecklist('📱', 'Thừa: ${imei.substring(imei.length - 5)}', imei, status: '🚨');
    }
  }

  void _handleAccessoryScan(Map<String, String> qrMap) {
    final code = qrMap['code'];
    if (code == null || code.isEmpty) {
      _provideScanFeedback(isSuccess: false);
      NotificationService.showSnackBar('❌ QR phụ kiện thiếu code', color: Colors.red);
      return;
    }

    // Increment scan count for this accessory
    setState(() {
      _scannedAccessoryCounts[code] = (_scannedAccessoryCounts[code] ?? 0) + 1;
      _totalScanned++;
    });

    final currentCount = _scannedAccessoryCounts[code]!;
    final expectedCount = _expectedAccessoryCounts[code] ?? 0;

    final accessoryName = _expectedAccessories
        .firstWhere((a) => (a.firestoreId ?? a.id.toString()) == code,
            orElse: () => Product(name: 'Phụ kiện không xác định', brand: '', createdAt: 0, type: 'ACCESSORY'))
        .name;

    _provideScanFeedback(isSuccess: true);

    // Always show as successful scan with current count
    NotificationService.showSnackBar('✅ $accessoryName (đã quét: $currentCount)');

    // Update zone progress
    _updateZoneProgress(code, 1);

    // Add to checklist (will update existing if same accessory)
    _addToChecklist('🔧', accessoryName, 'x$currentCount');
  }

  /// Handle legacy QR codes that don't have type field
  Future<void> _handleLegacyQR(String qrData, Map<String, String> qrMap) async {
    // Handle legacy inventory check format: check_inv:ID
    if (qrData.startsWith('check_inv:')) {
      final productId = qrData.substring('check_inv:'.length);
      if (productId.isNotEmpty) {
        await _handleLegacyInventoryCheck(productId);
        return;
      }
    }

    // Case 1: Has imei key
    if (qrMap.containsKey('imei') && qrMap['imei']!.isNotEmpty) {
      _handlePhoneScan(qrMap);
      return;
    }

    // Case 2: Has code key
    if (qrMap.containsKey('code') && qrMap['code']!.isNotEmpty) {
      _handleAccessoryScan(qrMap);
      return;
    }

    // Case 3: No key-value pairs, just raw data
    if (qrMap.isEmpty) {
      // Check if it's a number (IMEI)
      if (RegExp(r'^\d+$').hasMatch(qrData) && qrData.length >= 5) {
        final legacyQrMap = {'imei': qrData, 'type': 'PHONE'};
        _handlePhoneScan(legacyQrMap);
        return;
      }
      // Check if it's text (accessory code)
      else if (qrData.isNotEmpty) {
        final legacyQrMap = {'code': qrData, 'type': 'ACCESSORY'};
        _handleAccessoryScan(legacyQrMap);
        return;
      }
    }

    // Case 4: Malformed or unknown format
    HapticFeedback.vibrate();
    NotificationService.showSnackBar('⚠️ QR không hợp lệ cho kiểm kho - cần IMEI hoặc code sản phẩm', color: Colors.orange);
  }

  /// Handle legacy inventory check format: check_inv:ID
  Future<void> _handleLegacyInventoryCheck(String productId) async {
    try {
      final db = DBHelper();
      final product = await db.getProductById(int.tryParse(productId) ?? -1);
      if (product == null) {
        HapticFeedback.vibrate();
        NotificationService.showSnackBar('🚨 Không tìm thấy sản phẩm với ID: $productId', color: Colors.red);
        return;
      }

      // Determine if it's a phone or accessory based on type and IMEI
      if (product.type == 'PHONE' && product.imei != null && product.imei!.isNotEmpty) {
        // Handle as phone
        final legacyQrMap = {'imei': product.imei!, 'type': 'PHONE'};
        _handlePhoneScan(legacyQrMap);
      } else if (product.type == 'ACCESSORY') {
        // Handle as accessory using firestoreId or id as code
        final code = product.firestoreId ?? product.id.toString();
        final legacyQrMap = {'code': code, 'type': 'ACCESSORY'};
        _handleAccessoryScan(legacyQrMap);
      } else {
        HapticFeedback.vibrate();
        NotificationService.showSnackBar('⚠️ Sản phẩm không hỗ trợ kiểm kho: ${product.name}', color: Colors.orange);
      }
    } catch (e) {
      HapticFeedback.vibrate();
      NotificationService.showSnackBar('❌ Lỗi kiểm tra sản phẩm: $e', color: Colors.red);
    }
  }

  void _toggleScanning() {
    setState(() => _isScanning = !_isScanning);
    if (_isScanning) {
      _scannerController.start();
    } else {
      _scannerController.stop();
    }
  }

  void _showScanSettings() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('CÀI ĐẶT QUÉT QR'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SwitchListTile(
                    title: const Text('Âm thanh phản hồi'),
                    subtitle: const Text('Phát âm thanh khi scan'),
                    value: _enableSoundFeedback,
                    onChanged: (value) {
                      setState(() => _enableSoundFeedback = value);
                    },
                  ),
                  SwitchListTile(
                    title: const Text('Rung phản hồi'),
                    subtitle: const Text('Rung thiết bị khi scan'),
                    value: _enableHapticFeedback,
                    onChanged: (value) {
                      setState(() => _enableHapticFeedback = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '⚡ Mẹo: Giữ khoảng cách 20-30cm với QR code\n⏱️ Thời gian chờ giữa các lần scan: 1.5 giây\n🚫 Tránh scan cùng mã quá nhanh',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ĐÓNG'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _resetCheck() {
    setState(() {
      _checkedPhoneImeis.clear();
      _scannedAccessoryCounts.clear();
      _totalScanned = 0;
      _currentZone = _inventoryZones.isNotEmpty ? _inventoryZones.first : null;
      // Reset zone progress
      for (var zone in _inventoryZones) {
        zone.scannedCounts.clear();
      }
    });
  }

  Map<String, int> _getPhoneResults() {
    final expectedImeis = _expectedPhones.map((p) => p.imei!).toSet();
    final checkedImeis = _checkedPhoneImeis;
    final missing = expectedImeis.difference(checkedImeis).length;
    final extra = checkedImeis.difference(expectedImeis).length;
    final checked = expectedImeis.intersection(checkedImeis).length;

    return {'checked': checked, 'missing': missing, 'extra': extra};
  }

  Map<String, int> _getAccessoryResults() {
    // For accessories, we just count total scanned items since each scan represents checking one item
    final totalScanned = _scannedAccessoryCounts.values.fold(0, (sum, count) => sum + count);

    // Since accessories can be scanned multiple times for same type, we don't calculate missing/extra
    // All scanned accessories are considered "checked"
    return {'checked': totalScanned, 'missing': 0, 'extra': 0};
  }

  void _updateZoneProgress(String productCode, int count) {
    if (_currentZone == null) return;

    setState(() {
      final updatedScannedCounts = Map<String, int>.from(_currentZone!.scannedCounts);
      updatedScannedCounts[productCode] = (updatedScannedCounts[productCode] ?? 0) + count;

      _inventoryZones = _inventoryZones.map((zone) {
        if (zone.id == _currentZone!.id) {
          final updatedZone = zone.copyWith(scannedCounts: updatedScannedCounts);
          // Check if zone is completed
          if (updatedZone.progress >= 1.0 && !updatedZone.isCompleted) {
            return updatedZone.copyWith(
              completedAt: DateTime.now(),
              isActive: false,
            );
          }
          return updatedZone;
        }
        return zone;
      }).toList();

      // Update current zone reference
      _currentZone = _inventoryZones.firstWhere((zone) => zone.id == _currentZone!.id);
    });
  }

  void _selectZone(InventoryZone zone) {
    setState(() {
      // Deactivate all zones
      _inventoryZones = _inventoryZones.map((z) => z.copyWith(isActive: false)).toList();

      // Activate selected zone
      _inventoryZones = _inventoryZones.map((z) {
        if (z.id == zone.id) {
          return z.copyWith(isActive: true);
        }
        return z;
      }).toList();

      _currentZone = _inventoryZones.firstWhere((z) => z.id == zone.id);
      _showZoneSelector = false;
    });

    NotificationService.showSnackBar('Đã chuyển sang zone: ${zone.name}');
  }

  /// Add scanned item to checklist (smart grouping for accessories)
  void _addToChecklist(String type, String name, String identifier, {String? status}) {
    // For accessories, check if we already have this item and update count instead of adding new
    if (type == '🔧') {
      final existingIndex = _scannedItems.indexWhere((item) =>
        item['type'] == type && item['name'] == name && item['status'] == (status ?? '✅')
      );

      if (existingIndex != -1) {
        // Update existing accessory count
        setState(() {
          _scannedItems[existingIndex]['identifier'] = identifier;
          _scannedItems[existingIndex]['timestamp'] = DateTime.now();
          // Move to top
          final item = _scannedItems.removeAt(existingIndex);
          _scannedItems.insert(0, item);
        });
        return;
      }
    }

    // Add new item
    setState(() {
      _scannedItems.insert(0, {
        'type': type,
        'name': name,
        'identifier': identifier,
        'timestamp': DateTime.now(),
        'status': status ?? '✅',
      });

      // Keep only last 50 items to avoid memory issues
      if (_scannedItems.length > 50) {
        _scannedItems.removeLast();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final phoneResults = _getPhoneResults();
    final accessoryResults = _getAccessoryResults();

    return Scaffold(
      appBar: AppBar(
        title: const Text('KIỂM KHO NHANH'),
        backgroundColor: const Color(0xFF2962FF),
        foregroundColor: Colors.white,
        actions: [
          // Zone selector
          TextButton.icon(
            onPressed: () => setState(() => _showZoneSelector = !_showZoneSelector),
            icon: Icon(_showZoneSelector ? Icons.expand_less : Icons.expand_more, color: Colors.white),
            label: Text(
              _currentZone?.name ?? 'Chọn Zone',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          IconButton(
            icon: Icon(_showChecklist ? Icons.checklist : Icons.checklist_outlined),
            onPressed: () => setState(() => _showChecklist = !_showChecklist),
            tooltip: _showChecklist ? 'Ẩn checklist' : 'Hiện checklist',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showScanSettings,
            tooltip: 'Cài đặt scan',
          ),
          IconButton(
            icon: Icon(_isScanning ? Icons.stop : Icons.qr_code_scanner),
            onPressed: _toggleScanning,
            tooltip: _isScanning ? 'Dừng scan' : 'Bắt đầu scan',
          ),
          if (_isScanning)
            IconButton(
              icon: const Icon(Icons.flashlight_on),
              onPressed: () => _scannerController.toggleTorch(),
              tooltip: 'Bật/tắt đèn flash',
            ),
        ],
      ),
      body: Column(
        children: [
          // Zone Selector (expandable)
          if (_showZoneSelector) _buildZoneSelector(),

          // Zone Progress
          if (_currentZone != null) _buildZoneProgress(),

          // Status bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem('📱 Đã kiểm', phoneResults['checked']!, Colors.green),
                _buildStatusItem('📱 Thiếu', phoneResults['missing']!, Colors.red),
                _buildStatusItem('📱 Thừa', phoneResults['extra']!, Colors.orange),
                _buildStatusItem('🔧 Đã kiểm', accessoryResults['checked']!, Colors.green),
                _buildStatusItem('🔧 Thiếu', accessoryResults['missing']!, Colors.red),
                _buildStatusItem('🔧 Thừa', accessoryResults['extra']!, Colors.orange),
              ],
            ),
          ),

          // Scanner and Checklist Row
          Expanded(
            child: Row(
              children: [
                // Scanner (takes most space)
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      _isScanning
                          ? MobileScanner(
                              controller: _scannerController,
                              onDetect: _onQRDetected,
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.qr_code_scanner, size: 100, color: Colors.grey),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Nhấn nút scan để bắt đầu kiểm kho',
                                    style: TextStyle(fontSize: 18, color: Colors.grey),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Điện thoại: scan IMEI\nPhụ kiện: scan từng món',
                                    style: TextStyle(color: Colors.grey[600]),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),

                      // Processing overlay
                      if (_isProcessingScan)
                        Container(
                          color: Colors.black.withOpacity(0.3),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Đang xử lý...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // Checklist Panel
                if (_showChecklist && _scannedItems.isNotEmpty)
                  Container(
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(left: BorderSide(color: Colors.grey.shade300)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(-2, 0),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Checklist Header
                        Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.blue.shade50,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Đã scan (${_scannedItems.length})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () => setState(() => _showChecklist = false),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),

                        // Scanned Items List
                        Expanded(
                          child: ListView.builder(
                            itemCount: _scannedItems.length,
                            itemBuilder: (context, index) {
                              final item = _scannedItems[index];
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      item['status'],
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${item['type']} ${item['name']}',
                                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            item['identifier'],
                                            style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // Bottom info
          if (_isScanning)
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.black87,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Đã scan: $_totalScanned',
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  Text(
                    'Giữ yên QR trước camera',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusItem(String label, int count, Color color) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: color),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildZoneSelector() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFF2962FF)),
                const SizedBox(width: 8),
                const Text(
                  'Chọn khu vực kiểm tra',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _showZoneSelector = false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 120,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _inventoryZones.length,
              itemBuilder: (context, index) {
                final zone = _inventoryZones[index];
                final isSelected = zone.id == _currentZone?.id;

                return Container(
                  width: 160,
                  margin: const EdgeInsets.only(right: 12),
                  child: Card(
                    elevation: isSelected ? 4 : 1,
                    color: isSelected ? Colors.blue.shade50 : Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected ? const Color(0xFF2962FF) : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => _selectZone(zone),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  zone.isCompleted ? Icons.check_circle : Icons.location_on,
                                  color: zone.isCompleted ? Colors.green : const Color(0xFF2962FF),
                                  size: 20,
                                ),
                                const Spacer(),
                                if (isSelected)
                                  const Icon(Icons.check, color: Color(0xFF2962FF), size: 16),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              zone.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: isSelected ? const Color(0xFF2962FF) : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${zone.totalScanned}/${zone.totalExpected} items',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneProgress() {
    if (_currentZone == null) return const SizedBox.shrink();

    final zone = _currentZone!;
    final progress = zone.progress;
    final isCompleted = zone.isCompleted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: isCompleted ? Colors.green.shade50 : Colors.blue.shade50,
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                isCompleted ? Icons.check_circle : Icons.location_on,
                color: isCompleted ? Colors.green : const Color(0xFF2962FF),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      zone.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      zone.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isCompleted ? Colors.green : const Color(0xFF2962FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${zone.totalScanned}/${zone.totalExpected}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation(
                isCompleted ? Colors.green : const Color(0xFF2962FF),
              ),
              minHeight: 6,
            ),
          ),
          if (isCompleted) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.celebration, color: Colors.green, size: 16),
                const SizedBox(width: 4),
                Text(
                  'Hoàn thành!',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}