import 'dart:async';
import 'package:flutter/material.dart';
import '../services/sync_orchestrator.dart';

/// Widget hiển thị trạng thái sync và số lượng pending
/// Có thể sử dụng trong AppBar hoặc bất kỳ đâu
class PendingSyncIndicator extends StatefulWidget {
  /// Callback khi user tap vào indicator
  final VoidCallback? onTap;
  
  /// Hiển thị text hay chỉ icon
  final bool showText;
  
  /// Icon size
  final double iconSize;
  
  /// Badge color
  final Color? badgeColor;
  
  const PendingSyncIndicator({
    super.key,
    this.onTap,
    this.showText = false,
    this.iconSize = 24,
    this.badgeColor,
  });

  @override
  State<PendingSyncIndicator> createState() => _PendingSyncIndicatorState();
}

class _PendingSyncIndicatorState extends State<PendingSyncIndicator>
    with SingleTickerProviderStateMixin {
  final SyncOrchestrator _orchestrator = SyncOrchestrator();
  
  late StreamSubscription<int> _countSubscription;
  late StreamSubscription<SyncStatus> _statusSubscription;
  late AnimationController _animationController;
  
  int _pendingCount = 0;
  SyncStatus _status = SyncStatus.synced;

  @override
  void initState() {
    super.initState();
    
    // Animation cho icon khi đang sync
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    
    // Subscribe to pending count
    _pendingCount = _orchestrator.pendingCount;
    _countSubscription = _orchestrator.pendingCountStream.listen((count) {
      if (mounted) {
        setState(() => _pendingCount = count);
      }
    });
    
    // Subscribe to sync status
    _statusSubscription = _orchestrator.syncStatusStream.listen((status) {
      if (mounted) {
        setState(() => _status = status);
        if (status == SyncStatus.syncing) {
          _animationController.repeat();
        } else {
          _animationController.stop();
          _animationController.reset();
        }
      }
    });
  }

  @override
  void dispose() {
    _countSubscription.cancel();
    _statusSubscription.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeColor = widget.badgeColor ?? theme.colorScheme.error;
    
    // Determine icon and color based on status
    IconData icon;
    Color iconColor;
    String tooltip;
    
    switch (_status) {
      case SyncStatus.synced:
        icon = Icons.cloud_done;
        iconColor = Colors.green;
        tooltip = 'Đã đồng bộ';
        break;
      case SyncStatus.hasPending:
        icon = Icons.cloud_upload;
        iconColor = Colors.orange;
        tooltip = '$_pendingCount thay đổi chưa đồng bộ';
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        iconColor = theme.colorScheme.primary;
        tooltip = 'Đang đồng bộ...';
        break;
      case SyncStatus.noNetwork:
        icon = Icons.cloud_off;
        iconColor = Colors.grey;
        tooltip = 'Không có mạng';
        break;
      case SyncStatus.error:
        icon = Icons.cloud_off;
        iconColor = Colors.red;
        tooltip = 'Lỗi đồng bộ';
        break;
    }
    
    Widget iconWidget = AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _status == SyncStatus.syncing
              ? _animationController.value * 2 * 3.14159
              : 0,
          child: Icon(
            icon,
            size: widget.iconSize,
            color: iconColor,
          ),
        );
      },
    );
    
    // Add badge if has pending
    if (_pendingCount > 0 && _status != SyncStatus.syncing) {
      iconWidget = Badge(
        label: Text(
          _pendingCount > 99 ? '99+' : '$_pendingCount',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
        backgroundColor: badgeColor,
        child: iconWidget,
      );
    }
    
    // Add text if needed
    Widget content = iconWidget;
    if (widget.showText) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(width: 8),
          Text(
            _getStatusText(),
            style: TextStyle(
              color: iconColor,
              fontSize: 14,
            ),
          ),
        ],
      );
    }
    
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: widget.onTap ?? () => _showSyncDialog(context),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: content,
        ),
      ),
    );
  }
  
  String _getStatusText() {
    switch (_status) {
      case SyncStatus.synced:
        return 'Đã đồng bộ';
      case SyncStatus.hasPending:
        return '$_pendingCount chưa đồng bộ';
      case SyncStatus.syncing:
        return 'Đang đồng bộ...';
      case SyncStatus.noNetwork:
        return 'Không có mạng';
      case SyncStatus.error:
        return 'Lỗi đồng bộ';
    }
  }
  
  void _showSyncDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const SyncStatusDialog(),
    );
  }
}

/// Dialog hiển thị chi tiết trạng thái sync
class SyncStatusDialog extends StatefulWidget {
  const SyncStatusDialog({super.key});

  @override
  State<SyncStatusDialog> createState() => _SyncStatusDialogState();
}

class _SyncStatusDialogState extends State<SyncStatusDialog> {
  final SyncOrchestrator _orchestrator = SyncOrchestrator();
  
  Map<String, int> _stats = {};
  List<SyncQueueItem> _failedItems = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final stats = await _orchestrator.getSyncStats();
      final failed = await _orchestrator.getFailedItems();
      if (mounted) {
        setState(() {
          _stats = stats;
          _failedItems = failed;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    try {
      final result = await _orchestrator.syncAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.toString())),
        );
        await _loadStats();
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _retryFailed() async {
    await _orchestrator.retryFailedItems();
    await _syncNow();
  }

  Future<void> _clearFailed() async {
    final count = await _orchestrator.clearFailedItems();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xóa $count mục lỗi')),
      );
      await _loadStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.sync),
          SizedBox(width: 8),
          Text('Trạng thái đồng bộ'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats cards
                    _buildStatCard(
                      'Đang chờ',
                      _stats['pending'] ?? 0,
                      Icons.hourglass_empty,
                      Colors.orange,
                    ),
                    const SizedBox(height: 8),
                    _buildStatCard(
                      'Đang xử lý',
                      _stats['processing'] ?? 0,
                      Icons.sync,
                      theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    _buildStatCard(
                      'Lỗi',
                      _stats['failed'] ?? 0,
                      Icons.error_outline,
                      Colors.red,
                    ),
                    
                    // Failed items list
                    if (_failedItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'Các mục lỗi:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      ...(_failedItems.take(5).map((item) => Card(
                        child: ListTile(
                          dense: true,
                          leading: const Icon(Icons.error, color: Colors.red, size: 20),
                          title: Text(
                            '${item.entityType.name} #${item.entityId}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            item.lastError ?? 'Unknown error',
                            style: const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ))),
                      if (_failedItems.length > 5)
                        Text(
                          '... và ${_failedItems.length - 5} mục khác',
                          style: TextStyle(
                            color: theme.colorScheme.outline,
                            fontSize: 14,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        if (_failedItems.isNotEmpty) ...[
          TextButton.icon(
            onPressed: _clearFailed,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Xóa lỗi'),
          ),
          TextButton.icon(
            onPressed: _retryFailed,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Thử lại'),
          ),
        ],
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
        ElevatedButton.icon(
          onPressed: _isSyncing ? null : _syncNow,
          icon: _isSyncing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync, size: 18),
          label: Text(_isSyncing ? 'Đang đồng bộ...' : 'Đồng bộ ngay'),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          Text(
            '$count',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 18,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact sync button for AppBar
class SyncActionButton extends StatelessWidget {
  const SyncActionButton({super.key});

  @override
  Widget build(BuildContext context) {
    return const PendingSyncIndicator(
      iconSize: 22,
    );
  }
}
