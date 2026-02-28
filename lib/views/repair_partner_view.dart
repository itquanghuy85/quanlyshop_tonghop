import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/repair_partner_model.dart';
import '../services/user_service.dart';
import '../services/event_bus.dart';
import '../services/repair_partner_service.dart';
import '../widgets/gradient_fab.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'repair_partner_detail_view.dart';

class RepairPartnerView extends StatefulWidget {
  const RepairPartnerView({super.key});

  @override
  State<RepairPartnerView> createState() => _RepairPartnerViewState();
}

class _RepairPartnerViewState extends State<RepairPartnerView> {
  StreamSubscription<String>? _subscription;
  final db = DBHelper();
  final partnerService = RepairPartnerService();
  List<RepairPartner> _partners = [];
  Map<int, Map<String, dynamic>> _partnerStats = {};
  bool _isLoading = true;
  bool _isAdmin = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadRole();
    _refresh();
    _subscription = EventBus().on('repair_partners_changed', _onPartnersChanged);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onPartnersChanged(dynamic data) {
    _refresh();
  }

  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() {
      _isAdmin = perms['allowViewRepairs'] ?? false;
    });
  }

  Future<void> _refresh() async {
    setState(() => _isLoading = true);
    final partners = await partnerService.getRepairPartners();
    
    // Load stats for each partner
    final Map<int, Map<String, dynamic>> stats = {};
    for (final partner in partners) {
      if (partner.id != null) {
        final s = await partnerService.getPartnerRepairStats(partner.id!, partnerFirestoreId: partner.firestoreId);
        if (s != null) {
          stats[partner.id!] = s;
        }
      }
    }
    
    setState(() {
      _partners = partners;
      _partnerStats = stats;
      _isLoading = false;
    });
  }

  List<RepairPartner> get _filteredPartners {
    if (_searchQuery.isEmpty) return _partners;
    return _partners.where((partner) {
      final name = partner.name.toLowerCase();
      final phone = partner.phone?.toLowerCase() ?? '';
      final note = partner.note?.toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || phone.contains(query) || note.contains(query);
    }).toList();
  }

  Future<void> _confirmDeletePartner(RepairPartner partner) async {
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
            Text("XÓA ĐỐI TÁC", style: AppTextStyles.headline6.copyWith(color: AppColors.error)),
          ],
        ),
        content: Text(
          "Bạn chắc chắn muốn xóa đối tác \"${partner.name}\" khỏi danh sách? Các đơn sửa cũ vẫn giữ nguyên thông tin đối tác dạng chữ.",
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
      final firestoreId = partner.firestoreId;
      final id = partner.id;
      
      if (id == null) return;
      
      final success = await partnerService.deleteRepairPartner(id, firestoreId: firestoreId);
      
      if (success) {
        messenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: AppColors.onSuccess, size: 20),
                const SizedBox(width: 8),
                Text('ĐÃ XÓA ĐỐI TÁC', style: AppTextStyles.body2.copyWith(color: AppColors.onSuccess)),
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
            content: Text('Lỗi: Không thể xóa đối tác', style: AppTextStyles.body2.copyWith(color: AppColors.onError)),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showAddPartner() {
    final nameC = TextEditingController();
    final phoneC = TextEditingController();
    final noteC = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(12),
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
                    child: const Icon(Icons.handshake, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text("THÊM ĐỐI TÁC SỬA CHỮA", style: AppTextStyles.headline5.copyWith(color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 24),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInputField(nameC, "Tên đối tác", Icons.business, true, "VD: TIỆM SỬA ABC"),
                      const SizedBox(height: 16),
                      _buildInputField(phoneC, "Số điện thoại", Icons.phone, false, "Số điện thoại liên hệ", TextInputType.phone),
                      const SizedBox(height: 16),
                      _buildInputField(noteC, "Ghi chú", Icons.note, false, "Chuyên sửa màn hình, main... (tùy chọn)"),
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
                              content: Text('Vui lòng nhập tên đối tác', style: AppTextStyles.body2.copyWith(color: AppColors.onError)),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        final navigator = Navigator.of(ctx);
                        final shopId = await UserService.getCurrentShopId() ?? '';
                        final partner = RepairPartner(
                          name: nameC.text.trim().toUpperCase(),
                          phone: phoneC.text.trim(),
                          note: noteC.text.trim(),
                          active: true,
                          shopId: shopId,
                        );
                        await partnerService.addRepairPartner(partner);
                        navigator.pop();
                        _refresh();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: AppColors.onSuccess, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Đã thêm đối tác thành công', style: AppTextStyles.body2.copyWith(color: AppColors.onSuccess)),
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

  void _showEditPartner(RepairPartner partner) {
    final nameC = TextEditingController(text: partner.name);
    final phoneC = TextEditingController(text: partner.phone ?? '');
    final noteC = TextEditingController(text: partner.note ?? '');

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.edit, color: AppColors.warning, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Text("SỬA THÔNG TIN ĐỐI TÁC", style: AppTextStyles.headline5.copyWith(color: AppColors.warning)),
                ],
              ),
              const SizedBox(height: 24),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildInputField(nameC, "Tên đối tác", Icons.business, true, "VD: TIỆM SỬA ABC"),
                      const SizedBox(height: 16),
                      _buildInputField(phoneC, "Số điện thoại", Icons.phone, false, "Số điện thoại liên hệ", TextInputType.phone),
                      const SizedBox(height: 16),
                      _buildInputField(noteC, "Ghi chú", Icons.note, false, "Chuyên sửa màn hình, main... (tùy chọn)"),
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
                              content: Text('Vui lòng nhập tên đối tác', style: AppTextStyles.body2.copyWith(color: AppColors.onError)),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }
                        final navigator = Navigator.of(ctx);
                        final updated = partner.copyWith(
                          name: nameC.text.trim().toUpperCase(),
                          phone: phoneC.text.trim(),
                          note: noteC.text.trim(),
                          updatedAt: DateTime.now().millisecondsSinceEpoch,
                        );
                        await partnerService.updateRepairPartner(updated);
                        navigator.pop();
                        _refresh();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                children: [
                                  const Icon(Icons.check_circle, color: AppColors.onSuccess, size: 20),
                                  const SizedBox(width: 8),
                                  Text('Đã cập nhật đối tác', style: AppTextStyles.body2.copyWith(color: AppColors.onSuccess)),
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
                        backgroundColor: AppColors.warning,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 2,
                      ),
                      child: Text("CẬP NHẬT", style: AppTextStyles.button),
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
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
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
            const Icon(Icons.handshake, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Text("ĐỐI TÁC SỬA CHỮA", style: AppTextStyles.headline6.copyWith(color: Colors.white)),
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
                hintText: "Tìm kiếm đối tác...",
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
        : _filteredPartners.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
              onRefresh: _refresh,
              color: AppColors.primary,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _filteredPartners.length,
                itemBuilder: (ctx, i) => _buildPartnerCard(_filteredPartners[i]),
              ),
            ),
      floatingActionButton: GradientFab.primary(
        onPressed: _showAddPartner,
        icon: Icons.add,
        label: 'Thêm ĐT',
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.handshake, size: 64, color: AppColors.primary.withOpacity(0.5)),
          ),
          const SizedBox(height: 24),
          Text(
            _searchQuery.isEmpty ? "Chưa có đối tác nào" : "Không tìm thấy đối tác",
            style: AppTextStyles.headline6.copyWith(color: AppColors.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isEmpty
                ? "Thêm đối tác sửa chữa để quản lý công nợ & lịch sử gửi sửa"
                : "Thử tìm kiếm với từ khóa khác",
            style: AppTextStyles.body2.copyWith(color: AppColors.onSurface.withOpacity(0.5)),
            textAlign: TextAlign.center,
          ),
          if (_searchQuery.isEmpty) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _showAddPartner,
              icon: const Icon(Icons.add),
              label: Text("THÊM ĐỐI TÁC ĐẦU TIÊN", style: AppTextStyles.button),
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

  Widget _buildPartnerCard(RepairPartner partner) {
    final isActive = partner.active;
    final stats = _partnerStats[partner.id];
    final totalOrders = stats?['totalOrders'] ?? stats?['totalRepairs'] ?? 0;
    final totalCost = stats?['totalCost'] ?? 0;
    final totalPaid = stats?['totalPaid'] ?? 0;
    final remainDebt = totalCost - totalPaid;
    final synced = partner.firestoreId != null;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
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
              Icons.handshake,
              color: isActive ? AppColors.primary : AppColors.warning,
              size: 24,
            ),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                partner.name,
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
                  Icon(Icons.build, size: 16, color: AppColors.onSurface.withOpacity(0.6)),
                  const SizedBox(width: 4),
                  Text(
                    "$totalOrders đơn gửi sửa",
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
            _buildInfoRow("Số điện thoại", partner.phone, Icons.phone),
            if (partner.note != null && partner.note!.isNotEmpty)
              _buildInfoRow("Ghi chú", partner.note, Icons.note),
            const SizedBox(height: 20),
            
            // Stats summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long, color: AppColors.primary, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        "TỔNG CHI PHÍ GỬI SỬA:",
                        style: AppTextStyles.body2.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        "${NumberFormat('#,###').format(totalCost)} đ",
                        style: AppTextStyles.headline6.copyWith(
                          color: AppColors.error,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _statChip("Đã trả", totalPaid, AppColors.success),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _statChip("Còn nợ", remainDebt, remainDebt > 0 ? AppColors.error : AppColors.success),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showPartnerDetails(partner),
                    icon: const Icon(Icons.history, size: 20),
                    label: Text("CHI TIẾT", style: AppTextStyles.button),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary, width: 1.5),
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Nút sửa
                IconButton(
                  onPressed: () => _showEditPartner(partner),
                  icon: const Icon(Icons.edit_outlined, size: 22),
                  tooltip: 'Sửa thông tin',
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.warning.withOpacity(0.1),
                    foregroundColor: AppColors.warning,
                    padding: const EdgeInsets.all(12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(width: 8),
                // Nút xóa
                IconButton(
                  onPressed: () => _confirmDeletePartner(partner),
                  icon: const Icon(Icons.delete_outline, size: 22),
                  tooltip: 'Xóa đối tác',
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

  Widget _statChip(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: AppTextStyles.caption.copyWith(color: color)),
          const SizedBox(height: 2),
          Text("${NumberFormat('#,###').format(value)} đ", style: AppTextStyles.body2.copyWith(color: color, fontWeight: FontWeight.bold)),
        ],
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

  void _showPartnerDetails(RepairPartner partner) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RepairPartnerDetailView(partner: partner),
      ),
    ).then((_) => _refresh());
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
              'Chỉ chủ shop/quản lý được phép xóa đối tác.\nNhập mật khẩu tài khoản để xác nhận:',
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
