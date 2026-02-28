import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/dashboard_config_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// View to customize dashboard layout - drag & drop, show/hide cards
class DashboardSettingsView extends StatefulWidget {
  final String role;
  final List<DashboardCardConfig> currentConfig;
  final VoidCallback? onConfigChanged;

  const DashboardSettingsView({
    super.key,
    required this.role,
    required this.currentConfig,
    this.onConfigChanged,
  });

  @override
  State<DashboardSettingsView> createState() => _DashboardSettingsViewState();
}

class _DashboardSettingsViewState extends State<DashboardSettingsView> {
  late List<DashboardCardConfig> _configs;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    // Deep copy
    _configs = widget.currentConfig
        .map((c) => DashboardCardConfig(
              type: c.type,
              visible: c.visible,
              order: c.order,
            ))
        .toList();
  }

  Future<void> _save() async {
    await DashboardConfigService.saveConfig(_configs);
    widget.onConfigChanged?.call();
    if (mounted) {
      NotificationService.showSnackBar(
        '✅ Đã lưu bố cục Dashboard!',
        color: Colors.green,
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _resetDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.restore, color: Colors.orange),
            SizedBox(width: 8),
            Text('Khôi phục mặc định?'),
          ],
        ),
        content: const Text('Bố cục Dashboard sẽ trở về mặc định theo vai trò của bạn.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('KHÔI PHỤC'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DashboardConfigService.resetConfig();
      final defaults = DashboardConfigService.getDefaultLayout(
        role: widget.role,
        isSuperAdmin: UserService.isCurrentUserSuperAdmin(),
      );
      setState(() {
        _configs = defaults;
        _hasChanges = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Tùy chỉnh Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: 'Khôi phục mặc định',
            onPressed: _resetDefaults,
          ),
          TextButton.icon(
            onPressed: _hasChanges ? _save : null,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('LƯU'),
            style: TextButton.styleFrom(
              foregroundColor: _hasChanges ? Colors.white : Colors.white54,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Instructions
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            color: Colors.blue.shade50,
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade600, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Kéo thả để sắp xếp • Bật/tắt để ẩn hiện',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Card list
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _configs.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _configs.removeAt(oldIndex);
                  _configs.insert(newIndex, item);
                  _hasChanges = true;
                });
                HapticFeedback.lightImpact();
              },
              proxyDecorator: (child, index, animation) {
                return AnimatedBuilder(
                  listenable: animation,
                  builder: (ctx, c) => Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(14),
                    shadowColor: Colors.black38,
                    child: c,
                  ),
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final config = _configs[index];
                return _buildCardTile(config, index);
              },
            ),
          ),

          // Preview info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Text(
                      '${_configs.where((c) => c.visible).length} hiện',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      '${_configs.where((c) => !c.visible).length} ẩn',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_hasChanges)
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('LƯU'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardTile(DashboardCardConfig config, int index) {
    final isFinance = config.requiresFinanceAccess;
    final isOwner = widget.role == 'owner' || widget.role == 'admin' ||
        UserService.isCurrentUserSuperAdmin();

    return Card(
      key: ValueKey(config.type),
      margin: const EdgeInsets.only(bottom: 6),
      elevation: config.visible ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: config.visible
              ? config.color.withOpacity(0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: AnimatedOpacity(
        opacity: config.visible ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 200),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Icon(Icons.drag_handle, color: Colors.grey.shade400, size: 20),
              const SizedBox(width: 8),
              // Card icon
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: config.visible
                      ? config.color.withOpacity(0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  config.icon,
                  color: config.visible ? config.color : Colors.grey,
                  size: 20,
                ),
              ),
            ],
          ),
          title: Text(
            config.displayName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: config.visible ? Colors.black87 : Colors.grey,
            ),
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  config.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
              if (isFinance && !isOwner)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Chủ shop',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.orange.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          trailing: Switch.adaptive(
            value: config.visible,
            activeColor: config.color,
            onChanged: (isFinance && !isOwner)
                ? null // Can't enable finance cards for non-owners
                : (val) {
                    setState(() {
                      config.visible = val;
                      _hasChanges = true;
                    });
                    HapticFeedback.lightImpact();
                  },
          ),
        ),
      ),
    );
  }
}

/// AnimatedBuilder wrapper (needed for proxy decorator)
class AnimatedBuilder extends StatelessWidget {
  final Animation<double> listenable;
  final Widget Function(BuildContext, Widget?) builder;
  final Widget? child;

  const AnimatedBuilder({
    super.key,
    required this.listenable,
    required this.builder,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
