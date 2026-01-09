import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import 'user_service.dart';
import 'audit_service.dart';

/// Service quản lý bút toán điều chỉnh sau khi đã chốt quỹ
/// 
/// NGUYÊN TẮC:
/// 1. Không sửa trực tiếp dữ liệu của ngày đã chốt quỹ
/// 2. Mọi điều chỉnh phải tạo bút toán ở ngày hiện tại
/// 3. Ghi log đầy đủ: ai sửa, sửa gì, lý do
/// 4. Công nợ có thể điều chỉnh, quỹ ngày cũ không đổi
class AdjustmentService {
  static final _db = DBHelper();
  static final _firestore = FirebaseFirestore.instance;

  /// Kiểm tra ngày có bị khóa (đã chốt quỹ) không
  /// Returns: dateKey nếu bị khóa, null nếu chưa khóa
  static Future<String?> getLockedDateKey(int timestamp) async {
    final dateKey = DateFormat('yyyy-MM-dd').format(
      DateTime.fromMillisecondsSinceEpoch(timestamp),
    );
    
    final database = await _db.database;
    final result = await database.query(
      'cash_closings',
      where: 'dateKey = ? AND isLocked = 1',
      whereArgs: [dateKey],
      limit: 1,
    );
    
    if (result.isNotEmpty) {
      debugPrint('🔒 Ngày $dateKey ĐÃ CHỐT QUỸ');
      return dateKey;
    }
    debugPrint('✅ Ngày $dateKey CHƯA chốt quỹ, có thể sửa');
    return null;
  }

  /// Kiểm tra có thể sửa trực tiếp hay phải dùng bút toán điều chỉnh
  static Future<bool> canEditDirectly(int originalDate) async {
    final lockedDate = await getLockedDateKey(originalDate);
    return lockedDate == null;
  }

  /// Lấy thông tin chốt quỹ của một ngày
  static Future<Map<String, dynamic>?> getClosingForDate(String dateKey) async {
    final database = await _db.database;
    final result = await database.query(
      'cash_closings',
      where: 'dateKey = ?',
      whereArgs: [dateKey],
      limit: 1,
    );
    return result.isNotEmpty ? result.first : null;
  }

  /// Lấy danh sách các ngày đã chốt quỹ
  static Future<List<String>> getLockedDates() async {
    final database = await _db.database;
    final result = await database.query(
      'cash_closings',
      columns: ['dateKey'],
      where: 'isLocked = 1',
      orderBy: 'dateKey DESC',
    );
    return result.map((r) => r['dateKey'] as String).toList();
  }

  // ==================== BÚT TOÁN ĐIỀU CHỈNH GIÁ NHẬP ====================

