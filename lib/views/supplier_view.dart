import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../services/user_service.dart';
import '../services/event_bus.dart';
import '../services/supplier_service.dart';
import '../widgets/gradient_fab.dart';
import 'fast_stock_in_view.dart';
import 'supplier_details_dialog.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

class SupplierView extends StatefulWidget {
  const SupplierView({super.key});

  @override
  State<SupplierView> createState() => _SupplierViewState();
}

class _SupplierViewState extends State<SupplierView> {
  StreamSubscription<String>? _subscription;
  final db = DBHelper();
  final supplierService = SupplierService();
  List<Map<String, dynamic>> _suppliers = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRole();
    _refresh();
    _subscription = EventBus().on('suppliers_changed', _onSuppliersChanged);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSuppliersChanged(dynamic data) {
    _refresh();
  }

  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() {
      _isAdmin = perms['allowViewSuppliers'] ?? false;
    });
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final suppliers = await supplierService.getSuppliers();
    setState(() {
      _suppliers = suppliers.map((s) => s.toMap()).toList();
      _isLoading = false;
    });
  }

  List<Map<String, dynamic>> get _filteredSuppliers {
    if (_searchQuery.isEmpty) return _suppliers;
    return _suppliers.where((supplier) {
      final name = supplier['name']?.toString().toLowerCase() ?? '';
      final contact = supplier['contactPerson']?.toString().toLowerCase() ?? '';
      final phone = supplier['phone']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || contact.contains(query) || phone.contains(query);
    }).toList();
  }

  Future<void> _confirmDeleteSupplier(Map<String, dynamic> s) async {
    final messenger = ScaffoldMessenger.of(context);

    // Yêu cầu xác thực mật khẩu trước khi xóa
    final password = await _showPasswordDialog();
    if (password == null || password.isEmpty) return;

    // Xác thực mật khẩu
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Vui lòng đăng nhập lại', style: AppTextStyles.body2.copyWith(color: AppColors.onError)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: currentUser.email!,
        password: password,
      );
      await currentUser.reauthenticateWithCredential(credential);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Mật khẩu không đúng!', style: AppTextStyles.body2.copyWith(color: AppColors.onError)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 28),
            const SizedBox(width: 12),
            Text("XÓA NHÀ CUNG CẤP", style: AppTextStyles.headline6.copyWith(color: AppColors.error)),
          ],
        ),
        content: Text(
          "Bạn chắc chắn muốn xóa nhà cung cấp \"${s['name']}\" khỏi danh sách? Các sản phẩm cũ vẫn giữ nguyên thông tin NCC dạng chữ.",
          style: AppTextStyles.body2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text("HỦY", style: AppTextStyles.button),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.onError,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text("XÓA", style: AppTextStyles.button),
          ),
        ],
      ),
    );

    if (ok == true) {
      final firestoreId = s['firestoreId'] as String?;
      final id = s['id'] as int;
      
      // Sử dụng SupplierService để xóa cả local và cloud (soft delete)
      final success = await supplierService.deleteSupplier(id, firestoreId: firestoreId);
      
      if (success) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.onSuccess, size: 20),
                const SizedBox(width: 8),
                Text('ĐÃ XÓA NHÀ CUNG CẤP', style: AppTextStyles.body2.copyWith(color: AppColors.onSuccess)),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            duration: const Duration(seconds: 3),
          ),
        );
        _refresh();
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Lỗi: Không thể xóa nhà cung cấp', style: AppTextStyles.body2.copyWith(color: AppColors.onError)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAddSupplier() {
    final nameC = TextEditingController();
    final contactC = TextEditingController();
    final phoneC = TextEditingController();
    final addressC = TextEditingController();
    final itemsC = TextEditingController();
    final emailC = TextEditingController();
    final noteC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.business, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text("THÊM NHÀ CUNG CẤP", style: AppTextStyles.headline5.copyWith(color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 24),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInputField(nameC, "Tên nhà cung cấp", Icons.business, true, "VD: Kho Hà Nội"),
                      const SizedBox(height: 16),
                      _buildInputField(contactC, "Người liên hệ", Icons.person, false, "Tên người bán hàng"),
                      const SizedBox(height: 16),
                      _buildInputField(phoneC, "Số điện thoại", Icons.phone, false, "Số điện thoại liên hệ", TextInputType.phone),
                      const SizedBox(height: 16),
                      _buildInputField(emailC, "Email", Icons.email, false, "Địa chỉ email (tùy chọn)"),
                      const SizedBox(height: 16),
                      _buildInputField(addressC, "Địa chỉ", Icons.location_on, false, "Địa chỉ kho hàng"),
                      const SizedBox(height: 16),
                      _buildInputField(itemsC, "Mặt hàng cung cấp", Icons.inventory, false, "Các loại sản phẩm chính"),
                      const SizedBox(height: 16),
                      _buildInputField(noteC, "Ghi chú", Icons.note, false, "Thông tin bổ sung (tùy chọn)"),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text("HỦY", style: AppTextStyles.button.copyWith(color: AppColors.onSurface.withOpacity(0.7))),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (nameC.text.trim().isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text('Vui lòng nhập tên nhà cung cấp', style: AppTextStyles.body2.copyWith(color: AppColors.onError)),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        final navigator = Navigator.of(ctx);
                        await db.insertSupplier({
                          'name': nameC.text.trim().toUpperCase(),
                          'contactPerson': contactC.text.trim().toUpperCase(),
                          'phone': phoneC.text.trim(),
                          'email': emailC.text.trim(),
                          'address': addressC.text.trim().toUpperCase(),
                          'items': itemsC.text.trim().toUpperCase(),
                          'note': noteC.text.trim(),
                          'active': 1,
                          'createdAt': DateTime.now().millisecondsSinceEpoch,
                          'updatedAt': DateTime.now().millisecondsSinceEpoch,
                        });
                        navigator.pop();
                        _refresh();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: AppColors.onSuccess, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Đã thêm nhà cung cấp thành công', style: AppTextStyles.body2.copyWith(color: AppColors.onSuccess)),
                                ],
                              ),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 2,
                      ),
                      child: Text("LƯU", style: AppTextStyles.button),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField(TextEditingController controller, String label, IconData icon, bool caps, [String? hint, TextInputType? keyboardType]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.w600, color: AppColors.onSurface)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
          style: AppTextStyles.body1,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
            prefixIcon: Icon(icon, color: AppColors.primary, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
        title: Row(
          children: [
            const Icon(Icons.business_center, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Text("QUẢN LÝ NHÀ CUNG CẤP", style: AppTextStyles.headline6.copyWith(color: Colors.white)),
          ],
        ),
        automaticallyImplyLeading: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(80),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary.withOpacity(0.1), AppColors.primary.withOpacity(0.05)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary),
              decoration: InputDecoration(
                hintText: "Tìm kiếm nhà cung cấp...",
                hintStyle: AppTextStyles.body2.copyWith(color: AppColors.onPrimary.withOpacity(0.7)),
                prefixIcon: Icon(Icons.search, color: AppColors.onPrimary.withOpacity(0.7)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: AppColors.onPrimary.withOpacity(0.7)),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.onPrimary.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.onPrimary.withOpacity(0.3)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.onPrimary, width: 2),
                ),
                filled: true,
                fillColor: AppColors.onPrimary.withOpacity(0.1),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 16),
                Text("Đang tải danh sách...", style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.7))),
              ],
            ),
          )
        : _filteredSuppliers.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.primary,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredSuppliers.length,
                itemBuilder: (ctx, i) => _buildSupplierCard(_filteredSuppliers[i]),
              ),
            ),
      floatingActionButton: GradientFab.primary(
        onPressed: _showAddSupplier,
        icon: Icons.add_business,
        label: 'Thêm NCC',
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.business, size: 64, color: AppColors.primary.withOpacity(0.5)),
          ),
          const SizedBox(height: 24),
          Text(
            _searchQuery.isEmpty ? "Chưa có nhà cung cấp nào" : "Không tìm thấy nhà cung cấp",
            style: AppTextStyles.headline6.copyWith(color: AppColors.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? "Thêm nhà cung cấp đầu tiên để bắt đầu quản lý kho hàng"
                : "Thử tìm kiếm với từ khóa khác",
            style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
            textAlign: TextAlign.center,
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddSupplier,
              icon: const Icon(Icons.add),
              label: Text("THÊM NHÀ CUNG CẤP ĐẦU TIÊN", style: AppTextStyles.button),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSupplierCard(Map<String, dynamic> supplier) {
    final isActive = supplier['active'] == 1;
    final totalAmount = supplier['totalAmount'] ?? 0;
    final importCount = supplier['importCount'] ?? 0;
    final synced = supplier['firestoreId'] != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: isActive ? AppColors.primary.withOpacity(0.2) : AppColors.warning.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isActive ? AppColors.primary.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.business,
              color: isActive ? AppColors.primary : AppColors.warning,
              size: 24,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                supplier['name'] ?? 'N/A',
                style: AppTextStyles.headline6.copyWith(
                  color: AppColors.onSurface,
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.inventory, size: 16, color: AppColors.onSurface.withOpacity(0.6)),
                  const SizedBox(width: 4),
                  Text(
                    "$importCount lần nhập",
                    style: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.success.withOpacity(0.1) : AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isActive ? "HOẠT ĐỘNG" : "TẠM DỪNG",
                      style: AppTextStyles.caption.copyWith(
                        color: isActive ? AppColors.success : AppColors.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!synced)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.sync_problem, size: 12, color: AppColors.warning),
                          const SizedBox(width: 4),
                          Text('Chưa đồng bộ', style: AppTextStyles.caption.copyWith(color: AppColors.warning)),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
          trailing: Icon(
            Icons.expand_more,
            color: AppColors.onSurface.withOpacity(0.6),
          ),
          children: [
            const Divider(height: 32, thickness: 1),
            _buildInfoRow("Người liên hệ", supplier['contactPerson'], Icons.person),
            _buildInfoRow("Số điện thoại", supplier['phone'], Icons.phone),
            _buildInfoRow("Email", supplier['email'], Icons.email),
            _buildInfoRow("Địa chỉ", supplier['address'], Icons.location_on),
            _buildInfoRow("Mặt hàng", supplier['items'], Icons.inventory),
            if (supplier['note'] != null && supplier['note'].toString().isNotEmpty)
              _buildInfoRow("Ghi chú", supplier['note'], Icons.note),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet, color: AppColors.primary, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    "TỔNG GIÁ TRỊ NHẬP:",
                    style: AppTextStyles.body2.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    "${NumberFormat('#,###').format(totalAmount)} đ",
                    style: AppTextStyles.headline6.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FastStockInView(
                            preselectedSupplier: supplier['name'],
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.inventory, size: 20),
                    label: Text("NHẬP KHO", style: AppTextStyles.button),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: AppColors.onSuccess,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      shadowColor: AppColors.shadow,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showSupplierDetails(supplier),
                    icon: const Icon(Icons.history, size: 20),
                    label: Text("LỊCH SỬ", style: AppTextStyles.button),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Nút xóa nhà cung cấp - yêu cầu xác thực mật khẩu
                IconButton(
                  onPressed: () => _confirmDeleteSupplier(supplier),
                  icon: const Icon(Icons.delete_outline, size: 22),
                  tooltip: 'Xóa nhà cung cấp',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.error.withOpacity(0.1),
                    foregroundColor: AppColors.error,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value, IconData icon) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.onSurface.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppTextStyles.body2.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSupplierDetails(Map<String, dynamic> supplier) {
    showDialog(
      context: context,
      builder: (ctx) => SupplierDetailsDialog(supplier: supplier),
    );
  }

  Future<String?> _showPasswordDialog() async {
    String password = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.lock, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),
            Text('XÁC NHẬN XÓA', style: AppTextStyles.headline6.copyWith(color: AppColors.primary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chỉ chủ shop/quản lý được phép xóa nhà cung cấp.\nNhập mật khẩu tài khoản để xác nhận:',
              style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.7)),
            ),
            const SizedBox(height: 16),
            TextField(
              obscureText: true,
              onChanged: (value) => password = value,
              style: AppTextStyles.body1,
              decoration: InputDecoration(
                hintText: 'Mật khẩu',
                hintStyle: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
                prefixIcon: const Icon(Icons.password, color: AppColors.primary, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.outline),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.onSurface.withOpacity(0.7),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            child: Text('HỦY', style: AppTextStyles.button),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, password),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('XÁC NHẬN', style: AppTextStyles.button),
          ),
        ],
      ),
    );
  }
}
