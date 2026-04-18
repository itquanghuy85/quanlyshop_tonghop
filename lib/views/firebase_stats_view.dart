import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firebase_stats_service.dart';

/// Màn hình thống kê Firebase R/W chi tiết.
/// Hiển thị số reads/writes hôm nay, per collection, ảnh load, upload bytes,
/// danh sách hoạt động gần đây, và ước tính chi phí.
class FirebaseStatsView extends StatefulWidget {
  const FirebaseStatsView({super.key});

  @override
  State<FirebaseStatsView> createState() => _FirebaseStatsViewState();
}

class _FirebaseStatsViewState extends State<FirebaseStatsView>
    with SingleTickerProviderStateMixin {
  StreamSubscription<FirebaseStatsSnapshot>? _sub;
  FirebaseStatsSnapshot? _snap;
  late TabController _tabs;

  // Ticker cho "live" clock (cập nhật session duration mỗi giây)
  Timer? _ticker;
  Timer? _cloudRefreshTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _snap = FirebaseStatsService.current();
    _sub = FirebaseStatsService.instance.stream.listen((s) {
      if (mounted) setState(() => _snap = s);
    });
    unawaited(FirebaseStatsService.refreshCloudCounts(force: true));
    // Force emit để lấy dữ liệu mới nhất
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _snap = FirebaseStatsService.current());
    });
    _cloudRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(FirebaseStatsService.refreshCloudCounts());
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _cloudRefreshTimer?.cancel();
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snap;
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          '📊 Firebase Monitor',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (snap != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: _LiveDot(active: snap.activeListeners > 0),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Làm mới',
            onPressed: () async {
              await FirebaseStatsService.refreshCloudCounts(force: true);
              if (mounted) {
                setState(() => _snap = FirebaseStatsService.current());
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            tooltip: 'Reset hôm nay',
            onPressed: _confirmReset,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: 'TỔNG QUAN', icon: Icon(Icons.dashboard, size: 16)),
            Tab(text: 'COLLECTION', icon: Icon(Icons.storage, size: 16)),
            Tab(text: 'LOG GẦN ĐÂY', icon: Icon(Icons.history, size: 16)),
          ],
        ),
      ),
      body: snap == null
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(snap: snap),
                _CollectionTab(snap: snap),
                _LogTab(snap: snap),
              ],
            ),
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reset stats'),
        content: const Text('Xóa toàn bộ số liệu hôm nay?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseStatsService.resetToday();
      if (mounted) setState(() => _snap = FirebaseStatsService.current());
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 – TỔNG QUAN
// ─────────────────────────────────────────────────────────────────────────────
class _OverviewTab extends StatelessWidget {
  final FirebaseStatsSnapshot snap;
  const _OverviewTab({required this.snap});

  @override
  Widget build(BuildContext context) {
    final sessionMin = snap.sessionDuration.inMinutes;
    final sessionSec = snap.sessionDuration.inSeconds % 60;
    final readsPerMin = sessionMin > 0
        ? (snap.sessionReads / sessionMin).toStringAsFixed(1)
        : '—';
    final writesPerMin = sessionMin > 0
        ? (snap.sessionWrites / sessionMin).toStringAsFixed(1)
        : '—';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ── Ngày + active listeners ─────────────────────────────
        _DarkCard(
          child: Row(
            children: [
              const Icon(Icons.calendar_today, color: Colors.cyanAccent, size: 16),
              const SizedBox(width: 8),
              Text(
                'Hôm nay: ${DateFormat('dd/MM/yyyy').format(snap.statsDate)}',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: snap.activeListeners > 0
                      ? Colors.green.shade900
                      : Colors.grey.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${snap.activeListeners} listeners',
                  style: TextStyle(
                    color: snap.activeListeners > 0 ? Colors.greenAccent : Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        _DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_done, color: Colors.lightBlueAccent, size: 16),
                  const SizedBox(width: 6),
                  const Text(
                    'Dữ liệu trực tiếp từ Firebase',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  if (snap.isRefreshingCloudCounts)
                    const SizedBox(
                      height: 12,
                      width: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.lightBlueAccent,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Tổng docs: ${_fmt(snap.totalCloudDocuments)} | Thành công: ${snap.cloudCollectionsSuccess} | Lỗi: ${snap.cloudCollectionsError}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                snap.cloudLastUpdated == null
                    ? 'Chưa cập nhật'
                    : 'Cập nhật lúc ${DateFormat('HH:mm:ss dd/MM').format(snap.cloudLastUpdated!)}',
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
              if (snap.cloudCountErrors.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Collections lỗi: ${snap.cloudCountErrors.keys.join(', ')}',
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Hôm nay 4 thẻ chính ────────────────────────────────
        Row(
          children: [
            Expanded(child: _MetricCard(
              icon: Icons.menu_book_rounded,
              color: Colors.cyanAccent,
              label: 'READS (realtime)',
              value: _fmt(snap.totalReads),
              sub: '${(snap.readsQuotaPercent * 100).toStringAsFixed(1)}% quota miễn phí',
              progress: snap.readsQuotaPercent,
              progressColor: _quotaColor(snap.readsQuotaPercent),
            )),
            const SizedBox(width: 8),
            Expanded(child: _MetricCard(
              icon: Icons.edit_note_rounded,
              color: Colors.orangeAccent,
              label: 'WRITES hôm nay',
              value: _fmt(snap.totalWrites),
              sub: '${(snap.writesQuotaPercent * 100).toStringAsFixed(1)}% quota miễn phí',
              progress: snap.writesQuotaPercent,
              progressColor: _quotaColor(snap.writesQuotaPercent),
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _MetricCard(
              icon: Icons.cloud_upload_rounded,
              color: Colors.purpleAccent,
              label: 'UPLOADS hôm nay',
              value: '${snap.totalUploads} file',
              sub: snap.uploadBytesFormatted,
            )),
            const SizedBox(width: 8),
            Expanded(child: _MetricCard(
              icon: Icons.image_rounded,
              color: Colors.tealAccent,
              label: 'ẢNH hôm nay',
              value: '${snap.totalImagesNetwork + snap.totalImagesCached}',
              sub: 'Cache: ${snap.totalImagesCached}  Net: ${snap.totalImagesNetwork}',
              progress: snap.imageCacheHitRate,
              progressColor: Colors.tealAccent,
            )),
          ],
        ),
        const SizedBox(height: 6),
        // ── Ghi chú nguồn dữ liệu ─────────────────────────────
        _DarkCard(
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Reads: chỉ từ realtime listeners. Writes: tất cả. Quota reset mỗi ngày lúc 00:00.',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Ước tính chi phí ────────────────────────────────────
        _DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.attach_money, color: Colors.yellowAccent, size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    'Ước tính chi phí hôm nay',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    snap.estimatedCostToday < 0.001
                        ? '< \$0.001'
                        : '\$${snap.estimatedCostToday.toStringAsFixed(4)}',
                    style: const TextStyle(
                      color: Colors.yellowAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _CostRow(
                label: 'Reads (50K free)',
                used: snap.totalReads,
                cap: 50000,
                unitCost: 0.06,
                unitLabel: '/ 100K docs',
              ),
              const SizedBox(height: 3),
              _CostRow(
                label: 'Writes (20K free)',
                used: snap.totalWrites,
                cap: 20000,
                unitCost: 0.18,
                unitLabel: '/ 100K docs',
              ),
              const SizedBox(height: 3),
              _CostRow(
                label: 'Storage upload',
                used: snap.totalUploadBytes ~/ (1024 * 1024),
                cap: 5 * 1024,
                unitCost: 0.026,
                unitLabel: '/ GB',
                isBytes: true,
                bytesRaw: snap.totalUploadBytes,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Session stats ───────────────────────────────────────
        _DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Session (${sessionMin}m ${sessionSec}s)',
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _SessionStat(
                    icon: Icons.menu_book_rounded,
                    color: Colors.cyanAccent,
                    label: 'Reads',
                    value: _fmt(snap.sessionReads),
                    sub: '$readsPerMin/min',
                  ),
                  _SessionStat(
                    icon: Icons.edit_note_rounded,
                    color: Colors.orangeAccent,
                    label: 'Writes',
                    value: _fmt(snap.sessionWrites),
                    sub: '$writesPerMin/min',
                  ),
                  _SessionStat(
                    icon: Icons.cloud_upload_rounded,
                    color: Colors.purpleAccent,
                    label: 'Uploads',
                    value: '${snap.sessionUploads}',
                    sub: '',
                  ),
                  _SessionStat(
                    icon: Icons.image_rounded,
                    color: Colors.tealAccent,
                    label: 'Ảnh',
                    value: '${snap.sessionImages}',
                    sub: '',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Cache hit rate ───────────────────────────────────────
        _DarkCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tỷ lệ cache ảnh hôm nay',
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _CacheBar(
                cached: snap.totalImagesCached,
                network: snap.totalImagesNetwork,
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _fmt(int n) => NumberFormat('#,###').format(n);

  static Color _quotaColor(double p) {
    if (p < 0.5) return Colors.greenAccent;
    if (p < 0.8) return Colors.yellowAccent;
    return Colors.redAccent;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 – PER COLLECTION
// ─────────────────────────────────────────────────────────────────────────────
class _CollectionTab extends StatelessWidget {
  final FirebaseStatsSnapshot snap;
  const _CollectionTab({required this.snap});

  @override
  Widget build(BuildContext context) {
    // Merge read/write + cloud collections
    final allCollections = <String>{
      ...snap.readsByCollection.keys,
      ...snap.writesByCollection.keys,
      ...snap.cloudDocCounts.keys,
    }.toList()
      ..sort((a, b) {
        final ra = snap.readsByCollection[a] ?? 0;
        final rb = snap.readsByCollection[b] ?? 0;
        return rb.compareTo(ra);
      });

    if (allCollections.isEmpty) {
      return const Center(
        child: Text(
          'Chưa có dữ liệu collection.\nRead/Write sẽ xuất hiện ngay khi app bắt đầu sync.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    final maxReads = allCollections.fold(
      0,
      (m, c) => [m, snap.readsByCollection[c] ?? 0].reduce((a, b) => a > b ? a : b),
    );
    final maxWrites = allCollections.fold(
      0,
      (m, c) => [m, snap.writesByCollection[c] ?? 0].reduce((a, b) => a > b ? a : b),
    );
    final maxCloudDocs = allCollections.fold(
      0,
      (m, c) => [m, snap.cloudDocCounts[c] ?? 0].reduce((a, b) => a > b ? a : b),
    );

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _DarkCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _CollectionSummary(
                icon: Icons.menu_book_rounded,
                color: Colors.cyanAccent,
                label: 'Tổng Reads',
                value: snap.totalReads,
              ),
              Container(width: 1, height: 30, color: Colors.white12),
              _CollectionSummary(
                icon: Icons.edit_note_rounded,
                color: Colors.orangeAccent,
                label: 'Tổng Writes',
                value: snap.totalWrites,
              ),
              Container(width: 1, height: 30, color: Colors.white12),
              _CollectionSummary(
                icon: Icons.storage,
                color: Colors.lightBlueAccent,
                label: 'Cloud Docs',
                value: snap.totalCloudDocuments,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...allCollections.map((col) {
          final reads  = snap.readsByCollection[col]  ?? 0;
          final writes = snap.writesByCollection[col] ?? 0;
          final cloudDocs = snap.cloudDocCounts[col] ?? 0;
          return _CollectionRow(
            collection: col,
            reads: reads,
            writes: writes,
            cloudDocs: cloudDocs,
            maxReads: maxReads,
            maxWrites: maxWrites,
            maxCloudDocs: maxCloudDocs,
          );
        }),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3 – LOG GẦN ĐÂY
// ─────────────────────────────────────────────────────────────────────────────
class _LogTab extends StatefulWidget {
  final FirebaseStatsSnapshot snap;
  const _LogTab({required this.snap});

  @override
  State<_LogTab> createState() => _LogTabState();
}

class _LogTabState extends State<_LogTab> {
  StatsOpType? _filter;

  @override
  Widget build(BuildContext context) {
    var ops = widget.snap.recentOps;
    if (_filter != null) {
      ops = ops.where((o) => o.type == _filter).toList();
    }

    return Column(
      children: [
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              _FilterChip(
                label: 'Tất cả',
                selected: _filter == null,
                color: Colors.white54,
                onTap: () => setState(() => _filter = null),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: '📖 Read',
                selected: _filter == StatsOpType.read,
                color: Colors.cyanAccent,
                onTap: () => setState(() =>
                    _filter = _filter == StatsOpType.read ? null : StatsOpType.read),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: '✏️ Write',
                selected: _filter == StatsOpType.write,
                color: Colors.orangeAccent,
                onTap: () => setState(() =>
                    _filter = _filter == StatsOpType.write ? null : StatsOpType.write),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: '☁️ Upload',
                selected: _filter == StatsOpType.upload,
                color: Colors.purpleAccent,
                onTap: () => setState(() =>
                    _filter = _filter == StatsOpType.upload ? null : StatsOpType.upload),
              ),
              const SizedBox(width: 6),
              _FilterChip(
                label: '🖼️ Ảnh',
                selected: _filter == StatsOpType.imageNetwork ||
                    _filter == StatsOpType.imageCached,
                color: Colors.tealAccent,
                onTap: () => setState(() {
                  if (_filter == StatsOpType.imageNetwork ||
                      _filter == StatsOpType.imageCached) {
                    _filter = null;
                  } else {
                    _filter = StatsOpType.imageNetwork;
                  }
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: ops.isEmpty
              ? const Center(
                  child: Text(
                    'Chưa có hoạt động nào.',
                    style: TextStyle(color: Colors.white38),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: ops.length,
                  itemBuilder: (ctx, i) => _LogRow(op: ops[i]),
                ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _DarkCard extends StatelessWidget {
  final Widget child;
  const _DarkCard({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF111827),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: child,
  );
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String sub;
  final double? progress;
  final Color? progressColor;

  const _MetricCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.sub,
    this.progress,
    this.progressColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFF111827),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white38, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          sub,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        if (progress != null) ...[
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress!,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor!),
              minHeight: 4,
            ),
          ),
        ],
      ],
    ),
  );
}

class _SessionStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String sub;

  const _SessionStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
        if (sub.isNotEmpty)
          Text(sub, style: const TextStyle(color: Colors.white24, fontSize: 9)),
      ],
    ),
  );
}

class _CostRow extends StatelessWidget {
  final String label;
  final int used;
  final int cap;
  final double unitCost;
  final String unitLabel;
  final bool isBytes;
  final int? bytesRaw;

  const _CostRow({
    required this.label,
    required this.used,
    required this.cap,
    required this.unitCost,
    required this.unitLabel,
    this.isBytes = false,
    this.bytesRaw,
  });

  @override
  Widget build(BuildContext context) {
    final billable = (used - cap).clamp(0, 999999999);
    final cost = isBytes
        ? (billable / 1024) * unitCost
        : (billable / 100000) * unitCost;
    final percent = (used / cap).clamp(0.0, 1.0);
    final overQuota = used > cap;

    String usedLabel;
    if (isBytes && bytesRaw != null) {
      final mb = bytesRaw! / (1024 * 1024);
      usedLabel = mb < 1 ? '${(bytesRaw! / 1024).toStringAsFixed(0)} KB' : '${mb.toStringAsFixed(1)} MB';
    } else {
      usedLabel = NumberFormat('#,###').format(used);
    }

    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: percent,
                  backgroundColor: Colors.white10,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    overQuota ? Colors.redAccent : Colors.greenAccent,
                  ),
                  minHeight: 5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                usedLabel,
                style: TextStyle(
                  color: overQuota ? Colors.redAccent : Colors.white38,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          cost < 0.0001 ? 'Free' : '\$${cost.toStringAsFixed(4)}',
          style: TextStyle(
            color: cost < 0.0001 ? Colors.greenAccent : Colors.redAccent,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _CacheBar extends StatelessWidget {
  final int cached;
  final int network;
  const _CacheBar({required this.cached, required this.network});

  @override
  Widget build(BuildContext context) {
    final total = cached + network;
    if (total == 0) {
      return const Text(
        'Chưa có ảnh nào',
        style: TextStyle(color: Colors.white38, fontSize: 12),
      );
    }
    final cacheRatio = cached / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: 16,
            child: Row(
              children: [
                if (cacheRatio > 0)
                  Flexible(
                    flex: (cacheRatio * 100).round(),
                    child: Container(
                      color: Colors.tealAccent.withOpacity(0.8),
                      alignment: Alignment.center,
                      child: cacheRatio > 0.15
                          ? Text(
                              '${(cacheRatio * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
                            )
                          : const SizedBox(),
                    ),
                  ),
                Flexible(
                  flex: ((1 - cacheRatio) * 100).round().clamp(1, 100),
                  child: Container(
                    color: Colors.orangeAccent.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _dot(Colors.tealAccent),
            const SizedBox(width: 4),
            Text('Cache: $cached', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(width: 16),
            _dot(Colors.orangeAccent),
            const SizedBox(width: 4),
            Text('Network: $network', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            const SizedBox(width: 16),
            Text(
              'Hit rate: ${(cacheRatio * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                color: cacheRatio >= 0.7 ? Colors.greenAccent : Colors.yellowAccent,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _dot(Color c) => Container(
    width: 8, height: 8,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
}

class _CollectionRow extends StatelessWidget {
  final String collection;
  final int reads;
  final int writes;
  final int cloudDocs;
  final int maxReads;
  final int maxWrites;
  final int maxCloudDocs;

  const _CollectionRow({
    required this.collection,
    required this.reads,
    required this.writes,
    required this.cloudDocs,
    required this.maxReads,
    required this.maxWrites,
    required this.maxCloudDocs,
  });

  @override
  Widget build(BuildContext context) {
    final readRatio  = maxReads  > 0 ? reads  / maxReads  : 0.0;
    final writeRatio = maxWrites > 0 ? writes / maxWrites : 0.0;
    final cloudRatio = maxCloudDocs > 0 ? cloudDocs / maxCloudDocs : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.folder, color: Colors.white38, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  collection,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                'R: ${NumberFormat('#,###').format(reads)}  W: ${NumberFormat('#,###').format(writes)}  D: ${NumberFormat('#,###').format(cloudDocs)}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 16),
            const Icon(Icons.menu_book_rounded, color: Colors.cyanAccent, size: 11),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: readRatio,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
                  minHeight: 6,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const SizedBox(width: 16),
            const Icon(Icons.edit_note_rounded, color: Colors.orangeAccent, size: 11),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: writeRatio,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(Colors.orangeAccent),
                  minHeight: 6,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            const SizedBox(width: 16),
            const Icon(Icons.storage_rounded, color: Colors.lightBlueAccent, size: 11),
            const SizedBox(width: 4),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: cloudRatio,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation(Colors.lightBlueAccent),
                  minHeight: 6,
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _CollectionSummary extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int value;
  const _CollectionSummary({required this.icon, required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(height: 4),
      Text(
        NumberFormat('#,###').format(value),
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 18),
      ),
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
    ],
  );
}

class _LogRow extends StatelessWidget {
  final StatsOp op;
  const _LogRow({required this.op});

  @override
  Widget build(BuildContext context) {
    Color typeColor;
    switch (op.type) {
      case StatsOpType.read:         typeColor = Colors.cyanAccent; break;
      case StatsOpType.write:        typeColor = Colors.orangeAccent; break;
      case StatsOpType.upload:       typeColor = Colors.purpleAccent; break;
      case StatsOpType.imageNetwork: typeColor = Colors.tealAccent; break;
      case StatsOpType.imageCached:  typeColor = Colors.teal.shade200; break;
    }

    final time = DateFormat('HH:mm:ss').format(op.timestamp);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: typeColor.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Text(op.typeIcon, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: typeColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              op.typeLabel,
              style: TextStyle(
                color: typeColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              op.count > 1 ? '${op.label} (×${op.count})' : op.label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          if (op.bytes != null && op.bytes! > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '${(op.bytes! / 1024).toStringAsFixed(0)} KB',
                style: const TextStyle(color: Colors.white38, fontSize: 10),
              ),
            ),
          Text(
            time,
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.2) : Colors.white10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : Colors.white24),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? color : Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}

class _LiveDot extends StatefulWidget {
  final bool active;
  const _LiveDot({required this.active});

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 1))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) {
      return Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle),
      );
    }
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 8, height: 8,
        decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
      ),
    );
  }
}
