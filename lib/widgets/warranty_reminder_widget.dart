import 'package:flutter/material.dart';
import '../services/warranty_reminder_service.dart';

/// Widget hiển thị bảo hành sắp hết hạn — dùng cho dashboard
class WarrantyReminderWidget extends StatefulWidget {
  const WarrantyReminderWidget({super.key});

  @override
  State<WarrantyReminderWidget> createState() => _WarrantyReminderWidgetState();
}

class _WarrantyReminderWidgetState extends State<WarrantyReminderWidget> {
  late Future<List<Map<String, dynamic>>> _futureWarranties;

  @override
  void initState() {
    super.initState();
    _futureWarranties = WarrantyReminderService.getUpcomingExpiringWarranties(daysAhead: 30);
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
                const Icon(Icons.verified_user, color: Colors.orange, size: 24),
                const SizedBox(width: 12),
                const Text(
                  'Bảo hành sắp hết hạn',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '30 ngày',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _futureWarranties,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 100,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Text('✅ Không có bảo hành sắp hết hạn'),
                    ),
                  );
                }

                final warranties = snapshot.data!;
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: warranties.length,
                  itemBuilder: (context, index) {
                    final w = warranties[index];
                    final status = w['status'] as String;
                    final daysLeft = w['daysLeft'] as int;
                    final color = status == 'expired'
                        ? Colors.red
                        : status == 'urgent'
                            ? Colors.orange
                            : Colors.amber;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        border: Border(
                          left: BorderSide(color: color, width: 4),
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${w['customerName']} - ${w['model']}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'SĐT: ${w['phone']}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: color,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  daysLeft == 0
                                      ? 'HẾT HẠN'
                                      : 'Còn $daysLeft ngày',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
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
}
