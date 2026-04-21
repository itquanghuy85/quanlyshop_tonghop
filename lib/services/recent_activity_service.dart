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
      final rows = await _db.getFinancialActivities(
        startDate: threshold,
        limit: 180,
      );
      for (final row in rows) {
        final id =
            row['firestoreId']?.toString() ??
            'financial_${row['id']?.toString() ?? row['createdAt']?.toString() ?? ''}';
        items.add(
          RecentActivityItem(
            id: id,
            source: RecentActivitySource.financial,
            domain: _financialDomain(row['activityType']?.toString() ?? ''),
            title: _financialTitle(row),
            subtitle: _financialSubtitle(row),
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
        if (shopId != null &&
            shopId.isNotEmpty &&
            rowShopId != null &&
            rowShopId != shopId) {
          continue;
        }

        final id =
            row['firestoreId']?.toString() ??
            'audit_${row['id']?.toString() ?? row['createdAt']?.toString() ?? ''}';
        items.add(
          RecentActivityItem(
            id: id,
            source: RecentActivitySource.audit,
            domain: row['targetType']?.toString() ?? 'system',
            title: _auditTitle(row),
            subtitle: _auditSubtitle(row),
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
    if (t == 'REPAIR') return 'repair';
    if (t == 'EXPENSE') return 'financial';
    if (t == 'PURCHASE') return 'inventory';
    if (t == 'DEBT_COLLECT' || t == 'DEBT_PAY') return 'financial';
    if (t == 'SETTLEMENT') return 'financial';
    return 'financial';
  }

  static String _financialTitle(Map<String, dynamic> row) {
    final rawTitle = row['title']?.toString().trim() ?? '';
    if (rawTitle.isNotEmpty && !_looksTechnical(rawTitle)) {
      return rawTitle;
    }

    final type = (row['activityType']?.toString() ?? '').toUpperCase();
    final direction = (row['direction']?.toString() ?? '').toUpperCase();

    switch (type) {
      case 'SALE':
        return 'Bán hàng';
      case 'REPAIR':
        return 'Sửa chữa';
      case 'EXPENSE':
        return direction == 'IN' ? 'Thu khác' : 'Chi phí';
      case 'PURCHASE':
        return 'Nhập hàng';
      case 'DEBT_COLLECT':
        return 'Thu nợ khách hàng';
      case 'DEBT_PAY':
        return 'Trả nợ nhà cung cấp';
      case 'SETTLEMENT':
        return 'Thu tất toán trả góp';
      case 'PAYMENT_REQUEST_IN':
        return 'Nhận tiền yêu cầu đóng tiền';
      case 'PAYMENT_REQUEST_OUT':
        return 'Chi tiền yêu cầu đóng tiền';
      default:
        return 'Hoạt động tài chính';
    }
  }

  static String _financialSubtitle(Map<String, dynamic> row) {
    final description = row['description']?.toString().trim() ?? '';
    if (description.isNotEmpty && !_looksTechnical(description)) {
      return description;
    }

    final customer = row['customerName']?.toString().trim() ?? '';
    final phone = row['phone']?.toString().trim() ?? '';
    final note = row['note']?.toString().trim() ?? '';
    final parts = <String>[];

    if (customer.isNotEmpty) parts.add(customer);
    if (phone.isNotEmpty) parts.add(phone);
    if (note.isNotEmpty && !_looksTechnical(note)) parts.add(note);

    if (parts.isNotEmpty) return parts.join(' • ');
    return 'Chi tiết hoạt động tài chính';
  }

  static String _syncTitle(SyncAuditEvent event) {
    final entity = _syncEntityLabel(event.entityType);
    final outcome = _syncOutcomeLabel(event.outcome);
    return '$outcome: $entity';
  }

  static String _syncSubtitle(SyncAuditEvent event) {
    final operation = _syncOperationLabel(event.operation);
    final base = '$operation • Mã #${event.entityId}';
    final error = (event.errorMessage ?? '').trim();
    if (error.isNotEmpty) {
      return '$base • ${_safeInlineError(error)}';
    }
    return base;
  }

  static String _syncEntityLabel(String entityType) {
    switch (entityType) {
      case 'sale':
        return 'Đơn bán hàng';
      case 'repair':
        return 'Đơn sửa chữa';
      case 'expense':
        return 'Khoản thu/chi';
      case 'debt':
        return 'Công nợ';
      case 'debtPayment':
        return 'Phiếu thanh toán công nợ';
      case 'supplierPayment':
        return 'Phiếu trả nhà cung cấp';
      case 'partnerPayment':
        return 'Phiếu trả đối tác sửa chữa';
      case 'product':
        return 'Sản phẩm/kho';
      case 'purchaseOrder':
        return 'Đơn nhập hàng';
      case 'cashClosing':
        return 'Chốt quỹ';
      case 'customer':
        return 'Khách hàng';
      default:
        return 'Dữ liệu hệ thống';
    }
  }

  static String _syncOperationLabel(String operation) {
    switch (operation.toLowerCase()) {
      case 'insert':
      case 'create':
        return 'Tạo mới';
      case 'update':
      case 'upsert':
        return 'Cập nhật';
      case 'delete':
        return 'Xóa';
      case 'sync':
        return 'Đồng bộ';
      default:
        return 'Đồng bộ dữ liệu';
    }
  }

  static String _syncOutcomeLabel(String outcome) {
    switch (outcome.toLowerCase()) {
      case 'success':
        return 'Đồng bộ thành công';
      case 'retry':
        return 'Đang thử đồng bộ lại';
      case 'failed':
        return 'Đồng bộ thất bại';
      default:
        return 'Trạng thái đồng bộ';
    }
  }

  static String _auditTitle(Map<String, dynamic> row) {
    final action = row['action']?.toString().trim() ?? '';
    if (action.isEmpty) return 'Nhật ký hệ thống';

    const directMap = {
      'DEBT_COLLECTED': 'Thu nợ khách hàng',
      'DEBT_COLLECT': 'Thu nợ khách hàng',
      'SUPPLIER_PAID': 'Trả nợ nhà cung cấp',
      'PART_IMPORT': 'Nhập kho linh kiện',
      'PART_INFO_UPDATE': 'Cập nhật thông tin linh kiện',
      'PART_ADD_STOCK': 'Bổ sung tồn kho linh kiện',
      'DELETE_PART': 'Xóa linh kiện',
      'PAYMENT_REQUEST_APPROVED': 'Duyệt yêu cầu đóng tiền',
      'PAYMENT_REQUEST_REJECTED': 'Từ chối yêu cầu đóng tiền',
      'PAYMENT_REQUEST_CREATED': 'Tạo yêu cầu đóng tiền',
    };

    final upper = action.toUpperCase();
    if (directMap.containsKey(upper)) {
      return directMap[upper]!;
    }

    return _humanizeActionCode(action);
  }

  static String _auditSubtitle(Map<String, dynamic> row) {
    final description = row['description']?.toString().trim() ?? '';
    if (description.isNotEmpty && !_looksTechnical(description)) {
      return description;
    }

    final userName = row['userName']?.toString().trim() ?? '';
    final targetType = row['targetType']?.toString().trim() ?? '';
    final targetId = row['targetId']?.toString().trim() ?? '';

    final parts = <String>[];
    if (userName.isNotEmpty) parts.add('Bởi $userName');
    if (targetType.isNotEmpty) {
      final typeLabel = _humanizeActionCode(targetType);
      if (targetId.isNotEmpty) {
        parts.add('$typeLabel #$targetId');
      } else {
        parts.add(typeLabel);
      }
    }

    if (parts.isNotEmpty) return parts.join(' • ');
    return 'Chi tiết nhật ký hệ thống';
  }

  static String _humanizeActionCode(String input) {
    final normalized = input
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_ ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(' ', '_')
        .toUpperCase();

    final tokens = normalized.split('_').where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return 'Nhật ký hệ thống';

    const tokenMap = {
      'DEBT': 'công nợ',
      'COLLECT': 'thu',
      'COLLECTED': 'đã thu',
      'PAY': 'trả',
      'PAID': 'đã trả',
      'SUPPLIER': 'nhà cung cấp',
      'CUSTOMER': 'khách hàng',
      'PART': 'linh kiện',
      'STOCK': 'tồn kho',
      'IMPORT': 'nhập kho',
      'ADD': 'thêm',
      'UPDATE': 'cập nhật',
      'EDIT': 'chỉnh sửa',
      'DELETE': 'xóa',
      'REMOVE': 'xóa',
      'CREATE': 'tạo',
      'PAYMENT': 'thanh toán',
      'REQUEST': 'yêu cầu',
      'APPROVED': 'đã duyệt',
      'REJECTED': 'đã từ chối',
      'REPAIR': 'sửa chữa',
      'SALE': 'bán hàng',
      'SYSTEM': 'hệ thống',
      'LOG': 'nhật ký',
      'SYNC': 'đồng bộ',
    };

    final words = tokens.map((t) => tokenMap[t] ?? t.toLowerCase()).toList();
    final sentence = words.join(' ').trim();
    if (sentence.isEmpty) return 'Nhật ký hệ thống';
    return '${sentence[0].toUpperCase()}${sentence.substring(1)}';
  }

  static bool _looksTechnical(String text) {
    final value = text.trim();
    if (value.isEmpty) return false;
    final upper = value.toUpperCase();
    if (upper.contains('SYNC ') || upper.contains('SYNC_')) return true;
    if (upper.contains('DEBT_') || upper.contains('PAYMENT_REQUEST_')) {
      return true;
    }
    if (upper.contains('#') && upper.contains('ID')) return true;
    return false;
  }

  static String _safeInlineError(String raw) {
    final cleaned = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length <= 90) return cleaned;
    return '${cleaned.substring(0, 90)}...';
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
