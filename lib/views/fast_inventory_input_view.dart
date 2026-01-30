import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/utils/money_utils.dart';
import '../controllers/fast_inventory_input_controller.dart';
import '../models/product_model.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../services/first_time_guide_service.dart';
import '../utils/imei_extractor.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/imei_scan_result_dialog.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'fast_stock_in_view.dart';

class FastInventoryInputView extends StatefulWidget {
  const FastInventoryInputView({super.key});

  @override
  State<FastInventoryInputView> createState() => _FastInventoryInputViewState();
}

class _FastInventoryInputViewState extends State<FastInventoryInputView>
    with TickerProviderStateMixin {
  final FastInventoryInputController _controller =
      FastInventoryInputController();
  late TabController _tabController;

  // Scanner
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 1000,
    formats: [BarcodeFormat.qrCode, BarcodeFormat.code128, BarcodeFormat.ean13, BarcodeFormat.ean8],
  );
  bool _isScanning = false;

  // Product data
  final TextEditingController _imeiController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _costController = TextEditingController();
  final TextEditingController _retailController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController(
    text: "1",
  );

  // SKU generation
  final String _selectedGroup = 'IP';
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _infoController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();

  // Settings
  final String _selectedType = 'DIEN_THOAI';
  String _selectedSupplier = '';
  List<Map<String, dynamic>> _suppliers = [];
  bool _isSaving = false;

  // Batch import
  final List<Map<String, dynamic>> _batchItems = [];
  bool _isBatchMode = false;

  // Recent products display
  List<Product> _recentProducts = [];
  bool _showRecent = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialData();

    // Listen for supplier changes
    EventBus().stream.listen((event) {
      if (event == 'suppliers_changed' && mounted) {
        _loadSuppliers();
      }
    });

    // Hiển thị hướng dẫn cho người dùng mới
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showGuideIfNeeded(
      context: context,
      screenKey: FirstTimeGuideService.keyFastInventoryInput,
      title: 'Nhập Nhanh (Siêu Tốc)',
      icon: Icons.flash_on,
      color: Colors.orange,
      steps: const [
        GuideStep(
          title: '📷 Quét mã liên tục',
          description: 'Quét barcode/QR nhiều sản phẩm liên tục. Hệ thống tự động điền thông tin từ thư viện.',
          icon: Icons.qr_code_scanner,
          iconColor: Colors.purple,
        ),
        GuideStep(
          title: '📝 Nhập theo lô',
          description: 'Chế độ batch cho phép quét nhiều mã rồi xác nhận 1 lần. Tiết kiệm thời gian.',
          icon: Icons.layers,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '🏢 Chọn NCC trước',
          description: 'Nhớ tạo và chọn NCC trước khi nhập. Tất cả sản phẩm sẽ được gắn với NCC đã chọn.',
          icon: Icons.store,
          iconColor: Colors.teal,
        ),
        GuideStep(
          title: '⚡ Xác nhận ngay',
          description: 'Khác với "Nhập Mới", ở đây hàng vào kho ngay sau khi nhập. Phù hợp nhập số lượng lớn.',
          icon: Icons.check_circle,
          iconColor: Colors.green,
        ),
      ],
    );
  }

  Future<void> _loadInitialData() async {
    try {
      final suppliers = await _controller.getSuppliers();
      final recentProducts = await _controller.loadRecentProducts();

      if (mounted) {
        setState(() {
          _suppliers = suppliers;
          if (_suppliers.isNotEmpty) {
            _selectedSupplier = _suppliers.first['name'] as String;
          }
          _recentProducts = recentProducts;
        });
      }
    } catch (e) {
      NotificationService.showSnackBar(
        "Lỗi tải dữ liệu: $e",
        color: AppColors.error,
      );
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await _controller.getSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = suppliers;
          if (_suppliers.isNotEmpty && _selectedSupplier.isEmpty) {
            _selectedSupplier = _suppliers.first['name'] as String;
          }
        });
      }
    } catch (e) {
      NotificationService.showSnackBar(
        "Lỗi tải nhà cung cấp: $e",
        color: AppColors.error,
      );
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    _imeiController.dispose();
    _nameController.dispose();
    _costController.dispose();
    _retailController.dispose();
    _detailController.dispose();
    _quantityController.dispose();
    _modelController.dispose();
    _infoController.dispose();
    _skuController.dispose();
    super.dispose();
  }

  void _onScanResult(BarcodeCapture capture) {
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String code = barcodes.first.rawValue ?? '';
      if (code.isNotEmpty) {
        setState(() {
          _imeiController.text = code;
          _isScanning = false;
        });
        NotificationService.showSnackBar("Đã scan: $code", color: Colors.green);
        _scannerController.stop();
      }
    }
  }

  /// Mở scanner QR/Barcode để quét IMEI - xử lý thông minh QR nhiều dòng
  void _openQRScannerForIMEI() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _IMEIScannerSheet(
        onIMEISelected: (imei) {
          setState(() {
            _imeiController.text = imei;
          });
        },
      ),
    );
  }

  Future<void> _saveBatch() async {
    if (_batchItems.isEmpty) return;

    setState(() => _isSaving = true);

    try {
      // Parallel processing for better performance
      await _controller.saveBatchProducts(_batchItems);

      setState(() => _batchItems.clear());
      NotificationService.showSnackBar(
        "Đã nhập kho ${_batchItems.length} sản phẩm thành công!",
        color: Colors.green,
      );
      HapticFeedback.lightImpact();

      // Parallel refresh
      await _refreshRecentProducts();

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      NotificationService.showSnackBar(
        "Lỗi khi nhập batch: $e",
        color: Colors.red,
      );
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _refreshRecentProducts() async {
    try {
      final recentProducts = await _controller.loadRecentProducts();
      if (mounted) {
        setState(() => _recentProducts = recentProducts);
      }
    } catch (e) {
      // Silent fail for refresh
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
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
          "NHẬP KHO SIÊU TỐC",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.add_circle, size: 18), text: "Nhập"),
            Tab(icon: Icon(Icons.qr_code_scanner, size: 18), text: "Scan"),
            Tab(icon: Icon(Icons.inventory, size: 18), text: "Batch"),
          ],
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
        ),
        actions: [
          IconButton(
            onPressed: () => setState(() => _showRecent = !_showRecent),
            icon: Icon(_showRecent ? Icons.history : Icons.history_outlined),
            tooltip: _showRecent
                ? "Ẩn sản phẩm gần đây"
                : "Hiện sản phẩm gần đây",
          ),
          if (_isBatchMode && _batchItems.isNotEmpty)
            IconButton(
              onPressed: _saveBatch,
              icon: const Icon(Icons.save, color: Colors.green),
              tooltip: "Lưu batch",
            ),
          IconButton(
            onPressed: () => setState(() => _isBatchMode = !_isBatchMode),
            icon: Icon(
              _isBatchMode
                  ? Icons.batch_prediction
                  : Icons.batch_prediction_outlined,
              color: _isBatchMode ? Colors.blue : Colors.grey,
            ),
            tooltip: _isBatchMode ? "Tắt chế độ batch" : "Bật chế độ batch",
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab "Nhập đơn" sử dụng FastStockInView embedded (không có Scaffold)
          _buildFastStockInEmbedded(),
          _buildScannerTab(),
          _buildBatchTab(),
        ],
      ),
    );
  }

  /// Build embedded FastStockInView without Scaffold for tab integration
  Widget _buildFastStockInEmbedded() {
    // Use the FastStockInView in embedded mode (no Scaffold/AppBar)
    return const FastStockInView(embedded: true);
  }

  Widget _buildScannerTab() {
    return Column(
      children: [
        Expanded(
          child: _isScanning
              ? MobileScanner(
                  controller: _scannerController,
                  onDetect: _onScanResult,
                )
              : Container(
                  color: Colors.black,
                  child: const Center(
                    child: Text(
                      "Camera chưa được khởi động",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        setState(() => _isScanning = !_isScanning);
                        if (_isScanning) {
                          _scannerController.start();
                        } else {
                          _scannerController.stop();
                        }
                      },
                      icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow),
                      label: Text(_isScanning ? "DỪNG SCAN" : "BẮT ĐẦU SCAN"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isScanning
                            ? Colors.red
                            : Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: () => _scannerController.toggleTorch(),
                    icon: const Icon(Icons.flashlight_on),
                    tooltip: "Bật/tắt đèn flash",
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ValidatedTextField(
                      controller: _imeiController,
                      label: "IMEI/Serial (có thể nhập thủ công)",
                      icon: Icons.fingerprint,
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _openQRScannerForIMEI,
                    icon: const Icon(
                      Icons.qr_code_scanner,
                      color: Colors.green,
                    ),
                    tooltip: 'Quét QR lấy 5 số cuối IMEI',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.withOpacity(0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBatchTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "DANH SÁCH BATCH (${_batchItems.length})",
                style: AppTextStyles.headline6.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              if (_batchItems.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _saveBatch,
                  icon: const Icon(Icons.save, color: AppColors.onSuccess),
                  label: Text("LƯU TẤT CẢ", style: AppTextStyles.button),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: AppColors.onSuccess,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _batchItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 80,
                        color: Colors.grey,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Chưa có sản phẩm nào trong batch",
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Chuyển sang tab 'Nhập đơn' và bật chế độ batch",
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.onSurface.withOpacity(0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _batchItems.length,
                  itemBuilder: (context, index) {
                    final item = _batchItems[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(item['name']),
                        subtitle: Text(
                          "IMEI: ${item['imei']} • Giá: ${MoneyUtils.formatVND(item['price'])}đ",
                        ),
                        trailing: IconButton(
                          onPressed: () =>
                              setState(() => _batchItems.removeAt(index)),
                          icon: const Icon(Icons.delete, color: Colors.red),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ============================================================
// IMEI SCANNER SHEET - Xử lý thông minh QR nhiều dòng
// ============================================================

class _IMEIScannerSheet extends StatefulWidget {
  final Function(String imei) onIMEISelected;

  const _IMEIScannerSheet({required this.onIMEISelected});

  @override
  State<_IMEIScannerSheet> createState() => _IMEIScannerSheetState();
}

class _IMEIScannerSheetState extends State<_IMEIScannerSheet> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  String? _lastScannedData;
  DateTime? _lastScanTime;

  // Delay trước khi bắt đầu scan (2-3 giây để user chuẩn bị)
  bool _isScanReady = false;
  int _countdownSeconds = 2;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionTimeoutMs: 500,
      returnImage: false,
    );
    // Bắt đầu countdown trước khi scan
    _startCountdown();
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() => _countdownSeconds = 1);
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        setState(() {
          _countdownSeconds = 0;
          _isScanReady = true;
        });
      });
    });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    // Chờ countdown xong mới cho scan
    if (!_isScanReady) return;
    if (_isProcessing) return;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final rawValue = barcodes.first.rawValue ?? '';
    if (rawValue.isEmpty) return;

    // Debounce: Tránh quét trùng trong 2 giây
    final now = DateTime.now();
    if (_lastScannedData == rawValue &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
      return;
    }

    _lastScannedData = rawValue;
    _lastScanTime = now;

    setState(() => _isProcessing = true);

    try {
      // Trích xuất IMEI từ QR data
      final result = IMEIExtractor.extract(rawValue);

      // Nếu có 1 IMEI duy nhất và không phải multi-line phức tạp
      if (result.candidates.length == 1 && !result.isMultiLine) {
        // Auto-select với 5 số cuối
        final imei = result.candidates.first;
        final last5 = IMEIExtractor.getLast5Digits(imei);

        Navigator.of(context).pop();
        widget.onIMEISelected(last5);
        NotificationService.showSnackBar(
          '✅ IMEI: ${IMEIExtractor.formatIMEI(imei)} → 5 số cuối: $last5',
          color: Colors.green,
        );
      }
      // Nếu có nhiều candidates hoặc QR phức tạp -> hiện dialog chọn
      else if (result.candidates.isNotEmpty) {
        // Tạm dừng camera
        await _controller?.stop();

        if (!mounted) return;

        // Hiện dialog chọn IMEI
        final selected = await IMEIScanResultDialog.show(context, result);

        if (selected != null && selected.isNotEmpty) {
          Navigator.of(context).pop();
          widget.onIMEISelected(selected);
          NotificationService.showSnackBar(
            '✅ Đã chọn: $selected',
            color: Colors.green,
          );
        } else {
          // User đóng dialog, resume camera
          await _controller?.start();
        }
      }
      // Không tìm thấy IMEI -> thử lấy raw digits
      else {
        // Fallback: lấy 5 số cuối từ raw data
        final digitsOnly = rawValue.replaceAll(RegExp(r'[^0-9]'), '');
        if (digitsOnly.length >= 5) {
          final last5 = digitsOnly.substring(digitsOnly.length - 5);

          Navigator.of(context).pop();
          widget.onIMEISelected(last5);
          NotificationService.showSnackBar(
            '⚠️ Không tìm thấy IMEI, dùng 5 số cuối: $last5',
            color: Colors.orange,
          );
        } else {
          NotificationService.showSnackBar(
            '❌ Không tìm thấy số IMEI trong QR',
            color: Colors.red,
          );
        }
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi xử lý QR: $e', color: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.qr_code_scanner, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'QUÉT QR/BARCODE IMEI',
                      style: TextStyle(
                        fontSize: AppTextStyles.headline3.fontSize,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
          ),

          // Hướng dẫn
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 20, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hỗ trợ QR nhiều dòng (Apple, Samsung...).\n'
                    'Tự động trích xuất IMEI và cho phép chọn nếu có nhiều số.',
                    style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize, color: Colors.blue),
                  ),
                ),
              ],
            ),
          ),

          // Scanner area với overlay
          Expanded(
            child: Stack(
              children: [
                // Camera
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                  ),
                ),

                // Countdown overlay khi chưa sẵn sàng
                if (!_isScanReady)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.hourglass_top,
                            size: 48,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _countdownSeconds > 0
                                ? 'Chuẩn bị...\n$_countdownSeconds'
                                : 'Sẵn sàng!',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: AppTextStyles.headline1.fontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Hướng camera vào mã QR',
                            style: TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Scan area overlay
                Center(
                  child: Container(
                    width: 280,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.green, width: 3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.center_focus_weak,
                          size: 40,
                          color: Colors.green,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Đưa mã QR/Barcode vào khung',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppTextStyles.subtitle1.fontSize,
                            shadows: [
                              Shadow(color: Colors.black, blurRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Processing indicator
                if (_isProcessing)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 16),
                          Text(
                            'Đang xử lý...',
                            style: TextStyle(color: Colors.white, fontSize: AppTextStyles.headline4.fontSize),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Bottom controls
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Torch button
                IconButton(
                  onPressed: () => _controller?.toggleTorch(),
                  icon: const Icon(Icons.flashlight_on),
                  tooltip: 'Bật/tắt đèn flash',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
                const SizedBox(width: 12),
                // Switch camera button
                IconButton(
                  onPressed: () => _controller?.switchCamera(),
                  icon: const Icon(Icons.cameraswitch),
                  tooltip: 'Đổi camera',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade200,
                  ),
                ),
                const Spacer(),
                // Manual input button
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    // Trả về empty để user biết cần nhập thủ công
                    widget.onIMEISelected('');
                  },
                  icon: const Icon(Icons.keyboard),
                  label: const Text('Nhập thủ công'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
