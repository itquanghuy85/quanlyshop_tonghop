import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/responsive_wrapper.dart';
import '../data/db_helper.dart';
import '../models/sale_order_model.dart';
import '../utils/money_utils.dart';
import '../services/event_bus.dart';
import '../services/user_service.dart';
import '../theme/app_text_styles.dart';
import 'sale_detail_view.dart';

/// Màn hình thống kê đơn trả góp ngân hàng
/// - Lọc theo ngân hàng
/// - Lọc theo thời gian (ngày, tuần, tháng, tùy chọn)
/// - Hiển thị tổng tiền, đã nhận, chờ nhận
class BankInstallmentReportView extends StatefulWidget {
  final bool embedded;
  const BankInstallmentReportView({super.key, this.embedded = false});

  @override
  State<BankInstallmentReportView> createState() => _BankInstallmentReportViewState();
}

class _BankInstallmentReportViewState extends State<BankInstallmentReportView> {
  final db = DBHelper();
  List<SaleOrder> _allInstallmentSales = [];
  bool _loading = true;

  // Filters
  String _selectedBank = 'all'; // 'all' or bank name
  String _timeFilter = 'month'; // all, today, week, month, custom
  DateTime? _customStartDate;
  DateTime? _customEndDate;

  // Unique bank names from data
  List<String> _bankNames = [];
  bool _hasPermission = false;

  @override
  void initState() {
    super.initState();
    _checkPermission();
    _loadData();
    EventBus().on('sales_changed', (_) {
      if (mounted) _loadData();
    });
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = perms['allowViewRevenue'] ?? false);
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    
    try {
      final allSales = await db.getAllSales();
      debugPrint('BankInstallment: Total sales = ${allSales.length}');
      
      // Lọc đơn trả góp ngân hàng
      _allInstallmentSales = allSales.where((s) => 
        s.isInstallment && s.paymentMethod.toUpperCase() == 'TRẢ GÓP (NH)'
      ).toList();
      
      debugPrint('BankInstallment: Installment sales = ${_allInstallmentSales.length}');
      for (var s in _allInstallmentSales) {
        debugPrint('  - ${s.customerName}: bank1=${s.bankName} loan1=${s.loanAmount}, bank2=${s.bankName2} loan2=${s.loanAmount2}');
      }
      
      // Sort by date descending
      _allInstallmentSales.sort((a, b) => b.soldAt.compareTo(a.soldAt));
      
      // Extract unique bank names - loại bỏ duplicate và giá trị 'all'
      final banks = <String>{};
      for (var s in _allInstallmentSales) {
        if (s.bankName != null && s.bankName!.isNotEmpty && s.bankName != 'all') {
          banks.add(s.bankName!);
        }
      }
      _bankNames = banks.toList()..sort();
      
      // Reset selected bank nếu không còn trong danh sách
      if (_selectedBank != 'all' && !_bankNames.contains(_selectedBank)) {
        _selectedBank = 'all';
      }
      
    } catch (e) {
      debugPrint('BankInstallmentReportView _loadData error: $e');
    }
    
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  List<SaleOrder> _applyFilters() {
    return _allInstallmentSales.where((s) {
      // Bank filter
      if (_selectedBank != 'all') {
        if (s.bankName != _selectedBank) return false;
      }
      
      // Time filter
      final saleDate = DateTime.fromMillisecondsSinceEpoch(s.soldAt);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      switch (_timeFilter) {
        case 'today':
          final saleDay = DateTime(saleDate.year, saleDate.month, saleDate.day);
          if (saleDay != today) return false;
          break;
        case 'week':
          final weekAgo = today.subtract(const Duration(days: 7));
          if (saleDate.isBefore(weekAgo)) return false;
          break;
        case 'month':
          final monthStart = DateTime(now.year, now.month, 1);
          if (saleDate.isBefore(monthStart)) return false;
          break;
        case 'custom':
          if (_customStartDate != null && saleDate.isBefore(_customStartDate!)) return false;
          if (_customEndDate != null && saleDate.isAfter(_customEndDate!.add(const Duration(days: 1)))) return false;
          break;
      }
      
      return true;
    }).toList();
  }

