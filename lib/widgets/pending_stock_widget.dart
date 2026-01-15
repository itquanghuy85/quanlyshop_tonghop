import 'package:flutter/material.dart';
import '../services/stock_entry_service.dart';
import '../views/pending_stock_list_view.dart';

/// Widget hiển thị số lượng hàng chờ xác nhận trên Dashboard
class PendingStockWidget extends StatefulWidget {
  const PendingStockWidget({super.key});

  @override
  State<PendingStockWidget> createState() => _PendingStockWidgetState();
}

class _PendingStockWidgetState extends State<PendingStockWidget> {
  final _service = StockEntryService();
  int _pendingCount = 0;
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      final count = await _service.getPendingCount();
      final stats = await _service.getPendingStats();
      if (mounted) {
        setState(() {
          _pendingCount = count;
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading pending stats: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _openPendingList() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PendingStockListView()),
    ).then((_) => _loadStats());
  }

  @override
  Widget build(BuildContext context) {
    // Không hiển thị nếu không có hàng chờ
    if (!_isLoading && _pendingCount == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade300),
      ),
      child: InkWell(
        onTap: _openPendingList,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: _isLoading
              ? const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Row(
                  children: [
                    // Icon with badge
                    Stack(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Colors.orange.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.pending_actions,
                            size: 28,
                            color: Colors.orange.shade700,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$_pendingCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    // Content
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Hàng chờ xác nhận',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.arrow_forward_ios,
                                size: 14,
                                color: Colors.orange.shade600,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // Stats row
                          Wrap(
                            spacing: 8,
                            children: [
                              if (_stats['phone'] != null && _stats['phone'] > 0)
                                _buildStatChip('📱', _stats['phone']),
                              if (_stats['accessory'] != null && _stats['accessory'] > 0)
                                _buildStatChip('🎧', _stats['accessory']),
                              if (_stats['part'] != null && _stats['part'] > 0)
                                _buildStatChip('🔧', _stats['part']),
                            ],
                          ),
                          if (_stats['oldestDays'] != null && _stats['oldestDays'] > 3) ...[
                            const SizedBox(height: 4),
                            Text(
                              '⚠️ Có phiếu quá ${_stats['oldestDays']} ngày!',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildStatChip(String icon, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$icon $count',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }
}

/// Widget dạng compact hơn cho Dashboard grid
class PendingStockCompactWidget extends StatelessWidget {
  final int pendingCount;
  final VoidCallback? onTap;

  const PendingStockCompactWidget({
    super.key,
    required this.pendingCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingCount == 0) return const SizedBox.shrink();

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.orange.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pending_actions, size: 18, color: Colors.orange.shade700),
            const SizedBox(width: 6),
            Text(
              'Chờ XN',
              style: TextStyle(
                fontSize: 12,
                color: Colors.orange.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$pendingCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stream-based widget với realtime updates
class PendingStockStreamWidget extends StatelessWidget {
  const PendingStockStreamWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final service = StockEntryService();

    return StreamBuilder<int>(
      stream: service.watchPendingCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;

        if (count == 0) {
          return const SizedBox.shrink();
        }

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Colors.orange.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orange.shade300),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PendingStockListView()),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Icon with badge
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.inventory_2,
                          size: 24,
                          color: Colors.orange.shade700,
                        ),
                      ),
                      Positioned(
                        right: -4,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Hàng chờ xác nhận',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        Text(
                          'Nhấn để xem và xác nhận',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.orange.shade600,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
