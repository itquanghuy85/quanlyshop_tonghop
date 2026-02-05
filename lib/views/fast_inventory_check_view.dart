import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../theme/app_text_styles.dart';
import '../models/inventory_zone_model.dart';
import '../services/notification_service.dart';
import '../services/first_time_guide_service.dart';
import '../utils/qr_parser.dart';
import '../utils/imei_extractor.dart';

class FastInventoryCheckView extends StatefulWidget {
  const FastInventoryCheckView({super.key});

  @override
  State<FastInventoryCheckView> createState() => _FastInventoryCheckViewState();
}

class _FastInventoryCheckViewState extends State<FastInventoryCheckView> {
  final db = DBHelper();
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 1000,
    formats: [BarcodeFormat.all],
  );

  double _zoomScale = 0.0; // 0.0 - 1.0 (platform dependent)

  // Inventory data
  List<Product> _expectedPhones = [];
  List<Product> _expectedAccessories = [];

  // Zone management
  List<InventoryZone> _inventoryZones = [];
  InventoryZone? _currentZone;
  bool _showZoneSelector = false;

  // Check results
  final Set<String> _checkedPhoneImeis = {}; // IMEI-based for phones
  final Map<String, int> _scannedAccessoryCounts =
      {}; // Count-based for accessories
  final Map<String, int> _expectedAccessoryCounts = {}; // Expected counts

  // Scanned items checklist
  final List<Map<String, dynamic>> _scannedItems =
      []; // List of scanned items for display

  bool _isLoading = true;
  bool _isScanning = false;
  bool _showChecklist = true; // Toggle checklist visibility
  int _totalScanned = 0;

  // Debounce mechanism
  Timer? _scanDebounceTimer;
  bool _isProcessingScan = false;
  bool _isScanInProgress = false; // Track if async processing is running
  DateTime? _lastScanTime;
  static const Duration _scanDebounceDuration = Duration(
    seconds: 1,
  ); // Increased to 1 second to prevent multiple notifications
  static const Duration _duplicateScanWarningDuration = Duration(
    seconds: 2,
  ); // Reduced to 2 seconds

  // Duplicate scan tracking
  String? _lastScannedCode;
  Timer? _duplicateWarningTimer;
  final Map<String, DateTime> _recentlyProcessedQRs =
      {}; // Track processed QR codes to prevent duplicates

  // User preferences
  bool _enableSoundFeedback = true;
  bool _enableHapticFeedback = true;

  // Delay trước khi bắt đầu scan (2 giây để user chuẩn bị)
  bool _isScanReady = false;
  DateTime? _scanStartTime;

  Future<void> _setZoom(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped == _zoomScale) return;
    setState(() => _zoomScale = clamped);
    try {
      await _scannerController.setZoomScale(clamped);
    } catch (_) {
      // Ignore if device does not support zoom
    }
  }

  @override
  void initState() {
    super.initState();
    _loadInventoryData();
    // Hiển thị hướng dẫn cho người dùng mới
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showCarouselGuide(
      context: context,
      screenKey: FirstTimeGuideService.keyFastInventoryCheck,
      title: 'Kiểm Kho Nhanh',
      color: Colors.purple,
      steps: const [
        GuideStep(
          title: '📋 Danh sách cần kiểm',
          description:
              'Hệ thống hiển thị tất cả sản phẩm trong kho. Quét để đánh dấu đã kiểm.',
          icon: Icons.checklist,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '📷 Quét IMEI/Barcode',
          description:
              'Nhấn "Bắt đầu quét" và đưa camera vào mã. Hệ thống tự nhận diện và check.',
          icon: Icons.qr_code_scanner,
          iconColor: Colors.purple,
        ),
        GuideStep(
          title: '✅ Đã kiểm vs ❌ Thiếu',
          description:
              'Màu xanh = đã quét thấy. Màu đỏ = chưa quét hoặc thiếu. Dễ dàng phát hiện hàng mất.',
          icon: Icons.compare_arrows,
          iconColor: Colors.orange,
        ),
        GuideStep(
          title: '📊 Báo cáo kiểm kê',
          description:
              'Sau khi quét xong, xem báo cáo tổng hợp: Đã kiểm, Thiếu, Thừa (không có trong hệ thống).',
          icon: Icons.assessment,
          iconColor: Colors.teal,
        ),
      ],
    );
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
      _expectedPhones = phones
          .where(
            (p) =>
                p.type == 'DIEN_THOAI' && p.imei != null && p.imei!.isNotEmpty,
          )
          .toList();

      // Load accessories (quantity-based inventory)
      final accessories = await db.getInStockProducts();
      final accessoryProducts = accessories
          .where((p) => p.type == 'PHỤ KIỆN')
          .toList();

      // Group accessories by code and count quantities
      _expectedAccessoryCounts.clear();
      for (final accessory in accessoryProducts) {
        final code = accessory.firestoreId ?? accessory.id.toString();
        _expectedAccessoryCounts[code] =
            (_expectedAccessoryCounts[code] ?? 0) + 1;
      }
      _expectedAccessories = accessoryProducts;

      // Create default zones based on product types
      _createDefaultZones();

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        NotificationService.showSnackBar(
          'Lỗi tải dữ liệu kho: $e',
          color: Colors.red,
        );
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

  /// Smart IMEI matching - hỗ trợ 4-5 số (mã ngắn) hoặc 15 số (IMEI chuẩn)
  /// [storedIMEI]: IMEI đã lưu trong DB (có thể 4-5 hoặc 15 số)
  /// [scannedIMEI]: IMEI vừa quét được (có thể 4-5 hoặc 15 số)
  bool _matchIMEI(String storedIMEI, String scannedIMEI) {
    // Làm sạch - chỉ giữ số
    final stored = storedIMEI.replaceAll(RegExp(r'[^0-9]'), '');
    final scanned = scannedIMEI.replaceAll(RegExp(r'[^0-9]'), '');

    if (stored.isEmpty || scanned.isEmpty) return false;

    // Case 1: Match chính xác
    if (stored == scanned) return true;

    // Case 2: Scanned là mã ngắn (4-5 số) - so với cuối stored
    if (scanned.length >= 4 && scanned.length <= 5) {
      if (stored.length >= scanned.length) {
        return stored.substring(stored.length - scanned.length) == scanned;
      }
      // stored cũng là mã ngắn - so chính xác
      return stored == scanned;
    }

    // Case 3: Stored là mã ngắn (4-5 số) - so với cuối scanned
    if (stored.length >= 4 && stored.length <= 5) {
      if (scanned.length >= stored.length) {
        return scanned.substring(scanned.length - stored.length) == stored;
      }
    }

    // Case 4: Cả 2 đều là IMEI dài (15 số) - đã check ở Case 1
    return false;
  }

  void _onQRDetected(BarcodeCapture capture) {
    // Chờ countdown 2 giây xong mới cho scan
    if (!_isScanReady) return;

    // Cancel any existing debounce timer
    _scanDebounceTimer?.cancel();

    // If currently processing a scan, ignore new detections
    if (_isProcessingScan || _isScanInProgress) {
      return;
    }

    if (capture.barcodes.isEmpty) return;

    final barcode = capture.barcodes.firstWhere((b) {
      final raw = b.rawValue?.trim();
      final display = b.displayValue?.trim();
      return (raw != null && raw.isNotEmpty) ||
          (display != null && display.isNotEmpty);
    }, orElse: () => capture.barcodes.first);

    final qrData = (barcode.rawValue ?? barcode.displayValue ?? '').trim();
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
    _recentlyProcessedQRs.removeWhere(
      (key, time) => now.difference(time) > const Duration(seconds: 5),
    );

    // Process the scan asynchronously
    _processQRScan(qrData)
        .then((_) {
          // Reset processing flags after successful processing
          if (mounted) {
            setState(() {
              _isProcessingScan = false;
              _isScanInProgress = false;
            });
          }
        })
        .catchError((error) {
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
    return _lastScannedCode == qrData &&
        timeSinceLastScan < _duplicateScanWarningDuration;
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

      if (type == 'DIEN_THOAI') {
        _handlePhoneScan(qrMap);
      } else if (type == 'PHỤ KIỆN') {
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
      NotificationService.showSnackBar(
        '❌ QR điện thoại thiếu IMEI',
        color: Colors.red,
      );
      return;
    }
    // Check if this IMEI exists in expected inventory
    final expectedProduct = _expectedPhones.firstWhere(
      (p) {
        if (p.imei == null || p.imei!.isEmpty) return false;
        // Smart matching: hỗ trợ 4-5 số (mã ngắn) hoặc 15 số (IMEI chuẩn)
        return _matchIMEI(p.imei!, imei);
      },
      orElse: () => Product(
        name: 'Không có trong kho',
        brand: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
        type: 'DIEN_THOAI',
        imei: imei,
      ),
    );

    if (expectedProduct.imei != null &&
        expectedProduct.name != 'Không có trong kho') {
      // Valid phone found - use the stored IMEI for tracking
      final storedImei = expectedProduct.imei!;
      if (!_checkedPhoneImeis.contains(storedImei)) {
        setState(() {
          _checkedPhoneImeis.add(storedImei);
          _totalScanned++;
        });
        _provideScanFeedback(isSuccess: true);
        final imeiSuffix = storedImei.length >= 5
            ? storedImei.substring(storedImei.length - 5)
            : storedImei;
        NotificationService.showSnackBar(
          '✅ ${expectedProduct.name} ($imeiSuffix)',
        );

        // Update zone progress
        _updateZoneProgress(storedImei, 1);

        // Add to checklist
        _addToChecklist('📱', expectedProduct.name, imeiSuffix);
      }
    } else {
      // Unexpected phone
      _provideScanFeedback(isSuccess: false);
      final extraImeiSuffix = imei.length >= 5
          ? imei.substring(imei.length - 5)
          : imei;
      NotificationService.showSnackBar(
        '🚨 Thừa: $extraImeiSuffix',
        color: Colors.red,
      );

      // Add to checklist as extra
      _addToChecklist('📱', 'Thừa: $extraImeiSuffix', imei, status: '🚨');
    }
  }

  void _handleAccessoryScan(Map<String, String> qrMap) {
    final code = qrMap['code'];
    if (code == null || code.isEmpty) {
      _provideScanFeedback(isSuccess: false);
      NotificationService.showSnackBar(
        '❌ QR phụ kiện thiếu code',
        color: Colors.red,
      );
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
        .firstWhere(
          (a) => (a.firestoreId ?? a.id.toString()) == code,
          orElse: () => Product(
            name: 'Phụ kiện không xác định',
            brand: '',
            createdAt: 0,
            type: 'PHỤ KIỆN',
          ),
        )
        .name;

    _provideScanFeedback(isSuccess: true);

    // Always show as successful scan with current count
    NotificationService.showSnackBar(
      '✅ $accessoryName (đã quét: $currentCount)',
    );

    // Update zone progress
    _updateZoneProgress(code, 1);

    // Add to checklist (will update existing if same accessory)
    _addToChecklist('🔧', accessoryName, 'x$currentCount');
  }

  /// Handle legacy QR codes that don't have type field
  Future<void> _handleLegacyQR(String qrData, Map<String, String> qrMap) async {
    // Normalize common IMEI prefix formats (e.g., "IMEI:12345")
    final imeiPrefixMatch = RegExp(
      r'imei\s*[:\-]?\s*(\d{4,})',
      caseSensitive: false,
    ).firstMatch(qrData);
    if (imeiPrefixMatch != null) {
      final imei = imeiPrefixMatch.group(1);
      if (imei != null && imei.isNotEmpty) {
        _handlePhoneScan({'imei': imei, 'type': 'DIEN_THOAI'});
        return;
      }
    }

    // Handle legacy inventory check format: check_inv:ID hoặc check_product:ID
    if (qrData.startsWith('check_inv:')) {
      final productId = qrData.substring('check_inv:'.length);
      if (productId.isNotEmpty) {
        await _handleLegacyInventoryCheck(productId);
        return;
      }
    }

    // Handle QR từ tem in: check_product:ID
    if (qrData.startsWith('check_product:')) {
      final productId = qrData.substring('check_product:'.length);
      if (productId.isNotEmpty) {
        await _handleLegacyInventoryCheck(productId);
        return;
      }
    }

    // Case 1: Has imei key (format: imei=XXXXX hoặc imei=XXXXX&id=YYY)
    if (qrMap.containsKey('imei') && qrMap['imei']!.isNotEmpty) {
      debugPrint('✅ Found imei key: ${qrMap['imei']}');
      _handlePhoneScan(qrMap);
      return;
    }

    // Case 1b: Has id key only (format: id=XXXXX) - lookup product by firestoreId
    if (qrMap.containsKey('id') && qrMap['id']!.isNotEmpty) {
      debugPrint('✅ Found id key: ${qrMap['id']}');
      await _handleLegacyInventoryCheck(qrMap['id']!);
      return;
    }

    // Case 2: Has code key
    if (qrMap.containsKey('code') && qrMap['code']!.isNotEmpty) {
      _handleAccessoryScan(qrMap);
      return;
    }

    // Case 3: Try smart IMEI extraction for multi-line QR (Apple, Samsung, etc)
    final imeiResult = IMEIExtractor.extract(qrData);
    if (imeiResult.hasIMEI) {
      // Sử dụng IMEI đầu tiên được tìm thấy
      final imei = imeiResult.imei!;
      final legacyQrMap = {'imei': imei, 'type': 'DIEN_THOAI'};
      _handlePhoneScan(legacyQrMap);

      // Thông báo nếu QR có nhiều IMEI
      if (imeiResult.hasMultipleCandidates) {
        NotificationService.showSnackBar(
          'ℹ️ QR có ${imeiResult.candidates.length} IMEI, đã dùng IMEI đầu tiên',
          color: Colors.blue,
        );
      }
      return;
    }

    // Case 4: Raw data (single line number/text) - xử lý cả khi qrMap không rỗng nhưng không có type/imei/code
    // Khi QRParser parse "1234" sẽ trả về {"1234": ""} - không empty nhưng không hợp lệ
    final isRawNumber = RegExp(r'^\d+$').hasMatch(qrData);
    if (isRawNumber && qrData.length >= 4) {
      // IMEI ngắn (4-5 số) hoặc IMEI chuẩn (15 số)
      final legacyQrMap = {'imei': qrData, 'type': 'DIEN_THOAI'};
      _handlePhoneScan(legacyQrMap);
      return;
    }

    // Nếu không phải số thuần, check qrMap empty rồi xử lý như text
    if (qrMap.isEmpty && qrData.isNotEmpty) {
      final legacyQrMap = {'code': qrData, 'type': 'PHỤ KIỆN'};
      _handleAccessoryScan(legacyQrMap);
      return;
    }

    // Case 5: Malformed or unknown format
    HapticFeedback.vibrate();
    NotificationService.showSnackBar(
      '⚠️ QR không hợp lệ cho kiểm kho - cần IMEI hoặc code sản phẩm',
      color: Colors.orange,
    );
  }

  /// Handle legacy inventory check format: check_inv:ID hoặc check_product:ID
  Future<void> _handleLegacyInventoryCheck(String productId) async {
    try {
      final db = DBHelper();
      Product? product;

      // Thử tìm theo SQLite id (số nguyên)
      final intId = int.tryParse(productId);
      if (intId != null && intId > 0) {
        product = await db.getProductById(intId);
      }

      // Nếu không tìm thấy, thử tìm theo firestoreId (chuỗi)
      product ??= await db.getProductByFirestoreId(productId);

      if (product == null) {
        HapticFeedback.vibrate();
        NotificationService.showSnackBar(
          '🚨 Không tìm thấy sản phẩm với ID: $productId',
          color: Colors.red,
        );
        return;
      }

      // Determine if it's a phone or accessory based on type and IMEI
      if (product.type == 'DIEN_THOAI' &&
          product.imei != null &&
          product.imei!.isNotEmpty) {
        // Handle as phone
        final legacyQrMap = {'imei': product.imei!, 'type': 'DIEN_THOAI'};
        _handlePhoneScan(legacyQrMap);
      } else if (product.type == 'PHỤ KIỆN') {
        // Handle as accessory using firestoreId or id as code
        final code = product.firestoreId ?? product.id.toString();
        final legacyQrMap = {'code': code, 'type': 'PHỤ KIỆN'};
        _handleAccessoryScan(legacyQrMap);
      } else {
        HapticFeedback.vibrate();
        NotificationService.showSnackBar(
          '⚠️ Sản phẩm không hỗ trợ kiểm kho: ${product.name}',
          color: Colors.orange,
        );
      }
    } catch (e) {
      HapticFeedback.vibrate();
      NotificationService.showSnackBar(
        '❌ Lỗi kiểm tra sản phẩm: $e',
        color: Colors.red,
      );
    }
  }

  void _toggleScanning() {
    setState(() {
      _isScanning = !_isScanning;
      if (_isScanning) {
        // Bắt đầu countdown 2 giây trước khi cho phép scan
        _isScanReady = false;
        _scanStartTime = DateTime.now();
        _scannerController.start();
        // Sau 2 giây mới cho phép xử lý scan
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _isScanning) {
            setState(() => _isScanReady = true);
          }
        });
      } else {
        _isScanReady = false;
        _scannerController.stop();
      }
    });
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
                  Text(
                    '⚡ Mẹo: Giữ khoảng cách 20-30cm với QR code\n⏱️ Thời gian chờ giữa các lần scan: 1.5 giây\n🚫 Tránh scan cùng mã quá nhanh',
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                      color: Colors.grey,
                    ),
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

  /// Dialog nhập IMEI thủ công khi QR bị mờ/rách
  void _showManualInputDialog() {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.keyboard, color: Colors.purple),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('NHẬP IMEI THỦ CÔNG', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade700,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Dùng khi QR bị mờ hoặc rách.\nNhập IMEI in trên máy để check.',
                          style: TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    labelText: 'IMEI / Mã sản phẩm',
                    hintText: 'Ví dụ: 353456789012345',
                    prefixIcon: const Icon(Icons.phone_android, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    isDense: true,
                    helperText: 'IMEI thường có 15 số',
                    helperStyle: const TextStyle(fontSize: 11),
                  ),
                  style: const TextStyle(fontSize: 14),
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      Navigator.pop(ctx);
                      _processManualInput(value.trim());
                    }
                  },
                ),
                // Quick buttons for recent scans - only show if space available
                if (_scannedItems.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Đã scan gần đây:',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: _scannedItems.take(2).map((item) {
                      final id = item['identifier'] as String;
                      return ActionChip(
                        padding: EdgeInsets.zero,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          id.length > 8
                              ? '...${id.substring(id.length - 8)}'
                              : id,
                          style: const TextStyle(fontSize: 10),
                        ),
                        onPressed: () {
                          controller.text = id;
                        },
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(ctx);
                _processManualInput(controller.text.trim());
              }
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('CHECK VÀO LIST'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Xử lý IMEI nhập thủ công
  void _processManualInput(String input) {
    // Normalize input - remove spaces and dashes
    final normalized = input.replaceAll(RegExp(r'[\s\-]'), '');

    // Check if it's a number (IMEI) or text (product code)
    final isNumber = RegExp(r'^\d+$').hasMatch(normalized);

    if (isNumber && normalized.length >= 4) {
      // Treat as IMEI for phone
      final qrMap = {'imei': normalized, 'type': 'DIEN_THOAI'};
      _handlePhoneScan(qrMap);
    } else if (normalized.isNotEmpty) {
      // Treat as product code for accessory
      final qrMap = {'code': normalized, 'type': 'PHỤ KIỆN'};
      _handleAccessoryScan(qrMap);
    } else {
      NotificationService.showSnackBar(
        '⚠️ Vui lòng nhập IMEI hoặc mã sản phẩm hợp lệ',
        color: Colors.orange,
      );
    }
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
    final totalScanned = _scannedAccessoryCounts.values.fold(
      0,
      (sum, count) => sum + count,
    );

    // Since accessories can be scanned multiple times for same type, we don't calculate missing/extra
    // All scanned accessories are considered "checked"
    return {'checked': totalScanned, 'missing': 0, 'extra': 0};
  }

  void _updateZoneProgress(String productCode, int count) {
    if (_currentZone == null) return;

    setState(() {
      final updatedScannedCounts = Map<String, int>.from(
        _currentZone!.scannedCounts,
      );
      updatedScannedCounts[productCode] =
          (updatedScannedCounts[productCode] ?? 0) + count;

      _inventoryZones = _inventoryZones.map((zone) {
        if (zone.id == _currentZone!.id) {
          final updatedZone = zone.copyWith(
            scannedCounts: updatedScannedCounts,
          );
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
      _currentZone = _inventoryZones.firstWhere(
        (zone) => zone.id == _currentZone!.id,
      );
    });
  }

  void _selectZone(InventoryZone zone) {
    setState(() {
      // Deactivate all zones
      _inventoryZones = _inventoryZones
          .map((z) => z.copyWith(isActive: false))
          .toList();

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

  /// Build TOÀN BỘ danh sách kho với trạng thái đã kiểm/chưa kiểm
  /// Sắp xếp: Chưa kiểm lên đầu, đã kiểm xuống cuối (với gạch ngang)
  Widget _buildFullInventoryList() {
    // Gộp điện thoại và phụ kiện thành 1 list
    final allItems = <Map<String, dynamic>>[];

    // Thêm điện thoại
    for (final phone in _expectedPhones) {
      final isChecked = _checkedPhoneImeis.contains(phone.imei);
      // Lấy 5 số cuối IMEI một cách an toàn
      String imeiSuffix = '';
      if (phone.imei != null && phone.imei!.isNotEmpty) {
        final imeiLen = phone.imei!.length;
        imeiSuffix = imeiLen >= 5
            ? phone.imei!.substring(imeiLen - 5)
            : phone.imei!;
      }
      allItems.add({
        'type': '📱',
        'name': phone.name,
        'identifier': imeiSuffix,
        'fullImei': phone.imei,
        'isChecked': isChecked,
        'isPhone': true,
        'product': phone,
      });
    }

    // Thêm phụ kiện
    for (final acc in _expectedAccessories) {
      final code = acc.firestoreId ?? acc.id.toString();
      final scanned = _scannedAccessoryCounts[code] ?? 0;
      final expected = _expectedAccessoryCounts[code] ?? 1;
      allItems.add({
        'type': '🔧',
        'name': acc.name,
        'identifier': 'SL: $scanned/$expected',
        'code': code,
        'isChecked': scanned >= expected,
        'isPhone': false,
        'product': acc,
      });
    }

    if (allItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Không có sản phẩm nào trong kho',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // GIỮ NGUYÊN THỨ TỰ GỐC - không sắp xếp lại khi check
    // để người dùng có thể theo dõi vị trí

    return ListView.builder(
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        final isChecked = item['isChecked'] as bool;
        final isPhone = item['isPhone'] as bool;

        return InkWell(
          // Cho phép nhấn để check thủ công (khi QR mờ/rách)
          onTap: isChecked ? null : () => _showQuickCheckConfirm(item, isPhone),
          onLongPress: () => _showQuickCheckConfirm(item, isPhone),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isChecked ? Colors.green.shade50 : null,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                // Checkbox icon
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isChecked ? Colors.green : Colors.grey.shade300,
                  ),
                  child: Icon(
                    isChecked ? Icons.check : Icons.circle_outlined,
                    size: 14,
                    color: isChecked ? Colors.white : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['type']} ${item['name']}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isChecked ? Colors.green.shade700 : null,
                          decoration: isChecked
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: Colors.green.shade700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item['identifier'] as String,
                        style: TextStyle(
                          fontSize: 10,
                          color: isChecked
                              ? Colors.green.shade600
                              : Colors.grey[600],
                          decoration: isChecked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Icon gợi ý có thể nhấn để check
                if (!isChecked)
                  Icon(Icons.touch_app, size: 12, color: Colors.grey.shade400),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Build danh sách sản phẩm chờ kiểm (khi chưa scan gì)
  Widget _buildPendingItemsList() {
    // Gộp điện thoại và phụ kiện thành 1 list
    final allItems = <Map<String, dynamic>>[];

    // Thêm điện thoại
    for (final phone in _expectedPhones) {
      final isChecked = _checkedPhoneImeis.contains(phone.imei);
      // Lấy 5 số cuối IMEI một cách an toàn
      String imeiSuffix = '';
      if (phone.imei != null && phone.imei!.isNotEmpty) {
        final imeiLen = phone.imei!.length;
        imeiSuffix = imeiLen >= 5
            ? phone.imei!.substring(imeiLen - 5)
            : phone.imei!;
      }
      allItems.add({
        'type': '📱',
        'name': phone.name,
        'identifier': imeiSuffix,
        'isChecked': isChecked,
      });
    }

    // Thêm phụ kiện
    for (final acc in _expectedAccessories) {
      final code = acc.firestoreId ?? acc.id.toString();
      final scanned = _scannedAccessoryCounts[code] ?? 0;
      final expected = _expectedAccessoryCounts[code] ?? 1;
      allItems.add({
        'type': '🔧',
        'name': acc.name,
        'identifier': 'SL: $scanned/$expected',
        'isChecked': scanned >= expected,
      });
    }

    if (allItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Không có sản phẩm nào trong kho',
            style: TextStyle(color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: allItems.length,
      itemBuilder: (context, index) {
        final item = allItems[index];
        final isChecked = item['isChecked'] as bool;
        final isPhone = item['type'] == '📱';

        return InkWell(
          // Cho phép nhấn để check thủ công (khi QR mờ/rách)
          onTap: isChecked ? null : () => _showQuickCheckConfirm(item, isPhone),
          onLongPress: () => _showQuickCheckConfirm(item, isPhone),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isChecked ? Colors.green.shade50 : null,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                Text(
                  isChecked ? '✅' : '⏳',
                  style: TextStyle(fontSize: AppTextStyles.caption.fontSize),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item['type']} ${item['name']}',
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                          fontWeight: FontWeight.w500,
                          color: isChecked ? Colors.green.shade700 : null,
                          decoration: isChecked
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        item['identifier'],
                        style: TextStyle(
                          fontSize: AppTextStyles.overlineSize,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Icon gợi ý có thể nhấn để check
                if (!isChecked)
                  Icon(Icons.touch_app, size: 14, color: Colors.grey.shade400),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Confirm dialog để check thủ công 1 item
  void _showQuickCheckConfirm(Map<String, dynamic> item, bool isPhone) {
    final name = item['name'] as String;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isPhone ? Icons.phone_android : Icons.inventory_2,
              color: Colors.purple,
            ),
            const SizedBox(width: 8),
            const Expanded(child: Text('CHECK THỦ CÔNG')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đánh dấu đã kiểm cho:',
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Text(
                    item['type'] as String,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          item['identifier'] as String,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    color: Colors.orange.shade700,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Dùng khi QR bị mờ/rách và đã xác nhận bằng mắt',
                      style: TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              _manualCheckItem(item, isPhone);
            },
            icon: const Icon(Icons.check, size: 18),
            label: const Text('XÁC NHẬN ĐÃ KIỂM'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Check thủ công 1 item từ pending list
  void _manualCheckItem(Map<String, dynamic> item, bool isPhone) {
    if (isPhone) {
      // Tìm điện thoại trong danh sách expected
      final phone = _expectedPhones.firstWhere(
        (p) => p.name == item['name'],
        orElse: () => _expectedPhones.first,
      );
      if (phone.imei != null && phone.imei!.isNotEmpty) {
        final qrMap = {'imei': phone.imei!, 'type': 'DIEN_THOAI'};
        _handlePhoneScan(qrMap);
      }
    } else {
      // Tìm phụ kiện trong danh sách expected
      final acc = _expectedAccessories.firstWhere(
        (a) => a.name == item['name'],
        orElse: () => _expectedAccessories.first,
      );
      final code = acc.firestoreId ?? acc.id.toString();
      final qrMap = {'code': code, 'type': 'PHỤ KIỆN'};
      _handleAccessoryScan(qrMap);
    }
  }

  /// Add scanned item to checklist (smart grouping for accessories)
  void _addToChecklist(
    String type,
    String name,
    String identifier, {
    String? status,
  }) {
    // For accessories, check if we already have this item and update count instead of adding new
    if (type == '🔧') {
      final existingIndex = _scannedItems.indexWhere(
        (item) =>
            item['type'] == type &&
            item['name'] == name &&
            item['status'] == (status ?? '✅'),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final phoneResults = _getPhoneResults();
    final accessoryResults = _getAccessoryResults();

    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF6A1B9A), Color(0xFF9C27B0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          'KIỂM KHO NHANH',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Zone selector
          TextButton.icon(
            onPressed: () =>
                setState(() => _showZoneSelector = !_showZoneSelector),
            icon: Icon(
              _showZoneSelector ? Icons.expand_less : Icons.expand_more,
              color: Colors.white,
            ),
            label: Text(
              _currentZone?.name ?? 'Chọn Zone',
              style: TextStyle(
                color: Colors.white,
                fontSize: AppTextStyles.headline4.fontSize,
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
          IconButton(
            icon: Icon(
              _showChecklist ? Icons.checklist : Icons.checklist_outlined,
            ),
            onPressed: () => setState(() => _showChecklist = !_showChecklist),
            tooltip: _showChecklist ? 'Ẩn checklist' : 'Hiện checklist',
          ),
          // NÚT NHẬP IMEI THỦ CÔNG - cho trường hợp QR bị mờ/rách
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: _showManualInputDialog,
            tooltip: 'Nhập IMEI thủ công',
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
                _buildStatusItem(
                  '📱 Đã kiểm',
                  phoneResults['checked']!,
                  Colors.green,
                ),
                _buildStatusItem(
                  '📱 Thiếu',
                  phoneResults['missing']!,
                  Colors.red,
                ),
                _buildStatusItem(
                  '📱 Thừa',
                  phoneResults['extra']!,
                  Colors.orange,
                ),
                _buildStatusItem(
                  '🔧 Đã kiểm',
                  accessoryResults['checked']!,
                  Colors.green,
                ),
                _buildStatusItem(
                  '🔧 Thiếu',
                  accessoryResults['missing']!,
                  Colors.red,
                ),
                _buildStatusItem(
                  '🔧 Thừa',
                  accessoryResults['extra']!,
                  Colors.orange,
                ),
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
                          ? LayoutBuilder(
                              builder: (context, constraints) {
                                final scanWindow = Rect.fromCenter(
                                  center: Offset(
                                    constraints.maxWidth / 2,
                                    constraints.maxHeight / 2,
                                  ),
                                  width: constraints.maxWidth * 0.72,
                                  height: constraints.maxHeight * 0.38,
                                );

                                return Stack(
                                  children: [
                                    MobileScanner(
                                      controller: _scannerController,
                                      onDetect: _onQRDetected,
                                      scanWindow: scanWindow,
                                    ),
                                    Positioned.fromRect(
                                      rect: scanWindow,
                                      child: IgnorePointer(
                                        child: Container(
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.greenAccent,
                                              width: 2,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Positioned(
                                      right: 8,
                                      bottom: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.5),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Nút zoom + nhỏ gọn
                                            SizedBox(
                                              width: 32,
                                              height: 32,
                                              child: IconButton(
                                                onPressed: () => _setZoom(
                                                  (_zoomScale + 0.15).clamp(
                                                    0.0,
                                                    1.0,
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.add,
                                                  size: 16,
                                                ),
                                                color: Colors.white,
                                                tooltip: 'Zoom +',
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                            // Slider dọc nhỏ gọn
                                            SizedBox(
                                              height: 80,
                                              width: 28,
                                              child: RotatedBox(
                                                quarterTurns: 3,
                                                child: SliderTheme(
                                                  data: SliderThemeData(
                                                    trackHeight: 3,
                                                    thumbShape:
                                                        const RoundSliderThumbShape(
                                                          enabledThumbRadius: 6,
                                                        ),
                                                    overlayShape:
                                                        const RoundSliderOverlayShape(
                                                          overlayRadius: 12,
                                                        ),
                                                  ),
                                                  child: Slider(
                                                    value: _zoomScale,
                                                    min: 0.0,
                                                    max: 1.0,
                                                    onChanged: (v) =>
                                                        _setZoom(v),
                                                    activeColor: Colors.white,
                                                    inactiveColor:
                                                        Colors.white24,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            // Nút zoom - nhỏ gọn
                                            SizedBox(
                                              width: 32,
                                              height: 32,
                                              child: IconButton(
                                                onPressed: () => _setZoom(
                                                  (_zoomScale - 0.15).clamp(
                                                    0.0,
                                                    1.0,
                                                  ),
                                                ),
                                                icon: const Icon(
                                                  Icons.remove,
                                                  size: 16,
                                                ),
                                                color: Colors.white,
                                                tooltip: 'Zoom -',
                                                padding: EdgeInsets.zero,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.qr_code_scanner,
                                    size: 100,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Nhấn nút scan để bắt đầu kiểm kho',
                                    style: TextStyle(
                                      fontSize:
                                          AppTextStyles.headline2.fontSize,
                                      color: Colors.grey,
                                    ),
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
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Đang xử lý...',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: AppTextStyles.headline3.fontSize,
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

                // Checklist Panel - Hiện cả khi chưa scan (để xem danh sách cần kiểm)
                if (_showChecklist)
                  Container(
                    width: 220,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        left: BorderSide(color: Colors.grey.shade300),
                      ),
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
                        // Checklist Header with tabs
                        Container(
                          padding: const EdgeInsets.all(8),
                          color: Colors.blue.shade50,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  'Kho (${_checkedPhoneImeis.length + _scannedAccessoryCounts.values.fold(0, (a, b) => a + b)}/${_expectedPhones.length + _expectedAccessories.length})',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: AppTextStyles.subtitle1.fontSize,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () =>
                                    setState(() => _showChecklist = false),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),

                        // Items List - LUÔN hiện toàn bộ danh sách kho với trạng thái check
                        Expanded(child: _buildFullInventoryList()),
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
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppTextStyles.headline3.fontSize,
                    ),
                  ),
                  Text(
                    'Giữ yên QR trước camera',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: AppTextStyles.subtitle1.fontSize,
                    ),
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
            fontSize: AppTextStyles.headline1.fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: AppTextStyles.caption.fontSize,
            color: color,
          ),
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
                        color: isSelected
                            ? const Color(0xFF2962FF)
                            : Colors.grey.shade300,
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
                                  zone.isCompleted
                                      ? Icons.check_circle
                                      : Icons.location_on,
                                  color: zone.isCompleted
                                      ? Colors.green
                                      : const Color(0xFF2962FF),
                                  size: 20,
                                ),
                                const Spacer(),
                                if (isSelected)
                                  const Icon(
                                    Icons.check,
                                    color: Color(0xFF2962FF),
                                    size: 16,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              zone.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: AppTextStyles.headline4.fontSize,
                                color: isSelected
                                    ? const Color(0xFF2962FF)
                                    : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${zone.totalScanned}/${zone.totalExpected} items',
                              style: TextStyle(
                                fontSize: AppTextStyles.subtitle1.fontSize,
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
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AppTextStyles.headline4.fontSize,
                      ),
                    ),
                    Text(
                      zone.description,
                      style: TextStyle(
                        fontSize: AppTextStyles.subtitle1.fontSize,
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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppTextStyles.subtitle1.fontSize,
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
                    fontSize: AppTextStyles.subtitle1.fontSize,
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
