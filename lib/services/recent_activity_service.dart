import '../data/db_helper.dart';
import 'sync_audit_service.dart';
import 'user_service.dart';

class RecentActivitySource {
  static const String all = 'all';
  static const String financial = 'financial';
  static const String sync = 'sync';
  static const String audit = 'audit';
}

class RecentActivityItem {
  final String id;
  final String source;
  final String domain;
  final String title;
  final String subtitle;
  final int timestamp;
  final int? amount;
  final String? direction;
  final String? status;

  const RecentActivityItem({
    required this.id,
    required this.source,
    required this.domain,
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.amount,
    required this.direction,
    required this.status,
  });
}

class RecentActivitySnapshot {
  final DateTime generatedAt;
  final List<RecentActivityItem> items;

  const RecentActivitySnapshot({
    required this.generatedAt,
    required this.items,
  });

  int get totalCount => items.length;
  int get financialCount =>
      items.where((i) => i.source == RecentActivitySource.financial).length;
  int get syncCount =>
      items.where((i) => i.source == RecentActivitySource.sync).length;
  int get auditCount =>
      items.where((i) => i.source == RecentActivitySource.audit).length;
}

class RecentActivityService {
  static final DBHelper _db = DBHelper();

  static Future<RecentActivitySnapshot> load({
    String sourceFilter = RecentActivitySource.all,
    Duration window = const Duration(hours: 24),
    int limit = 300,
  }) async {
    final now = DateTime.now();
    final threshold = now.subtract(window).millisecondsSinceEpoch;
    final shopId = await UserService.getCurrentShopId();
    final items = <RecentActivityItem>[];

    if (sourceFilter == RecentActivitySource.all ||
        sourceFilter == RecentActivitySource.financial) {
      final rows = await _db.getFinancialActivities(startDate: threshold, limit: 180);
      for (final row in rows) {
        final id = row['firestoreId']?.toString() ??
            'financial_${row['id']?.toString() ?? row['createdAt']?.toString() ?? ''}';
        items.add(
          RecentActivityItem(
            id: id,
            source: RecentActivitySource.financial,
            domain: _financialDomain(row['activityType']?.toString() ?? ''),
            title: row['title']?.toString() ?? 'Hoạt động tài chính',
            subtitle: row['description']?.toString() ??
                row['customerName']?.toString() ??
                '-',
            timestamp: _toInt(row['createdAt']),
            amount: _toNullableInt(row['amount']),
            direction: row['direction']?.toString(),
            status: null,
          ),
        );
      }
    }

    if (sourceFilter == RecentActivitySource.all ||
        sourceFilter == RecentActivitySource.sync) {
      final events = await SyncAuditService.getRecentEvents(limit: 200);
      for (final e in events) {
        final ts = e.createdAt.millisecondsSinceEpoch;
        if (ts < threshold) continue;
        items.add(
          RecentActivityItem(
            id: 'sync_${e.id}',
            source: RecentActivitySource.sync,
            domain: e.domainKey,
            title: _syncTitle(e),
            subtitle: _syncSubtitle(e),
            timestamp: ts,
            amount: null,
            direction: null,
            status: e.outcome,
          ),
        );
      }
    }

    if (sourceFilter == RecentActivitySource.all ||
        sourceFilter == RecentActivitySource.audit) {
      final logs = await _db.getAuditLogs();
      for (final row in logs) {
        final ts = _toInt(row['createdAt']);
        if (ts < threshold) continue;

        final rowShopId = row['shopId']?.toString();
        if (shopId != null && shopId.isNotEmpty && rowShopId != null && rowShopId != shopId) {
          continue;
        }

        final id = row['firestoreId']?.toString() ??
            'audit_${row['id']?.toString() ?? row['createdAt']?.toString() ?? ''}';
        items.add(
          RecentActivityItem(
            id: id,
            source: RecentActivitySource.audit,
            domain: row['targetType']?.toString() ?? 'system',
            title: row['action']?.toString() ?? 'Nhật ký hệ thống',
            subtitle: row['description']?.toString() ??
                row['userName']?.toString() ??
                '-',
            timestamp: ts,
            amount: null,
            direction: null,
            status: null,
          ),
        );
      }
    }

    items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final limited = items.length > limit ? items.take(limit).toList() : items;

    return RecentActivitySnapshot(generatedAt: now, items: limited);
  }

  static String _financialDomain(String activityType) {
    final t = activityType.toUpperCase();
    if (t == 'SALE') return 'sales';
    if (t == 'EXPENSE') return 'financial';
    if (t == 'PURCHASE') return 'inventory';
    if (t == 'DEBT_COLLECT' || t == 'DEBT_PAY') return 'financial';
    if (t == 'SETTLEMENT') return 'financial';
    return 'financial';
  }

  static String _syncTitle(SyncAuditEvent event) {
    return 'Sync ${event.entityType}#${event.entityId}';
  }

  static String _syncSubtitle(SyncAuditEvent event) {
    final error = (event.errorMessage ?? '').trim();
    if (error.isNotEmpty) {
      return '${event.operation} • ${event.outcome} • $error';
    }
    return '${event.operation} • ${event.outcome}';
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static int? _toNullableInt(dynamic value) {
    final v = _toInt(value);
    if (v == 0) return null;
    return v;
  }
}
