import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';

class NotificationItem extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback onTap;
  final VoidCallback onMarkAsRead;

  const NotificationItem({
    super.key,
    required this.notification,
    required this.onTap,
    required this.onMarkAsRead,
  });

  @override
  Widget build(BuildContext context) {
    final isRead = notification['isRead'] ?? false;
    final type = notification['type'] ?? 'system';
    final createdAt = notification['createdAt'] as Timestamp?;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _getTypeColor(type),
        child: Icon(_getTypeIcon(type), color: Colors.white),
      ),
      title: Text(
        notification['title'] ?? '',
        style: AppTextStyles.body1.copyWith(
          fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(notification['body'] ?? ''),
          if (createdAt != null)
            Text(
              _formatTime(createdAt.toDate()),
              style: AppTextStyles.caption.copyWith(color: AppColors.onSurface.withOpacity(0.6)),
            ),
        ],
      ),
      trailing: isRead
        ? null
        : IconButton(
          icon: const Icon(Icons.circle, color: Colors.blue),
          onPressed: onMarkAsRead,
        ),
      onTap: onTap,
      tileColor: isRead ? null : Colors.blue.withOpacity(0.1),
    );
  }

  Color _getTypeColor(String type) {
    switch (type) {
      case 'repair': return Colors.orange;
      case 'sale': return Colors.green;
      case 'payment': return Colors.blue;
      case 'inventory': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type) {
      case 'repair': return Icons.build;
      case 'sale': return Icons.shopping_cart;
      case 'payment': return Icons.payment;
      case 'inventory': return Icons.inventory;
      default: return Icons.notifications;
    }
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} giờ trước';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} phút trước';
    } else {
      return 'Vừa xong';
    }
  }
}