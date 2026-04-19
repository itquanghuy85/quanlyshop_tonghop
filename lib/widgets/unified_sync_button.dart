import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'responsive_wrapper.dart';
import '../data/db_helper.dart';
import '../services/sync_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/sync_health_check.dart';
import '../services/notification_service.dart';
import '../services/data_migration_service.dart';
import '../services/firestore_connectivity_service.dart';
import '../services/sync_audit_service.dart';
import '../services/sync_domain_report_service.dart';
import '../views/firestore_connectivity_test_view.dart';
import '../views/firebase_rw_stats_view.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

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
          style: const TextStyle(
            fontSize: AppTextStyles.overlineSize,
            fontWeight: FontWeight.bold,
          ),
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
    showAppBottomSheet(
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
  FirestoreConnectivityReport? _firestoreConnectivityReport;
  SyncDomainReportSnapshot? _domainReport;
  Map<String, int>? _localStats;
  Map<String, int>? _syncQueueStats;
  bool _isRealtimeSyncActive = false;

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

      // Load sync queue stats
      _syncQueueStats = await _orchestrator.getSyncStats();

      // Check realtime sync status
      _isRealtimeSyncActive = SyncService.isRealTimeSyncActive;

      // Load health check (quick)
      _healthReport = await SyncHealthCheck.runFullCheck();

      // Load Firestore connectivity diagnostics
      _firestoreConnectivityReport =
          await FirestoreConnectivityService.runDiagnostics();

      // Build domain-level sync report
      _domainReport = await SyncDomainReportService.buildReport(
        healthReport: _healthReport,
      );
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
                    const Icon(
                      Icons.cloud_sync,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TRUNG TÂM ĐỒNG BỘ',
                            style: TextStyle(
                              fontSize: AppTextStyles.headline2.fontSize,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Quản lý dữ liệu Local ↔ Cloud',
                            style: TextStyle(
                              fontSize: AppTextStyles.subtitle1.fontSize,
                              color: Colors.grey,
                            ),
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

                          // Domain sync report
                          _buildDomainSyncReportCard(),

                          const SizedBox(height: 16),

                          // Proactive stuck-sync alert banner
                          _buildOperationalAlertCard(),

                          if (_domainReport?.hasOperationalAlerts ?? false)
                            const SizedBox(height: 16),

                          // Main actions
                          const Text(
                            'THAO TÁC ĐỒNG BỘ',
                            style: TextStyle(
                              fontSize: AppTextStyles.subtitle1Size,
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

                          _buildActionTile(
                            icon: Icons.replay,
                            iconColor: Colors.blue,
                            title: 'Khởi động lại Realtime',
                            subtitle:
                                'Kết nối lại listener khi không nhận data',
                            onTap: _handleReinitializeSync,
                          ),

                          // Auto fix button - shown when there are mismatches
                          if (_healthReport != null &&
                              !_healthReport!.isFullyHealthy)
                            _buildActionTile(
                              icon: Icons.auto_fix_high,
                              iconColor: Colors.red,
                              title: '🔧 SỬA TỰ ĐỘNG',
                              subtitle:
                                  'Tự động sửa ${_healthReport!.totalMismatches} bản ghi chưa khớp',
                              onTap: _handleAutoFix,
                            ),

                          const SizedBox(height: 16),

                          // Advanced actions
                          const Text(
                            'NÂNG CAO',
                            style: TextStyle(
                              fontSize: AppTextStyles.subtitle1Size,
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
                            icon: Icons.wifi_find,
                            iconColor: Colors.indigo,
                            title: 'Kiểm tra kết nối Firestore',
                            subtitle: _firestoreConnectivityReport == null
                                ? 'Test mạng, auth và quyền đọc dữ liệu cloud'
                                : _firestoreConnectivityReport!.summary,
                            onTap: _handleOpenFirestoreConnectivityPage,
                          ),

                          _buildActionTile(
                            icon: Icons.query_stats,
                            iconColor: Colors.blueGrey,
                            title: 'Thống kê Firebase Read/Write',
                            subtitle:
                                'Theo collection: cloud docs, realtime reads, write 24h',
                            onTap: _handleOpenFirebaseStats,
                          ),

                          _buildActionTile(
                            icon: Icons.restore,
                            iconColor: Colors.blue,
                            title: 'Khôi phục dữ liệu',
                            subtitle: 'Tìm dữ liệu bị "lạc" do đổi shop',
                            onTap: _handleDataRecovery,
                          ),

                          _buildActionTile(
                            icon: Icons.summarize,
                            iconColor: Colors.deepPurple,
                            title: 'Xuất báo cáo Sync',
                            subtitle:
                                'Tạo file Markdown trạng thái sync để gửi vận hành',
                            onTap: _handleExportSyncReport,
                          ),

                          // Show retry/clear failed when there are failed items
                          if (_syncQueueStats != null &&
                              (_syncQueueStats!['failed'] ?? 0) > 0) ...[
                            _buildActionTile(
                              icon: Icons.refresh,
                              iconColor: Colors.orange,
                              title:
                                  'Thử lại ${_syncQueueStats!['failed']} items lỗi',
                              subtitle: 'Reset và sync lại các items bị failed',
                              onTap: _handleRetryFailed,
                            ),
                            _buildActionTile(
                              icon: Icons.delete_sweep,
                              iconColor: Colors.red,
                              title: 'Xóa items lỗi',
                              subtitle:
                                  'Xóa vĩnh viễn các items không thể sync',
                              onTap: _handleClearFailed,
                            ),
                          ],

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
                    fontSize: AppTextStyles.headline3.fontSize,
                  ),
                ),
                const SizedBox(height: 4),
                if (_healthReport != null) ...[
                  Text(
                    'Local: ${_healthReport!.totalLocalRecords} | Cloud: ${_healthReport!.totalCloudRecords}',
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                    ),
                  ),
                  if (!isHealthy)
                    Text(
                      '${_healthReport!.totalMismatches} bản ghi chưa khớp',
                      style: TextStyle(
                        fontSize: AppTextStyles.body1.fontSize,
                        color: Colors.orange.shade700,
                      ),
                    ),
                ] else
                  Text(
                    'Đang kiểm tra...',
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                    ),
                  ),
                // Show realtime sync status
                Row(
                  children: [
                    Icon(
                      _isRealtimeSyncActive ? Icons.wifi : Icons.wifi_off,
                      size: 12,
                      color: _isRealtimeSyncActive ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _isRealtimeSyncActive ? 'Realtime: ON' : 'Realtime: OFF',
                      style: TextStyle(
                        fontSize: AppTextStyles.body1.fontSize,
                        color: _isRealtimeSyncActive
                            ? Colors.green
                            : Colors.red,
                      ),
                    ),
                    if (_syncQueueStats != null &&
                        (_syncQueueStats!['pending'] ?? 0) > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '| Queue: ${_syncQueueStats!['pending']} pending',
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ],
                    if (_syncQueueStats != null &&
                        (_syncQueueStats!['failed'] ?? 0) > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        ', ${_syncQueueStats!['failed']} failed',
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ],
                ),
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
                  fontSize: AppTextStyles.subtitle1Size,
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
                _buildStatChip(
                  'Sửa chữa',
                  _localStats!['repairs'] ?? 0,
                  Icons.build,
                ),
                _buildStatChip(
                  'Bán hàng',
                  _localStats!['sales'] ?? 0,
                  Icons.shopping_cart,
                ),
                _buildStatChip(
                  'Sản phẩm',
                  _localStats!['products'] ?? 0,
                  Icons.inventory,
                ),
                _buildStatChip(
                  'Chi phí',
                  _localStats!['expenses'] ?? 0,
                  Icons.money_off,
                ),
                _buildStatChip(
                  'Công nợ',
                  _localStats!['debts'] ?? 0,
                  Icons.account_balance,
                ),
              ],
            )
          else
            const Text('Đang tải...'),
        ],
      ),
    );
  }

  Widget _buildDomainSyncReportCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.assessment, size: 18, color: Colors.black87),
              SizedBox(width: 8),
              Text(
                'BÁO CÁO SYNC THEO NGHIỆP VỤ',
                style: TextStyle(
                  fontSize: AppTextStyles.subtitle1Size,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_domainReport == null)
            const Text('Đang tổng hợp báo cáo...')
          else
            ..._domainReport!.domains.map(_buildDomainRow),
        ],
      ),
    );
  }

  Widget _buildDomainRow(DomainSyncReport domain) {
    final statusColor = _domainStatusColor(domain);
    final statusIcon = _domainStatusIcon(domain);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, size: 18, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  domain.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextStyles.subtitle1Size,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  domain.statusLabel,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                    fontSize: AppTextStyles.body1Size,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Queue: ${domain.pendingQueue} chờ | ${domain.processingQueue} đang xử lý | ${domain.failedQueue} lỗi',
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Local chưa sync: ${domain.unsyncedLocal} | Lệch local-cloud: ${domain.mismatchCount} | Tổng local: ${domain.totalLocalRecords}',
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '24h gần nhất: ${domain.recentSuccessCount} thành công | ${domain.recentRetryCount} retry | ${domain.recentFailedCount} lỗi',
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: domain.recentIssueCount > 0
                  ? Colors.orange.shade800
                  : Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            domain.lastSyncAt != null
                ? 'Cập nhật cloud gần nhất: ${_formatSyncTime(domain.lastSyncAt!)}'
                : 'Cập nhật cloud gần nhất: chưa có mốc sync',
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: Colors.grey.shade700,
            ),
          ),
          if (domain.lastFailureAt != null)
            Text(
              'Lần lỗi gần nhất: ${_formatSyncTime(domain.lastFailureAt!)}',
              style: TextStyle(
                fontSize: AppTextStyles.body1.fontSize,
                color: Colors.red.shade700,
              ),
            )
          else if (domain.lastSuccessAt != null)
            Text(
              'Lần thành công gần nhất: ${_formatSyncTime(domain.lastSuccessAt!)}',
              style: TextStyle(
                fontSize: AppTextStyles.body1.fontSize,
                color: Colors.green.shade700,
              ),
            ),
          if (domain.hasStuckQueue)
            Text(
              'Cảnh báo kẹt sync: ${domain.stalePendingQueue} pending + ${domain.staleProcessingQueue} processing > ${SyncDomainReportService.stuckQueueThresholdMinutes} phút${domain.oldestQueueAgeMinutes != null ? ' (cũ nhất ${domain.oldestQueueAgeMinutes} phút)' : ''}',
              style: TextStyle(
                fontSize: AppTextStyles.body1.fontSize,
                color: Colors.deepOrange.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOperationalAlertCard() {
    final report = _domainReport;
    if (report == null || !report.hasOperationalAlerts) {
      return const SizedBox.shrink();
    }

    final alertDomains = report.alertDomains;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.deepOrange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepOrange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.deepOrange.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                'CẢNH BÁO VẬN HÀNH SYNC',
                style: TextStyle(
                  color: Colors.deepOrange.shade800,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextStyles.subtitle1Size,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Phát hiện ${report.totalStuckQueue} item kẹt > ${SyncDomainReportService.stuckQueueThresholdMinutes} phút và ${report.totalFailed} item failed trong queue.',
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: Colors.deepOrange.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          ...alertDomains.map(
            (domain) => Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                '• ${domain.title}: failed=${domain.failedQueue}, kẹt=${domain.staleQueueTotal}',
                style: TextStyle(
                  fontSize: AppTextStyles.body1.fontSize,
                  color: Colors.deepOrange.shade700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _domainStatusColor(DomainSyncReport domain) {
    if (domain.hasError) return Colors.red;
    if (domain.hasStuckQueue) return Colors.deepOrange;
    if (domain.hasPending) return Colors.orange;
    return Colors.green;
  }

  IconData _domainStatusIcon(DomainSyncReport domain) {
    if (domain.hasError) return Icons.cloud_off;
    if (domain.hasStuckQueue) return Icons.warning_amber_rounded;
    if (domain.hasPending) return Icons.cloud_upload;
    return Icons.cloud_done;
  }

  String _formatSyncTime(DateTime dateTime) {
    final d = dateTime.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
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
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: AppTextStyles.headline5.fontSize,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: AppTextStyles.body1.fontSize,
              color: Colors.grey,
            ),
          ),
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
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: AppTextStyles.subtitle1.fontSize),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Future<void> _handleDownload() async {
    final confirm = await _showConfirmDialog(
      title: '📥 TẢI TỪ CLOUD',
      message:
          'Tải toàn bộ dữ liệu shop từ đám mây về máy này.\n\nDữ liệu local sẽ được cập nhật theo cloud.',
      confirmText: 'TẢI XUỐNG',
      confirmColor: Colors.blue,
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang tải từ Cloud...';
    });

    try {
      await SyncService.downloadAllFromCloud(force: true);
      if (mounted) {
        Navigator.pop(context);
        NotificationService.showSnackBar(
          '✅ Đã tải xong dữ liệu từ Cloud!',
          color: Colors.green,
        );
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUpload() async {
    final confirm = await _showConfirmDialog(
      title: '📤 ĐẨY LÊN CLOUD',
      message:
          'Upload dữ liệu chưa đồng bộ từ máy này lên đám mây.\n\nDữ liệu trên cloud sẽ KHÔNG bị xóa.',
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
        NotificationService.showSnackBar(
          '✅ Đã đồng bộ lên Cloud!',
          color: Colors.green,
        );
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAutoFix() async {
    final confirm = await _showConfirmDialog(
      title: '🔧 SỬA TỰ ĐỘNG',
      message:
          'Tự động sửa các bản ghi không khớp giữa Local và Cloud:\n\n'
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
      _domainReport = await SyncDomainReportService.buildReport(
        healthReport: _healthReport,
      );

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

  Future<void> _handleReinitializeSync() async {
    final confirm = await _showConfirmDialog(
      title: '🔄 KHỞI ĐỘNG LẠI REALTIME SYNC',
      message:
          'Kết nối lại tất cả listeners để nhận dữ liệu mới từ máy khác.\n\nDùng khi:\n• Không nhận được đơn mới từ máy khác\n• Biểu tượng sync vàng không chuyển xanh\n• Sau khi mất mạng',
      confirmText: 'KHỞI ĐỘNG LẠI',
      confirmColor: Colors.blue,
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang khởi động lại listeners...';
    });

    try {
      // Check current sync status before reinit
      final isActive = SyncService.isRealTimeSyncActive;
      final status = SyncService.subscriptionStatus;
      debugPrint(
        '📊 Current sync status: isActive=$isActive, subscriptions=$status',
      );

      // Force reinitialize
      await SyncService.forceReinitializeSync();

      // Wait a moment for subscriptions to establish
      await Future.delayed(const Duration(seconds: 2));

      // Download latest data after reinit
      setState(() => _loadingMessage = 'Đang tải dữ liệu mới...');
      await SyncService.downloadAllFromCloud(force: true);

      if (mounted) {
        Navigator.pop(context);
        final newStatus = SyncService.subscriptionStatus;
        NotificationService.showSnackBar(
          '✅ Đã khởi động lại ${newStatus.length} listeners!',
          color: Colors.green,
        );
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFullSync() async {
    final confirm = await _showConfirmDialog(
      title: '🔄 ĐỒNG BỘ 2 CHIỀU',
      message:
          'Upload local lên cloud, sau đó download cloud về local.\n\nĐảm bảo dữ liệu 2 bên giống nhau.',
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
      await SyncService.downloadAllFromCloud(force: true);

      if (mounted) {
        Navigator.pop(context);
        NotificationService.showSnackBar(
          '✅ Đồng bộ 2 chiều hoàn tất!',
          color: Colors.green,
        );
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleRetryFailed() async {
    final confirm = await _showConfirmDialog(
      title: '🔄 THỬ LẠI ITEMS LỖI',
      message:
          'Reset và sync lại tất cả items đã bị đánh dấu failed.\n\nCác items này sẽ được đưa trở lại hàng đợi sync.',
      confirmText: 'THỬ LẠI',
      confirmColor: Colors.orange,
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang reset...';
    });

    try {
      await _orchestrator.retryFailedItems();

      // Trigger sync after retry
      setState(() => _loadingMessage = 'Đang sync...');
      await _orchestrator.syncAll();

      // Reload stats
      _syncQueueStats = await _orchestrator.getSyncStats();
      _domainReport = await SyncDomainReportService.buildReport(
        healthReport: _healthReport,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        NotificationService.showSnackBar(
          '✅ Đã reset và thử sync lại!',
          color: Colors.green,
        );
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleClearFailed() async {
    final confirm = await _showConfirmDialog(
      title: '🗑️ XÓA ITEMS LỖI',
      message:
          '⚠️ CẢNH BÁO: Xóa vĩnh viễn tất cả items bị failed.\n\nDữ liệu local KHÔNG bị xóa, chỉ xóa khỏi hàng đợi sync.\n\nDùng khi items không thể sync và bạn muốn làm sạch queue.',
      confirmText: 'XÓA',
      confirmColor: Colors.red,
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang xóa...';
    });

    try {
      final count = await _orchestrator.clearFailedItems();

      // Reload stats
      _syncQueueStats = await _orchestrator.getSyncStats();
      _domainReport = await SyncDomainReportService.buildReport(
        healthReport: _healthReport,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        NotificationService.showSnackBar(
          '✅ Đã xóa $count items lỗi!',
          color: Colors.green,
        );
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
        _healthReport = report;
        _domainReport = await SyncDomainReportService.buildReport(
          healthReport: report,
        );
        setState(() => _isLoading = false);
        _showDetailedReportDialog(report);
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleFirestoreConnectivityTest() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang kiểm tra kết nối Firestore...';
    });

    try {
      final report = await FirestoreConnectivityService.runDiagnostics();
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _firestoreConnectivityReport = report;
      });

      _showFirestoreConnectivityDialog(report);
      NotificationService.showSnackBar(
        report.isHealthy
            ? '✅ Firestore kết nối ổn định'
            : '⚠️ Firestore cần kiểm tra thêm',
        color: report.isHealthy ? Colors.green : Colors.orange,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      NotificationService.showSnackBar(
        '❌ Lỗi kiểm tra kết nối: $e',
        color: Colors.red,
      );
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
          NotificationService.showSnackBar(
            'Không tìm thấy dữ liệu bị lạc',
            color: Colors.blue,
          );
        } else {
          _showOrphanDataDialog(orphanData);
        }
      }
    } catch (e) {
      NotificationService.showSnackBar('❌ Lỗi: $e', color: Colors.red);
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleOpenFirebaseStats() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FirebaseRwStatsView()),
    );

    if (!mounted) return;
    await _loadInitialData();
  }

  Future<void> _handleOpenFirestoreConnectivityPage() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FirestoreConnectivityTestView()),
    );

    if (!mounted) return;
    await _loadInitialData();
  }

  Future<void> _handleExportSyncReport() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Đang tạo báo cáo sync...';
    });

    try {
      final latestHealth =
          _healthReport ?? await SyncHealthCheck.runFullCheck();
      final latestDomainReport = await SyncDomainReportService.buildReport(
        healthReport: latestHealth,
      );
      final latestQueueStats = await _orchestrator.getSyncStats();
      final events = await SyncAuditService.getRecentEvents(limit: 80);
      final markdown = _buildSyncOperationalMarkdown(
        report: latestDomainReport,
        queueStats: latestQueueStats,
        events: events,
      );

      final reportPath = await SyncAuditService.writeMarkdownReport(
        markdown: markdown,
        prefix: 'sync_operational_report',
      );

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _healthReport = latestHealth;
        _domainReport = latestDomainReport;
        _syncQueueStats = latestQueueStats;
      });

      await _showReportExportDialog(reportPath);
      NotificationService.showSnackBar(
        '✅ Đã tạo báo cáo sync thành công',
        color: Colors.green,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      NotificationService.showSnackBar(
        '❌ Không thể xuất báo cáo sync: $e',
        color: Colors.red,
      );
    }
  }

  String _buildSyncOperationalMarkdown({
    required SyncDomainReportSnapshot report,
    required Map<String, int> queueStats,
    required List<SyncAuditEvent> events,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('# Báo cáo vận hành Sync');
    buffer.writeln('');
    buffer.writeln('- Thời gian tạo: ${_formatSyncTime(report.generatedAt)}');
    buffer.writeln('- Tổng pending queue: ${queueStats['pending'] ?? 0}');
    buffer.writeln('- Tổng processing queue: ${queueStats['processing'] ?? 0}');
    buffer.writeln('- Tổng failed queue: ${queueStats['failed'] ?? 0}');
    buffer.writeln('- Tổng cảnh báo kẹt queue: ${report.totalStuckQueue}');
    buffer.writeln('');

    buffer.writeln('## Trạng thái theo nghiệp vụ');
    for (final domain in report.domains) {
      buffer.writeln('');
      buffer.writeln('### ${domain.title} (${domain.statusLabel})');
      buffer.writeln(
        '- Queue: pending=${domain.pendingQueue}, processing=${domain.processingQueue}, failed=${domain.failedQueue}',
      );
      buffer.writeln(
        '- Queue kẹt: ${domain.staleQueueTotal} (pending=${domain.stalePendingQueue}, processing=${domain.staleProcessingQueue})',
      );
      buffer.writeln(
        '- Local chưa sync: ${domain.unsyncedLocal}, lệch local-cloud: ${domain.mismatchCount}, tổng local: ${domain.totalLocalRecords}',
      );
      buffer.writeln(
        '- 24h gần nhất: success=${domain.recentSuccessCount}, retry=${domain.recentRetryCount}, failed=${domain.recentFailedCount}',
      );
      buffer.writeln(
        '- Mốc cloud gần nhất: ${domain.lastSyncAt != null ? _formatSyncTime(domain.lastSyncAt!) : 'chưa có'}',
      );
      buffer.writeln(
        '- Lỗi gần nhất: ${domain.lastFailureAt != null ? _formatSyncTime(domain.lastFailureAt!) : 'không có'}',
      );
    }

    buffer.writeln('');
    buffer.writeln('## Nhật ký sự kiện sync gần nhất');
    if (events.isEmpty) {
      buffer.writeln('- Chưa có sự kiện trong bảng sync_audit_log.');
    } else {
      buffer.writeln('|Thời gian|Domain|Entity|Kết quả|Queue|Retry|Lỗi|');
      buffer.writeln('|---|---|---|---|---|---:|---|');
      for (final event in events.take(40)) {
        final error = (event.errorMessage ?? '')
            .replaceAll('\n', ' ')
            .replaceAll('|', '/')
            .trim();
        buffer.writeln(
          '|${_formatSyncTime(event.createdAt)}|${_domainTitleFromKey(event.domainKey)}|${event.entityType}#${event.entityId}|${event.outcome}|${event.queueStatus}|${event.retryCount}|${error.isEmpty ? '-' : error}|',
        );
      }
    }

    return buffer.toString();
  }

  String _domainTitleFromKey(String key) {
    switch (key) {
      case 'financial':
        return 'Tài chính';
      case 'repair':
        return 'Đơn sửa';
      case 'inventory':
        return 'Kho';
      case 'sales':
        return 'Bán hàng';
      default:
        return key;
    }
  }

  Future<void> _showReportExportDialog(String reportPath) async {
    final normalizedPath = reportPath.replaceAll('\\', '/');
    final fileName = normalizedPath.split('/').last;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.description, color: Colors.indigo),
            SizedBox(width: 8),
            Text('BÁO CÁO SYNC ĐÃ TẠO'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('File: $fileName'),
            const SizedBox(height: 8),
            Text(
              reportPath,
              style: TextStyle(
                fontSize: AppTextStyles.body1.fontSize,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'close'),
            child: const Text('Đóng'),
          ),
          if (!kIsWeb)
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx, 'open'),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('Mở'),
            ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'share'),
            icon: const Icon(Icons.share, size: 18),
            label: const Text('Chia sẻ'),
          ),
        ],
      ),
    );

    if (action == 'open') {
      await OpenFilex.open(reportPath);
      return;
    }

    if (action == 'share') {
      await SharePlus.instance.share(
        ShareParams(files: [XFile(reportPath)], title: fileName),
      );
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
                fontSize: AppTextStyles.headline3.fontSize,
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
                Text(
                  'Shop ID: ${report.shopId ?? 'N/A'}',
                  style: TextStyle(
                    fontSize: AppTextStyles.body1.fontSize,
                    color: Colors.grey,
                  ),
                ),
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

  void _showFirestoreConnectivityDialog(FirestoreConnectivityReport report) {
    final statusColor = report.isHealthy ? Colors.green : Colors.orange;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(
              report.isHealthy ? Icons.wifi : Icons.wifi_off,
              color: statusColor,
            ),
            const SizedBox(width: 8),
            Text(
              report.isHealthy
                  ? 'KẾT NỐI FIRESTORE TỐT'
                  : 'FIRESTORE CẦN KIỂM TRA',
              style: TextStyle(
                color: statusColor,
                fontSize: AppTextStyles.headline3.fontSize,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tổng quan: ${report.summary}',
                  style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                ),
                const SizedBox(height: 8),
                if (report.latencyMs > 0)
                  Text(
                    'Độ trễ trung bình: ${report.latencyMs} ms',
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                      color: Colors.grey.shade700,
                    ),
                  ),
                const Divider(height: 20),
                _buildConnectivityCheckRow('Internet', report.hasNetwork),
                _buildConnectivityCheckRow(
                  'Đăng nhập Firebase Auth',
                  report.hasAuthenticatedUser,
                ),
                _buildConnectivityCheckRow(
                  'Kết nối Firestore server',
                  report.canReachFirestoreServer,
                ),
                _buildConnectivityCheckRow(
                  'Đọc hồ sơ người dùng',
                  report.canReadCurrentUserDocument,
                ),
                _buildConnectivityCheckRow(
                  report.hasShopContext
                      ? 'Đọc dữ liệu theo shop'
                      : 'Ngữ cảnh shop',
                  report.hasShopContext ? report.canReadShopScopedData : true,
                ),
                if (report.warnings.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Cảnh báo:',
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade800,
                    ),
                  ),
                  ...report.warnings.map(
                    (w) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• $w',
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                    ),
                  ),
                ],
                if (report.errors.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Lỗi phát hiện:',
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade700,
                    ),
                  ),
                  ...report.errors.map(
                    (err) => Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '• $err',
                        style: TextStyle(
                          fontSize: AppTextStyles.body1.fontSize,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  'Khuyến nghị:',
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ...report.recommendations.map(
                  (tip) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '• $tip',
                      style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _handleFirestoreConnectivityTest();
            },
            child: const Text('Kiểm tra lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectivityCheckRow(String title, bool ok) {
    final color = ok ? Colors.green : Colors.red;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.error_outline,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportRow(SyncCheckResult r) {
    final isOk = r.isHealthy;
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
                Text(
                  r.collection,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppTextStyles.headline5.fontSize,
                  ),
                ),
                Text(
                  'Local: ${r.localCount} | Cloud: ${r.cloudCount}',
                  style: TextStyle(
                    fontSize: AppTextStyles.body1.fontSize,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${r.displayPercentage}%',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isOk ? Colors.green : Colors.orange,
              fontSize: AppTextStyles.subtitle1.fontSize,
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
      groupedByShop[info.shopId] =
          (groupedByShop[info.shopId] ?? 0) + info.count;
    }

    final totalCount = orphanData.fold<int>(0, (sum, item) => sum + item.count);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.find_in_page, color: Colors.blue),
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
            ...orphanData.map(
              (info) => Text(
                '• ${info.collection}: ${info.count} (shop: ${info.shopId.substring(0, 8)}...)',
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Để khôi phục, vui lòng vào Cài đặt > Thông tin cửa hàng > Khôi phục dữ liệu và chọn shopId nguồn.',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: AppTextStyles.body1Size,
              ),
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
        title: Text(
          title,
          style: TextStyle(color: confirmColor, fontWeight: FontWeight.bold),
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: confirmColor),
            child: Text(
              confirmText,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
