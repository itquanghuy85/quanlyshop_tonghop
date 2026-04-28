import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../core/utils/money_utils.dart';
import '../models/customer_model.dart';
import '../services/customer_service.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/responsive_wrapper.dart';

class CustomerProfileView extends StatefulWidget {
  final Customer customer;

  const CustomerProfileView({super.key, required this.customer});

  @override
  State<CustomerProfileView> createState() => _CustomerProfileViewState();
}

class _CustomerProfileViewState extends State<CustomerProfileView> {
  final _service = CustomerService();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _saving = false;
  bool _loadingHistory = true;
  String _avatarUrl = '';
  String? _pendingAvatarPath;

  Map<String, dynamic> _history = const {
    'history': <dynamic>[],
    'totalSales': 0,
    'totalRepairs': 0,
    'totalPayments': 0,
    'totalSpent': 0,
    'totalRepairCost': 0,
    'totalPaymentAmount': 0,
  };

  String _historyFilter = 'all';

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _nameCtrl.text = c.name;
    _phoneCtrl.text = c.phone;
    _emailCtrl.text = c.email ?? '';
    _addressCtrl.text = c.address ?? '';
    _notesCtrl.text = c.notes ?? '';
    _avatarUrl = c.avatarUrl ?? '';
    _loadHistory();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final data = await _service.getCustomerHistory(_phoneCtrl.text.trim());
      if (!mounted) return;
      setState(() => _history = data);
    } catch (e) {
      NotificationService.showSnackBar('Không tải được lịch sử: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _pickAvatar() async {
    if (_saving) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2200,
    );
    if (picked == null) return;
    setState(() {
      _pendingAvatarPath = picked.path;
      _avatarUrl = picked.path;
    });
    NotificationService.showSnackBar(
      'Đã chọn ảnh khách hàng. Nhấn Lưu để tải lên.',
      color: Colors.blue,
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    if (name.isEmpty || phone.isEmpty) {
      NotificationService.showSnackBar('Tên và số điện thoại là bắt buộc', color: Colors.red);
      return;
    }

    final base = widget.customer;
    String finalAvatarUrl = _avatarUrl;

    setState(() => _saving = true);
    try {
      if (_pendingAvatarPath != null && _pendingAvatarPath!.trim().isNotEmpty) {
        NotificationService.showSnackBar(
          'Đang tải ảnh khách hàng lên hệ thống...',
          color: Colors.blue,
          duration: const Duration(seconds: 6),
        );
        final urls = await StorageService.uploadMultipleImages([
          _pendingAvatarPath!,
        ], 'user_photos');
        if (urls.isEmpty || urls.first.trim().isEmpty) {
          NotificationService.showSnackBar(
            'Tải ảnh khách hàng thất bại, vui lòng thử lại',
            color: Colors.red,
          );
          return;
        }
        finalAvatarUrl = urls.first;
      }

    final updated = base.copyWith(
      avatarUrl: finalAvatarUrl,
      name: name,
      phone: phone,
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );

      final ok = await _service.updateCustomer(updated);
      if (!mounted) return;
      if (!ok) {
        NotificationService.showSnackBar('Lưu khách hàng thất bại', color: Colors.red);
        return;
      }
      _avatarUrl = finalAvatarUrl;
      _pendingAvatarPath = null;
      NotificationService.showSnackBar('Đã lưu hồ sơ khách hàng', color: Colors.green);
      Navigator.pop(context, updated);
    } catch (e) {
      NotificationService.showSnackBar('Lỗi lưu khách hàng: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteCustomer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Xóa khách hàng'),
        content: Text('Bạn có chắc muốn xóa ${_nameCtrl.text.trim()}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _saving = true);
    try {
      final id = widget.customer.id;
      if (id == null) return;
      final deleted = await _service.deleteCustomer(id);
      if (!mounted) return;
      if (!deleted) {
        NotificationService.showSnackBar('Xóa khách hàng thất bại', color: Colors.red);
        return;
      }
      NotificationService.showSnackBar('Đã xóa khách hàng', color: Colors.green);
      Navigator.pop(context, {'deleted': true});
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<Map<String, dynamic>> get _filteredHistory {
    final all = List<Map<String, dynamic>>.from(_history['history'] as List<dynamic>? ?? const []);
    if (_historyFilter == 'all') return all;
    return all.where((e) => (e['type'] ?? '').toString() == _historyFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final totalSpent = (_history['totalSpent'] as int?) ?? widget.customer.totalSpent;
    final totalRepair = (_history['totalRepairCost'] as int?) ?? widget.customer.totalRepairCost;
    final avatarProvider = EntityAvatar.imageProviderFromUrl(_avatarUrl);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Hồ sơ khách hàng'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A56C2), Color(0xFF0E74DB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0E74DB), Color(0xFF5AA6F4)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => EntityAvatar.showPreview(
                      context,
                      _avatarUrl,
                      _nameCtrl.text.trim(),
                    ),
                    child: Container(
                      height: 190,
                      width: double.infinity,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade200,
                        borderRadius: BorderRadius.circular(12),
                        image: avatarProvider != null
                            ? DecorationImage(
                                image: avatarProvider,
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: Stack(
                        children: [
                          if (avatarProvider == null)
                            Center(
                              child: Text(
                                'Thêm ảnh khách hàng',
                                style: AppTextStyles.body1.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: Row(
                              children: [
                                if (avatarProvider != null)
                                  IconButton(
                                    tooltip: 'Xem ảnh lớn',
                                    onPressed: () => EntityAvatar.showPreview(
                                      context,
                                      _avatarUrl,
                                      _nameCtrl.text,
                                    ),
                                    icon: const Icon(Icons.fullscreen, color: Colors.white),
                                  ),
                                IconButton(
                                  tooltip: 'Đổi ảnh',
                                  onPressed: _pickAvatar,
                                  icon: const Icon(Icons.camera_alt, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _nameCtrl.text.trim().isEmpty ? 'Khách hàng' : _nameCtrl.text.trim(),
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.headline2.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _phoneCtrl.text.trim(),
                    style: AppTextStyles.subtitle1.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _statCard(
                      'Đã mua',
                      MoneyUtils.formatCompact(totalSpent),
                      Icons.shopping_cart_checkout,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      'Số lần sửa',
                      '${widget.customer.totalRepairs}',
                      Icons.build,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _statCard(
                      'Tổng sửa',
                      MoneyUtils.formatCompact(totalRepair),
                      Icons.receipt_long,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Tác vụ nhanh', style: AppTextStyles.headline6),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _actionChip('Tất cả', 'all'),
                        _actionChip('Mua bán', 'sale'),
                        _actionChip('Sửa chữa', 'repair'),
                        _actionChip('Thanh toán', 'payment'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save),
                            label: const Text('Chỉnh sửa và Lưu'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _deleteCustomer,
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            label: const Text('Xóa', style: TextStyle(color: Colors.red)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thông tin khách hàng', style: AppTextStyles.headline6),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Họ và tên', prefixIcon: Icon(Icons.person)),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Địa chỉ', prefixIcon: Icon(Icons.location_on)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(labelText: 'Ghi chú', prefixIcon: Icon(Icons.notes)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Lịch sử giao dịch', style: AppTextStyles.headline6),
                        const Spacer(),
                        if (_loadingHistory)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_filteredHistory.isEmpty)
                      Text('Chưa có lịch sử phù hợp', style: AppTextStyles.caption)
                    else
                      ..._filteredHistory.take(20).map((h) {
                        final dateMs = (h['date'] as int?) ?? 0;
                        final amount = (h['amount'] as int?) ?? 0;
                        final dateText = dateMs > 0
                            ? DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(dateMs))
                            : '--';
                        final type = (h['type'] ?? '').toString();
                        final label = type == 'sale'
                            ? 'Mua bán'
                            : (type == 'repair' ? 'Sửa chữa' : 'Thanh toán');
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: type == 'sale'
                                ? Colors.green.shade100
                                : (type == 'repair' ? Colors.orange.shade100 : Colors.blue.shade100),
                            child: Icon(
                              type == 'sale'
                                  ? Icons.shopping_bag
                                  : (type == 'repair' ? Icons.build : Icons.payments_outlined),
                              size: 14,
                              color: type == 'sale'
                                  ? Colors.green.shade700
                                  : (type == 'repair' ? Colors.orange.shade700 : Colors.blue.shade700),
                            ),
                          ),
                          title: Text('$label • ${MoneyUtils.formatCompact(amount)}', style: AppTextStyles.body1),
                          subtitle: Text('${h['description'] ?? ''}\n$dateText', style: AppTextStyles.caption),
                          isThreeLine: true,
                        );
                      }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionChip(String label, String value) {
    final selected = _historyFilter == value;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _historyFilter = value);
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF0B66D1), size: 18),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(title, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
