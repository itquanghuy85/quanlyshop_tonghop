import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';

class AuditLogView extends StatefulWidget {
  const AuditLogView({super.key});
  @override
  State<AuditLogView> createState() => _AuditLogViewState();
}

class _AuditLogViewState extends State<AuditLogView> {
  final db = DBHelper();
  List<Map<String, dynamic>> _logs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final data = await db.getAuditLogs();
    if (!mounted) return;
    setState(() { _logs = data; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        title: const Text("NHẬT KÝ HỆ THỐNG", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        backgroundColor: const Color(0xFF2962FF), foregroundColor: Colors.white, elevation: 0,
        automaticallyImplyLeading: true,
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh, color: Colors.white))],
      ),
      body: _loading ? const Center(child: CircularProgressIndicator()) : _logs.isEmpty 
        ? _buildEmpty() 
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _logs.length,
            itemBuilder: (ctx, i) => _buildLogCard(_logs[i]),
          ),
    );
  }

  Widget _buildEmpty() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.history_toggle_off_rounded, size: 80, color: Colors.grey[300]),
      const SizedBox(height: 10),
      const Text("Chưa có ghi chép hoạt động nào", style: TextStyle(color: Colors.grey)),
    ]));
  }

  Widget _buildLogCard(Map<String, dynamic> log) {
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(log['createdAt']);
    final Color actionColor = _getActionColor(log['action']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 5)],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: actionColor.withAlpha(25), shape: BoxShape.circle),
          child: Icon(_getActionIcon(log['action']), color: actionColor, size: 20),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(log['userName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
            Text(DateFormat('HH:mm - dd/MM').format(date), style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(log['action'], style: TextStyle(color: actionColor, fontWeight: FontWeight.bold, fontSize: 11)),
              const SizedBox(height: 2),
              Text(log['description'] ?? "", style: const TextStyle(fontSize: 12, color: Colors.black87)),
            ],
          ),
        ),
      ),
    );
  }

  Color _getActionColor(String action) {
    if (action.contains("XÓA")) return Colors.red;
    if (action.contains("NHẬP") || action.contains("THÊM")) return Colors.green;
    if (action.contains("SỬA") || action.contains("CẬP NHẬT")) return Colors.orange;
    if (action.contains("BÁN")) return Colors.pink;
    return Colors.blue;
  }

  IconData _getActionIcon(String action) {
    if (action.contains("XÓA")) return Icons.delete_forever;
    if (action.contains("NHẬP")) return Icons.add_business;
    if (action.contains("BÁN")) return Icons.shopping_cart;
    if (action.contains("SỬA")) return Icons.edit_note;
    return Icons.info_outline;
  }
}
