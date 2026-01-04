import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../services/firestore_service.dart';
import 'repair_detail_view.dart';
import 'create_repair_order_view.dart';
import 'global_search_view.dart';

class OrderListView extends StatefulWidget {
  final int? initialStatus;
  final bool todayOnly;
  final List<int>? statusFilter;
  final String role; 
  const OrderListView({super.key, this.initialStatus, this.todayOnly = false, this.statusFilter, this.role = 'user'});

  @override
  State<OrderListView> createState() => OrderListViewState();
}

class OrderListViewState extends State<OrderListView> {
  final db = DBHelper();
  final ScrollController _scrollController = ScrollController();
  
  List<Repair> _displayedRepairs = [];
  bool _isLoading = true;
  String _currentSearch = "";

  bool get canDelete => widget.role == 'admin' || widget.role == 'owner';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    final all = await db.getAllRepairs();
    if (!mounted) return;
    setState(() {
      _displayedRepairs = _applyFilters(all);
      _isLoading = false;
    });
  }

  void _onSearch(String val) async {
    setState(() => _currentSearch = val);
    final all = await db.getAllRepairs();
    setState(() {
      final filtered = _applyFilters(all);
      if (val.isEmpty) {
        _displayedRepairs = filtered;
      } else {
        _displayedRepairs = filtered.where((r) => 
          r.customerName.toLowerCase().contains(val.toLowerCase()) || 
          r.phone.contains(val) || 
          r.model.toLowerCase().contains(val.toLowerCase())
        ).toList();
      }
    });
  }

  List<Repair> _applyFilters(List<Repair> list) {
    return list.where((r) {
      if (widget.statusFilter != null && !widget.statusFilter!.contains(r.status)) return false;
      if (widget.todayOnly) {
        final d = DateTime.fromMillisecondsSinceEpoch(r.createdAt);
        final now = DateTime.now();
        if (!(d.year == now.year && d.month == now.month && d.day == now.day)) return false;
      }
      return true;
    }).toList();
  }

  void _confirmDelete(Repair r) {
    if (!canDelete) return;
    final passCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("XÁC NHẬN XÓA ĐƠN"),
        content: TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(hintText: "Nhập mật khẩu quản lý")),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("HỦY")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final user = FirebaseAuth.instance.currentUser;
              if (user == null || user.email == null) return;
              try {
                final navigator = Navigator.of(ctx);
                final cred = EmailAuthProvider.credential(email: user.email!, password: passCtrl.text);
                await user.reauthenticateWithCredential(cred);
                await db.deleteRepairByFirestoreId(r.firestoreId ?? "");
                if (r.firestoreId != null) await FirestoreService.deleteRepair(r.firestoreId!);
                navigator.pop();
                _loadInitialData();
                messenger.showSnackBar(const SnackBar(content: Text('ĐÃ XÓA THÀNH CÔNG')));
              } catch (_) {
                messenger.showSnackBar(const SnackBar(content: Text('Mật khẩu sai')));
              }
            },
            child: const Text("XÓA", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text("DANH SÁCH MÁY SỬA", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF2962FF), 
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GlobalSearchView(role: widget.role))),
            icon: const Icon(Icons.search, color: Colors.white),
            tooltip: 'Tìm kiếm toàn app',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: "Tìm khách, model, SĐT...",
                prefixIcon: const Icon(Icons.search),
                filled: true, fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadInitialData,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _displayedRepairs.length,
                    itemBuilder: (ctx, i) => _buildRepairCard(_displayedRepairs[i]),
                  ),
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => CreateRepairOrderView(role: widget.role)));
          if (res == true) _loadInitialData();
        },
        label: const Text("NHẬN MÁY MỚI"),
        icon: const Icon(Icons.add_a_photo_rounded),
        backgroundColor: const Color(0xFF2962FF),
      ),
    );
  }

  Widget _buildRepairCard(Repair r) {
    final bool isDone = r.status >= 3;
    final List<String> images = r.receiveImages;
    final String firstImage = images.isNotEmpty ? images.first : "";

    return Dismissible(
      key: Key(r.firestoreId ?? r.createdAt.toString()),
      direction: canDelete ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(20)),
        child: const Icon(Icons.delete_forever, color: Colors.white, size: 30),
      ),
      confirmDismiss: (_) async { _confirmDelete(r); return false; },
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: InkWell(
          onTap: () async {
            final res = await Navigator.push(context, MaterialPageRoute(builder: (_) => RepairDetailView(repair: r)));
            if (res == true) _loadInitialData();
          },
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. HÌNH ẢNH NHẬN MÁY
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                    image: firstImage.isNotEmpty 
                      ? DecorationImage(image: firstImage.startsWith('http') ? NetworkImage(firstImage) : FileImage(File(firstImage)) as ImageProvider, fit: BoxFit.cover)
                      : null,
                  ),
                  child: firstImage.isEmpty ? const Icon(Icons.image_not_supported_outlined, color: Colors.grey) : null,
                ),
                if (images.length > 1) 
                  Positioned(bottom: 0, right: 0, child: Container(padding: const EdgeInsets.all(2), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)), child: Text("+${images.length - 1}", style: const TextStyle(color: Colors.white, fontSize: 10)))),

                const SizedBox(width: 15),

                // 2. THÔNG TIN CHI TIẾT
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.model, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF2962FF))),
                      Text("Khách: ${r.customerName}", style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 4),
                      Text("Lỗi: ${r.issue.split('|').first}", style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text("Ghi chú: ${r.accessories}", style: const TextStyle(color: Colors.blueGrey, fontSize: 11, fontStyle: FontStyle.italic), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),

                // 3. TRẠNG THÁI & THỜI GIAN
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(DateFormat('dd/MM').format(DateTime.fromMillisecondsSinceEpoch(r.createdAt)), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(color: isDone ? Colors.green.shade100 : Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Text(isDone ? "XONG" : "ĐANG SỬA", style: TextStyle(color: isDone ? Colors.green.shade700 : Colors.orange.shade700, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
