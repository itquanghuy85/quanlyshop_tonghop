import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_write_helper.dart';
import '../utils/money_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/db_helper.dart';
import '../constants/product_constants.dart';
import '../utils/vietnamese_utils.dart';
import '../models/product_model.dart';
import '../models/inventory_check_model.dart';
import '../models/payment_intent_model.dart';
import '../constants/financial_constants.dart';
import 'create_sale_view.dart';
import '../services/sync_orchestrator.dart';
import '../services/sync_service.dart';
import '../services/unified_printer_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/event_bus.dart';
import '../services/supplier_service.dart';
import '../services/firestore_service.dart';
import '../services/first_time_guide_service.dart';
import '../services/payment_intent_service.dart';
import '../services/variant_service.dart';
import 'supplier_list_view.dart';
import '../utils/sku_generator.dart';
import '../widgets/printer_selection_dialog.dart';
import '../widgets/variant_selector.dart';
import '../models/printer_types.dart';
import 'smart_stock_in_view.dart';
import 'global_search_view.dart';
import 'fast_stock_in_view.dart';
import 'parts_inventory_view.dart';
import 'pty_print_designer_view.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/validated_text_field.dart';
import '../models/stock_entry_model.dart';
import '../services/stock_entry_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import '../widgets/custom_app_bar.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../models/shop_settings_model.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/export_date_filter_dialog.dart';
import '../widgets/responsive_wrapper.dart';

class InventoryView extends StatefulWidget {
  final String role;
  final String initialFilterType;
  const InventoryView({
    super.key,
    required this.role,
    this.initialFilterType = 'TẤT CẢ',
  });
  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView>
    with TickerProviderStateMixin {
  final db = DBHelper();
  final supplierService = SupplierService();
  List<Product> _products = [];
  List<Product> _allLoadedProducts = []; // Cache for filtering
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentOffset = 0;
  static const int _pageSize =
      10; // Load 10 products at a time for better performance
  int _unsyncedCount = 0;
  bool _isAdmin = false; // Used in _init for permission check
  bool _canViewCostPrice = false; // Phân quyền xem giá vốn

  // Total inventory summary from DB (not from paginated data)
  int _totalQtyFromDB = 0;
  int _totalCapitalFromDB = 0;
  bool _hasInventoryAccess = false;
  String _searchQuery = "";
  bool _showOutOfStock = false; // Hiển thị cả hàng hết
  String _filterType =
      'TẤT CẢ'; // Filter theo loại: TẤT CẢ, DIEN_THOAI, PHỤ KIỆN, LINH_KIEN
  int _repairPartsCount = 0; // Count for repair parts tab chip

  // ScrollController for lazy loading
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<String>? _inventoryEventSub;
  Timer? _inventoryRefreshDebounce;

  final Set<String> _inventoryRefreshEvents = {
    'sales_changed',
    'sales_returns_changed',
    'products_changed',
    'stock_entries_changed',
    'sync_now_completed',
    'app_resumed',
    EventBus.dataRefresh,
    EventBus.shopChanged,
  };

  /// Check if we need full data (for filtering)
  bool get _needsFullData =>
      _searchQuery.isNotEmpty || _filterType != 'TẤT CẢ' || _showOutOfStock;

  final Set<int> _selectedIds = {};
  bool _isSelectionMode = false;

  // Tab controller
  late TabController _tabController;

  // Inventory check variables
  String _selectedType = 'DIEN_THOAI';
  List<Map<String, dynamic>> _items = [];
  List<InventoryCheckItem> _checkItems = [];
  bool _isCheckingLoading = false;
  bool _isScanning = false;
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 1000,
    formats: [BarcodeFormat.all],
  );
  InventoryCheck? _currentCheck;

  // Layout sizing constants (iconSize, smallFontSize, btnMinHeight are in use)
  final double _iconSize = 20.0;
  final double _smallFontSize = 11.0;
  final double _btnMinHeight = 44.0;

  // Phase 2: Multi-Industry - Shop Settings
  ShopSettings? _shopSettings;
  bool get _enableExpiry => _shopSettings?.enableExpiry ?? false;
  bool get _enableBatch => _shopSettings?.enableBatch ?? false;
  bool get _enableSerial => _shopSettings?.enableSerial ?? true;
  bool get _enableVariants => _shopSettings?.enableVariants ?? false;
  bool get _enableRepair => _shopSettings?.enableRepair ?? true;
  String get _businessType => _shopSettings?.businessType ?? 'electronics';
  bool get _isFashion => _businessType == 'fashion';
  bool get _isElectronics => _businessType == 'electronics';

  // Variant Service for fashion products
  final VariantService _variantService = VariantService();

  /// Terminology động theo ngành
  BusinessTerminology get _terms =>
      BusinessTypeHelper.instance.getTerminology(_shopSettings);

