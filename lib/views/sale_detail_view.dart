import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../models/sale_order_model.dart';
import '../data/db_helper.dart';
import '../services/firestore_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/event_bus.dart';
import '../services/user_service.dart';
import '../services/audit_service.dart';
import '../services/unified_printer_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../services/payment_intent_service.dart';
import '../services/category_service.dart';
import '../services/business_type_helper.dart';
import '../models/payment_intent_model.dart';
import '../models/shop_settings_model.dart';
import '../models/printer_types.dart';
import '../constants/financial_constants.dart';
import '../widgets/printer_selection_dialog.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'sale_invoice_template_view.dart';
import 'sale_invoice_preview_view.dart';

class SaleDetailView extends StatefulWidget {
  final SaleOrder sale;
  const SaleDetailView({super.key, required this.sale});

  @override
  State<SaleDetailView> createState() => _SaleDetailViewState();
}

class _SaleDetailViewState extends State<SaleDetailView> {
  final db = DBHelper();
  late SaleOrder s;

  String _shopName = "";
  String _shopAddr = "";
  String _shopPhone = "";
  String _logoPath = "";
  bool get _hasLogo => _logoPath.isNotEmpty && File(_logoPath).existsSync();
  bool get _isInstallmentNH => s.paymentMethod.toUpperCase() == "TRẢ GÓP (NH)";
  bool _managerUnlocked = false;
  bool _checkingManager = false;
  
  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms => BusinessTypeHelper.instance.getTerminology(_shopSettings);

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
    final settings = await CategoryService().getShopSettings();
    if (!mounted) return;
    setState(() {
      _shopSettings = settings;
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
      final saleData = _buildSalePrintData();

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

  Map<String, dynamic> _buildSalePrintData() {
    final discount = s.discount;
    final finalTotal = s.finalPrice;
    return {
      'customerName': s.customerName,
      'customerPhone': s.phone,
      'customerAddress': s.address,
      'productNames': s.productNames,
      'productImeis': s.productImeis,
      'warranty': s.warranty.isNotEmpty ? s.warranty : 'KO BH',
      'sellerName': s.sellerName,
      'soldAt': s.soldAt,
      'totalPrice': s.totalPrice,
      'discount': discount,
      'finalTotal': finalTotal,
      'firestoreId': s.firestoreId ?? s.id.toString(),
      'shopName': _shopName,
      'shopAddr': _shopAddr,
      'shopPhone': _shopPhone,
      'paymentMethod': s.paymentMethod,
      'isInstallment': s.isInstallment,
      'downPayment': s.downPayment,
      'downPaymentMethod': s.downPaymentMethod,
      'loanAmount': s.loanAmount,
      'loanAmount2': s.loanAmount2,
      'installmentTerm': s.installmentTerm,
      'bankName': s.bankName,
      'bankName2': s.bankName2,
      'remainingDebt': s.remainingDebt,
    };
  }

  Future<void> _openSettlementDialog() async {
    final formKey = GlobalKey<FormState>();
    final amountCtrl = TextEditingController(
      text: CurrencyTextField.formatDisplay(
        s.settlementAmount > 0 ? s.settlementAmount : s.loanAmount,
      ),
    );
    final feeCtrl = TextEditingController(
      text: CurrencyTextField.formatDisplay(s.settlementFee),
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
              CurrencyTextField(
                controller: amountCtrl,
                label: "Số tiền nhận (VNĐ)",
                validator: (v) => MoneyUtils.validateAmount(
                  v ?? '',
                  min: 1,
                  fieldName: 'Số tiền nhận',
                ),
              ),
              const SizedBox(height: 8),
              CurrencyTextField(
                controller: feeCtrl,
                label: "Phí NH giữ lại (VNĐ)",
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

    // Không nhân 1000 - user đã nhập số đầy đủ với formatter
    final received = MoneyUtils.parseCurrency(amountCtrl.text);
    final fee = MoneyUtils.parseCurrency(feeCtrl.text);
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

    // Tạo PaymentIntent cho khoản thu từ ngân hàng tất toán (status = completed vì đã nhận tiền)
    final user = FirebaseAuth.instance.currentUser;
    final intentId = 'pi_settlement_${s.firestoreId ?? s.id}_$nowMs';
    final settlementIntent = PaymentIntent(
      id: intentId,
      type: PaymentIntentType.saleInstallment,
      status: PaymentIntentStatus.completed,
      amount: received,
      personName: s.bankName ?? 'NGÂN HÀNG',
      personPhone: '',
      description:
          'Ngân hàng ${s.bankName ?? ""} tất toán - KH: ${s.customerName}',
      referenceType: 'sale',
      referenceId: s.firestoreId ?? 'sale_${s.soldAt}',
      createdBy: user?.uid ?? 'unknown',
      createdAt: nowMs,
      paymentMethod: PaymentMethod.bank,
      paidAt: nowMs,
    );
    await PaymentIntentService.createIntent(settlementIntent);
    debugPrint('💳 Created PaymentIntent for bank settlement: $intentId');

    // Ghi chi phí NH nếu có fee > 0
    if (fee > 0) {
      final feeIntentId = 'pi_bank_fee_${s.firestoreId ?? s.id}_$nowMs';
      final feeIntent = PaymentIntent(
        id: feeIntentId,
        type: PaymentIntentType.operatingExpense,
        status: PaymentIntentStatus.completed,
        amount: fee,
        personName: s.bankName ?? 'NGÂN HÀNG',
        personPhone: '',
        description: 'Phí NH ${s.bankName ?? ""} - KH: ${s.customerName}',
        referenceType: 'sale',
        referenceId: s.firestoreId ?? 'sale_${s.soldAt}',
        createdBy: user?.uid ?? 'unknown',
        createdAt: nowMs,
        paymentMethod: PaymentMethod.bank,
        paidAt: nowMs,
      );
      await PaymentIntentService.createIntent(feeIntent);
      debugPrint('💳 Created PaymentIntent for bank fee: $feeIntentId');
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
    final notes = TextEditingController(text: s.notes ?? "");
    final warranties = ["KO BH", "1 THÁNG", "3 THÁNG", "6 THÁNG", "12 THÁNG"];
    String warranty = s.warranty.isNotEmpty ? s.warranty : "KO BH";
    String payment = s.paymentMethod;
    final oldPaymentMethod = s.paymentMethod; // Lưu lại để so sánh

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
                  decoration: InputDecoration(labelText: _terms.productLabel),
                ),
                TextFormField(
                  controller: imeis,
                  decoration: InputDecoration(labelText: _terms.specialField1Label),
                ),
                // Các trường số tiền đã bị vô hiệu hóa để bảo vệ dữ liệu tài chính
                DropdownButtonFormField<String>(
                  initialValue: warranty,
                  decoration: InputDecoration(labelText: _terms.specialField2Label),
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
                            "KẾT HỢP",
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
      // Không cho phép sửa số tiền để bảo vệ dữ liệu tài chính
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

    // FIX: Sync sale lên Firestore sau khi update
    if (s.firestoreId != null && s.id != null) {
      await SyncOrchestrator().enqueue(
        entityType: SyncEntityType.sale,
        entityId: s.id!,
        firestoreId: s.firestoreId,
        operation: SyncOperation.update,
        data: s.toMap(),
      );
    }

    // Update debt if payment method is debt
    // FIX: Sử dụng finalPrice (đã trừ discount) thay vì totalPrice
    final debtAmount = s.finalPrice;

    if (s.paymentMethod == 'CÔNG NỢ') {
      final existingDebts = await db.getAllDebts();
      final linkedDebt = existingDebts
          .where((d) => d['linkedId'] == s.firestoreId)
          .firstOrNull;
      if (linkedDebt != null) {
        // Update existing debt
        linkedDebt['totalAmount'] = debtAmount;
        linkedDebt['personName'] = s.customerName; // Cập nhật tên khách
        linkedDebt['phone'] = s.phone; // Cập nhật SĐT
        linkedDebt['status'] =
            (debtAmount - (linkedDebt['paidAmount'] ?? 0)) > 0
            ? 'UNPAID'
            : 'PAID';
        linkedDebt['isSynced'] = 0;
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
        // Create new debt (khi đổi từ hình thức khác sang CÔNG NỢ)
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
          'isSynced': 0,
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

        // Tạo PaymentIntent cho việc thu nợ sau này (CHỜ THU)
        final user = FirebaseAuth.instance.currentUser;
        final intent = PaymentIntent(
          id: 'pi_sale_debt_${DateTime.now().millisecondsSinceEpoch}_${s.id}',
          type: PaymentIntentType.customerDebtCollection,
          amount: debtAmount,
          description: 'Thu tiền bán hàng: ${s.customerName}',
          referenceId: debtFId,
          referenceType: 'sale_debt',
          personName: s.customerName,
          personPhone: s.phone,
          createdBy: user?.uid ?? 'unknown',
          createdAt: DateTime.now().millisecondsSinceEpoch,
          metadata: {
            'saleId': s.id,
            'saleFirestoreId': s.firestoreId,
            'debtId': debtId,
            'debtFirestoreId': debtFId,
            'debtType': 'CUSTOMER_OWES',
          },
        );
        await PaymentIntentService.createIntent(intent);
        debugPrint(
          '💳 Created PaymentIntent for sale debt collection: ${intent.id}',
        );

        EventBus().emit('debts_changed');
      }
    } else if (oldPaymentMethod == 'CÔNG NỢ' && payment != 'CÔNG NỢ') {
      // FIX: Chỉ đánh dấu PAID khi đổi TỪ CÔNG NỢ sang hình thức khác
      final existingDebts = await db.getAllDebts();
      final linkedDebt = existingDebts
          .where((d) => d['linkedId'] == s.firestoreId)
          .firstOrNull;
      if (linkedDebt != null) {
        linkedDebt['status'] = 'PAID';
        linkedDebt['paidAmount'] = linkedDebt['totalAmount'];
        linkedDebt['isSynced'] = 0;
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

    // Emit event và thông báo
    EventBus().emit('sales_changed');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã cập nhật thông tin đơn hàng'),
          backgroundColor: Colors.green,
        ),
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
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
        automaticallyImplyLeading: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "CHI TIẾT ĐƠN BÁN",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTextStyles.headline2.fontSize,
              ),
            ),
            Text(
              s.customerName,
              style: TextStyle(
                fontSize: AppTextStyles.body1.fontSize,
                color: Colors.white70,
              ),
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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SaleInvoicePreviewView(
                    saleData: _buildSalePrintData(),
                    paper: PaperSize.mm58,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.preview, color: Colors.white),
          ),
          IconButton(
            onPressed: _printWifi,
            icon: const Icon(Icons.print_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const SaleInvoiceTemplateView(),
                ),
              );
            },
            icon: const Icon(Icons.design_services, color: Colors.white),
          ),
          if (_managerUnlocked)
            IconButton(
              onPressed: _openEditSaleDialog,
              tooltip: 'Sửa thông tin đơn',
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

            _card("GIAO DỊCH", [
              _item("Khách hàng", s.customerName),
              _item("Số điện thoại", s.phone),
              _item("Địa chỉ", s.address.isEmpty ? "---" : s.address),
              _item("Sản phẩm", s.productNames),
              _item("IMEI", s.productImeis),
              _item("Bảo hành", s.warranty.isNotEmpty ? s.warranty : "KO BH"),
              _item("Nhân viên", s.sellerName),
              _item("Thời gian", _fmtDate(s.soldAt)),
              _item("Hình thức", s.paymentMethod),
              // Hiển thị chi tiết kết hợp thanh toán
              if (s.paymentMethod.toUpperCase() == 'KẾT HỢP' && (s.cashAmount > 0 || s.transferAmount > 0)) ...[
                _item(
                  "💵 Tiền mặt",
                  "${MoneyUtils.formatCurrency(s.cashAmount)} Đ",
                  color: Colors.green,
                ),
                _item(
                  "🏦 Chuyển khoản",
                  "${MoneyUtils.formatCurrency(s.transferAmount)} Đ",
                  color: Colors.blue,
                ),
              ],
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
        Text(l, style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize)),
        Text(
          v,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextStyles.headline5.fontSize,
          ),
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
