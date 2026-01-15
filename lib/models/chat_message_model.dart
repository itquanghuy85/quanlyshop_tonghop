import 'package:cloud_firestore/cloud_firestore.dart';

/// Model tin nhắn chat nâng cao
class ChatMessage {
  String? id;
  String shopId;
  String senderId;
  String senderName;
  String? senderAvatar;
  String message;
  
  // Message type: text, image, file, system, linked_order
  String messageType;
  
  // Media attachments
  List<String>? mediaUrls;
  String? fileUrl;
  String? fileName;
  int? fileSize;
  
  // Reply functionality
  String? replyToId;
  String? replyToMessage;
  String? replyToSender;
  
  // Linked order (repair/sale)
  String? linkedType; // repair, sale, product, expense
  String? linkedKey;
  String? linkedSummary;
  Map<String, dynamic>? linkedData;
  
  // Reactions
  Map<String, List<String>>? reactions; // emoji -> list of userIds
  
  // Read receipts
  List<String> readBy;
  
  // Mentions
  List<String>? mentions; // list of userIds mentioned
  
  // Status
  bool isEdited;
  bool isDeleted;
  String? editedMessage;
  
  // Timestamps
  DateTime createdAt;
  DateTime? updatedAt;
  
  // Priority/pinned
  bool isPinned;
  int priority; // 0 = normal, 1 = important, 2 = urgent

  ChatMessage({
    this.id,
    required this.shopId,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    required this.message,
    this.messageType = 'text',
    this.mediaUrls,
    this.fileUrl,
    this.fileName,
    this.fileSize,
    this.replyToId,
    this.replyToMessage,
    this.replyToSender,
    this.linkedType,
    this.linkedKey,
    this.linkedSummary,
    this.linkedData,
    this.reactions,
    this.readBy = const [],
    this.mentions,
    this.isEdited = false,
    this.isDeleted = false,
    this.editedMessage,
    required this.createdAt,
    this.updatedAt,
    this.isPinned = false,
    this.priority = 0,
  });

