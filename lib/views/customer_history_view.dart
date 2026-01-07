import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' as m;
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../core/utils/money_utils.dart';

import '../data/db_helper.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import 'repair_detail_view.dart';
import 'sale_detail_view.dart';

class CustomerHistoryView extends StatefulWidget {
  final String phone;
  final String name;
  const CustomerHistoryView({
    super.key,
    required this.phone,
    required this.name,
  });

  @override
  State<CustomerHistoryView> createState() => _CustomerHistoryViewState();
}

class _CustomerHistoryViewState extends State<CustomerHistoryView> {
  final db = DBHelper();
  List<Map<String, dynamic>> combinedHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUnifiedHistory();
  }

  Future<void> _loadUnifiedHistory() async {
    setState(() => _isLoading = true);
    final repairs = await db.getAllRepairs();
    final sales = await db.getAllSales();

    List<Map<String, dynamic>> results = [];

    for (var r in repairs.where((item) => item.phone == widget.phone)) {
      results.add({
        'type': 'REPAIR',
        'time': r.createdAt,
        'title': r.model,
        'subtitle': "Sửa: ${r.issue.split('|').first}",
        'status': r.status,
        'amount': r.price,
        'images': r.receiveImages,
        'data': r,
      });
    }

    for (var s in sales.where((item) => item.phone == widget.phone)) {
      results.add({
        'type': 'SALE',
        'time': s.soldAt,
        'title': s.productNames,
        'subtitle': "Mua máy mới",
        'status': 4,
        'amount': s.totalPrice,
        'images': [],
        'data': s,
      });
    }

    results.sort((a, b) => (b['time'] as int).compareTo(a['time'] as int));

    setState(() {
      combinedHistory = results;
      _isLoading = false;
    });
  }

  void _openGallery(List<String> images, int index) {
    final validImages = images.where((p) => p.startsWith('http') || File(p).existsSync()).toList();
    if (validImages.isEmpty) return;

    m.Navigator.push(context, m.MaterialPageRoute(builder: (_) => m.Scaffold(
      appBar: m.AppBar(backgroundColor: m.Colors.black, iconTheme: const m.IconThemeData(color: m.Colors.white)),
      backgroundColor: m.Colors.black,
      body: PhotoViewGallery.builder(
        itemCount: validImages.length,
        builder: (context, i) => PhotoViewGalleryPageOptions(
          imageProvider: validImages[i].startsWith('http') ? m.NetworkImage(validImages[i]) : m.FileImage(File(validImages[i])) as m.ImageProvider,
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
        ),
        pageController: PageController(initialPage: index.clamp(0, validImages.length - 1)),
        scrollPhysics: const m.BouncingScrollPhysics(),
      ),
    )));
  }

  String _fmtDate(int ms) =>
      DateFormat('dd/MM/yyyy HH:mm').format(DateTime.fromMillisecondsSinceEpoch(ms));

  @override
  Widget build(BuildContext context) {
    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: const CupertinoNavigationBar(
        middle: Text("Hồ sơ khách hàng"),
      ),
      child: m.Material(
        color: m.Colors.transparent,
        child: SafeArea(
          child: _isLoading
            ? const m.Center(child: m.CircularProgressIndicator())
            : combinedHistory.isEmpty
              ? const m.Center(child: Text("Chưa có lịch sử giao dịch"))
              : m.ListView.builder(
                  padding: const m.EdgeInsets.all(16),
                  itemCount: combinedHistory.length,
                  itemBuilder: (context, index) {
                    final item = combinedHistory[index];
                    final bool isRepair = item['type'] == 'REPAIR';
                    final List<String> imgs = List<String>.from(item['images']);
                    final String thumb = imgs.firstWhere(
                      (p) => p.startsWith('http') || File(p).existsSync(),
                      orElse: () => '',
                    );
                    final bool hasThumb = thumb.isNotEmpty;

                    return m.Container(
                      margin: const m.EdgeInsets.only(bottom: 12),
                      decoration: m.BoxDecoration(
                        color: m.Colors.white,
                        borderRadius: m.BorderRadius.circular(15),
                        boxShadow: [m.BoxShadow(color: m.Colors.black.withAlpha(5), blurRadius: 10)]
                      ),
                      child: m.ListTile(
                        contentPadding: const m.EdgeInsets.all(12),
                        leading: m.GestureDetector(
                          onTap: imgs.isNotEmpty ? () => _openGallery(imgs, 0) : null,
                          child: m.Container(
                            width: 55, height: 55,
                            decoration: m.BoxDecoration(
                              color: isRepair ? m.Colors.orange.withAlpha(25) : m.Colors.pink.withAlpha(25),
                              borderRadius: m.BorderRadius.circular(10),
                            ),
                            child: hasThumb
                              ? m.ClipRRect(
                                  borderRadius: m.BorderRadius.circular(10),
                                  child: thumb.startsWith('http')
                                      ? m.Image.network(thumb, fit: m.BoxFit.cover)
                                      : m.Image.file(File(thumb), fit: m.BoxFit.cover),
                                )
                              : m.Icon(isRepair ? m.Icons.build : m.Icons.shopping_bag, color: isRepair ? m.Colors.orange : m.Colors.pink, size: 24),
                          ),
                        ),
                        title: m.Text(
                          item['title'],
                          style: const m.TextStyle(fontWeight: m.FontWeight.bold, fontSize: 15),
                        ),
                        subtitle: m.Column(
                          crossAxisAlignment: m.CrossAxisAlignment.start,
                          children: [
                            m.Text("${item['subtitle']} - ${MoneyUtils.formatVND(item['amount'])}đ", style: const m.TextStyle(fontSize: 13)),
                            m.Text(_fmtDate(item['time']), style: const m.TextStyle(fontSize: 11, color: m.Colors.grey)),
                          ],
                        ),
                        trailing: const m.Icon(m.Icons.chevron_right, size: 18),
                        onTap: () async {
                          if (isRepair) {
                            await m.Navigator.push(context, m.MaterialPageRoute(builder: (_) => RepairDetailView(repair: item['data'] as Repair)));
                          } else {
                            await m.Navigator.push(context, m.MaterialPageRoute(builder: (_) => SaleDetailView(sale: item['data'] as SaleOrder)));
                          }
                          _loadUnifiedHistory();
                         },
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
