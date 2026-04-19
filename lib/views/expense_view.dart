import 'dart:async';
import 'dart:math' as math;
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import '../services/financial_activity_service.dart';
import '../services/audit_service.dart';
import '../constants/financial_constants.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import '../widgets/gradient_fab.dart';
import 'fast_stock_in_view.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/responsive_wrapper.dart';
import '../utils/excel_export_helper.dart';
import '../widgets/export_date_filter_dialog.dart';

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

  // THU/CHI toggle
  String _viewMode = 'CHI'; // 'CHI' or 'THU'

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
      // Real-time listeners handle downloads — chỉ push local changes

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

    // First filter by THU/CHI type
    final typeFiltered = _expenses.where((e) {
      final eType = (e['type'] ?? 'CHI').toString();
      return eType == _viewMode;
    }).toList();

    switch (_filterType) {
      case 'NGÀY':
        filtered = typeFiltered.where((e) {
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
        filtered = typeFiltered.where((e) {
          final d = DateTime.fromMillisecondsSinceEpoch(e['date']);
          return d.isAfter(startOfWeek.subtract(const Duration(days: 1))) &&
              d.isBefore(endOfWeek.add(const Duration(days: 1)));
        }).toList();
        break;
      case 'THÁNG':
        filtered = typeFiltered.where((e) {
          final d = DateTime.fromMillisecondsSinceEpoch(e['date']);
          return d.month == _selectedDate.month && d.year == _selectedDate.year;
        }).toList();
        break;
      default:
        // Default to current month if no filter
        filtered = typeFiltered.where((e) {
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
    final isIncome = (exp['type'] ?? 'CHI') == 'THU';
    final label = isIncome ? 'thu phát sinh' : 'chi phí';
    
    if (exp['isPurchaseDebt'] == true) {
      NotificationService.showSnackBar(
        "Không thể xóa chi phí từ đơn nhập hàng!",
        color: AppColors.error,
      );
      return;
    }
    
    // Kiểm tra ngày đã chốt quỹ chưa
    final expenseTimestamp = exp['date'] is int ? exp['date'] : DateTime.now().millisecondsSinceEpoch;
    final canEdit = await AdjustmentService.canEditDirectly(expenseTimestamp);
    if (!canEdit && mounted) {
      final expenseDate = DateTime.fromMillisecondsSinceEpoch(expenseTimestamp);
      NotificationService.showSnackBar(
        '❌ Ngày ${DateFormat('dd/MM/yyyy').format(expenseDate)} đã chốt quỹ! Không thể xóa $label.',
        color: Colors.red,
      );
      return;
    }
    
    final passC = TextEditingController();
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isIncome ? "XÁC NHẬN XÓA KHOẢN THU" : "XÁC NHẬN XÓA CHI PHÍ",
          style: AppTextStyles.headline5.copyWith(
            color: AppColors.error,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Bạn đang xóa khoản ${isIncome ? 'thu' : 'chi'}: ${exp['title']}\nSố tiền: ${MoneyUtils.formatCurrency(exp['amount'])}",
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
          
          // 1. Delete from local DB (by firestoreId or by id)
          if (firestoreId != null && firestoreId.isNotEmpty) {
            await db.deleteExpenseByFirestoreId(firestoreId);
          } else if (expenseId != null) {
            await db.deleteExpense(expenseId);
          }
          
          // 2. Soft-delete on Firestore IMMEDIATELY (not just queue)
          // This prevents the record from being re-synced back
          if (firestoreId != null && firestoreId.isNotEmpty) {
            try {
              await FirebaseFirestore.instance
                  .collection('expenses')
                  .doc(firestoreId)
                  .update({
                'deleted': true,
                'updatedAt': FieldValue.serverTimestamp(),
              });
              debugPrint('Firestore soft-delete expense: $firestoreId');
            } catch (e) {
              // Firestore delete failed - queue for later sync
              debugPrint('Firestore delete failed, queuing: $e');
              if (expenseId != null) {
                await SyncOrchestrator().enqueue(
                  entityType: SyncEntityType.expense,
                  entityId: expenseId,
                  firestoreId: firestoreId,
                  operation: SyncOperation.delete,
                  data: null,
                );
              }
            }
          }

          final user = FirebaseAuth.instance.currentUser;
          await db.logAction(
            userId: user?.uid ?? "0",
            userName: email.split('@').first.toUpperCase(),
            action: isIncome ? "XÓA THU PHÁT SINH" : "XÓA CHI PHÍ",
            type: "FINANCE",
            desc: "Đã xóa khoản ${isIncome ? 'thu' : 'chi'} ${exp['title']} số tiền ${exp['amount']}đ",
          );

          NotificationService.showSnackBar(
            isIncome ? "Đã xóa khoản thu thành công" : "Đã xóa chi phí thành công",
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
    String scope = "SHOP";

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
                    const SizedBox(height: 12),
                    Text(
                      "PHẠM VI CHI",
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        {'value': 'SHOP', 'label': 'SHOP'},
                        {'value': 'CA_NHAN', 'label': 'CÁ NHÂN'},
                      ].map((item) {
                        final value = item['value']!;
                        final label = item['label']!;
                        return ChoiceChip(
                          label: Text(label, style: AppTextStyles.caption),
                          selected: scope == value,
                          onSelected: (_) => setS(() => scope = value),
                        );
                      }).toList(),
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
                        final txRef =
                          'expense_${DateTime.now().millisecondsSinceEpoch}_${category.trim().toUpperCase()}_${scope}_${method.code}_${amount}_${titleC.text.trim().toUpperCase()}';
                            
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
                          referenceId: txRef,
                          referenceType: 'quick_expense',
                          notes: noteC.text.trim().isEmpty ? null : noteC.text.trim(),
                          idempotencyKey: txRef,
                          metadata: {
                            'category': category,
                            'title': titleC.text.toUpperCase(),
                            'note': noteC.text,
                            'scope': scope,
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
                colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
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

    final body = ResponsiveCenter(
      child: Column(
      children: [
        // THU/CHI toggle
        _buildViewModeToggle(),
        _buildFilterBar(),
        _viewMode == 'CHI'
            ? _buildProfessionalHeader(totalAmount, _filteredExpenses)
            : _buildIncomeHeader(totalAmount, _filteredExpenses),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredExpenses.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: _filteredExpenses.length,
                  itemBuilder: (ctx, i) =>
                      _expenseProfessionalCard(_filteredExpenses[i]),
                ),
        ),
      ],
    ),
    );

    final fab = kIsWeb
        ? null
        : GradientFab(
            onPressed: _viewMode == 'CHI' ? _showAddExpenseDialog : _showAddIncomeDialog,
            icon: _viewMode == 'CHI' ? Icons.add_circle_outline : Icons.add_card,
            label: _viewMode == 'CHI' ? 'Chi phí mới' : 'Thu phát sinh',
            gradientColors: _viewMode == 'CHI'
                ? [const Color(0xFFD32F2F), const Color(0xFFEF5350)]
                : [const Color(0xFF2E7D32), const Color(0xFF66BB6A)],
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
        title: _viewMode == 'CHI' ? 'QUẢN LÝ CHI PHÍ' : 'THU PHÁT SINH',
        subtitle: _viewMode == 'CHI'
            ? '${_filteredExpenses.length} khoản chi'
            : '${_filteredExpenses.length} khoản thu',
        accentColor: _viewMode == 'CHI' ? AppBarAccents.staff : const Color(0xFF2E7D32),
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
          IconButton(
            icon: Icon(Icons.file_download_outlined, color: AppBarAccents.staff),
            tooltip: 'Xuất Excel thu chi',
            onPressed: () async {
              final result = await ExportDateFilterDialog.show(context, title: 'Xuất thu chi');
              if (result == null) return;
              if (!mounted) return;
              await ExcelExportHelper.exportExpenses(
                context,
                startMs: result['startMs'],
                endMs: result['endMs'],
              );
            },
          ),
        ],
      ),
      body: body,
      floatingActionButton: fab,
    );
  }

  Widget _buildViewModeToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _toggleBtn('CHI', Icons.arrow_downward, const Color(0xFFD32F2F)),
          const SizedBox(width: 3),
          _toggleBtn('THU', Icons.arrow_upward, const Color(0xFF2E7D32)),
        ],
      ),
    );
  }

  Widget _toggleBtn(String mode, IconData icon, Color activeColor) {
    final active = _viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (_viewMode != mode) {
            setState(() => _viewMode = mode);
            _filterExpenses();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: active ? Colors.white : Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(
                mode == 'CHI' ? 'CHI PHÍ' : 'THU PHÁT SINH',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIncomeHeader(int total, List<Map<String, dynamic>> list) {
    int phatSinh = list.where((e) => e['category'] == 'PHÁT SINH').fold(0, (sum, e) => sum + (e['amount'] as int));
    int dichVu = list.where((e) => e['category'] == 'DỊCH VỤ').fold(0, (sum, e) => sum + (e['amount'] as int));
    int hoanTien = list.where((e) => e['category'] == 'HOÀN TIỀN').fold(0, (sum, e) => sum + (e['amount'] as int));
    int khac = list.where((e) => e['category'] != 'PHÁT SINH' && e['category'] != 'DỊCH VỤ' && e['category'] != 'HOÀN TIỀN')
        .fold(0, (sum, e) => sum + (e['amount'] as int));

    final categories = <_ExpCat>[
      _ExpCat('Phát sinh', phatSinh, const Color(0xFF43A047)),
      _ExpCat('Dịch vụ', dichVu, const Color(0xFF1E88E5)),
      _ExpCat('Hoàn tiền', hoanTien, const Color(0xFF00ACC1)),
      _ExpCat('Khác', khac, const Color(0xFF7E57C2)),
    ].where((c) => c.value > 0).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2E7D32).withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _filterType == 'NGÀY' ? 'HÔM NAY' : _filterType == 'TUẦN' ? 'TUẦN NÀY' : 'THÁNG NÀY',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF2E7D32), letterSpacing: 0.3),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Tổng thu phát sinh', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  Text(
                    MoneyUtils.formatCurrency(total),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF2E7D32)),
                  ),
                ],
              ),
            ],
          ),

          if (categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                SizedBox(
                  width: 80, height: 80,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 22,
                      sections: categories.map((c) {
                        final pct = total > 0 ? (c.value / total * 100) : 0.0;
                        return PieChartSectionData(
                          color: c.color,
                          value: c.value.toDouble(),
                          radius: 16,
                          title: '${pct.round()}%',
                          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          titlePositionPercentageOffset: 0.6,
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: categories.map((c) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 4),
                        Text(c.label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        const SizedBox(width: 3),
                        Text(MoneyUtils.formatCurrency(c.value), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.color)),
                      ],
                    )).toList(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showAddIncomeDialog() async {
    if (_isSaving) return;

    // Kiểm tra ngày hôm nay đã chốt quỹ chưa
    final today = DateTime.now();
    final canEdit = await AdjustmentService.canEditDirectly(today.millisecondsSinceEpoch);
    if (!canEdit && mounted) {
      NotificationService.showSnackBar(
        '❌ Ngày hôm nay đã chốt quỹ! Không thể thêm thu phát sinh mới.',
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
    String scope = "SHOP";

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
              "GHI CHÉP THU PHÁT SINH",
              style: AppTextStyles.headline5.copyWith(
                color: const Color(0xFF2E7D32),
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
                        "PHÁT SINH",
                        "DỊCH VỤ",
                        "HOÀN TIỀN",
                        "BÁN TÀI SẢN",
                        "KHÁC",
                      ].map(
                        (c) => ChoiceChip(
                          label: Text(
                            c,
                            style: AppTextStyles.caption.copyWith(fontSize: AppTextStyles.body1.fontSize),
                          ),
                          selected: category == c,
                          selectedColor: const Color(0xFF66BB6A),
                          onSelected: (v) => setS(() => category = c),
                        ),
                      ).toList(),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: titleC,
                      decoration: const InputDecoration(labelText: "Nội dung thu *", prefixIcon: Icon(Icons.edit_note)),
                      textCapitalization: TextCapitalization.characters,
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Vui lòng nhập nội dung thu' : null,
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
                    const SizedBox(height: 12),
                    Text(
                      "PHẠM VI",
                      style: AppTextStyles.overline.copyWith(
                        color: AppColors.onSurface.withOpacity(0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: const [
                        {'value': 'SHOP', 'label': 'SHOP'},
                        {'value': 'CA_NHAN', 'label': 'CÁ NHÂN'},
                      ].map((item) {
                        final value = item['value']!;
                        final label = item['label']!;
                        return ChoiceChip(
                          label: Text(label, style: AppTextStyles.caption),
                          selected: scope == value,
                          onSelected: (_) => setS(() => scope = value),
                        );
                      }).toList(),
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
                  backgroundColor: const Color(0xFF2E7D32),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _isSaving
                    ? null
                    : () async {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        setS(() => _isSaving = true);

                        final amount = MoneyUtils.parseCurrency(amountC.text);
                        final user = FirebaseAuth.instance.currentUser;
                        final navigator = Navigator.of(ctx);
                        final method = payMethod == 'CHUYỂN KHOẢN'
                            ? PaymentMethod.transfer
                            : PaymentMethod.cash;
                        final txRef =
                          'income_${DateTime.now().millisecondsSinceEpoch}_${category.trim().toUpperCase()}_${scope}_${method.code}_${amount}_${titleC.text.trim().toUpperCase()}';

                        navigator.pop(); // Close dialog first

                        // Execute payment as income (direction IN)
                        final result = await PaymentIntentService.executePaymentDirect(
                          type: PaymentIntentType.otherIncome,
                          amount: amount,
                          paymentMethod: method,
                          description: '${titleC.text.toUpperCase()}${noteC.text.isNotEmpty ? " - ${noteC.text}" : ""}',
                          executedBy: user?.displayName ?? user?.email ?? 'unknown',
                          referenceId: txRef,
                          referenceType: 'quick_income',
                          notes: noteC.text.trim().isEmpty ? null : noteC.text.trim(),
                          idempotencyKey: txRef,
                          metadata: {
                            'category': category,
                            'title': titleC.text.toUpperCase(),
                            'note': noteC.text,
                            'scope': scope,
                          },
                        );

                        if (result != null && result.success) {
                          EventBus().emit('expenses_changed');
                          NotificationService.showSnackBar(
                            "Đã lưu thu phát sinh!",
                            color: AppColors.success,
                          );
                        }

                        setState(() {
                          _isSaving = false;
                        });
                        await _refresh();
                      },
                child: Text(
                  "LƯU KHOẢN THU",
                  style: AppTextStyles.button.copyWith(
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

  Widget _buildFilterBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          ...['NGÀY', 'TUẦN', 'THÁNG'].map((type) {
            final active = _filterType == type;
            return Padding(
              padding: const EdgeInsets.only(right: 4),
              child: GestureDetector(
                onTap: () => _changeFilterType(type),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: active
                        ? (_viewMode == 'CHI' ? const Color(0xFFE53935) : const Color(0xFF2E7D32))
                        : Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    type,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade600),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          InkWell(
            onTap: () async {
              DateTime? picked;
              if (_filterType == 'NGÀY' || _filterType == 'TUẦN') {
                picked = await showDatePicker(context: context, initialDate: _selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now());
              } else {
                picked = await _showMonthPicker();
              }
              if (picked != null) _changeDate(picked);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                  const SizedBox(width: 4),
                  Text(_getDateDisplayText(), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade700)),
                ],
              ),
            ),
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
        .where((e) => e['category'] == 'CỐ ĐỊNH' || e['category'] == 'LƯƠNG' || e['category'] == 'MẶT BẰNG' || e['category'] == 'ĐIỆN NƯỚC')
        .fold(0, (sum, e) => sum + (e['amount'] as int));
    int phatSinh = list
        .where((e) => e['category'] == 'PHÁT SINH' || e['category'] == 'REPAIR_PARTS')
        .fold(0, (sum, e) => sum + (e['amount'] as int));
    int nhapHang = list
        .where((e) => e['category'] == 'NHẬP HÀNG' || e['category'] == 'PURCHASE' || e['category'] == 'ĐƠN NHẬP HÀNG')
        .fold(0, (sum, e) => sum + (e['amount'] as int));
    int khac = list
        .where((e) => e['category'] == 'KHÁC' || e['category'] == 'Phí NH')
        .fold(0, (sum, e) => sum + (e['amount'] as int));

    final categories = <_ExpCat>[
      _ExpCat('Cố định', coDinh, const Color(0xFF1E88E5)),
      _ExpCat('Phát sinh', phatSinh, const Color(0xFFFB8C00)),
      _ExpCat('Nhập hàng', nhapHang, const Color(0xFF43A047)),
      _ExpCat('Khác', khac, const Color(0xFF7E57C2)),
    ].where((c) => c.value > 0).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE53935).withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total + period
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _filterType == 'NGÀY' ? 'HÔM NAY' : _filterType == 'TUẦN' ? 'TUẦN NÀY' : 'THÁNG NÀY',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE53935), letterSpacing: 0.3),
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Tổng chi', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                  Text(
                    MoneyUtils.formatCurrency(total),
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFFE53935)),
                  ),
                ],
              ),
            ],
          ),

          if (categories.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Donut chart + legend
            Row(
              children: [
                SizedBox(
                  width: 80, height: 80,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 22,
                      sections: categories.map((c) {
                        final pct = total > 0 ? (c.value / total * 100) : 0.0;
                        return PieChartSectionData(
                          color: c.color,
                          value: c.value.toDouble(),
                          radius: 16,
                          title: '${pct.round()}%',
                          titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                          titlePositionPercentageOffset: 0.6,
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: categories.map((c) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: c.color, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 4),
                        Text(c.label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        const SizedBox(width: 3),
                        Text(MoneyUtils.formatCurrency(c.value), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.color)),
                      ],
                    )).toList(),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _expenseProfessionalCard(Map<String, dynamic> e) {
    final cat = (e['category'] ?? 'KHÁC').toString();
    final isIncome = (e['type'] ?? 'CHI') == 'THU';
    final rawScope = (e['scope'] ?? 'SHOP').toString().toUpperCase();
    final scopeLabel =
        (rawScope == 'CA_NHAN' || rawScope == 'CÁ NHÂN' || rawScope == 'PERSONAL')
        ? 'CÁ NHÂN'
        : 'SHOP';
    Color color;
    IconData icon;

    if (isIncome) {
      if (cat == 'PHÁT SINH') { color = const Color(0xFF43A047); icon = Icons.trending_up; }
      else if (cat == 'DỊCH VỤ') { color = Colors.teal; icon = Icons.miscellaneous_services; }
      else if (cat == 'HOÀN TIỀN') { color = const Color(0xFF00ACC1); icon = Icons.replay; }
      else if (cat == 'BÁN TÀI SẢN') { color = Colors.amber.shade700; icon = Icons.sell; }
      else { color = const Color(0xFF2E7D32); icon = Icons.attach_money; }
    } else if (cat == 'CỐ ĐỊNH' || cat == 'LƯƠNG' || cat == 'MẶT BẰNG' || cat == 'ĐIỆN NƯỚC') {
      color = const Color(0xFF1E88E5); icon = Icons.home_work;
    } else if (cat == 'PHÁT SINH' || cat == 'REPAIR_PARTS') {
      color = const Color(0xFFFB8C00); icon = Icons.build;
    } else if (cat == 'NHẬP HÀNG' || cat == 'PURCHASE' || cat == 'ĐƠN NHẬP HÀNG') {
      color = const Color(0xFF43A047); icon = Icons.inventory_2;
    } else if (cat == 'Phí NH') {
      color = const Color(0xFF1E88E5); icon = Icons.account_balance;
    } else {
      color = Colors.grey; icon = Icons.shopping_cart;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade50),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (e['title'] ?? 'Không tên').toString(),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                Text(
                  "$scopeLabel • $cat • ${DateFormat('HH:mm dd/MM').format(DateTime.fromMillisecondsSinceEpoch(e['date']))}",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            "${isIncome ? '+' : '-'}${MoneyUtils.formatCurrency(e['amount'])}",
            style: TextStyle(color: isIncome ? const Color(0xFF2E7D32) : const Color(0xFFE53935), fontWeight: FontWeight.w700, fontSize: 14),
          ),
          if (e['isPurchaseDebt'] != true)
            SizedBox(
              width: 24, height: 24,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(Icons.delete_outline, color: Colors.grey.shade400, size: 14),
                onPressed: () => _handleDeleteExpense(e),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _viewMode == 'THU' ? Icons.account_balance_wallet_outlined : Icons.money_off_rounded,
          size: 80,
          color: Colors.grey[200],
        ),
        const SizedBox(height: 16),
        Text(
          kIsWeb
              ? "Tính năng này không khả dụng trên trình duyệt web.\nVui lòng sử dụng ứng dụng di động."
              : _viewMode == 'THU'
                  ? "Không có khoản thu phát sinh nào trong ${_filterType.toLowerCase()} này"
                  : "Không có chi phí nào trong ${_filterType.toLowerCase()} này",
          style: const TextStyle(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

class _ExpCat {
  final String label;
  final int value;
  final Color color;
  _ExpCat(this.label, this.value, this.color);
}