  // Tính tổng các giá trị
  Map<String, int> _calculateTotals(List<SaleOrder> sales) {
    int totalAmount = 0; // Tổng giá trị đơn
    int totalDownPayment = 0; // Tổng đã nhận trước
    int totalLoanAmount = 0; // Tổng NH giải ngân (dự kiến)
    int totalReceived = 0; // Tổng đã nhận từ NH
    int totalPending = 0; // Tổng chờ NH chuyển
    int totalFee = 0; // Tổng phí NH
    int countReceived = 0; // Số đơn đã tất toán
    int countPending = 0; // Số đơn chờ tất toán
    
    for (var s in sales) {
      totalAmount += s.totalPrice;
      totalDownPayment += s.downPayment;
      totalLoanAmount += s.loanAmount + s.loanAmount2; // Include both loans
      totalFee += s.settlementFee;
      
      if (s.settlementReceivedAt != null) {
        totalReceived += s.settlementAmount > 0 ? s.settlementAmount : (s.loanAmount + s.loanAmount2);
        countReceived++;
      } else {
        totalPending += s.loanAmount + s.loanAmount2; // Include both loans
        countPending++;
      }
    }
    
    return {
      'totalAmount': totalAmount,
      'totalDownPayment': totalDownPayment,
      'totalLoanAmount': totalLoanAmount,
      'totalReceived': totalReceived,
      'totalPending': totalPending,
      'totalFee': totalFee,
      'countReceived': countReceived,
      'countPending': countPending,
      'count': sales.length,
    };
  }

  // Thống kê theo từng ngân hàng
  Map<String, Map<String, int>> _calculateByBank(List<SaleOrder> sales) {
    final result = <String, Map<String, int>>{};
    
    for (var s in sales) {
      // Xử lý NH thứ nhất
      final bank = (s.bankName == null || s.bankName!.isEmpty) 
          ? 'Không xác định' 
          : s.bankName!;
      
      if (!result.containsKey(bank)) {
        result[bank] = {
          'count': 0,
          'totalAmount': 0,
          'totalReceived': 0,
          'totalPending': 0,
          'totalFee': 0,
        };
      }
      
      result[bank]!['count'] = (result[bank]!['count'] ?? 0) + 1;
      result[bank]!['totalAmount'] = (result[bank]!['totalAmount'] ?? 0) + s.loanAmount;
      result[bank]!['totalFee'] = (result[bank]!['totalFee'] ?? 0) + s.settlementFee;
      
      if (s.settlementReceivedAt != null) {
        result[bank]!['totalReceived'] = (result[bank]!['totalReceived'] ?? 0) + 
            (s.settlementAmount > 0 ? s.settlementAmount : s.loanAmount);
      } else {
        result[bank]!['totalPending'] = (result[bank]!['totalPending'] ?? 0) + s.loanAmount;
      }
      
      // Xử lý NH thứ hai (nếu có)
      if (s.loanAmount2 > 0 && s.bankName2 != null && s.bankName2!.isNotEmpty) {
        final bank2 = s.bankName2!;
        
        if (!result.containsKey(bank2)) {
          result[bank2] = {
            'count': 0,
            'totalAmount': 0,
            'totalReceived': 0,
            'totalPending': 0,
            'totalFee': 0,
          };
        }
        
        result[bank2]!['count'] = (result[bank2]!['count'] ?? 0) + 1;
        result[bank2]!['totalAmount'] = (result[bank2]!['totalAmount'] ?? 0) + s.loanAmount2;
        // settlementFee chỉ tính cho NH chính
        
        // Giả định: nếu đơn đã tất toán thì cả 2 NH đều tất toán
        if (s.settlementReceivedAt != null) {
          result[bank2]!['totalReceived'] = (result[bank2]!['totalReceived'] ?? 0) + s.loanAmount2;
        } else {
          result[bank2]!['totalPending'] = (result[bank2]!['totalPending'] ?? 0) + s.loanAmount2;
        }
      }
    }
    
    return result;
  }

  Future<void> _selectDateRange() async {
    final initialRange = DateTimeRange(
      start: _customStartDate ?? DateTime.now(),
      end: _customEndDate ?? DateTime.now(),
    );
    
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initialRange,
      locale: const Locale('vi', 'VN'),
    );
    
