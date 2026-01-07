import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/db_helper.dart';
import '../services/notification_service.dart';

class PayrollSettingsView extends StatefulWidget {
  const PayrollSettingsView({super.key});
  @override
  State<PayrollSettingsView> createState() => _PayrollSettingsViewState();
}

class _PayrollSettingsViewState extends State<PayrollSettingsView> {
  final db = DBHelper();
  final baseSalaryC = TextEditingController();
  final saleCommC = TextEditingController();
  final repairCommC = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await db.getPayrollSettings();
    setState(() {
      baseSalaryC.text = (settings['baseSalary'] ?? 0).toString();
      saleCommC.text = (settings['saleCommPercent'] ?? 1.0).toString();
      repairCommC.text = (settings['repairProfitPercent'] ?? 10.0).toString();
      _loading = false;
    });
  }

  Future<void> _save() async {
    final data = {
      'baseSalary': int.tryParse(baseSalaryC.text) ?? 0,
      'saleCommPercent': double.tryParse(saleCommC.text) ?? 1.0,
      'repairProfitPercent': double.tryParse(repairCommC.text) ?? 10.0,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    };
    await db.savePayrollSettings(data);
    HapticFeedback.mediumImpact();
    NotificationService.showSnackBar("ĐÃ LƯU CÔNG THỨC TÍNH LƯƠNG MỚI", color: Colors.green);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(title: const Text("CÀI ĐẶT CÔNG THỨC LƯƠNG", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
      body: _loading ? const Center(child: CircularProgressIndicator()) : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildCard("LƯƠNG CƠ BẢN", Icons.money, baseSalaryC, "đ / tháng", isMoney: true),
            const SizedBox(height: 20),
            _buildCard("HOA HỒNG BÁN MÁY", Icons.shopping_bag, saleCommC, "% trên giá bán"),
            const SizedBox(height: 20),
            _buildCard("THƯỞNG SỬA CHỮA", Icons.build, repairCommC, "% trên lợi nhuận sửa"),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity, height: 55,
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded, color: Colors.white),
                label: const Text("ÁP DỤNG CÔNG THỨC", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildCard(String title, IconData icon, TextEditingController ctrl, String sub, {bool isMoney = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withAlpha(5), blurRadius: 10)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, size: 18, color: Colors.blueGrey), const SizedBox(width: 8), Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey))]),
          const SizedBox(height: 15),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
            decoration: InputDecoration(suffixText: sub, border: InputBorder.none, hintText: "0"),
          ),
        ],
      ),
    );
  }
}
