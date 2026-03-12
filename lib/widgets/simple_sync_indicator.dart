import 'dart:async';
import 'package:flutter/material.dart';
import '../services/sync_orchestrator.dart';
import '../services/sync_service.dart';
import '../theme/app_colors.dart';

/// Widget hiển thị trạng thái sync đơn giản
/// - Tự động sync ở background
/// - Tap để force sync nếu cần
/// - Hiện icon theo trạng thái: ✓ synced, ⟳ syncing, ⚠ pending/error
class SimpleSyncIndicator extends StatefulWidget {
  const SimpleSyncIndicator({super.key});

  @override
  State<SimpleSyncIndicator> createState() => _SimpleSyncIndicatorState();
}

class _SimpleSyncIndicatorState extends State<SimpleSyncIndicator>
    with SingleTickerProviderStateMixin {
  final SyncOrchestrator _orchestrator = SyncOrchestrator();

  StreamSubscription<int>? _countSubscription;
  StreamSubscription<SyncStatus>? _statusSubscription;
  late AnimationController _animationController;

  int _pendingCount = 0;
  SyncStatus _status = SyncStatus.synced;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _pendingCount = _orchestrator.pendingCount;
    _countSubscription = _orchestrator.pendingCountStream.listen((count) {
      if (mounted) {
        setState(() => _pendingCount = count);
        // Auto sync khi có pending và không đang sync
        if (count > 0 && !_isSyncing) {
          _autoSync();
        }
      }
    });

    _statusSubscription = _orchestrator.syncStatusStream.listen((status) {
      if (mounted) {
        setState(() {
          _status = status;
          _isSyncing = status == SyncStatus.syncing;
        });
        if (status == SyncStatus.syncing) {
          _animationController.repeat();
        } else {
          _animationController.stop();
          _animationController.reset();
        }
      }
    });

    // Auto sync khi khởi tạo (sau 2s để app load xong)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) _autoSync();
    });
  }

  @override
  void dispose() {
    _countSubscription?.cancel();
    _statusSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  /// Auto sync - không hiện thông báo, chạy ngầm
  Future<void> _autoSync() async {
    if (_isSyncing) return;

    try {
      // Chỉ push local changes — real-time listeners handle downloads
      await SyncService.syncAllToCloud();
    } catch (e) {
      debugPrint('Auto sync error: $e');
    }
  }

  /// Force sync khi user tap - có feedback nhẹ
  Future<void> _forceSync() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);

    try {
      if (_status == SyncStatus.error) {
        await _orchestrator.retryFailedItems();
      }
      // Upload local changes
      await SyncService.syncAllToCloud();
      // Download from cloud (user-triggered)
      await SyncService.downloadAllFromCloud(force: true);

      if (mounted) {
        // Feedback nhẹ - không dùng SnackBar để tránh spam
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Đồng bộ hoàn tất'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Force sync error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi đồng bộ: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Xác định icon và màu theo trạng thái
    IconData icon;
    Color iconColor;
    String tooltip;

    if (_isSyncing || _status == SyncStatus.syncing) {
      icon = Icons.sync;
      iconColor = AppColors.primary;
      tooltip = 'Đang đồng bộ...';
    } else if (_status == SyncStatus.noNetwork) {
      icon = Icons.cloud_off;
      iconColor = Colors.grey;
      tooltip = 'Không có mạng';
    } else if (_status == SyncStatus.error) {
      icon = Icons.cloud_off;
      iconColor = Colors.red;
      tooltip = 'Lỗi đồng bộ - Bấm để thử lại';
    } else if (_pendingCount > 0 || _status == SyncStatus.hasPending) {
      icon = Icons.cloud_upload;
      iconColor = Colors.orange;
      tooltip = 'Có $_pendingCount thay đổi chưa đồng bộ';
    } else {
      icon = Icons.cloud_done;
      iconColor = AppColors.success;
      tooltip = 'Đã đồng bộ';
    }

    // Widget icon với animation khi đang sync
    Widget iconWidget;
    if (_isSyncing || _status == SyncStatus.syncing) {
      iconWidget = AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return Transform.rotate(
            angle: _animationController.value * 2 * 3.14159,
            child: Icon(icon, size: 22, color: iconColor),
          );
        },
      );
    } else {
      iconWidget = Icon(icon, size: 22, color: iconColor);
    }

    // Badge nhỏ khi có pending (không hiện số, chỉ chấm đỏ)
    if (_pendingCount > 0 && !_isSyncing && _status != SyncStatus.syncing) {
      iconWidget = Badge(
        smallSize: 8,
        backgroundColor: Colors.red,
        child: iconWidget,
      );
    }

    return IconButton(
      onPressed: _forceSync,
      icon: iconWidget,
      tooltip: tooltip,
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
    );
  }
}
