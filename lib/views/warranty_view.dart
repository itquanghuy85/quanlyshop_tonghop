import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../theme/app_text_styles.dart';
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
    setState(() {
      _isAdmin = perms['allowViewWarranty'] ?? false;
    });
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
      debugPrint(
        "WARRANTY_DEBUG: Repair - id:${r.id}, firestoreId:${r.firestoreId}, warranty:${r.warranty}, status:${r.status}, deleted:${r.deleted}, customerName:${r.customerName}",
      );
    }
    for (var s in sales) {
      debugPrint(
        "WARRANTY_DEBUG: Sale - id:${s.id}, firestoreId:${s.firestoreId}, warranty:${s.warranty}, customerName:${s.customerName}",
      );
    }

    List<Map<String, dynamic>> results = [];

    // 1. BẢO HÀNH MÁY SỬA
    for (var r in repairs) {
      if (r.deliveredAt != null &&
          r.warranty.isNotEmpty &&
          r.warranty != "KO BH") {
        int months = int.tryParse(r.warranty.split(' ').first) ?? 0;
        if (months > 0) {
          DateTime delDate = DateTime.fromMillisecondsSinceEpoch(
            r.deliveredAt!,
          );
          DateTime expDate = DateTime(
            delDate.year,
            delDate.month + months,
            delDate.day,
          );
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
        int months =
            int.tryParse(s.warranty.split(' ').first) ??
            12; // Mặc định 12th nếu lỗi parse
        DateTime saleDate = DateTime.fromMillisecondsSinceEpoch(s.soldAt);
        DateTime expDate = DateTime(
          saleDate.year,
          saleDate.month + months,
          saleDate.day,
        );

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

    results.sort(
      (a, b) => (a['expiry'] as DateTime).compareTo(b['expiry'] as DateTime),
    );
    if (mounted)
      setState(() {
        _warrantyList = results;
        _isLoading = false;
      });
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
        title: Text(
          "SIÊU TRUNG TÂM BẢO HÀNH",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextStyles.headline3.fontSize,
            color: Colors.white,
          ),
        ),
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            onPressed: _loadAllWarranty,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _warrantyList.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(10),
              itemCount: _warrantyList.length,
              itemBuilder: (ctx, i) =>
                  _buildWarrantyCard(_warrantyList[i], i + 1),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.verified_user_outlined,
            size: 100,
            color: Colors.blue.withAlpha(51),
          ),
          const SizedBox(height: 15),
          Text(
            "KHÔNG CÓ MÁY NÀO TRONG HẠN BẢO HÀNH",
            style: TextStyle(
              color: Colors.blueGrey,
              fontWeight: FontWeight.bold,
              fontSize: AppTextStyles.headline5.fontSize,
            ),
          ),
          Text(
            "Mọi đơn hàng đã hết hạn hoặc chưa được giao.",
            style: TextStyle(color: Colors.grey, fontSize: AppTextStyles.body1.fontSize),
          ),
        ],
      ),
    );
  }

  Widget _buildWarrantyCard(Map<String, dynamic> item, int index) {
    final bool isSale = item['type'] == 'SALE';
    final DateTime expDate = item['expiry'];
    final DateTime startDate = item['startDate'];
    final int totalDays = expDate.difference(startDate).inDays;
    final int daysLeft = expDate.difference(DateTime.now()).inDays;
    final double progress = (daysLeft / (totalDays > 0 ? totalDays : 1)).clamp(
      0.0,
      1.0,
    );

    // Colors based on urgency
    final urgentColor = daysLeft < 10
        ? Colors.red
        : (daysLeft < 30 ? Colors.orange : Colors.green);
    final bgColor = daysLeft < 10 ? Colors.red.shade50 : Colors.white;
    final borderColor = daysLeft < 10
        ? Colors.red.shade200
        : Colors.grey.shade200;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: borderColor, width: 1),
      ),
      elevation: 1,
      color: bgColor,
      child: InkWell(
        onTap: () {
          if (isSale) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SaleDetailView(sale: item['data'] as SaleOrder),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    RepairDetailView(repair: item['data'] as Repair),
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  // STT + Type icon
                  Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: (isSale ? Colors.pink : Colors.orange).withOpacity(
                        0.15,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '$index',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextStyles.caption.fontSize,
                          color: isSale
                              ? Colors.pink.shade700
                              : Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    isSale ? '📱' : '🔧',
                    style: TextStyle(fontSize: AppTextStyles.headline3.fontSize),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              margin: const EdgeInsets.only(right: 4),
                              decoration: BoxDecoration(
                                color: isSale ? Colors.pink : Colors.orange,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                isSale ? 'BÁN' : 'SỬA',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: AppTextStyles.overlineSize,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                item['model'].toString().toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextStyles.subtitle1.fontSize,
                                  color: Color(0xFF1A237E),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        // Customer + IMEI
                        Text(
                          '${item['customer']} • ${item['imei']}',
                          style: TextStyle(
                            fontSize: AppTextStyles.caption.fontSize,
                            color: Colors.grey.shade600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Days badge
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: urgentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: urgentColor.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$daysLeft',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextStyles.subtitle1.fontSize,
                                color: urgentColor,
                              ),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              'ngày',
                              style: TextStyle(fontSize: AppTextStyles.overlineSize, color: urgentColor),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        DateFormat('dd/MM/yy').format(expDate),
                        style: TextStyle(
                          fontSize: AppTextStyles.overlineSize,
                          color: urgentColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 6),

              // Progress bar row
              Row(
                children: [
                  Text(
                    '${DateFormat('dd/MM').format(startDate)}',
                    style: TextStyle(fontSize: AppTextStyles.overlineSize, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.grey.shade200,
                        color: urgentColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${DateFormat('dd/MM').format(expDate)}',
                    style: TextStyle(
                      fontSize: AppTextStyles.overlineSize,
                      color: urgentColor,
                      fontWeight: FontWeight.w500,
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

  Color _getProgressColor(int days) {
    if (days < 10) return Colors.redAccent;
    if (days < 30) return Colors.orangeAccent;
    return const Color(0xFF2962FF);
  }
}