    if (picked != null) {
      setState(() {
        _customStartDate = picked.start;
        _customEndDate = picked.end;
        _timeFilter = 'custom';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      if (widget.embedded) {
        return const Center(
          child: Text(
            'Bạn không có quyền truy cập tính năng này',
            style: TextStyle(color: Colors.grey),
          ),
        );
      }
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFF),
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
          title: const Text('TRẢ GÓP NGÂN HÀNG'),
        ),
        body: const Center(
          child: Text(
            'Bạn không có quyền truy cập tính năng này',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    final filteredSales = _applyFilters();
    final totals = _calculateTotals(filteredSales);
    final byBank = _calculateByBank(filteredSales);
    
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : Column(
            children: [
              _buildFilters(),
              _buildSummaryCards(totals),
              Expanded(
                child: _selectedBank == 'all'
                    ? _buildBankBreakdown(byBank)
                    : _buildSalesList(filteredSales),
              ),
            ],
          );

    if (widget.embedded) return ResponsiveCenter(child: body);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
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
        title: Text(
          'THỐNG KÊ TRẢ GÓP NH',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTextStyles.headline3.fontSize, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
            tooltip: 'Làm mới',
          ),
        ],
      ),
      body: ResponsiveCenter(child: body),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Time filter
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildTimeChip('Tất cả', 'all'),
                _buildTimeChip('Hôm nay', 'today'),
                _buildTimeChip('7 ngày', 'week'),
                _buildTimeChip('Tháng này', 'month'),
                ActionChip(
                  avatar: Icon(
                    Icons.date_range,
                    size: 16,
                    color: _timeFilter == 'custom' ? Colors.white : Colors.indigo,
                  ),
                  label: Text(
                    _timeFilter == 'custom' && _customStartDate != null
                        ? '${DateFormat('dd/MM').format(_customStartDate!)} - ${DateFormat('dd/MM').format(_customEndDate!)}'
                        : 'Tùy chọn',
                    style: TextStyle(
                      color: _timeFilter == 'custom' ? Colors.white : Colors.indigo,
                      fontSize: AppTextStyles.subtitle1.fontSize,
                    ),
                  ),
                  backgroundColor: _timeFilter == 'custom' ? Colors.indigo : Colors.indigo.shade50,
                  onPressed: _selectDateRange,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          
          // Bank filter
          Row(
            children: [
              const Text('Ngân hàng: ', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBank,
                      isExpanded: true,
                      hint: const Text('Chọn ngân hàng'),
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Tất cả ngân hàng'),
                        ),
                        // Lọc bỏ các bank name trùng với 'all' và loại bỏ duplicate
                        ..._bankNames
                            .where((bank) => bank.isNotEmpty && bank != 'all')
                            .toSet() // Loại bỏ duplicate
                            .map((bank) => DropdownMenuItem(
                              value: bank,
                              child: Text(bank),
                            )),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _selectedBank = value);
                        }
                      },
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

  Widget _buildTimeChip(String label, String value) {
    final isSelected = _timeFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.indigo,
            fontSize: AppTextStyles.subtitle1.fontSize,
          ),
        ),
        selected: isSelected,
        selectedColor: Colors.indigo,
        backgroundColor: Colors.indigo.shade50,
        onSelected: (_) {
          setState(() => _timeFilter = value);
        },
      ),
    );
  }

  Widget _buildSummaryCards(Map<String, int> totals) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          // Row 1: Count and total amount
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'Tổng đơn',
                  '${totals['count']}',
                  Icons.receipt_long,
                  Colors.blue,
                  subtitle: '${totals['countReceived']} đã TT / ${totals['countPending']} chờ TT',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryCard(
                  'Tổng tiền NH',
                  '${MoneyUtils.formatCurrency(totals['totalLoanAmount'] ?? 0)}đ',
                  Icons.account_balance,
                  Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Row 2: Received and Pending
          Row(
            children: [
              Expanded(
                child: _summaryCard(
                  'Đã nhận từ NH',
                  '${MoneyUtils.formatCurrency(totals['totalReceived'] ?? 0)}đ',
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryCard(
                  'Chờ NH chuyển',
                  '${MoneyUtils.formatCurrency(totals['totalPending'] ?? 0)}đ',
                  Icons.hourglass_empty,
                  Colors.orange,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Row 3: Fee
          if ((totals['totalFee'] ?? 0) > 0)
            _summaryCard(
              'Phí NH đã trừ',
              '${MoneyUtils.formatCurrency(totals['totalFee'] ?? 0)}đ',
              Icons.money_off,
              Colors.red,
              fullWidth: true,
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color, {String? subtitle, bool fullWidth = false}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    color: Colors.grey.shade700,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: AppTextStyles.headline4.fontSize,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: AppTextStyles.caption.fontSize,
                      color: Colors.grey.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBankBreakdown(Map<String, Map<String, int>> byBank) {
    if (byBank.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Không có đơn trả góp\ntrong khoảng thời gian này',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }
    
    // Sort banks by total amount descending
    final sortedBanks = byBank.entries.toList()
      ..sort((a, b) => (b.value['totalAmount'] ?? 0).compareTo(a.value['totalAmount'] ?? 0));
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: sortedBanks.length,
      itemBuilder: (context, index) {
        final entry = sortedBanks[index];
        final bank = entry.key;
        final data = entry.value;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              // Chỉ cho tap nếu bank tồn tại trong danh sách dropdown
              if (_bankNames.contains(bank)) {
                setState(() => _selectedBank = bank);
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.account_balance, color: Colors.indigo.shade700, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              bank,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextStyles.headline3.fontSize,
                              ),
                            ),
                            Text(
                              '${data['count']} đơn',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: AppTextStyles.subtitle1.fontSize,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: Colors.grey),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _bankStatItem(
                          'Tổng tiền',
                          '${MoneyUtils.formatCurrency(data['totalAmount'] ?? 0)}đ',
                          Colors.blue,
                        ),
                      ),
                      Expanded(
                        child: _bankStatItem(
                          'Đã nhận',
                          '${MoneyUtils.formatCurrency(data['totalReceived'] ?? 0)}đ',
                          Colors.green,
                        ),
                      ),
                      Expanded(
                        child: _bankStatItem(
                          'Chờ nhận',
                          '${MoneyUtils.formatCurrency(data['totalPending'] ?? 0)}đ',
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bankStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: AppTextStyles.body1.fontSize,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: AppTextStyles.subtitle1.fontSize,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSalesList(List<SaleOrder> sales) {
    if (sales.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Không có đơn trả góp\ncho ngân hàng "$_selectedBank"',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Xem tất cả'),
              onPressed: () => setState(() => _selectedBank = 'all'),
            ),
          ],
        ),
      );
    }
    
    return Column(
      children: [
        // Back button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text('Xem tất cả'),
                onPressed: () => setState(() => _selectedBank = 'all'),
              ),
              const Spacer(),
              Text(
                '${sales.length} đơn',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        
        // Sales list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: sales.length,
            itemBuilder: (context, index) {
              final s = sales[index];
              final isReceived = s.settlementReceivedAt != null;
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => SaleDetailView(sale: s)),
                    );
                    _loadData(); // Refresh after returning
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.customerName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: AppTextStyles.headline4.fontSize,
                                    ),
                                  ),
                                  Text(
                                    s.productNames,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: AppTextStyles.subtitle1.fontSize,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isReceived ? Colors.green.shade50 : Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isReceived ? 'Đã TT' : 'Chờ TT',
                                style: TextStyle(
                                  color: isReceived ? Colors.green.shade700 : Colors.orange.shade700,
                                  fontSize: AppTextStyles.body1.fontSize,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _saleInfoChip(
                              Icons.account_balance,
                              s.bankName ?? '?',
                              Colors.indigo,
                            ),
                            const SizedBox(width: 8),
                            _saleInfoChip(
                              Icons.calendar_today,
                              DateFormat('dd/MM/yy').format(
                                DateTime.fromMillisecondsSinceEpoch(s.soldAt),
                              ),
                              Colors.grey,
                            ),
                            const Spacer(),
                            Text(
                              '${MoneyUtils.formatCurrency(s.loanAmount)}đ',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo.shade700,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _saleInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
