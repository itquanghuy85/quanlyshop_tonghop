import 'dart:async';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
// BỔ SUNG THƯ VIỆN BỊ THIẾU
import 'package:fl_chart/fl_chart.dart';
import '../utils/money_utils.dart';
import '../widgets/currency_text_field.dart';
import '../data/db_helper.dart';
import '../services/notification_service.dart';
import '../services/sync_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/user_service.dart';
import '../services/adjustment_service.dart';
import '../services/event_bus.dart';
import '../services/payment_intent_service.dart';
import '../models/payment_intent_model.dart';
import '../constants/financial_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import '../widgets/gradient_fab.dart';
import 'fast_stock_in_view.dart';
import '../widgets/custom_app_bar.dart';

class ExpenseView extends StatefulWidget {
  final bool embedded;
  const ExpenseView({super.key, this.embedded = false});
  @override
  State<ExpenseView> createState() => _ExpenseViewState();
}

class _ExpenseViewState extends State<ExpenseView> {
  final db = DBHelper();
  List<Map<String, dynamic>> _expenses = [];
  List<Map<String, dynamic>> _filteredExpenses = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSyncing = false;
  String _syncStatus =
      'Đã đồng bộ'; // 'Đã đồng bộ', 'Đang đồng bộ...', 'Lỗi đồng bộ'
  bool _hasPermission = false;

  // Filter options
  String _filterType = 'THÁNG'; // NGÀY, TUẦN, THÁNG
  DateTime _selectedDate = DateTime.now();

