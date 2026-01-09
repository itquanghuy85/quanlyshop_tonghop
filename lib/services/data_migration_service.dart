import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'user_service.dart';

/// Service để migrate dữ liệu từ shopId cũ sang shopId mới
/// CHỈ migrate dữ liệu do user hiện tại tạo ra (để tránh lấy nhầm data shop khác)
class DataMigrationService {
  static final _db = FirebaseFirestore.instance;

  /// Tìm tất cả shopId có dữ liệu trên cloud
  static Future<Map<String, int>> findAllShopIdsWithData() async {
    final shopIdCounts = <String, int>{};
    
    final collections = [
      'repairs',
      'sales',
      'products',
      'expenses',
      'debts',
      'attendance',
      'customers',
      'suppliers',
      'quick_input_codes',
      'repair_parts',
    ];

    for (var collection in collections) {
      try {
        // Lấy sample docs để tìm các shopId
        final snapshot = await _db.collection(collection).limit(100).get();
        
        for (var doc in snapshot.docs) {
          final shopId = doc.data()['shopId']?.toString() ?? 'null';
          shopIdCounts[shopId] = (shopIdCounts[shopId] ?? 0) + 1;
        }
      } catch (e) {
        debugPrint('Error checking $collection: $e');
      }
    }

    return shopIdCounts;
  }

  /// Đếm số lượng dữ liệu theo shopId
  static Future<Map<String, int>> countDataByShopId(String shopId) async {
    final counts = <String, int>{};
    
    final collections = [
      'repairs',
      'sales',
      'products',
      'expenses',
      'debts',
      'attendance',
      'customers',
      'suppliers',
      'quick_input_codes',
      'repair_parts',
    ];

    for (var collection in collections) {
      try {
        QuerySnapshot snapshot;
        if (shopId == 'null') {
          // Dữ liệu không có shopId
          snapshot = await _db
              .collection(collection)
              .where('shopId', isNull: true)
              .get();
        } else {
          snapshot = await _db
              .collection(collection)
              .where('shopId', isEqualTo: shopId)
              .get();
        }
        
        // Filter deleted
        final activeCount = snapshot.docs
            .where((d) => d.data() is Map && (d.data() as Map)['deleted'] != true)
            .length;
        
        if (activeCount > 0) {
          counts[collection] = activeCount;
        }
      } catch (e) {
        debugPrint('Error counting $collection: $e');
      }
    }

    return counts;
  }

