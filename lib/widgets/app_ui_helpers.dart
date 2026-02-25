import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Helper class chứa các widgets UI dùng chung cho toàn app
/// Áp dụng style thống nhất như Settings View
class AppUIHelpers {
  /// Gradient colors chủ đạo cho AppBar (2 màu đẹp)
  static const Color gradientStart = Color(0xFF0068FF); // Zalo Blue
  static const Color gradientEnd = Color(0xFF0084FF); // Zalo Blue Light

  /// Alternative gradients
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient blueGradient = LinearGradient(
    colors: [Color(0xFF1565C0), Color(0xFF42A5F5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFF00695C), Color(0xFF26A69A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient orangeGradient = LinearGradient(
    colors: [Color(0xFFE65100), Color(0xFFFF9800)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// AppBar gradient đẹp với 2 màu - STYLE CHÍNH của app
  static PreferredSizeWidget buildGradientAppBar({
    required String title,
    String? subtitle,
    List<Widget>? actions,
    bool showBackButton = true,
    PreferredSizeWidget? bottom,
    LinearGradient? gradient,
  }) {
    return AppBar(
      flexibleSpace: Container(
        decoration: BoxDecoration(gradient: gradient ?? primaryGradient),
      ),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: showBackButton,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
        ],
      ),
      actions: actions,
      bottom: bottom,
    );
  }

  /// AppBar gradient đẹp với title và subtitle (legacy - backward compatible)
  static PreferredSizeWidget gradientAppBar({
    required String title,
    String? subtitle,
    required Color color,
    List<Widget>? actions,
    bool showBackButton = true,
    PreferredSizeWidget? bottom,
  }) {
    return AppBar(
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: showBackButton,
      iconTheme: const IconThemeData(color: Colors.white),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Colors.white,
            ),
          ),
          if (subtitle != null)
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withOpacity(0.8),
              ),
            ),
        ],
      ),
      actions: actions,
      bottom: bottom,
    );
  }

  /// Header card với gradient cho các trang chi tiết
  static Widget headerCard({
    required String title,
    required IconData icon,
    required Color color,
    String? subtitle,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// Section header giống Settings View
  static Widget sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 5),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 12,
          color: Colors.blueGrey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Menu item card với màu sắc
  static Widget menuItemCard({
    required String title,
    required IconData icon,
    required Color color,
    String? subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: color.withOpacity(0.05),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              )
            : null,
        trailing:
            trailing ??
            Icon(
              Icons.arrow_forward_ios,
              color: color.withOpacity(0.5),
              size: 16,
            ),
        onTap: onTap,
      ),
    );
  }

  /// Quick action card 2 cột
  static Widget quickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    int? badgeCount,
  }) {
    return Card(
      color: color.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: BorderSide(color: color.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Stack(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  if (badgeCount != null && badgeCount > 0)
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
                          badgeCount > 9 ? '9+' : badgeCount.toString(),
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
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Stat card cho dashboard
  static Widget statCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color.withOpacity(0.8),
                      fontWeight: FontWeight.w600,
                      fontSize: 10,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(
                    Icons.arrow_forward_ios,
                    color: color.withOpacity(0.4),
                    size: 10,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 9),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Empty state widget
  static Widget emptyState({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[const SizedBox(height: 24), action],
          ],
        ),
      ),
    );
  }

  /// Loading overlay
  static Widget loadingOverlay({String? message}) {
    return Container(
      color: Colors.black.withOpacity(0.3),
      child: Center(
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                if (message != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Confirmation dialog với style mới
  static Future<bool?> showConfirmDialog({
    required BuildContext context,
    required String title,
    required String message,
    String confirmText = 'XÁC NHẬN',
    String cancelText = 'HỦY',
    Color confirmColor = Colors.red,
    IconData? icon,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: confirmColor),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: confirmColor,
                ),
              ),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              confirmText,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  /// Date display helper
  static String formatDate(
    int timestamp, {
    String format = 'dd/MM/yyyy HH:mm',
  }) {
    return DateFormat(
      format,
      'vi',
    ).format(DateTime.fromMillisecondsSinceEpoch(timestamp));
  }

  /// Today date string
  static String get todayString =>
      DateFormat('EEEE, dd/MM/yyyy', 'vi').format(DateTime.now());
}

/// Extension để dễ dàng format số tiền
extension MoneyFormat on int {
  String get vnd => NumberFormat('#,###', 'vi').format(this);
  String get vndFull => '${NumberFormat('#,###', 'vi').format(this)} đ';
}
