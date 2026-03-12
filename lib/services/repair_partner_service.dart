import 'dart:convert';
import '../data/db_helper.dart';
import '../models/repair_partner_model.dart';
import '../models/partner_repair_history_model.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../services/audit_service.dart';
import '../core/utils/money_utils.dart';

class RepairPartnerService {
  final db = DBHelper();

  static String generateServiceFirestoreId() {
    return 'svc_${DateTime.now().microsecondsSinceEpoch}';
  }

  static String buildPartnerDebtFirestoreId({
    required String repairOrderId,
    required String serviceFirestoreId,
    required int partnerId,
    required int partnerCost,
  }) {
    final normalized = _normalizeTrackingKey(
      'debt_${repairOrderId}_${serviceFirestoreId}_${partnerId}_$partnerCost',
    );
    return 'debt_partner_$normalized';
  }

  static String buildPartnerPaymentIdempotencyKey({
    required String repairOrderId,
    required String serviceFirestoreId,
    required int partnerId,
    required int partnerCost,
    required String paymentMethod,
  }) {
    return _normalizeTrackingKey(
      'partner_payment_${repairOrderId}_${serviceFirestoreId}_${partnerId}_${paymentMethod.trim().toUpperCase()}_$partnerCost',
    );
  }

  static String buildPartnerTrackingNote({
    required String repairOrderId,
    required String serviceFirestoreId,
    required String serviceName,
    required String deviceModel,
    required String customerName,
    required bool isDebt,
  }) {
    final label = isDebt ? 'Công nợ đối tác' : 'Thanh toán đối tác';
    return '$label: $serviceName - Đơn sửa $deviceModel ($customerName) [repair:$repairOrderId|service:$serviceFirestoreId]';
  }

  static String _normalizeTrackingKey(String value) {
    final normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    if (normalized.length <= 80) {
      return normalized;
    }
    return normalized.substring(0, 80);
  }

