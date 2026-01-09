import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/utils/money_utils.dart';
import '../controllers/fast_inventory_input_controller.dart';
import '../models/product_model.dart';
import '../services/notification_service.dart';
import '../services/event_bus.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/validated_text_field.dart';
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
  final MobileScannerController _scannerController = MobileScannerController();
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
  String _selectedGroup = 'IP';
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _infoController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();

  // Settings
  String _selectedType = 'PHONE';
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

  /// Mở scanner QR/Barcode để quét IMEI - chỉ quét 1 lần, lấy 5 số cuối
  void _openQRScannerForIMEI() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
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
                  const Text(
                    'QUÉT QR/BARCODE IMEI',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Hướng camera vào mã QR hoặc Barcode IMEI.\nChỉ lấy 5 số cuối để nhập vào trường IMEI.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ),
            // Scanner
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: MobileScanner(
                  controller: MobileScannerController(
                    detectionTimeoutMs: 1000,
                    returnImage: false,
                  ),
                  onDetect: (capture) {
                    final barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final rawValue = barcodes.first.rawValue ?? '';
                      if (rawValue.isNotEmpty) {
                        // Lấy 5 số cuối từ IMEI
                        final digitsOnly = rawValue.replaceAll(
                          RegExp(r'[^0-9]'),
                          '',
                        );
                        final last5 = digitsOnly.length >= 5
                            ? digitsOnly.substring(digitsOnly.length - 5)
                            : digitsOnly;

                        // Đóng scanner và set IMEI
                        Navigator.pop(ctx);
                        setState(() {
                          _imeiController.text = last5;
                        });
                        NotificationService.showSnackBar(
                          'Đã quét: $rawValue → 5 số cuối: $last5',
                          color: Colors.green,
                        );
                      }
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
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
        title: Text(
          "NHẬP KHO SIÊU TỐC",
          style: AppTextStyles.headline6.copyWith(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.add_circle), text: "Nhập đơn"),
            Tab(icon: Icon(Icons.qr_code_scanner), text: "Scan QR"),
            Tab(icon: Icon(Icons.inventory), text: "Batch"),
          ],
          labelColor: const Color(0xFF2962FF),
          unselectedLabelColor: Colors.grey,
          indicatorColor: const Color(0xFF2962FF),
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
                  icon: Icon(Icons.save, color: AppColors.onSuccess),
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
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 80,
                        color: Colors.grey,
                      ),
                      SizedBox(height: 16),
                      Text(
                        "Chưa có sản phẩm nào trong batch",
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.onSurface.withOpacity(0.6),
                        ),
                      ),
                      SizedBox(height: 8),
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