  /// Migrate dữ liệu từ shopId cũ sang shopId mới
  /// CHỈ migrate dữ liệu do user hiện tại tạo ra
  static Future<Map<String, int>> migrateData({
    required String fromShopId,
    required String toShopId,
    Function(String message)? onProgress,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      onProgress?.call('❌ Chưa đăng nhập');
      return {};
    }
    
    final currentUserId = currentUser.uid;
    debugPrint('🔄 Migrate dữ liệu của user $currentUserId từ $fromShopId → $toShopId');
    
    final results = <String, int>{};
    
    final collections = [
      'repairs',
      'sales',
      'products',
      'expenses',
      'debts',
      'attendance',
      'customers',
      'suppliers',
      'quick_input_codes',
      'repair_parts',
    ];

    for (var collection in collections) {
      try {
        onProgress?.call('Đang migrate $collection...');
        
        QuerySnapshot snapshot;
        if (fromShopId == 'null') {
          snapshot = await _db
              .collection(collection)
              .where('shopId', isNull: true)
              .get();
        } else {
          snapshot = await _db
              .collection(collection)
              .where('shopId', isEqualTo: fromShopId)
              .get();
        }

        int migratedCount = 0;
        int skippedCount = 0;
        final batch = _db.batch();
        
        for (var doc in snapshot.docs) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data == null || data['deleted'] == true) continue;
          
          // QUAN TRỌNG: Chỉ migrate nếu dữ liệu do user hiện tại tạo
          final createdBy = data['createdBy']?.toString();
          final userId = data['userId']?.toString();
          final staffId = data['staffId']?.toString();
          
          final isCreatedByCurrentUser = 
              createdBy == currentUserId || 
              userId == currentUserId ||
              staffId == currentUserId;
          
          if (!isCreatedByCurrentUser) {
            skippedCount++;
            continue; // Bỏ qua dữ liệu của người khác
          }
          
          batch.update(doc.reference, {
            'shopId': toShopId,
            'migratedAt': FieldValue.serverTimestamp(),
            'migratedFrom': fromShopId,
          });
          migratedCount++;
        }

        if (migratedCount > 0) {
          await batch.commit();
          results[collection] = migratedCount;
          onProgress?.call('✅ Đã migrate $migratedCount $collection');
        }
        if (skippedCount > 0) {
          debugPrint('⚠️ Bỏ qua $skippedCount $collection (của user khác)');
        }
      } catch (e) {
        debugPrint('Error migrating $collection: $e');
        onProgress?.call('❌ Lỗi migrate $collection: $e');
      }
    }

    return results;
  }

  /// Kiểm tra và hiển thị thông tin về dữ liệu orphan (không có shopId hoặc shopId khác)
  /// CHỈ tìm dữ liệu do user hiện tại tạo ra
  static Future<List<OrphanDataInfo>> findOrphanData() async {
    final currentShopId = await UserService.getCurrentShopId();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentShopId == null || currentUser == null) return [];

    final currentUserId = currentUser.uid;
    final currentEmail = currentUser.email;
    
    debugPrint('🔍 Tìm dữ liệu orphan của user: $currentUserId ($currentEmail)');

    final orphanInfo = <OrphanDataInfo>[];
    
    final collections = [
      'repairs',
      'sales',
      'products',
      'expenses',
      'debts',
      'attendance',
      'customers',
      'suppliers',
      'quick_input_codes',
      'repair_parts',
    ];

    for (var collection in collections) {
      try {
        // Lấy tất cả docs của collection (limit để tránh quá tải)
        final snapshot = await _db.collection(collection).limit(500).get();
        
        final shopIdGroups = <String, int>{};
        
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['deleted'] == true) continue;
          
          final docShopId = data['shopId']?.toString() ?? 'null';
          
          // Chỉ đếm những docs KHÔNG thuộc shop hiện tại
          if (docShopId != currentShopId) {
            // QUAN TRỌNG: Chỉ đếm nếu dữ liệu do user hiện tại tạo
            final createdBy = data['createdBy']?.toString();
            final userId = data['userId']?.toString();
            final staffId = data['staffId']?.toString();
            
            final isCreatedByCurrentUser = 
                createdBy == currentUserId || 
                userId == currentUserId ||
                staffId == currentUserId;
            
            if (isCreatedByCurrentUser) {
              shopIdGroups[docShopId] = (shopIdGroups[docShopId] ?? 0) + 1;
            }
          }
        }

        for (var entry in shopIdGroups.entries) {
          orphanInfo.add(OrphanDataInfo(
            collection: collection,
            shopId: entry.key,
            count: entry.value,
          ));
        }
      } catch (e) {
        debugPrint('Error finding orphan data in $collection: $e');
      }
    }
    
    debugPrint('📊 Tìm thấy ${orphanInfo.length} nhóm dữ liệu orphan của user');

    return orphanInfo;
  }
  
  /// Tìm TẤT CẢ dữ liệu orphan (kể cả của người khác) - chỉ dùng cho admin debug
  static Future<List<OrphanDataInfo>> findAllOrphanData() async {
    final currentShopId = await UserService.getCurrentShopId();
    if (currentShopId == null) return [];

    final orphanInfo = <OrphanDataInfo>[];
    
    final collections = [
      'repairs',
      'sales',
      'products',
      'expenses',
      'debts',
      'attendance',
      'customers',
      'suppliers',
      'quick_input_codes',
      'repair_parts',
    ];

    for (var collection in collections) {
      try {
        final snapshot = await _db.collection(collection).limit(500).get();
        
        final shopIdGroups = <String, int>{};
        
        for (var doc in snapshot.docs) {
          final data = doc.data();
          if (data['deleted'] == true) continue;
          
          final docShopId = data['shopId']?.toString() ?? 'null';
          
          if (docShopId != currentShopId) {
            shopIdGroups[docShopId] = (shopIdGroups[docShopId] ?? 0) + 1;
          }
        }

        for (var entry in shopIdGroups.entries) {
          orphanInfo.add(OrphanDataInfo(
            collection: collection,
            shopId: entry.key,
            count: entry.value,
          ));
        }
      } catch (e) {
        debugPrint('Error finding all orphan data in $collection: $e');
      }
    }

    return orphanInfo;
  }
}

class OrphanDataInfo {
  final String collection;
  final String shopId;
  final int count;

  OrphanDataInfo({
    required this.collection,
    required this.shopId,
    required this.count,
  });
}