  /// Tạo bút toán điều chỉnh giá nhập linh kiện
  /// 
  /// Khi sửa giá nhập sau chốt:
  /// - Không sửa phiếu nhập cũ
  /// - Tạo bút toán điều chỉnh tăng/giảm
  /// - Điều chỉnh công nợ NCC (nếu là công nợ)
  /// - Không ảnh hưởng quỹ đã chốt
  static Future<AdjustmentResult> adjustPartCost({
    required int partId,
    required String partName,
    required int oldCost,
    required int newCost,
    required int quantity,
    required int originalDate,
    required String reason,
    int? supplierId,
    String? supplierName,
    String? paymentMethod,
  }) async {
    try {
      final lockedDateKey = await getLockedDateKey(originalDate);
      if (lockedDateKey == null) {
        return AdjustmentResult(
          success: false,
          message: 'Ngày chưa chốt quỹ, có thể sửa trực tiếp',
          canEditDirectly: true,
        );
      }

      final user = FirebaseAuth.instance.currentUser;
      final shopId = await UserService.getCurrentShopId();
      final now = DateTime.now().millisecondsSinceEpoch;
      final userName = user?.email?.split('@').first.toUpperCase() ?? 'SYSTEM';
      
      final costDelta = (newCost - oldCost) * quantity;
      final adjustmentId = 'adj_cost_${now}_$partId';
      
      final database = await _db.database;
      
      // 1. Tạo bút toán điều chỉnh
      await database.insert('adjustment_entries', {
        'firestoreId': adjustmentId,
        'shopId': shopId,
        'adjustmentType': 'COST_ADJUSTMENT',
        'originalEntityType': 'repair_part',
        'originalEntityId': partId.toString(),
        'originalDate': originalDate,
        'adjustmentDate': now,
        'description': 'Điều chỉnh giá nhập: $partName',
        'reason': reason,
        'oldValues': jsonEncode({
          'cost': oldCost,
          'totalCost': oldCost * quantity,
        }),
        'newValues': jsonEncode({
          'cost': newCost,
          'totalCost': newCost * quantity,
        }),
        'costDelta': costDelta,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'createdBy': userName,
        'createdAt': now,
        'status': 'APPROVED', // Tự động approve
        'approvedBy': userName,
        'approvedAt': now,
        'isSynced': 0,
      });

      // 2. Điều chỉnh công nợ nếu là CÔNG NỢ
      if (paymentMethod == 'CÔNG NỢ' && supplierId != null && costDelta != 0) {
        // Tìm công nợ liên quan
        final debts = await database.query(
          'debts',
          where: "relatedPartId = ? AND type = 'SHOP_OWES'",
          whereArgs: [partId.toString()],
        );
        
        if (debts.isNotEmpty) {
          final debt = debts.first;
          final debtId = debt['id'] as int;
          final oldTotal = debt['totalAmount'] as int? ?? 0;
          final newTotal = oldTotal + costDelta;
          
          // Cập nhật công nợ
          await database.update(
            'debts',
            {
              'totalAmount': newTotal,
              'note': '${debt['note']} [Điều chỉnh ${DateFormat('dd/MM/yyyy').format(DateTime.now())}: ${costDelta > 0 ? '+' : ''}${NumberFormat('#,###').format(costDelta)}đ - $reason]',
              'isSynced': 0,
            },
            where: 'id = ?',
            whereArgs: [debtId],
          );
          
          // Tạo bút toán điều chỉnh công nợ
          await database.insert('adjustment_entries', {
            'firestoreId': 'adj_debt_${now}_$debtId',
            'shopId': shopId,
            'adjustmentType': 'DEBT_ADJUSTMENT',
            'originalEntityType': 'debt',
            'originalEntityId': debtId.toString(),
            'originalDate': originalDate,
            'adjustmentDate': now,
            'description': 'Điều chỉnh công nợ NCC: $supplierName',
            'reason': 'Theo điều chỉnh giá nhập $partName',
            'oldValues': jsonEncode({'totalAmount': oldTotal}),
            'newValues': jsonEncode({'totalAmount': newTotal}),
            'debtDelta': costDelta,
            'supplierId': supplierId,
            'supplierName': supplierName,
            'createdBy': userName,
            'createdAt': now,
            'status': 'APPROVED',
            'approvedBy': userName,
            'approvedAt': now,
            'isSynced': 0,
          });
        }
      }
      
      // 3. Nếu đã thanh toán (TIỀN MẶT/CHUYỂN KHOẢN), tạo phiếu chi/thu bổ sung
      else if ((paymentMethod == 'TIỀN MẶT' || paymentMethod == 'CHUYỂN KHOẢN') && costDelta != 0) {
        final expenseFirestoreId = 'adj_exp_${now}_$partId';
        await _db.insertExpense({
          'firestoreId': expenseFirestoreId,
          'category': costDelta > 0 ? 'ĐIỀU CHỈNH TĂNG' : 'ĐIỀU CHỈNH GIẢM',
          'description': 'Điều chỉnh giá nhập: $partName${supplierName != null ? " từ $supplierName" : ""} - $reason',
          'amount': costDelta, // Dương = chi thêm, Âm = hoàn lại
          'date': now,
          'paymentMethod': paymentMethod,
          'createdAt': now,
          'shopId': shopId,
          'isSynced': 0,
          'isAdjustment': 1,
          'adjustmentRef': adjustmentId,
        });
      }

      // 4. Cập nhật giá cost trong repair_parts (giá mới cho tương lai)
      await database.update(
        'repair_parts',
        {
          'cost': newCost,
          'updatedAt': now,
          'isSynced': 0,
        },
        where: 'id = ?',
        whereArgs: [partId],
      );

      // 5. Ghi audit log
      await AuditService.logAction(
        action: 'PART_COST_ADJUSTMENT',
        entityType: 'repair_part',
        entityId: partId.toString(),
        summary: 'Điều chỉnh giá nhập $partName: ${NumberFormat('#,###').format(oldCost)}đ → ${NumberFormat('#,###').format(newCost)}đ (${costDelta > 0 ? '+' : ''}${NumberFormat('#,###').format(costDelta)}đ)',
        payload: {
          'partName': partName,
          'oldCost': oldCost,
          'newCost': newCost,
          'quantity': quantity,
          'costDelta': costDelta,
          'originalDate': originalDate,
          'lockedDateKey': lockedDateKey,
          'reason': reason,
          'paymentMethod': paymentMethod,
          'supplierId': supplierId,
          'supplierName': supplierName,
        },
      );

      return AdjustmentResult(
        success: true,
        message: 'Đã tạo bút toán điều chỉnh giá nhập',
        adjustmentId: adjustmentId,
        costDelta: costDelta,
      );
    } catch (e) {
      debugPrint('AdjustmentService.adjustPartCost error: $e');
      return AdjustmentResult(
        success: false,
        message: 'Lỗi tạo bút toán: $e',
      );
    }
  }

