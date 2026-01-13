import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/money_utils.dart';
import '../models/sale_order_model.dart';
import '../data/db_helper.dart';
import '../services/firestore_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/event_bus.dart';
import '../services/user_service.dart';
import '../services/audit_service.dart';
import '../services/unified_printer_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../models/printer_types.dart';
import '../widgets/printer_selection_dialog.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'create_sale_view.dart';

class SaleDetailView extends StatefulWidget {
  final SaleOrder sale;
  const SaleDetailView({super.key, required this.sale});

  @override
  State<SaleDetailView> createState() => _SaleDetailViewState();
}

class _SaleDetailViewState extends State<SaleDetailView> {
  final db = DBHelper();
  late SaleOrder s;
  final ScreenshotController screenshotController = ScreenshotController();

  String _shopName = "";
  String _shopAddr = "";
  String _shopPhone = "";
  String _logoPath = "";
  bool get _hasLogo => _logoPath.isNotEmpty && File(_logoPath).existsSync();
  bool get _isInstallmentNH => s.paymentMethod.toUpperCase() == "TRẢ GÓP (NH)";
  bool _managerUnlocked = false;
  bool _checkingManager = false;

  // Theme colors cho màn hình chi tiết đơn bán hàng
  final Color _primaryColor = Colors.indigo; // Đồng bộ với create_sale_view
  final Color _accentColor = Colors.indigo.shade600;
  final Color _backgroundColor = const Color(0xFFF8FAFF);

  @override
  void initState() {
    super.initState();
    s = widget.sale;
    _loadShopInfo();
  }

