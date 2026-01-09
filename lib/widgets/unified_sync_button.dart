import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../data/db_helper.dart';
import '../services/sync_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/sync_health_check.dart';
import '../services/notification_service.dart';
import '../services/data_migration_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';

/// Widget hiển thị nút sync thống nhất trên AppBar
/// Gom tất cả chức năng sync vào một nơi
class UnifiedSyncButton extends StatefulWidget {
  const UnifiedSyncButton({super.key});

  @override
  State<UnifiedSyncButton> createState() => _UnifiedSyncButtonState();
}

class _UnifiedSyncButtonState extends State<UnifiedSyncButton>
    with SingleTickerProviderStateMixin {
  final SyncOrchestrator _orchestrator = SyncOrchestrator();
  
  StreamSubscription<int>? _countSubscription;
  StreamSubscription<SyncStatus>? _statusSubscription;
  late AnimationController _animationController;
  
  int _pendingCount = 0;
  SyncStatus _status = SyncStatus.synced;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    
    _pendingCount = _orchestrator.pendingCount;
    _countSubscription = _orchestrator.pendingCountStream.listen((count) {
      if (mounted) setState(() => _pendingCount = count);
    });
    
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
    _countSubscription?.cancel();
    _statusSubscription?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color iconColor;
    
    switch (_status) {
      case SyncStatus.synced:
        icon = Icons.cloud_done;
        iconColor = AppColors.success;
        break;
      case SyncStatus.hasPending:
        icon = Icons.cloud_upload;
        iconColor = Colors.orange;
        break;
      case SyncStatus.syncing:
        icon = Icons.sync;
        iconColor = AppColors.primary;
        break;
      case SyncStatus.noNetwork:
        icon = Icons.cloud_off;
        iconColor = Colors.grey;
        break;
      case SyncStatus.error:
        icon = Icons.cloud_off;
        iconColor = Colors.red;
        break;
    }
    
    Widget iconWidget = AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return Transform.rotate(
          angle: _status == SyncStatus.syncing
              ? _animationController.value * 2 * 3.14159
              : 0,
          child: Icon(icon, size: 24, color: iconColor),
        );
      },
    );
    
    // Badge khi có pending
    if (_pendingCount > 0 && _status != SyncStatus.syncing) {
      iconWidget = Badge(
        label: Text(
          _pendingCount > 99 ? '99+' : '$_pendingCount',
          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.red,
        child: iconWidget,
      );
    }
    
    return IconButton(
      onPressed: () => _showSyncCenter(context),
      icon: iconWidget,
      tooltip: 'Trung tâm đồng bộ',
    );
  }
  
  void _showSyncCenter(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const SyncCenterSheet(),
    );
  }
}

/// Bottom sheet chứa tất cả chức năng sync
class SyncCenterSheet extends StatefulWidget {
  const SyncCenterSheet({super.key});

  @override
  State<SyncCenterSheet> createState() => _SyncCenterSheetState();
}

class _SyncCenterSheetState extends State<SyncCenterSheet> {
  final SyncOrchestrator _orchestrator = SyncOrchestrator();
  
