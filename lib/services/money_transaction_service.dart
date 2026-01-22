// MoneyTransactionService - Append-only ledger writer
//
// PURPOSE:
// - Single entry point to record financial ledger entries
// - Append-only (no updates, no deletes)
// - Assume inputs are already validated elsewhere (e.g., MoneyValidationService)
//
// RULES:
// - No validation here
// - No calculations here
// - No UI dependencies
// - Just persist ledger entries using DBHelper
//
// Created: 2026-01-22
// Author: AI Assistant (Phase 4 - MoneyTransactionService)

import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/financial_activity_model.dart';
import 'user_service.dart';

/// Append-only ledger writer for money transactions.
class MoneyTransactionService {
  static final DBHelper _db = DBHelper();

  /// Append a ledger entry to local log (financial_activity_log table).
  /// - Does NOT validate
  /// - Does NOT calculate
  /// - Returns inserted row id or null on failure
  static Future<int?> appendLedger({
    required String activityType,
    required String direction,
    required int amount,
    required String paymentMethod,
    String? referenceType,
    String? referenceId,
    String? notes,
    String? createdBy,
    String? title,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final now = DateTime.now().millisecondsSinceEpoch;
      
      final activity = FinancialActivity(
        activityType: activityType,
        direction: direction,
        amount: amount,
        paymentMethod: paymentMethod,
        referenceType: referenceType,
        referenceId: referenceId,
        description: notes,
        title: title ?? activityType,
        createdAt: now,
        createdBy: createdBy,
        shopId: shopId,
      );
      
      final data = activity.toMap();
      final id = await _db.insertFinancialActivity(data);
      return id;
    } catch (e, stack) {
      debugPrint('MoneyTransactionService.appendLedger error: $e');
      debugPrint(stack.toString());
      return null;
    }
  }

  /// Append a ledger entry from FinancialActivity model.
  static Future<int?> appendLedgerFromModel(FinancialActivity activity) async {
    try {
      final data = activity.toMap();
      final id = await _db.insertFinancialActivity(data);
      return id;
    } catch (e, stack) {
      debugPrint('MoneyTransactionService.appendLedgerFromModel error: $e');
      debugPrint(stack.toString());
      return null;
    }
  }

  /// Append a ledger entry from raw map (when model not available).
  /// Caller must ensure the payload matches financial_activity_log schema.
  static Future<int?> appendLedgerRaw(Map<String, dynamic> data) async {
    try {
      final id = await _db.insertFinancialActivity(data);
      return id;
    } catch (e, stack) {
      debugPrint('MoneyTransactionService.appendLedgerRaw error: $e');
      debugPrint(stack.toString());
      return null;
    }
  }

  /// Get all ledger entries for reconciliation
  static Future<List<FinancialActivity>> getLedgerEntries({
    int? startDate,
    int? endDate,
    int limit = 500,
  }) async {
    try {
      final shopId = UserService.getShopIdSync();
      final db = await _db.database;
      
      String whereClause = 'shopId = ?';
      List<dynamic> whereArgs = [shopId];
      
      if (startDate != null) {
        whereClause += ' AND createdAt >= ?';
        whereArgs.add(startDate);
      }
      if (endDate != null) {
        whereClause += ' AND createdAt <= ?';
        whereArgs.add(endDate);
      }
      
      final results = await db.query(
        'financial_activity_log',
        where: whereClause,
        whereArgs: whereArgs,
        orderBy: 'createdAt DESC',
        limit: limit,
      );
      
      return results.map((e) => FinancialActivity.fromMap(e)).toList();
    } catch (e, stack) {
      debugPrint('MoneyTransactionService.getLedgerEntries error: $e');
      debugPrint(stack.toString());
      return [];
    }
  }
}
