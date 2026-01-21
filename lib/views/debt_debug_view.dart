import 'package:flutter/material.dart';
import '../data/db_helper.dart';

class DebtDebugView extends StatefulWidget {
  const DebtDebugView({super.key});

  @override
  State<DebtDebugView> createState() => _DebtDebugViewState();
}

class _DebtDebugViewState extends State<DebtDebugView> {
  final db = DBHelper();
  List<Map<String, dynamic>> _allDebts = [];
  String _debugInfo = '';

  @override
  void initState() {
    super.initState();
    _loadDebtData();
  }

  Future<void> _loadDebtData() async {
    debugPrint('DebtDebugView: Loading debt data...');
    final debts = await db.getAllDebts();
    debugPrint('DebtDebugView: Found ${debts.length} debts');

    setState(() {
      _allDebts = debts;
    });

    // Tính toán theo logic home_view MỚI (filter PAID/CANCELLED)
    int homeTotal = 0;
    int homeTotalOld = 0; // Logic cũ để so sánh
    for (var d in debts) {
      final int total = d['totalAmount'] ?? 0;
      final int paid = d['paidAmount'] ?? 0;
      final int remain = total - paid;
      
      // Logic cũ (không filter)
      if (remain > 0) homeTotalOld += remain;
      
      // Logic mới (filter PAID/CANCELLED)
      final status = (d['status']?.toString() ?? '').toUpperCase();
      if (status == 'PAID' || status == 'CANCELLED') continue;
      if (remain > 0 && total > 0) homeTotal += remain;
    }

    // Tính toán theo logic debt_view cho từng loại
    final customerOwes = debts.where((d) {
      final status = (d['status']?.toString() ?? '').toUpperCase();
      return d['type'] == 'CUSTOMER_OWES' && status != 'PAID' && status != 'CANCELLED';
    }).toList();
    final shopOwes = debts.where((d) {
      final status = (d['status']?.toString() ?? '').toUpperCase();
      return d['type'] == 'SHOP_OWES' && status != 'PAID' && status != 'CANCELLED';
    }).toList();

    int customerTotal = customerOwes.fold(0, (sum, d) {
      final int total = d['totalAmount'] as int;
      final int paid = d['paidAmount'] as int? ?? 0;
      final int remain = total - paid;
      return remain > 0 ? sum + remain : sum;
    });

    int shopTotal = shopOwes.fold(0, (sum, d) {
      final int total = d['totalAmount'] as int;
      final int paid = d['paidAmount'] as int? ?? 0;
      final int remain = total - paid;
      return remain > 0 ? sum + remain : sum;
    });

    setState(() {
      _debugInfo = '''
Tổng số debt records: ${debts.length}

HOME VIEW LOGIC MỚI (filter PAID/CANCELLED):
Total: $homeTotal đ

HOME VIEW LOGIC CŨ (tất cả nợ còn lại > 0):
Total: $homeTotalOld đ

DEBT VIEW LOGIC (theo loại, status != 'paid'):
Khách nợ: $customerTotal đ (${customerOwes.length} records)
Shop nợ NCC: $shopTotal đ (${shopOwes.length} records)
Tổng cả 2 loại: ${customerTotal + shopTotal} đ

Chi tiết từng debt:
${debts.map((d) => 'ID: ${d['id']}, Type: ${d['type']}, Status: ${d['status']}, Total: ${d['totalAmount']}, Paid: ${d['paidAmount'] ?? 0}, Remain: ${(d['totalAmount'] ?? 0) - (d['paidAmount'] ?? 0)}').join('\n')}
''';
    });
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
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Debt Debug'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Debt Data Analysis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(_debugInfo, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
      ),
    );
  }
}