import 'package:flutter/material.dart';

import '../services/firebase_rw_stats_service.dart';

class FirebaseRwStatsView extends StatefulWidget {
  const FirebaseRwStatsView({super.key});

  @override
  State<FirebaseRwStatsView> createState() => _FirebaseRwStatsViewState();
}

class _FirebaseRwStatsViewState extends State<FirebaseRwStatsView> {
  FirebaseRwDashboardSnapshot? _snapshot;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final snapshot = await FirebaseRwStatsService.buildSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('THỐNG KÊ DỮ LIỆU READ/WRITE'),
        actions: [
          IconButton(
            tooltip: 'Làm mới',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 36),
              const SizedBox(height: 8),
              Text(
                'Không thể tải thống kê Firebase',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSummaryCard(snapshot),
          if (snapshot.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildWarningCard(snapshot.warnings),
          ],
          const SizedBox(height: 12),
          Text(
            'Theo collection (24h gần nhất)',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          ...snapshot.collectionStats.map(_buildCollectionCard),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(FirebaseRwDashboardSnapshot snapshot) {
    final updatedAt = _formatDateTime(snapshot.generatedAt);
    final shopId = snapshot.shopId ?? 'N/A';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.blue.shade50,
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.query_stats, color: Colors.blue),
              SizedBox(width: 8),
              Text(
                'TỔNG QUAN',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Shop: $shopId'),
          Text('Cập nhật: $updatedAt'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildSummaryChip(
                icon: Icons.cloud,
                label: 'Cloud docs',
                value: _fmt(snapshot.totalCloudDocuments),
                color: Colors.indigo,
              ),
              _buildSummaryChip(
                icon: Icons.remove_red_eye,
                label: 'Reads 24h',
                value: _fmt(snapshot.totalReads24h),
                color: Colors.teal,
              ),
              _buildSummaryChip(
                icon: Icons.upload,
                label: 'Writes 24h',
                value: _fmt(snapshot.totalWriteAttempts24h),
                color: Colors.green,
              ),
              _buildSummaryChip(
                icon: Icons.wifi,
                label: 'Sync collections',
                value: '${snapshot.activeListeners}/${snapshot.totalListeners}',
                color: Colors.deepPurple,
              ),
              _buildSummaryChip(
                icon: Icons.schedule,
                label: 'Queue pending',
                value: _fmt(snapshot.pendingQueue),
                color: Colors.orange,
              ),
              _buildSummaryChip(
                icon: Icons.error_outline,
                label: 'Queue failed',
                value: _fmt(snapshot.failedQueue),
                color: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Lưu ý: Trạng thái ON bên dưới là trạng thái đồng bộ (polling/listener). Reads 24h là tổng đọc từ cloud trong 24 giờ gần nhất nên có thể tăng theo chu kỳ polling hoặc khi sync khởi động lại.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blueGrey.shade700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: $value',
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard(List<String> warnings) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
              const SizedBox(width: 6),
              Text(
                'Cảnh báo',
                style: TextStyle(
                  color: Colors.orange.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...warnings.map(
            (w) => Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('• $w'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionCard(FirebaseCollectionRwStat stat) {
    final hasCloudError = stat.cloudCountError != null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stat.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: stat.listenerActive
                        ? Colors.teal.shade50
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    stat.listenerActive ? 'Polling ON' : 'Sync OFF',
                    style: TextStyle(
                      color: stat.listenerActive
                          ? Colors.teal.shade700
                          : Colors.grey[700],
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              stat.collection,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _metricTag(
                  'Cloud',
                  hasCloudError ? 'N/A' : _fmt(stat.cloudDocumentCount ?? 0),
                  hasCloudError ? Colors.red : Colors.indigo,
                ),
                _metricTag('Reads 24h', _fmt(stat.reads24h), Colors.teal),
                _metricTag(
                  'Writes 24h',
                  _fmt(stat.writeAttempts24h),
                  Colors.green,
                ),
                _metricTag('Success', _fmt(stat.writeSuccess24h), Colors.green),
                _metricTag('Retry', _fmt(stat.writeRetry24h), Colors.orange),
                _metricTag('Failed', _fmt(stat.writeFailed24h), Colors.red),
              ],
            ),
            if (hasCloudError) ...[
              const SizedBox(height: 8),
              Text(
                'Lỗi cloud count: ${stat.cloudCountError}',
                style: TextStyle(color: Colors.red.shade700, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _metricTag(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: color.withOpacity(0.08),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _fmt(int value) {
    final s = value.toString();
    final chars = s.split('').reversed.toList();
    final out = <String>[];
    for (int i = 0; i < chars.length; i++) {
      if (i > 0 && i % 3 == 0) {
        out.add(',');
      }
      out.add(chars[i]);
    }
    return out.reversed.join();
  }

  String _formatDateTime(DateTime dt) {
    String two(int v) => v.toString().padLeft(2, '0');
    final l = dt.toLocal();
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }
}