  Map<String, dynamic> toMap() {
    return {
      'shopId': shopId,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'message': message,
      'messageType': messageType,
      'mediaUrls': mediaUrls,
      'fileUrl': fileUrl,
      'fileName': fileName,
      'fileSize': fileSize,
      'replyToId': replyToId,
      'replyToMessage': replyToMessage,
      'replyToSender': replyToSender,
      'linkedType': linkedType,
      'linkedKey': linkedKey,
      'linkedSummary': linkedSummary,
      'linkedData': linkedData,
      'reactions': reactions,
      'readBy': readBy,
      'mentions': mentions,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'editedMessage': editedMessage,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'isPinned': isPinned,
      'priority': priority,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map, {String? docId}) {
    return ChatMessage(
      id: docId ?? map['id'],
      shopId: map['shopId'] ?? '',
      senderId: map['senderId'] ?? '',
      senderName: map['senderName'] ?? '',
      senderAvatar: map['senderAvatar'],
      message: map['message'] ?? '',
      messageType: map['messageType'] ?? 'text',
      mediaUrls: (map['mediaUrls'] as List?)?.cast<String>(),
      fileUrl: map['fileUrl'],
      fileName: map['fileName'],
      fileSize: map['fileSize'],
      replyToId: map['replyToId'],
      replyToMessage: map['replyToMessage'],
      replyToSender: map['replyToSender'],
      linkedType: map['linkedType'],
      linkedKey: map['linkedKey'],
      linkedSummary: map['linkedSummary'],
      linkedData: map['linkedData'] as Map<String, dynamic>?,
      reactions: _parseReactions(map['reactions']),
      readBy: (map['readBy'] as List?)?.cast<String>() ?? [],
      mentions: (map['mentions'] as List?)?.cast<String>(),
      isEdited: map['isEdited'] ?? false,
      isDeleted: map['isDeleted'] ?? false,
      editedMessage: map['editedMessage'],
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      isPinned: map['isPinned'] ?? false,
      priority: map['priority'] ?? 0,
    );
  }

  static Map<String, List<String>>? _parseReactions(dynamic reactions) {
    if (reactions == null) return null;
    if (reactions is Map) {
      return reactions.map((key, value) =>
          MapEntry(key.toString(), (value as List?)?.cast<String>() ?? []));
    }
    return null;
  }

  factory ChatMessage.fromSnapshot(DocumentSnapshot<Map<String, dynamic>> doc) {
    return ChatMessage.fromMap(doc.data() ?? {}, docId: doc.id);
  }

  /// Kiểm tra tin nhắn có phải của user hiện tại
  bool isFromUser(String userId) => senderId == userId;

  /// Lấy số lượng reaction theo emoji
  int getReactionCount(String emoji) => reactions?[emoji]?.length ?? 0;

  /// Lấy tổng số reactions
  int get totalReactions {
    if (reactions == null) return 0;
    return reactions!.values.fold(0, (sum, list) => sum + list.length);
  }

  /// Kiểm tra user đã react emoji này chưa
  bool hasUserReacted(String userId, String emoji) {
    return reactions?[emoji]?.contains(userId) ?? false;
  }

  /// Icon theo loại tin nhắn
  String get typeIcon {
    switch (messageType) {
      case 'image': return '🖼️';
      case 'file': return '📎';
      case 'system': return '⚙️';
      case 'linked_order': return linkedType == 'repair' ? '🔧' : '🛒';
      default: return '💬';
    }
  }

  /// Màu priority
  int get priorityColor {
    switch (priority) {
      case 2: return 0xFFD32F2F; // urgent - red
      case 1: return 0xFFFF9800; // important - orange
      default: return 0xFF2196F3; // normal - blue
    }
  }

  ChatMessage copyWith({
    String? id,
    String? shopId,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? message,
    String? messageType,
    List<String>? mediaUrls,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? replyToId,
    String? replyToMessage,
    String? replyToSender,
    String? linkedType,
    String? linkedKey,
    String? linkedSummary,
    Map<String, dynamic>? linkedData,
    Map<String, List<String>>? reactions,
    List<String>? readBy,
    List<String>? mentions,
    bool? isEdited,
    bool? isDeleted,
    String? editedMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPinned,
    int? priority,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      shopId: shopId ?? this.shopId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      message: message ?? this.message,
      messageType: messageType ?? this.messageType,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      replyToId: replyToId ?? this.replyToId,
      replyToMessage: replyToMessage ?? this.replyToMessage,
      replyToSender: replyToSender ?? this.replyToSender,
      linkedType: linkedType ?? this.linkedType,
      linkedKey: linkedKey ?? this.linkedKey,
      linkedSummary: linkedSummary ?? this.linkedSummary,
      linkedData: linkedData ?? this.linkedData,
      reactions: reactions ?? this.reactions,
      readBy: readBy ?? this.readBy,
      mentions: mentions ?? this.mentions,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      editedMessage: editedMessage ?? this.editedMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPinned: isPinned ?? this.isPinned,
      priority: priority ?? this.priority,
    );
  }
}

/// Typing indicator model
class TypingUser {
  final String odUserId;
  final String userName;
  final DateTime startedAt;

  TypingUser({
    required this.odUserId,
    required this.userName,
    required this.startedAt,
  });

  Map<String, dynamic> toMap() => {
    'userId': odUserId,
    'userName': userName,
    'startedAt': Timestamp.fromDate(startedAt),
  };

  factory TypingUser.fromMap(Map<String, dynamic> map) {
    return TypingUser(
      odUserId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      startedAt: (map['startedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

/// Online user model
class OnlineUser {
  final String odUserId;
  final String userName;
  final String? avatar;
  final DateTime lastSeen;
  final bool isOnline;

  OnlineUser({
    required this.odUserId,
    required this.userName,
    this.avatar,
    required this.lastSeen,
    this.isOnline = false,
  });

  Map<String, dynamic> toMap() => {
    'userId': odUserId,
    'userName': userName,
    'avatar': avatar,
    'lastSeen': Timestamp.fromDate(lastSeen),
    'isOnline': isOnline,
  };

  factory OnlineUser.fromMap(Map<String, dynamic> map) {
    return OnlineUser(
      odUserId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      avatar: map['avatar'],
      lastSeen: (map['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isOnline: map['isOnline'] ?? false,
    );
  }
}
