import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_message_model.dart';
import 'user_service.dart';

/// Service quản lý Chat nâng cao với đầy đủ tính năng
class ChatService {
  static final FirebaseFirestore _db = FirebaseFirestore.instance;
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  
  static const String _collectionChats = 'chats';
  static const String _collectionTyping = 'chat_typing';
  static const String _collectionOnline = 'chat_online';
  
  // Typing debounce
  static Timer? _typingTimer;
  static bool _isTyping = false;

  // ============== SEND MESSAGES ==============

  /// Gửi tin nhắn text
  static Future<String?> sendTextMessage({
    required String message,
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    List<String>? mentions,
    int priority = 0,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;
      
      final userName = user.email?.split('@').first.toUpperCase() ?? 'USER';
      
      final chatMessage = ChatMessage(
        shopId: shopId,
        senderId: user.uid,
        senderName: userName,
        message: message,
        messageType: 'text',
        replyToId: replyToId,
        replyToMessage: replyToMessage,
        replyToSender: replyToSender,
        mentions: mentions,
        readBy: [user.uid],
        createdAt: DateTime.now(),
        priority: priority,
      );
      
      final docRef = await _db.collection(_collectionChats).add(chatMessage.toMap());
      
      // Stop typing indicator
      await setTypingStatus(false);
      
      debugPrint('📨 Chat: Sent message ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Chat sendTextMessage error: $e');
      return null;
    }
  }

  /// Gửi tin nhắn với linked order (repair/sale)
  static Future<String?> sendLinkedMessage({
    required String message,
    required String linkedType, // repair, sale, product
    required String linkedKey,
    required String linkedSummary,
    Map<String, dynamic>? linkedData,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;
      
      final userName = user.email?.split('@').first.toUpperCase() ?? 'USER';
      
      final chatMessage = ChatMessage(
        shopId: shopId,
        senderId: user.uid,
        senderName: userName,
        message: message,
        messageType: 'linked_order',
        linkedType: linkedType,
        linkedKey: linkedKey,
        linkedSummary: linkedSummary,
        linkedData: linkedData,
        readBy: [user.uid],
        createdAt: DateTime.now(),
      );
      
      final docRef = await _db.collection(_collectionChats).add(chatMessage.toMap());
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Chat sendLinkedMessage error: $e');
      return null;
    }
  }

  /// Gửi tin nhắn hệ thống
  static Future<String?> sendSystemMessage({
    required String message,
    int priority = 0,
  }) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;
      
      final chatMessage = ChatMessage(
        shopId: shopId,
        senderId: 'system',
        senderName: '🤖 HỆ THỐNG',
        message: message,
        messageType: 'system',
        readBy: [],
        createdAt: DateTime.now(),
        priority: priority,
      );
      