  // Repair Partner CRUD
  Future<List<RepairPartner>> getRepairPartners() async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getRepairPartners();
    return data
        .where((p) => p['shopId'] == shopId && p['deleted'] != 1 && p['deleted'] != true)
        .map((p) => RepairPartner.fromMap(p))
        .toList();
  }

  /// Get repair partner by ID
  Future<RepairPartner?> getRepairPartnerById(int partnerId) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getRepairPartners();
    final partnerData = data.where((p) => 
        p['id'] == partnerId && 
        p['shopId'] == shopId && 
        p['deleted'] != 1 && 
        p['deleted'] != true
    ).firstOrNull;
    
    if (partnerData != null) {
      return RepairPartner.fromMap(partnerData);
    }
    return null;
  }

  Future<RepairPartner?> addRepairPartner(RepairPartner partner) async {
    final partnerMap = partner.toMap();
    final shopId = await UserService.getCurrentShopId();
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // Tạo firestoreId TRƯỚC khi insert để tránh duplicate từ realtime sync
    final firestoreId = 'partner_$now';
    
    partnerMap['shopId'] = shopId;
    partnerMap['createdAt'] = now;
    partnerMap['updatedAt'] = now;
    partnerMap['firestoreId'] = firestoreId;
    partnerMap['isSynced'] = 0;

    final id = await db.insertRepairPartner(partnerMap);
    if (id > 0) {
      // Sync lên Firestore - sử dụng firestoreId đã tạo
      final cloudId = await FirestoreService.addRepairPartner(partnerMap);
      if (cloudId != null) {
        // Đánh dấu đã sync
        await db.updateRepairPartner(id, {'isSynced': 1});
        return partner.copyWith(id: id, firestoreId: firestoreId);
      }
      // Dù chưa sync được cloud, vẫn return partner với firestoreId local
      return partner.copyWith(id: id, firestoreId: firestoreId);
    }
    return null;
  }

  Future<bool> updateRepairPartner(RepairPartner partner) async {
    final partnerMap = partner.toMap();
    partnerMap['updatedAt'] = DateTime.now().millisecondsSinceEpoch;
    // Ensure firestoreId present for cloud update
    if (partner.firestoreId != null) {
      partnerMap['firestoreId'] = partner.firestoreId;
    }

    final result = await db.updateRepairPartner(partner.id!, partnerMap);
    if (result > 0) {
      await FirestoreService.updateRepairPartner(partnerMap);
      return true;
    }
    return false;
  }

  Future<bool> deleteRepairPartner(int partnerId, {String? firestoreId}) async {
    // Lấy firestoreId nếu chưa có
    String? fsId = firestoreId;
    if (fsId == null) {
      final partners = await db.getRepairPartners();
      final partner = partners.firstWhere(
        (p) => p['id'] == partnerId,
        orElse: () => {},
      );
      fsId = partner['firestoreId'] as String?;
    }
    
    // Soft delete local: đánh dấu deleted = 1 và active = 0
    final localDb = await db.database;
    final result = await localDb.update(
      'repair_partners',
      {
        'active': 0,
        'deleted': 1,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [partnerId],
    );
    
    if (result > 0) {
      // Xóa trên Firestore nếu có firestoreId
      if (fsId != null && fsId.isNotEmpty) {
        await FirestoreService.deleteRepairPartnerByFirestoreId(fsId);
      }
      return true;
    }
    return false;
  }

  // Partner Repair History
  Future<PartnerRepairHistory?> addPartnerRepairHistory(PartnerRepairHistory history) async {
    final historyMap = history.toMap();
    historyMap['shopId'] = await UserService.getCurrentShopId();
    historyMap['sentAt'] = DateTime.now().millisecondsSinceEpoch;

    // Look up partner's firestoreId for stable cross-device sync
    if (history.partnerId > 0) {
      final partners = await db.getRepairPartners();
      final partner = partners.firstWhere(
        (p) => p['id'] == history.partnerId,
        orElse: () => {},
      );
      if (partner.isNotEmpty && partner['firestoreId'] != null) {
        historyMap['partnerFirestoreId'] = partner['firestoreId'];
      }
    }

    final id = await db.insertPartnerRepairHistory(historyMap);
    if (id > 0) {
      final firestoreId = await FirestoreService.addPartnerRepairHistory(historyMap);
      if (firestoreId != null) {
        await db.updatePartnerRepairHistory(id, {'firestoreId': firestoreId});
        return history.copyWith(id: id);
      }
    }
    return null;
  }

  Future<List<PartnerRepairHistory>> getPartnerRepairHistory({int? partnerId, String? partnerFirestoreId, String? repairOrderId, String? partnerName}) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getPartnerRepairHistory(
      partnerId: partnerId,
      partnerFirestoreId: partnerFirestoreId,
      repairOrderId: repairOrderId,
    );
    final histories = data
        .where((h) => h['shopId'] == shopId)
        .map((h) => PartnerRepairHistory.fromMap(h))
        .toList();

    // If history table is empty but repairs exist with this partner, build virtual entries
    if (histories.isEmpty && partnerId != null) {
      final virtualHistories = await _buildHistoriesFromRepairs(partnerId, partnerName, shopId);
      if (virtualHistories.isNotEmpty) return virtualHistories;
    }
    return histories;
  }

  /// Build PartnerRepairHistory entries from repairs table services JSON
  Future<List<PartnerRepairHistory>> _buildHistoriesFromRepairs(int partnerId, String? partnerName, String? shopId) async {
    final dbInstance = await db.database;
    final nameUpper = (partnerName ?? '').toUpperCase().trim();
    // repairs table has no shopId column — all local repairs belong to current shop
    const where = "(deleted IS NULL OR deleted = 0)";
    final rows = await dbInstance.query('repairs', where: where,
        columns: ['firestoreId', 'customerName', 'model', 'services', 'createdAt']);
    final List<PartnerRepairHistory> results = [];
    for (final row in rows) {
      final servicesJson = row['services'];
      if (servicesJson == null || servicesJson.toString().isEmpty) continue;
      try {
        final services = jsonDecode(servicesJson.toString()) as List;
        for (final s in services) {
          if (s is! Map) continue;
          final sPartnerId = s['partnerId'];
          final sPartnerName = (s['partnerName'] ?? '').toString().toUpperCase().trim();
          if (sPartnerId == partnerId || (nameUpper.isNotEmpty && sPartnerName == nameUpper)) {
            results.add(PartnerRepairHistory(
              repairOrderId: row['firestoreId']?.toString() ?? '',
              partnerId: partnerId,
              customerName: row['customerName']?.toString() ?? '',
              deviceModel: row['model']?.toString() ?? '',
              issue: s['serviceName']?.toString() ?? '',
              partnerCost: (s['cost'] as num?)?.toInt() ?? 0,
              repairContent: s['serviceName']?.toString(),
              sentAt: row['createdAt'] as int? ?? 0,
              shopId: shopId ?? '',
            ));
            break;
          }
        }
      } catch (_) {}
    }
    results.sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return results;
  }

  Future<Map<String, dynamic>?> getPartnerRepairStats(int partnerId, {String? partnerFirestoreId, String? partnerName}) async {
    final shopId = await UserService.getCurrentShopId();
    final dbStats = await db.getPartnerRepairStats(
      partnerId,
      shopId: shopId,
      partnerFirestoreId: partnerFirestoreId,
    );
    // Also get total paid from payments table
    // Use OR to match by partnerId OR partnerName (in case local ID changed after reinstall/sync)
    final dbInstance = await db.database;
    String paymentWhere = 'shopId = ? AND deleted = 0 AND (partnerId = ?';
    List<dynamic> paymentArgs = [shopId, partnerId];
    if (partnerName != null && partnerName.isNotEmpty) {
      paymentWhere += ' OR UPPER(partnerName) = ?';
      paymentArgs.add(partnerName.toUpperCase());
    }
    paymentWhere += ')';
    final payments = await dbInstance.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as totalPaid FROM repair_partner_payments WHERE $paymentWhere',
      paymentArgs,
    );
    final totalPaid = payments.isNotEmpty ? (payments.first['totalPaid'] as int? ?? 0) : 0;

    // Also count repairs directly from repairs table where services reference this partner
    // This catches cases where partner_repair_history was not created
    final repairStats = await _countRepairsForPartner(partnerId, partnerName, shopId);
    final historyOrders = (dbStats?['totalRepairs'] ?? 0) as int;
    final repairOrders = repairStats['count'] as int;
    final repairCost = repairStats['totalCost'] as int;
    final repairLastDate = repairStats['lastDate'] as int?;

    // Use the higher count (repairs table is source of truth)
    final actualOrders = repairOrders > historyOrders ? repairOrders : historyOrders;
    final actualCost = repairOrders > historyOrders ? repairCost : ((dbStats?['totalCost'] ?? 0) as int);
    final actualLastDate = repairOrders > historyOrders ? repairLastDate : dbStats?['lastRepairDate'];

    return {
      ...?dbStats,
      'totalOrders': actualOrders,
      'totalCost': actualCost,
      'totalPaid': totalPaid,
      'avgCost': actualOrders > 0 ? (actualCost / actualOrders).round() : 0,
      'lastRepairDate': actualLastDate,
    };
  }

  /// Count repairs from repairs table that have services referencing this partner
  Future<Map<String, dynamic>> _countRepairsForPartner(int partnerId, String? partnerName, String? shopId) async {
    final dbInstance = await db.database;
    final nameUpper = (partnerName ?? '').toUpperCase().trim();
    // repairs table has no shopId column — all local repairs belong to current shop
    const where = "(deleted IS NULL OR deleted = 0)";
    final rows = await dbInstance.query('repairs', where: where, columns: ['services', 'createdAt']);
    int count = 0;
    int totalCost = 0;
    int? lastDate;
    for (final row in rows) {
      final servicesJson = row['services'];
      if (servicesJson == null || servicesJson.toString().isEmpty) continue;
      try {
        final services = jsonDecode(servicesJson.toString()) as List;
        for (final s in services) {
          if (s is! Map) continue;
          final sPartnerId = s['partnerId'];
          final sPartnerName = (s['partnerName'] ?? '').toString().toUpperCase().trim();
          if (sPartnerId == partnerId || (nameUpper.isNotEmpty && sPartnerName == nameUpper)) {
            count++;
            totalCost += (s['cost'] as num?)?.toInt() ?? 0;
            final createdAt = row['createdAt'] as int?;
            if (createdAt != null && (lastDate == null || createdAt > lastDate)) {
              lastDate = createdAt;
            }
            break; // Count each repair once even if multiple services reference same partner
          }
        }
      } catch (_) {}
    }
    return {'count': count, 'totalCost': totalCost, 'lastDate': lastDate};
  }

  // Combined operation for repair order with partner
  Future<bool> createPartnerHistoryForRepair({
    required String repairOrderId,
    required int partnerId,
    required int partnerCost,
    required String customerName,
    required String deviceModel,
    required String issue,
    String? repairContent,
  }) async {
    final shopId = await UserService.getCurrentShopId() ?? '';
    final normalizedIssue = issue.trim().toUpperCase();
    final normalizedRepairContent = (repairContent ?? '').trim().toUpperCase();

    final existingHistories = await db.getPartnerRepairHistory(
      repairOrderId: repairOrderId,
    );
    final duplicate = existingHistories.any((history) {
      final samePartner = history['partnerId'] == partnerId;
      final sameIssue =
          (history['issue'] ?? '').toString().trim().toUpperCase() ==
          normalizedIssue;
      final sameRepairContent =
          (history['repairContent'] ?? '').toString().trim().toUpperCase() ==
          normalizedRepairContent;
      final sameCost = (history['partnerCost'] as num?)?.toInt() == partnerCost;
      return samePartner && sameIssue && sameRepairContent && sameCost;
    });

    if (duplicate) {
      return true;
    }

    final history = PartnerRepairHistory(
      repairOrderId: repairOrderId,
      partnerId: partnerId,
      customerName: customerName,
      deviceModel: deviceModel,
      issue: normalizedIssue,
      partnerCost: partnerCost,
      repairContent: normalizedRepairContent.isEmpty
          ? null
          : normalizedRepairContent,
      sentAt: DateTime.now().millisecondsSinceEpoch,
      shopId: shopId,
    );

    final result = await addPartnerRepairHistory(history);
    
    // Ghi nhật ký hệ thống khi tạo chi phí gửi sửa
    if (result != null) {
      // Lấy tên đối tác
      final partners = await db.getRepairPartners();
      final partner = partners.firstWhere((p) => p['id'] == partnerId, orElse: () => {});
      final partnerName = partner['name'] ?? 'N/A';
      
      await AuditService.logAction(
        action: 'PARTNER_REPAIR_COST',
        entityType: 'partner_repair_history',
        entityId: repairOrderId,
        summary: 'Gửi sửa đối tác $partnerName: ${MoneyUtils.formatVND(partnerCost)} - $deviceModel',
        payload: {
          'repairOrderId': repairOrderId,
          'partnerId': partnerId,
          'partnerName': partnerName,
          'partnerCost': partnerCost,
          'customerName': customerName,
          'deviceModel': deviceModel,
          'issue': issue,
        },
      );
    }
    
    return result != null;
  }
}