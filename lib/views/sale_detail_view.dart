import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firestore_write_helper.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../models/sale_order_model.dart';
import '../models/product_model.dart';
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
import '../services/customer_service.dart';
import '../services/financial_activity_service.dart';
import '../services/notification_service.dart';
import '../models/payment_intent_model.dart';
import '../models/shop_settings_model.dart';
import '../models/printer_types.dart';
import '../constants/financial_constants.dart';
import '../widgets/printer_selection_dialog.dart';
import '../widgets/responsive_wrapper.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'sale_invoice_template_view.dart';
import 'sale_invoice_preview_view.dart';
import 'create_sales_return_view.dart';
import '../services/sales_return_service.dart';
import '../models/sales_return_model.dart';

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
  bool _canViewCostPrice = false;

  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;
  BusinessTerminology get _terms =>
      BusinessTypeHelper.instance.getTerminology(_shopSettings);

  // Theme colors cho màn hình chi tiết đơn bán hàng
  final Color _primaryColor = const Color(0xFF2E7D32); // Xanh lá - đồng bộ bán hàng
  final Color _accentColor = const Color(0xFF388E3C);
  final Color _backgroundColor = const Color(0xFFF8FAFF);

  // Return info
  SalesReturn? _returnInfo;
  List<SalesReturn> _allReturns = [];
  int _totalReturnedAmount = 0;
  bool _allItemsReturned = false;

  @override
  void initState() {
    super.initState();
    s = widget.sale;
    _loadShopInfo();
    _loadReturnInfo();
    _loadCostPermission();
  }

  Future<void> _loadCostPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    final isSuper = UserService.isCurrentUserSuperAdmin();
    if (!mounted) return;
    setState(() {
      _canViewCostPrice = isSuper || (perms['allowViewCostPrice'] ?? false);
    });
  }

  Future<void> _loadReturnInfo() async {
    try {
      final returns = await SalesReturnService.getReturns();
      final matches = returns
          .where(
            (r) =>
                r.salesOrderFirestoreId == s.firestoreId ||
                r.salesOrderId == s.id,
          )
          .toList();
      final totalReturned = matches.fold<int>(
        0,
        (sum, r) => sum + r.totalReturnAmount,
      );

      // Check if all items are fully returned
      bool allReturned = false;
      if (matches.isNotEmpty && s.id != null && s.id! > 0) {
        final returnedMap = await DBHelper().getReturnedQuantitiesForSale(
          s.id!,
        );
        if (returnedMap.isNotEmpty) {
          // Parse original items and compare
          final names = s.productNames.split(RegExp(r',\s*'));
          final imeis = s.productImeis.split(RegExp(r',\s*'));
          allReturned = true;
          for (int i = 0; i < names.length; i++) {
            final name = names[i].trim();
            if (name.isEmpty) continue;
            final imei = i < imeis.length ? imeis[i].trim() : '';
            int origQty = 1;
            final qtyMatch = RegExp(r'^(.+?)\s+[xX](\d+)').firstMatch(name);
            String cleanName = name;
            if (qtyMatch != null) {
              cleanName = qtyMatch.group(1)!.trim();
              origQty = int.tryParse(qtyMatch.group(2)!) ?? 1;
            }
            if (imei.toUpperCase().startsWith('PKX')) {
              origQty =
                  int.tryParse(imei.toUpperCase().replaceAll('PKX', '')) ?? 1;
            }
            final isPhone =
                imei.isNotEmpty &&
                !imei.toUpperCase().startsWith('PKX') &&
                imei != 'NO_IMEI';
            final key = isPhone ? imei.toUpperCase() : cleanName.toUpperCase();
            final returned = returnedMap[key] ?? 0;
            if (returned < origQty) {
              allReturned = false;
              break;
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          _returnInfo = matches.firstOrNull;
          _allReturns = matches;
          _totalReturnedAmount = totalReturned;
          _allItemsReturned = allReturned;
        });
      }
    } catch (_) {}
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
    final totalLoan = s.loanAmount + s.loanAmount2;
    final amountCtrl = TextEditingController(
      text: CurrencyTextField.formatDisplay(
        s.settlementAmount > 0 ? s.settlementAmount : totalLoan,
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
    EventBus().emit('products_changed');

    // Tạo PaymentIntent cho khoản thu từ ngân hàng tất toán (status = completed vì đã nhận tiền)
    final user = FirebaseAuth.instance.currentUser;
    final intentId = 'pi_settlement_${s.firestoreId ?? s.id}_$nowMs';
    final settlementIntent = PaymentIntent(
      id: intentId,
      type: PaymentIntentType.saleInstallment,
      status: PaymentIntentStatus.completed,
      amount: received,
      personName: [
        s.bankName,
        if (s.bankName2 != null && s.bankName2!.isNotEmpty) s.bankName2,
      ].whereType<String>().join(' + '),
      personPhone: '',
      description:
          'Ngân hàng ${[s.bankName ?? "", if (s.bankName2 != null && s.bankName2!.isNotEmpty) s.bankName2!].join(" + ")} tất toán - KH: ${s.customerName}',
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
      payload: {
        'fee': fee,
        'bank': s.bankName,
        if (s.bankName2 != null && s.bankName2!.isNotEmpty)
          'bank2': s.bankName2,
      },
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
                  decoration: InputDecoration(
                    labelText: _terms.specialField1Label,
                  ),
                ),
                // Các trường số tiền đã bị vô hiệu hóa để bảo vệ dữ liệu tài chính
                DropdownButtonFormField<String>(
                  initialValue: warranty,
                  decoration: InputDecoration(
                    labelText: _terms.specialField2Label,
                  ),
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

        // Công nợ đã ghi nhận ở bảng debts - không cần PaymentIntent
        debugPrint('✅ Sale debt recorded: $debtFId');

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
    EventBus().emit('products_changed');
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

    // === BƯỚC 1: XÁC NHẬN TRƯỚC KHI XÓA ===
    final saleRef = s.firestoreId ?? 'sale_${s.soldAt}';
    final finalPrice = s.finalPrice;
    final hasDebt =
        s.paymentMethod == 'CÔNG NỢ' ||
        (s.paymentMethod == 'TRẢ GÓP (NH)' && s.remainingDebt > 0);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.delete_forever, color: AppColors.error, size: 22),
            const SizedBox(width: 8),
            const Text("XÓA ĐƠN BÁN", style: TextStyle(fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Đơn hàng: ${s.productNames}',
              style: const TextStyle(fontWeight: FontWeight.bold),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Text(
              'Giá trị: ${NumberFormat('#,###', 'vi').format(finalPrice)}đ',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Hệ thống sẽ tự động:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  _infoRow(Icons.inventory, 'Khôi phục số lượng kho'),
                  if (hasDebt)
                    _infoRow(
                      Icons.account_balance_wallet,
                      'Xóa công nợ liên quan',
                    ),
                  _infoRow(Icons.receipt_long, 'Xóa bản ghi thanh toán'),
                  _infoRow(Icons.person, 'Cập nhật lại chi tiêu KH'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '⚠️ Hành động này không thể hoàn tác!',
              style: TextStyle(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
                fontSize: 14,
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
            child: const Text("XÓA ĐƠN"),
          ),
        ],
      ),
    );

    if (ok != true) return;

    // === BƯỚC 2: THỰC HIỆN XÓA (sau khi user xác nhận) ===
    try {
      int restoredCount = 0;
      int debtDeleted = 0;
      int intentDeleted = 0;

      // 2A: Khôi phục inventory
      final imeis = s.productImeis.split(', ');
      final names = s.productNames.split(', ');
      for (int i = 0; i < imeis.length; i++) {
        final imei = imeis[i].trim();
        if (imei.isEmpty) continue;

        Product? product;
        int qtyToRestore = 1;

        if (imei.toUpperCase().startsWith("PKX") || imei == "NO_IMEI") {
          // Phụ kiện (PKxN) hoặc sản phẩm không có IMEI → tìm theo tên
          if (imei.toUpperCase().startsWith("PKX")) {
            qtyToRestore =
                int.tryParse(imei.toUpperCase().replaceAll('PKX', '')) ?? 1;
          }
          // Tách tên sản phẩm từ productNames (bỏ " xN"/" XN", "(Tặng)", "(Giảm ...)")
          if (i < names.length) {
            final nameEntry = names[i].trim();
            // Regex case-insensitive: match "Tên SP x2" hoặc "Tên SP X2"
            final nameMatch = RegExp(r'^(.+?)\s+[xX]\d+').firstMatch(nameEntry);
            var productName = nameMatch != null
                ? nameMatch.group(1)!.trim()
                : nameEntry;
            // Bỏ hậu tố (TẶNG) hoặc (GIẢM ...) nếu còn dính
            productName = productName.replaceAll(
              RegExp(r'\s*\(TẶNG\)\s*$', caseSensitive: false),
              '',
            );
            productName = productName.replaceAll(
              RegExp(r'\s*\(GIẢM\s+[\d,.]+\)\s*$', caseSensitive: false),
              '',
            );
            productName = productName.trim();
            debugPrint(
              '🔍 Tìm sản phẩm theo tên: "$productName" (từ: "$nameEntry")',
            );
            product = await db.getProductByName(productName);
            if (product == null) {
              debugPrint('⚠️ Không tìm thấy sản phẩm theo tên: $productName');
            }
          }
        } else {
          // Điện thoại có IMEI → tìm theo IMEI
          product = await db.getProductByImei(imei);
        }

        if (product != null) {
          await db.addProductQuantity(product.id!, qtyToRestore);
          product.quantity += qtyToRestore;
          if (product.status == 0 && product.quantity > 0) {
            product.status = 1;
            await db.updateProductStatus(product.id!, 1);
          }
          // Sync trực tiếp lên cloud (tránh real-time listener ghi đè)
          if (product.firestoreId != null && product.firestoreId!.isNotEmpty) {
            try {
              await FirebaseFirestore.instance
                  .collection('products')
                  .doc(product.firestoreId)
                  .update({
                    'quantity': product.quantity,
                    'status': product.status,
                    'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
                  });
              debugPrint(
                '☁️ Synced product quantity to cloud: ${product.firestoreId}',
              );
            } catch (e) {
              debugPrint('⚠️ Cloud sync failed, queueing: $e');
              await SyncOrchestrator().enqueue(
                entityType: SyncEntityType.product,
                entityId: product.id!,
                firestoreId: product.firestoreId,
                operation: SyncOperation.update,
                data: product.toMap(),
              );
            }
          }
          restoredCount += qtyToRestore;
          debugPrint(
            '✅ Khôi phục kho: ${product.name} +$qtyToRestore (tổng: ${product.quantity})',
          );
        }
      }

      // 2B: Xóa công nợ liên quan
      if (s.firestoreId != null) {
        final existingDebts = await db.getAllDebts();
        final linkedDebts = existingDebts
            .where((d) => d['linkedId'] == s.firestoreId)
            .toList();
        for (final debt in linkedDebts) {
          final debtFId = debt['firestoreId'] as String?;
          if (debtFId != null) {
            await db.deleteDebtByFirestoreId(debtFId);
            await SyncOrchestrator().enqueue(
              entityType: SyncEntityType.debt,
              entityId: debt['id'] as int,
              firestoreId: debtFId,
              operation: SyncOperation.delete,
              data: {...debt, 'deleted': true},
            );
          }
          debtDeleted++;
        }
      }

      // 2C: Xóa PaymentIntents liên quan
      try {
        intentDeleted = await db.deletePaymentIntentsByReferenceId(saleRef);
        debugPrint(
          '🗑️ Deleted $intentDeleted payment intents for sale $saleRef',
        );
      } catch (e) {
        debugPrint('⚠️ Failed to delete payment intents: $e');
      }

      // 2D: Cập nhật lại chi tiêu khách hàng (trừ đi)
      try {
        final phone = s.walkInPhone ?? s.phone;
        if (phone.isNotEmpty) {
          final customerService = CustomerService();
          final customer = await customerService.getCustomerByPhone(phone);
          if (customer != null && finalPrice > 0) {
            final newTotal = (customer.totalSpent - finalPrice)
                .clamp(0, double.maxFinite)
                .toInt();
            final updated = customer.copyWith(totalSpent: newTotal);
            await customerService.updateCustomer(updated);
            debugPrint(
              '📊 Reverted customer totalSpent: ${customer.totalSpent} → $newTotal',
            );
          }
        }
      } catch (e) {
        debugPrint('⚠️ Failed to revert customer stats: $e');
      }

      // 2E: Log financial reversal
      try {
        await FinancialActivityService.logCustomActivity(
          activityType: 'SALE_VOID',
          amount: finalPrice,
          direction: 'OUT',
          paymentMethod: s.paymentMethod,
          title: 'HỦY ĐƠN BÁN',
          description: 'Hủy đơn: ${s.productNames}. KH: ${s.customerName}',
          customerName: s.customerName,
          phone: s.walkInPhone ?? s.phone,
          productInfo: s.productNames,
          referenceType: 'sale',
          referenceId: s.firestoreId,
        );
      } catch (e) {
        debugPrint('⚠️ Failed to log financial reversal: $e');
      }

      // 2F: Soft-delete trên cloud TRƯỚC (tránh real-time sync tải lại sale)
      if (s.firestoreId != null) {
        try {
          await FirestoreService.deleteSale(s.firestoreId!);
          debugPrint('✅ Cloud soft-delete sale: ${s.firestoreId}');
        } catch (e) {
          debugPrint('⚠️ Cloud soft-delete failed, queuing: $e');
          // Fallback: queue delete nếu cloud gọi trực tiếp lỗi
          await SyncOrchestrator().enqueue(
            entityType: SyncEntityType.sale,
            entityId: s.id!,
            firestoreId: s.firestoreId,
            operation: SyncOperation.delete,
            data: {'firestoreId': s.firestoreId},
          );
        }
      }

      // 2G: Xóa sale khỏi local DB (sau khi cloud đã soft-delete)
      await db.deleteSale(s.id!);

      // 2H: Audit log
      AuditService.logAction(
        action: 'DELETE_SALE',
        entityType: 'sale',
        entityId: saleRef,
        summary: '${s.customerName} - ${s.productNames}',
        payload: {
          'totalPrice': s.totalPrice,
          'finalPrice': finalPrice,
          'inventoryRestored': restoredCount,
          'debtsDeleted': debtDeleted,
          'intentsDeleted': intentDeleted,
          'paymentMethod': s.paymentMethod,
        },
      );

      // 2I: Thông báo thành công
      NotificationService.showSnackBar(
        'Đã xóa đơn bán${restoredCount > 0 ? ' • Kho +$restoredCount' : ''}${debtDeleted > 0 ? ' • Xóa $debtDeleted nợ' : ''}',
        color: Colors.green,
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('❌ Lỗi xóa đơn bán: $e');
      NotificationService.showSnackBar(
        'Lỗi xóa đơn bán: $e',
        color: Colors.red,
      );
    }
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.blue.shade700),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 13, color: Colors.blue.shade800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
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
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(20),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _bottomAction(Icons.sms_rounded, 'SMS', _sendSmsToCustomer),
                _bottomAction(
                  Icons.chat_bubble_outline_rounded,
                  'Chat',
                  _sendToChat,
                ),
                _bottomAction(Icons.preview, 'Xem trước', () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SaleInvoicePreviewView(
                        saleData: _buildSalePrintData(),
                        paper: PaperSize.mm58,
                      ),
                    ),
                  );
                }),
                _bottomAction(Icons.print_rounded, 'In', _printWifi),
                _bottomAction(
                  Icons.assignment_return_rounded,
                  _allItemsReturned ? 'Đã trả hết' : 'Trả hàng',
                  _allItemsReturned
                      ? null
                      : () async {
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CreateSalesReturnView(sale: s),
                            ),
                          );
                          if (result == true && mounted) {
                            _loadReturnInfo();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Trả hàng thành công!'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                ),
                _bottomAction(Icons.design_services, 'Mẫu in', () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SaleInvoiceTemplateView(),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
      body: ResponsiveCenter(
        maxWidth: 800,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              if (_isInstallmentNH &&
                  (s.settlementReceivedAt == null ||
                      s.settlementAmount < s.loanAmount + s.loanAmount2))
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
                    label: Text(
                      s.settlementReceivedAt != null
                          ? "CẬP NHẬT TẤT TOÁN (còn ${MoneyUtils.formatCurrency(s.loanAmount + s.loanAmount2 - s.settlementAmount)} đ)"
                          : "NHẬN TIỀN TỪ NGÂN HÀNG",
                    ),
                  ),
                ),
              if (_isInstallmentNH) const SizedBox(height: 10),

              // Return indicator
              if (_allReturns.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _allItemsReturned
                        ? Colors.grey.shade100
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _allItemsReturned
                          ? Colors.grey.shade400
                          : Colors.red.shade200,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.assignment_return,
                        color: _allItemsReturned
                            ? Colors.grey.shade700
                            : Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _allItemsReturned
                                  ? 'ĐÃ TRẢ TOÀN BỘ — ${MoneyUtils.formatCurrency(_totalReturnedAmount)}đ'
                                  : 'ĐÃ TRẢ 1 PHẦN — ${MoneyUtils.formatCurrency(_totalReturnedAmount)}đ (${_allReturns.length} lần)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: _allItemsReturned
                                    ? Colors.grey.shade700
                                    : Colors.red.shade700,
                              ),
                            ),
                            ..._allReturns.map(
                              (r) => Text(
                                '${r.refundMethod} • ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(r.returnDate))} • ${MoneyUtils.formatCurrency(r.totalReturnAmount)}đ${r.note != null && r.note!.isNotEmpty ? ' • ${r.note}' : ''}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _allItemsReturned
                                      ? Colors.grey.shade600
                                      : Colors.red.shade600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

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
                if (s.paymentMethod.toUpperCase() == 'KẾT HỢP' &&
                    (s.cashAmount > 0 || s.transferAmount > 0)) ...[
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
                if (_canViewCostPrice && s.totalCost > 0) ...[
                  _item(
                    "Giá vốn",
                    "${MoneyUtils.formatCurrency(s.totalCost)} Đ",
                    color: Colors.orange.shade700,
                  ),
                  _item(
                    "Lợi nhuận",
                    "${s.finalPrice - s.totalCost >= 0 ? '+' : ''}${MoneyUtils.formatCurrency(s.finalPrice - s.totalCost)} Đ",
                    color: s.finalPrice - s.totalCost >= 0
                        ? Colors.green.shade700
                        : Colors.red,
                  ),
                ],
              ]),
              if (_isInstallmentNH)
                _card("TRẢ GÓP - NGÂN HÀNG", [
                  _item(
                    "Down payment",
                    "${MoneyUtils.formatCurrency(s.downPayment)} đ",
                  ),
                  _item("NH 1 giải ngân", s.bankName ?? "---"),
                  _item(
                    "Số tiền NH 1",
                    "${MoneyUtils.formatCurrency(s.loanAmount)} đ",
                  ),
                  if (s.bankName2 != null && s.bankName2!.isNotEmpty) ...[
                    _item("NH 2 giải ngân", s.bankName2!),
                    _item(
                      "Số tiền NH 2",
                      "${MoneyUtils.formatCurrency(s.loanAmount2)} đ",
                    ),
                  ],
                  _item(
                    "Tổng vay NH",
                    "${MoneyUtils.formatCurrency(s.loanAmount + s.loanAmount2)} đ",
                  ),
                  _item("Ngày dự kiến", _fmtShort(s.settlementPlannedAt)),
                  _item("Mã hồ sơ", s.settlementCode ?? "---"),
                  _item("Ghi chú", s.settlementNote ?? "---"),
                  _item(
                    "Tất toán",
                    s.settlementReceivedAt == null
                        ? "Chưa nhận"
                        : s.settlementAmount >= s.loanAmount + s.loanAmount2
                        ? "Đã nhận đủ ${_fmtShort(s.settlementReceivedAt)}"
                        : "Đã nhận ${MoneyUtils.formatCurrency(s.settlementAmount)} đ / ${MoneyUtils.formatCurrency(s.loanAmount + s.loanAmount2)} đ",
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: const TextStyle(color: Colors.grey)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            v,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.end,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
  Widget _row(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l, style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize)),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            v,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: AppTextStyles.headline5.fontSize,
            ),
            textAlign: TextAlign.end,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );

  Widget _bottomAction(IconData icon, String label, VoidCallback? onTap) {
    final isDisabled = onTap == null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isDisabled ? Colors.grey : const Color(0xFF0068FF),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isDisabled ? Colors.grey : const Color(0xFF0068FF),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
