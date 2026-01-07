import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/money_utils.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import 'repair_detail_view.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';
import 'sale_detail_view.dart';
import '../theme/app_theme.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';

class CustomerListView extends StatefulWidget {
  final String role;
  const CustomerListView({super.key, this.role = 'user'});

  @override
  State<CustomerListView> createState() => _CustomerListViewState();
}

class _CustomerListViewState extends State<CustomerListView> {
  final db = DBHelper();
  List<Map<String, dynamic>> _customers = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _showUnassignedOnly = false; // Thêm biến này
  
  // Multi-select state
  bool _isSelectionMode = false;
  final Set<int> _selectedIndices = {};
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _refresh();
  }

  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final role = await UserService.getUserRole(uid);
    if (!mounted) return;
    setState(() {
      _isAdmin = role == 'admin';
    });
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);

    // Lấy toàn bộ repairs và sales
    final allRepairs = await db.getAllRepairs();
    final allSales = await db.getAllSales();

    // Map<phone, customer info>
    final Map<String, Map<String, dynamic>> customerMap = {};

    // Gộp từ repairs
    for (var r in allRepairs) {
      final phone = r.phone;
      if (phone.isNotEmpty) {
        final key = phone;
        customerMap.putIfAbsent(key, () => {
          'customerName': r.customerName,
          'phone': phone,
          'address': r.address,
          'totalSpent': 0,
          'repairCount': 0,
          'saleCount': 0,
        });
        customerMap[key]!['totalSpent'] = (customerMap[key]!['totalSpent'] as int) + r.price;
        customerMap[key]!['repairCount'] = (customerMap[key]!['repairCount'] as int) + 1;
      }
    }

    // Gộp từ sales
    for (var s in allSales) {
      final phone = s.phone;
      if (phone.isNotEmpty) {
        final key = phone;
        customerMap.putIfAbsent(key, () => {
          'customerName': s.customerName,
          'phone': phone,
          'address': s.address,
          'totalSpent': 0,
          'repairCount': 0,
          'saleCount': 0,
        });
        customerMap[key]!['totalSpent'] = (customerMap[key]!['totalSpent'] as int) + s.totalPrice;
        customerMap[key]!['saleCount'] = (customerMap[key]!['saleCount'] as int) + 1;
      }
    }

    // Nếu lọc khách chưa gán shop, chỉ lấy từ bảng customers chưa có shopId
    List<Map<String, dynamic>> result;
    if (_showUnassignedOnly) {
      final unassigned = await db.getCustomersWithoutShop();
      // Chỉ lấy những khách chưa gán shop có trong customerMap
      result = unassigned.where((c) => customerMap.containsKey(c['phone'])).map((c) {
        final merged = Map<String, dynamic>.from(customerMap[c['phone']]!);
        merged['customerName'] = c['customerName'] ?? merged['customerName'];
        merged['address'] = c['address'] ?? merged['address'];
        return merged;
      }).toList();
    } else {
      result = customerMap.values.toList();
    }

    // Sắp xếp theo tên khách hàng
    result.sort((a, b) => (a['customerName'] ?? '').toString().compareTo((b['customerName'] ?? '').toString()));

    setState(() {
      _customers = result;
      _isLoading = false;
    });
  }

  void _toggleSelection(int index) {
    setState(() {
      if (_selectedIndices.contains(index)) {
        _selectedIndices.remove(index);
        if (_selectedIndices.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIndices.add(index);
      }
    });
  }

  void _startSelection(int index) {
    setState(() {
      _isSelectionMode = true;
      _selectedIndices.add(index);
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedIndices.clear();
    });
  }

  Future<void> _deleteSelectedCustomers() async {
    if (_selectedIndices.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);

    // Xác thực mật khẩu admin
    final password = await _showPasswordDialog();
    if (password == null || password.isEmpty) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      // Re-authenticate với mật khẩu
      final credential = EmailAuthProvider.credential(
        email: currentUser.email!,
        password: password,
      );
      await currentUser.reauthenticateWithCredential(credential);
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Mật khẩu không đúng!"))
      );
      return;
    }

    setState(() => _isDeleting = true);

    try {
      final selectedCustomers = _selectedIndices.map((i) => _customers[i]).toList();
      
      for (final customer in selectedCustomers) {
        // Xóa tất cả repairs và sales của customer này
        await db.deleteCustomerData(customer['customerName'], customer['phone']);
        if (customer['firestoreId'] != null) {
          await FirestoreService.deleteCustomer(customer['firestoreId']);
        }
      }

      await _refresh();
      _cancelSelection();

      messenger.showSnackBar(
        SnackBar(content: Text("Đã xóa ${selectedCustomers.length} khách hàng"))
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Lỗi khi xóa: $e"))
      );
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  Future<String?> _showPasswordDialog() async {
    String password = '';
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Nhập mật khẩu tài khoản chủ shop để xóa:"),
            const SizedBox(height: 10),
            TextField(
              obscureText: true,
              onChanged: (value) => password = value,
              decoration: const InputDecoration(
                hintText: "Mật khẩu",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, password),
            child: const Text("Xác nhận"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 2,
        automaticallyImplyLeading: true,
        title: Text(
          _isSelectionMode 
            ? "Đã chọn ${_selectedIndices.length} khách hàng"
            : _showUnassignedOnly 
              ? "KHÁCH HÀNG CHƯA GÁN SHOP (${_customers.length})"
              : "HỆ THỐNG KHÁCH HÀNG (${_customers.length})", 
          style: AppTextStyles.headline6.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.bold)
        ),
        actions: _isSelectionMode ? [
          IconButton(
            icon: Icon(Icons.close, color: AppColors.onPrimary),
            onPressed: _cancelSelection,
            tooltip: "Hủy chọn",
          ),
          if (_isAdmin)
            IconButton(
              icon: Icon(Icons.delete_forever, color: AppColors.onPrimary),
              onPressed: _isDeleting ? null : _deleteSelectedCustomers,
              tooltip: "Xóa các khách đã chọn",
            ),
        ] : [
          IconButton(
            icon: Icon(_showUnassignedOnly ? Icons.group : Icons.group_off, color: AppColors.onPrimary),
            onPressed: () {
              setState(() => _showUnassignedOnly = !_showUnassignedOnly);
              _refresh();
            },
            tooltip: _showUnassignedOnly ? "Xem tất cả khách hàng" : "Xem khách chưa gán shop",
          ),
        ],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _customers.isEmpty
          ? const Center(child: Text("Chưa có dữ liệu khách hàng"))
          : ListView.builder(
              padding: const EdgeInsets.all(15),
              itemCount: _customers.length,
              itemBuilder: (ctx, i) {
                final c = _customers[i];
                return _customerCard(c, i);
              },
            ),
    );
  }

  Widget _customerCard(Map<String, dynamic> c, int index) {
    final bool canDelete = _isAdmin && (c['repairCount'] as int? ?? 0) == 0 && (c['saleCount'] as int? ?? 0) == 0;
    final bool isSelected = _selectedIndices.contains(index);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: isSelected ? AppColors.primary.withOpacity(0.1) : AppColors.surface,
      child: InkWell(
        onTap: _isSelectionMode 
          ? () => _toggleSelection(index)
          : () => _showCustomerFullHistory(c),
        onLongPress: _isSelectionMode 
          ? null 
          : () => _startSelection(index),
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_isSelectionMode)
                    Checkbox(
                      value: isSelected,
                      onChanged: (value) => _toggleSelection(index),
                    ),
                  Expanded(
                    child: Text(
                      "${c['customerName']}",
                      style: AppTextStyles.body1.copyWith(
                        fontWeight: FontWeight.bold, 
                        color: isSelected ? AppColors.primary : AppColors.onSurface
                      ),
                    ),
                  ),
                  if (!_isSelectionMode && canDelete)
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: AppColors.error),
                      tooltip: "Xóa khách khỏi danh sách",
                      onPressed: () => _confirmDeleteCustomer(c),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "${MoneyUtils.formatVND(c['totalSpent'] ?? 0)} đ",
                      style: AppTextStyles.caption.copyWith(color: AppColors.onError, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text("SĐT: ${c['phone']}", style: AppTextStyles.body2.copyWith(color: AppColors.onSurface)),
              if ((c['address'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    "Địa chỉ: ${c['address']}",
                    style: AppTextStyles.caption.copyWith(color: AppColors.onSurface),
                  ),
                ),
              const Divider(height: 20),
              Row(
                children: [
                  _miniStat(Icons.build_circle_outlined, "${c['repairCount'] ?? 0} lần sửa", AppColors.info),
                  const SizedBox(width: 20),
                  _miniStat(Icons.shopping_bag_outlined, "${c['saleCount'] ?? 0} máy đã mua", AppColors.secondary),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _miniStat(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w500)),
      ],
    );
  }

  void _showCustomerFullHistory(Map<String, dynamic> c) async {
    final allRepairs = await db.getAllRepairs();
    final allSales = await db.getAllSales();
    
    final repairHistory = allRepairs.where((r) => r.phone == c['phone']).toList();
    final saleHistory = allSales.where((s) => s.phone == c['phone']).toList();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DefaultTabController(
        length: 2,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25))
          ),
          child: Column(
            children: [
              // Header với drag handle
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(10)
                ),
              ),

              // Customer info header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.person, color: AppColors.onPrimary, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c['customerName'].toString().toUpperCase(),
                                style: AppTextStyles.headline4.copyWith(fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                                  const SizedBox(width: 4),
                                  Text(
                                    c['phone'].toString(),
                                    style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
                                  ),
                                ],
                              ),
                              // address part
                              if (c['address'] != null && c['address'].toString().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Icon(Icons.location_on, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        c['address'].toString(),
                                        style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildStatItem(
                            "Tổng chi tiêu",
                            "${MoneyUtils.formatVND(c['totalSpent'] ?? 0)} đ",
                            Colors.red,
                            Icons.attach_money,
                          ),
                          _buildStatItem(
                            "Lần sửa chữa",
                            "${c['repairCount'] ?? 0}",
                            Colors.orange,
                            Icons.build,
                          ),
                          _buildStatItem(
                            "Lần mua hàng",
                            "${c['saleCount'] ?? 0}",
                            Colors.blue,
                            Icons.shopping_cart,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Tab bar
              Container(
                color: Colors.white,
                child: const TabBar(
                  labelColor: Colors.pink,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.pink,
                  indicatorWeight: 3,
                  tabs: [
                    Tab(text: "LỊCH SỬ SỬA CHỮA"),
                    Tab(text: "LỊCH SỬ MUA HÀNG"),
                  ],
                ),
              ),

              // Tab content
              Expanded(
                child: TabBarView(
                  children: [
                    _buildRepairHistoryList(repairHistory),
                    _buildSaleHistoryList(saleHistory),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRepairHistoryList(List<Repair> list) {
    if (list.isEmpty) return const Center(child: Text("Chưa có lịch sử sửa chữa"));
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final r = list[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: InkWell(
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(context, MaterialPageRoute(builder: (_) => RepairDetailView(repair: r)));
            },
            borderRadius: BorderRadius.circular(12),
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
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.build, color: Colors.orange, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.model,
                              style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold),
                            ),
                            Text(
                              "Lỗi: ${r.issue.split('|').first}",
                              style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "${MoneyUtils.formatVND(r.price)} đ",
                          style: AppTextStyles.priceStyle,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        "Ngày: ${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(r.createdAt))}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(r.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _getStatusText(r.status),
                          style: AppTextStyles.caption.copyWith(
                            color: _getStatusColor(r.status),
                            fontWeight: FontWeight.w500,
                          ),
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

  Widget _buildSaleHistoryList(List<SaleOrder> list) {
    if (list.isEmpty) return const Center(child: Text("Chưa có máy đã mua"));
    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: list.length,
      itemBuilder: (ctx, i) {
        final s = list[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
          child: InkWell(
            onTap: () => _showSaleDetail(s),
            borderRadius: BorderRadius.circular(12),
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
                          color: Colors.pink.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.phone_iphone, color: Colors.pink, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.productNames,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              "IMEI: ${s.productImeis}",
                              style: TextStyle(color: Colors.grey[600], fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          "${MoneyUtils.formatVND(s.totalPrice)} đ",
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today, size: 16, color: Colors.grey[500]),
                      const SizedBox(width: 4),
                      Text(
                        "Ngày mua: ${DateFormat('dd/MM/yyyy').format(DateTime.fromMillisecondsSinceEpoch(s.soldAt))}",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          "Đã bán",
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
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

  Future<void> _confirmDeleteCustomer(Map<String, dynamic> c) async {
    if (!_isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chỉ tài khoản QUẢN LÝ mới được xóa khách hàng khỏi danh sách')),
      );
      return;
    }

    final hasHistory = (c['repairCount'] as int? ?? 0) > 0 || (c['saleCount'] as int? ?? 0) > 0;
    if (hasHistory) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể xóa khách đã có lịch sử sửa/bán.')), 
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("XÓA KHÁCH HÀNG"),
        content: Text(
          "Bạn chắc chắn muốn xóa khách ${c['customerName']} (${c['phone']}) khỏi danh sách? Hành động này chỉ xóa khỏi DANH BẠ, không xóa lịch sử sửa/bán.",
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("HỦY")),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("XÓA")),
        ],
      ),
    );

    if (ok == true) {
      final firestoreId = c['firestoreId'] as String?;
      if (firestoreId != null) {
        await FirestoreService.deleteCustomer(firestoreId);
      }
      await db.deleteCustomerByPhone(c['phone'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ĐÃ XÓA KHÁCH KHỎI DANH BẠ')), 
      );
      _refresh();
    }
  }

  void _showSaleDetail(SaleOrder sale) {
    Navigator.pop(context); // Đóng bottom sheet
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SaleDetailView(sale: sale)),
    );
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1: return Colors.orange; // Đang sửa
      case 2: return Colors.blue;   // Chờ linh kiện
      case 3: return Colors.green;  // Hoàn thành
      case 4: return Colors.red;    // Đã trả máy
      default: return Colors.grey;
    }
  }

  String _getStatusText(int status) {
    switch (status) {
      case 1: return "Đang sửa";
      case 2: return "Chờ linh kiện";
      case 3: return "Hoàn thành";
      case 4: return "Đã trả máy";
      default: return "Không xác định";
    }
  }

  Widget _buildStatItem(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
