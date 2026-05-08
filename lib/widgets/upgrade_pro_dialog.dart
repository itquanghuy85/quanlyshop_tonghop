import 'package:flutter/material.dart';
import '../core/app_mode.dart';
import '../services/user_service.dart';
import '../views/choose_mode_screen.dart';

/// Dialog giới thiệu bản Pro và hướng dẫn nâng cấp
class UpgradeProDialog extends StatelessWidget {
  const UpgradeProDialog({super.key});

  static void show(BuildContext context) {
    showDialog(context: context, builder: (_) => const UpgradeProDialog());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.workspace_premium, color: Colors.amber, size: 28),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Nâng cấp lên bản Pro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Bản Pro cung cấp đầy đủ tính năng:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ..._features.map((f) => _FeatureRow(icon: f.$1, text: f.$2)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Liên hệ để nâng cấp:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.phone, size: 16, color: Colors.blue),
                    const SizedBox(width: 6),
                    const Text('0909 123 456', style: TextStyle(fontSize: 13)),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    const Icon(Icons.email_outlined, size: 16, color: Colors.blue),
                    const SizedBox(width: 6),
                    const Text('support@huluca.com', style: TextStyle(fontSize: 13)),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Để sau'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.upgrade, size: 18),
          label: const Text('Kích hoạt ngay'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.amber.shade700,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () async {
            Navigator.pop(context);
            await _activateOnline(context);
          },
        ),
      ],
    );
  }

  static Future<void> _activateOnline(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chuyển sang chế độ Online?'),
        content: const Text(
          'App sẽ yêu cầu bạn đăng nhập tài khoản.\n'
          'Dữ liệu offline hiện tại vẫn được giữ lại trong máy.\n\n'
          'Bạn có muốn tiếp tục không?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await AppMode.upgradeToOnline();
    UserService.clearOfflineSession();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ChooseModeScreen()),
      (route) => false,
    );
  }
}

/// Banner gợi ý nâng cấp Pro nhỏ gọn cho các màn hình
class UpgradeProBanner extends StatelessWidget {
  final String message;
  const UpgradeProBanner({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (!AppMode.isOfflineMode) return const SizedBox.shrink();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => UpgradeProDialog.show(context),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.amber.shade100, Colors.orange.shade50],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade300),
          ),
          child: Row(
            children: [
              const Icon(Icons.workspace_premium, color: Colors.amber, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                'Xem chi tiết',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange.shade700,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _features = [
  (Icons.cloud_sync, 'Đồng bộ dữ liệu lên đám mây an toàn'),
  (Icons.people, 'Quản lý nhân viên & phân quyền'),
  (Icons.bar_chart, 'Báo cáo doanh thu chi tiết theo tháng'),
  (Icons.backup, 'Sao lưu & khôi phục dữ liệu'),
  (Icons.store, 'Quản lý nhiều cửa hàng'),
  (Icons.receipt_long, 'Lịch sử đồng bộ & audit log'),
];

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _FeatureRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.green.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
