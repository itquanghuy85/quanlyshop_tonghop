import 'dart:async';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../widgets/responsive_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/chat_message_model.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/shop_settings_model.dart';
import '../services/chat_service.dart';
import '../services/user_service.dart';
import '../services/event_bus.dart';
import '../services/category_service.dart';
import '../data/db_helper.dart';
import '../utils/money_utils.dart';
import '../theme/app_text_styles.dart';
import 'repair_detail_view.dart';
import 'sale_detail_view.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/permission_gate.dart';
import 'community_view.dart';
import 'staff_public_profile_view.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Chat View đẳng cấp với đầy đủ tính năng
class AdvancedChatView extends StatefulWidget {
  const AdvancedChatView({super.key});

  @override
  State<AdvancedChatView> createState() => _AdvancedChatViewState();
}

class _AdvancedChatViewState extends State<AdvancedChatView>
    with WidgetsBindingObserver {
  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final DBHelper _db = DBHelper();

  // State
  bool _isLoading = true;
  bool _isSending = false;
  List<ChatMessage> _messages = [];
  List<ChatMessage> _pinnedMessages = [];
  List<TypingUser> _typingUsers = [];
  List<OnlineUser> _onlineUsers = [];
  final Map<String, String> _senderAvatarCache = {};
  String _chatBackgroundPresetKey = 'solid_light';
  String _chatBackgroundImagePath = '';
  String _chatBackgroundImageUrl = '';
  int _messageLimit = 20;
  bool _loadingMoreMessages = false;

  static const Map<String, Map<String, dynamic>> _chatBackgroundPresets = {
    'solid_light': {
      'label': 'Xám sáng',
      'colors': [0xFFF5F5F5],
    },
    'solid_sky': {
      'label': 'Xanh trời nhạt',
      'colors': [0xFFEFF6FF],
    },
    'solid_warm': {
      'label': 'Kem ấm',
      'colors': [0xFFFBF5E9],
    },
    'solid_mint': {
      'label': 'Xanh ngọc nhạt',
      'colors': [0xFFEDF9F6],
    },
    'gradient_sky': {
      'label': 'Gradient trời',
      'colors': [0xFFEAF4FF, 0xFFDDEBFF, 0xFFF8FBFF],
    },
    'gradient_peach': {
      'label': 'Gradient đào',
      'colors': [0xFFFFF1EB, 0xFFFFE4D9, 0xFFFFF8F3],
    },
    'gradient_mint': {
      'label': 'Gradient ngọc',
      'colors': [0xFFEDFDF8, 0xFFDDF7EE, 0xFFF7FFFC],
    },
  };

  // Reply state
  ChatMessage? _replyingTo;

  // Search state
  bool _isSearching = false;
  // ignore: unused_field
  String _searchQuery = ''; // Used in _toggleSearch but search feature WIP
  List<ChatMessage> _searchResults = [];

  // Subscriptions
  StreamSubscription? _messagesSubscription;
  StreamSubscription? _pinnedSubscription;
  StreamSubscription? _typingSubscription;
  StreamSubscription? _onlineSubscription;
  StreamSubscription? _shopChangedSubscription;

  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;
  bool get _enableRepair => _shopSettings?.enableRepair ?? true;

  // Emoji reactions
  final List<String> _reactions = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🔥',
    '👏',
    '🎉',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initChat();
    unawaited(_loadChatBackgroundColor());
    _msgCtrl.addListener(_onTyping);
    _scrollCtrl.addListener(_onMessageScroll);

    // Listen for shop changes to reinitialize chat
    _shopChangedSubscription = EventBus().on(EventBus.shopChanged, (_) async {
      debugPrint('🔄 AdvancedChatView: Shop changed, reinitializing chat...');

      // 1. Cancel all existing subscriptions
      _cancelSubscriptions();

      // 2. Clear current data and show loading
      if (mounted) {
        setState(() {
          _messages = [];
          _pinnedMessages = [];
          _typingUsers = [];
          _onlineUsers = [];
          _isLoading = true;
        });
      }

      // 3. Small delay to ensure cache is updated
      await Future.delayed(const Duration(milliseconds: 300));

      // 4. Reinitialize with new shop
      if (mounted) {
        _initChat();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelSubscriptions();
    _shopChangedSubscription?.cancel();
    _msgCtrl.removeListener(_onTyping);
    _scrollCtrl.removeListener(_onMessageScroll);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    ChatService.cleanup();
    super.dispose();
  }

  void _cancelSubscriptions() {
    _messagesSubscription?.cancel();
    _pinnedSubscription?.cancel();
    _typingSubscription?.cancel();
    _onlineSubscription?.cancel();
  }

  Future<void> _loadChatBackgroundColor() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString('advanced_chat_background_preset') ?? 'solid_light';
    final imagePath = prefs.getString('advanced_chat_background_image') ?? '';
    String imageUrl = prefs.getString('advanced_chat_background_image_url') ?? '';

    if (imageUrl.trim().isEmpty) {
      try {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          imageUrl = (userDoc.data()?['chatBackgroundUrl'] ?? '')
              .toString()
              .trim();
          if (imageUrl.isNotEmpty) {
            await prefs.setString('advanced_chat_background_image_url', imageUrl);
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _chatBackgroundPresetKey = _chatBackgroundPresets.containsKey(value)
          ? value
          : 'solid_light';
      _chatBackgroundImagePath = imagePath;
      _chatBackgroundImageUrl = imageUrl;
    });
  }

  Future<void> _setChatBackgroundPreset(String presetKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('advanced_chat_background_preset', presetKey);
    if (!mounted) return;
    setState(() => _chatBackgroundPresetKey = presetKey);
  }

  Future<void> _pickChatBackgroundImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 3200,
    );
    if (picked == null) return;

    final croppedFile = await _openChatBackgroundEditor(File(picked.path));
    if (croppedFile == null) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('advanced_chat_background_image', croppedFile.path);
    if (!mounted) return;
    setState(() => _chatBackgroundImagePath = croppedFile.path);
    _showSuccess('Đã cập nhật ảnh nền chat, đang đồng bộ nền...');
    unawaited(_uploadChatBackgroundToCloud(croppedFile));
  }

  Future<void> _uploadChatBackgroundToCloud(File croppedFile) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null || uid.isEmpty) return;

      final url = await ChatService.uploadImageFileAndGetUrl(
        croppedFile,
        'user_photos/$uid',
      );
      if (url == null || url.trim().isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('advanced_chat_background_image_url', url);
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'chatBackgroundUrl': url,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _chatBackgroundImageUrl = url);
      _showSuccess('Đã đồng bộ nền chat');
    } catch (e) {
      debugPrint('Chat background upload failed: $e');
    }
  }

  Future<File?> _openChatBackgroundEditor(File sourceFile) async {
    final bytes = await sourceFile.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      _showError('Không đọc được ảnh đã chọn');
      return null;
    }

    final imageAspect = decoded.width / decoded.height;
    const targetAspect = 16 / 9;
    double cropTopFactor = 0.5;

    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Crop nền chat (16:9)'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AspectRatio(
                    aspectRatio: targetAspect,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(sourceFile, fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    imageAspect > targetAspect
                        ? 'Ảnh rộng, sẽ crop ngang ở giữa.'
                        : 'Ảnh cao, kéo thanh để chọn vùng crop.',
                    style: AppTextStyles.caption,
                  ),
                  if (imageAspect <= targetAspect) ...[
                    const SizedBox(height: 6),
                    Slider(
                      value: cropTopFactor,
                      onChanged: (v) => setDialogState(() => cropTopFactor = v),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Dùng ảnh này'),
                ),
              ],
            );
          },
        );
      },
    );

    if (accepted != true) return null;

    int cropX = 0;
    int cropY = 0;
    int cropW = decoded.width;
    int cropH = decoded.height;

    if (imageAspect > targetAspect) {
      cropH = decoded.height;
      cropW = (cropH * targetAspect).round();
      cropX = ((decoded.width - cropW) / 2).round();
    } else {
      cropW = decoded.width;
      cropH = (cropW / targetAspect).round();
      final maxTop = (decoded.height - cropH).clamp(0, decoded.height);
      cropY = (maxTop * cropTopFactor).round();
    }

    final cropped = img.copyCrop(
      decoded,
      x: cropX,
      y: cropY,
      width: cropW,
      height: cropH,
    );

    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(
      tempDir.path,
      'chat_background_${DateTime.now().millisecondsSinceEpoch}.jpg',
    );
    final outFile = File(outPath);
    await outFile.writeAsBytes(img.encodeJpg(cropped, quality: 92), flush: true);
    return outFile;
  }

  Future<void> _clearChatBackgroundImage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('advanced_chat_background_image');
    await prefs.remove('advanced_chat_background_image_url');

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      unawaited(
        FirebaseFirestore.instance.collection('users').doc(uid).set({
          'chatBackgroundUrl': '',
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)),
      );
    }

    if (!mounted) return;
    setState(() {
      _chatBackgroundImagePath = '';
      _chatBackgroundImageUrl = '';
    });
    _showSuccess('Đã xoá ảnh nền chat');
  }

  ImageProvider? get _chatBackgroundImageProvider {
    final cloudUrl = _chatBackgroundImageUrl.trim();
    if (cloudUrl.isNotEmpty) {
      return CachedNetworkImageProvider(cloudUrl);
    }

    final path = _chatBackgroundImagePath.trim();
    if (path.isEmpty) return null;
    if (kIsWeb) {
      return NetworkImage(path);
    }
    final file = File(path);
    if (!file.existsSync()) return null;
    return FileImage(file);
  }

  List<Color> get _chatBackgroundColors {
    final raw = _chatBackgroundPresets[_chatBackgroundPresetKey]?['colors'] as List<dynamic>?;
    if (raw == null || raw.isEmpty) {
      return const [Color(0xFFF5F5F5)];
    }
    return raw.map((value) => Color(value as int)).toList();
  }

  BoxDecoration get _chatBackgroundDecoration {
    final colors = _chatBackgroundColors;
    final backgroundImage = _chatBackgroundImageProvider;
    if (colors.length == 1) {
      return BoxDecoration(
        color: colors.first,
        image: backgroundImage != null
            ? DecorationImage(
                image: backgroundImage,
                fit: BoxFit.cover,
                opacity: 0.28,
              )
            : null,
      );
    }
    return BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ),
      image: backgroundImage != null
          ? DecorationImage(
              image: backgroundImage,
              fit: BoxFit.cover,
              opacity: 0.24,
            )
          : null,
    );
  }

  Future<void> _showChatBackgroundPicker() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chọn nền chat',
              style: TextStyle(
                fontSize: AppTextStyles.headline3.fontSize,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _pickChatBackgroundImage();
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Chọn và crop ảnh nền'),
                  ),
                ),
                if (_chatBackgroundImagePath.trim().isNotEmpty) ...[
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await _clearChatBackgroundImage();
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Xóa ảnh'),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _chatBackgroundPresets.entries.map((entry) {
                final meta = entry.value;
                final colors = (meta['colors'] as List<dynamic>).map((value) => Color(value as int)).toList();
                final selected = _chatBackgroundPresetKey == entry.key;
                return InkWell(
                  onTap: () async {
                    await _setChatBackgroundPreset(entry.key);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 108,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? AppBarAccents.chat : Colors.grey.shade300,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: colors.first,
                            gradient: colors.length > 1
                                ? LinearGradient(
                                    colors: colors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          meta['label'] as String,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: AppTextStyles.subtitle1.fontSize,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _avatarInitial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
  }

  String? _resolveSenderAvatarUrl(ChatMessage message) {
    final fromMessage = (message.senderAvatar ?? '').trim();
    if (fromMessage.isNotEmpty) return fromMessage;
    final fromCache = (_senderAvatarCache[message.senderId] ?? '').trim();
    if (fromCache.isNotEmpty) return fromCache;
    return null;
  }

  Widget _buildSenderAvatar(ChatMessage message, {double radius = 16}) {
    final avatarUrl = _resolveSenderAvatarUrl(message);
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.grey.shade100,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: avatarUrl,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => Text(
              _avatarInitial(message.senderName),
              style: TextStyle(
                fontSize: radius - 2,
                fontWeight: FontWeight.w700,
                color: Colors.blueGrey.shade700,
              ),
            ),
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.blueGrey.shade100,
      child: Text(
        _avatarInitial(message.senderName),
        style: TextStyle(
          fontSize: radius - 2,
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade700,
        ),
      ),
    );
  }

  Future<void> _openStaffProfile(
    String uid, {
    String? fallbackName,
  }) async {
    if (uid.trim().isEmpty || uid == 'system') return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffPublicProfileView(
          userId: uid,
          fallbackName: fallbackName,
        ),
      ),
    );
  }

  Future<void> _syncSenderAvatarCache(List<ChatMessage> messages) async {
    final pending = messages
        .where((m) => m.senderId.isNotEmpty && m.senderId != 'system')
        .map((m) => m.senderId)
        .where((uid) {
          final hasInline = messages.any((m) =>
              m.senderId == uid &&
              (m.senderAvatar ?? '').trim().isNotEmpty);
          return !hasInline && (_senderAvatarCache[uid] ?? '').trim().isEmpty;
        })
        .toSet()
        .toList();

    if (pending.isEmpty) return;

    const chunkSize = 10;
    final found = <String, String>{};

    for (var i = 0; i < pending.length; i += chunkSize) {
      final chunk = pending.sublist(
        i,
        i + chunkSize > pending.length ? pending.length : i + chunkSize,
      );
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final url = (doc.data()['photoUrl'] ?? '').toString().trim();
          if (url.isNotEmpty) {
            found[doc.id] = url;
          }
        }
      } catch (e) {
        debugPrint('Chat avatar cache load failed: $e');
      }
    }

    if (!mounted || found.isEmpty) return;
    setState(() {
      _senderAvatarCache.addAll(found);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ChatService.setOnlineStatus(true);
    } else if (state == AppLifecycleState.paused) {
      ChatService.setOnlineStatus(false);
    }
  }

  void _initChat() async {
    setState(() => _isLoading = true);

    // Load shop settings for multi-industry support
    final settings = await CategoryService().getShopSettings();
    if (mounted && settings != null) {
      setState(() => _shopSettings = settings);
    }

    // Set online
    await ChatService.setOnlineStatus(true);

    // Mark all chat as read for this user (for badge count)
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await UserService.markChatAsRead(uid);
    }

    // Subscribe to messages
    _messagesSubscription = ChatService.messagesStream(limit: _messageLimit).listen((
      messages,
    ) {
      if (mounted) {
        setState(() {
          _messages = messages;
          _isLoading = false;
          _loadingMoreMessages = false;
        });
        _syncSenderAvatarCache(messages);
        // Mark as read
        for (final msg in messages.take(5)) {
          if (msg.id != null) ChatService.markAsRead(msg.id!);
        }
      }
    });

    // Subscribe to pinned
    _pinnedSubscription = ChatService.pinnedMessagesStream().listen((pinned) {
      if (mounted) setState(() => _pinnedMessages = pinned);
    });

    // Subscribe to typing
    _typingSubscription = ChatService.typingUsersStream().listen((users) {
      if (mounted) setState(() => _typingUsers = users);
    });

    // Subscribe to online users
    _onlineSubscription = ChatService.onlineUsersStream().listen((users) {
      if (mounted) setState(() => _onlineUsers = users);
    });
  }

  void _onTyping() {
    if (_msgCtrl.text.isNotEmpty) {
      ChatService.setTypingStatus(true);
    }
  }

  void _onMessageScroll() {
    if (!_scrollCtrl.hasClients || _loadingMoreMessages) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 120) {
      _loadMoreMessages();
    }
  }

  void _loadMoreMessages() {
    if (_loadingMoreMessages) return;
    if (_messages.length < _messageLimit) return;

    setState(() {
      _loadingMoreMessages = true;
      _messageLimit = (_messageLimit + 20).clamp(20, 200);
    });

    _messagesSubscription?.cancel();
    _messagesSubscription = ChatService.messagesStream(limit: _messageLimit).listen(
      (messages) {
        if (!mounted) return;
        setState(() {
          _messages = messages;
          _loadingMoreMessages = false;
        });
        _syncSenderAvatarCache(messages);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _loadingMoreMessages = false);
      },
    );
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);

    try {
      await ChatService.sendTextMessage(
        message: text,
        replyToId: _replyingTo?.id,
        replyToMessage: _replyingTo?.message,
        replyToSender: _replyingTo?.senderName,
      );

      _msgCtrl.clear();
      _cancelReply();
      _scrollToBottom();
    } catch (e) {
      _showError('Không thể gửi tin nhắn');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  void _startReply(ChatMessage message) {
    setState(() => _replyingTo = message);
    _focusNode.requestFocus();
  }

  Future<void> _pickAndSendImage() async {
    try {
      final picker = ImagePicker();
      final images = await picker.pickMultiImage(imageQuality: 70);

      if (images.isEmpty) return;

      setState(() => _isSending = true);

      final files = images.map((xfile) => File(xfile.path)).toList();
      await ChatService.sendImageMessage(images: files);

      _scrollToBottom();
    } catch (e) {
      _showError('Không thể gửi hình ảnh');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _showReactionPicker(ChatMessage message) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null || message.id == null) return;

    showAppBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Chọn biểu cảm',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTextStyles.headline3.fontSize,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _reactions.map((emoji) {
                final hasReacted = message.hasUserReacted(userId, emoji);
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    ChatService.toggleReaction(message.id!, emoji, hasReacted);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasReacted
                          ? Colors.blue.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: hasReacted
                          ? Border.all(color: Colors.blue, width: 2)
                          : null,
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                );
              }).toList(),
            ),
            SizedBox(height: MediaQuery.of(ctx).padding.bottom + 16),
          ],
        ),
      ),
    );
  }

  void _showMessageActions(ChatMessage message) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final isOwner = message.senderId == userId;

    showAppBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _actionTile(
              icon: Icons.reply,
              label: 'Trả lời',
              onTap: () {
                Navigator.pop(ctx);
                _startReply(message);
              },
            ),
            _actionTile(
              icon: Icons.add_reaction_outlined,
              label: 'Thêm biểu cảm',
              onTap: () {
                Navigator.pop(ctx);
                _showReactionPicker(message);
              },
            ),
            _actionTile(
              icon: Icons.copy,
              label: 'Sao chép',
              onTap: () {
                Navigator.pop(ctx);
                Clipboard.setData(ClipboardData(text: message.message));
                _showSuccess('Đã sao chép');
              },
            ),
            _actionTile(
              icon: message.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              label: message.isPinned ? 'Bỏ ghim' : 'Ghim tin nhắn',
              onTap: () {
                Navigator.pop(ctx);
                if (message.id != null) {
                  ChatService.pinMessage(message.id!, !message.isPinned);
                }
              },
            ),
            if (isOwner) ...[
              _actionTile(
                icon: Icons.edit,
                label: 'Chỉnh sửa',
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditDialog(message);
                },
              ),
              _actionTile(
                icon: Icons.delete_outline,
                label: 'Xóa',
                color: Colors.red,
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmDelete(message);
                },
              ),
            ],
            SizedBox(height: MediaQuery.of(ctx).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  void _showEditDialog(ChatMessage message) {
    final editCtrl = TextEditingController(text: message.message);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Chỉnh sửa tin nhắn'),
        content: TextField(
          controller: editCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Nội dung tin nhắn...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (message.id != null && editCtrl.text.trim().isNotEmpty) {
                ChatService.editMessage(message.id!, editCtrl.text.trim());
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(ChatMessage message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xóa tin nhắn?'),
        content: const Text('Tin nhắn sẽ bị xóa và không thể khôi phục.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              if (message.id != null) ChatService.deleteMessage(message.id!);
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _showPinOrderDialog() async {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        // Multi-Industry: Determine tabs based on enabled features
        final showRepair = _enableRepair;
        final tabCount = showRepair ? 2 : 1;

        return Container(
          height: MediaQuery.of(ctx).size.height * 0.7,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: DefaultTabController(
            length: tabCount,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Gim đơn hàng vào chat',
                        style: TextStyle(
                          fontSize: AppTextStyles.headline2.fontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                TabBar(
                  labelColor: Colors.blue,
                  tabs: [
                    if (showRepair)
                      const Tab(icon: Icon(Icons.build, size: 18), text: 'Sửa'),
                    const Tab(
                      icon: Icon(Icons.shopping_cart, size: 18),
                      text: 'Bán',
                    ),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      if (showRepair) _buildRepairList(),
                      _buildSaleList(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRepairList() {
    return FutureBuilder<List<Repair>>(
      future: _db.getAllRepairs(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final repairs = snapshot.data!.take(20).toList();
        if (repairs.isEmpty) {
          return const Center(child: Text('Chưa có đơn sửa chữa'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: repairs.length,
          itemBuilder: (ctx, i) {
            final r = repairs[i];
            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: _getStatusColor(r.status),
                  child: const Icon(Icons.build, color: Colors.white, size: 20),
                ),
                title: Text(
                  r.customerName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${r.model} - ${r.issue}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  _getStatusText(r.status),
                  style: TextStyle(
                    color: _getStatusColor(r.status),
                    fontSize: AppTextStyles.subtitle1.fontSize,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pinRepairOrder(r);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSaleList() {
    return FutureBuilder<List<SaleOrder>>(
      future: _db.getAllSales(),
      builder: (ctx, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final sales = snapshot.data!.take(20).toList();
        if (sales.isEmpty) {
          return const Center(child: Text('Chưa có đơn bán hàng'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: sales.length,
          itemBuilder: (ctx, i) {
            final s = sales[i];
            return Card(
              child: ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Colors.green,
                  child: Icon(
                    Icons.shopping_cart,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                title: Text(
                  s.customerName.isNotEmpty ? s.customerName : 'Khách lẻ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  s.productNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Text(
                  MoneyUtils.formatCompactCurrency(s.totalPrice),
                  style: const TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pinSaleOrder(s);
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _pinRepairOrder(Repair repair) async {
    final message =
        '''
🛠️ ĐƠN SỬA CHỮA #${repair.id}
👤 ${repair.customerName} - 📱 ${repair.phone}
📲 ${repair.model}
🔧 ${repair.issue}
💰 ${repair.price > 0 ? '${NumberFormat('#,###').format(repair.price)}đ' : 'Chưa báo giá'}
📊 ${_getStatusText(repair.status)}''';

    await ChatService.sendLinkedMessage(
      message: message,
      linkedType: 'repair',
      linkedKey: repair.firestoreId ?? repair.id.toString(),
      linkedSummary: 'Đơn #${repair.id} - ${repair.customerName}',
    );

    _scrollToBottom();
  }

  Future<void> _pinSaleOrder(SaleOrder sale) async {
    final message =
        '''
🛒 ĐƠN BÁN HÀNG
👤 ${sale.customerName.isNotEmpty ? sale.customerName : 'Khách lẻ'} - 📱 ${sale.phone.isNotEmpty ? sale.phone : 'N/A'}
📦 ${sale.productNames}
💰 ${NumberFormat('#,###').format(sale.totalPrice)}đ
💳 ${sale.paymentMethod}''';

    await ChatService.sendLinkedMessage(
      message: message,
      linkedType: 'sale',
      linkedKey: sale.firestoreId ?? 'sale_${sale.soldAt}',
      linkedSummary:
          '${sale.customerName.isNotEmpty ? sale.customerName : 'Khách lẻ'} - ${MoneyUtils.formatCompactCurrency(sale.totalPrice)}',
    );

    _scrollToBottom();
  }

  void _toggleSearch() {
    setState(() {
      _isSearching = !_isSearching;
      if (!_isSearching) {
        _searchQuery = '';
        _searchResults = [];
      }
    });
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      setState(() => _searchResults = []);
      return;
    }

    final results = await ChatService.searchMessages(query);
    if (mounted) setState(() => _searchResults = results);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  /// Mở dialog xem hình ảnh lớn
  void _openImageViewer(
    List<String> urls,
    int initialIndex,
    String? senderName,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ImageViewerDialog(
          imageUrls: urls,
          initialIndex: initialIndex,
          senderName: senderName,
        ),
      ),
    );
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1:
        return Colors.blue;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.green;
      case 4:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(int status) {
    switch (status) {
      case 1:
        return 'Đã nhận';
      case 2:
        return 'Đang sửa';
      case 3:
        return 'Xong';
      case 4:
        return 'Đã giao';
      default:
        return '?';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: _buildAppBar(),
      body: ResponsiveCenter(
        child: Container(
          decoration: _chatBackgroundDecoration,
          child: Column(
            children: [
              // Pinned messages
              if (_pinnedMessages.isNotEmpty) _buildPinnedSection(),

              // Online users indicator
              if (_onlineUsers.isNotEmpty) _buildOnlineIndicator(),

              // Messages list
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _isSearching && _searchResults.isNotEmpty
                    ? _buildSearchResults()
                    : _buildMessagesList(),
              ),

              // Typing indicator
              if (_typingUsers.isNotEmpty) _buildTypingIndicator(),

              // Reply preview
              if (_replyingTo != null) _buildReplyPreview(),

              // Input area
              _buildInputArea(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppBarAccents.chat, AppBarAccents.chat.withOpacity(0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      title: _isSearching
          ? Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                autofocus: true,
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: AppTextStyles.headline3.fontSize,
                ),
                cursorColor: AppBarAccents.chat,
                decoration: InputDecoration(
                  hintText: 'Tìm tin nhắn...',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  prefixIcon: Icon(
                    Icons.search,
                    color: Colors.grey.shade500,
                    size: 20,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onChanged: _search,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chat nội bộ',
                  style: TextStyle(
                    fontSize: AppTextStyles.headline3.fontSize,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (_onlineUsers.isNotEmpty)
                  Text(
                    '${_onlineUsers.length} người online',
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                      fontWeight: FontWeight.w400,
                      color: Colors.white70,
                    ),
                  ),
              ],
            ),
      actions: [
        IconButton(
          icon: const Icon(Icons.groups_2_outlined, size: 22, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CommunityView()),
            );
          },
          tooltip: 'Cộng đồng shop',
          splashRadius: 20,
        ),
        IconButton(
          icon: Icon(
            _isSearching ? Icons.close : Icons.search_rounded,
            size: 22,
            color: Colors.white,
          ),
          onPressed: _toggleSearch,
          splashRadius: 20,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, size: 22, color: Colors.white),
          splashRadius: 20,
          onSelected: (value) {
            switch (value) {
              case 'markRead':
                ChatService.markAllAsRead();
                _showSuccess('Đã đánh dấu tất cả đã đọc');
                break;
              case 'pinned':
                _showPinnedMessages();
                break;
              case 'sendPrintLink':
                _showSendPrintLinkDialog();
                break;
              case 'chatBackground':
                _showChatBackgroundPicker();
                break;
            }
          },
          itemBuilder: (ctx) => [
            const PopupMenuItem(
              value: 'markRead',
              child: Text('Đánh dấu đã đọc'),
            ),
            const PopupMenuItem(value: 'pinned', child: Text('Tin ghim')),
            const PopupMenuItem(
              value: 'chatBackground',
              child: Text('Nền chat'),
            ),
            const PopupMenuItem(
              value: 'sendPrintLink',
              child: Text('Gửi link in web'),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: Colors.white.withOpacity(0.2), height: 1),
      ),
    );
  }

  Widget _buildPinnedSection() {
    final latestPin = _pinnedMessages.first;
    // isMe reserved for future styling (own pins vs others)
    // ignore: unused_local_variable
    final isMe = latestPin.senderId == FirebaseAuth.instance.currentUser?.uid;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.amber.shade100, Colors.amber.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withAlpha(40),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _showPinnedMessages,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Pin icon với animation pulse
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.push_pin,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            '📌 ${_pinnedMessages.length} tin ghim',
                            style: TextStyle(
                              fontSize: AppTextStyles.body1.fontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '• ${latestPin.senderName}',
                            style: TextStyle(
                              fontSize: AppTextStyles.caption.fontSize,
                              color: Colors.amber.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        latestPin.messageType == 'image'
                            ? '📷 Hình ảnh'
                            : latestPin.message,
                        style: TextStyle(
                          fontSize: AppTextStyles.headline5.fontSize,
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade200,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.expand_more,
                    size: 18,
                    color: Colors.amber.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPinnedMessages() {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.6,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.push_pin, color: Colors.amber),
                  const SizedBox(width: 8),
                  Text(
                    'Tin nhắn đã ghim',
                    style: TextStyle(
                      fontSize: AppTextStyles.headline2.fontSize,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _pinnedMessages.length,
                itemBuilder: (ctx, i) =>
                    _buildMessageBubble(_pinnedMessages[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.green.shade50,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _onlineUsers.map((u) => u.userName).join(', '),
              style: TextStyle(
                fontSize: AppTextStyles.subtitle1.fontSize,
                color: Colors.green,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có tin nhắn',
              style: TextStyle(color: Colors.grey.shade500),
            ),
            const SizedBox(height: 8),
            Text(
              'Hãy gửi tin nhắn đầu tiên!',
              style: TextStyle(
                color: Colors.grey.shade400,
                fontSize: AppTextStyles.headline5.fontSize,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollCtrl,
      reverse: true,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length + (_loadingMoreMessages ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (_loadingMoreMessages && i == _messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return _buildMessageBubble(_messages[i]);
      },
    );
  }

  Widget _buildSearchResults() {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _searchResults.length,
      itemBuilder: (ctx, i) => _buildMessageBubble(_searchResults[i]),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    final isMe = message.senderId == userId;
    final isSystem = message.messageType == 'system';

    if (isSystem) {
      return _buildSystemMessage(message);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // Reply preview
          if (message.replyToMessage != null)
            Container(
              margin: EdgeInsets.only(
                left: isMe ? 60 : 0,
                right: isMe ? 0 : 60,
                bottom: 4,
              ),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                  left: BorderSide(color: Colors.blue, width: 3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.replyToSender ?? '',
                    style: TextStyle(
                      fontSize: AppTextStyles.body1.fontSize,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  Text(
                    message.replyToMessage!,
                    style: TextStyle(
                      fontSize: AppTextStyles.subtitle1.fontSize,
                      color: Colors.grey,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

          // Message bubble + avatar
          Row(
            mainAxisAlignment: isMe
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isMe) ...[
                GestureDetector(
                  onTap: () => _openStaffProfile(
                    message.senderId,
                    fallbackName: message.senderName,
                  ),
                  child: _buildSenderAvatar(message),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _showMessageActions(message),
                  onDoubleTap: () => _showReactionPicker(message),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: (MediaQuery.sizeOf(context).width * 0.72)
                          .clamp(0, 460),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isMe ? const Color(0xFF2962FF) : Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isMe ? 16 : 4),
                        bottomRight: Radius.circular(isMe ? 4 : 16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(10),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Sender name
                        if (!isMe)
                          Text(
                            message.senderName,
                            style: TextStyle(
                              fontSize: AppTextStyles.body1.fontSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade700,
                            ),
                          ),

                  // Priority indicator
                  if (message.priority > 0)
                    Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Color(message.priorityColor).withAlpha(30),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        message.priority == 2 ? '🔴 KHẨN' : '🟠 QUAN TRỌNG',
                        style: TextStyle(
                          fontSize: AppTextStyles.caption.fontSize,
                          fontWeight: FontWeight.bold,
                          color: Color(message.priorityColor),
                        ),
                      ),
                    ),

                  // Message content
                  _buildMessageText(message, isMe),

                  // Linked order
                  if (message.linkedType != null &&
                      message.linkedSummary != null)
                    GestureDetector(
                      onTap: () => _openLinkedOrder(message),
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isMe
                              ? Colors.white.withAlpha(30)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              message.linkedType == 'repair'
                                  ? Icons.build
                                  : Icons.shopping_cart,
                              size: 16,
                              color: isMe ? Colors.white70 : Colors.blue,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                message.linkedSummary!,
                                style: TextStyle(
                                  fontSize: AppTextStyles.subtitle1.fontSize,
                                  color: isMe ? Colors.white : Colors.black87,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.chevron_right,
                              size: 16,
                              color: isMe ? Colors.white54 : Colors.grey,
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Images - bấm vào để xem lớn
                  if (message.mediaUrls != null &&
                      message.mediaUrls!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: message.mediaUrls!.asMap().entries.map((
                          entry,
                        ) {
                          final index = entry.key;
                          final url = entry.value;
                          return GestureDetector(
                            onTap: () => _openImageViewer(
                              message.mediaUrls!,
                              index,
                              message.senderName,
                            ),
                            child: Hero(
                              tag: 'chat_image_$url',
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedNetworkImage(
                                  imageUrl: url,
                                  width: 150,
                                  height: 150,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 300,
                                  memCacheHeight: 300,
                                  placeholder: (_, __) => Container(
                                    width: 150,
                                    height: 150,
                                    color: Colors.grey.shade200,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                        // Footer: time + edited + pin
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('HH:mm').format(message.createdAt),
                              style: TextStyle(
                                fontSize: AppTextStyles.caption.fontSize,
                                color: isMe ? Colors.white60 : Colors.grey,
                              ),
                            ),
                            if (message.isEdited) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(đã sửa)',
                                style: TextStyle(
                                  fontSize: AppTextStyles.caption.fontSize,
                                  fontStyle: FontStyle.italic,
                                  color: isMe ? Colors.white60 : Colors.grey,
                                ),
                              ),
                            ],
                            if (message.isPinned) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.push_pin,
                                size: 12,
                                color:
                                    isMe ? Colors.amber.shade200 : Colors.amber,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: 8),
                _buildSenderAvatar(message),
              ],
            ],
          ),

          // Reactions
          if (message.totalReactions > 0)
            Container(
              margin: EdgeInsets.only(
                top: 4,
                left: isMe ? 0 : 8,
                right: isMe ? 8 : 0,
              ),
              child: Wrap(
                spacing: 4,
                children: message.reactions!.entries
                    .where((e) => e.value.isNotEmpty)
                    .map(
                      (e) => GestureDetector(
                        onTap: () {
                          if (message.id != null && userId != null) {
                            ChatService.toggleReaction(
                              message.id!,
                              e.key,
                              e.value.contains(userId),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: e.value.contains(userId)
                                ? Colors.blue.shade50
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: e.value.contains(userId)
                                ? Border.all(color: Colors.blue.shade200)
                                : null,
                          ),
                          child: Text(
                            '${e.key} ${e.value.length}',
                            style: TextStyle(
                              fontSize: AppTextStyles.subtitle1.fontSize,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSystemMessage(ChatMessage message) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          message.message,
          style: TextStyle(
            fontSize: AppTextStyles.subtitle1.fontSize,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildMessageText(ChatMessage message, bool isMe) {
    final text = message.message;
    final baseStyle = TextStyle(
      color: isMe ? Colors.white : Colors.black87,
      fontStyle: message.isDeleted ? FontStyle.italic : FontStyle.normal,
    );
    if (message.isDeleted) {
      return Text(text, style: baseStyle);
    }

    final regex = RegExp(r'(https?://[^\s]+)', caseSensitive: false);
    final matches = regex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final m in matches) {
      if (m.start > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, m.start), style: baseStyle),
        );
      }
      final urlText = text.substring(m.start, m.end);
      spans.add(
        TextSpan(
          text: urlText,
          style: baseStyle.copyWith(
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.w600,
            color: isMe ? Colors.white : Colors.blue.shade700,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              _openChatUrl(urlText);
            },
        ),
      );
      cursor = m.end;
    }
    if (cursor < text.length) {
      spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
    }

    return RichText(text: TextSpan(children: spans));
  }

  Future<void> _openChatUrl(String rawUrl) async {
    try {
      final uri = Uri.parse(rawUrl.trim());
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        _showError('Không mở được link');
      }
    } catch (_) {
      _showError('Link không hợp lệ');
    }
  }

  Future<void> _showSendPrintLinkDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final existingBridgeUrl = (prefs.getString('web_print_bridge_url') ?? '')
        .trim();

    String defaultBridgeIp = '192.168.1.10';
    try {
      if (existingBridgeUrl.isNotEmpty) {
        final uri = Uri.parse(existingBridgeUrl);
        if (uri.host.isNotEmpty) {
          defaultBridgeIp = uri.host;
        }
      }
    } catch (_) {}

    final bridgeIpCtrl = TextEditingController(text: defaultBridgeIp);
    final bridgePortCtrl = TextEditingController(text: '19191');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gửi link in web'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: bridgeIpCtrl,
              decoration: const InputDecoration(
                labelText: 'IP máy chạy bridge',
                hintText: 'VD: 192.168.1.10',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bridgePortCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Port',
                hintText: '19191',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () async {
              final bridgeIp = bridgeIpCtrl.text.trim();
              final bridgePort = bridgePortCtrl.text.trim().isEmpty
                  ? '19191'
                  : bridgePortCtrl.text.trim();
              if (bridgeIp.isEmpty) {
                _showError('Vui lòng nhập IP bridge');
                return;
              }

              final bridgeEndpoint = 'http://$bridgeIp:$bridgePort/print';
              final token = (prefs.getString('web_print_bridge_token') ?? '')
                  .trim();

              final query = <String, String>{'bridgeUrl': bridgeEndpoint};
              if (token.isNotEmpty) {
                query['bridgeToken'] = token;
              }
              final link = Uri.https(
                'quanlyshop.web.app',
                '/',
                query,
              ).toString();

              await prefs.setString('web_print_bridge_url', bridgeEndpoint);

              await ChatService.sendTextMessage(
                message:
                    '🖨️ Link in web cho điện thoại:\n$link\n\nChỉ cần bấm link -> mở đơn -> bấm IN.',
              );

              if (mounted) {
                Navigator.pop(ctx);
                _showSuccess('Đã gửi link in vào chat');
              }
            },
            child: const Text('Gửi link'),
          ),
        ],
      ),
    );
  }

  Future<void> _openLinkedOrder(ChatMessage message) async {
    if (message.linkedType == null || message.linkedKey == null) return;

    try {
      if (message.linkedType == 'repair') {
        if (!PermissionGateCheck.check(context, 'allowViewRepairs')) return;
        final repair = await _db.getRepairByFirestoreId(message.linkedKey!);
        if (repair != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => RepairDetailView(repair: repair)),
          );
        }
      } else if (message.linkedType == 'sale') {
        if (!PermissionGateCheck.check(context, 'allowViewSales')) return;
        final sale = await _db.getSaleByFirestoreId(message.linkedKey!);
        if (sale != null && mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => SaleDetailView(sale: sale)),
          );
        }
      }
    } catch (e) {
      _showError('Không thể mở đơn hàng');
    }
  }

  Widget _buildTypingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: 24, height: 16, child: _TypingDots()),
          const SizedBox(width: 8),
          Text(
            '${_typingUsers.map((u) => u.userName).join(', ')} đang nhập...',
            style: TextStyle(
              fontSize: AppTextStyles.subtitle1.fontSize,
              color: Colors.grey,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trả lời ${_replyingTo!.senderName}',
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                Text(
                  _replyingTo!.message,
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    color: Colors.grey,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Image button
            IconButton(
              icon: const Icon(Icons.image, color: Colors.blue),
              onPressed: _isSending ? null : _pickAndSendImage,
              tooltip: 'Gửi hình ảnh',
            ),

            // Pin order button
            IconButton(
              icon: const Icon(Icons.attach_file, color: Colors.orange),
              onPressed: _showPinOrderDialog,
              tooltip: 'Gim đơn hàng',
            ),

            // Text field
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _msgCtrl,
                  focusNode: _focusNode,
                  maxLines: 4,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: InputDecoration(
                    hintText: 'Nhập tin nhắn...',
                    hintStyle: TextStyle(color: Colors.grey.shade500),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send button
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF2962FF),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: _isSending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white),
                onPressed: _isSending ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog xem hình ảnh lớn
class _ImageViewerDialog extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;
  final String? senderName;

  const _ImageViewerDialog({
    required this.imageUrls,
    this.initialIndex = 0,
    this.senderName,
  });

  @override
  State<_ImageViewerDialog> createState() => _ImageViewerDialogState();
}

class _ImageViewerDialogState extends State<_ImageViewerDialog> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.senderName != null)
              Text(
                widget.senderName!,
                style: TextStyle(
                  fontSize: AppTextStyles.headline4.fontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            if (widget.imageUrls.length > 1)
              Text(
                '${_currentIndex + 1}/${widget.imageUrls.length}',
                style: TextStyle(
                  fontSize: AppTextStyles.subtitle1.fontSize,
                  color: Colors.white70,
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Chức năng tải xuống sẽ được phát triển'),
                ),
              );
            },
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imageUrls.length,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Hero(
                tag: 'chat_image_${widget.imageUrls[index]}',
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrls[index],
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Animated typing dots
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (i) {
      return AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
      );
    });

    _animations = _controllers.map((c) {
      return Tween<double>(
        begin: 0,
        end: 1,
      ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut));
    }).toList();

    _startAnimation();
  }

  void _startAnimation() async {
    while (mounted) {
      for (int i = 0; i < 3; i++) {
        if (!mounted) return;
        _controllers[i].forward();
        await Future.delayed(const Duration(milliseconds: 150));
      }
      await Future.delayed(const Duration(milliseconds: 200));
      for (var c in _controllers) {
        c.reverse();
      }
      await Future.delayed(const Duration(milliseconds: 400));
    }
  }

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _animations[i],
          builder: (ctx, child) {
            return Transform.translate(
              offset: Offset(0, -4 * _animations[i].value),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey.shade500,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
