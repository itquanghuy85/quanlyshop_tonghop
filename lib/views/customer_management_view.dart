import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/customer_model.dart';
import '../services/customer_service.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/global_search_bar.dart';

class CustomerManagementView extends StatefulWidget {
  const CustomerManagementView({super.key});

  @override
  State<CustomerManagementView> createState() => _CustomerManagementViewState();
}

class _CustomerManagementViewState extends State<CustomerManagementView> {
  final CustomerService _customerService = CustomerService();
  List<Customer> _customers = [];
  List<Customer> _filteredCustomers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      // Sync customers from cloud first (ignore errors)
      try {
        await SyncService.syncCustomersFromCloud();
      } catch (syncError) {
        debugPrint('Sync customers error (ignored): $syncError');
      }
      
      final customers = await _customerService.getCustomers();
      setState(() {
        _customers = customers;
        _filteredCustomers = customers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải danh sách khách hàng: $e')),
        );
      }
    }
  }

  void _filterCustomers(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredCustomers = _customers;
      } else {
        _filteredCustomers = _customers.where((customer) {
          return customer.name.toLowerCase().contains(query.toLowerCase()) ||
                 customer.phone.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _addCustomer() async {
    final result = await showDialog<Customer>(
      context: context,
      builder: (context) => const CustomerFormDialog(),
    );

    if (result != null) {
      await _customerService.addCustomer(result);
      _loadCustomers();
    }
  }

  Future<void> _editCustomer(Customer customer) async {
    // Verify owner password first
    if (!await _verifyOwnerPassword('chỉnh sửa khách hàng')) return;

    final result = await showDialog<Customer>(
      context: context,
      builder: (context) => CustomerFormDialog(customer: customer),
    );

    if (result != null) {
      await _customerService.updateCustomer(result);
      _loadCustomers();
    }
  }

  Future<void> _deleteCustomer(Customer customer) async {
    // Verify owner password first
    if (!await _verifyOwnerPassword('xóa khách hàng')) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa khách hàng "${customer.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _customerService.deleteCustomer(customer.id!);
      _loadCustomers();
    }
  }

  // ============ PASSWORD VERIFICATION ============
  Future<String?> _showPasswordDialog(String action) async {
    String password = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Xác nhận $action'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chỉ chủ shop được phép thực hiện.\nNhập mật khẩu tài khoản để xác nhận:'),
            const SizedBox(height: 10),
            TextField(
              obscureText: true,
              onChanged: (value) => password = value,
              decoration: const InputDecoration(
                hintText: 'Mật khẩu',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, password),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Future<bool> _verifyOwnerPassword(String action) async {
    final password = await _showPasswordDialog(action);
    if (password == null || password.isEmpty) return false;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập lại')),
      );
      return false;
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: currentUser.email!,
        password: password,
      );
      await currentUser.reauthenticateWithCredential(credential);
      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mật khẩu không đúng!')),
        );
      }
      return false;
    }
  }

  Future<void> _viewCustomerHistory(Customer customer) async {
    final history = await _customerService.getCustomerHistory(customer.phone);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => CustomerHistoryDialog(
        customer: customer,
        history: history,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
        title: const Text('Quản lý khách hàng', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addCustomer,
            tooltip: 'Thêm khách hàng',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: GlobalSearchBar(
              hintText: 'Tìm kiếm khách hàng...',
              onSearch: _filterCustomers,
            ),
          ),

          // Customer list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCustomers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Chưa có khách hàng nào'
                                  : 'Không tìm thấy khách hàng',
                              style: AppTextStyles.body1.copyWith(
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredCustomers.length,
                        itemBuilder: (context, index) {
                          final customer = _filteredCustomers[index];
                          return CustomerListItem(
                            customer: customer,
                            onEdit: () => _editCustomer(customer),
                            onDelete: () => _deleteCustomer(customer),
                            onViewHistory: () => _viewCustomerHistory(customer),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class CustomerListItem extends StatelessWidget {
  final Customer customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onViewHistory;

  const CustomerListItem({
    super.key,
    required this.customer,
    required this.onEdit,
    required this.onDelete,
    required this.onViewHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primary.withOpacity(0.1),
          child: Text(
            customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          customer.name,
          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              customer.phone,
              style: AppTextStyles.caption,
            ),
            if (customer.address?.isNotEmpty == true)
              Text(
                customer.address!,
                style: AppTextStyles.caption.copyWith(color: Colors.grey.shade600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (customer.notes?.isNotEmpty == true)
              Text(
                'Ghi chú: ${customer.notes!}',
                style: AppTextStyles.caption.copyWith(color: Colors.blue.shade600, fontStyle: FontStyle.italic),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Row(
              children: [
                Text(
                  'Đã mua: ${NumberFormat('#,###').format(customer.totalSpent)}đ',
                  style: AppTextStyles.caption.copyWith(color: AppColors.success),
                ),
                const SizedBox(width: 8),
                Text(
                  'Sửa: ${customer.totalRepairs} lần',
                  style: AppTextStyles.caption.copyWith(color: AppColors.warning),
                ),
              ],
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'edit':
                onEdit();
                break;
              case 'delete':
                onDelete();
                break;
              case 'history':
                onViewHistory();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'history',
              child: Row(
                children: [
                  Icon(Icons.history, size: 20),
                  SizedBox(width: 8),
                  Text('Lịch sử'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Chỉnh sửa'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Text('Xóa', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
        onTap: onViewHistory,
      ),
    );
  }
}

class CustomerFormDialog extends StatefulWidget {
  final Customer? customer;

  const CustomerFormDialog({super.key, this.customer});

  @override
  State<CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.customer != null) {
      _nameController.text = widget.customer!.name;
      _phoneController.text = widget.customer!.phone;
      _emailController.text = widget.customer!.email ?? '';
      _addressController.text = widget.customer!.address ?? '';
      _notesController.text = widget.customer!.notes ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.customer == null ? 'Thêm khách hàng' : 'Chỉnh sửa khách hàng'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Tên khách hàng *',
                  hintText: 'Nhập tên khách hàng',
                ),
                validator: (value) {
                  if (value?.trim().isEmpty == true) {
                    return 'Vui lòng nhập tên khách hàng';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại *',
                  hintText: 'Nhập số điện thoại',
                ),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  if (value?.trim().isEmpty == true) {
                    return 'Vui lòng nhập số điện thoại';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Nhập email (tùy chọn)',
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ',
                  hintText: 'Nhập địa chỉ (tùy chọn)',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  hintText: 'Nhập ghi chú (tùy chọn)',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _saveCustomer,
          child: const Text('Lưu'),
        ),
      ],
    );
  }

  void _saveCustomer() {
    if (!_formKey.currentState!.validate()) return;

    final customer = Customer(
      id: widget.customer?.id,
      firestoreId: widget.customer?.firestoreId,
      name: _nameController.text.trim(),
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      createdAt: widget.customer?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
      totalSpent: widget.customer?.totalSpent ?? 0,
      totalRepairs: widget.customer?.totalRepairs ?? 0,
      totalRepairCost: widget.customer?.totalRepairCost ?? 0,
      isSynced: widget.customer?.isSynced ?? false,
      deleted: widget.customer?.deleted ?? false,
    );

    Navigator.pop(context, customer);
  }
}

class CustomerHistoryDialog extends StatelessWidget {
  final Customer customer;
  final Map<String, dynamic> history;

  const CustomerHistoryDialog({
    super.key,
    required this.customer,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final historyList = history['history'] as List<dynamic>;
    final totalSales = history['totalSales'] as int;
    final totalRepairs = history['totalRepairs'] as int;
    final totalSpent = history['totalSpent'] as int;
    final totalRepairCost = history['totalRepairCost'] as int;

    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: Text(
                    customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: AppTextStyles.headline6,
                      ),
                      Text(
                        customer.phone,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),

            const Divider(),

            // Summary stats
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    'Tổng mua hàng',
                    '${NumberFormat('#,###').format(totalSpent)}đ',
                    '$totalSales đơn',
                    AppColors.success,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard(
                    'Tổng sửa chữa',
                    '${NumberFormat('#,###').format(totalRepairCost)}đ',
                    '$totalRepairs lần',
                    AppColors.warning,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // History list
            Expanded(
              child: historyList.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.history,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Chưa có lịch sử',
                            style: AppTextStyles.body1.copyWith(
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: historyList.length,
                      itemBuilder: (context, index) {
                        final item = historyList[index] as Map<String, dynamic>;
                        return _buildHistoryItem(item);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String amount, String count, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: AppTextStyles.body2.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            count,
            style: AppTextStyles.caption.copyWith(color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final type = item['type'] as String;
    final date = DateTime.fromMillisecondsSinceEpoch(item['date'] as int);
    final amount = item['amount'] as int;
    final description = item['description'] as String;

    final isSale = type == 'sale';
    final color = isSale ? AppColors.success : AppColors.warning;
    final icon = isSale ? Icons.shopping_cart : Icons.build;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.1),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          description,
          style: AppTextStyles.body2,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          DateFormat('dd/MM/yyyy HH:mm').format(date),
          style: AppTextStyles.caption,
        ),
        trailing: Text(
          '${NumberFormat('#,###').format(amount)}đ',
          style: AppTextStyles.body2.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}