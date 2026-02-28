import '../data/db_helper.dart';
import '../models/repair_partner_model.dart';
import '../models/partner_repair_history_model.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../services/audit_service.dart';
import '../core/utils/money_utils.dart';

class RepairPartnerService {
  final db = DBHelper();

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

  Future<List<PartnerRepairHistory>> getPartnerRepairHistory({int? partnerId, String? partnerFirestoreId, String? repairOrderId}) async {
    final shopId = await UserService.getCurrentShopId();
    final data = await db.getPartnerRepairHistory(
      partnerId: partnerId,
      partnerFirestoreId: partnerFirestoreId,
      repairOrderId: repairOrderId,
    );
    return data
        .where((h) => h['shopId'] == shopId)
        .map((h) => PartnerRepairHistory.fromMap(h))
        .toList();
  }

  Future<Map<String, dynamic>?> getPartnerRepairStats(int partnerId, {String? partnerFirestoreId}) async {
    final shopId = await UserService.getCurrentShopId();
    final dbStats = await db.getPartnerRepairStats(
      partnerId,
      shopId: shopId,
      partnerFirestoreId: partnerFirestoreId,
    );
    // Also get total paid from payments table
    final dbInstance = await db.database;
    final payments = await dbInstance.rawQuery(
      'SELECT COALESCE(SUM(amount), 0) as totalPaid FROM repair_partner_payments WHERE partnerId = ? AND shopId = ? AND deleted = 0',
      [partnerId, shopId],
    );
    final totalPaid = payments.isNotEmpty ? (payments.first['totalPaid'] as int? ?? 0) : 0;
    return {
      ...?dbStats,
      'totalOrders': dbStats?['totalRepairs'] ?? 0,
      'totalCost': dbStats?['totalCost'] ?? 0,
      'totalPaid': totalPaid,
    };
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
    final history = PartnerRepairHistory(
      repairOrderId: repairOrderId,
      partnerId: partnerId,
      customerName: customerName,
      deviceModel: deviceModel,
      issue: issue,
      partnerCost: partnerCost,
      repairContent: repairContent,
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