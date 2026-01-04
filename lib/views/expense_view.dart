import 'dart:async';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
// BỔ SUNG THƯ VIỆN BỊ THIẾU
import 'package:fl_chart/fl_chart.dart';
import '../core/utils/money_utils.dart';
import '../data/db_helper.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/sync_service.dart';
import '../services/user_service.dart';
import '../widgets/validated_text_field.dart';
import '../services/event_bus.dart';
import '../widgets/currency_text_field.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';
import 'fast_stock_in_view.dart';

class ExpenseView extends StatefulWidget {
  const ExpenseView({super.key});
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
              "Bạn đang xóa khoản chi: ${exp['title']}\nSố tiền: ${MoneyUtils.formatVND(exp['amount'])}đ",
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

          await db.deleteExpenseByFirestoreId(exp['firestoreId']);
          await FirestoreService.deleteExpenseCloud(exp['firestoreId']);

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

  void _showAddExpenseDialog() {
    if (_isSaving) return;
    final titleC = TextEditingController();
    final amountC = TextEditingController();
    final noteC = TextEditingController();
    String category = "PHÁT SINH";
    String payMethod = "TIỀN MẶT";

    bool isValidExpenseInput() {
      return titleC.text.isNotEmpty && amountC.text.isNotEmpty;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          titleC.addListener(() => setS(() {}));
          amountC.addListener(() => setS(() {}));
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
            ),
            title: Text(
              "GHI CHÉP CHI PHÍ",
              style: AppTextStyles.headline5.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
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
                    children: ["CỐ ĐỊNH", "PHÁT SINH", "LƯƠNG", "MẶT BẰNG", "ĐIỆN NƯỚC", "KHÁC"]
                        .map(
                          (c) => ChoiceChip(
                            label: Text(c, style: AppTextStyles.caption.copyWith(fontSize: 11)),
                            selected: category == c,
                            onSelected: (v) => setS(() => category = c),
                            selectedColor: AppColors.error.withOpacity(0.1),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 15),
                  _input(titleC, "Nội dung chi *", Icons.edit_note, caps: true),
                  _input(
                    amountC,
                    "Số tiền (x1k) *",
                    Icons.payments,
                    type: TextInputType.number,
                  ),
                  _input(noteC, "Ghi chú thêm", Icons.description),
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
                onPressed: isValidExpenseInput() && !_isSaving
                    ? () async {
                        if (titleC.text.isEmpty ||
                            amountC.text.isEmpty ||
                            _isSaving)
                          return;
                        setS(() => _isSaving = true);

                        // Lấy giá trị đã được CurrencyTextField xử lý
                        int amount = CurrencyTextField.parseValue(amountC.text);

                        final String fId =
                            "exp_${DateTime.now().millisecondsSinceEpoch}_${titleC.text.hashCode}";
                        final expData = {
                          'firestoreId': fId,
                          'title': titleC.text.toUpperCase(),
                          'amount': amount,
                          'category': category,
                          'date': DateTime.now().millisecondsSinceEpoch,
                          'note': noteC.text,
                          'paymentMethod': payMethod,
                        };

                        final navigator = Navigator.of(ctx);
                        await db.insertExpense(expData);
                        await FirestoreService.addExpenseCloud(expData);

                        final user = FirebaseAuth.instance.currentUser;
                        await db.logAction(
                          userId: user?.uid ?? "0",
                          userName:
                              user?.email?.split('@').first.toUpperCase() ??
                              "NV",
                          action: "CHI PHÍ",
                          type: "FINANCE",
                          desc: "Đã chi ${MoneyUtils.formatVND(amount)}đ",
                        );

                        if (!mounted) return;
                        navigator.pop();
                        await _refresh(); // Load lại data từ DB thay vì chỉ filter
                        setState(() {
                          _isSaving = false;
                        });
                        NotificationService.showSnackBar(
                          "Đã lưu chi phí!",
                          color: AppColors.success,
                        );
                      }
                    : null,
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

  Widget _input(
    TextEditingController c,
    String l,
    IconData i, {
    TextInputType type = TextInputType.text,
    bool caps = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: type == TextInputType.number
          ? CurrencyTextField(controller: c, label: l, icon: i)
          : ValidatedTextField(
              controller: c,
              label: l,
              icon: i,
              uppercase: caps,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("QUẢN LÝ CHI PHÍ"),
          backgroundColor: AppColors.surface,
          elevation: 0,
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: Text(
          "QUẢN LÝ CHI PHÍ",
          style: AppTextStyles.headline6.copyWith(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => FastStockInView()),
            ),
            icon: Icon(Icons.inventory_2_outlined, color: AppColors.success),
            tooltip: 'Nhập kho',
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _syncStatus,
                style: AppTextStyles.caption.copyWith(
                  color: _syncStatus == 'Lỗi đồng bộ'
                      ? AppColors.error
                      : AppColors.onSurface.withOpacity(0.6),
                  fontWeight: _isSyncing ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _isSyncing ? null : _syncWithFirebase,
                icon: Icon(
                  _isSyncing ? Icons.sync : Icons.sync_outlined,
                  color: _isSyncing ? AppColors.warning : AppColors.primary,
                ),
                tooltip: 'Đồng bộ với Firebase',
              ),
            ],
          ),
        ],
      ),
      body: Column(
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
      ),
      floatingActionButton: kIsWeb
          ? null
          : FloatingActionButton.extended(
              onPressed: _showAddExpenseDialog,
              label: const Text(
                "CHI PHÍ MỚI",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              icon: const Icon(Icons.add_circle_outline),
              backgroundColor: const Color(0xFFD32F2F),
            ),
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
              const Text(
                "LỌC THEO: ",
                style: TextStyle(
                  fontSize: 12,
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
                              fontSize: 11,
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
                      style: const TextStyle(
                        fontSize: 14,
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

    String headerTitle = _filterType == 'NGÀY'
        ? 'TỔNG CHI HÔM NAY'
        : _filterType == 'TUẦN'
        ? 'TỔNG CHI TUẦN NÀY'
        : 'TỔNG CHI THÁNG NÀY';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFB71C1C), Color(0xFFEF5350)],
        ),
        borderRadius: BorderRadius.circular(25),
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
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "${MoneyUtils.formatVND(total)} đ",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
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
        Text(label, style: const TextStyle(color: Colors.white60, fontSize: 9)),
        Text(
          MoneyUtils.formatVND(val),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _expenseProfessionalCard(Map<String, dynamic> e) {
    final cat = e['category'] ?? 'KHÁC';
    Color color;
    IconData icon;
    
    if (cat == 'CỐ ĐỊNH' || cat == 'LƯƠNG' || cat == 'MẶT BẰNG' || cat == 'ĐIỆN NƯỚC') {
      color = Colors.blue;
      icon = Icons.home_work;
    } else if (cat == 'PHÁT SINH' || cat == 'REPAIR_PARTS') {
      color = Colors.orange;
      icon = Icons.build;
    } else if (cat == 'NHẬP HÀNG' || cat == 'PURCHASE' || cat == 'ĐƠN NHẬP HÀNG') {
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
          child: Icon(
            icon,
            color: color,
            size: 24,
          ),
        ),
        title: Text(
          e['title'],
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: Color(0xFF1A237E),
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              cat,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
            ),
            Text(
              "${DateFormat('HH:mm - dd/MM').format(DateTime.fromMillisecondsSinceEpoch(e['date']))} | ${e['isPurchaseDebt'] == true ? 'CÔNG NỢ' : (e['paymentMethod'] ?? 'TIỀN MẶT')}",
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "-${MoneyUtils.formatVND(e['amount'])}",
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w900,
                fontSize: 15,
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
