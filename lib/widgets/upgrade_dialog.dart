import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/app_mode.dart';
import '../services/user_service.dart';
import '../views/login_view.dart';

class UpgradeDialog extends StatelessWidget {
  const UpgradeDialog({super.key});

  static void show(BuildContext context) {
    showDialog(context: context, builder: (_) => const UpgradeDialog());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4CC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.star, color: Color(0xFFE6A700)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Nang cap len Pro (Online)',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: const [
            _FeatureTile(icon: Icons.cloud_done, text: 'Dong bo du lieu cloud, an toan va da thiet bi'),
            _FeatureTile(icon: Icons.people_alt_outlined, text: 'Quan ly nhan vien va phan quyen chi tiet'),
            _FeatureTile(icon: Icons.insights_outlined, text: 'Bao cao nang cao theo thang, nam, loi nhuan'),
            _FeatureTile(icon: Icons.backup_outlined, text: 'Sao luu va khoi phuc du lieu nhanh chong'),
            _FeatureTile(icon: Icons.print_outlined, text: 'In hoa don nhiet va ho tro may quet ma vach'),
            _FeatureTile(icon: Icons.notifications_active_outlined, text: 'Thong bao den khach hang theo trang thai don'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Dong'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.call, size: 16),
          label: const Text('Lien he nang cap'),
          onPressed: () async {
            Navigator.of(context).pop();
            final telUri = Uri(scheme: 'tel', path: '0987654321');
            if (await canLaunchUrl(telUri)) {
              await launchUrl(telUri);
              return;
            }
            final mailUri = Uri(
              scheme: 'mailto',
              path: 'support@huluca.com',
              queryParameters: {'subject': 'Dang ky nang cap Pro'},
            );
            if (await canLaunchUrl(mailUri)) {
              await launchUrl(mailUri);
            }
          },
        ),
        FilledButton.icon(
          icon: const Icon(Icons.vpn_key_outlined, size: 16),
          label: const Text('Nhap ma kich hoat'),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD89B00)),
          onPressed: () {
            Navigator.of(context).pop();
            _showActivationDialog(context);
          },
        ),
      ],
    );
  }

  static Future<void> _showActivationDialog(BuildContext context) async {
    final codeController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nhap ma kich hoat'),
        content: TextField(
          controller: codeController,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'HULUCA2025',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Xac nhan'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final code = codeController.text.trim().toUpperCase();
    if (code != 'HULUCA2025') {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ma khong hop le'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Upgrade feature
    await AppMode.upgradeToOnline();
    UserService.clearOfflineSession();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Nang cap thanh cong! Vui long dang nhap.'),
        backgroundColor: Colors.green,
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginView()),
      (route) => false,
    );
  }
}

class UpgradePromptBanner extends StatelessWidget {
  final String message;
  final String actionLabel;

  const UpgradePromptBanner({
    super.key,
    required this.message,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (!AppMode.isOfflineMode) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7D6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE08A)),
      ),
      child: Row(
        children: [
          const Icon(Icons.workspace_premium, color: Color(0xFFE6A700), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          TextButton(
            onPressed: () => UpgradeDialog.show(context),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeatureTile({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2E7D32)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}