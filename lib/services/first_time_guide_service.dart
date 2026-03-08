import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service quản lý hiển thị hướng dẫn cho người dùng mới
/// Dialog chỉ hiển thị 1 lần duy nhất cho mỗi màn hình
class FirstTimeGuideService {
  static const String _prefix = 'guide_shown_';

  // Keys cho các màn hình
  static const String keySmartStockIn = 'smart_stock_in';
  static const String keyCreateRepair = 'create_repair';
  static const String keySalesView = 'sales_view';
  static const String keySupplierList = 'supplier_list';
  static const String keyProductList = 'product_list';
  static const String keyInventoryTab = 'inventory_tab';
  static const String keyFinanceTab = 'finance_tab';
  static const String keyStaffTab = 'staff_tab';
  static const String keyHomeTab = 'home_tab';
  static const String keyFastInventoryInput = 'fast_inventory_input';
  static const String keyFastInventoryCheck = 'fast_inventory_check';
  static const String keyPendingEntries = 'pending_entries';
  static const String keyDebtManagement = 'debt_management';

  /// Kiểm tra xem đã hiển thị hướng dẫn cho màn hình này chưa
  static Future<bool> hasShownGuide(String screenKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_prefix$screenKey') ?? false;
  }

  /// Đánh dấu đã hiển thị hướng dẫn
  static Future<void> markGuideAsShown(String screenKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_prefix$screenKey', true);
  }

  /// Reset tất cả hướng dẫn (dùng để test)
  static Future<void> resetAllGuides() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith(_prefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
  }

  /// Hiển thị dialog hướng dẫn nếu chưa từng hiển thị
  static Future<void> showGuideIfNeeded({
    required BuildContext context,
    required String screenKey,
    required String title,
    required List<GuideStep> steps,
    IconData? icon,
    Color? color,
  }) async {
    if (await hasShownGuide(screenKey)) return;

    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _GuideDialog(
        title: title,
        steps: steps,
        icon: icon ?? Icons.help_outline,
        color: color ?? Colors.blue,
        onDismiss: () async {
          await markGuideAsShown(screenKey);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }

  /// Hiển thị dialog hướng dẫn dạng carousel
  static Future<void> showCarouselGuide({
    required BuildContext context,
    required String screenKey,
    required String title,
    required List<GuideStep> steps,
    Color? color,
  }) async {
    if (await hasShownGuide(screenKey)) return;

    if (!context.mounted) return;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CarouselGuideDialog(
        title: title,
        steps: steps,
        color: color ?? Colors.blue,
        onDismiss: () async {
          await markGuideAsShown(screenKey);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }
}

/// Một bước hướng dẫn
class GuideStep {
  final String title;
  final String description;
  final IconData icon;
  final Color? iconColor;

  const GuideStep({
    required this.title,
    required this.description,
    required this.icon,
    this.iconColor,
  });
}

/// Dialog hướng dẫn đơn giản (hiển thị tất cả steps)
class _GuideDialog extends StatelessWidget {
  final String title;
  final List<GuideStep> steps;
  final IconData icon;
  final Color color;
  final VoidCallback onDismiss;

  const _GuideDialog({
    required this.title,
    required this.steps,
    required this.icon,
    required this.color,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '👋 Chào mừng!',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            ...steps.map((step) => _buildStepItem(step)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Hướng dẫn này chỉ hiển thị 1 lần',
                      style: TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onDismiss,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('ĐÃ HIỂU, BẮT ĐẦU!'),
            style: ElevatedButton.styleFrom(
              backgroundColor: color,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStepItem(GuideStep step) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: (step.iconColor ?? color).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              step.icon,
              color: step.iconColor ?? color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  step.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.3,
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

/// Dialog hướng dẫn dạng carousel (xem từng bước)
class _CarouselGuideDialog extends StatefulWidget {
  final String title;
  final List<GuideStep> steps;
  final Color color;
  final VoidCallback onDismiss;

  const _CarouselGuideDialog({
    required this.title,
    required this.steps,
    required this.color,
    required this.onDismiss,
  });

  @override
  State<_CarouselGuideDialog> createState() => _CarouselGuideDialogState();
}

class _CarouselGuideDialogState extends State<_CarouselGuideDialog> {
  int _currentStep = 0;

  @override
  Widget build(BuildContext context) {
    final step = widget.steps[_currentStep];
    final isLast = _currentStep == widget.steps.length - 1;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  color: widget.color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: widget.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentStep + 1}/${widget.steps.length}',
                  style: TextStyle(
                    color: widget.color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Progress indicator
          Row(
            children: List.generate(
              widget.steps.length,
              (index) => Expanded(
                child: Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: index <= _currentStep
                        ? widget.color
                        : widget.color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      content: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Column(
          key: ValueKey(_currentStep),
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: (step.iconColor ?? widget.color).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                step.icon,
                color: step.iconColor ?? widget.color,
                size: 48,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              step.title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              step.description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentStep--),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: widget.color,
                    side: BorderSide(color: widget.color),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Quay lại'),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: isLast
                    ? widget.onDismiss
                    : () => setState(() => _currentStep++),
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: Text(isLast ? 'BẮT ĐẦU!' : 'Tiếp theo'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
