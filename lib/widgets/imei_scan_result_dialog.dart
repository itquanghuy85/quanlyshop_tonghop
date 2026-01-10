import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/imei_extractor.dart';
import '../theme/app_colors.dart';

/// Dialog hiển thị kết quả quét QR IMEI cho user chọn
class IMEIScanResultDialog extends StatelessWidget {
  final IMEIExtractResult result;
  final Function(String imei, {bool useLast5}) onSelect;

  const IMEIScanResultDialog({
    super.key,
    required this.result,
    required this.onSelect,
  });

  /// Show dialog và return IMEI được chọn
  static Future<String?> show(
    BuildContext context,
    IMEIExtractResult result, {
    bool allowLast5 = true,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => IMEIScanResultDialog(
        result: result,
        onSelect: (imei, {useLast5 = false}) {
          final value = useLast5 ? IMEIExtractor.getLast5Digits(imei) : imei;
          Navigator.of(ctx).pop(value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = result.hasMultipleCandidates;
    final theme = Theme.of(context);

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            hasMultiple ? Icons.warning_amber : Icons.qr_code_scanner,
            color: hasMultiple ? Colors.orange : Colors.green,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hasMultiple ? 'Phát hiện nhiều IMEI' : 'Kết quả quét QR',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thông báo nếu multi-line
            if (result.isMultiLine)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'QR chứa ${result.allLines.length} dòng dữ liệu',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Danh sách IMEI candidates
            if (result.candidates.isNotEmpty) ...[
              const Text(
                'IMEI phát hiện:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...result.candidates.asMap().entries.map((entry) {
                final idx = entry.key;
                final imei = entry.value;
                final isFirst = idx == 0;
                return _IMEIOptionTile(
                  imei: imei,
                  isRecommended: isFirst,
                  onSelectFull: () => onSelect(imei, useLast5: false),
                  onSelectLast5: () => onSelect(imei, useLast5: true),
                );
              }),
            ],

            // Hiển thị Serial nếu có
            if (result.serial != null) ...[
              const Divider(height: 24),
              _InfoRow(
                label: 'Serial Number',
                value: result.serial!,
                icon: Icons.confirmation_number,
              ),
            ],

            // Hiển thị Model nếu có
            if (result.model != null) ...[
              const SizedBox(height: 8),
              _InfoRow(
                label: 'Model',
                value: result.model!,
                icon: Icons.phone_android,
              ),
            ],

            // Raw data (collapsed)
            if (result.allLines.length > 1) ...[
              const Divider(height: 24),
              ExpansionTile(
                title: const Text(
                  'Dữ liệu gốc',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.all(8),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      result.rawData,
                      style: const TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Không tìm thấy IMEI
            if (result.candidates.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Không tìm thấy IMEI hợp lệ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Dữ liệu quét được:\n${result.rawData}',
                      style: const TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Đóng'),
        ),
        if (result.candidates.isEmpty)
          TextButton(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('Nhập thủ công'),
          ),
      ],
    );
  }
}

/// Tile hiển thị 1 IMEI candidate
class _IMEIOptionTile extends StatelessWidget {
  final String imei;
  final bool isRecommended;
  final VoidCallback onSelectFull;
  final VoidCallback onSelectLast5;

  const _IMEIOptionTile({
    required this.imei,
    required this.isRecommended,
    required this.onSelectFull,
    required this.onSelectLast5,
  });

  @override
  Widget build(BuildContext context) {
    final last5 = IMEIExtractor.getLast5Digits(imei);
    final formatted = IMEIExtractor.formatIMEI(imei);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: isRecommended ? Colors.green : Colors.grey.shade300,
          width: isRecommended ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
        color: isRecommended ? Colors.green.shade50 : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header với IMEI
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                if (isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Đề xuất',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        formatted,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '5 số cuối: $last5',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: imei));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã copy IMEI'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: 'Copy IMEI',
                ),
              ],
            ),
          ),
          // Buttons
          Container(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onSelectLast5,
                    icon: const Icon(Icons.short_text, size: 16),
                    label: Text('Dùng $last5'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onSelectFull,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Dùng đầy đủ'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Row hiển thị thông tin
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _InfoRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        Expanded(
          child: SelectableText(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