  StreamSubscription<String>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _refresh();
    _eventSubscription = EventBus().stream.listen((event) {
      if (event == 'expenses_changed') {
        _refresh();
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    super.dispose();
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = perms['allowViewExpenses'] ?? false);
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    try {
      if (kIsWeb) {
        // Web doesn't support SQLite, show empty state
        setState(() {
          _expenses = [];
          _filterExpenses();
          _isLoading = false;
        });
        print('DEBUG: Web platform detected, skipping local DB');
        return;
      }

      final expenses = await db.getAllExpenses();
      final purchaseDebts = await db.getPurchaseDebts();
      // Convert purchase debts to expense-like format
      final purchaseExpenses = purchaseDebts
          .map(
            (po) => {
              'id': 'po_${po['id']}',
              'title': 'Đơn nhập: ${po['orderCode']} - ${po['supplierName']}',
              'amount': po['totalCost'],
              'date': po['createdAt'],
              'category': 'ĐƠN NHẬP HÀNG',
              'createdBy': po['createdBy'],
              'note': po['notes'],
              'isPurchaseDebt': true,
            },
          )
          .toList();
      if (!mounted) return;
      setState(() {
        _expenses = [...expenses, ...purchaseExpenses];
        _filterExpenses();
        _isLoading = false;
      });

      // Debug logging
      print(
        'DEBUG: Loaded ${_expenses.length} expenses, filtered: ${_filteredExpenses.length}',
      );
    } catch (e) {
      print('DEBUG: Error loading expenses: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncWithFirebase() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _syncStatus = 'Đang đồng bộ...';
    });

    try {
      await SyncService.syncAllToCloud();
      await SyncService.downloadAllFromCloud();

      // Reload data after sync
      await _refresh();

      if (mounted) {
        setState(() {
          _syncStatus = 'Đã đồng bộ';
        });
      }
    } catch (e) {
      print('DEBUG: Sync error: $e');
      if (mounted) {
        setState(() {
          _syncStatus = 'Lỗi đồng bộ';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  void _filterExpenses() {
    DateTime now = DateTime.now();
    List<Map<String, dynamic>> filtered = [];

    switch (_filterType) {
      case 'NGÀY':
        filtered = _expenses.where((e) {
          final d = DateTime.fromMillisecondsSinceEpoch(e['date']);
          return d.day == _selectedDate.day &&
              d.month == _selectedDate.month &&
              d.year == _selectedDate.year;
        }).toList();
        break;
      case 'TUẦN':
        // Get start of week (Monday)
        DateTime startOfWeek = _selectedDate.subtract(
          Duration(days: _selectedDate.weekday - 1),
        );
        DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
        filtered = _expenses.where((e) {
          final d = DateTime.fromMillisecondsSinceEpoch(e['date']);
          return d.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
              d.isBefore(endOfWeek.add(const Duration(days: 1)));
        }).toList();
        break;
      case 'THÁNG':
        filtered = _expenses.where((e) {
          final d = DateTime.fromMillisecondsSinceEpoch(e['date']);
          return d.month == _selectedDate.month && d.year == _selectedDate.year;
        }).toList();
        break;
      default:
        // Default to current month if no filter
        filtered = _expenses.where((e) {
          final d = DateTime.fromMillisecondsSinceEpoch(e['date']);
          return d.month == now.month && d.year == now.year;
        }).toList();
        break;
    }

    setState(() {
      _filteredExpenses = filtered;
    });

    // Debug logging
    print(
      'DEBUG: Filtered to ${_filteredExpenses.length} expenses for $_filterType',
    );
  }

  void _changeFilterType(String type) {
    setState(() {
      _filterType = type;
      if (type == 'NGÀY') {
        _selectedDate = DateTime.now();
      } else if (type == 'TUẦN') {
        _selectedDate = DateTime.now();
      } else if (type == 'THÁNG') {
        _selectedDate = DateTime.now();
      }
      _filterExpenses();
    });
  }

  void _changeDate(DateTime newDate) {
    setState(() {
      _selectedDate = newDate;
      _filterExpenses();
    });
  }

  Future<void> _handleDeleteExpense(Map<String, dynamic> exp) async {
    if (exp['isPurchaseDebt'] == true) {
      NotificationService.showSnackBar(
        "Không thể xóa chi phí từ đơn nhập hàng!",
        color: AppColors.error,
      );
      return;
    }
    
    // Kiểm tra ngày của chi phí đã chốt quỹ chưa
    final expenseTimestamp = exp['date'] is int ? exp['date'] : DateTime.now().millisecondsSinceEpoch;
    final canEdit = await AdjustmentService.canEditDirectly(expenseTimestamp);
    if (!canEdit && mounted) {
      final expenseDate = DateTime.fromMillisecondsSinceEpoch(expenseTimestamp);
      NotificationService.showSnackBar(
        '❌ Ngày ${DateFormat('dd/MM/yyyy').format(expenseDate)} đã chốt quỹ! Không thể xóa chi phí.',
        color: Colors.red,
      );
      return;
    }
    
    final passC = TextEditingController();
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          "XÁC NHẬN XÓA CHI PHÍ",
          style: AppTextStyles.headline5.copyWith(
            color: AppColors.error,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Bạn đang xóa khoản chi: ${exp['title']}\nSố tiền: ${MoneyUtils.formatCurrency(exp['amount'])}",
            ),
            const SizedBox(height: 15),
            TextField(
              controller: passC,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: "Nhập mật khẩu tài khoản để xóa",
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
            onPressed: () => Navigator.pop(ctx, true),
            style: AppButtonStyles.errorElevatedButtonStyle,
            child: Text(
              "XÁC NHẬN XÓA",
              style: AppTextStyles.button.copyWith(color: AppColors.onError),
            ),
          ),
        ],
      ),
    );

    if (result == true) {
      if (passC.text.isEmpty) return;
      setState(() => _isLoading = true);
      try {
        final email = FirebaseAuth.instance.currentUser?.email;
        if (email != null) {
          AuthCredential credential = EmailAuthProvider.credential(
            email: email,
            password: passC.text,
          );
          await FirebaseAuth.instance.currentUser?.reauthenticateWithCredential(
            credential,
          );

          final expenseId = exp['id'] as int?;
          final firestoreId = exp['firestoreId'] as String?;
          await db.deleteExpenseByFirestoreId(firestoreId ?? '');
          
          // Queue delete sync via SyncOrchestrator
          if (expenseId != null) {
            await SyncOrchestrator().enqueue(
              entityType: SyncEntityType.expense,
              entityId: expenseId,
              firestoreId: firestoreId,
              operation: SyncOperation.delete,
              data: null,
            );
          }

          final user = FirebaseAuth.instance.currentUser;
          await db.logAction(
            userId: user?.uid ?? "0",
            userName: email.split('@').first.toUpperCase(),
            action: "XÓA CHI PHÍ",
            type: "FINANCE",
            desc: "Đã xóa khoản chi ${exp['title']} số tiền ${exp['amount']}đ",
          );

          NotificationService.showSnackBar(
            "Đã xóa chi phí thành công",
            color: AppColors.success,
          );
          _refresh();
        }
      } catch (e) {
        NotificationService.showSnackBar(
          "Mật khẩu không đúng! Không thể xóa.",
          color: AppColors.error,
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddExpenseDialog() async {
    if (_isSaving) return;
    
    // Kiểm tra ngày hôm nay đã chốt quỹ chưa
    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(today.millisecondsSinceEpoch);
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể thêm chi phí mới.',
        color: Colors.red,
      );
      return;
    }
    
    final formKey = GlobalKey<FormState>();
    final titleC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    String category = "PHÁT SINH";
    String payMethod = "TIỀN MẶT";

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) {
          titleC.addListener(() => setS(() {}));
          amountC.addListener(() => setS(() {}));
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: Text(
              "GHI CHÉP CHI PHÍ",
              style: AppTextStyles.headline5.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "PHÂN LOẠI",
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        "CỐ ĐỊNH",
                        "PHÁT SINH",
                        "LƯƠNG",
                        "MẶT BẰNG",
                        "ĐIỆN NƯỚC",
                        "KHÁC",
                      ].map(
                        (c) => ChoiceChip(
                          label: Text(
                            c,
                            style: AppTextStyles.caption.copyWith(fontSize: AppTextStyles.body1.fontSize),
                          ),
                          selected: category == c,
                          onSelected: (v) => setS(() => category = c),
                        ),
                      ).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: titleC,
                      decoration: const InputDecoration(labelText: "Nội dung chi *", prefixIcon: Icon(Icons.edit_note)),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập nội dung chi' : null,
                    ),
                    const SizedBox(height: 12),
                    CurrencyTextField(
                      controller: amountC,
                      label: "Số tiền (VNĐ) *",
                      icon: Icons.payments,
                      validator: (v) => MoneyUtils.validateAmount(v ?? '', min: 1, fieldName: 'Số tiền'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteC,
                      decoration: const InputDecoration(labelText: "Ghi chú thêm", prefixIcon: Icon(Icons.description)),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "THANH TOÁN BẰNG",
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: ["TIỀN MẶT", "CHUYỂN KHOẢN"]
                          .map(
                            (m) => Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: ChoiceChip(
                                  label: Text(m, style: AppTextStyles.caption),
                                  selected: payMethod == m,
                                  onSelected: (v) => setS(() => payMethod = m),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("HỦY"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD32F2F),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        setS(() => _isSaving = true);

                        // Không nhân 1000 - user đã nhập số đầy đủ với formatter
                        final amount = MoneyUtils.parseCurrency(amountC.text);

                        final user = FirebaseAuth.instance.currentUser;
                        final navigator = Navigator.of(ctx);
                        
                        // Convert payment method string to enum
                        final method = payMethod == 'CHUYỂN KHOẢN' 
                            ? PaymentMethod.transfer 
                            : PaymentMethod.cash;
                            
                        navigator.pop(); // Close dialog first
                        
                        // Execute payment directly without navigation
                        final result = await PaymentIntentService.executePaymentDirect(
                          type: category == 'ĐIỆN NƯỚC' || category == 'INTERNET' 
                              ? PaymentIntentType.utilityExpense 
                              : PaymentIntentType.operatingExpense,
                          amount: amount,
                          paymentMethod: method,
                          description: '${titleC.text.toUpperCase()}${noteC.text.isNotEmpty ? " - ${noteC.text}" : ""}',
                          executedBy: user?.displayName ?? user?.email ?? 'unknown',
                          metadata: {
                            'category': category,
                            'title': titleC.text.toUpperCase(),
                            'note': noteC.text,
                          },
                        );

                        if (result != null && result.success) {
                          EventBus().emit('expenses_changed');
                          NotificationService.showSnackBar(
                            "Đã lưu chi phí!",
                            color: AppColors.success,
                          );
                        }
                        
                        setState(() {
                          _isSaving = false;
                        });
                        await _refresh();
                      },
                child: Text(
                  "LƯU CHI PHÍ",
                  style: AppTextStyles.button.copyWith(
                    color: AppColors.onSuccess,
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

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      if (widget.embedded) {
        return Center(
          child: Text(
            "Bạn không có quyền truy cập tính năng này",
            style: AppTextStyles.body1.copyWith(
              color: AppColors.onSurface.withOpacity(0.6),
            ),
          ),
        );
      }
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
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text("QUẢN LÝ CHI PHÍ"),
        ),
        body: Center(
          child: Text(
            "Bạn không có quyền truy cập tính năng này",
            style: AppTextStyles.body1.copyWith(
              color: AppColors.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    int totalAmount = _filteredExpenses.fold(
      0,
      (sum, e) => sum + (e['amount'] as int),
    );

    final body = Column(
      children: [
        _buildFilterBar(),
        _buildProfessionalHeader(totalAmount, _filteredExpenses),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredExpenses.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredExpenses.length,
                  itemBuilder: (ctx, i) =>
                      _expenseProfessionalCard(_filteredExpenses[i]),
                ),
        ),
      ],
    );

    final fab = kIsWeb
        ? null
        : GradientFab.danger(
            onPressed: _showAddExpenseDialog,
            icon: Icons.add_circle_outline,
            label: 'Chi phí mới',
          );

    if (widget.embedded) {
      return Stack(
        children: [
          body,
          if (fab != null)
            Positioned(
              right: 16,
              bottom: 16,
              child: fab,
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: CustomAppBar.build(
        title: 'QUẢN LÝ CHI PHÍ',
        subtitle: '${_filteredExpenses.length} khoản chi',
        accentColor: AppBarAccents.staff,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FastStockInView()),
            ),
            icon: const Icon(Icons.inventory_2_outlined, color: AppBarAccents.staff),
            tooltip: 'Nhập kho',
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _syncStatus,
                style: AppTextStyles.caption.copyWith(
                  color: _syncStatus == 'Lỗi đồng bộ'
                      ? Colors.orange
                      : AppBarAccents.staff.withOpacity(0.7),
                  fontWeight: _isSyncing ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSyncing ? null : _syncWithFirebase,
                icon: Icon(
                  _isSyncing ? Icons.sync : Icons.sync_outlined,
                  color: _isSyncing ? Colors.orange : AppBarAccents.staff,
                ),
                tooltip: 'Đồng bộ với Firebase',
              ),
            ],
          ),
        ],
      ),
      body: body,
      floatingActionButton: fab,
    );
  }

  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: AppColors.shadow.withOpacity(0.1), blurRadius: 8),
        ],
      ),
      child: Column(
        children: [
          // Filter type selector
          Row(
            children: [
              Text(
                "LỌC THEO: ",
                style: TextStyle(
                  fontSize: AppTextStyles.subtitle1.fontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: ['NGÀY', 'TUẦN', 'THÁNG'].map((type) {
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        child: ChoiceChip(
                          label: Text(
                            type,
                            style: TextStyle(
                              fontSize: AppTextStyles.body1.fontSize,
                              fontWeight: FontWeight.bold,
                              color: _filterType == type
                                  ? Colors.white
                                  : Colors.grey[700],
                            ),
                          ),
                          selected: _filterType == type,
                          onSelected: (selected) {
                            if (selected) _changeFilterType(type);
                          },
                          selectedColor: const Color(0xFFD32F2F),
                          backgroundColor: Colors.grey[100],
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Date selector
          Row(
            children: [
              Icon(
                _filterType == 'NGÀY'
                    ? Icons.calendar_today
                    : _filterType == 'TUẦN'
                    ? Icons.calendar_view_week
                    : Icons.calendar_month,
                size: 16,
                color: Colors.grey,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    DateTime? picked;
                    if (_filterType == 'NGÀY') {
                      picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                    } else if (_filterType == 'THÁNG') {
                      // Month picker
                      picked = await _showMonthPicker();
                    } else if (_filterType == 'TUẦN') {
                      picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                    }
                    if (picked != null) {
                      _changeDate(picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _getDateDisplayText(),
                      style: TextStyle(
                        fontSize: AppTextStyles.headline4.fontSize,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getDateDisplayText() {
    switch (_filterType) {
      case 'NGÀY':
        return DateFormat('dd/MM/yyyy').format(_selectedDate);
      case 'TUẦN':
        DateTime startOfWeek = _selectedDate.subtract(
          Duration(days: _selectedDate.weekday - 1),
        );
        DateTime endOfWeek = startOfWeek.add(const Duration(days: 6));
        return '${DateFormat('dd/MM').format(startOfWeek)} - ${DateFormat('dd/MM/yyyy').format(endOfWeek)}';
      case 'THÁNG':
        return DateFormat('MM/yyyy').format(_selectedDate);
      default:
        return '';
    }
  }

  Future<DateTime?> _showMonthPicker() async {
    return await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDatePickerMode: DatePickerMode.year,
    );
  }

  Widget _buildProfessionalHeader(int total, List<Map<String, dynamic>> list) {
    int coDinh = list
        .where(
          (e) =>
              e['category'] == 'CỐ ĐỊNH' ||
              e['category'] == 'LƯƠNG' ||
              e['category'] == 'MẶT BẰNG' ||
              e['category'] == 'ĐIỆN NƯỚC',
        )
        .fold(0, (sum, e) => sum + (e['amount'] as int));
    int phatSinh = list
        .where(
          (e) =>
              e['category'] == 'PHÁT SINH' || e['category'] == 'REPAIR_PARTS',
        )
        .fold(0, (sum, e) => sum + (e['amount'] as int));
    int nhapHang = list
        .where(
          (e) =>
              e['category'] == 'NHẬP HÀNG' ||
              e['category'] == 'PURCHASE' ||
              e['category'] == 'ĐƠN NHẬP HÀNG',
        )
        .fold(0, (sum, e) => sum + (e['amount'] as int));
    int khac = list
        .where((e) => e['category'] == 'KHÁC' || e['category'] == 'Phí NH')
        .fold(0, (sum, e) => sum + (e['amount'] as int));

    String headerTitle = _filterType == 'NGÀY'
        ? 'TỔNG CHI HÔM NAY'
        : _filterType == 'TUẦN'
        ? 'TỔNG CHI TUẦN NÀY'
        : 'TỔNG CHI THÁNG NÀY';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB71C1C), Color(0xFFEF5350)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withAlpha(77),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headerTitle,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: AppTextStyles.body1.fontSize,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  MoneyUtils.formatCurrency(total),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppTextStyles.headline1.fontSize,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 15),
                Row(
                  children: [
                    _miniStat("Cố định", coDinh),
                    const SizedBox(width: 10),
                    _miniStat("Phát sinh", phatSinh),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _miniStat("Nhập hàng", nhapHang),
                    const SizedBox(width: 10),
                    _miniStat("Khác", khac),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 80,
            height: 80,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 15,
                sections: [
                  PieChartSectionData(
                    value: coDinh.toDouble() == 0 ? 1 : coDinh.toDouble(),
                    color: Colors.white,
                    radius: 12,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    value: phatSinh.toDouble() == 0 ? 1 : phatSinh.toDouble(),
                    color: Colors.white70,
                    radius: 12,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    value: nhapHang.toDouble() == 0 ? 1 : nhapHang.toDouble(),
                    color: Colors.white54,
                    radius: 12,
                    showTitle: false,
                  ),
                  PieChartSectionData(
                    value: khac.toDouble() == 0 ? 1 : khac.toDouble(),
                    color: Colors.white30,
                    radius: 12,
                    showTitle: false,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, int val) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: AppTextStyles.overlineSize)),
        Text(
          MoneyUtils.formatCurrency(val),
          style: TextStyle(
            color: Colors.white,
            fontSize: AppTextStyles.body1.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _expenseProfessionalCard(Map<String, dynamic> e) {
    final cat = (e['category'] ?? 'KHÁC').toString();
    Color color;
    IconData icon;

    if (cat == 'CỐ ĐỊNH' ||
        cat == 'LƯƠNG' ||
        cat == 'MẶT BẰNG' ||
        cat == 'ĐIỆN NƯỚC') {
      color = Colors.blue;
      icon = Icons.home_work;
    } else if (cat == 'PHÁT SINH' || cat == 'REPAIR_PARTS') {
      color = Colors.orange;
      icon = Icons.build;
    } else if (cat == 'NHẬP HÀNG' ||
        cat == 'PURCHASE' ||
        cat == 'ĐƠN NHẬP HÀNG') {
      color = Colors.green;
      icon = Icons.inventory_2;
    } else if (cat == 'Phí NH') {
      color = Colors.purple;
      icon = Icons.account_balance;
    } else {
      color = Colors.grey;
      icon = Icons.shopping_cart;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withAlpha(25),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          (e['title'] ?? 'Chi phí không tên').toString(),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextStyles.headline4.fontSize,
            color: const Color(0xFF1A237E),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cat,
              style: TextStyle(
                fontSize: AppTextStyles.caption.fontSize,
                color: color,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "${DateFormat('HH:mm - dd/MM').format(DateTime.fromMillisecondsSinceEpoch(e['date']))} | ${e['isPurchaseDebt'] == true ? 'CÔNG NỢ' : (e['paymentMethod'] ?? 'TIỀN MẶT')}",
              style: TextStyle(fontSize: AppTextStyles.caption.fontSize, color: Colors.grey),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "-${MoneyUtils.formatCurrency(e['amount'])}",
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w900,
                fontSize: AppTextStyles.headline3.fontSize,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.grey,
                size: 20,
              ),
              onPressed: e['isPurchaseDebt'] == true
                  ? null
                  : () => _handleDeleteExpense(e),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.money_off_rounded, size: 80, color: Colors.grey[200]),
        const SizedBox(height: 16),
        Text(
          kIsWeb
              ? "Tính năng quản lý chi phí không khả dụng trên trình duyệt web.\nVui lòng sử dụng ứng dụng di động."
              : "Không có chi phí nào trong ${_filterType.toLowerCase()} này",
          style: const TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}
