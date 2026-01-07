import 'package:flutter/material.dart';
import '../widgets/currency_text_field.dart';

class CurrencyInputDemo extends StatefulWidget {
  const CurrencyInputDemo({super.key});

  @override
  State<CurrencyInputDemo> createState() => _CurrencyInputDemoState();
}

class _CurrencyInputDemoState extends State<CurrencyInputDemo> {
  final TextEditingController _oldController = TextEditingController();
  final TextEditingController _newController = TextEditingController();

  String _oldValue = '0';
  String _newValue = '0';

  @override
  void dispose() {
    _oldController.dispose();
    _newController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('So sánh Currency Input'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🎯 DEMO SO SÁNH QUY ƯỚC NHẬP TIỀN',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
            ),
            const SizedBox(height: 8),
            const Text(
              'Quy ước x1k (đồng bộ toàn app) vs Nhập trực tiếp',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),

            // Old Currency Input
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red),
                      SizedBox(width: 8),
                      Text(
                        'QUY ƯỚC X1K (CurrencyTextField)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '•VNĐ\n• Lưu giá trị thực: 220\n• Quy ước x1k: rõ ràng, đồng bộ',
                    style: TextStyle(color: Colors.red[700], fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  CurrencyTextField(
                    controller: _oldController,
                    label: 'Giá tiền (VNĐ)',
                    hint: ' VNĐ',
                    icon: Icons.attach_money,
                    onChanged: (value) {
                      setState(() => _oldValue = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Giá trị thực: ${_formatCurrency(int.tryParse(_oldValue) ?? 0)} VNĐ',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // New Enhanced Currency Input
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        'NHẬP TRỰC TIẾP (EnhancedCurrencyInput)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• Nhập trực tiếp số tiền đầy đủ\n• Hiển thị rõ ràng với định dạng VNĐ\n• Quick select buttons cho số tiền phổ biến\n• UX hiện đại, linh hoạt',
                    style: TextStyle(color: Colors.green[700], fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  EnhancedCurrencyInput(
                    controller: _newController,
                    label: 'Giá tiền (nhập trực tiếp)',
                    hint: 'Nhập số tiền trực tiếp hoặc chọn nhanh',
                    icon: Icons.monetization_on,
                    onChanged: (value) {
                      setState(() => _newValue = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Giá trị thực: ${_formatCurrency(int.tryParse(_newValue) ?? 0)} VNĐ',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Comparison Summary
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '📊 SO SÁNH CHI TIẾT',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue),
                  ),
                  const SizedBox(height: 16),
                  _buildComparisonRow('Nhập liệu', 'Quy ước x1k (rõ ràng)', 'Đơn giản (trực tiếp)'),
                  _buildComparisonRow('Hiển thị', '220 VNĐ + x1k', '220 VNĐ'),
                  _buildComparisonRow('Quick Select', 'Không có', 'Có (100K, 200K, 500K, 1M...)'),
                  _buildComparisonRow('UX', 'Rõ ràng với ghi chú', 'Trực quan'),
                  _buildComparisonRow('Tốc độ nhập', 'Trung bình', 'Nhanh'),
                  _buildComparisonRow('Độ chính xác', 'Chính xác với quy ước', 'Chính xác'),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      _oldController.clear();
                      _newController.clear();
                      setState(() {
                        _oldValue = '0';
                        _newValue = '0';
                      });
                    },
                    icon: const Icon(Icons.clear),
                    label: const Text('Xóa tất cả'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      // Test with sample values
                      _oldController.text = '220';
                      _newController.text = '220000';
                      setState(() {
                        _oldValue = '220000';
                        _newValue = '220000';
                      });
                    },
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Test 220K'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonRow(String feature, String oldWay, String newWay) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(feature, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 2,
            child: Text(oldWay, style: const TextStyle(color: Colors.red)),
          ),
          Expanded(
            flex: 2,
            child: Text(newWay, style: const TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(int amount) {
    String str = amount.toString();
    String result = '';
    int count = 0;

    for (int i = str.length - 1; i >= 0; i--) {
      result = str[i] + result;
      count++;
      if (count % 3 == 0 && i > 0) {
        result = '.$result';
      }
    }

    return result;
  }
}
