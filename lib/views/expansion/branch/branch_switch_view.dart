import 'package:flutter/material.dart';

import '../../../expansion/safe_mode/expansion_feature_flags.dart';
import '../../../expansion/safe_mode/branch_models.dart';
import '../../../expansion/safe_mode/branch_service.dart';

/// Màn chọn / chuyển chi nhánh.
/// Trả về [Branch] đã chọn khi pop, hoặc null nếu user huỷ.
class BranchSwitchView extends StatefulWidget {
  final String shopId;
  final String? currentUserId;
  final ExpansionFeatureFlags flags;

  const BranchSwitchView({
    super.key,
    required this.shopId,
    this.currentUserId,
    this.flags = const ExpansionFeatureFlags.safeDefaults(),
  });

  @override
  State<BranchSwitchView> createState() => _BranchSwitchViewState();
}

class _BranchSwitchViewState extends State<BranchSwitchView> {
  late final BranchService _service;
  List<Branch> _branches = [];
  int? _selectedId;
  bool _loading = true;
  bool _saving = false;

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
      // Pre-select chi nhánh của user nếu có
      int? current;
      if (widget.currentUserId != null) {
        final b = await _service.getBranchForUser(widget.currentUserId!);
        current = b?.id;
      }
      // Fallback: active branch trong service
      current ??= _service.activeContext?.branchId;

      if (mounted) {
        setState(() {
          _branches = list;
          _selectedId = current ?? (list.isNotEmpty ? list.first.id : null);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirm() async {
    if (_selectedId == null) return;
    setState(() => _saving = true);

    try {
      // Cập nhật active context trong service
      await _service.setActiveBranch(_selectedId!);

      // Gán user nếu có currentUserId
      if (widget.currentUserId != null) {
        await _service.switchUserBranch(
          userId: widget.currentUserId!,
          newBranchId: _selectedId!,
        );
      }

      final chosen = _branches.firstWhere((b) => b.id == _selectedId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã chuyển sang chi nhánh "${chosen.name}"'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, chosen);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chọn chi nhánh')),
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
                  ? const Center(child: Text('Chưa có chi nhánh nào.'))
                  : Column(
                      children: [
                        _buildHeader(),
                        Expanded(child: _buildList()),
                        _buildConfirmButton(),
                      ],
                    ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: Colors.blue.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Chọn chi nhánh làm việc',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            'Dữ liệu sẽ được lọc theo chi nhánh bạn chọn.',
            style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _branches.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final b = _branches[i];
        final isSelected = b.id == _selectedId;
        return ListTile(
          leading: CircleAvatar(
            backgroundColor:
                isSelected ? Colors.blue : Colors.grey.shade100,
            child: Icon(
              Icons.business_outlined,
              color: isSelected ? Colors.white : Colors.grey.shade400,
              size: 20,
            ),
          ),
          title: Text(
            b.name,
            style: TextStyle(
              fontWeight:
                  isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.blue.shade800 : null,
            ),
          ),
          subtitle: b.address != null && b.address!.isNotEmpty
              ? Text(b.address!,
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey))
              : null,
          trailing: Radio<int?>(
            value: b.id,
            groupValue: _selectedId,
            onChanged: (v) => setState(() => _selectedId = v),
            activeColor: Colors.blue,
          ),
          onTap: () => setState(() => _selectedId = b.id),
          selected: isSelected,
          selectedTileColor: Colors.blue.shade50,
        );
      },
    );
  }

  Widget _buildConfirmButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton.icon(
            onPressed: (_selectedId == null || _saving) ? null : _confirm,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check_circle_outline),
            label: const Text('Xác nhận', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
