import 'package:flutter/material.dart';
import '../services/money_transaction_service.dart';
import '../models/financial_activity_model.dart';
import '../theme/app_text_styles.dart';

class FinancialReconciliationView extends StatefulWidget {
  const FinancialReconciliationView({Key? key}) : super(key: key);

  @override
  State<FinancialReconciliationView> createState() =>
      _FinancialReconciliationViewState();
}

class _FinancialReconciliationViewState
    extends State<FinancialReconciliationView> {
  List<FinancialActivity> _ledger = [];
  List<FinancialActivity> _filteredLedger = [];
  int _income = 0;
  int _expense = 0;
  int _balance = 0;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _loadLedger();
  }

  void _loadLedger() async {
    final ledger = await MoneyTransactionService.getLedgerEntries();
    setState(() {
      _ledger = ledger;
      _filteredLedger = ledger;
      _income = ledger
          .where((e) => e.amount > 0)
          .fold(0, (sum, e) => sum + e.amount);
      _expense = ledger
          .where((e) => e.amount < 0)
          .fold(0, (sum, e) => sum + e.amount);
      _balance = _income + _expense;
    });
  }

  void _applyFilter(String value) {
    setState(() {
      _filter = value;
      _filteredLedger = _ledger
          .where(
            (e) =>
                e.referenceId?.contains(value) == true ||
                e.activityType.contains(value) == true ||
                e.description?.contains(value) == true,
          )
          .toList();
    });
  }

  bool _isAnomaly(FinancialActivity entry) {
    // Highlight: adjustments, negative, duplicate sourceId
    final isAdjust = entry.activityType == 'ADJUSTMENT';
    final isNegative = entry.amount < 0;
    final isDuplicate =
        _ledger.where((e) => e.referenceId == entry.referenceId).length > 1;
    return isAdjust || isNegative || isDuplicate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Đối Soát Dòng Tiền')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryCard('Thu', _income, Colors.green),
                _summaryCard('Chi', _expense, Colors.red),
                _summaryCard('Cân Bằng', _balance, Colors.blue),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Lọc theo mã, loại, ghi chú',
              ),
              onChanged: _applyFilter,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredLedger.length,
              itemBuilder: (context, idx) {
                final entry = _filteredLedger[idx];
                final anomaly = _isAnomaly(entry);
                return Card(
                  color: anomaly ? Colors.yellow[100] : null,
                  child: ListTile(
                    title: Text(
                      '${entry.activityType ?? ''} - ${entry.amount}đ',
                    ),
                    subtitle: Text(
                      '${entry.referenceId ?? ''} | ${entry.description ?? ''}',
                    ),
                    trailing: anomaly
                        ? const Icon(Icons.warning, color: Colors.orange)
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, int value, Color color) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              label,
              style: TextStyle(fontWeight: FontWeight.bold, color: color),
            ),
            Text('$value đ', style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, color: color)),
          ],
        ),
      ),
    );
  }
}