      final docRef = await _db.collection(_collectionChats).add(chatMessage.toMap());
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Chat sendSystemMessage error: $e');
      return null;
    }
  }

  /// Gửi tin nhắn với hình ảnh
  static Future<String?> sendImageMessage({
    required List<File> images,
    String? caption,
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return null;
      
      final userName = user.email?.split('@').first.toUpperCase() ?? 'USER';
      
      // Upload images
      final List<String> urls = [];
      for (final image in images) {
        final fileName = 'chat_${DateTime.now().millisecondsSinceEpoch}_${urls.length}.jpg';
        final ref = _storage.ref().child('chat_images/$shopId/$fileName');
        await ref.putFile(image);
        final url = await ref.getDownloadURL();
        urls.add(url);
      }
      
      final chatMessage = ChatMessage(
        shopId: shopId,
        senderId: user.uid,
        senderName: userName,
        message: caption ?? '📷 Hình ảnh',
        messageType: 'image',
        mediaUrls: urls,
        readBy: [user.uid],
        createdAt: DateTime.now(),
      );
      
      final docRef = await _db.collection(_collectionChats).add(chatMessage.toMap());
      return docRef.id;
    } catch (e) {
      debugPrint('❌ Chat sendImageMessage error: $e');
      return null;
    }
  }

  // ============== MESSAGE ACTIONS ==============

  /// Thêm reaction vào tin nhắn
  static Future<bool> addReaction(String messageId, String emoji) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      
      await _db.collection(_collectionChats).doc(messageId).update({
        'reactions.$emoji': FieldValue.arrayUnion([user.uid]),
      });
      
      debugPrint('👍 Chat: Added reaction $emoji to $messageId');
      return true;
    } catch (e) {
      debugPrint('❌ Chat addReaction error: $e');
      return false;
    }
  }

  /// Xóa reaction khỏi tin nhắn
  static Future<bool> removeReaction(String messageId, String emoji) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      
      await _db.collection(_collectionChats).doc(messageId).update({
        'reactions.$emoji': FieldValue.arrayRemove([user.uid]),
      });
      
      return true;
    } catch (e) {
      debugPrint('❌ Chat removeReaction error: $e');
      return false;
    }
  }

  /// Toggle reaction
  static Future<bool> toggleReaction(String messageId, String emoji, bool hasReacted) async {
    if (hasReacted) {
      return removeReaction(messageId, emoji);
    } else {
      return addReaction(messageId, emoji);
    }
  }

  /// Chỉnh sửa tin nhắn
  static Future<bool> editMessage(String messageId, String newMessage) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      
      // Verify ownership
      final doc = await _db.collection(_collectionChats).doc(messageId).get();
      if (doc.data()?['senderId'] != user.uid) {
        debugPrint('❌ Chat: Cannot edit - not owner');
        return false;
      }
      
      await _db.collection(_collectionChats).doc(messageId).update({
        'message': newMessage,
        'isEdited': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      return true;
    } catch (e) {
      debugPrint('❌ Chat editMessage error: $e');
      return false;
    }
  }

  /// Xóa tin nhắn (soft delete)
  static Future<bool> deleteMessage(String messageId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;
      
      // Verify ownership or admin
      final doc = await _db.collection(_collectionChats).doc(messageId).get();
      final isOwner = doc.data()?['senderId'] == user.uid;
      final isAdmin = await UserService.isCurrentUserAdmin();
      
      if (!isOwner && !isAdmin) {
        debugPrint('❌ Chat: Cannot delete - not owner or admin');
        return false;
      }
      
      await _db.collection(_collectionChats).doc(messageId).update({
        'isDeleted': true,
        'message': '🗑️ Tin nhắn đã bị xóa',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      return true;
    } catch (e) {
      debugPrint('❌ Chat deleteMessage error: $e');
      return false;
    }
  }

  /// Ghim tin nhắn
  static Future<bool> pinMessage(String messageId, bool isPinned) async {
    try {
      await _db.collection(_collectionChats).doc(messageId).update({
        'isPinned': isPinned,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('❌ Chat pinMessage error: $e');
      return false;
    }
  }

  /// Đánh dấu đã đọc
  static Future<void> markAsRead(String messageId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      await _db.collection(_collectionChats).doc(messageId).update({
        'readBy': FieldValue.arrayUnion([user.uid]),
      });
    } catch (e) {
      debugPrint('❌ Chat markAsRead error: $e');
    }
  }

  /// Đánh dấu tất cả đã đọc
  static Future<void> markAllAsRead() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;
      
      // Get unread messages
      final unread = await _db.collection(_collectionChats)
          .where('shopId', isEqualTo: shopId)
          .where('readBy', arrayContains: user.uid)
          .get();
      
      // Batch update - lấy các tin nhắn chưa đọc
      final allDocs = await _db.collection(_collectionChats)
          .where('shopId', isEqualTo: shopId)
          .get();
      
      final batch = _db.batch();
      for (final doc in allDocs.docs) {
        final readBy = (doc.data()['readBy'] as List?) ?? [];
        if (!readBy.contains(user.uid)) {
          batch.update(doc.reference, {
            'readBy': FieldValue.arrayUnion([user.uid]),
          });
        }
      }
      await batch.commit();
      
      debugPrint('✅ Chat: Marked all as read');
    } catch (e) {
      debugPrint('❌ Chat markAllAsRead error: $e');
    }
  }

  // ============== STREAMS ==============

  /// Stream tin nhắn realtime
  static Stream<List<ChatMessage>> messagesStream({
    int limit = 100,
    String? beforeMessageId,
  }) async* {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      yield [];
      return;
    }
    
    Query<Map<String, dynamic>> query = _db.collection(_collectionChats)
        .where('shopId', isEqualTo: shopId)
        .orderBy('createdAt', descending: true)
        .limit(limit);
    
    yield* query.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => ChatMessage.fromSnapshot(doc)).toList();
    });
  }

  /// Stream tin nhắn đã ghim
  static Stream<List<ChatMessage>> pinnedMessagesStream() async* {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      yield [];
      return;
    }
    
    yield* _db.collection(_collectionChats)
        .where('shopId', isEqualTo: shopId)
        .where('isPinned', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(10)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => ChatMessage.fromSnapshot(doc)).toList();
        });
  }

  /// Đếm tin nhắn chưa đọc
  static Future<int> getUnreadCount() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return 0;
      
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return 0;
      
      final snapshot = await _db.collection(_collectionChats)
          .where('shopId', isEqualTo: shopId)
          .get();
      
      int count = 0;
      for (final doc in snapshot.docs) {
        final readBy = (doc.data()['readBy'] as List?) ?? [];
        if (!readBy.contains(user.uid)) count++;
      }
      
      return count;
    } catch (e) {
      debugPrint('❌ Chat getUnreadCount error: $e');
      return 0;
    }
  }

  /// Stream số tin chưa đọc
  static Stream<int> unreadCountStream() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      yield 0;
      return;
    }
    
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      yield 0;
      return;
    }
    
    yield* _db.collection(_collectionChats)
        .where('shopId', isEqualTo: shopId)
        .snapshots()
        .map((snapshot) {
          int count = 0;
          for (final doc in snapshot.docs) {
            final readBy = (doc.data()['readBy'] as List?) ?? [];
            if (!readBy.contains(user.uid)) count++;
          }
          return count;
        });
  }

  // ============== TYPING INDICATOR ==============

  /// Set trạng thái đang gõ
  static Future<void> setTypingStatus(bool isTyping) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;
      
      _isTyping = isTyping;
      
      if (isTyping) {
        final userName = user.email?.split('@').first.toUpperCase() ?? 'USER';
        await _db.collection(_collectionTyping).doc('${shopId}_${user.uid}').set({
          'shopId': shopId,
          'userId': user.uid,
          'userName': userName,
          'startedAt': FieldValue.serverTimestamp(),
        });
        
        // Auto clear after 5s
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 5), () {
          setTypingStatus(false);
        });
      } else {
        await _db.collection(_collectionTyping).doc('${shopId}_${user.uid}').delete();
        _typingTimer?.cancel();
      }
    } catch (e) {
      debugPrint('❌ Chat setTypingStatus error: $e');
    }
  }

  /// Stream người đang gõ
  static Stream<List<TypingUser>> typingUsersStream() async* {
    final user = FirebaseAuth.instance.currentUser;
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      yield [];
      return;
    }
    
    yield* _db.collection(_collectionTyping)
        .where('shopId', isEqualTo: shopId)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => TypingUser.fromMap(doc.data()))
              .where((t) => t.odUserId != user?.uid) // Exclude self
              .toList();
        });
  }

  // ============== ONLINE STATUS ==============

  /// Cập nhật trạng thái online
  static Future<void> setOnlineStatus(bool isOnline) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return;
      
      final userName = user.email?.split('@').first.toUpperCase() ?? 'USER';
      
      await _db.collection(_collectionOnline).doc('${shopId}_${user.uid}').set({
        'shopId': shopId,
        'userId': user.uid,
        'userName': userName,
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': isOnline,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ Chat setOnlineStatus error: $e');
    }
  }

  /// Stream users online
  static Stream<List<OnlineUser>> onlineUsersStream() async* {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      yield [];
      return;
    }
    
    yield* _db.collection(_collectionOnline)
        .where('shopId', isEqualTo: shopId)
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => OnlineUser.fromMap(doc.data()))
              .toList();
        });
  }

  // ============== SEARCH ==============

  /// Tìm kiếm tin nhắn
  static Future<List<ChatMessage>> searchMessages(String query) async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];
      
      final snapshot = await _db.collection(_collectionChats)
          .where('shopId', isEqualTo: shopId)
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();
      
      final queryLower = query.toLowerCase();
      return snapshot.docs
          .map((doc) => ChatMessage.fromSnapshot(doc))
          .where((msg) => 
              msg.message.toLowerCase().contains(queryLower) ||
              msg.senderName.toLowerCase().contains(queryLower) ||
              (msg.linkedSummary?.toLowerCase().contains(queryLower) ?? false))
          .toList();
    } catch (e) {
      debugPrint('❌ Chat searchMessages error: $e');
      return [];
    }
  }

  // ============== UTILITY ==============

  /// Lấy danh sách emoji reactions phổ biến
  static List<String> get commonReactions => ['👍', '❤️', '😂', '😮', '😢', '🔥', '👏', '🎉'];

  /// Lấy tin nhắn theo ID
  static Future<ChatMessage?> getMessageById(String messageId) async {
    try {
      final doc = await _db.collection(_collectionChats).doc(messageId).get();
      if (!doc.exists) return null;
      return ChatMessage.fromSnapshot(doc);
    } catch (e) {
      debugPrint('❌ Chat getMessageById error: $e');
      return null;
    }
  }

  /// Xóa tin nhắn cũ (admin only)
  static Future<int> deleteOldMessages(int daysOld) async {
    try {
      final isAdmin = await UserService.isCurrentUserAdmin();
      if (!isAdmin) return 0;
      
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return 0;
      
      final cutoff = DateTime.now().subtract(Duration(days: daysOld));
      
      final snapshot = await _db.collection(_collectionChats)
          .where('shopId', isEqualTo: shopId)
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoff))
          .where('isPinned', isEqualTo: false)
          .get();
      
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      
      debugPrint('🗑️ Chat: Deleted ${snapshot.docs.length} old messages');
      return snapshot.docs.length;
    } catch (e) {
      debugPrint('❌ Chat deleteOldMessages error: $e');
      return 0;
    }
  }

  /// Cleanup khi dispose
  static void cleanup() {
    _typingTimer?.cancel();
    setTypingStatus(false);
    setOnlineStatus(false);
  }
}