  bool _isLoading = false;
  String _loadingMessage = '';
  SyncHealthReport? _healthReport;
  Map<String, int>? _localStats;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang kiểm tra...';
    });
    
    try {
      // Load local stats
      final db = DBHelper();
      final repairs = await db.getAllRepairs();
      final sales = await db.getAllSales();
      final products = await db.getAllProducts();
      final expenses = await db.getAllExpenses();
      final debts = await db.getAllDebts();
      
      _localStats = {
        'repairs': repairs.length,
        'sales': sales.length,
        'products': products.length,
        'expenses': expenses.length,
        'debts': debts.length,
      };
      
      // Load health check (quick)
      _healthReport = await SyncHealthCheck.runFullCheck();
    } catch (e) {
      debugPrint('Error loading sync data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // Title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.cloud_sync, color: AppColors.primary, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TRUNG TÂM ĐỒNG BỘ',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Quản lý dữ liệu Local ↔ Cloud',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              
              const Divider(),
              
              // Content
              Expanded(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(_loadingMessage),
                          ],
                        ),
                      )
                    : ListView(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        children: [
                          // Health status card
                          _buildHealthStatusCard(),
                          
                          const SizedBox(height: 16),
                          
                          // Local stats
                          _buildLocalStatsCard(),
                          
                          const SizedBox(height: 16),
                          
                          // Main actions
                          const Text(
                            'THAO TÁC ĐỒNG BỘ',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          
                          _buildActionTile(
                            icon: Icons.cloud_download,
                            iconColor: Colors.blue,
                            title: 'Tải từ Cloud',
                            subtitle: 'Download dữ liệu từ đám mây về máy',
                            onTap: _handleDownload,
                          ),
                          
                          _buildActionTile(
                            icon: Icons.cloud_upload,
                            iconColor: Colors.green,
                            title: 'Đẩy lên Cloud',
                            subtitle: 'Upload dữ liệu chưa sync lên đám mây',
                            onTap: _handleUpload,
                          ),
                          
                          _buildActionTile(
                            icon: Icons.sync,
                            iconColor: Colors.orange,
                            title: 'Đồng bộ 2 chiều',
                            subtitle: 'Upload + Download để đồng nhất dữ liệu',
                            onTap: _handleFullSync,
                          ),
                          
                          // Auto fix button - shown when there are mismatches
                          if (_healthReport != null && !_healthReport!.isFullyHealthy)
                            _buildActionTile(
                              icon: Icons.auto_fix_high,
                              iconColor: Colors.red,
                              title: '🔧 SỬA TỰ ĐỘNG',
                              subtitle: 'Tự động sửa ${_healthReport!.totalMismatches} bản ghi chưa khớp',
                              onTap: _handleAutoFix,
                            ),
                          
                          const SizedBox(height: 16),
                          
                          // Advanced actions
                          const Text(
                            'NÂNG CAO',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          
                          _buildActionTile(
                            icon: Icons.health_and_safety,
                            iconColor: Colors.teal,
                            title: 'Kiểm tra chi tiết',
                            subtitle: 'So sánh từng bảng Local vs Cloud',
                            onTap: _handleDetailedCheck,
                          ),
                          
                          _buildActionTile(
                            icon: Icons.restore,
                            iconColor: Colors.purple,
                            title: 'Khôi phục dữ liệu',
                            subtitle: 'Tìm dữ liệu bị "lạc" do đổi shop',
                            onTap: _handleDataRecovery,
                          ),
                          
                          const SizedBox(height: 32),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHealthStatusCard() {
    final isHealthy = _healthReport?.isFullyHealthy ?? true;
    final color = isHealthy ? Colors.green : Colors.orange;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isHealthy ? Icons.check_circle : Icons.warning,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isHealthy ? 'ĐỒNG BỘ TỐT' : 'CẦN ĐỒNG BỘ',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                if (_healthReport != null) ...[
                  Text(
                    'Local: ${_healthReport!.totalLocalRecords} | Cloud: ${_healthReport!.totalCloudRecords}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (!isHealthy)
                    Text(
                      '${_healthReport!.totalMismatches} bản ghi chưa khớp',
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                    ),
                ] else
                  const Text('Đang kiểm tra...', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalStatsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.storage, size: 18, color: Colors.grey),
              SizedBox(width: 8),
              Text(
                'DỮ LIỆU LOCAL',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_localStats != null)
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _buildStatChip('Sửa chữa', _localStats!['repairs'] ?? 0, Icons.build),
                _buildStatChip('Bán hàng', _localStats!['sales'] ?? 0, Icons.shopping_cart),
                _buildStatChip('Sản phẩm', _localStats!['products'] ?? 0, Icons.inventory),
                _buildStatChip('Chi phí', _localStats!['expenses'] ?? 0, Icons.money_off),
                _buildStatChip('Công nợ', _localStats!['debts'] ?? 0, Icons.account_balance),
              ],
            )
          else
            const Text('Đang tải...'),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, int count, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Future<void> _handleDownload() async {
    final confirm = await _showConfirmDialog(
      title: '📥 TẢI TỪ CLOUD',
      message: 'Tải toàn bộ dữ liệu shop từ đám mây về máy này.\n\nDữ liệu local sẽ được cập nhật theo cloud.',
      confirmText: 'TẢI XUỐNG',
      confirmColor: Colors.blue,
    );
    
    if (confirm != true) return;
    
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang tải từ Cloud...';
    });
    
    try {
      await SyncService.downloadAllFromCloud();
      if (mounted) {
        Navigator.pop(context);
        NotificationService.showSnackBar('✅ Đã tải xong dữ liệu từ Cloud!', color: Colors.green);
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUpload() async {
    final confirm = await _showConfirmDialog(
      title: '📤 ĐẨY LÊN CLOUD',
      message: 'Upload dữ liệu chưa đồng bộ từ máy này lên đám mây.\n\nDữ liệu trên cloud sẽ KHÔNG bị xóa.',
      confirmText: 'UPLOAD',
      confirmColor: Colors.green,
    );
    
    if (confirm != true) return;
    
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang đẩy lên Cloud...';
    });
    
    try {
      await SyncService.syncAllToCloud();
      // Also sync pending queue
      await _orchestrator.syncAll();
      if (mounted) {
        Navigator.pop(context);
        NotificationService.showSnackBar('✅ Đã đồng bộ lên Cloud!', color: Colors.green);
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAutoFix() async {
    final confirm = await _showConfirmDialog(
      title: '🔧 SỬA TỰ ĐỘNG',
      message: 'Tự động sửa các bản ghi không khớp giữa Local và Cloud:\n\n'
          '1. Upload dữ liệu local chưa sync\n'
          '2. Download TẤT CẢ dữ liệu từ Cloud\n'
          '3. Đánh dấu đã đồng bộ\n\n'
          'Quá trình này có thể mất vài phút.',
      confirmText: 'SỬA NGAY',
      confirmColor: Colors.red,
    );
    
    if (confirm != true) return;
    
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang sửa tự động...';
    });
    
    try {
      final fixedCount = await SyncHealthCheck.autoFix();
      
      // Reload health report
      _healthReport = await SyncHealthCheck.runFullCheck();
      
      if (mounted) {
        setState(() => _isLoading = false);
        
        final isFixed = _healthReport?.isFullyHealthy ?? false;
        if (isFixed) {
          NotificationService.showSnackBar(
            '✅ Đã sửa xong! Tải $fixedCount bản ghi mới.',
            color: Colors.green,
          );
        } else {
          NotificationService.showSnackBar(
            '⚠️ Đã xử lý $fixedCount bản ghi. Còn ${_healthReport?.totalMismatches ?? 0} chưa khớp.',
            color: Colors.orange,
          );
        }
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFullSync() async {
    final confirm = await _showConfirmDialog(
      title: '🔄 ĐỒNG BỘ 2 CHIỀU',
      message: 'Upload local lên cloud, sau đó download cloud về local.\n\nĐảm bảo dữ liệu 2 bên giống nhau.',
      confirmText: 'ĐỒNG BỘ',
      confirmColor: Colors.orange,
    );
    
    if (confirm != true) return;
    
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Bước 1: Upload...';
    });
    
    try {
      await SyncService.syncAllToCloud();
      await _orchestrator.syncAll();
      
      setState(() => _loadingMessage = 'Bước 2: Download...');
      await SyncService.downloadAllFromCloud();
      
      if (mounted) {
        Navigator.pop(context);
        NotificationService.showSnackBar('✅ Đồng bộ 2 chiều hoàn tất!', color: Colors.green);
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDetailedCheck() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang kiểm tra chi tiết...';
    });
    
    try {
      final report = await SyncHealthCheck.runFullCheck();
      if (mounted) {
        setState(() => _isLoading = false);
        _showDetailedReportDialog(report);
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleDataRecovery() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      NotificationService.showSnackBar('Vui lòng đăng nhập', color: Colors.red);
      return;
    }
    
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang tìm dữ liệu...';
    });
    
    try {
      final orphanData = await DataMigrationService.findOrphanData();
      
      if (mounted) {
        setState(() => _isLoading = false);
        
        if (orphanData.isEmpty) {
          NotificationService.showSnackBar('Không tìm thấy dữ liệu bị lạc', color: Colors.blue);
        } else {
          _showOrphanDataDialog(orphanData);
        }
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  void _showDetailedReportDialog(SyncHealthReport report) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              report.isFullyHealthy ? Icons.check_circle : Icons.warning,
              color: report.isFullyHealthy ? Colors.green : Colors.orange,
            ),
            const SizedBox(width: 8),
            Text(
              report.isFullyHealthy ? 'ĐỒNG BỘ TỐT' : 'CẦN ĐỒNG BỘ',
              style: TextStyle(
                color: report.isFullyHealthy ? Colors.green : Colors.orange,
                fontSize: 16,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Shop ID: ${report.shopId ?? 'N/A'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                const Divider(),
                ...report.results.map((r) => _buildReportRow(r)),
              ],
            ),
          ),
        ),
        actions: [
          if (!report.isFullyHealthy)
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _handleFullSync();
              },
              child: const Text('SỬA LỖI'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );
  }

  Widget _buildReportRow(SyncCheckResult r) {
    final isOk = r.syncPercentage >= 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check : Icons.warning,
            color: isOk ? Colors.green : Colors.orange,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.collection, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text('Local: ${r.localCount} | Cloud: ${r.cloudCount}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          Text(
            '${r.syncPercentage.toStringAsFixed(0)}%',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isOk ? Colors.green : Colors.orange,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _showOrphanDataDialog(List<OrphanDataInfo> orphanData) {
    // Group by shopId
    final groupedByShop = <String, int>{};
    for (var info in orphanData) {
      groupedByShop[info.shopId] = (groupedByShop[info.shopId] ?? 0) + info.count;
    }
    
    final totalCount = orphanData.fold<int>(0, (sum, item) => sum + item.count);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.find_in_page, color: Colors.purple),
            SizedBox(width: 8),
            Text('DỮ LIỆU TÌM THẤY'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tìm thấy $totalCount bản ghi bị lạc:'),
            const SizedBox(height: 12),
            ...orphanData.map((info) => Text('• ${info.collection}: ${info.count} (shop: ${info.shopId.substring(0, 8)}...)')),
            const SizedBox(height: 12),
            const Text(
              'Để khôi phục, vui lòng vào Cài đặt > Thông tin cửa hàng > Khôi phục dữ liệu và chọn shopId nguồn.',
              style: TextStyle(fontStyle: FontStyle.italic, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmText,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: TextStyle(color: confirmColor, fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmText, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
