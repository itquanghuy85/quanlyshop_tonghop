import 'dart:async';
import 'package:flutter/material.dart';
import '../models/repair_partner_model.dart';
import '../services/repair_partner_service.dart';
import '../services/notification_service.dart';
import '../widgets/validated_text_field.dart';
import '../services/user_service.dart';

class RepairPartnerListView extends StatefulWidget {
  const RepairPartnerListView({super.key});

  @override
  State<RepairPartnerListView> createState() => _RepairPartnerListViewState();
}

class _RepairPartnerListViewState extends State<RepairPartnerListView> {
  final RepairPartnerService _service = RepairPartnerService();
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<RepairPartner> _partners = [];
  bool _isLoading = false;
  String _searchQuery = '';

  List<RepairPartner> get _filteredPartners {
    if (_searchQuery.isEmpty) {
      return _partners;
    }
    return _partners.where((partner) =>
      partner.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
      (partner.phone?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
      (partner.note?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
    ).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadPartners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPartners() async {
    setState(() => _isLoading = true);
    try {
      final partners = await _service.getRepairPartners();
      setState(() => _partners = partners);
    } catch (e) {
      NotificationService.showSnackBar('Không thể tải danh sách đối tác: $e', color: Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addPartner(RepairPartner partner) async {
    try {
      final result = await _service.addRepairPartner(partner);
      if (result != null) {
        setState(() => _partners.add(result));
        NotificationService.showSnackBar('Đã thêm đối tác mới');
      } else {
        NotificationService.showSnackBar('Không thể thêm đối tác', color: Colors.red);
      }
    } catch (e) {
      NotificationService.showSnackBar('Không thể thêm đối tác: $e', color: Colors.red);
    }
  }

  Future<void> _updatePartner(RepairPartner partner) async {
    try {
      final success = await _service.updateRepairPartner(partner);
      if (success) {
        final index = _partners.indexWhere((p) => p.id == partner.id);
        if (index != -1) {
          setState(() => _partners[index] = partner);
        }
        NotificationService.showSnackBar('Đã cập nhật đối tác');
      } else {
        NotificationService.showSnackBar('Không thể cập nhật đối tác', color: Colors.red);
      }
    } catch (e) {
      NotificationService.showSnackBar('Không thể cập nhật đối tác: $e', color: Colors.red);
    }
  }

  Future<void> _deletePartner(int partnerId) async {
    try {
      final success = await _service.deleteRepairPartner(partnerId);
      if (success) {
        setState(() => _partners.removeWhere((p) => p.id == partnerId));
        NotificationService.showSnackBar('Đã xóa đối tác');
      } else {
        NotificationService.showSnackBar('Không thể xóa đối tác', color: Colors.red);
      }
    } catch (e) {
      NotificationService.showSnackBar('Không thể xóa đối tác: $e', color: Colors.red);
    }
  }

  Future<void> _togglePartnerStatus(RepairPartner partner) async {
    final updatedPartner = partner.copyWith(active: !partner.active);
    await _updatePartner(updatedPartner);
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
        title: const Text("ĐỐI TÁC SỬA CHỮA", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddPartnerDialog(context),
          ),
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Column(
          children: [
            // Search bar
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: ValidatedTextField(
                controller: _searchController,
                label: 'Tìm kiếm đối tác...',
                icon: Icons.search,
                onChanged: (value) {
                  _searchDebounce?.cancel();
                  _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                    setState(() => _searchQuery = value);
                  });
                },
              ),
            ),

            // Partner list
            Expanded(
              child: _filteredPartners.isEmpty
                ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.business, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text(
                        'Chưa có đối tác nào',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Nhấn + để thêm đối tác mới',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ],
                  ),
                )
                : ListView.builder(
                  itemCount: _filteredPartners.length,
                  itemBuilder: (context, index) {
                    final partner = _filteredPartners[index];
                    return _buildPartnerCard(context, partner);
                  },
                ),
            ),
          ],
        ),
    );
  }

  Widget _buildPartnerCard(BuildContext context, RepairPartner partner) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: partner.active ? Colors.green : Colors.grey,
          child: const Icon(
            Icons.business,
            color: Colors.white,
          ),
        ),
        title: Text(
          partner.name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: partner.active ? Colors.black : Colors.grey,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (partner.phone?.isNotEmpty ?? false)
              Text('📞 ${partner.phone}'),
            if (partner.note?.isNotEmpty ?? false)
              Text('📝 ${partner.note}', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              partner.active ? 'Đang hoạt động' : 'Tạm ngừng',
              style: TextStyle(
                color: partner.active ? Colors.green : Colors.red,
                fontSize: 12,
              ),
            ),
            if (partner.firestoreId == null)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Icon(Icons.sync_problem, size: 14, color: Colors.orange),
                    SizedBox(width: 4),
                    Text('Chưa đồng bộ', style: TextStyle(fontSize: 12, color: Colors.orange)),
                  ],
                ),
              ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (value) => _handleMenuAction(context, value, partner),
          itemBuilder: (context) => [
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
            PopupMenuItem(
              value: 'toggle',
              child: Row(
                children: [
                  Icon(
                    partner.active ? Icons.pause : Icons.play_arrow,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(partner.active ? 'Tạm ngừng' : 'Kích hoạt'),
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
        onTap: () => _showPartnerDetails(context, partner),
      ),
    );
  }

  void _handleMenuAction(BuildContext context, String action, RepairPartner partner) {
    switch (action) {
      case 'edit':
        _showEditPartnerDialog(context, partner);
        break;
      case 'toggle':
        _togglePartnerStatus(partner);
        break;
      case 'delete':
        _showDeleteConfirmation(context, partner);
        break;
    }
  }

  void _showAddPartnerDialog(BuildContext context) {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final noteController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm Đối Tác Mới'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValidatedTextField(
                controller: nameController,
                label: 'Tên đối tác *',
                hint: 'Nhập tên đối tác',
                required: true,
              ),
              const SizedBox(height: 16),
              ValidatedTextField(
                controller: phoneController,
                label: 'Số điện thoại',
                hint: 'Nhập số điện thoại',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              ValidatedTextField(
                controller: noteController,
                label: 'Ghi chú',
                hint: 'Nhập ghi chú về đối tác',
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                NotificationService.showSnackBar('Vui lòng nhập tên đối tác', color: Colors.red);
                return;
              }

              if (phoneController.text.trim().isNotEmpty) {
                try {
                  UserService.validatePhone(phoneController.text.trim());
                } catch (e) {
                  NotificationService.showSnackBar('Số điện thoại không hợp lệ: $e', color: Colors.red);
                  return;
                }
              }

              final partner = RepairPartner(
                name: nameController.text.trim(),
                phone: phoneController.text.trim(),
                note: noteController.text.trim(),
                active: true,
                shopId: '', // Will be set in service
              );

              await _addPartner(partner);
              Navigator.of(context).pop();
            },
            child: const Text('Thêm'),
          ),
        ],
      ),
    );
  }

  void _showEditPartnerDialog(BuildContext context, RepairPartner partner) {
    final nameController = TextEditingController(text: partner.name);
    final phoneController = TextEditingController(text: partner.phone ?? '');
    final noteController = TextEditingController(text: partner.note ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Chỉnh Sửa Đối Tác'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValidatedTextField(
                controller: nameController,
                label: 'Tên đối tác *',
                hint: 'Nhập tên đối tác',
                required: true,
              ),
              const SizedBox(height: 16),
              ValidatedTextField(
                controller: phoneController,
                label: 'Số điện thoại',
                hint: 'Nhập số điện thoại',
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              ValidatedTextField(
                controller: noteController,
                label: 'Ghi chú',
                hint: 'Nhập ghi chú về đối tác',
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                NotificationService.showSnackBar('Vui lòng nhập tên đối tác', color: Colors.red);
                return;
              }

              if (phoneController.text.trim().isNotEmpty) {
                try {
                  UserService.validatePhone(phoneController.text.trim());
                } catch (e) {
                  NotificationService.showSnackBar('Số điện thoại không hợp lệ: $e', color: Colors.red);
                  return;
                }
              }

              final updatedPartner = partner.copyWith(
                name: nameController.text.trim(),
                phone: phoneController.text.trim(),
                note: noteController.text.trim(),
              );

              await _updatePartner(updatedPartner);
              Navigator.of(context).pop();
            },
            child: const Text('Cập nhật'),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, RepairPartner partner) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác Nhận Xóa'),
        content: Text('Bạn có chắc muốn xóa đối tác "${partner.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _deletePartner(partner.id!);
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showPartnerDetails(BuildContext context, RepairPartner partner) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(partner.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (partner.phone?.isNotEmpty ?? false) Text('SĐT: ${partner.phone}'),
            if (partner.note?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              const Text('Ghi chú:'),
              Text(partner.note!),
            ],
            const SizedBox(height: 12),
            Text(
              partner.active ? 'Trạng thái: Đang hoạt động' : 'Trạng thái: Tạm ngừng',
              style: TextStyle(color: partner.active ? Colors.green : Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showEditPartnerDialog(context, partner);
            },
            child: const Text('Chỉnh sửa'),
          ),
        ],
      ),
    );
  }
}