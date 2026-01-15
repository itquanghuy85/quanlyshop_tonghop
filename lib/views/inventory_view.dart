import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../utils/money_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../models/inventory_check_model.dart';
import '../models/debt_model.dart';
import 'create_sale_view.dart';
import '../services/sync_orchestrator.dart';
import '../services/unified_printer_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../services/event_bus.dart';
import '../services/supplier_service.dart';
import '../services/firestore_service.dart';
import '../services/first_time_guide_service.dart';
import 'supplier_list_view.dart';
import '../utils/sku_generator.dart';
import '../widgets/printer_selection_dialog.dart';
import '../models/printer_types.dart';
import 'stock_in_view.dart';
import 'global_search_view.dart';
import 'fast_stock_in_view.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/validated_text_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import '../widgets/custom_app_bar.dart';

class InventoryView extends StatefulWidget {
  final String role;
  const InventoryView({super.key, required this.role});
  @override
  State<InventoryView> createState() => _InventoryViewState();
}

class _InventoryViewState extends State<InventoryView>
    with TickerProviderStateMixin {
  final db = DBHelper();
  final supplierService = SupplierService();
  List<Product> _products = [];
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  int _unsyncedCount = 0;
  bool _isAdmin = false;
  bool _hasInventoryAccess = false;
  String _searchQuery = "";
  bool _showOutOfStock = false; // Hiển thị cả hàng hết
  String _filterType =
      'TẤT CẢ'; // Filter theo loại: TẤT CẢ, DIEN_THOAI, PHỤ KIỆN, LINH KIỆN
  bool _showOnlyPending = false; // Filter chỉ hiện kho tạm

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
  final MobileScannerController _scannerController = MobileScannerController();
  InventoryCheck? _currentCheck;

  // Layout sizing constants
  final double _pad = 12.0;
  final double _cardPadding = 12.0;
  final double _iconSize = 20.0;
  final double _titleFontSize = 18.0;
  final double _smallFontSize = 11.0;
  final double _btnMinHeight = 44.0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    // ensure UI updates when user switches tabs
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _init();
    // Re-enable inventory check initialization for QR check
    _initCheckData();
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
      title: 'Danh Sách Sản Phẩm',
      icon: Icons.inventory_2,
      color: Colors.blue,
      steps: const [
        GuideStep(
          title: '📦 Tồn kho hiện tại',
          description: 'Danh sách tất cả sản phẩm trong kho. Lọc theo loại hoặc tìm kiếm nhanh.',
          icon: Icons.list,
          iconColor: Colors.blue,
        ),
        GuideStep(
          title: '🔍 Tìm kiếm',
          description: 'Nhấn icon kính lúp để tìm theo tên, IMEI, SKU. Hỗ trợ tìm kiếm toàn cục.',
          icon: Icons.search,
          iconColor: Colors.purple,
        ),
        GuideStep(
          title: '🛒 Bán hàng nhanh',
          description: 'Nhấn vào sản phẩm để xem chi tiết, hoặc vuốt để bán nhanh/in tem.',
          icon: Icons.shopping_cart,
          iconColor: Colors.green,
        ),
        GuideStep(
          title: '✏️ Chỉnh sửa giá',
          description: 'Admin có thể chỉnh sửa giá bán, giá nhập trực tiếp từ chi tiết sản phẩm.',
          icon: Icons.edit,
          iconColor: Colors.orange,
        ),
      ],
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
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

  void _showProductDetail(Product p) async {
    HapticFeedback.lightImpact();
    final repairs = await db.getRepairsByImei(p.imei ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
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
            if (p.isPending) ...[
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
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                              fontSize: 14,
                            ),
                          ),
                          if (p.pendingSupplier != null)
                            Text(
                              'NCC dự kiến: ${p.pendingSupplier}',
                              style: TextStyle(
                                color: Colors.orange.shade600,
                                fontSize: 12,
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
              p.name,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: p.isPending
                    ? Colors.orange.shade800
                    : const Color(0xFF2962FF),
              ),
            ),
            const SizedBox(height: 15),
            _detailItem("Chi tiết máy", p.capacity ?? ""),
            _detailItem("IMEI/Serial", p.imei ?? "N/A"),
            _detailItem(
              "Nhà cung cấp",
              p.isPending
                  ? (p.pendingSupplier ?? "Chưa xác nhận")
                  : (p.supplier ?? "N/A"),
            ),
            _detailItem(
              "Giá nhập",
              p.isPending
                  ? "Chờ xác nhận"
                  : "${MoneyUtils.formatCurrency(p.cost)} đ",
              color: p.isPending ? Colors.orange : null,
            ),
            _detailItem(
              "Giá bán",
              p.isPending
                  ? "Chờ xác nhận"
                  : "${MoneyUtils.formatCurrency(p.price)} đ",
              color: p.isPending ? Colors.orange : Colors.red,
            ),
            _detailItem(
              "Thanh toán",
              p.isPending ? "Chờ xác nhận" : (p.paymentMethod ?? "N/A"),
            ),
            _detailItem(
              "Cập nhật cuối",
              p.updatedAt != null
                  ? DateFormat(
                      'dd/MM/yyyy HH:mm',
                    ).format(DateTime.fromMillisecondsSinceEpoch(p.updatedAt!))
                  : "N/A",
              color: Colors.grey,
            ),
            if (repairs.isNotEmpty) ...[
              const Divider(height: 30),
              const Text(
                "LỊCH SỬ SỬA CHỮA",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2962FF),
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
                        style: const TextStyle(
                          fontSize: 12,
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
                  label: const Text(
                    "XÁC NHẬN GIÁ - CHUYỂN KHO CHÍNH",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
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
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      // Show printer selection dialog directly
                      try {
                        final printerConfig = await showPrinterSelectionDialog(
                          context,
                        );
                        if (printerConfig != null) {
                          final printerType =
                              printerConfig['type'] as PrinterType?;
                          final bluetoothPrinter =
                              printerConfig['bluetoothPrinter']
                                  as BluetoothPrinterConfig?;
                          final wifiIp = printerConfig['wifiIp'] as String?;
                          final success =
                              await UnifiedPrinterService.printProductQRLabel(
                                p.toMap(),
                                customMac: bluetoothPrinter?.macAddress,
                                printerType: printerType,
                                wifiIp: wifiIp,
                              );
                          if (success) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã in tem thành công!'),
                                ),
                              );
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('In tem thất bại!'),
                                ),
                              );
                            }
                          }
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('Lỗi: $e')));
                        }
                      }
                    },
                    icon: const Icon(Icons.qr_code_2, color: Colors.white),
                    label: const Text(
                      "IN TEM QR",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 8),
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
                    label: const Text(
                      "CHỈNH SỬA",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(vertical: 8),
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
                    label: const Text(
                      "TẠO ĐƠN HÀNG",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2962FF),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close),
                    label: const Text("ĐÓNG", style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
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

  void _createSaleOrder(Product p) {
    HapticFeedback.mediumImpact();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateSaleView(preSelectedProduct: p)),
    ).then((_) => _refresh());
  }

  void _showEditProductDialog(Product p) {
    final nameCtrl = TextEditingController(text: p.name);
    final capacityCtrl = TextEditingController(text: p.capacity ?? '');
    final imeiCtrl = TextEditingController(text: p.imei ?? '');
    final supplierCtrl = TextEditingController(text: p.supplier ?? '');
    final costCtrl = TextEditingController(
      text: MoneyUtils.formatCurrency(p.cost),
    );
    final priceCtrl = TextEditingController(
      text: MoneyUtils.formatCurrency(p.price),
    );
    final quantityCtrl = TextEditingController(text: p.quantity.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chỉnh sửa sản phẩm'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValidatedTextField(
                controller: nameCtrl,
                label: 'Tên sản phẩm',
                uppercase: true,
                customValidator: (val) =>
                    val.isEmpty ? 'Vui lòng nhập tên sản phẩm' : null,
              ),
              const SizedBox(height: 12),
              ValidatedTextField(
                controller: capacityCtrl,
                label: 'Chi tiết máy',
              ),
              const SizedBox(height: 12),
              ValidatedTextField(controller: imeiCtrl, label: 'IMEI/Serial'),
              const SizedBox(height: 12),
              ValidatedTextField(
                controller: supplierCtrl,
                label: 'Nhà cung cấp',
              ),
              const SizedBox(height: 12),
              CurrencyTextField(controller: costCtrl, label: 'Giá nhập (VNĐ)'),
              const SizedBox(height: 12),
              CurrencyTextField(controller: priceCtrl, label: 'Giá bán (VNĐ)'),
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
                final newCost = CurrencyTextField.getValueWithMultiply(
                  costCtrl,
                );

                // Nếu sản phẩm đang ở kho tạm và giờ có giá vốn > 0
                // → Chuyển sang kho chính (isPending = false)
                final shouldTransferToMainInventory =
                    p.isPending && newCost > 0;

                final updatedProduct = p.copyWith(
                  name: nameCtrl.text.trim().toUpperCase(),
                  capacity: capacityCtrl.text.trim(),
                  imei: imeiCtrl.text.trim(),
                  supplier: supplierCtrl.text.trim(),
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
                          const Text(
                            'Bạn vừa thay đổi giá của sản phẩm. Điều này sẽ ảnh hưởng đến:',
                            style: TextStyle(fontWeight: FontWeight.bold),
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
                          const Text(
                            'Để cập nhật chính xác, bạn cần sửa lại từng đơn hàng đã tạo.',
                            style: TextStyle(
                              color: AppColors.error,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
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
                  'Đã cập nhật sản phẩm',
                  color: Colors.green,
                );
              } catch (e) {
                NotificationService.showSnackBar(
                  'Lỗi cập nhật sản phẩm: $e',
                  color: Colors.red,
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
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
              title: const Text('Xóa hàng trong kho'),
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
    bool deleteRelatedDebt = false;
    bool deleteImportHistory = false;
    bool deleteRelatedExpense = false;
    bool deleteRelatedSale = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red.shade700),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('XÓA SẢN PHẨM', style: TextStyle(fontSize: 16)),
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
                      if (p.imei != null && p.imei!.isNotEmpty)
                        Text(
                          'IMEI: ${p.imei}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      Text(
                        'Giá vốn: ${MoneyUtils.formatCurrency(p.cost)}đ',
                        style: const TextStyle(fontSize: 12),
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
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '⚠️ LƯU Ý QUAN TRỌNG:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '• Số liệu TÀI CHÍNH ĐÃ CHỐT sẽ KHÔNG thay đổi\n'
                        '• Chọn các mục bên dưới để xóa dữ liệu liên quan\n'
                        '• Dữ liệu CHƯA CHỐT sẽ bị ảnh hưởng',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Options xóa liên quan
                const Text(
                  'Tùy chọn xóa dữ liệu liên quan:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: deleteRelatedDebt,
                  onChanged: (v) => setS(() => deleteRelatedDebt = v ?? false),
                  title: const Text(
                    'Xóa công nợ NCC liên quan',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Công nợ nhập hàng với NCC',
                    style: TextStyle(fontSize: 11),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: deleteImportHistory,
                  onChanged: (v) =>
                      setS(() => deleteImportHistory = v ?? false),
                  title: const Text(
                    'Xóa lịch sử nhập hàng',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Xóa khỏi báo cáo NCC',
                    style: TextStyle(fontSize: 11),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: deleteRelatedExpense,
                  onChanged: (v) =>
                      setS(() => deleteRelatedExpense = v ?? false),
                  title: const Text(
                    'Xóa chi phí liên quan',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'Chi phí nhập hàng, vận chuyển...',
                    style: TextStyle(fontSize: 11),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                CheckboxListTile(
                  value: deleteRelatedSale,
                  onChanged: (v) => setS(() => deleteRelatedSale = v ?? false),
                  title: const Text(
                    'Xóa đơn bán chứa SP này',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    'CẢNH BÁO: Xóa đơn bán sẽ ảnh hưởng doanh thu',
                    style: TextStyle(fontSize: 11, color: Colors.red.shade700),
                  ),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
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
                      deleteRelatedDebt: deleteRelatedDebt,
                      deleteImportHistory: deleteImportHistory,
                      deleteRelatedExpense: deleteRelatedExpense,
                      deleteRelatedSale: deleteRelatedSale,
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
              child: const Text('XÓA SẢN PHẨM'),
            ),
          ],
        ),
      ),
    );
  }

  /// Xóa sản phẩm với các options liên quan
  Future<void> _deleteProductWithOptions(
    Product p, {
    bool deleteRelatedDebt = false,
    bool deleteImportHistory = false,
    bool deleteRelatedExpense = false,
    bool deleteRelatedSale = false,
    String? reason,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? 'NV';
      final productId = p.firestoreId ?? '';
      final imei = p.imei ?? '';

      // 1. GHI AUDIT LOG trước khi xóa
      await db.logAction(
        userId: user?.uid ?? '0',
        userName: userName,
        action: 'XÓA SẢN PHẨM',
        type: 'PRODUCT',
        targetId: productId,
        desc:
            'Xóa SP: ${p.name} | IMEI: $imei | Giá vốn: ${p.cost} | Lý do: ${reason ?? "Không ghi"}',
      );

      // 2. Xóa công nợ NCC liên quan (nếu chọn)
      if (deleteRelatedDebt && productId.isNotEmpty) {
        final debts = await db.getDebtsByProductId(productId);
        for (var debt in debts) {
          final debtId = debt['id'] as int?;
          if (debtId != null) {
            await db.softDeleteDebt(
              debtId,
              reason: 'Xóa theo sản phẩm ${p.name}',
            );

            // Log xóa công nợ
            await db.logAction(
              userId: user?.uid ?? '0',
              userName: userName,
              action: 'XÓA CÔNG NỢ (THEO SP)',
              type: 'DEBT',
              targetId: debt['firestoreId']?.toString(),
              desc: 'Xóa công nợ NCC theo SP: ${p.name}',
            );
          }
        }
      }

      // 3. Xóa lịch sử nhập hàng (nếu chọn) - xóa thật vì bảng không có cột deleted
      if (deleteImportHistory && productId.isNotEmpty) {
        await db.deleteImportHistoryByProduct(productId);

        await db.logAction(
          userId: user?.uid ?? '0',
          userName: userName,
          action: 'XÓA LỊCH SỬ NHẬP (THEO SP)',
          type: 'IMPORT_HISTORY',
          targetId: productId,
          desc: 'Xóa lịch sử nhập theo SP: ${p.name}',
        );
      }

      // 4. Xóa chi phí liên quan (nếu chọn)
      if (deleteRelatedExpense && productId.isNotEmpty) {
        final expenses = await db.getExpensesByProductId(productId, imei: imei);
        for (var expense in expenses) {
          final expenseId = expense['id'] as int?;
          if (expenseId != null) {
            await db.deleteExpense(expenseId);

            await db.logAction(
              userId: user?.uid ?? '0',
              userName: userName,
              action: 'XÓA CHI PHÍ (THEO SP)',
              type: 'EXPENSE',
              targetId: expense['firestoreId']?.toString(),
              desc:
                  'Xóa chi phí: ${expense['title']} | ${expense['amount']}đ | theo SP: ${p.name}',
            );
          }
        }
      }

      // 5. Xóa đơn bán chứa sản phẩm này (nếu chọn) - CẢNH BÁO: ảnh hưởng doanh thu
      if (deleteRelatedSale && imei.isNotEmpty) {
        final sales = await db.getSalesByProductImei(imei);
        for (var sale in sales) {
          final saleId = sale['id'] as int?;
          if (saleId != null) {
            await db.deleteSale(saleId);

            await db.logAction(
              userId: user?.uid ?? '0',
              userName: userName,
              action: 'XÓA ĐƠN BÁN (THEO SP)',
              type: 'SALE',
              targetId: sale['firestoreId']?.toString(),
              desc:
                  'Xóa đơn bán: ${sale['customerName']} | ${sale['totalPrice']}đ | theo SP: ${p.name}',
            );
          }
        }
      }

      // 6. XÓA sản phẩm (xóa thật vì bảng không có cột deleted)
      if (p.id != null) {
        // Queue delete sync via SyncOrchestrator trước khi xóa local
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.product,
          entityId: p.id!,
          firestoreId: p.firestoreId,
          operation: SyncOperation.delete,
          data: null,
        );

        // Xóa sản phẩm khỏi local DB
        await db.deleteProduct(p.id!);

        // SYNC NGAY LẬP TỨC
        await SyncOrchestrator().syncAll();
      }

      await _refresh();
      NotificationService.showSnackBar(
        'Đã xóa sản phẩm: ${p.name}',
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar(
        'Lỗi xóa sản phẩm: $e',
        color: Colors.red,
      );
    }
  }

  Widget _detailItem(String l, String v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          l,
          style: AppTextStyles.caption.copyWith(color: AppColors.onSurface),
        ),
        Text(
          v,
          style: AppTextStyles.body2.copyWith(
            fontWeight: FontWeight.bold,
            color: color ?? AppColors.onSurface,
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
    if (n.startsWith("PK-")) return Colors.purple; // Phụ kiện
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
    if (!mounted) return;
    setState(() {
      _isAdmin = perms['allowViewInventory'] ?? false;
      _hasInventoryAccess = perms['allowViewInventory'] ?? false;
    });
    _refresh();
  }

  Future<void> _initCheckData() async {
    await _loadOrCreateCurrentCheck();
    await _loadCheckItems();
  }

  Future<void> _refresh() async {
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _isSelectionMode = false;
    });
    // Lấy TẤT CẢ sản phẩm thay vì chỉ còn hàng
    final data = await db.getAllProducts();
    // Sắp xếp theo thời gian cập nhật mới nhất lên đầu
    data.sort((a, b) => (b.updatedAt ?? 0).compareTo(a.updatedAt ?? 0));
    final suppliers = await supplierService.getSuppliers();
    final unsyncedCount = await db.getUnsyncedQuickInputCodesCount();
    if (!mounted) return;
    setState(() {
      _products = data;
      _suppliers = suppliers.map((s) => s.toMap()).toList();
      _unsyncedCount = unsyncedCount;
      _isLoading = false;
    });
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
            desc: "Đã xóa ${p.name} (IMEI: ${p.imei})",
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
      final checks = await db.getInventoryChecks();
      final today = DateTime.now();
      final todayKey = DateFormat('yyyy-MM-dd').format(today);

      // Find today's check or create new one
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
        itemName: 'Sản phẩm quét: $imei',
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
          title: const Text("QUẢN LÝ KHO TỔNG"),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          automaticallyImplyLeading: true,
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2, size: 64, color: Colors.grey),
              SizedBox(height: 16),
              Text(
                "Bạn không có quyền truy cập\nmàn hình quản lý kho",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.grey),
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
            '${_products.length} sản phẩm${_unsyncedCount > 0 ? ' • $_unsyncedCount chưa đồng bộ' : ''}',
        accentColor: AppBarAccents.inventory,
        actions: [
          IconButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CreateSaleView()),
              ).then((_) => _refresh());
            },
            icon: Icon(
              Icons.shopping_cart_checkout_rounded,
              color: AppBarAccents.inventory,
              size: 22,
            ),
            tooltip: 'Bán hàng nhanh',
            splashRadius: 20,
          ),
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GlobalSearchView(role: widget.role),
              ),
            ),
            icon: Icon(
              Icons.search_rounded,
              color: AppBarAccents.inventory,
              size: 22,
            ),
            tooltip: 'Tìm kiếm toàn app',
            splashRadius: 20,
          ),
          IconButton(
            onPressed: _refresh,
            icon: Icon(
              Icons.refresh_rounded,
              color: AppBarAccents.inventory,
              size: 22,
            ),
            tooltip: 'Làm mới',
            splashRadius: 20,
          ),
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SupplierListView()),
            ),
            icon: Icon(
              Icons.business_center,
              size: 18,
              color: AppBarAccents.inventory.withOpacity(0.7),
            ),
            label: Text(
              'NCC',
              style: AppTextStyles.caption.copyWith(
                color: AppBarAccents.inventory.withOpacity(0.7),
              ),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildInventoryTab()],
            ),
          ),
          // Bottom navigation row (THƯ VIỆN đã ẩn theo yêu cầu)
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Nhập kho nhanh button (mở rộng)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const StockInView()),
                    ).then((_) => _refresh()),
                    icon: Icon(Icons.add_box_rounded, size: _iconSize),
                    label: Text("NHẬP KHO", style: AppTextStyles.caption),
                    style: AppButtonStyles.elevatedButtonStyle,
                  ),
                ),
                const SizedBox(width: 8),
                // Nhập nhanh button
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FastStockInView(),
                      ),
                    ).then((_) => _refresh()),
                    icon: Icon(Icons.flash_on, size: _iconSize),
                    label: Text("NHẬP NHANH", style: AppTextStyles.caption),
                    style: AppButtonStyles.elevatedButtonStyle,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
    // Lọc theo search query
    var filteredList = _products
        .where(
          (p) =>
              p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
              (p.imei ?? "").contains(_searchQuery),
        )
        .toList();

    // Lọc theo loại hàng
    if (_filterType != 'TẤT CẢ') {
      filteredList = filteredList.where((p) => p.type == _filterType).toList();
    }

    // Lọc theo trạng thái Kho Tạm
    if (_showOnlyPending) {
      filteredList = filteredList.where((p) => p.isPending).toList();
    }

    // Nếu không bật showOutOfStock, chỉ hiện còn hàng (quantity > 0)
    if (!_showOutOfStock) {
      filteredList = filteredList.where((p) => p.quantity > 0).toList();
    }

    // Tính tổng kho và vốn THEO FILTER (thay đổi theo loại hàng đang lọc)
    List<Product> summaryProducts;
    if (_filterType == 'TẤT CẢ') {
      summaryProducts = _products.where((p) => p.quantity > 0).toList();
    } else {
      summaryProducts = _products
          .where((p) => p.quantity > 0 && p.type == _filterType)
          .toList();
    }
    int totalQty = summaryProducts.fold(0, (sum, item) => sum + item.quantity);
    int totalCapital = summaryProducts.fold(
      0,
      (sum, item) => sum + (item.cost * item.quantity),
    );

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
                      style: AppTextStyles.body1.copyWith(
                        color: AppColors.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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
                      onRefresh: _refresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                        itemCount: filteredList.length,
                        itemBuilder: (ctx, i) =>
                            _buildProfessionalCard(filteredList[i], i + 1),
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
              // Type selector
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: InputDecoration(
                  labelText: "Loại sản phẩm kiểm kho",
                  prefixIcon: const Icon(Icons.category),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: const [
                  DropdownMenuItem(
                    value: "DIEN_THOAI",
                    child: Text("📱 Điện thoại"),
                  ),
                  DropdownMenuItem(
                    value: "PHỤ KIỆN",
                    child: Text("🔧 Phụ kiện"),
                  ),
                ],
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
                        style: TextStyle(fontSize: _smallFontSize),
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
                "Tổng sản phẩm",
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
                            Text("IMEI: ${item.imei ?? 'N/A'}"),
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
                                style: TextStyle(
                                  fontSize: 16,
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
            "${MoneyUtils.formatCurrency(capital)} đ",
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
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          val,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
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
          style: TextStyle(
            color: color ?? const Color(0xFF2962FF),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildSearchBox() {
    // Đếm sản phẩm hết hàng
    final outOfStockCount = _products.where((p) => p.quantity <= 0).length;

    return Column(
      children: [
        // Filter theo loại hàng
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTypeFilterChip('TẤT CẢ', Icons.apps, Colors.blue),
                const SizedBox(width: 8),
                _buildTypeFilterChip(
                  'DIEN_THOAI',
                  Icons.smartphone,
                  Colors.indigo,
                ),
                const SizedBox(width: 8),
                _buildTypeFilterChip(
                  'PHỤ KIỆN',
                  Icons.headset_mic,
                  Colors.green,
                ),
                const SizedBox(width: 8),
                // Filter Kho Tạm
                _buildPendingFilterChip(),
              ],
            ),
          ),
        ),
        // Search box và toggle hết hàng
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: "Tìm máy, phụ kiện hoặc IMEI...",
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
                          style: TextStyle(
                            fontSize: 11,
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
        ? 'Điện thoại'
        : type == 'PHỤ KIỆN'
        ? 'Phụ kiện'
        : type == 'LINH KIỆN'
        ? 'Linh kiện'
        : 'Tất cả';

    // Đếm số lượng theo type
    int count = type == 'TẤT CẢ'
        ? _products.where((p) => p.quantity > 0 || _showOutOfStock).length
        : _products
              .where(
                (p) => p.type == type && (p.quantity > 0 || _showOutOfStock),
              )
              .length;

    return InkWell(
      onTap: () => setState(() => _filterType = type),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
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
              style: TextStyle(
                fontSize: 12,
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
                  style: const TextStyle(
                    fontSize: 10,
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

  Widget _buildPendingFilterChip() {
    final pendingCount = _products.where((p) => p.isPending).length;
    final isSelected = _showOnlyPending;

    return InkWell(
      onTap: () => setState(() => _showOnlyPending = !_showOnlyPending),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.orange.withOpacity(0.15)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? Colors.orange : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.hourglass_empty,
              size: 16,
              color: isSelected ? Colors.orange : Colors.grey,
            ),
            const SizedBox(width: 4),
            Text(
              'Kho tạm',
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? Colors.orange.shade700
                    : Colors.grey.shade700,
              ),
            ),
            if (pendingCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$pendingCount',
                  style: const TextStyle(
                    fontSize: 10,
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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? Colors.red
              : (isPending ? Colors.orange : Colors.transparent),
          width: isPending ? 2 : (isSelected ? 2 : 0),
        ),
      ),
      elevation: 2,
      color: isPending
          ? Colors.orange.shade50
          : null, // Nền cam nhạt cho kho tạm
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
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.all(_cardPadding),
          child: Row(
            children: [
              // STT (Số thứ tự)
              if (index != null) ...[
                Container(
                  width: 28,
                  height: 28,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: isPending
                        ? Colors.orange.withOpacity(0.2)
                        : AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$index',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isPending
                            ? Colors.orange.shade700
                            : AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
              // Brand Icon with Pending badge
              Stack(
                children: [
                  Container(
                    padding: EdgeInsets.all(_cardPadding - 2),
                    decoration: BoxDecoration(
                      color: isPending
                          ? Colors.orange.withAlpha(40)
                          : _getBrandColor(p.name).withAlpha(25),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      p.type == 'DIEN_THOAI'
                          ? Icons.phone_iphone
                          : Icons.headset_mic,
                      color: isPending ? Colors.orange : _getBrandColor(p.name),
                      size: _iconSize,
                    ),
                  ),
                  if (isPending)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.orange,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.hourglass_empty,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),

              SizedBox(width: _pad),

              // Product Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isPending)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'KHO TẠM',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Text(
                            p.name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: _titleFontSize - 2,
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
                    const SizedBox(height: 4),
                    Text(
                      p.capacity ?? "Chi tiết trống",
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.blueGrey,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.fingerprint,
                          size: 12,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            p.imei ?? "N/A",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            "Nhập: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(p.createdAt))}",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Price and Quantity
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (isPending) ...[
                    // Hiển thị trạng thái chờ xác nhận giá cho kho tạm
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.orange.shade300),
                      ),
                      child: const Text(
                        'Chờ giá',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ] else ...[
                    Text(
                      "${MoneyUtils.formatCurrency(p.price)} đ",
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: _smallFontSize + 2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.withAlpha(25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "TỒN: ${p.quantity}",
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: _smallFontSize - 1,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              // Selection indicator
              if (isSelected) ...[
                const SizedBox(width: 8),
                const Icon(Icons.check_circle, color: Colors.red, size: 24),
              ],
            ],
          ),
        ),
      ),
    );
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
                "Vui lòng chọn nhóm sản phẩm!",
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
              if (payMethod != "CÔNG NỢ") {
                final expFId = 'exp_${ts}_${p.name.hashCode}';
                final expData = {
                  'firestoreId': expFId,
                  'title': "NHẬP HÀNG: ${p.name}",
                  'amount': p.cost * p.quantity,
                  'category': "NHẬP HÀNG",
                  'date': ts,
                  'paymentMethod': payMethod,
                  'note': "Nhập từ $supplier",
                };
                final expenseId = await db.insertExpense(expData);

                // Queue sync via SyncOrchestrator
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.expense,
                  entityId: expenseId,
                  firestoreId: expFId,
                  operation: SyncOperation.create,
                  data: expData,
                );
              } else {
                final debtFId = 'debt_inv_$ts';
                final debtData = {
                  'firestoreId': debtFId,
                  'personName': supplier,
                  'totalAmount': p.cost * p.quantity,
                  'paidAmount': 0,
                  'type': "SHOP_OWES",
                  'status': "ACTIVE",
                  'createdAt': ts,
                  'note': "Nợ tiền máy ${p.name}",
                };
                final debtId = await db.insertDebt(debtData);

                // Queue sync via SyncOrchestrator
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.debt,
                  entityId: debtId,
                  firestoreId: debtFId,
                  operation: SyncOperation.create,
                  data: debtData,
                );
              }
              await db.upsertProduct(p);

              // Get product ID and queue sync
              final savedProduct = await db.getProductByFirestoreId(
                p.firestoreId ?? 'prod_${p.createdAt}',
              );
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
                    items: const [
                      DropdownMenuItem(
                        value: "DIEN_THOAI",
                        child: Text("DIEN_THOAI"),
                      ),
                      DropdownMenuItem(
                        value: "PHỤ KIỆN",
                        child: Text("PHỤ KIỆN"),
                      ),
                    ],
                    onChanged: (v) => setS(() => type = v!),
                    decoration: const InputDecoration(labelText: "Loại hàng"),
                  ),

                  // Tên máy
                  _input(
                    nameC,
                    "Tên máy *",
                    Icons.phone_android,
                    f: nameF,
                    next: imeiF,
                    caps: true,
                  ),

                  // Chi tiết
                  _input(
                    detailC,
                    "Chi tiết (Dung lượng - Màu...)",
                    Icons.info_outline,
                    caps: true,
                  ),

                  // IMEI/Serial
                  _input(
                    imeiC,
                    "Số IMEI / Serial",
                    Icons.fingerprint,
                    f: imeiF,
                    next: costF,
                    type: TextInputType.number,
                  ),

                  // Giá vốn
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

                  // SKU Section
                  const Divider(height: 30, thickness: 1),
                  const Text(
                    "MÃ HÀNG",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2962FF),
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
                    items: const [
                      DropdownMenuItem(value: "IP", child: Text("IP - iPhone")),
                      DropdownMenuItem(
                        value: "SS",
                        child: Text("SS - Samsung"),
                      ),
                      DropdownMenuItem(
                        value: "PIN",
                        child: Text("PIN - Pin sạc"),
                      ),
                      DropdownMenuItem(
                        value: "MH",
                        child: Text("MH - Màn hình"),
                      ),
                      DropdownMenuItem(
                        value: "PK",
                        child: Text("PK - Phụ kiện"),
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
                            label: Text(
                              m,
                              style: const TextStyle(fontSize: 11),
                            ),
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
                // Sync ngay lập tức để tránh race condition với realtime sync
                await SyncOrchestrator().syncAll();
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

              // 3. Xử lý thanh toán
              if (selectedPaymentMethod == 'CÔNG NỢ') {
                // Tạo công nợ nhà cung cấp
                final supplierPhone = supplierData['phone']?.toString() ?? '';
                final debt = Debt(
                  personName: selectedSupplier!,
                  phone: supplierPhone,
                  totalAmount: cost * p.quantity,
                  paidAmount: 0,
                  type: 'SHOP_OWES',
                  status: 'ACTIVE',
                  createdAt: ts,
                  note: 'Công nợ xác nhận giá từ Kho Tạm - ${p.name}',
                  linkedId: p.firestoreId,
                );
                debt.firestoreId = "debt_confirm_${ts}_${p.imei}";
                await db.upsertDebt(debt);

                final debtId = await db.getDebtIdByFirestoreId(
                  debt.firestoreId!,
                );
                if (debtId != null) {
                  await SyncOrchestrator().enqueue(
                    entityType: SyncEntityType.debt,
                    entityId: debtId,
                    firestoreId: debt.firestoreId,
                    operation: SyncOperation.create,
                    data: debt.toMap(),
                  );
                }
                EventBus().emit('debts_changed');
              } else {
                // Tạo expense cho tiền mặt/chuyển khoản
                final expFId = "exp_confirm_${ts}_${p.imei}";
                final exp = {
                  'firestoreId': expFId,
                  'title': 'Xác nhận giá Kho Tạm - $selectedSupplier',
                  'amount': cost * p.quantity,
                  'category': 'NHẬP HÀNG',
                  'date': ts,
                  'note': 'Xác nhận giá ${p.name} từ Kho Tạm',
                  'paymentMethod': selectedPaymentMethod,
                  'createdAt': ts,
                };
                final expenseId = await db.insertExpense(exp);
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.expense,
                  entityId: expenseId,
                  firestoreId: expFId,
                  operation: SyncOperation.create,
                  data: exp,
                );
                EventBus().emit('expenses_changed');
              }

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
                const Expanded(
                  child: Text(
                    'Xác nhận giá - Chuyển Kho Chính',
                    style: TextStyle(fontSize: 16),
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
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'IMEI: ${p.imei ?? "N/A"}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        Text(
                          'SL: ${p.quantity}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Giá vốn
                  CurrencyTextField(
                    controller: costC,
                    label: 'GIÁ VỐN (*)',
                    icon: Icons.monetization_on,
                    autoMultiply1000: true,
                  ),
                  const SizedBox(height: 12),

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
                    value: _suppliers.any((s) => s['name'] == selectedSupplier)
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
                    value: selectedPaymentMethod,
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
    final nameC = TextEditingController(text: p.name);
    final imeiC = TextEditingController(text: p.imei ?? '');
    final costC = TextEditingController(
      text: CurrencyTextField.formatDisplay(p.cost),
    );
    final priceC = TextEditingController(
      text: CurrencyTextField.formatDisplay(p.price),
    );
    final detailC = TextEditingController(text: p.capacity ?? '');
    final qtyC = TextEditingController(text: p.quantity.toString());
    final modelC = TextEditingController(text: p.model ?? '');

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

              final updatedP = p.copyWith(
                name: nameC.text.trim().toUpperCase(),
                model: modelC.text.trim().isNotEmpty
                    ? modelC.text.trim()
                    : null,
                imei: imeiC.text.trim(),
                cost: newCost,
                price: CurrencyTextField.parseValue(priceC.text),
                capacity: detailC.text.trim().toUpperCase(),
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
                Navigator.of(context).pop();
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
            title: const Text(
              "CHỈNH SỬA SẢN PHẨM",
              style: TextStyle(
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
                        size: 18,
                        color: Colors.grey,
                      ),
                      filled: true,
                      fillColor: Color(0xFFF5F5F5),
                    ),
                    child: Text(
                      type,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                    ),
                  ),

                  // Tên máy
                  _input(nameC, "Tên máy *", Icons.phone_android, caps: true),

                  // Chi tiết
                  _input(
                    detailC,
                    "Chi tiết (Dung lượng - Màu...)",
                    Icons.info_outline,
                    caps: true,
                  ),

                  // IMEI/Serial (read-only)
                  _input(
                    imeiC,
                    "Số IMEI / Serial",
                    Icons.fingerprint,
                    readOnly: true,
                  ),

                  // Model
                  _input(modelC, "Model", Icons.smartphone, caps: true),

                  // Giá vốn
                  _input(
                    costC,
                    "Giá vốn (k)",
                    Icons.money,
                    type: TextInputType.number,
                    suffix: "k",
                  ),

                  // Giá bán
                  _input(
                    priceC,
                    "Giá bán (k)",
                    Icons.sell,
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
                              size: 18,
                              color: Colors.grey,
                            ),
                            filled: true,
                            fillColor: Color(0xFFF5F5F5),
                          ),
                          child: Text(
                            supplier ?? 'Không có',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black54,
                            ),
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
        style: TextStyle(
          color: AppColors.onSurface.withOpacity(0.8),
          fontSize: 12,
        ),
      ),
    );
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1:
        return Colors.orange;
      case 2:
        return Colors.blue;
      case 3:
        return Colors.green;
      case 4:
        return Colors.grey;
      default:
        return Colors.black;
    }
  }
}