  @override
  void initState() {
    super.initState();
    _filterType = widget.initialFilterType;
    _tabController = TabController(length: 1, vsync: this);
    _bindInventoryRefreshEvents();
    _init(); // _init sẽ gọi _initCheckData sau khi load shop settings
    // Setup scroll listener for lazy loading
    _scrollController.addListener(_onScroll);
    // Hiển thị hướng dẫn cho người dùng mới
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showFirstTimeGuide();
    });
  }

  /// Hiển thị hướng dẫn lần đầu
  Future<void> _showFirstTimeGuide() async {
    await FirstTimeGuideService.showGuideIfNeeded(
      context: context,
      screenKey: FirstTimeGuideService.keyProductList,
      title: 'Danh Sách ${_terms.productLabel}',
      icon: Icons.inventory_2,
      color: Colors.blue,
      steps: [
        GuideStep(
          title: '📦 Tồn kho hiện tại',
          description:
              'Danh sách tất cả ${_terms.productLabel.toLowerCase()} trong kho. Lọc theo loại hoặc tìm kiếm nhanh.',
          icon: Icons.list,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '🔍 Tìm kiếm',
          description:
              'Nhấn icon kính lúp để tìm theo tên, ${_terms.specialField1Label}, SKU. Hỗ trợ tìm kiếm toàn cục.',
          icon: Icons.search,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '🛒 Bán hàng nhanh',
          description:
              'Nhấn vào ${_terms.productLabel.toLowerCase()} để xem chi tiết, hoặc vuốt để bán nhanh/in tem.',
          icon: Icons.shopping_cart,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '✏️ Chỉnh sửa giá',
          description:
              'Admin có thể chỉnh sửa giá bán, giá nhập trực tiếp từ chi tiết ${_terms.productLabel.toLowerCase()}.',
          icon: Icons.edit,
          iconColor: Colors.orange,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _inventoryRefreshDebounce?.cancel();
    _inventoryEventSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _bindInventoryRefreshEvents() {
    _inventoryEventSub?.cancel();
    _inventoryEventSub = EventBus().stream
        .where((event) => _inventoryRefreshEvents.contains(event))
        .listen((event) {
          if (!mounted) return;

          final shouldRefreshCloud =
              event == 'stock_entries_changed' ||
              event == 'sales_returns_changed';
          if (shouldRefreshCloud) {
            unawaited(
              SyncService.refreshCloudCollections(
                reason: 'inventory_view_$event',
                force: true,
              ),
            );
          }

          _inventoryRefreshDebounce?.cancel();
          _inventoryRefreshDebounce = Timer(
            Duration(milliseconds: shouldRefreshCloud ? 600 : 220),
            () async {
              if (!mounted) return;
              await _refreshLocalData();
            },
          );
        });
  }

  void _onScroll() {
    if (!mounted) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMoreIfNeeded();
    }
  }

  Future<void> _loadMoreIfNeeded() async {
    if (_isLoadingMore || !_hasMore || _needsFullData) return;
    if (!mounted) return;
    setState(() => _isLoadingMore = true);

    try {
      final newData = await db.getProductsPaged(_pageSize, _currentOffset);
      if (mounted) {
        setState(() {
          _allLoadedProducts.addAll(newData);
          _products = _allLoadedProducts;
          _currentOffset += _pageSize;
          _isLoadingMore = false;
          _hasMore = newData.length >= _pageSize;
        });
      }
    } catch (e) {
      debugPrint('InventoryView: Error loading more: $e');
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Widget _input(
    TextEditingController c,
    String l,
    IconData i, {
    FocusNode? f,
    FocusNode? next,
    TextInputType type = TextInputType.text,
    String? suffix,
    bool caps = false,
    bool isBig = false,
    bool readOnly = false,
  }) {
    if (type == TextInputType.number &&
        (l.contains('GIÁ') || l.contains('TIỀN') || suffix == 'k')) {
      // Use CurrencyTextField for price fields
      bool multiply = !(l.contains('GIÁ NHẬP') || l.contains('GIÁ BÁN'));
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: CurrencyTextField(
          controller: c,
          label: l,
          icon: i,
          autoMultiply1000: multiply,
          onSubmitted: () {
            if (next != null) FocusScope.of(context).requestFocus(next);
          },
        ),
      );
    } else {
      // Use ValidatedTextField for text fields
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: ValidatedTextField(
          controller: c,
          label: l,
          icon: i,
          keyboardType: type,
          uppercase: caps,
          onSubmitted: () {
            if (next != null) FocusScope.of(context).requestFocus(next);
          },
        ),
      );
    }
  }

  /// Auto-fix paymentMethod cho sản phẩm cũ thiếu thông tin
  Future<void> _autoFixProductPaymentMethod(Product p) async {
    try {
      String paymentMethod = 'TIỀN MẶT'; // Default

      // Lấy từ Firestore để kiểm tra stockEntryId
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(p.firestoreId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        final stockEntryId = data['stockEntryId'] as String?;

        if (stockEntryId != null) {
          // Lấy paymentMethod từ stock_entries
          final entryDoc = await FirebaseFirestore.instance
              .collection('stock_entries')
              .doc(stockEntryId)
              .get();
          if (entryDoc.exists) {
            paymentMethod = entryDoc.data()?['paymentMethod'] ?? 'TIỀN MẶT';
          }
        } else if (data['supplierId'] != null) {
          // Nếu có supplierId, kiểm tra có debt không
          final debtSnap = await FirebaseFirestore.instance
              .collection('supplier_debts')
              .where('supplierId', isEqualTo: data['supplierId'])
              .limit(1)
              .get();
          if (debtSnap.docs.isNotEmpty) {
            paymentMethod = 'CÔNG NỢ';
          }
        }

        // Cập nhật Firestore
        await FirebaseFirestore.instance
            .collection('products')
            .doc(p.firestoreId)
            .update({
              'paymentMethod': paymentMethod,
              'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
            });

        // Cập nhật local
        p.paymentMethod = paymentMethod;
        await db.upsertProduct(p);

        debugPrint('✅ Auto-fixed paymentMethod for ${p.name}: $paymentMethod');
      }
    } catch (e) {
      debugPrint('⚠️ Error auto-fixing paymentMethod: $e');
    }
  }

  void _showProductDetail(Product p) async {
    HapticFeedback.lightImpact();

    // Auto-fix paymentMethod cho sản phẩm cũ nếu thiếu
    if (p.paymentMethod == null && !p.isPending && p.firestoreId != null) {
      await _autoFixProductPaymentMethod(p);
    }

    // Reload product từ Firestore để đảm bảo có data mới nhất
    Product displayProduct = p;
    if (p.firestoreId != null && !p.isPending) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('products')
            .doc(p.firestoreId)
            .get();
        if (doc.exists) {
          final data = doc.data()!;
          // Cập nhật cost, price, paymentMethod từ Firestore
          displayProduct = p.copyWith(
            cost: data['cost'] is int
                ? data['cost']
                : (data['cost'] is double
                      ? (data['cost'] as double).toInt()
                      : p.cost),
            price: data['price'] is int
                ? data['price']
                : (data['price'] is double
                      ? (data['price'] as double).toInt()
                      : p.price),
            paymentMethod: data['paymentMethod'] as String? ?? p.paymentMethod,
            supplier: data['supplier'] as String? ?? p.supplier,
          );

          // Sync lại vào local DB nếu khác
          if (displayProduct.cost != p.cost ||
              displayProduct.price != p.price) {
            await db.upsertProduct(displayProduct);
            debugPrint(
              '✅ Synced product ${p.name}: cost=${displayProduct.cost}, price=${displayProduct.price}',
            );
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error loading product from Firestore: $e');
      }
    }

    final repairs = await db.getRepairsByImei(displayProduct.imei ?? '');
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Banner KHO TẠM nếu sản phẩm pending
            if (displayProduct.isPending) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_empty,
                      color: Colors.orange.shade700,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'KHO TẠM - Chờ xác nhận giá',
                            style: AppTextStyles.headline4.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                          if (displayProduct.pendingSupplier != null)
                            Text(
                              'NCC dự kiến: ${displayProduct.pendingSupplier}',
                              style: AppTextStyles.subtitle1.copyWith(
                                color: Colors.orange.shade600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            Text(
              displayProduct.name,
              style: AppTextStyles.headline3.copyWith(
                fontWeight: FontWeight.bold,
                color: displayProduct.isPending
                    ? Colors.orange.shade800
                    : const Color(0xFF2962FF),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
            // Show capacity/size based on business type
            if (_isElectronics)
              _detailItem("Chi tiết máy", displayProduct.capacity ?? "")
            else if (_isFashion &&
                (displayProduct.capacity?.isNotEmpty ?? false))
              _detailItem("Size", displayProduct.capacity ?? ""),
            if (_enableSerial)
              _detailItem(
                _terms.specialField1Label,
                displayProduct.imei ?? "N/A",
              ),
            _detailItem(
              "Nhà cung cấp",
              displayProduct.isPending
                  ? (displayProduct.pendingSupplier ?? "Chưa xác nhận")
                  : (displayProduct.supplier ?? "N/A"),
            ),
            if (_canViewCostPrice)
              _detailItem(
                "Giá nhập",
                displayProduct.isPending
                    ? "Chờ xác nhận"
                    : "${MoneyUtils.formatCurrency(displayProduct.cost)} đ",
                color: displayProduct.isPending ? Colors.orange : null,
              ),
            _detailItem(
              "Giá bán",
              displayProduct.isPending
                  ? "Chờ xác nhận"
                  : "${MoneyUtils.formatCurrency(displayProduct.price)} đ",
              color: displayProduct.isPending ? Colors.orange : Colors.red,
            ),
            _detailItem(
              "Thanh toán",
              displayProduct.isPending
                  ? "Chờ xác nhận"
                  : (displayProduct.paymentMethod ?? "N/A"),
            ),
            if (displayProduct.labelNote != null &&
                displayProduct.labelNote!.isNotEmpty)
              _detailItem("Ghi chú", displayProduct.labelNote!),
            _detailItem(
              "Cập nhật cuối",
              displayProduct.updatedAt != null
                  ? DateFormat('dd/MM/yyyy HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(
                        displayProduct.updatedAt!,
                      ),
                    )
                  : "N/A",
              color: Colors.grey,
            ),
            if (repairs.isNotEmpty && _enableRepair) ...[
              const Divider(height: 30),
              Text(
                "LỊCH SỬ SỬA CHỮA",
                style: AppTextStyles.headline3.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF2962FF),
                ),
              ),
              const SizedBox(height: 10),
              ...repairs.map(
                (r) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Khách: ${r.customerName}",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text("Vấn đề: ${r.issue}"),
                      Text(
                        "Trạng thái: ${_getStatusText(r.status)}",
                        style: TextStyle(color: _getStatusColor(r.status)),
                      ),
                      Text(
                        "Ngày nhận: ${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(r.createdAt))}",
                        style: AppTextStyles.subtitle1.copyWith(
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const Divider(height: 30),
            // Nút XÁC NHẬN GIÁ cho kho tạm
            if (p.isPending) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showConfirmCostDialog(p);
                  },
                  icon: const Icon(Icons.check_circle, color: Colors.white),
                  label: Text(
                    "XÁC NHẬN GIÁ - CHUYỂN KHO CHÍNH",
                    style: AppTextStyles.headline5.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Quick stock-in button for PHU_KIEN / LINH_KIEN
            if (p.type == 'PHU_KIEN' || p.type == 'LINH_KIEN') ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showQuickStockInDialog(p);
                  },
                  icon: const Icon(
                    Icons.add_shopping_cart,
                    color: Colors.white,
                  ),
                  label: Text(
                    'NHẬP THÊM (${p.quantity} trong kho)',
                    style: AppTextStyles.subtitle1.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      // Hiện popup chọn máy in
                      final printerConfig = await showPrinterSelectionDialog(
                        context,
                      );
                      if (printerConfig == null) return; // User hủy

                      final printerType = printerConfig['type'] as PrinterType?;
                      final bluetoothPrinter =
                          printerConfig['bluetoothPrinter'];
                      final wifiIp = printerConfig['wifiIp'] as String?;

                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đang in tem...'),
                          duration: Duration(seconds: 1),
                        ),
                      );

                      // In tem theo cài đặt từ THIẾT KẾ TEM
                      final ok =
                          await UnifiedPrinterService.printProductQRLabel(
                            p.toMap(),
                            printerType: printerType,
                            bluetoothPrinter: bluetoothPrinter,
                            customMac: bluetoothPrinter is Map
                                ? bluetoothPrinter['macAddress']
                                : null,
                            wifiIp: wifiIp,
                          );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok ? '✅ In tem thành công!' : '❌ Lỗi khi in tem',
                            ),
                            backgroundColor: ok ? Colors.green : Colors.red,
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.qr_code_2, color: Colors.white),
                    label: Text(
                      "IN TEM",
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _editProduct(p);
                    },
                    icon: const Icon(Icons.edit, color: Colors.white),
                    label: Text(
                      "SỬA",
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _createSaleOrder(p);
                    },
                    icon: const Icon(Icons.shopping_cart, color: Colors.white),
                    label: Text(
                      "BÁN",
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2962FF),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                    label: Text("ĐÓNG", style: AppTextStyles.caption),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      minimumSize: const Size(0, 36),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Quick stock-in dialog for PHU_KIEN / LINH_KIEN
  void _showQuickStockInDialog(Product p) {
    final qtyCtrl = TextEditingController(text: '1');
    final costCtrl = TextEditingController(
      text: p.cost > 0 ? p.cost.toString() : '',
    );
    String paymentMethod = 'TIỀN MẶT';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.add_shopping_cart, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'NHẬP THÊM',
                    style: AppTextStyles.headline3.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: responsiveDialogWidth(context),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Text(
                          p.type == 'LINH_KIEN' ? '🔧' : '🎧',
                          style: const TextStyle(fontSize: 24),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                p.name,
                                style: AppTextStyles.headline4.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Tồn kho hiện tại: ${p.quantity}',
                                style: AppTextStyles.subtitle1.copyWith(
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Quantity
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Số lượng nhập thêm',
                      prefixIcon: const Icon(Icons.add_circle_outline),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Cost price
                  CurrencyTextField(
                    controller: costCtrl,
                    label: 'Giá nhập (VNĐ)',
                    icon: Icons.attach_money,
                  ),
                  const SizedBox(height: 12),
                  // Payment method
                  DropdownButtonFormField<String>(
                    value: paymentMethod,
                    decoration: InputDecoration(
                      labelText: 'Phương thức thanh toán',
                      prefixIcon: const Icon(Icons.payment),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'TIỀN MẶT',
                        child: Text('Tiền mặt'),
                      ),
                      DropdownMenuItem(
                        value: 'CHUYỂN KHOẢN',
                        child: Text('Chuyển khoản'),
                      ),
                      DropdownMenuItem(
                        value: 'CÔNG NỢ',
                        child: Text('Công nợ'),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => paymentMethod = v!),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('HỦY'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, color: Colors.white),
                label: const Text(
                  'NHẬP KHO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () async {
                  final qty = int.tryParse(qtyCtrl.text) ?? 0;
                  if (qty <= 0) {
                    NotificationService.showSnackBar(
                      'Vui lòng nhập số lượng hợp lệ',
                      color: Colors.red,
                    );
                    return;
                  }
                  final cost = CurrencyTextField.parseValue(costCtrl.text);
                  if (cost <= 0) {
                    NotificationService.showSnackBar(
                      'Vui lòng nhập giá nhập hợp lệ',
                      color: Colors.red,
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  await _processQuickStockIn(p, qty, cost, paymentMethod);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _processQuickStockIn(
    Product p,
    int qty,
    int cost,
    String paymentMethod,
  ) async {
    try {
      NotificationService.showSnackBar('Đang nhập kho...', color: Colors.blue);
      final shopId = await UserService.getCurrentShopId() ?? '';
      final service = StockEntryService();

      // Create a stock entry for audit trail and financial tracking
      final entry = StockEntry(
        shopId: shopId,
        status: StockEntryStatus.draft,
        entryType: StockEntryType.quick,
        paymentMethod: paymentMethod,
        supplierName: p.supplier,
        items: [
          StockEntryItem(
            name: p.name,
            quantity: qty,
            cost: cost.toDouble(),
            price: p.price.toDouble(),
            productType: p.type,
            brand: p.brand,
            model: p.model,
            capacity: p.capacity,
            color: p.color,
            sku: p.sku,
            unit: p.unit,
            size: p.size,
          ),
        ],
      );

      final created = await service.createEntry(entry);
      if (created == null || created.firestoreId == null) {
        NotificationService.showSnackBar(
          'Lỗi tạo phiếu nhập kho',
          color: Colors.red,
        );
        return;
      }

      // Auto-confirm entry to update stock + financial records
      final confirmed = await service.confirmEntry(created.firestoreId!);
      if (confirmed) {
        NotificationService.showSnackBar(
          '✅ Đã nhập thêm $qty ${p.name} vào kho',
          color: Colors.green,
        );
        // Force sync to reflect new quantities
        await SyncOrchestrator().syncAll();
        _refresh();
      } else {
        NotificationService.showSnackBar(
          'Lỗi xác nhận phiếu nhập kho',
          color: Colors.red,
        );
      }
    } catch (e) {
      debugPrint('Quick stock-in error: $e');
      NotificationService.showSnackBar('Lỗi: $e', color: Colors.red);
    }
  }

  void _createSaleOrder(Product p) {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateSaleView(preSelectedProduct: p)),
    ).then((_) => _refresh());
  }

  void _showEditProductDialog(Product p) {
    // Tách model riêng, brand riêng
    String? selectedBrand = ProductConstants.mapBrand(p.brand);
    final modelCtrl = TextEditingController(text: p.model ?? '');
    final capacityCtrl = TextEditingController(
      text: ProductConstants.mapCapacity(p.capacity),
    );
    final colorCtrl = TextEditingController(
      text: ProductConstants.mapColor(p.color),
    );
    final imeiCtrl = TextEditingController(text: p.imei ?? '');
    final supplierCtrl = TextEditingController(text: p.supplier ?? '');
    final costCtrl = TextEditingController(
      text: MoneyUtils.formatCurrency(p.cost),
    );
    final priceCtrl = TextEditingController(
      text: MoneyUtils.formatCurrency(p.price),
    );
    final quantityCtrl = TextEditingController(text: p.quantity.toString());

    // Kiểm tra xem có được sửa giá vốn/NCC không
    // Chỉ được sửa nếu: còn trong kho tạm (isPending) VÀ chưa bán (status == 1)
    final canEditFinancialInfo = p.isPending && p.status == 1;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text('Chỉnh sửa ${_terms.productLabel.toLowerCase()}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Hãng
                DropdownButtonFormField<String>(
                  value: ProductConstants.brands.contains(selectedBrand)
                      ? selectedBrand
                      : null,
                  decoration: const InputDecoration(
                    labelText: "Hãng *",
                    prefixIcon: Icon(Icons.business, size: 18),
                    border: OutlineInputBorder(),
                  ),
                  items: ProductConstants.brands
                      .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                      .toList(),
                  onChanged: (v) => setS(() => selectedBrand = v),
                ),
                const SizedBox(height: 12),
                // Model
                ValidatedTextField(
                  controller: modelCtrl,
                  label: 'Model (VD: 15 PRO MAX)',
                  uppercase: true,
                  customValidator: (val) =>
                      val.isEmpty ? 'Vui lòng nhập model' : null,
                ),
                const SizedBox(height: 12),
                // Dung lượng/Size - chỉ hiển thị cho electronics hoặc fashion
                if (_isElectronics || _isFashion)
                  ValidatedTextField(
                    controller: capacityCtrl,
                    label: _isFashion ? 'Size' : 'Dung lượng (VD: 256GB)',
                    uppercase: true,
                  ),
                if (_isElectronics || _isFashion) const SizedBox(height: 12),
                ValidatedTextField(
                  controller: colorCtrl,
                  label: 'Màu sắc',
                  uppercase: true,
                ),
                const SizedBox(height: 12),
                if (_enableSerial) ...[
                  ValidatedTextField(
                    controller: imeiCtrl,
                    label: _terms.specialField1Label,
                  ),
                  const SizedBox(height: 12),
                ],
                // Nhà cung cấp - KHÓA nếu đã nhập kho chính
                if (canEditFinancialInfo)
                  ValidatedTextField(
                    controller: supplierCtrl,
                    label: 'Nhà cung cấp',
                  )
                else
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Nhà cung cấp (không đổi)',
                      prefixIcon: Icon(
                        Icons.lock,
                        size: 16,
                        color: Colors.grey,
                      ),
                      filled: true,
                      fillColor: Color(0xFFF5F5F5),
                    ),
                    child: Text(
                      p.supplier ?? 'N/A',
                      style: AppTextStyles.headline4.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                // Giá nhập - KHÓA nếu đã nhập kho chính hoặc không có quyền xem giá vốn
                if (_canViewCostPrice) ...[
                  if (canEditFinancialInfo)
                    CurrencyTextField(
                      controller: costCtrl,
                      label: 'Giá nhập (VNĐ)',
                    )
                  else
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Giá nhập (không đổi)',
                        prefixIcon: Icon(
                          Icons.lock,
                          size: 16,
                          color: Colors.grey,
                        ),
                        filled: true,
                        fillColor: Color(0xFFF5F5F5),
                      ),
                      child: Text(
                        MoneyUtils.formatCurrency(p.cost),
                        style: AppTextStyles.headline4.copyWith(
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                CurrencyTextField(
                  controller: priceCtrl,
                  label: 'Giá bán (VNĐ)',
                ),
                const SizedBox(height: 12),
                ValidatedTextField(
                  controller: quantityCtrl,
                  label: 'Số lượng',
                  keyboardType: TextInputType.number,
                  customValidator: (val) {
                    final qty = int.tryParse(val);
                    if (qty == null || qty < 0) {
                      return 'Số lượng phải là số không âm';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                // Validate form
                final qty = int.tryParse(quantityCtrl.text);
                if (qty == null || qty < 0) {
                  NotificationService.showSnackBar(
                    'Số lượng không hợp lệ',
                    color: Colors.red,
                  );
                  return;
                }

                try {
                  final oldCost = p.cost;
                  final oldPrice = p.price;
                  // Chỉ lấy giá mới nếu được phép sửa
                  final newCost = canEditFinancialInfo
                      ? CurrencyTextField.getValueWithMultiply(costCtrl)
                      : p.cost;

                  // Nếu sản phẩm đang ở kho tạm và giờ có giá vốn > 0
                  // → Chuyển sang kho chính (isPending = false)
                  final shouldTransferToMainInventory =
                      p.isPending && newCost > 0;

                  // Tạo tên sản phẩm chuẩn từ các field
                  final generatedName = ProductConstants.generateProductName(
                    brand: selectedBrand ?? '',
                    model: modelCtrl.text.trim(),
                    capacity: capacityCtrl.text.trim(),
                    color: colorCtrl.text.trim(),
                    condition: p.condition, // Giữ nguyên condition
                  );

                  final updatedProduct = p.copyWith(
                    name: generatedName,
                    brand: selectedBrand,
                    model: modelCtrl.text.trim(),
                    capacity: ProductConstants.mapCapacity(
                      capacityCtrl.text.trim(),
                    ),
                    color: ProductConstants.mapColor(colorCtrl.text.trim()),
                    imei: imeiCtrl.text.trim(),
                    supplier: canEditFinancialInfo
                        ? supplierCtrl.text.trim()
                        : p.supplier,
                    cost: newCost,
                    price: CurrencyTextField.getValueWithMultiply(priceCtrl),
                    quantity: qty,
                    updatedAt: DateTime.now().millisecondsSinceEpoch,
                    isSynced: false,
                    // Tự động chuyển kho tạm → kho chính nếu có giá vốn
                    isPending: shouldTransferToMainInventory
                        ? false
                        : p.isPending,
                    pendingSupplier: shouldTransferToMainInventory
                        ? null
                        : p.pendingSupplier,
                  );

                  // Kiểm tra nếu giá thay đổi
                  final priceChanged =
                      oldCost != updatedProduct.cost ||
                      oldPrice != updatedProduct.price;

                  // Cập nhật local database
                  await db.updateProduct(updatedProduct);

                  // Queue sync to cloud via SyncOrchestrator
                  if (updatedProduct.id != null) {
                    await SyncOrchestrator().enqueue(
                      entityType: SyncEntityType.product,
                      entityId: updatedProduct.id!,
                      firestoreId: updatedProduct.firestoreId,
                      operation: SyncOperation.update,
                      data: updatedProduct.toMap(),
                    );
                  }

                  await _refresh();
                  Navigator.pop(ctx);

                  // CẬP NHẬT BẢNG GIÁ NHÀ CUNG CẤP NẾU CÓ THAY ĐỔI GIÁ NHẬP
                  if (oldCost != updatedProduct.cost &&
                      updatedProduct.supplier?.isNotEmpty == true) {
                    try {
                      // Tìm supplier ID từ tên supplier
                      final suppliers = await supplierService.getSuppliers();
                      final supplier = suppliers
                          .where((s) => s.name == updatedProduct.supplier)
                          .firstOrNull;

                      if (supplier != null) {
                        // Cập nhật hoặc tạo mới giá trong bảng supplier_product_prices
                        final priceData = {
                          'supplierId': supplier.id,
                          'productName': updatedProduct.name,
                          'productBrand': updatedProduct.brand,
                          'productModel': updatedProduct.capacity ?? '',
                          'costPrice': updatedProduct.cost,
                          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
                          'createdAt': DateTime.now().millisecondsSinceEpoch,
                          'isActive': 1,
                        };

                        await db.insertSupplierProductPrice(priceData);
                        debugPrint(
                          'Updated supplier price for ${updatedProduct.name}: ${updatedProduct.cost}',
                        );
                      }
                    } catch (e) {
                      debugPrint('Error updating supplier product price: $e');
                    }
                  }

                  if (priceChanged) {
                    // Hiển thị cảnh báo về việc giá thay đổi
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('⚠️ Lưu ý quan trọng'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Bạn vừa thay đổi giá của ${_terms.productLabel.toLowerCase()}. Điều này sẽ ảnh hưởng đến:',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.warning.withOpacity(0.3),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _warningItem(
                                    '❌ Các đơn hàng bán đã tạo: GIÁ KHÔNG ĐƯỢC CẬP NHẬT',
                                  ),
                                  _warningItem(
                                    '❌ Công nợ khách hàng: SỐ TIỀN KHÔNG THAY ĐỔI',
                                  ),
                                  _warningItem('❌ Báo cáo lợi nhuận: TÍNH SAI'),
                                  _warningItem(
                                    '❌ Đơn hàng nhập: GIÁ KHÔNG ẢNH HƯỞNG',
                                  ),
                                  _warningItem(
                                    '✅ Bảng giá nhà cung cấp: ĐƯỢC CẬP NHẬT TỰ ĐỘNG',
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Để cập nhật chính xác, bạn cần sửa lại từng đơn hàng đã tạo.',
                              style: AppTextStyles.headline5.copyWith(
                                color: AppColors.error,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('ĐÃ HIỂU'),
                          ),
                        ],
                      ),
                    );
                  }

                  NotificationService.showSnackBar(
                    'Đã cập nhật ${_terms.productLabel.toLowerCase()}',
                    color: Colors.green,
                  );
                } catch (e) {
                  NotificationService.showSnackBar(
                    'Lỗi cập nhật ${_terms.productLabel.toLowerCase()}: $e',
                    color: Colors.red,
                  );
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        ),
      ),
    );
  }

  void _showProductActionDialog(Product p) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chọn hành động'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, color: AppColors.primary),
              title: const Text('Chỉnh sửa'),
              onTap: () {
                Navigator.pop(ctx);
                _editProduct(p); // Dùng dialog chỉnh sửa đầy đủ
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppColors.error),
              title: const Text('Ẩn khỏi kho'),
              onTap: () {
                Navigator.pop(ctx);
                _showDeleteConfirmation(p);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Product p) {
    final passwordCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ẨN ${_terms.productLabel.toUpperCase()} (KHO)',
                  style: AppTextStyles.headline3,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Thông tin sản phẩm
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (_enableSerial && p.imei != null && p.imei!.isNotEmpty)
                        Text(
                          '${_terms.specialField1Label}: ${p.imei}',
                          style: AppTextStyles.subtitle1.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      if (_canViewCostPrice)
                        Text(
                          'Giá vốn: ${MoneyUtils.formatCurrency(p.cost)}đ',
                          style: AppTextStyles.subtitle1,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Cảnh báo
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ LƯU Ý QUAN TRỌNG:',
                        style: AppTextStyles.subtitle1.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '• Đây là XÓA MỀM – chỉ ẩn khỏi danh sách kho\n'
                        '• KHÔNG ảnh hưởng doanh thu, công nợ, lịch sử nhập\n'
                        '• Mọi số liệu tài chính khác GIỮ NGUYÊN',
                        style: AppTextStyles.body1,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Lý do xóa
                TextField(
                  controller: reasonCtrl,
                  decoration: InputDecoration(
                    labelText: 'Lý do xóa (tùy chọn)',
                    hintText: 'VD: Nhập sai, trả hàng NCC...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),

                // Mật khẩu xác nhận
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Mật khẩu tài khoản *',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    isDense: true,
                    prefixIcon: const Icon(Icons.lock, size: 20),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (passwordCtrl.text.isEmpty) {
                  NotificationService.showSnackBar(
                    'Vui lòng nhập mật khẩu',
                    color: AppColors.error,
                  );
                  return;
                }

                try {
                  final user = FirebaseAuth.instance.currentUser;
                  if (user?.email != null) {
                    // Re-authenticate với mật khẩu tài khoản
                    AuthCredential credential = EmailAuthProvider.credential(
                      email: user!.email!,
                      password: passwordCtrl.text,
                    );
                    await user.reauthenticateWithCredential(credential);

                    Navigator.pop(ctx);
                    await _deleteProductWithOptions(
                      p,
                      reason: reasonCtrl.text.trim(),
                    );
                  }
                } catch (e) {
                  NotificationService.showSnackBar(
                    'Mật khẩu không đúng',
                    color: AppColors.error,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('ẨN KHỎI KHO'),
            ),
          ],
        ),
      ),
    );
  }

  /// Xóa sản phẩm với các options liên quan
  Future<void> _deleteProductWithOptions(Product p, {String? reason}) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? 'NV';
      final productId = p.firestoreId ?? '';
      final imei = p.imei ?? '';

      // 1. GHI AUDIT LOG trước khi xóa
      await db.logAction(
        userId: user?.uid ?? '0',
        userName: userName,
        action: 'ẨN ${_terms.productLabel.toUpperCase()} (KHO)',
        type: 'PRODUCT',
        targetId: productId,
        desc:
            'Ẩn SP khỏi kho: ${p.name} | ${_terms.specialField1Label}: $imei | Giá vốn: ${p.cost} | Lý do: ${reason ?? "Không ghi"}',
      );

      // 2. XÓA MỀM sản phẩm (chỉ ẩn khỏi danh sách kho)
      if (p.id != null) {
        await db.softDeleteProduct(p.id!);

        // Sync update (soft delete) lên cloud
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.product,
          entityId: p.id!,
          firestoreId: p.firestoreId,
          operation: SyncOperation.update,
        );
      }

      await _refresh();
      NotificationService.showSnackBar(
        'Đã ẩn ${_terms.productLabel.toLowerCase()} khỏi kho: ${p.name}',
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar(
        'Lỗi xóa ${_terms.productLabel.toLowerCase()}: $e',
        color: Colors.red,
      );
    }
  }

  Widget _detailItem(String l, String v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l,
          style: AppTextStyles.caption.copyWith(color: AppColors.onSurface),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            v,
            style: AppTextStyles.body2.copyWith(
              fontWeight: FontWeight.bold,
              color: color ?? AppColors.onSurface,
            ),
            textAlign: TextAlign.right,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  Color _getBrandColor(String name) {
    String n = name.toUpperCase();
    if (n.startsWith("IP-")) return Colors.blueGrey; // iPhone
    if (n.startsWith("SS-")) return Colors.blue; // Samsung
    if (n.startsWith("PIN-")) return Colors.green; // Pin/Linh kiện
    if (n.startsWith("MH-")) return Colors.orange; // Máy khác
    if (n.startsWith("PK-")) return Colors.blue; // Phụ kiện
    // Fallback cho tên cũ
    if (n.contains("IPHONE")) return Colors.blueGrey;
    if (n.contains("SAMSUNG")) return Colors.blue;
    if (n.contains("OPPO")) return Colors.green;
    if (n.contains("XIAOMI") || n.contains("REDMI")) return Colors.orange;
    return const Color(0xFF2962FF);
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.inventory_2_outlined,
            size: 80,
            color: AppColors.grey400,
          ),
          const SizedBox(height: 10),
          Text(
            "KHO HÀNG ĐANG TRỐNG",
            style: AppTextStyles.headline6.copyWith(
              color: AppColors.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _init() async {
    final perms = await UserService.getCurrentUserPermissions();
    // Load shop settings for multi-industry features
    final settings = await CategoryService().getShopSettings();
    if (!mounted) return;
    setState(() {
      _isAdmin = perms['allowViewInventory'] ?? false;
      _hasInventoryAccess = perms['allowViewInventory'] ?? false;
      _canViewCostPrice = perms['allowViewCostPrice'] ?? false;
      _shopSettings = settings;
      // Set default type based on business type
      _selectedType = _getDefaultInventoryType();
    });
    // CRITICAL: Init check data AFTER shop settings are loaded so _selectedType is correct
    _initCheckData();
    _refresh();
  }

  /// Get default inventory type based on business type
  String _getDefaultInventoryType() {
    switch (_businessType) {
      case 'food':
        return 'THUC_PHAM';
      case 'fashion':
        return 'THOI_TRANG';
      case 'general':
        return 'SAN_PHAM';
      case 'electronics':
      default:
        return 'DIEN_THOAI';
    }
  }

  /// Build inventory type dropdown items based on business type
  List<DropdownMenuItem<String>> _buildInventoryTypeItems() {
    switch (_businessType) {
      case 'food':
        return [
          DropdownMenuItem(
            value: 'THUC_PHAM',
            child: Text('🥗 ${_terms.category1}'),
          ),
          DropdownMenuItem(
            value: 'DO_UONG',
            child: Text('🥤 ${_terms.category2}'),
          ),
          DropdownMenuItem(
            value: 'NGUYEN_LIEU',
            child: Text('🌾 ${_terms.category3}'),
          ),
        ];
      case 'fashion':
        return [
          DropdownMenuItem(
            value: 'THOI_TRANG',
            child: Text('👕 ${_terms.category1}'),
          ),
          DropdownMenuItem(
            value: 'GIAY_DEP',
            child: Text('👟 ${_terms.category2}'),
          ),
          DropdownMenuItem(
            value: 'PHU_KIEN_TT',
            child: Text('👜 ${_terms.category3}'),
          ),
        ];
      case 'general':
        return [
          DropdownMenuItem(
            value: 'SAN_PHAM',
            child: Text('📦 ${_terms.productLabel}'),
          ),
          DropdownMenuItem(value: 'DICH_VU', child: Text('🛠️ Dịch vụ')),
        ];
      case 'electronics':
      default:
        return [
          DropdownMenuItem(
            value: 'DIEN_THOAI',
            child: Text('📱 ${_terms.category1}'),
          ),
          DropdownMenuItem(
            value: 'PHU_KIEN',
            child: Text('🔧 ${_terms.category2} (Kho sửa chữa)'),
          ),
        ];
    }
  }

  Future<void> _initCheckData() async {
    await _loadOrCreateCurrentCheck();
    await _loadCheckItems();
  }

  /// Sync tất cả products từ Firestore vào local DB để đảm bảo dữ liệu mới nhất
  Future<void> _forceSyncProductsFromFirestore() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;

      debugPrint('🔄 Force syncing products from Firestore...');

      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('shopId', isEqualTo: shopId)
          .where('deleted', isEqualTo: false)
          .get();

      int updated = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        data['firestoreId'] = doc.id;
        data['isSynced'] = 1;

        final product = Product.fromMap(data);
        await db.upsertProduct(product);
        updated++;
      }

      debugPrint('✅ Force synced $updated products from Firestore');
    } catch (e) {
      debugPrint('⚠️ Error force syncing products: $e');
    }
  }

  Future<void> _refresh({bool forceSync = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _isSelectionMode = false;
      _currentOffset = 0;
      _allLoadedProducts = [];
      _hasMore = true;
    });

    // Load từ local DB trước để UI hiển thị nhanh
    // Chỉ force sync khi user kéo refresh hoặc yêu cầu cụ thể
    if (forceSync) {
      // Sync Firestore ở background, không block UI
      _forceSyncProductsFromFirestore().then((_) {
        if (mounted) _refreshLocalData();
      });
    }

    await _refreshLocalData();
  }

  /// Load dữ liệu từ local DB (nhanh)
  Future<void> _refreshLocalData() async {
    final suppliers = await supplierService.getSuppliers();
    final unsyncedCount = await db.getUnsyncedQuickInputCodesCount();

    // Load repair parts count for category chip
    final parts = await db.getAllParts();
    final partsCount = parts
        .where((p) => (p['quantity'] as int? ?? 0) > 0 || _showOutOfStock)
        .length;

    // ALWAYS load total summary from DB first (for correct totals)
    final summary = await db.getInventorySummary(
      type: _filterType == 'TẤT CẢ' ? null : _filterType,
    );

    if (_needsFullData) {
      // Load all data for filtering
      final data = await db.getAllProducts();
      data.sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
      if (!mounted) return;
      setState(() {
        _allLoadedProducts = data;
        _products = data;
        _suppliers = suppliers.map((s) => s.toMap()).toList();
        _unsyncedCount = unsyncedCount;
        _totalQtyFromDB = summary['totalQty'] ?? 0;
        _totalCapitalFromDB = summary['totalCapital'] ?? 0;
        _repairPartsCount = partsCount;
        _isLoading = false;
        _hasMore = false;
      });
    } else {
      // Lazy load first page for better performance
      final firstPage = await db.getProductsPaged(_pageSize, 0);
      if (!mounted) return;
      setState(() {
        _allLoadedProducts = firstPage;
        _products = firstPage;
        _suppliers = suppliers.map((s) => s.toMap()).toList();
        _unsyncedCount = unsyncedCount;
        _totalQtyFromDB = summary['totalQty'] ?? 0;
        _totalCapitalFromDB = summary['totalCapital'] ?? 0;
        _repairPartsCount = partsCount;
        _currentOffset = _pageSize;
        _isLoading = false;
        _hasMore = firstPage.length >= _pageSize;
      });
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final passwordCtrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("XÁC NHẬN XÓA"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Bạn có chắc chắn muốn xóa ${_selectedIds.length} mặt hàng đã chọn không?",
            ),
            const SizedBox(height: 15),
            const Text('Nhập mật khẩu tài khoản để xóa:'),
            const SizedBox(height: 10),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Mật khẩu tài khoản',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (passwordCtrl.text.isEmpty) {
                NotificationService.showSnackBar(
                  'Vui lòng nhập mật khẩu',
                  color: Colors.red,
                );
                return;
              }

              try {
                final user = FirebaseAuth.instance.currentUser;
                if (user?.email != null) {
                  AuthCredential credential = EmailAuthProvider.credential(
                    email: user!.email!,
                    password: passwordCtrl.text,
                  );
                  await user.reauthenticateWithCredential(credential);

                  Navigator.pop(ctx, true);
                }
              } catch (e) {
                NotificationService.showSnackBar(
                  'Mật khẩu không đúng',
                  color: Colors.red,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              "XÓA NGAY",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        final user = FirebaseAuth.instance.currentUser;
        final userName = user?.email?.split('@').first.toUpperCase() ?? "ADMIN";
        for (int id in _selectedIds) {
          final p = _products.firstWhere((element) => element.id == id);
          await db.logAction(
            userId: user?.uid ?? "0",
            userName: userName,
            action: "XÓA KHO",
            type: "PRODUCT",
            targetId: p.imei,
            desc: "Đã xóa ${p.name} (${_terms.specialField1Label}: ${p.imei})",
          );
          await db.deleteProduct(id);

          // Queue delete sync via SyncOrchestrator
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.product,
            entityId: id,
            firestoreId: p.firestoreId,
            operation: SyncOperation.delete,
            data: null,
          );
        }
        HapticFeedback.mediumImpact();
        _refresh();
      } catch (e) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _toggleSelection(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  // ===== INVENTORY CHECK METHODS =====
  Future<void> _loadOrCreateCurrentCheck() async {
    try {
      // Lọc theo checkType để tránh lấy nhầm check của loại khác
      final checks = await db.getInventoryChecks(checkType: _selectedType);
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);

      // Find today's check for this type or create new one
      _currentCheck = checks.cast<InventoryCheck?>().firstWhere(
        (check) =>
            check != null &&
            DateFormat('yyyy-MM-dd').format(
                  DateTime.fromMillisecondsSinceEpoch(check.createdAt),
                ) ==
                todayKey,
        orElse: () => null,
      );

      if (_currentCheck == null) {
        _currentCheck = InventoryCheck(
          checkType: _selectedType,
          checkDate: today.millisecondsSinceEpoch,
          checkedBy: FirebaseAuth.instance.currentUser?.email ?? 'Unknown',
          items: [],
          createdAt: today.millisecondsSinceEpoch,
        );
        await db.insertInventoryCheck(_currentCheck!.toMap());
      }
    } catch (e) {
      print('Error loading current check: $e');
    }
  }

  Future<void> _loadCheckItems() async {
    setState(() => _isCheckingLoading = true);
    try {
      _items = await db.getItemsForInventoryCheck(_selectedType);
      _updateCheckItems();
    } catch (e) {
      debugPrint('Lỗi tải kiểm kho: $e');
      NotificationService.showSnackBar(
        'Lỗi tải danh sách: $e',
        color: Colors.red,
      );
    } finally {
      setState(() => _isCheckingLoading = false);
    }
  }

  void _updateCheckItems() {
    _checkItems = _items.map((item) {
      final existingItem = _currentCheck?.items.firstWhere(
        (checkItem) => checkItem.itemId == item['id'].toString(),
        orElse: () => InventoryCheckItem(
          itemId: item['id'].toString(),
          itemName: item['name'] ?? '',
          itemType: _selectedType,
          imei: item['imei'],
          quantity: item['quantity'] ?? 0,
        ),
      );
      return existingItem ??
          InventoryCheckItem(
            itemId: item['id'].toString(),
            itemName: item['name'] ?? '',
            itemType: _selectedType,
            imei: item['imei'],
            quantity: item['quantity'] ?? 0,
          );
    }).toList();
  }

  void _updateItemQuantity(String itemId, int quantity) {
    quantity = quantity < 0 ? 0 : quantity;
    setState(() {
      final index = _checkItems.indexWhere((item) => item.itemId == itemId);
      if (index != -1) {
        _checkItems[index] = InventoryCheckItem(
          itemId: _checkItems[index].itemId,
          itemName: _checkItems[index].itemName,
          itemType: _checkItems[index].itemType,
          imei: _checkItems[index].imei,
          color: _checkItems[index].color,
          quantity: quantity,
          isChecked: quantity > 0,
          checkedAt: quantity > 0 ? DateTime.now().millisecondsSinceEpoch : 0,
        );
      }
    });
  }

  Future<void> _saveCheck() async {
    if (_currentCheck == null) return;

    setState(() => _isCheckingLoading = true);
    try {
      _currentCheck = InventoryCheck(
        id: _currentCheck!.id,
        firestoreId: _currentCheck!.firestoreId,
        checkType: _currentCheck!.checkType,
        checkDate: _currentCheck!.checkDate,
        checkedBy: _currentCheck!.checkedBy,
        items: _checkItems,
        isCompleted: true,
        isSynced: _currentCheck!.isSynced,
        createdAt: _currentCheck!.createdAt,
      );

      await db.updateInventoryCheck(_currentCheck!.toMap());
      NotificationService.showSnackBar(
        'Đã lưu kiểm kho thành công!',
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar(
        'Lỗi lưu kiểm kho: $e',
        color: Colors.red,
      );
    } finally {
      setState(() => _isCheckingLoading = false);
    }
  }

  // Debounce variables for QR scanning
  DateTime? _lastQRScanTime;
  String? _lastQRCode;
  bool _isQRProcessing = false;
  static const Duration _qrScanDelay = Duration(seconds: 2); // 2-3s delay

  void _onQRDetected(BarcodeCapture capture) {
    // Prevent processing while already handling a scan
    if (_isQRProcessing) return;

    final barcode = capture.barcodes.first;
    if (barcode.rawValue == null || barcode.rawValue!.isEmpty) return;

    final imei = barcode.rawValue!.trim();
    final now = DateTime.now();

    // Check if this is a duplicate scan within the delay period
    if (_lastQRScanTime != null && _lastQRCode == imei) {
      final elapsed = now.difference(_lastQRScanTime!);
      if (elapsed < _qrScanDelay) {
        // Ignore duplicate scan within delay period
        return;
      }
    }

    // Set processing flag and update last scan time
    _isQRProcessing = true;
    _lastQRScanTime = now;
    _lastQRCode = imei;

    final item = _checkItems.firstWhere(
      (item) => item.imei == imei,
      orElse: () => InventoryCheckItem(
        itemId: imei,
        itemName: '${_terms.productLabel} quét: $imei',
        itemType: _selectedType,
        quantity: 1,
        isChecked: true,
        checkedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );

    if (!item.isChecked) {
      _updateItemQuantity(item.itemId, item.quantity + 1);
      HapticFeedback.vibrate();
      NotificationService.showSnackBar('Đã quét: ${item.itemName}');
    }

    // Reset processing flag after delay
    Future.delayed(_qrScanDelay, () {
      _isQRProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Kiểm tra quyền truy cập
    if (!_hasInventoryAccess) {
      return Scaffold(
        backgroundColor: AppColors.background,
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
          title: const Text("QUẢN LÝ KHO TỔNG"),
          automaticallyImplyLeading: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.inventory_2, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                "Bạn không có quyền truy cập\nmàn hình quản lý kho",
                textAlign: TextAlign.center,
                style: AppTextStyles.headline3.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: 'QUẢN LÝ KHO',
        subtitle:
            '${_products.length} ${_terms.productLabel.toLowerCase()}${_unsyncedCount > 0 ? ' • $_unsyncedCount chưa đồng bộ' : ''}',
        accentColor: AppBarAccents.inventory,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GlobalSearchView(role: widget.role),
              ),
            ),
            icon: const Icon(
              Icons.search_rounded,
              color: AppBarAccents.inventory,
              size: 22,
            ),
            tooltip: 'Tìm kiếm',
            splashRadius: 20,
          ),
          IconButton(
            onPressed: _refresh,
            icon: const Icon(
              Icons.refresh_rounded,
              color: AppBarAccents.inventory,
              size: 22,
            ),
            tooltip: 'Làm mới',
            splashRadius: 20,
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: Column(
          children: [
            // Category filter chips - always visible
            _buildCategoryChips(),
            Expanded(
              child: _filterType == 'LINH_KIEN'
                  ? const PartsInventoryViewContent()
                  : _buildInventoryTab(),
            ),
            // Unified bottom bar with labels
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: const Offset(0, -1),
                  ),
                ],
              ),
              padding: const EdgeInsets.only(
                top: 6,
                bottom: 6,
                left: 4,
                right: 4,
              ),
              child: SafeArea(
                top: false,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _bottomBarItem(
                      Icons.add_box_rounded,
                      'Nhập kho',
                      Colors.green,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SmartStockInView(),
                          ),
                        ).then((_) => _refresh());
                      },
                    ),
                    if (_businessType == 'electronics')
                      _bottomBarItem(
                        Icons.flash_on,
                        'Nhanh',
                        Colors.orange,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const FastStockInView(),
                            ),
                          ).then((_) => _refresh());
                        },
                      ),

                    _bottomBarItem(
                      Icons.shopping_cart_checkout_rounded,
                      'Bán hàng',
                      Colors.teal,
                      () {
                        HapticFeedback.mediumImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const CreateSaleView(),
                          ),
                        ).then((_) => _refresh());
                      },
                    ),
                    _bottomBarItem(
                      Icons.business_center,
                      'NCC',
                      Colors.indigo,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SupplierListView(),
                          ),
                        );
                      },
                    ),
                    _bottomBarItem(
                      Icons.qr_code_2_rounded,
                      'In tem',
                      Colors.purple,
                      () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PtyPrintDesignerView(),
                          ),
                        );
                      },
                    ),
                    _bottomBarItem(
                      Icons.file_download_outlined,
                      'Excel',
                      Colors.blueGrey,
                      () async {
                        if (_filterType == 'LINH_KIEN') {
                          final result = await ExportDateFilterDialog.show(
                            context,
                            title: 'Xuất kho linh kiện',
                          );
                          if (result == null || !mounted) return;
                          await ExcelExportHelper.exportRepairParts(
                            context,
                            startMs: result['startMs'],
                            endMs: result['endMs'],
                          );
                        } else {
                          final result = await ExportDateFilterDialog.show(
                            context,
                            title: 'Xuất kho hàng',
                          );
                          if (result == null || !mounted) return;
                          await ExcelExportHelper.exportProducts(
                            context,
                            startMs: result['startMs'],
                            endMs: result['endMs'],
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomBarItem(
    IconData icon,
    String label,
    Color color,
    VoidCallback onTap,
  ) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryTab() {
    // Lọc theo search query
    var filteredList = _products
        .where(
          (p) =>
              VietnameseUtils.containsVietnamese(p.name, _searchQuery) ||
              (p.imei ?? "").contains(_searchQuery),
        )
        .toList();

    // Lọc theo loại hàng
    if (_filterType != 'TẤT CẢ') {
      filteredList = filteredList.where((p) => p.type == _filterType).toList();
    }

    // Nếu không bật showOutOfStock, chỉ hiện còn hàng (quantity > 0)
    if (!_showOutOfStock) {
      filteredList = filteredList.where((p) => p.quantity > 0).toList();
    }

    // Sử dụng tổng từ DB (đã tính từ TẤT CẢ sản phẩm, không phụ thuộc pagination)
    final int totalQty = _totalQtyFromDB;
    final int totalCapital = _totalCapitalFromDB;

    return Stack(
      children: [
        Column(
          children: [
            // App Bar Section
            Container(
              color: AppColors.surface,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  if (_isSelectionMode) ...[
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.error),
                      onPressed: () => setState(() {
                        _isSelectionMode = false;
                        _selectedIds.clear();
                      }),
                    ),
                    Text(
                      "ĐÃ CHỌN ${_selectedIds.length}",
                      style: AppTextStyles.headline3.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: _deleteSelected,
                      icon: const Icon(
                        Icons.delete_forever,
                        color: Colors.red,
                        size: 28,
                      ),
                    ),
                  ] else ...[
                    // Quick action buttons moved to AppBar; keep header minimal
                    const Spacer(),
                  ],
                ],
              ),
            ),

            // Summary Section
            if (!_isSelectionMode)
              _buildInventorySummary(totalQty, totalCapital),

            // Search Box
            _buildSearchBox(),

            // Product List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredList.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: () => _refresh(
                        forceSync: true,
                      ), // Kéo refresh = force sync Firestore
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 92),
                        itemCount:
                            filteredList.length + (_isLoadingMore ? 1 : 0),
                        itemBuilder: (ctx, i) {
                          if (i >= filteredList.length) {
                            // Loading indicator at bottom
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          return _buildProfessionalCard(filteredList[i], i + 1);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInventoryCheckTab() {
    return Column(
      children: [
        // Type selector and Scanner Controls
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 8),
            ],
          ),
          child: Column(
            children: [
              // Type selector - dynamic based on business type
              DropdownButtonFormField<String>(
                value: _selectedType,
                decoration: InputDecoration(
                  labelText:
                      "Loại ${_terms.productLabel.toLowerCase()} kiểm kho",
                  prefixIcon: const Icon(Icons.category),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: _buildInventoryTypeItems(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedType = value);
                    _initCheckData();
                  }
                },
              ),

              const SizedBox(height: 16),

              // Scanner Controls
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
                      icon: Icon(
                        _isScanning ? Icons.stop : Icons.play_arrow,
                        size: _iconSize,
                      ),
                      label: Text(
                        _isScanning ? "DỪNG SCAN" : "BẮT ĐẦU SCAN",
                        style: AppTextStyles.body1,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isScanning
                            ? Colors.red
                            : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        minimumSize: Size(double.infinity, _btnMinHeight),
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
            ],
          ),
        ),

        // QR Scanner
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: _isScanning ? Colors.transparent : Colors.black,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: _isScanning
                ? MobileScanner(
                    controller: _scannerController,
                    onDetect: (capture) => _onQRDetected(capture),
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
        ),

        // Progress Summary
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 8),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _progressItem(
                "Tổng ${_terms.productLabel.toLowerCase()}",
                _checkItems.length.toString(),
                Icons.inventory,
              ),
              _progressItem(
                "Đã kiểm",
                _checkItems.where((item) => item.isChecked).length.toString(),
                Icons.check_circle,
                Colors.green,
              ),
              _progressItem(
                "Chưa kiểm",
                _checkItems.where((item) => !item.isChecked).length.toString(),
                Icons.radio_button_unchecked,
                Colors.orange,
              ),
            ],
          ),
        ),

        // Check items list
        Expanded(
          child: _isCheckingLoading
              ? const Center(child: CircularProgressIndicator())
              : _checkItems.isEmpty
              ? const Center(
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
                        "Chưa có dữ liệu kiểm kho",
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _checkItems.length,
                  itemBuilder: (context, index) {
                    final item = _checkItems[index];
                    final isComplete = item.isChecked;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        title: Text(
                          item.itemName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (item.imei != null && item.imei!.isNotEmpty)
                              Text("${_terms.specialField1Label}: ${item.imei}")
                            else
                              Text(
                                _selectedType == 'PHU_KIEN'
                                    ? "${_terms.category2} sửa chữa"
                                    : _selectedType == 'LINH_KIEN'
                                    ? "${_terms.category3} (không ${_terms.specialField1Label})"
                                    : "Mã SP: ${item.itemId}",
                                style: AppTextStyles.subtitle1.copyWith(
                                  color: Colors.grey,
                                ),
                              ),
                            Text(
                              "SL hiện tại: ${item.quantity}",
                              style: TextStyle(
                                color: isComplete
                                    ? Colors.green
                                    : Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove),
                              onPressed: item.quantity > 0
                                  ? () => _updateItemQuantity(
                                      item.itemId,
                                      item.quantity - 1,
                                    )
                                  : null,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isComplete
                                    ? Colors.green.withAlpha(25)
                                    : Colors.grey.withAlpha(25),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "${item.quantity}",
                                style: AppTextStyles.headline3.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isComplete
                                      ? Colors.green
                                      : Colors.grey,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () => _updateItemQuantity(
                                item.itemId,
                                item.quantity + 1,
                              ),
                            ),
                          ],
                        ),
                        leading: Icon(
                          isComplete
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: isComplete ? Colors.green : Colors.grey,
                          size: _iconSize,
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Save button
        Container(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton.icon(
            onPressed: _saveCheck,
            icon: const Icon(Icons.save),
            label: const Text("LƯU KIỂM KHO"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2962FF),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInventorySummary(int qty, int capital) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A237E), Color(0xFF2962FF)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withAlpha(46),
            blurRadius: 6,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _summaryItemCompact("TỔNG KHO", "$qty", Icons.inventory),
          Container(width: 1, height: 36, color: Colors.white24),
          _summaryItemCompact(
            "VỐN TỒN KHO",
            _canViewCostPrice
                ? "${MoneyUtils.formatCurrency(capital)} đ"
                : "***",
            Icons.account_balance_wallet,
          ),
        ],
      ),
    );
  }

  // Compact summary used in the smaller header
  Widget _summaryItemCompact(String label, String val, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.white70, size: 12),
            const SizedBox(width: 6),
            Text(
              label,
              style: AppTextStyles.overline.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: AppTextStyles.headline4.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _progressItem(
    String label,
    String val,
    IconData icon, [
    Color? color,
  ]) {
    return Column(
      children: [
        Icon(icon, color: color ?? const Color(0xFF2962FF), size: 24),
        const SizedBox(height: 4),
        Text(
          val,
          style: AppTextStyles.headline1.copyWith(
            color: color ?? const Color(0xFF2962FF),
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: AppTextStyles.subtitle1.copyWith(color: Colors.grey.shade600),
        ),
      ],
    );
  }

  /// Category filter chips - always visible at top
  Widget _buildCategoryChips() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildTypeFilterChip('TẤT CẢ', Icons.apps, Colors.blue),
            const SizedBox(width: 8),
            _buildTypeFilterChip('DIEN_THOAI', Icons.smartphone, Colors.indigo),
            const SizedBox(width: 8),
            _buildTypeFilterChip('PHU_KIEN', Icons.headset_mic, Colors.green),
            if (_businessType == 'electronics') ...[
              const SizedBox(width: 8),
              _buildTypeFilterChip(
                'LINH_KIEN',
                Icons.build_circle,
                const Color(0xFF0068FF),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBox() {
    // Đếm sản phẩm hết hàng
    final outOfStockCount = _products.where((p) => p.quantity <= 0).length;

    return Column(
      children: [
        // Search box và toggle hết hàng
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) {
                    setState(() => _searchQuery = v);
                    // Reload data when search changes to/from empty
                    if ((v.isEmpty &&
                            _allLoadedProducts.isNotEmpty &&
                            _hasMore) ||
                        (v.isNotEmpty && _hasMore)) {
                      _refresh();
                    }
                  },
                  decoration: InputDecoration(
                    hintText:
                        "Tìm ${_terms.productLabel.toLowerCase()}, ${_terms.category2.toLowerCase()} hoặc ${_terms.specialField1Label}...",
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF2962FF),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Toggle hiển thị hàng hết
              InkWell(
                onTap: () => setState(() => _showOutOfStock = !_showOutOfStock),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _showOutOfStock
                        ? Colors.orange.shade100
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _showOutOfStock
                          ? Colors.orange
                          : Colors.grey.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _showOutOfStock
                            ? Icons.visibility
                            : Icons.visibility_off,
                        size: 18,
                        color: _showOutOfStock ? Colors.orange : Colors.grey,
                      ),
                      if (outOfStockCount > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          "$outOfStockCount",
                          style: AppTextStyles.body1.copyWith(
                            fontWeight: FontWeight.bold,
                            color: _showOutOfStock
                                ? Colors.orange
                                : Colors.grey,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeFilterChip(String type, IconData icon, Color color) {
    final isSelected = _filterType == type;
    final label = type == 'DIEN_THOAI'
        ? _terms.category1
        : type == 'PHU_KIEN'
        ? _terms.category2
        : type == 'LINH_KIEN'
        ? _terms.category3
        : 'Tất cả';

    // Đếm số lượng theo type
    int count = type == 'LINH_KIEN'
        ? _repairPartsCount
        : type == 'TẤT CẢ'
        ? _products.where((p) => p.quantity > 0 || _showOutOfStock).length
        : _products
              .where(
                (p) => p.type == type && (p.quantity > 0 || _showOutOfStock),
              )
              .length;

    return InkWell(
      onTap: () async {
        setState(() => _filterType = type);
        // CRITICAL: Phải reload data khi thay đổi filter
        // Vì khi filter != TẤT CẢ, cần load TẤT CẢ products (không paginated)
        // Khi filter = TẤT CẢ, chuyển lại chế độ paginated
        await _refreshLocalData();
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? color : Colors.grey),
            const SizedBox(width: 4),
            Text(
              label,
              style: AppTextStyles.subtitle1.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? color : Colors.grey.shade700,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProfessionalCard(Product p, [int? index]) {
    final bool isSelected = _selectedIds.contains(p.id);
    final bool isPending = p.isPending; // Kho tạm
    final metaLine = _buildCompactMetaLine(p, isPending);

    // Type icon like pending_stock_list_view
    String typeIcon = p.type == 'DIEN_THOAI' ? '📱' : '🎧';
    if (p.type == 'LINH_KIEN') typeIcon = '🔧';

    // Colors based on state
    final bgColor = isPending
        ? Colors.orange.shade50
        : (p.quantity <= 0 ? Colors.red.shade50 : Colors.white);
    final borderColor = isSelected
        ? Colors.red
        : (isPending
              ? Colors.orange.shade300
              : (p.quantity <= 0 ? Colors.red.shade200 : Colors.grey.shade200));

    return Card(
      margin: const EdgeInsets.only(bottom: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor, width: isSelected ? 2 : 1),
      ),
      elevation: 1,
      color: bgColor,
      child: InkWell(
        onLongPress: () {
          HapticFeedback.heavyImpact();
          if (widget.role == 'owner' ||
              widget.role == 'admin' ||
              UserService.isCurrentUserSuperAdmin()) {
            _showProductActionDialog(p);
          } else {
            _toggleSelection(p.id!);
          }
        },
        onTap: () =>
            _isSelectionMode ? _toggleSelection(p.id!) : _showProductDetail(p),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // STT + Type icon
                  if (index != null)
                    Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: isPending
                            ? Colors.orange.withOpacity(0.2)
                            : AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isPending
                                ? Colors.orange.shade700
                                : AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  Text(typeIcon, style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isPending)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 1,
                                ),
                                margin: const EdgeInsets.only(right: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  'TẠM',
                                  style: AppTextStyles.overline.copyWith(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                ProductConstants.cleanProductName(p.name),
                                style: AppTextStyles.subtitle1.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isPending
                                      ? Colors.orange.shade800
                                      : const Color(0xFF1A237E),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        // Detail line: only IMEI (capacity/color/condition already in name)
                        if (p.imei != null && p.imei!.isNotEmpty)
                          Text(
                            '${_terms.specialField1Label}: ${p.imei}',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // Quantity badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: p.quantity > 0
                              ? Colors.blue.shade50
                              : Colors.red.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'x${p.quantity}',
                          style: AppTextStyles.body1.copyWith(
                            fontWeight: FontWeight.bold,
                            color: p.quantity > 0
                                ? Colors.blue.shade700
                                : Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.check_circle, color: Colors.red, size: 20),
                  ],
                ],
              ),

              if (metaLine.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  metaLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.overline.copyWith(
                    color: isPending ? Colors.orange.shade700 : Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_enableVariants && p.firestoreId != null) ...[
                const SizedBox(height: 3),
                VariantStockWidget(
                  productId: p.firestoreId!,
                  variantService: _variantService,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _buildCompactMetaLine(Product p, bool isPending) {
    final parts = <String>[];
    if (_canViewCostPrice && !isPending && p.cost > 0) {
      parts.add('Vốn ${NumberFormat.compact(locale: 'vi').format(p.cost)}đ');
    }
    if (!isPending) {
      parts.add('Bán ${NumberFormat.compact(locale: 'vi').format(p.price)}đ');
    }
    if (p.supplier != null && p.supplier!.trim().isNotEmpty) {
      parts.add(p.supplier!.trim());
    }
    if (isPending) {
      parts.add('Chờ giá');
    }
    return parts.join(' • ');
  }

  void _showAddProductDialog() {
    final nameC = TextEditingController();
    final imeiC = TextEditingController();
    final costC = TextEditingController();
    final priceC = TextEditingController();
    final detailC = TextEditingController();
    final qtyC = TextEditingController(text: "1");
    final nameF = FocusNode();
    final imeiF = FocusNode();
    final costF = FocusNode();
    final priceF = FocusNode();
    final qtyF = FocusNode();

    // Phase 2: Food module - Expiry & Batch fields
    final batchC = TextEditingController();
    DateTime? expiryDate;

    // SKU fields
    String selectedNhom = 'IP'; // Default nhóm
    final modelC = TextEditingController();
    final thongtinC = TextEditingController();
    final skuC = TextEditingController(); // Generated SKU display/edit
    final skuF = FocusNode();

    String type = "DIEN_THOAI";
    String payMethod = "TIỀN MẶT";
    String? supplier = _suppliers.isNotEmpty
        ? _suppliers.first['name'] as String
        : null;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> generateSKU() async {
            if (selectedNhom.isEmpty) {
              NotificationService.showSnackBar(
                "Vui lòng chọn nhóm ${_terms.productLabel.toLowerCase()}!",
                color: Colors.red,
              );
              return;
            }

            try {
              final generatedSKU = await SKUGenerator.generateSKU(
                nhom: selectedNhom,
                model: modelC.text.trim().isNotEmpty
                    ? modelC.text.trim()
                    : null,
                thongtin: thongtinC.text.trim().isNotEmpty
                    ? thongtinC.text.trim()
                    : null,
                dbHelper: db,
                firestoreService: null,
              );

              setS(() => skuC.text = generatedSKU);
              NotificationService.showSnackBar(
                "Đã tạo mã hàng: $generatedSKU",
                color: Colors.blue,
              );
            } catch (e) {
              NotificationService.showSnackBar(
                "Lỗi tạo mã hàng: $e",
                color: Colors.red,
              );
            }
          }

          Future<void> saveProcess({bool next = false}) async {
            // Finalize currency fields trước khi xử lý
            CurrencyTextField.finalizeAll();

            if (skuC.text.isEmpty) {
              NotificationService.showSnackBar(
                "Vui lòng tạo mã hàng trước!",
                color: Colors.red,
              );
              return;
            }
            if (supplier == null) {
              NotificationService.showSnackBar(
                "Vui lòng chọn Nhà cung cấp!",
                color: Colors.red,
              );
              return;
            }
            if (isSaving) return;
            setS(() => isSaving = true);
            try {
              final int ts = DateTime.now().millisecondsSinceEpoch;
              final String imei = imeiC.text.trim();
              final String fId = "prod_${ts}_${imei.isNotEmpty ? imei : ts}";
              final p = Product(
                firestoreId: fId,
                name: skuC.text.toUpperCase(),
                model: modelC.text.trim().isNotEmpty
                    ? modelC.text.trim()
                    : null,
                imei: imei,
                cost: CurrencyTextField.parseValueWithMultiply(costC.text),
                price: CurrencyTextField.parseValueWithMultiply(priceC.text),
                capacity: detailC.text.toUpperCase(),
                quantity: int.tryParse(qtyC.text) ?? 1,
                type: type,
                createdAt: ts,
                supplier: supplier,
                status: 1,
                sku: skuC.text.toUpperCase(), // Save generated SKU
                // Phase 2: Food module - Expiry & Batch
                expiryDate: expiryDate?.millisecondsSinceEpoch,
                batchNumber: batchC.text.trim().isNotEmpty
                    ? batchC.text.trim()
                    : null,
                unit: _shopSettings?.defaultUnit,
              );
              final user = FirebaseAuth.instance.currentUser;
              final userName =
                  user?.email?.split('@').first.toUpperCase() ?? "NV";
              await db.logAction(
                userId: user?.uid ?? "0",
                userName: userName,
                action: "NHẬP KHO",
                type: "PRODUCT",
                targetId: p.imei,
                desc: "Đã nhập máy ${p.name}",
              );

              await db.upsertProduct(p);

              // Get product ID and queue sync
              final savedProduct = await db.getProductByFirestoreId(
                p.firestoreId ?? 'prod_${p.createdAt}',
              );

              // === XỬ LÝ PAYMENT METHOD ===
              final totalCost = p.cost * p.quantity;
              if (totalCost > 0 && supplier != null && supplier!.isNotEmpty) {
                final shopId = await UserService.getCurrentShopId() ?? '';
                final nowTs = DateTime.now().millisecondsSinceEpoch;

                // Lấy supplier ID
                final suppliers = await supplierService.getSuppliers();
                final supplierData = suppliers
                    .where((s) => s.name == supplier)
                    .firstOrNull;
                final supplierId = supplierData?.id;

                if (payMethod == 'CÔNG NỢ') {
                  // Tạo debt record - Shop nợ NCC
                  final debtFId = 'debt_stockin_${nowTs}_${supplierId ?? 0}';
                  final debtData = {
                    'firestoreId': debtFId,
                    'type': 'SHOP_OWES',
                    'debtType': 'SHOP_OWES',
                    'personName': supplier,
                    'phone': '',
                    'totalAmount': totalCost,
                    'paidAmount': 0,
                    'note': 'Nhập kho: ${p.name} x${p.quantity}',
                    'status': 'ACTIVE',
                    'createdAt': nowTs,
                    'shopId': shopId,
                    'linkedId': p.firestoreId ?? '',
                    'relatedPartId': supplierId?.toString() ?? '',
                    'deleted': 0,
                    'isSynced': 0,
                  };
                  final debtId = await db.insertDebt(debtData);

                  if (debtId > 0) {
                    await SyncOrchestrator().enqueue(
                      entityType: SyncEntityType.debt,
                      entityId: debtId,
                      firestoreId: debtFId,
                      operation: SyncOperation.create,
                      data: debtData,
                    );
                  }

                  // Công nợ đã ghi nhận ở bảng debts - không cần PaymentIntent
                  debugPrint('✅ Inventory debt recorded: $debtFId');
                  EventBus().emit('debts_changed');
                } else {
                  // TIỀN MẶT / CHUYỂN KHOẢN - ghi nhận thanh toán trực tiếp
                  final payResult =
                      await PaymentIntentService.executePaymentDirect(
                        type: PaymentIntentType.inventoryPurchase,
                        amount: totalCost,
                        paymentMethod: PaymentMethod.fromCode(payMethod),
                        description:
                            'Nhập kho: $supplier - ${p.name} x${p.quantity}',
                        executedBy: user?.uid ?? 'unknown',
                        referenceId: p.firestoreId,
                        referenceType: 'inventory_stockin',
                        personName: supplier,
                        idempotencyKey: p.firestoreId,
                        metadata: {
                          'productId': savedProduct?.id,
                          'productName': p.name,
                          'quantity': p.quantity,
                          'supplierId': supplierId,
                          'paymentMethod': payMethod,
                        },
                      );
                  debugPrint(
                    '💳 Inventory payment ${payResult.success ? "OK" : "FAILED"}: ${totalCost}đ',
                  );
                }
              }
              if (savedProduct?.id != null) {
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.product,
                  entityId: savedProduct!.id!,
                  firestoreId: p.firestoreId,
                  operation: SyncOperation.create,
                  data: p.toMap(),
                );
              }

              // Lưu lịch sử nhập hàng từ nhà cung cấp
              if (supplier?.isNotEmpty == true) {
                final suppliers = await supplierService.getSuppliers();
                final supplierData = suppliers
                    .where((s) => s.name == supplier)
                    .firstOrNull;
                final supplierId = supplierData?.id;
                final shopId = await UserService.getCurrentShopId();
                if (supplierId != null) {
                  final importHistory = {
                    'supplierId': supplierId,
                    'supplierName': supplier,
                    'productName': p.name,
                    'productBrand': p.brand,
                    'productModel': p.model,
                    'imei': p.imei,
                    'quantity': p.quantity,
                    'costPrice': p.cost,
                    'totalAmount': p.cost * p.quantity,
                    'paymentMethod': payMethod,
                    'importDate': ts,
                    'importedBy': userName,
                    'notes': 'Nhập từ Inventory View',
                    'shopId': shopId,
                    'isSynced': 0,
                  };
                  final importHistoryId = await db.insertSupplierImportHistory(
                    importHistory,
                  );

                  // FIX BUG-001: Enqueue để sync lên Firestore
                  if (importHistoryId > 0) {
                    await SyncOrchestrator().enqueueSupplierImportHistory(
                      importHistoryId,
                      firestoreId: importHistory['firestoreId'] as String?,
                      operation: SyncOperation.create,
                    );
                  }

                  // Cập nhật thống kê nhà cung cấp
                  await db.updateSupplierStats(
                    supplierId,
                    p.cost * p.quantity,
                    1,
                  );

                  // Cập nhật giá nhà cung cấp
                  await db.deactivateSupplierProductPrice(
                    supplierId,
                    p.name,
                    p.brand,
                    p.model,
                  );
                  final supplierPrice = {
                    'supplierId': supplierId,
                    'productName': p.name,
                    'productBrand': p.brand,
                    'productModel': p.model,
                    'costPrice': p.cost,
                    'lastUpdated': ts,
                    'createdAt': ts,
                    'isActive': 1,
                    'shopId': shopId,
                  };
                  await db.insertSupplierProductPrice(supplierPrice);

                  // Cập nhật thống kê nhà cung cấp
                  await db.updateSupplierStats(
                    supplierId,
                    p.cost * p.quantity,
                    p.quantity,
                  );
                }
              }

              // Final sync pass after all related records are enqueued.
              try {
                await SyncOrchestrator().syncAll();
              } catch (e) {
                debugPrint('Inventory saveProcess sync warning: $e');
              }

              HapticFeedback.lightImpact();
              if (next) {
                imeiC.clear();
                setS(() => isSaving = false);
                if (mounted) {
                  FocusScope.of(context).requestFocus(imeiF);
                  NotificationService.showSnackBar(
                    "ĐÃ THÊM MÁY",
                    color: Colors.blue,
                  );
                }
              } else {
                if (mounted) {
                  EventBus().emit('suppliers_changed');
                  EventBus().emit('products_changed');
                  Navigator.of(context).pop();
                  _refresh();
                  NotificationService.showSnackBar(
                    "NHẬP KHO THÀNH CÔNG",
                    color: Colors.green,
                  );
                }
              }
            } catch (e) {
              setS(() => isSaving = false);
            }
          }

          return AlertDialog(
            title: const Text(
              "NHẬP KHO SIÊU TỐC",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF2962FF),
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Loại hàng
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    items: [
                      DropdownMenuItem(
                        value: "DIEN_THOAI",
                        child: Text(_terms.category1),
                      ),
                      DropdownMenuItem(
                        value: "PHỤ KIỆN",
                        child: Text(_terms.category2),
                      ),
                    ],
                    onChanged: (v) => setS(() => type = v!),
                    decoration: const InputDecoration(labelText: "Loại hàng"),
                  ),

                  // Tên máy
                  _input(
                    nameC,
                    _isFashion ? "Tên sản phẩm *" : "Tên máy *",
                    _isFashion ? Icons.checkroom : Icons.phone_android,
                    f: nameF,
                    next: imeiF,
                    caps: true,
                  ),

                  // Chi tiết
                  if (_isElectronics || _isFashion)
                    _input(
                      detailC,
                      _isFashion
                          ? "Size - Màu sắc"
                          : "Chi tiết (Dung lượng - Màu...)",
                      _isFashion ? Icons.straighten : Icons.info_outline,
                      caps: true,
                    ),

                  // IMEI/Serial - chỉ hiển thị cho electronics
                  if (_enableSerial)
                    _input(
                      imeiC,
                      "Số IMEI / Serial",
                      Icons.fingerprint,
                      f: imeiF,
                      next: _canViewCostPrice ? costF : priceF,
                      type: TextInputType.number,
                    ),

                  // Giá vốn - chỉ hiển thị nếu có quyền
                  if (_canViewCostPrice)
                    _input(
                      costC,
                      "Giá vốn (k)",
                      Icons.money,
                      f: costF,
                      next: priceF,
                      type: TextInputType.number,
                      suffix: "k",
                    ),

                  // Giá bán
                  _input(
                    priceC,
                    "Giá bán (k)",
                    Icons.sell,
                    f: priceF,
                    next: qtyF,
                    type: TextInputType.number,
                    suffix: "k",
                  ),

                  // Số lượng và Nhà cung cấp
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: _input(
                          qtyC,
                          "SL",
                          Icons.add_box,
                          f: qtyF,
                          isBig: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          initialValue: supplier,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: "Nhà cung cấp *",
                          ),
                          items: _suppliers
                              .map(
                                (s) => DropdownMenuItem(
                                  value: s['name'] as String,
                                  child: Text(s['name']),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => setS(() => supplier = v),
                        ),
                      ),
                    ],
                  ),

                  // Phase 2: Food module - Expiry & Batch fields
                  if (_enableExpiry || _enableBatch) ...[
                    const Divider(height: 30, thickness: 1),
                    Text(
                      "HẠN SỬ DỤNG",
                      style: AppTextStyles.headline4.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (_enableExpiry) ...[
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate:
                                expiryDate ??
                                DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365 * 5),
                            ),
                            helpText: 'Chọn ngày hết hạn',
                          );
                          if (picked != null) {
                            setS(() => expiryDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Ngày hết hạn',
                            prefixIcon: Icon(
                              Icons.event,
                              color: Colors.orange.shade600,
                            ),
                            suffixIcon: expiryDate != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () =>
                                        setS(() => expiryDate = null),
                                  )
                                : null,
                          ),
                          child: Text(
                            expiryDate != null
                                ? DateFormat('dd/MM/yyyy').format(expiryDate!)
                                : 'Chưa chọn',
                            style: TextStyle(
                              color: expiryDate != null
                                  ? Colors.black
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],

                    if (_enableBatch) ...[
                      const SizedBox(height: 12),
                      _input(batchC, "Số lô hàng", Icons.qr_code_2, caps: true),
                    ],
                  ],

                  // SKU Section
                  const Divider(height: 30, thickness: 1),
                  Text(
                    "MÃ HÀNG",
                    style: AppTextStyles.headline4.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF2962FF),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Nhóm
                  DropdownButtonFormField<String>(
                    initialValue: selectedNhom,
                    decoration: const InputDecoration(
                      labelText: "Nhóm *",
                      prefixIcon: Icon(Icons.category, size: 18),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: "IP",
                        child: Text("IP - iPhone"),
                      ),
                      const DropdownMenuItem(
                        value: "SS",
                        child: Text("SS - Samsung"),
                      ),
                      const DropdownMenuItem(
                        value: "PIN",
                        child: Text("PIN - Pin sạc"),
                      ),
                      const DropdownMenuItem(
                        value: "MH",
                        child: Text("MH - Màn hình"),
                      ),
                      DropdownMenuItem(
                        value: "PK",
                        child: Text("PK - ${_terms.category2}"),
                      ),
                    ],
                    onChanged: (v) => setS(() => selectedNhom = v!),
                  ),

                  // Model
                  _input(
                    modelC,
                    "Model (vd: IP12PM)",
                    Icons.smartphone,
                    caps: true,
                  ),

                  // Thông tin
                  _input(
                    thongtinC,
                    "Thông tin (vd: 256GB)",
                    Icons.info,
                    caps: true,
                  ),

                  // Mã hàng và nút tạo
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: _input(
                          skuC,
                          "Mã hàng được tạo",
                          Icons.qr_code,
                          f: skuF,
                          caps: true,
                          readOnly: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: ElevatedButton.icon(
                          onPressed: () => generateSKU(),
                          icon: const Icon(Icons.auto_fix_high, size: 16),
                          label: const Text("TẠO MÃ"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2962FF),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 15),
                  Wrap(
                    spacing: 8,
                    children: ["TIỀN MẶT", "CHUYỂN KHOẢN", "CÔNG NỢ"]
                        .map(
                          (m) => ChoiceChip(
                            label: Text(m, style: AppTextStyles.body1),
                            selected: payMethod == m,
                            onSelected: (v) => setS(() => payMethod = m),
                            selectedColor: Colors.blueAccent,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("HỦY"),
              ),
              OutlinedButton(
                onPressed: isSaving ? null : () => saveProcess(next: true),
                child: const Text("NHẬP TIẾP"),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : () => saveProcess(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2962FF),
                ),
                child: const Text(
                  "HOÀN TẤT",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Dialog xác nhận giá vốn và chuyển từ Kho Tạm sang Kho Chính
  void _showConfirmCostDialog(Product p) {
    final costC = TextEditingController();
    final priceC = TextEditingController();
    String? selectedSupplier = p.pendingSupplier;
    String selectedPaymentMethod = 'TIỀN MẶT';
    bool isSaving = false;

    final paymentMethods = ['TIỀN MẶT', 'CHUYỂN KHOẢN', 'CÔNG NỢ'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> confirmCost() async {
            CurrencyTextField.finalizeAll();

            final cost = CurrencyTextField.parseValue(costC.text);
            if (cost <= 0) {
              NotificationService.showSnackBar(
                "Vui lòng nhập giá vốn hợp lệ!",
                color: Colors.red,
              );
              return;
            }

            if (selectedSupplier == null || selectedSupplier!.isEmpty) {
              NotificationService.showSnackBar(
                "Vui lòng chọn nhà cung cấp!",
                color: Colors.red,
              );
              return;
            }

            if (isSaving) return;
            setS(() => isSaving = true);

            try {
              final ts = DateTime.now().millisecondsSinceEpoch;
              final price = CurrencyTextField.parseValue(priceC.text);

              // 1. Cập nhật sản phẩm - chuyển từ kho tạm sang kho chính
              final updatedP = p.copyWith(
                cost: cost,
                price: price > 0 ? price : null,
                isPending: false,
                pendingSupplier: null,
                supplier: selectedSupplier,
                paymentMethod: selectedPaymentMethod,
                updatedAt: ts,
              );

              await db.upsertProduct(updatedP);

              // Queue sync VÀ sync ngay lập tức lên Firestore
              if (p.id != null) {
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.product,
                  entityId: p.id!,
                  firestoreId: p.firestoreId,
                  operation: SyncOperation.update,
                  data: updatedP.toMap(),
                );
              }

              // 2. Lưu lịch sử nhập hàng từ nhà cung cấp
              final supplierData = _suppliers.firstWhere(
                (s) => s['name'] == selectedSupplier,
                orElse: () => {},
              );
              final supplierId = supplierData['id'];
              final shopId = await UserService.getCurrentShopId();
              final user = FirebaseAuth.instance.currentUser;
              final userName =
                  user?.email?.split('@').first.toUpperCase() ?? "NV";

              if (supplierId != null) {
                final importHistory = {
                  'supplierId': supplierId,
                  'supplierName': selectedSupplier,
                  'productName': p.name,
                  'productBrand': p.brand,
                  'productModel': p.model,
                  'imei': p.imei,
                  'quantity': p.quantity,
                  'costPrice': cost,
                  'totalAmount': cost * p.quantity,
                  'paymentMethod': selectedPaymentMethod,
                  'importDate': ts,
                  'importedBy': userName,
                  'notes': 'Xác nhận giá từ Kho Tạm',
                  'shopId': shopId,
                  'isSynced': 0,
                };
                final importHistoryId = await db.insertSupplierImportHistory(
                  importHistory,
                );
                if (importHistoryId > 0) {
                  await SyncOrchestrator().enqueueSupplierImportHistory(
                    importHistoryId,
                    firestoreId: importHistory['firestoreId'] as String?,
                    operation: SyncOperation.create,
                  );
                }

                // Cập nhật giá nhà cung cấp
                await db.deactivateSupplierProductPrice(
                  supplierId,
                  p.name,
                  p.brand,
                  p.model,
                );
                final supplierPrice = {
                  'supplierId': supplierId,
                  'productName': p.name,
                  'productBrand': p.brand,
                  'productModel': p.model,
                  'costPrice': cost,
                  'lastUpdated': ts,
                  'createdAt': ts,
                  'isActive': 1,
                  'shopId': shopId,
                };
                await db.insertSupplierProductPrice(supplierPrice);

                // Cập nhật thống kê nhà cung cấp
                await db.updateSupplierStats(
                  supplierId,
                  cost * p.quantity,
                  p.quantity,
                );
              }

              // Final sync pass after product + supplier import history are enqueued.
              try {
                await SyncOrchestrator().syncAll();
              } catch (e) {
                debugPrint('Inventory confirmCost sync warning: $e');
              }

              // 3. Xử lý thanh toán
              // NOTE: Direct insertExpense/upsertDebt for staging confirm BLOCKED
              // Payment must go through PaymentIntentService -> UnifiedPaymentPage
              // Product is updated but payment execution is separate flow

              // 4. Log action
              await db.logAction(
                userId: user?.uid ?? "0",
                userName: userName,
                action: "XÁC NHẬN GIÁ KHO TẠM",
                type: "PRODUCT",
                targetId: p.imei,
                desc:
                    "Xác nhận giá ${p.name} - Giá: ${MoneyUtils.formatCurrency(cost)}đ - NCC: $selectedSupplier",
              );

              // 5. Chat notification
              await FirestoreService.sendChat(
                message:
                    "✅ Đã xác nhận giá từ Kho Tạm: ${p.name} (${p.imei}) - Giá: ${MoneyUtils.formatCurrency(cost)}đ - NCC: $selectedSupplier",
                senderId: user?.uid ?? "system",
                senderName: userName,
                linkedType: "PRODUCT",
                linkedKey: p.imei ?? '',
                linkedSummary: p.name,
              );

              EventBus().emit('suppliers_changed');
              EventBus().emit('products_changed');

              if (mounted) {
                Navigator.pop(ctx);
                _refresh();
                NotificationService.showSnackBar(
                  "Đã xác nhận giá và chuyển sang Kho Chính!",
                  color: Colors.green,
                );
              }
            } catch (e) {
              setS(() => isSaving = false);
              NotificationService.showSnackBar("Lỗi: $e", color: Colors.red);
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Xác nhận giá - Chuyển Kho Chính',
                    style: AppTextStyles.headline3,
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thông tin sản phẩm
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.name,
                          style: AppTextStyles.headline4.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_terms.specialField1Label}: ${p.imei ?? "N/A"}',
                          style: AppTextStyles.subtitle1,
                        ),
                        Text(
                          'SL: ${p.quantity}',
                          style: AppTextStyles.subtitle1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Giá vốn - chỉ hiển thị nếu có quyền
                  if (_canViewCostPrice) ...[
                    CurrencyTextField(
                      controller: costC,
                      label: 'GIÁ VỐN (*)',
                      icon: Icons.monetization_on,
                      autoMultiply1000: true,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Giá bán (optional)
                  CurrencyTextField(
                    controller: priceC,
                    label: 'GIÁ BÁN (tùy chọn)',
                    icon: Icons.sell,
                    autoMultiply1000: true,
                  ),
                  const SizedBox(height: 12),

                  // Nhà cung cấp dropdown
                  DropdownButtonFormField<String>(
                    initialValue:
                        _suppliers.any((s) => s['name'] == selectedSupplier)
                        ? selectedSupplier
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'NHÀ CUNG CẤP (*)',
                      prefixIcon: Icon(Icons.business),
                      border: OutlineInputBorder(),
                    ),
                    items: _suppliers.map((s) {
                      return DropdownMenuItem<String>(
                        value: s['name'] as String,
                        child: Text(s['name'] as String),
                      );
                    }).toList(),
                    onChanged: (v) => setS(() => selectedSupplier = v),
                  ),
                  const SizedBox(height: 12),

                  // Phương thức thanh toán
                  DropdownButtonFormField<String>(
                    initialValue: selectedPaymentMethod,
                    decoration: const InputDecoration(
                      labelText: 'THANH TOÁN',
                      prefixIcon: Icon(Icons.payment),
                      border: OutlineInputBorder(),
                    ),
                    items: paymentMethods.map((m) {
                      return DropdownMenuItem<String>(value: m, child: Text(m));
                    }).toList(),
                    onChanged: (v) =>
                        setS(() => selectedPaymentMethod = v ?? 'TIỀN MẶT'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: const Text('HỦY'),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : confirmCost,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'XÁC NHẬN',
                        style: TextStyle(color: Colors.white),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editProduct(Product p) {
    // Tên máy = chỉ model (VD: "15 PRO MAX")
    final nameC = TextEditingController(text: p.model ?? '');
    final imeiC = TextEditingController(text: p.imei ?? '');
    final costC = TextEditingController(
      text: CurrencyTextField.formatDisplay(p.cost),
    );
    final priceC = TextEditingController(
      text: CurrencyTextField.formatDisplay(p.price),
    );
    // Chi tiết tách riêng: capacity, color, condition - dùng dropdown thay vì text
    final mappedCapacity = ProductConstants.mapCapacity(p.capacity);
    String? selectedCapacity =
        ProductConstants.capacities.contains(mappedCapacity)
        ? mappedCapacity
        : (mappedCapacity.isNotEmpty ? mappedCapacity : null);
    final mappedColor = p.color != null && p.color!.isNotEmpty
        ? ProductConstants.mapColor(p.color)
        : null;
    String? selectedColor =
        mappedColor != null && ProductConstants.colors.contains(mappedColor)
        ? mappedColor
        : null;
    final mappedCondition = p.condition.isNotEmpty
        ? ProductConstants.mapConditionShort(p.condition)
        : null;
    String? selectedCondition =
        mappedCondition != null &&
            ProductConstants.conditionsShort.contains(mappedCondition)
        ? mappedCondition
        : null;

    // Fallback: nếu color/capacity/condition chưa được lưu riêng (sản phẩm cũ),
    // thử parse từ description (= detail trong Firestore), format: "256GB - ĐEN - MỚI"
    if (selectedColor == null &&
        selectedCapacity == null &&
        p.description.isNotEmpty) {
      final parts = p.description.split(' - ');
      for (final part in parts) {
        final trimmed = part.trim().toUpperCase();
        // Parse capacity (kết thúc bằng GB hoặc TB)
        if (selectedCapacity == null &&
            (trimmed.endsWith('GB') || trimmed.endsWith('TB'))) {
          final cap = ProductConstants.mapCapacity(trimmed);
          if (ProductConstants.capacities.contains(cap)) selectedCapacity = cap;
        }
        // Parse color
        if (selectedColor == null &&
            ProductConstants.colors.contains(trimmed)) {
          selectedColor = trimmed;
        }
        // Parse condition
        if (selectedCondition == null &&
            ProductConstants.conditionsShort.contains(trimmed)) {
          selectedCondition = trimmed;
        }
      }
    }
    final labelInfoC = TextEditingController(text: p.labelInfo ?? '');
    final labelNoteC = TextEditingController(text: p.labelNote ?? '');
    final qtyC = TextEditingController(text: p.quantity.toString());
    // Brand chọn riêng - giữ từ sản phẩm gốc
    String? selectedBrand = ProductConstants.mapBrand(p.brand);

    // Phase 2: Food module - Expiry & Batch fields
    final batchC = TextEditingController(text: p.batchNumber ?? '');
    DateTime? expiryDate = p.expiryDate != null
        ? DateTime.fromMillisecondsSinceEpoch(p.expiryDate!)
        : null;

    String type = p.type;
    String? supplier = p.supplier;
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          Future<void> saveProcess() async {
            // Finalize currency fields trước khi xử lý
            CurrencyTextField.finalizeAll();

            if (supplier == null) {
              NotificationService.showSnackBar(
                "Vui lòng chọn Nhà cung cấp!",
                color: Colors.red,
              );
              return;
            }
            if (isSaving) return;
            setS(() => isSaving = true);
            try {
              final int ts = DateTime.now().millisecondsSinceEpoch;
              final newCost = CurrencyTextField.parseValue(costC.text);

              // Nếu sản phẩm đang ở kho tạm và giờ có giá vốn > 0
              // → Chuyển sang kho chính (isPending = false)
              final shouldTransferToMainInventory = p.isPending && newCost > 0;

              // Tạo tên sản phẩm chuẩn từ các field
              // nameC = model, selectedBrand = brand
              final generatedName = ProductConstants.generateProductName(
                brand: selectedBrand,
                model: nameC.text.trim(), // nameC chứa model
                capacity: selectedCapacity,
                color: selectedColor,
                condition: selectedCondition,
              );

              final updatedP = p.copyWith(
                name: generatedName,
                brand: selectedBrand ?? p.brand,
                model: nameC.text.trim().isNotEmpty ? nameC.text.trim() : null,
                imei: imeiC.text.trim(),
                cost: newCost,
                price: CurrencyTextField.parseValue(priceC.text),
                capacity: selectedCapacity ?? '',
                color: selectedColor ?? '',
                condition: selectedCondition ?? p.condition,
                labelInfo: labelInfoC.text.trim(),
                labelNote: labelNoteC.text.trim().isNotEmpty
                    ? labelNoteC.text.trim().toUpperCase()
                    : null,
                quantity: int.tryParse(qtyC.text) ?? 1,
                type: type,
                supplier: supplier,
                updatedAt: ts,
                isSynced: false,
                // Tự động chuyển kho tạm → kho chính nếu có giá vốn
                isPending: shouldTransferToMainInventory ? false : p.isPending,
                pendingSupplier: shouldTransferToMainInventory
                    ? null
                    : p.pendingSupplier,
                // Phase 2: Food module - Expiry & Batch
                expiryDate: expiryDate?.millisecondsSinceEpoch,
                batchNumber: batchC.text.trim().isNotEmpty
                    ? batchC.text.trim()
                    : null,
              );
              final user = FirebaseAuth.instance.currentUser;
              final userName =
                  user?.email?.split('@').first.toUpperCase() ?? "NV";
              await db.logAction(
                userId: user?.uid ?? "0",
                userName: userName,
                action: "CHỈNH SỬA",
                type: "PRODUCT",
                targetId: p.imei,
                desc: "Đã chỉnh sửa máy ${p.name}",
              );
              await db.upsertProduct(updatedP);

              // Get product ID and queue sync
              final savedProduct = await db.getProductByFirestoreId(
                updatedP.firestoreId ?? 'prod_${updatedP.createdAt}',
              );
              if (savedProduct?.id != null) {
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.product,
                  entityId: savedProduct!.id!,
                  firestoreId: updatedP.firestoreId,
                  operation: SyncOperation.update,
                  data: updatedP.toMap(),
                );
              }

              HapticFeedback.lightImpact();
              if (mounted) {
                Navigator.of(ctx).pop();
                _refresh();
                NotificationService.showSnackBar(
                  "CẬP NHẬT THÀNH CÔNG",
                  color: Colors.green,
                );
              }
            } catch (e) {
              setS(() => isSaving = false);
              NotificationService.showSnackBar("Lỗi: $e", color: Colors.red);
            }
          }

          return AlertDialog(
            title: Text(
              "CHỈNH SỬA ${_terms.productLabel.toUpperCase()}",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF2962FF),
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Loại hàng (KHÓA - không cho thay đổi)
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: "Loại hàng (không đổi)",
                      prefixIcon: Icon(
                        Icons.lock,
                        size: 16,
                        color: Colors.grey,
                      ),
                      filled: true,
                      fillColor: Color(0xFFF5F5F5),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: Text(
                      type,
                      style: AppTextStyles.subtitle1.copyWith(
                        color: Colors.black54,
                      ),
                    ),
                  ),

                  // Hãng - chỉ hiện cho điện thoại
                  if (_businessType == 'electronics') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: ProductConstants.brands.contains(selectedBrand)
                          ? selectedBrand
                          : null,
                      decoration: const InputDecoration(
                        labelText: "Hãng *",
                        prefixIcon: Icon(Icons.business, size: 16),
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: ProductConstants.brands
                          .map(
                            (b) => DropdownMenuItem(
                              value: b,
                              child: Text(
                                b,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setS(() => selectedBrand = v),
                    ),
                  ],

                  // Tên sản phẩm / Model
                  _input(
                    nameC,
                    _isElectronics
                        ? "Model (VD: 15 PRO MAX)"
                        : "Tên ${_terms.productLabel.toLowerCase()}",
                    _isElectronics ? Icons.phone_android : Icons.inventory_2,
                    caps: true,
                  ),

                  // Dung lượng/Size + Màu sắc (dropdown)
                  if (_isElectronics || _isFashion)
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _isFashion
                                ? (ProductConstants.clothingSizes.contains(
                                        selectedCapacity,
                                      )
                                      ? selectedCapacity
                                      : null)
                                : (ProductConstants.capacities.contains(
                                        selectedCapacity,
                                      )
                                      ? selectedCapacity
                                      : null),
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: _isFashion
                                  ? 'Kích thước'
                                  : 'Dung lượng',
                              prefixIcon: Icon(
                                _isFashion ? Icons.straighten : Icons.storage,
                                size: 16,
                              ),
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items:
                                (_isFashion
                                        ? ProductConstants.clothingSizes
                                        : ProductConstants.capacities)
                                    .map(
                                      (c) => DropdownMenuItem(
                                        value: c,
                                        child: Text(
                                          c,
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) => setS(() => selectedCapacity = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value:
                                ProductConstants.colors.contains(selectedColor)
                                ? selectedColor
                                : null,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Màu sắc',
                              prefixIcon: Icon(Icons.color_lens, size: 16),
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: ProductConstants.colors
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c,
                                    child: Text(
                                      c,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setS(() => selectedColor = v),
                          ),
                        ),
                      ],
                    ),
                  if (!_isElectronics && !_isFashion)
                    DropdownButtonFormField<String>(
                      value: ProductConstants.colors.contains(selectedColor)
                          ? selectedColor
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Màu sắc',
                        prefixIcon: Icon(Icons.color_lens, size: 16),
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: ProductConstants.colors
                          .map(
                            (c) => DropdownMenuItem(
                              value: c,
                              child: Text(
                                c,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setS(() => selectedColor = v),
                    ),

                  // Tình trạng (MỚI, 99, 98...)
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedCondition,
                    decoration: const InputDecoration(
                      labelText: 'Tình trạng',
                      prefixIcon: Icon(Icons.grade, size: 16),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    items: ProductConstants.conditionsShort
                        .map(
                          (c) => DropdownMenuItem(
                            value: c,
                            child: Text(
                              c,
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setS(() => selectedCondition = v),
                  ),

                  // Thông tin in trên tem
                  _input(
                    labelInfoC,
                    "Thông tin in trên tem",
                    Icons.local_offer_outlined,
                  ),

                  // Ghi chú sản phẩm
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextFormField(
                      controller: labelNoteC,
                      maxLines: 2,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú',
                        hintText: 'Ghi chú thêm về sản phẩm...',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.note_alt_outlined, size: 18),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),

                  // IMEI/Serial (read-only) - chỉ hiện nếu enableSerial
                  if (_enableSerial)
                    _input(
                      imeiC,
                      _terms.specialField1Label,
                      Icons.fingerprint,
                      readOnly: true,
                    ),

                  // Giá vốn - KHÓA nếu đã nhập kho chính hoặc đã bán, ẩn nếu không có quyền
                  if (_canViewCostPrice) ...[
                    if (!p.isPending || p.status == 0)
                      InputDecorator(
                        decoration: const InputDecoration(
                          labelText: "Giá vốn (đã nhập kho - không đổi)",
                          prefixIcon: Icon(
                            Icons.lock,
                            size: 16,
                            color: Colors.grey,
                          ),
                          filled: true,
                          fillColor: Color(0xFFF5F5F5),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        child: Text(
                          CurrencyTextField.formatDisplay(p.cost),
                          style: AppTextStyles.subtitle1.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                      )
                    else
                      _input(
                        costC,
                        "Giá vốn (k)",
                        Icons.money,
                        type: TextInputType.number,
                        suffix: "k",
                      ),
                  ],

                  // Giá bán
                  _input(
                    priceC,
                    "Giá bán (k)",
                    Icons.sell,
                    type: TextInputType.number,
                    suffix: "k",
                  ),

                  // Phase 2: Food module - Expiry & Batch fields
                  if (_enableExpiry || _enableBatch) ...[
                    const Divider(height: 30, thickness: 1),
                    Text(
                      "HẠN SỬ DỤNG",
                      style: AppTextStyles.headline4.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange.shade700,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (_enableExpiry) ...[
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate:
                                expiryDate ??
                                DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 365),
                            ),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365 * 5),
                            ),
                            helpText: 'Chọn ngày hết hạn',
                          );
                          if (picked != null) {
                            setS(() => expiryDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Ngày hết hạn',
                            prefixIcon: Icon(
                              Icons.event,
                              color: Colors.orange.shade600,
                            ),
                            suffixIcon: expiryDate != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () =>
                                        setS(() => expiryDate = null),
                                  )
                                : null,
                          ),
                          child: Text(
                            expiryDate != null
                                ? DateFormat('dd/MM/yyyy').format(expiryDate!)
                                : 'Chưa chọn',
                            style: TextStyle(
                              color: expiryDate != null
                                  ? Colors.black
                                  : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],

                    if (_enableBatch) ...[
                      const SizedBox(height: 12),
                      _input(batchC, "Số lô hàng", Icons.qr_code_2, caps: true),
                    ],
                  ],

                  // Số lượng và Nhà cung cấp
                  Row(
                    children: [
                      Expanded(
                        flex: 1,
                        child: _input(
                          qtyC,
                          "SL",
                          Icons.add_box,
                          type: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Nhà cung cấp (KHÓA - không cho thay đổi)
                      Expanded(
                        flex: 2,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: "Nhà cung cấp (không đổi)",
                            prefixIcon: Icon(
                              Icons.lock,
                              size: 16,
                              color: Colors.grey,
                            ),
                            filled: true,
                            fillColor: Color(0xFFF5F5F5),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            supplier ?? 'Không có',
                            style: AppTextStyles.subtitle1.copyWith(
                              color: Colors.black54,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("HỦY"),
              ),
              ElevatedButton(
                onPressed: isSaving ? null : () => saveProcess(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2962FF),
                ),
                child: const Text(
                  "CẬP NHẬT",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _getStatusText(int status) {
    switch (status) {
      case 1:
        return "Đã nhận";
      case 2:
        return "Đang sửa";
      case 3:
        return "Hoàn thành";
      case 4:
        return "Đã giao";
      default:
        return "Không rõ";
    }
  }

  Widget _warningItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        text,
        style: AppTextStyles.subtitle1.copyWith(
          color: AppColors.onSurface.withOpacity(0.8),
        ),
      ),
    );
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1:
        return AppColors.repairReceived;
      case 2:
        return AppColors.repairRepairing;
      case 3:
        return AppColors.repairDone;
      case 4:
        return AppColors.repairDelivered;
      default:
        return Colors.grey;
    }
  }
}
