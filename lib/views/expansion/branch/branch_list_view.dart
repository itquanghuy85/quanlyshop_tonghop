import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../expansion/safe_mode/expansion_feature_flags.dart';
import '../../../expansion/safe_mode/branch_models.dart';
import '../../../expansion/safe_mode/branch_service.dart';
import 'branch_switch_view.dart';

/// Màn quản lý danh sách chi nhánh.
/// Chỉ hiển thị khi enableMultiBranch = true.
class BranchListView extends StatefulWidget {
  final String shopId;
  final ExpansionFeatureFlags flags;

  const BranchListView({
    super.key,
    required this.shopId,
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
  });

  @override
  State<BranchListView> createState() => _BranchListViewState();
}

class _BranchListViewState extends State<BranchListView> {
  late final BranchService _service;
  List<Branch> _branches = [];
  bool _loading = true;
  final _dateFmt = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _service = BranchService(flags: widget.flags);
    _load();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (!widget.flags.enableMultiBranch) {
      setState(() => _loading = false);
      return;
    }
    try {
      final list = await _service.getBranches(widget.shopId);
      if (mounted) setState(() { _branches = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBranch() async {
    final nameCtrl = TextEditingController();
    final addressCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Thêm chi nhánh'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Tên chi nhánh *'),
              autofocus: true,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: addressCtrl,
              decoration:
                  const InputDecoration(labelText: 'Địa chỉ (tuỳ chọn)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Huỷ')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Thêm')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    try {
      await _service.createBranch(
        shopId: widget.shopId,
        name: name,
        address: addressCtrl.text.trim().isEmpty ? null : addressCtrl.text.trim(),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deactivate(Branch b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Vô hiệu hoá chi nhánh'),
        content: Text('Bạn có chắc muốn vô hiệu hoá "${b.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Huỷ')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Vô hiệu hoá',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _service.deactivateBranch(b.id!);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quản lý chi nhánh'),
        actions: [
          if (widget.flags.enableMultiBranch)
            IconButton(
              icon: const Icon(Icons.add_business_outlined),
              tooltip: 'Thêm chi nhánh',
              onPressed: _addBranch,
            ),
        ],
      ),
      body: !widget.flags.enableMultiBranch
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 48, color: Colors.orange),
                  SizedBox(height: 12),
                  Text('Module Multi-Branch chưa được bật.',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _branches.isEmpty
                  ? _buildEmpty()
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _branches.length,
                        itemBuilder: (_, i) => _buildCard(_branches[i]),
                      ),
                    ),
      floatingActionButton: widget.flags.enableMultiBranch
          ? FloatingActionButton.extended(
              onPressed: _addBranch,
              icon: const Icon(Icons.add),
              label: const Text('Thêm chi nhánh'),
            )
          : null,
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.business_outlined, size: 60, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          const Text('Chưa có chi nhánh nào.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _addBranch,
            icon: const Icon(Icons.add),
            label: const Text('Thêm chi nhánh đầu tiên'),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Branch b) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade50,
          child: const Icon(Icons.business_outlined, color: Colors.blue),
        ),
        title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (b.address != null && b.address!.isNotEmpty)
              Text(b.address!, style: const TextStyle(fontSize: 12)),
            Text('Tạo: ${_dateFmt.format(b.createdAt)}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'switch') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BranchSwitchView(
                    shopId: widget.shopId,
                    flags: widget.flags,
                  ),
                ),
              ).then((_) => _load());
            } else if (v == 'deactivate') {
              _deactivate(b);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'switch', child: Text('Chuyển chi nhánh')),
            const PopupMenuItem(
              value: 'deactivate',
              child: Text('Vô hiệu hoá', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
        isThreeLine: b.address != null && b.address!.isNotEmpty,
      ),
    );
  }
}