  // ==================== BÚT TOÁN ĐIỀU CHỈNH THANH TOÁN ====================

  /// Tạo bút toán điều chỉnh số tiền đã thanh toán
  /// 
  /// Khi sửa số tiền đã trả sau chốt:
  /// - Không sửa quỹ ngày cũ
  /// - Tạo phiếu chi/thu bổ sung ở ngày hiện tại
  /// - Cập nhật công nợ tương ứng
  static Future<AdjustmentResult> adjustPayment({
    required int partId,
    required String partName,
    required int originalDate,
    required String oldPaymentMethod,
    required int oldPaidAmount,
    required String newPaymentMethod,
    required int newPaidAmount,
    required String reason,
    int? supplierId,
    String? supplierName,
    int? totalCost,
  }) async {
    try {
      final lockedDateKey = await getLockedDateKey(originalDate);
      if (lockedDateKey == null) {
        return AdjustmentResult(
          success: false,
          message: 'Ngày chưa chốt quỹ, có thể sửa trực tiếp',
          canEditDirectly: true,
        );
      }

      final user = FirebaseAuth.instance.currentUser;
      final shopId = await UserService.getCurrentShopId();
      final now = DateTime.now().millisecondsSinceEpoch;
      final userName = user?.email?.split('@').first.toUpperCase() ?? 'SYSTEM';
      
      final paymentDelta = newPaidAmount - oldPaidAmount;
      final adjustmentId = 'adj_payment_${now}_$partId';
      
      final database = await _db.database;
      
      // 1. Tạo bút toán điều chỉnh
      await database.insert('adjustment_entries', {
        'firestoreId': adjustmentId,
        'shopId': shopId,
        'adjustmentType': 'PAYMENT_ADJUSTMENT',
        'originalEntityType': 'repair_part',
        'originalEntityId': partId.toString(),
        'originalDate': originalDate,
        'adjustmentDate': now,
        'description': 'Điều chỉnh thanh toán: $partName',
        'reason': reason,
        'oldValues': jsonEncode({
          'paymentMethod': oldPaymentMethod,
          'paidAmount': oldPaidAmount,
        }),
        'newValues': jsonEncode({
          'paymentMethod': newPaymentMethod,
          'paidAmount': newPaidAmount,
        }),
        'cashDelta': newPaymentMethod == 'TIỀN MẶT' ? paymentDelta : (oldPaymentMethod == 'TIỀN MẶT' ? -oldPaidAmount : 0),
        'bankDelta': newPaymentMethod == 'CHUYỂN KHOẢN' ? paymentDelta : (oldPaymentMethod == 'CHUYỂN KHOẢN' ? -oldPaidAmount : 0),
        'supplierId': supplierId,
        'supplierName': supplierName,
        'createdBy': userName,
        'createdAt': now,
        'status': 'APPROVED',
        'approvedBy': userName,
        'approvedAt': now,
        'isSynced': 0,
      });

      // 2. Xử lý thay đổi thanh toán
      if (paymentDelta != 0) {
        // Tạo phiếu chi/thu bổ sung ở ngày hiện tại
        if (newPaymentMethod == 'TIỀN MẶT' || newPaymentMethod == 'CHUYỂN KHOẢN') {
          await _db.insertExpense({
            'firestoreId': 'adj_exp_${now}_$partId',
            'category': paymentDelta > 0 ? 'THANH TOÁN BỔ SUNG' : 'HOÀN TIỀN ĐIỀU CHỈNH',
            'description': 'Điều chỉnh thanh toán: $partName${supplierName != null ? " từ $supplierName" : ""} - $reason',
            'amount': paymentDelta,
            'date': now,
            'paymentMethod': newPaymentMethod,
            'createdAt': now,
            'shopId': shopId,
            'isSynced': 0,
            'isAdjustment': 1,
            'adjustmentRef': adjustmentId,
          });
        }

        // Điều chỉnh công nợ nếu có
        if (supplierId != null && totalCost != null) {
          final oldDebtAmount = oldPaymentMethod == 'CÔNG NỢ' ? totalCost : (totalCost - oldPaidAmount);
          final newDebtAmount = newPaymentMethod == 'CÔNG NỢ' ? totalCost : (totalCost - newPaidAmount);
          final debtDelta = newDebtAmount - oldDebtAmount;
          
          if (debtDelta != 0) {
            // Tìm và cập nhật công nợ
            final debts = await database.query(
              'debts',
              where: "relatedPartId = ? AND type = 'SHOP_OWES'",
              whereArgs: [partId.toString()],
            );
            
            if (debts.isNotEmpty) {
              final debt = debts.first;
              final debtId = debt['id'] as int;
              final currentTotal = debt['totalAmount'] as int? ?? 0;
              
              await database.update(
                'debts',
                {
                  'totalAmount': currentTotal + debtDelta,
                  'note': '${debt['note']} [Điều chỉnh TT ${DateFormat('dd/MM/yyyy').format(DateTime.now())}: ${debtDelta > 0 ? '+' : ''}${NumberFormat('#,###').format(debtDelta)}đ]',
                  'isSynced': 0,
                },
                where: 'id = ?',
                whereArgs: [debtId],
              );
            } else if (debtDelta > 0) {
              // Tạo công nợ mới nếu chuyển sang công nợ
              await _db.insertDebt({
                'firestoreId': 'debt_adj_${now}_$partId',
                'type': 'SHOP_OWES',
                'personName': supplierName ?? 'NCC',
                'phone': '',
                'totalAmount': debtDelta,
                'paidAmount': 0,
                'note': 'Công nợ từ điều chỉnh thanh toán: $partName - $reason',
                'status': 'unpaid',
                'createdAt': now,
                'shopId': shopId,
                'isSynced': 0,
                'isAdjustment': 1,
                'adjustmentRef': adjustmentId,
                'relatedPartId': partId.toString(),
              });
            }
          }
        }
      }

      // 3. Ghi audit log
      await AuditService.logAction(
        action: 'PAYMENT_ADJUSTMENT',
        entityType: 'repair_part',
        entityId: partId.toString(),
        summary: 'Điều chỉnh thanh toán $partName: $oldPaymentMethod ${NumberFormat('#,###').format(oldPaidAmount)}đ → $newPaymentMethod ${NumberFormat('#,###').format(newPaidAmount)}đ',
        payload: {
          'partName': partName,
          'oldPaymentMethod': oldPaymentMethod,
          'oldPaidAmount': oldPaidAmount,
          'newPaymentMethod': newPaymentMethod,
          'newPaidAmount': newPaidAmount,
          'paymentDelta': paymentDelta,
          'originalDate': originalDate,
          'lockedDateKey': lockedDateKey,
          'reason': reason,
        },
      );

      return AdjustmentResult(
        success: true,
        message: 'Đã tạo bút toán điều chỉnh thanh toán',
        adjustmentId: adjustmentId,
      );
    } catch (e) {
      debugPrint('AdjustmentService.adjustPayment error: $e');
      return AdjustmentResult(
        success: false,
        message: 'Lỗi tạo bút toán: $e',
      );
    }
  }

