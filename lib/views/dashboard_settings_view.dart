import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../widgets/responsive_wrapper.dart';
import '../services/dashboard_config_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// View to customize dashboard layout - drag & drop, show/hide cards + shortcuts
class DashboardSettingsView extends StatefulWidget {
  final String role;
  final List<DashboardCardConfig> currentConfig;
  final List<ShortcutConfig> currentShortcuts;
  final VoidCallback? onConfigChanged;

  const DashboardSettingsView({
    super.key,
    required this.role,
    required this.currentConfig,
    this.currentShortcuts = const [],
    this.onConfigChanged,
  });

  @override
  State<DashboardSettingsView> createState() => _DashboardSettingsViewState();
}

class _DashboardSettingsViewState extends State<DashboardSettingsView>
    with SingleTickerProviderStateMixin {
  late List<DashboardCardConfig> _configs;
  late List<ShortcutConfig> _shortcuts;
  late TabController _tabController;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Deep copy dashboard configs
    _configs = widget.currentConfig
        .map((c) => DashboardCardConfig(
              type: c.type,
              visible: c.visible,
              order: c.order,
            ))
        .toList();
    // Deep copy shortcut configs
    if (widget.currentShortcuts.isNotEmpty) {
      _shortcuts = widget.currentShortcuts
          .map((s) => ShortcutConfig(
                type: s.type,
                visible: s.visible,
                order: s.order,
              ))
          .toList();
    } else {
      _shortcuts = ShortcutConfigService.getDefaultShortcuts();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    // Save to SharedPreferences in background
    DashboardConfigService.saveConfig(_configs);
    ShortcutConfigService.saveConfig(_shortcuts);
    widget.onConfigChanged?.call();
    if (mounted) {
      NotificationService.showSnackBar(
        '✅ Đã lưu bố cục Dashboard!',
        color: Colors.green,
      );
      // Return configs directly so caller can apply instantly without re-reading
      Navigator.pop(context, {
        'configs': _configs,
        'shortcuts': _shortcuts,
      });
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
      await ShortcutConfigService.resetConfig();
      final defaults = DashboardConfigService.getDefaultLayout(
        role: widget.role,
        isSuperAdmin: UserService.isCurrentUserSuperAdmin(),
      );
      setState(() {
        _configs = defaults;
        _shortcuts = ShortcutConfigService.getDefaultShortcuts();
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
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: [
            Tab(
              icon: const Icon(Icons.dashboard, size: 18),
              text: 'Thẻ Dashboard',
            ),
            Tab(
              icon: const Icon(Icons.apps, size: 18),
              text: 'Lối tắt nhanh',
            ),
          ],
        ),
      ),
      body: ResponsiveCenter(child: Column(
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
                      fontSize: 14,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Tabbed content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Dashboard cards
                _buildDashboardCardList(),
                // Tab 2: Shortcuts
                _buildShortcutList(),
              ],
            ),
          ),

          // Bottom info bar
          _buildBottomBar(),
        ],
      )),
    );
  }

  /// Build dashboard card reorderable list (Tab 1)
  Widget _buildDashboardCardList() {
    return ReorderableListView.builder(
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
    );
  }

  /// Build shortcut reorderable list (Tab 2)
  Widget _buildShortcutList() {
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _shortcuts.length,
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex--;
          final item = _shortcuts.removeAt(oldIndex);
          _shortcuts.insert(newIndex, item);
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
        final sc = _shortcuts[index];
        return _buildShortcutTile(sc, index);
      },
    );
  }

  /// Bottom bar showing counts + save button
  Widget _buildBottomBar() {
    final visibleCards = _configs.where((c) => c.visible).length;
    final hiddenCards = _configs.where((c) => !c.visible).length;
    final visibleShortcuts = _shortcuts.where((s) => s.visible).length;
    final hiddenShortcuts = _shortcuts.where((s) => !s.visible).length;

    return Container(
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
                '$visibleCards thẻ · $visibleShortcuts lối tắt',
                style: TextStyle(
                  fontSize: 13,
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
                '$hiddenCards · $hiddenShortcuts ẩn',
                style: TextStyle(
                  fontSize: 13,
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
              fontSize: 16,
              color: config.visible ? Colors.black87 : Colors.grey,
            ),
          ),
          subtitle: Row(
            children: [
              Expanded(
                child: Text(
                  config.description,
                  style: TextStyle(
                    fontSize: 13,
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
                      fontSize: 11,
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

  Widget _buildShortcutTile(ShortcutConfig sc, int index) {
    return Card(
      key: ValueKey(sc.type),
      margin: const EdgeInsets.only(bottom: 6),
      elevation: sc.visible ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: sc.visible
              ? sc.color.withOpacity(0.3)
              : Colors.grey.shade200,
        ),
      ),
      child: AnimatedOpacity(
        opacity: sc.visible ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 200),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.drag_handle, color: Colors.grey.shade400, size: 20),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: sc.visible
                      ? sc.color.withOpacity(0.12)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  sc.icon,
                  color: sc.visible ? sc.color : Colors.grey,
                  size: 20,
                ),
              ),
            ],
          ),
          title: Text(
            sc.displayName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: sc.visible ? Colors.black87 : Colors.grey,
            ),
          ),
          subtitle: sc.requiresRepair
              ? Text('Yêu cầu module sửa chữa',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
              : sc.requiresWarranty
                  ? Text('Yêu cầu module bảo hành',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500))
                  : null,
          trailing: Switch.adaptive(
            value: sc.visible,
            activeColor: sc.color,
            onChanged: (val) {
              setState(() {
                sc.visible = val;
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
