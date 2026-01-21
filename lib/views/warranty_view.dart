import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../services/user_service.dart';
import 'repair_detail_view.dart';
import 'sale_detail_view.dart';

class WarrantyView extends StatefulWidget {
  const WarrantyView({super.key});
  @override
  State<WarrantyView> createState() => _WarrantyViewState();
}

class _WarrantyViewState extends State<WarrantyView> {
  final db = DBHelper();
  List<Map<String, dynamic>> _warrantyList = []; 
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadAllWarranty();
  }

  Future<void> _loadRole() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() { _isAdmin = perms['allowViewWarranty'] ?? false; });
  }

  Future<void> _loadAllWarranty() async {
    setState(() => _isLoading = true);
    final repairs = await db.getAllRepairs();
    final sales = await db.getAllSales();
    final now = DateTime.now();
    
    // DEBUG: Log total counts
    debugPrint("WARRANTY_DEBUG: Total repairs in local DB: ${repairs.length}");
    debugPrint("WARRANTY_DEBUG: Total sales in local DB: ${sales.length}");
    for (var r in repairs) {
      debugPrint("WARRANTY_DEBUG: Repair - id:${r.id}, firestoreId:${r.firestoreId}, warranty:${r.warranty}, status:${r.status}, deleted:${r.deleted}, customerName:${r.customerName}");
    }
    for (var s in sales) {
      debugPrint("WARRANTY_DEBUG: Sale - id:${s.id}, firestoreId:${s.firestoreId}, warranty:${s.warranty}, customerName:${s.customerName}");
    }
    
    List<Map<String, dynamic>> results = [];

    // 1. BẢO HÀNH MÁY SỬA
    for (var r in repairs) {
      if (r.deliveredAt != null && r.warranty.isNotEmpty && r.warranty != "KO BH") {
        int months = int.tryParse(r.warranty.split(' ').first) ?? 0;
        if (months > 0) {
          DateTime delDate = DateTime.fromMillisecondsSinceEpoch(r.deliveredAt!);
          DateTime expDate = DateTime(delDate.year, delDate.month + months, delDate.day);
          if (expDate.isAfter(now)) {
            results.add({
              'type': 'REPAIR',
              'customer': r.customerName,
              'model': r.model,
              'imei': r.imei ?? "N/A",
              'startDate': delDate,
              'expiry': expDate,
              'data': r,
            });
          }
        }
      }
    }

    // 2. BẢO HÀNH MÁY BÁN
    for (var s in sales) {
      if (s.warranty.isNotEmpty && s.warranty != "KO BH") {
        int months = int.tryParse(s.warranty.split(' ').first) ?? 12; // Mặc định 12th nếu lỗi parse
        DateTime saleDate = DateTime.fromMillisecondsSinceEpoch(s.soldAt);
        DateTime expDate = DateTime(saleDate.year, saleDate.month + months, saleDate.day);
        
        if (expDate.isAfter(now)) {
          results.add({
            'type': 'SALE',
            'customer': s.customerName,
            'model': s.productNames,
            'imei': s.productImeis,
            'startDate': saleDate,
            'expiry': expDate,
            'data': s,
          });
        }
      }
    }

    results.sort((a, b) => (a['expiry'] as DateTime).compareTo(b['expiry'] as DateTime));
    if (mounted) setState(() { _warrantyList = results; _isLoading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
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
        title: const Text("SIÊU TRUNG TÂM BẢO HÀNH", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
        elevation: 0, backgroundColor: Colors.transparent, foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
        actions: [IconButton(onPressed: _loadAllWarranty, icon: const Icon(Icons.refresh_rounded, color: Colors.white))],
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _warrantyList.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _warrantyList.length,
              itemBuilder: (ctx, i) => _buildWarrantyCard(_warrantyList[i]),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.verified_user_outlined, size: 100, color: Colors.blue.withAlpha(51)),
      const SizedBox(height: 15),
      const Text("KHÔNG CÓ MÁY NÀO TRONG HẠN BẢO HÀNH", style: TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold, fontSize: 13)),
      const Text("Mọi đơn hàng đã hết hạn hoặc chưa được giao.", style: TextStyle(color: Colors.grey, fontSize: 11)),
    ]));
  }

  Widget _buildWarrantyCard(Map<String, dynamic> item) {
    final bool isSale = item['type'] == 'SALE';
    final DateTime expDate = item['expiry'];
    final DateTime startDate = item['startDate'];
    final int totalDays = expDate.difference(startDate).inDays;
    final int daysLeft = expDate.difference(DateTime.now()).inDays;
    final double progress = (daysLeft / (totalDays > 0 ? totalDays : 1)).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(8), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: InkWell(
        onTap: () {
          if (isSale) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => SaleDetailView(sale: item['data'] as SaleOrder)));
          } else {
            Navigator.push(context, MaterialPageRoute(builder: (_) => RepairDetailView(repair: item['data'] as Repair)));
          }
        },
        borderRadius: BorderRadius.circular(22),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: (isSale ? Colors.pink : Colors.orange).withAlpha(25), borderRadius: BorderRadius.circular(15)),
                    child: Icon(isSale ? Icons.shopping_bag_rounded : Icons.handyman_rounded, color: isSale ? Colors.pink : Colors.orange, size: 26),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item['model'].toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF1A237E))),
                      const SizedBox(height: 4),
                      Row(children: [
                        const Icon(Icons.person, size: 12, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(item['customer'], style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                      ]),
                      const SizedBox(height: 2),
                      Text("IMEI: ${item['imei']}", style: const TextStyle(fontSize: 10, color: Colors.grey, letterSpacing: 0.5)),
                    ]),
                  ),
                  _buildDayBadge(daysLeft),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text("Bắt đầu: ${DateFormat('dd/MM/yy').format(startDate)}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  Text("Hết hạn: ${DateFormat('dd/MM/yyyy').format(expDate)}", style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.redAccent)),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(value: progress, minHeight: 6, backgroundColor: Colors.grey.shade100, color: _getProgressColor(daysLeft)),
                ),
                const SizedBox(height: 15),
              ]),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDayBadge(int days) {
    Color color = days < 10 ? Colors.red : (days < 30 ? Colors.orange : Colors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: color.withAlpha(25), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withAlpha(51))),
      child: Column(children: [
        Text("$days", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        Text("NGÀY", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 8)),
      ]),
    );
  }

  Color _getProgressColor(int days) {
    if (days < 10) return Colors.redAccent;
    if (days < 30) return Colors.orangeAccent;
    return const Color(0xFF2962FF);
  }
}
