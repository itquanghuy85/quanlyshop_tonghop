import 'package:flutter/material.dart';
import '../services/customer_segment_service.dart';

/// Widget hiển thị Customer Segments — phân khúc khách hàng
class CustomerSegmentsWidget extends StatefulWidget {
  const CustomerSegmentsWidget({Key? key}) : super(key: key);

  @override
  State<CustomerSegmentsWidget> createState() => _CustomerSegmentsWidgetState();
}

class _CustomerSegmentsWidgetState extends State<CustomerSegmentsWidget> {
  late Future<Map<String, int>> _futureSegments;

  @override
  void initState() {
    super.initState();
    _futureSegments = CustomerSegmentService.getSegmentSummary();
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
            const Row(
              children: [
                Icon(Icons.people, color: Colors.purple, size: 24),
                SizedBox(width: 12),
                Text(
                  'Phân khúc khách hàng',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<Map<String, int>>(
              future: _futureSegments,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 150,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(child: Text('Chưa có dữ liệu')),
                  );
                }

                final segments = snapshot.data!;
                final segments_ordered = [
                  (CustomerSegmentService.segmentVip, segments[CustomerSegmentService.segmentVip] ?? 0),
                  (CustomerSegmentService.segmentFrequent, segments[CustomerSegmentService.segmentFrequent] ?? 0),
                  (CustomerSegmentService.segmentRegular, segments[CustomerSegmentService.segmentRegular] ?? 0),
                  (CustomerSegmentService.segmentNew, segments[CustomerSegmentService.segmentNew] ?? 0),
                  (CustomerSegmentService.segmentChurn, segments[CustomerSegmentService.segmentChurn] ?? 0),
                ];

                return GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1.1,
                  children: segments_ordered.map((item) {
                    final label = item.$1;
                    final count = item.$2;
                    final (color, icon, displayLabel) = _getSegmentStyle(label);

                    return GestureDetector(
                      onTap: () {
                        // Navigate to segment list
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Xem $displayLabel ($count KH)')),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          border: Border.all(color: color),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(icon, color: color, size: 32),
                            const SizedBox(height: 8),
                            Text(
                              count.toString(),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              displayLabel,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 11,
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                border: Border.all(color: Colors.blue[200]!),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'VIP: ≥10M + 5 giao dịch | Thường xuyên: 3+ giao dịch/tháng | Churn: >60 ngày',
                      style: TextStyle(fontSize: 11, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  (Color color, IconData icon, String label) _getSegmentStyle(String segment) {
    switch (segment) {
      case 'VIP':
        return (Colors.orange, Icons.diamond, 'VIP');
      case 'FREQUENT':
        return (Colors.green, Icons.trending_up, 'Thường xuyên');
      case 'REGULAR':
        return (Colors.blue, Icons.person, 'Thường');
      case 'NEW':
        return (Colors.cyan, Icons.new_releases, 'Mới');
      case 'CHURN':
        return (Colors.red, Icons.warning, 'Mất tích');
      default:
        return (Colors.grey, Icons.help, segment);
    }
  }
}