  Future<void> _loadShopInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shopName = prefs.getString('shop_name') ?? "TEN SHOP";
      _shopAddr = prefs.getString('shop_address') ?? "DIA CHI";
      _shopPhone = prefs.getString('shop_phone') ?? "SDT";
      _logoPath = prefs.getString('shop_logo_path') ?? "";
    });
  }

  String _fmtDate(int ms) => DateFormat(
    'HH:mm dd/MM/yyyy',
  ).format(DateTime.fromMillisecondsSinceEpoch(ms));
  String _fmtShort(int? ms) => ms == null
      ? "---"
      : DateFormat(
          'dd/MM/yyyy',
        ).format(DateTime.fromMillisecondsSinceEpoch(ms));

  Future<void> _unlockManager() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("CẦN ĐĂNG NHẬP TÀI KHOẢN QUẢN LÝ")),
      );
      return;
    }
    final perms = await UserService.getCurrentUserPermissions();
    final isSuper = UserService.isCurrentUserSuperAdmin();
    if (!(perms['allowViewSales'] ?? false) && !isSuper) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Chỉ tài khoản quản lý mới được sửa/xóa")),
      );
      return;
    }

    final passCtrl = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("XÁC THỰC QUẢN LÝ"),
        content: TextField(
          controller: passCtrl,
          obscureText: true,
          decoration: const InputDecoration(labelText: "Mật khẩu quản lý"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("XÁC NHẬN"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      setState(() => _checkingManager = true);
      final cred = EmailAuthProvider.credential(
        email: user.email ?? '',
        password: passCtrl.text,
      );
      await user.reauthenticateWithCredential(cred);
      if (mounted) {
        setState(() {
          _managerUnlocked = true;
          _checkingManager = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("ĐÃ MỞ KHÓA CHỈNH SỬA")));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _checkingManager = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Sai mật khẩu quản lý")));
      }
    }
  }

  String _toNoSign(String str) {
    var withDia =
        'àáâãèéêìíòóôõùúýỳỹỷỵửữừứựửữừứựàáâãèéêìíòóôõùúýỳỹỷỵửữừứựửữừứự';
    var withoutDia =
        'aaaaeeeeiioooouuyyyyyuuuuuuuuuuuaaaaeeeeiioooouuyyyyyuuuuuuuuuuu';
    for (int i = 0; i < withDia.length; i++) {
      str = str.replaceAll(withDia[i], withoutDia[i]);
    }
    return str.toUpperCase();
  }

  Future<void> _printWifi() async {
    // Show printer selection dialog
    final messenger = ScaffoldMessenger.of(context);
    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return; // User cancelled

    // Extract printer configuration
    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter =
        printerConfig['bluetoothPrinter'] as BluetoothPrinterConfig?;
    final wifiIp = printerConfig['wifiIp'] as String?;

    try {
      final saleData = {
        'customerName': s.customerName,
        'customerPhone': s.phone,
        'customerAddress': s.address,
        'productNames': s.productNames,
        'productImeis': s.productImeis,
        'warranty': s.warranty ?? 'KO BH',
        'sellerName': s.sellerName,
        'soldAt': s.soldAt,
        'totalPrice': s.totalPrice,
        'firestoreId': s.firestoreId ?? s.id.toString(),
        'shopName': _shopName,
        'shopAddr': _shopAddr,
        'shopPhone': _shopPhone,
      };

      final success = await UnifiedPrinterService.printSaleReceipt(
        saleData,
        PaperSize.mm58,
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
      );

      if (success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Đã in hóa đơn thành công!')),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('In thất bại! Vui lòng kiểm tra cài đặt máy in.'),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Lỗi khi in: $e')));
    }
  }

  Future<void> _openSettlementDialog() async {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController(
      text: MoneyUtils.formatCurrency(
        s.settlementAmount > 0 ? s.settlementAmount : s.loanAmount,
      ),
    );
    final feeCtrl = TextEditingController(
      text: MoneyUtils.formatCurrency(s.settlementFee),
    );
    final noteCtrl = TextEditingController(text: s.settlementNote ?? "");

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("NHẬN TIỀN TỪ NGÂN HÀNG"),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: amountCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyUtils.currencyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: "Số tiền nhận (VNĐ)",
                ),
                validator: (v) => MoneyUtils.validateAmount(
                  v ?? '',
                  min: 1,
                  fieldName: 'Số tiền nhận',
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: feeCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [MoneyUtils.currencyInputFormatter()],
                decoration: const InputDecoration(
                  labelText: "Phí NH giữ lại (VNĐ)",
                ),
                validator: (v) => MoneyUtils.validateAmount(
                  v ?? '',
                  min: 0,
                  fieldName: 'Phí NH',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: "Ghi chú"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(ctx, true);
            },
            child: const Text("XÁC NHẬN"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final parsedReceived = MoneyUtils.parseCurrency(amountCtrl.text);
    final parsedFee = MoneyUtils.parseCurrency(feeCtrl.text);
    final received = parsedReceived > 0 && parsedReceived < 100000
        ? parsedReceived * 1000
        : parsedReceived;
    final fee = parsedFee > 0 && parsedFee < 100000
        ? parsedFee * 1000
        : parsedFee;
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      s.settlementAmount = received;
      s.settlementFee = fee;
      s.settlementNote = noteCtrl.text;
      s.settlementReceivedAt = nowMs;
      s.isSynced = false;
    });

    await db.updateSale(s);

    // Sync settlement to Firestore
    if (s.firestoreId != null) {
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.sale,
        entityId: s.id!,
        firestoreId: s.firestoreId,
        operation: SyncOperation.update,
        data: s.toMap(),
      );
    }

    EventBus().emit('sales_changed');

    if (fee > 0) {
      final expFId = 'exp_${nowMs}_${s.firestoreId.hashCode}';
      final expData = {
        'firestoreId': expFId,
        'title': "Phí NH trả góp ${s.bankName ?? ''}",
        'amount': fee,
        'category': 'Phí NH',
        'date': nowMs,
        'note': s.settlementNote ?? '',
        'paymentMethod': 'CHUYỂN KHOẢN',
      };
      final expenseId = await db.insertExpense(expData);

      // Queue sync expense to cloud via SyncOrchestrator
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.expense,
        entityId: expenseId,
        firestoreId: expFId,
        operation: SyncOperation.create,
        data: expData,
      );
      EventBus().emit('expenses_changed');
    }

    if (!mounted) return;
    AuditService.logAction(
      action: 'SETTLEMENT_RECEIVED',
      entityType: 'sale',
      entityId: s.firestoreId ?? "sale_${s.soldAt}",
      summary: "Nhận ${MoneyUtils.formatCurrency(received)} đ từ NH",
      payload: {'fee': fee, 'bank': s.bankName},
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("ĐÃ GHI NHẬN TIỀN NGÂN HÀNG CHUYỂN")),
    );
    setState(() {});
  }

  Future<void> _openEditSaleDialog() async {
    final formKey = GlobalKey<FormState>();
    final name = TextEditingController(text: s.customerName);
    final phone = TextEditingController(text: s.phone);
    final address = TextEditingController(text: s.address);
    final products = TextEditingController(text: s.productNames);
    final imeis = TextEditingController(text: s.productImeis);
    final totalPrice = TextEditingController(
      text: MoneyUtils.formatCurrency(s.totalPrice),
    );
    final totalCost = TextEditingController(
      text: MoneyUtils.formatCurrency(s.totalCost),
    );
    final notes = TextEditingController(text: s.notes ?? "");
    final warranties = ["KO BH", "1 THÁNG", "3 THÁNG", "6 THÁNG", "12 THÁNG"];
    String warranty = s.warranty ?? "KO BH";
    String payment = s.paymentMethod;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("SỬA ĐƠN BÁN"),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: "Tên khách"),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Nhập tên khách' : null,
                ),
                TextFormField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: "SĐT"),
                ),
                TextFormField(
                  controller: address,
                  decoration: const InputDecoration(labelText: "Địa chỉ"),
                ),
                TextFormField(
                  controller: products,
                  decoration: const InputDecoration(labelText: "Sản phẩm"),
                ),
                TextFormField(
                  controller: imeis,
                  decoration: const InputDecoration(labelText: "IMEI/Serial"),
                ),
                TextFormField(
                  controller: totalPrice,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyUtils.currencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: "Tổng tiền (VNĐ)",
                  ),
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 1,
                    fieldName: 'Tổng tiền',
                  ),
                ),
                TextFormField(
                  controller: totalCost,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyUtils.currencyInputFormatter()],
                  decoration: const InputDecoration(labelText: "Giá vốn (VNĐ)"),
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 0,
                    fieldName: 'Giá vốn',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: warranty,
                  decoration: const InputDecoration(labelText: "Bảo hành"),
                  items: warranties
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => warranty = v ?? warranty,
                ),
                DropdownButtonFormField<String>(
                  initialValue: payment,
                  decoration: const InputDecoration(labelText: "Hình thức"),
                  items:
                      const [
                            "TIỀN MẶT",
                            "CHUYỂN KHOẢN",
                            "CÔNG NỢ",
                            "TRẢ GÓP (NH)",
                          ]
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (v) => payment = v ?? payment,
                ),
                TextField(
                  controller: notes,
                  decoration: const InputDecoration(labelText: "Ghi chú"),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(ctx, true);
            },
            child: const Text("LƯU"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() {
      s.customerName = name.text.trim().toUpperCase();
      s.phone = phone.text.trim();
      s.address = address.text.trim().toUpperCase();
      s.productNames = products.text.trim().toUpperCase();
      s.productImeis = imeis.text.trim().toUpperCase();
      final parsedTotal = MoneyUtils.parseCurrency(totalPrice.text);
      final parsedCost = MoneyUtils.parseCurrency(totalCost.text);
      s.totalPrice = parsedTotal > 0 && parsedTotal < 100000
          ? parsedTotal * 1000
          : parsedTotal;
      s.totalCost = parsedCost > 0 && parsedCost < 100000
          ? parsedCost * 1000
          : parsedCost;
      s.warranty = warranty;
      s.paymentMethod = payment;
      if (payment != 'TRẢ GÓP (NH)') {
        s.isInstallment = false;
        s.settlementPlannedAt = null;
        s.settlementReceivedAt = null;
        s.settlementAmount = 0;
        s.settlementFee = 0;
        s.settlementNote = null;
        s.settlementCode = null;
      }
      s.notes = notes.text;
      s.isSynced = false;
    });

    await db.updateSale(s);

    // Update debt if payment method is debt
    if (s.paymentMethod == 'CÔNG NỢ') {
      final existingDebts = await db.getAllDebts();
      final linkedDebt = existingDebts
          .where((d) => d['linkedId'] == s.firestoreId)
          .firstOrNull;
      final debtAmount =
          s.totalPrice; // Debt is the full sale price owed by customer
      if (linkedDebt != null) {
        // Update existing debt
        linkedDebt['totalAmount'] = debtAmount;
        linkedDebt['status'] =
            (debtAmount - (linkedDebt['paidAmount'] ?? 0)) > 0
            ? 'UNPAID'
            : 'PAID';
        await db.updateDebt(linkedDebt);

        // Queue sync debt to cloud via SyncOrchestrator
        final debtId = linkedDebt['id'] as int?;
        if (debtId != null) {
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.debt,
            entityId: debtId,
            firestoreId: linkedDebt['firestoreId'] as String?,
            operation: SyncOperation.update,
            data: linkedDebt,
          );
        }
        EventBus().emit('debts_changed');
      } else {
        // Create new debt
        final debtFId = "debt_${s.soldAt}_${s.phone}";
        final newDebt = {
          'firestoreId': debtFId,
          'personName': s.customerName,
          'phone': s.phone,
          'totalAmount': debtAmount,
          'paidAmount': 0,
          'status': 'UNPAID',
          'createdAt': s.soldAt,
          'note': 'Đơn bán ${s.firestoreId}',
          'linkedId': s.firestoreId,
          'type': 'CUSTOMER_OWES', // Customer owes shop
        };
        final debtId = await db.insertDebt(newDebt);

        // Queue sync debt to cloud via SyncOrchestrator
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.debt,
          entityId: debtId,
          firestoreId: debtFId,
          operation: SyncOperation.create,
          data: newDebt,
        );
        EventBus().emit('debts_changed');
      }
    } else {
      // If payment method changed from debt to something else, mark debt as paid
      final existingDebts = await db.getAllDebts();
      final linkedDebt = existingDebts
          .where((d) => d['linkedId'] == s.firestoreId)
          .firstOrNull;
      if (linkedDebt != null) {
        linkedDebt['status'] = 'PAID';
        linkedDebt['paidAmount'] = linkedDebt['totalAmount'];
        await db.updateDebt(linkedDebt);

        // Queue sync debt to cloud via SyncOrchestrator
        final debtId = linkedDebt['id'] as int?;
        if (debtId != null) {
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.debt,
            entityId: debtId,
            firestoreId: linkedDebt['firestoreId'] as String?,
            operation: SyncOperation.update,
            data: linkedDebt,
          );
        }
        EventBus().emit('debts_changed');
      }
    }
  }

  Future<void> _editSale() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => CreateSaleView(editSale: s)),
    );
    if (result == true && mounted) {
      // Reload the sale data from database after successful edit
      final updatedSale = await db.getSaleByFirestoreId(s.firestoreId!);
      if (updatedSale != null) {
        setState(() {
          s = updatedSale;
        });
      }
      // Also refresh the list view
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteSale() async {
    if (s.id == null) return;

    // Thử khôi phục inventory dựa trên IMEI
    bool inventoryRestored = false;
    try {
      final imeis = s.productImeis.split(', ');
      for (final imei in imeis) {
        if (imei.isNotEmpty && imei != "NO_IMEI" && !imei.startsWith("PKx")) {
          // Tìm sản phẩm theo IMEI
          final product = await db.getProductByImei(imei);
          if (product != null) {
            // Tăng quantity cho sản phẩm này
            await db.addProductQuantity(product.id!, 1);
            // Sync lên cloud
            product.quantity += 1;
            if (product.type == 'DIEN_THOAI' &&
                product.status == 0 &&
                product.quantity > 0) {
              product.status = 1; // Đánh dấu là available
            }
            // Queue sync via SyncOrchestrator
            await SyncOrchestrator().enqueue(
              entityType: SyncEntityType.product,
              entityId: product.id!,
              firestoreId: product.firestoreId,
              operation: SyncOperation.update,
              data: product.toMap(),
            );
            inventoryRestored = true;
          }
        }
      }
    } catch (e) {
      debugPrint('Lỗi khi khôi phục inventory: $e');
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("XÓA ĐƠN BÁN"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Bạn chắc chắn muốn xóa đơn này?"),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: inventoryRestored
                    ? AppColors.success.withOpacity(0.1)
                    : AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: inventoryRestored
                      ? AppColors.success.withOpacity(0.3)
                      : AppColors.warning.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    inventoryRestored
                        ? Icons.check_circle
                        : Icons.warning_amber_rounded,
                    color: inventoryRestored
                        ? AppColors.success
                        : AppColors.warning,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      inventoryRestored
                          ? "Số lượng sản phẩm đã được khôi phục tự động trong kho."
                          : "Không thể khôi phục tự động số lượng trong kho. Bạn cần cập nhật inventory thủ công.",
                      style: AppTextStyles.caption.copyWith(
                        color: inventoryRestored
                            ? AppColors.success
                            : AppColors.warning,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
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
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text("XÓA"),
          ),
        ],
      ),
    );

    if (ok == true) {
      await db.deleteSale(s.id!);
      if (s.firestoreId != null) {
        // Queue delete sync via SyncOrchestrator
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.sale,
          entityId: s.id!,
          firestoreId: s.firestoreId,
          operation: SyncOperation.delete,
          data: {'firestoreId': s.firestoreId},
        );
      }
      AuditService.logAction(
        action: 'DELETE_SALE',
        entityType: 'sale',
        entityId: s.firestoreId ?? "sale_${s.soldAt}",
        summary: s.customerName,
        payload: {
          'totalPrice': s.totalPrice,
          'inventoryRestored': inventoryRestored,
        },
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _shareInvoice() async {
    final directory = (await getApplicationDocumentsDirectory()).path;
    String fileName = 'HOA_DON_${s.customerName.replaceAll(' ', '_')}.png';

    final invoiceWidget = Container(
      width: 480,
      padding: const EdgeInsets.all(22),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_hasLogo) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(_logoPath),
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _shopName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.pink,
                    ),
                  ),
                  Text("ĐC: $_shopAddr", style: const TextStyle(fontSize: 12)),
                  Text(
                    "SĐT: $_shopPhone",
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(thickness: 2),
          const Center(
            child: Text(
              "HÓA ĐƠN BÁN LẺ",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 14),
          _row("KHÁCH HÀNG", s.customerName),
          _row("SĐT", s.phone),
          _row("ĐỊA CHỈ", s.address),
          _row("SẢN PHẨM", s.productNames),
          _row("IMEI", s.productImeis),
          _row("BẢO HÀNH", s.warranty ?? "KO BH"),
          _row("NHÂN VIÊN", s.sellerName),
          _row("THỜI GIAN", _fmtDate(s.soldAt)),
          if (s.discount > 0)
            _row("GIẢM GIÁ", "-${MoneyUtils.formatCurrency(s.discount)} Đ"),
          const Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "TỔNG THANH TOÁN:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                "${MoneyUtils.formatCurrency(s.finalPrice)} Đ",
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: QrImageView(
              data: s.firestoreId ?? s.id.toString(),
              size: 110,
            ),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              "CẢM ƠN QUÝ KHÁCH!",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );

    await screenshotController.captureFromWidget(invoiceWidget).then((
      image,
    ) async {
      final imagePath = '$directory/$fileName';
      await File(imagePath).writeAsBytes(image);
      await Share.shareXFiles([
        XFile(imagePath),
      ], text: 'HÓA ĐƠN SHOP $_shopName');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_primaryColor, _primaryColor.withOpacity(0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "CHI TIẾT ĐƠN BÁN",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              s.customerName,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          if (_checkingManager)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          if (!_managerUnlocked)
            IconButton(
              onPressed: _unlockManager,
              icon: const Icon(Icons.edit_rounded, color: Colors.white),
            ),
          IconButton(
            onPressed: _sendSmsToCustomer,
            icon: const Icon(Icons.sms_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: _sendToChat,
            icon: const Icon(
              Icons.chat_bubble_outline_rounded,
              color: Colors.white,
            ),
          ),
          IconButton(
            onPressed: _printWifi,
            icon: const Icon(Icons.print_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: _shareInvoice,
            icon: const Icon(Icons.share_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: _editSale,
            icon: const Icon(Icons.edit_note_rounded, color: Colors.white),
          ),
          if (_managerUnlocked)
            IconButton(
              onPressed: _deleteSale,
              icon: const Icon(
                Icons.delete_forever_rounded,
                color: Colors.white,
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_isInstallmentNH && s.settlementReceivedAt == null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openSettlementDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text("NHẬN TIỀN TỪ NGÂN HÀNG"),
                ),
              ),
            if (_isInstallmentNH) const SizedBox(height: 10),
            if (_managerUnlocked)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openEditSaleDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text("SỬA THÔNG TIN ĐƠN"),
                ),
              ),
            if (_managerUnlocked) const SizedBox(height: 10),
            _card("GIAO DỊCH", [
              _item("Khách hàng", s.customerName),
              _item("Số điện thoại", s.phone),
              _item("Địa chỉ", s.address.isEmpty ? "---" : s.address),
              _item("Sản phẩm", s.productNames),
              _item("IMEI", s.productImeis),
              _item("Bảo hành", s.warranty ?? "KO BH"),
              _item("Nhân viên", s.sellerName),
              _item("Thời gian", _fmtDate(s.soldAt)),
              _item("Hình thức", s.paymentMethod),
              if (s.notes != null && s.notes!.isNotEmpty)
                _item("Ghi chú", s.notes!),
              if (s.discount > 0)
                _item(
                  "Giảm giá",
                  "-${MoneyUtils.formatCurrency(s.discount)} Đ",
                  color: Colors.orange,
                ),
              _item(
                "Tổng tiền",
                "${MoneyUtils.formatCurrency(s.finalPrice)} Đ",
                color: Colors.red,
              ),
            ]),
            if (_isInstallmentNH)
              _card("TRẢ GÓP - NGÂN HÀNG", [
                _item(
                  "Down payment",
                  "${MoneyUtils.formatCurrency(s.downPayment)} đ",
                ),
                _item("Ngân hàng giải ngân", s.bankName ?? "---"),
                _item(
                  "Số tiền NH sẽ chuyển",
                  "${MoneyUtils.formatCurrency(s.settlementAmount > 0 ? s.settlementAmount : s.loanAmount)} đ",
                ),
                _item("Ngày dự kiến", _fmtShort(s.settlementPlannedAt)),
                _item("Mã hồ sơ", s.settlementCode ?? "---"),
                _item("Ghi chú", s.settlementNote ?? "---"),
                _item(
                  "Tất toán",
                  s.settlementReceivedAt == null
                      ? "Chưa nhận"
                      : "Đã nhận ${_fmtShort(s.settlementReceivedAt)}",
                ),
                if (s.settlementFee > 0)
                  _item(
                    "Phí NH",
                    "${MoneyUtils.formatCurrency(s.settlementFee)} đ",
                    color: Colors.orange,
                  ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _card(String t, List<Widget> c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.pink,
          ),
        ),
        const Divider(),
        ...c,
      ],
    ),
  );
  Widget _item(String l, String v, {Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: const TextStyle(color: Colors.grey)),
        Text(
          v,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
      ],
    ),
  );
  Widget _row(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(l, style: const TextStyle(fontSize: 12)),
        Text(
          v,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ],
    ),
  );

  Future<void> _sendToChat() async {
    final user = FirebaseAuth.instance.currentUser;
    final senderId = user?.uid ?? 'guest';
    final senderName = user?.email?.split('@').first.toUpperCase() ?? 'KHACH';
    final key = s.firestoreId ?? "sale_${s.soldAt}";
    final summary =
        "ĐƠN BÁN - ${s.customerName} - ${s.phone} - ${MoneyUtils.formatCurrency(s.finalPrice)} đ";
    final msg = "Trao đổi về $summary";

    final messenger = ScaffoldMessenger.of(context);
    await FirestoreService.sendChat(
      message: msg,
      senderId: senderId,
      senderName: senderName,
      linkedType: 'sale',
      linkedKey: key,
      linkedSummary: summary,
    );

    messenger.showSnackBar(
      const SnackBar(content: Text("ĐÃ GIM ĐƠN BÁN VÀO CHAT NỘI BỘ")),
    );
  }

  Future<void> _sendSmsToCustomer() async {
    final messenger = ScaffoldMessenger.of(context);
    final phone = s.phone.trim();
    if (phone.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text("KHÔNG CÓ SỐ DIEN_THOAI KHÁCH")),
      );
      return;
    }

    final customer = s.customerName.isNotEmpty ? s.customerName : phone;
    final body =
        "SHOP $_shopName xin chào $customer, cảm ơn anh/chị đã mua ${s.productNames}. Tổng thanh toán ${MoneyUtils.formatCurrency(s.finalPrice)}đ. Khi cần bảo hành vui lòng liên hệ $_shopPhone.";

    await Clipboard.setData(ClipboardData(text: body));

    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': body},
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        messenger.showSnackBar(
          const SnackBar(
            content: Text("ĐÃ MỞ ỨNG DỤNG NHẮN TIN (nội dung đã copy sẵn)."),
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              "KHÔNG MỞ ĐƯỢC ỨNG DỤNG NHẮN TIN, anh/chị dán nội dung vào Zalo/SMS giúp em.",
            ),
          ),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "LỖI KHI GỬI TIN NHẮN, nhưng nội dung đã được copy sẵn.",
          ),
        ),
      );
    }
  }
}
