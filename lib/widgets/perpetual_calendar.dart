import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';

class PerpetualCalendar extends StatelessWidget {
  const PerpetualCalendar({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dayStr = DateFormat('dd').format(now);
    final monthYearStr = DateFormat('MM / yyyy').format(now);
    final weekdayStr = DateFormat('EEEE', 'vi_VN').format(now);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF6A11CB), Color(0xFF2575FC)]),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.blue.withAlpha(77), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            decoration: BoxDecoration(color: Colors.white.withAlpha(51), borderRadius: BorderRadius.circular(15)),
            child: Text(dayStr, style: AppTextStyles.headline1.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.w900)),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(weekdayStr.toUpperCase(), style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary.withOpacity(0.7), fontWeight: FontWeight.bold)),
              Text("Tháng $monthYearStr", style: AppTextStyles.body1.copyWith(color: AppColors.onPrimary, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