  // ==================== THANH TOÁN NỢ ====================

  /// Thanh toán nợ nhà cung cấp
  /// Luôn ghi nhận ở ngày hiện tại, không tác động ngày cũ
  static Future<AdjustmentResult> paySupplierDebt({
    required int debtId,
    required int amount,
    required String paymentMethod,
    required String? note,
    int? supplierId,
    String? supplierName,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final shopId = await UserService.getCurrentShopId();
      final now = DateTime.now().millisecondsSinceEpoch;
      final userName = user?.email?.split('@').first.toUpperCase() ?? 'SYSTEM';
      
      final database = await _db.database;
      
      // Lấy thông tin công nợ
      final debts = await database.query(
        'debts',
        where: 'id = ?',
        whereArgs: [debtId],
        limit: 1,
      );
      
      if (debts.isEmpty) {
        return AdjustmentResult(
          success: false,
          message: 'Không tìm thấy công nợ',
        );
      }
      
      final debt = debts.first;
      final totalAmount = debt['totalAmount'] as int? ?? 0;
      final paidAmount = debt['paidAmount'] as int? ?? 0;
      final remain = totalAmount - paidAmount;
      
      if (amount > remain) {
        return AdjustmentResult(
          success: false,
          message: 'Số tiền thanh toán vượt quá công nợ còn lại (${NumberFormat('#,###').format(remain)}đ)',
        );
      }
      
      // 1. Ghi nhận thanh toán
      final paymentId = 'debt_pay_${now}_$debtId';
      await database.insert('debt_payments', {
        'firestoreId': paymentId,
        'debtId': debtId,
        'debtFirestoreId': debt['firestoreId'],
        'amount': amount,
        'paidAt': now,
        'paymentMethod': paymentMethod,
        'note': note ?? 'Thanh toán công nợ',
        'createdBy': userName,
        'isSynced': 0,
        'shopId': shopId,
      });
      
      // 2. Cập nhật công nợ
      final newPaidAmount = paidAmount + amount;
      final newStatus = newPaidAmount >= totalAmount ? 'paid' : 'partial';
      
      await database.update(
        'debts',
        {
          'paidAmount': newPaidAmount,
          'status': newStatus,
          'isSynced': 0,
        },
        where: 'id = ?',
        whereArgs: [debtId],
      );
      
      // 3. Ghi chi tiêu ở ngày hiện tại
      await _db.insertExpense({
        'firestoreId': 'exp_debt_${now}_$debtId',
        'category': 'THANH TOÁN CÔNG NỢ',
        'description': 'Thanh toán công nợ${supplierName != null ? " NCC $supplierName" : ""}${note != null ? " - $note" : ""}',
        'amount': amount,
        'date': now,
        'paymentMethod': paymentMethod,
        'createdAt': now,
        'shopId': shopId,
        'isSynced': 0,
      });
      
      // 4. Ghi audit log
      await AuditService.logAction(
        action: 'DEBT_PAYMENT',
        entityType: 'debt',
        entityId: debtId.toString(),
        summary: 'Thanh toán công nợ${supplierName != null ? " NCC $supplierName" : ""}: ${NumberFormat('#,###').format(amount)}đ ($paymentMethod)',
        payload: {
          'debtId': debtId,
          'amount': amount,
          'paymentMethod': paymentMethod,
          'totalAmount': totalAmount,
          'paidBefore': paidAmount,
          'paidAfter': newPaidAmount,
          'remainAfter': totalAmount - newPaidAmount,
          'status': newStatus,
        },
      );

      return AdjustmentResult(
        success: true,
        message: newStatus == 'paid' 
            ? 'Đã tất toán công nợ' 
            : 'Đã thanh toán ${NumberFormat('#,###').format(amount)}đ, còn lại ${NumberFormat('#,###').format(totalAmount - newPaidAmount)}đ',
      );
    } catch (e) {
      debugPrint('AdjustmentService.paySupplierDebt error: $e');
      return AdjustmentResult(
        success: false,
        message: 'Lỗi thanh toán: $e',
      );
    }
  }

