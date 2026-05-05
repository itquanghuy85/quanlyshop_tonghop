import 'package:flutter/material.dart';
import '../services/top_services_report_service.dart';
import '../utils/money_utils.dart';

/// Widget hiển thị Top Services — dịch vụ lãi nhất
/// Hiển thị top 10 dịch vụ theo doanh thu, lợi nhuận, hoặc tần suất
class TopServicesWidget extends StatefulWidget {
  final DateTime? startDate;
  final DateTime? endDate;
  final String sortBy; // 'revenue', 'profit', 'frequency'

  const TopServicesWidget({
    super.key,
    this.startDate,
    this.endDate,
    this.sortBy = 'revenue',
  });

  @override
  State<TopServicesWidget> createState() => _TopServicesWidgetState();
}

class _TopServicesWidgetState extends State<TopServicesWidget> {
  late Future<List<Map<String, dynamic>>> _futureServices;
  late String _sortBy;

  @override
  void initState() {
    super.initState();
    _sortBy = widget.sortBy;
    _loadServices();
  }

  @override
  void didUpdateWidget(covariant TopServicesWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final rangeChanged = oldWidget.startDate != widget.startDate ||
        oldWidget.endDate != widget.endDate;
    final sortChanged = oldWidget.sortBy != widget.sortBy;
    if (rangeChanged || sortChanged) {
      _sortBy = widget.sortBy;
      _loadServices();
    }
  }

  void _loadServices() {
    debugPrint(
      '[TopServicesWidget] _loadServices sortBy=$_sortBy, '
      'startDate=${widget.startDate?.toIso8601String()}, '
      'endDate=${widget.endDate?.toIso8601String()}',
    );
    switch (_sortBy) {
      case 'profit':
        _futureServices = TopServicesReportService.getTopServicesByProfit(
          startDate: widget.startDate,
          endDate: widget.endDate,
        );
        break;
      case 'frequency':
        _futureServices = TopServicesReportService.getTopServicesByFrequency(
          startDate: widget.startDate,
          endDate: widget.endDate,
        );
        break;
      default:
        _futureServices = TopServicesReportService.getTopServicesByRevenue(
          startDate: widget.startDate,
          endDate: widget.endDate,
        );
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, color: Colors.green, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Dịch vụ lãi nhất',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                PopupMenuButton<String>(
                  initialValue: _sortBy,
                  onSelected: (value) {
                    setState(() => _sortBy = value);
                    _loadServices();
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'revenue',
                      child: Text('Doanh thu'),
                    ),
                    const PopupMenuItem(
                      value: 'profit',
                      child: Text('Lợi nhuận'),
                    ),
                    const PopupMenuItem(
                      value: 'frequency',
                      child: Text('Tần suất'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _futureServices,
              builder: (context, snapshot) {
                debugPrint(
                  '[TopServicesWidget] Future state=${snapshot.connectionState} '
                  'hasData=${snapshot.hasData} hasError=${snapshot.hasError}',
                );
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (snapshot.hasError) {
                  debugPrint('[TopServicesWidget] Future error=${snapshot.error}');
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text('Lỗi tải dữ liệu dịch vụ')),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text('Chưa có dữ liệu')),
                  );
                }

                final services = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: services.length,
                  itemBuilder: (context, index) {
                    final service = services[index];
                    final serviceName = service['serviceName'] as String?;
                    final count = service['count'] as int?;
                    final totalRevenue = service['totalRevenue'] as int?;
                    final grossProfit = service['grossProfit'] as int?;
                    final marginPct = service['profitMarginPct'] as double?;

                    final summary =
                        '${serviceName ?? 'N/A'} · LN ${MoneyUtils.formatCurrency((grossProfit ?? 0).toInt())} · DT ${MoneyUtils.formatCurrency((totalRevenue ?? 0).toInt())} · ${count ?? 0} lần · ${(marginPct ?? 0).toStringAsFixed(1)}%';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 22,
                            child: Text(
                              '${index + 1}.',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _getColorByRank(index),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _getColorByRank(int index) {
    if (index == 0) return Colors.amber;
    if (index == 1) return Colors.grey;
    if (index == 2) return Colors.orange;
    return Colors.blue;
  }
}
