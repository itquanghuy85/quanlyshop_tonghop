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

  void _loadServices() {
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
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
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

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        border: Border.all(color: Colors.grey[200]!),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: _getColorByRank(index),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  serviceName ?? 'N/A',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Doanh thu: ${MoneyUtils.formatCurrency((totalRevenue ?? 0).toInt())}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Lợi nhuận: ${MoneyUtils.formatCurrency((grossProfit ?? 0).toInt())}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      border: Border.all(color: Colors.blue[200]!),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$count lần',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.green[50],
                                      border: Border.all(color: Colors.green[200]!),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${marginPct?.toStringAsFixed(1) ?? 0}%',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.green,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
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