  // ==================== LỊCH SỬ ĐIỀU CHỈNH ====================

  /// Lấy lịch sử điều chỉnh của một entity
  static Future<List<Map<String, dynamic>>> getAdjustmentHistory({
    String? entityType,
    String? entityId,
    int? limit,
  }) async {
    final database = await _db.database;
    
    String? where;
    List<dynamic>? whereArgs;
    
    if (entityType != null && entityId != null) {
      where = 'originalEntityType = ? AND originalEntityId = ?';
      whereArgs = [entityType, entityId];
    } else if (entityType != null) {
      where = 'originalEntityType = ?';
      whereArgs = [entityType];
    }
    
    return await database.query(
      'adjustment_entries',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'adjustmentDate DESC',
      limit: limit,
    );
  }

  /// Lấy tất cả bút toán điều chỉnh trong khoảng thời gian
  static Future<List<Map<String, dynamic>>> getAdjustmentsByDateRange({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final database = await _db.database;
    final start = startDate.millisecondsSinceEpoch;
    final end = endDate.millisecondsSinceEpoch;
    
    return await database.query(
      'adjustment_entries',
      where: 'adjustmentDate >= ? AND adjustmentDate <= ?',
      whereArgs: [start, end],
      orderBy: 'adjustmentDate DESC',
    );
  }

  /// Tổng hợp điều chỉnh theo ngày
  static Future<Map<String, int>> getAdjustmentSummaryByDate(String dateKey) async {
    final database = await _db.database;
    
    final startOfDay = DateTime.parse(dateKey).millisecondsSinceEpoch;
    final endOfDay = startOfDay + 86400000 - 1;
    
    final adjustments = await database.query(
      'adjustment_entries',
      where: 'adjustmentDate >= ? AND adjustmentDate <= ?',
      whereArgs: [startOfDay, endOfDay],
    );
    
    int totalCostDelta = 0;
    int totalDebtDelta = 0;
    int totalCashDelta = 0;
    int totalBankDelta = 0;
    
    for (var adj in adjustments) {
      totalCostDelta += adj['costDelta'] as int? ?? 0;
      totalDebtDelta += adj['debtDelta'] as int? ?? 0;
      totalCashDelta += adj['cashDelta'] as int? ?? 0;
      totalBankDelta += adj['bankDelta'] as int? ?? 0;
    }
    
    return {
      'costDelta': totalCostDelta,
      'debtDelta': totalDebtDelta,
      'cashDelta': totalCashDelta,
      'bankDelta': totalBankDelta,
      'count': adjustments.length,
    };
  }
}

/// Kết quả của thao tác điều chỉnh
class AdjustmentResult {
  final bool success;
  final String message;
  final String? adjustmentId;
  final int? costDelta;
  final bool canEditDirectly;

  AdjustmentResult({
    required this.success,
    required this.message,
    this.adjustmentId,
    this.costDelta,
    this.canEditDirectly = false,
  });
}
