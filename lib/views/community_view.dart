import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../services/community_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import 'staff_public_profile_view.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/responsive_wrapper.dart';
import '../widgets/safe_stream_builder.dart';

class CommunityView extends StatefulWidget {
  const CommunityView({
    super.key,
    this.initialPostId,
  });

  final String? initialPostId;

  @override
  State<CommunityView> createState() => _CommunityViewState();
}

class _CommunityViewState extends State<CommunityView> {
  final TextEditingController _postCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  String _shopId = '';
  String _shopName = '';
  bool _loading = true;
  bool _posting = false;
  File? _pickedImage;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _postsStream;
  int _visiblePostCount = 12;
  DateTime _streamStartedAt = DateTime.now();
  String _lastBuildSig = '';

  void _rt(String message) {
    debugPrint('[CommunityView] $message');
  }

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _postCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _visiblePostCount = 12;
      });
    }
    _rt('bootstrap:start');
    try {
      String shopId = (await UserService.getCurrentShopId() ?? '').trim();
      _rt('bootstrap:shopIdFromClaims=$shopId');

      if (shopId.isEmpty) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        if (uid != null && uid.isNotEmpty) {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .get();
          shopId = (userDoc.data()?['shopId'] ?? '').toString().trim();
          _rt('bootstrap:shopIdFromUserDoc=$shopId uid=$uid');
        }
      }

      _shopId = shopId;
      if (_shopId.isNotEmpty) {
        try {
          final shopDoc = await FirebaseFirestore.instance
              .collection('shops')
              .doc(_shopId)
              .get();
          _shopName = _safeString(shopDoc.data()?['name']).trim();
        } catch (_) {
          _shopName = '';
        }
      }
      _postsStream = _shopId.isEmpty
          ? null
          : CommunityService.streamPosts(
            shopId: _shopId,
            limit: _visiblePostCount + 8,
          );
      _streamStartedAt = DateTime.now();
    } catch (e) {
      _rt('bootstrap:error $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
      _rt('bootstrap:end loading=$_loading shopId=$_shopId');
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 2200,
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _pickedImage = File(picked.path));
  }

  Future<void> _submitPost() async {
    if (_posting || _shopId.isEmpty) return;
    setState(() => _posting = true);
    try {
      final ok = await CommunityService.createPost(
        shopId: _shopId,
        content: _postCtrl.text,
        imageFile: _pickedImage,
      );
      if (!ok) return;
      _postCtrl.clear();
      _pickedImage = null;
      if (!mounted) return;
      setState(() {});
      NotificationService.showSnackBar(
        'Đăng bài thành công',
        color: Colors.green,
      );
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  Future<void> _openComments({
    required String postId,
    required String postAuthor,
  }) async {
    final commentCtrl = TextEditingController();
    bool sending = false;
    bool sheetClosed = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return AnimatedPadding(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: FractionallySizedBox(
            heightFactor: 0.8,
            child: StatefulBuilder(
              builder: (sheetContext, setLocalState) {
                return PopScope(
                  onPopInvokedWithResult: (_, __) {
                    sheetClosed = true;
                  },
                  child: Column(
                  children: [
                    Container(
                      width: 42,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          Text(
                            'Bình luận của $postAuthor',
                            style: AppTextStyles.headline6,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: CommunityService.streamComments(postId),
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  _friendlyCommentError(snap.error),
                                  style: AppTextStyles.caption.copyWith(
                                    color: Colors.red.shade700,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          final docs = snap.data?.docs ?? const [];
                          if (docs.isEmpty) {
                            return Center(
                              child: Text(
                                'Chưa có bình luận nào',
                                style: AppTextStyles.caption,
                              ),
                            );
                          }
                          return ListView.separated(
                            reverse: true,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: docs.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final data = docs[index].data();
                              final authorName = _safeString(
                                data['authorName'],
                                fallback: 'Nhân viên',
                              );
                              final authorUid = _safeString(data['authorUid']);
                              final role = _safeString(data['authorRole']);
                              final content = _safeString(data['content']);
                              final photo =
                                  _safeString(data['authorPhotoUrl']).trim();
                              final createdAt = (data['createdAt'] as Timestamp?)
                                  ?.toDate();

                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    GestureDetector(
                                      onTap: authorUid.isEmpty
                                          ? null
                                          : () => _openUserProfile(authorUid),
                                      child: EntityAvatar(
                                        imageUrl: photo,
                                        name: authorName,
                                        radius: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '$authorName • $role',
                                            style: AppTextStyles.body2.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            content,
                                            style: AppTextStyles.body2,
                                          ),
                                          if (createdAt != null)
                                            Text(
                                              DateFormat('dd/MM HH:mm')
                                                  .format(createdAt),
                                              style: AppTextStyles.caption,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: commentCtrl,
                              maxLines: 3,
                              minLines: 1,
                              decoration: const InputDecoration(
                                hintText: 'Viết bình luận...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: sending
                                ? null
                                : () async {
                                    final text = commentCtrl.text.trim();
                                    if (text.isEmpty) return;
                                    if (sheetClosed || !sheetContext.mounted) return;
                                    setLocalState(() => sending = true);
                                    try {
                                      final ok = await CommunityService.addComment(
                                        postId: postId,
                                        content: text,
                                      );
                                      if (sheetClosed || !sheetContext.mounted) return;
                                      if (!ok) return;
                                      commentCtrl.clear();
                                    } finally {
                                      if (!sheetClosed && sheetContext.mounted) {
                                        setLocalState(() => sending = false);
                                      }
                                    }
                                  },
                            child: sending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send),
                          ),
                        ],
                      ),
                    ),
                  ],
                ));
              },
            ),
          ),
        );
      },
    ).whenComplete(() {
      sheetClosed = true;
      // Dispose after route pop animation/frame teardown to avoid
      // "TextEditingController was used after being disposed".
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 260), () {
          commentCtrl.dispose();
        });
      });
    });
  }

  Future<void> _openUserProfile(String uid) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StaffPublicProfileView(userId: uid),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sig = 'loading=$_loading|shopId=$_shopId|posting=$_posting';
    if (sig != _lastBuildSig) {
      _lastBuildSig = sig;
      _rt('build:$sig');
    }

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_shopId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cộng đồng shop')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.groups_2_outlined, size: 38, color: Colors.grey),
                const SizedBox(height: 10),
                Text(
                  'Không tìm thấy thông tin shop cho tài khoản hiện tại.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body1,
                ),
                const SizedBox(height: 8),
                Text(
                  'Vui lòng bấm Thử lại. Nếu vẫn lỗi, hãy đăng xuất và đăng nhập lại.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _bootstrap,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Thử lại'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _shopName.isEmpty ? 'Cộng đồng shop' : 'Cộng đồng • $_shopName',
        ),
      ),
      body: ResponsiveCenter(
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _postCtrl,
                    maxLines: 3,
                    minLines: 2,
                    decoration: const InputDecoration(
                      hintText:
                          'Hôm nay của bạn thế nào? Chia sẻ nhật ký, trạng thái hoặc thông tin cho cả shop...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_pickedImage != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 96,
                        width: double.infinity,
                        child: Image.file(_pickedImage!, fit: BoxFit.cover),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _actionChipButton(
                        onTap: _pickImage,
                        icon: Icons.image_outlined,
                        label: 'Thêm ảnh',
                      ),
                      if (_pickedImage != null) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => setState(() => _pickedImage = null),
                          child: const Text('Bỏ ảnh'),
                        ),
                      ],
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: _posting ? null : _submitPost,
                        icon: _posting
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded),
                        label: const Text('Đăng'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: _postsStream == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.groups_2_outlined, size: 28),
                            const SizedBox(height: 8),
                            Text(
                              'Chưa sẵn sàng kết nối bảng tin cộng đồng.',
                              style: AppTextStyles.body2,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            _actionChipButton(
                              onTap: _bootstrap,
                              icon: Icons.refresh,
                              label: 'Kết nối lại',
                            ),
                          ],
                        ),
                      ),
                    )
                  : SafeStreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _postsStream!,
                      shopId: _shopId,
                      builder: (context, snapshot) {
                    _rt('stream:${snapshot.connectionState.name} hasErr=${snapshot.hasError} docs=${snapshot.data?.docs.length ?? -1}');

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.red,
                              size: 30,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Không thể tải cộng đồng lúc này.',
                              style: AppTextStyles.body1.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _friendlyError(snapshot.error),
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.red.shade700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            _actionChipButton(
                              onTap: _bootstrap,
                              icon: Icons.refresh,
                              label: 'Tải lại cộng đồng',
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    final waited =
                        DateTime.now().difference(_streamStartedAt).inSeconds;
                    if (waited >= 8) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 10),
                              Text(
                                'Đang đồng bộ bảng tin... ($waited giây)',
                                style: AppTextStyles.body2,
                              ),
                              const SizedBox(height: 8),
                              _actionChipButton(
                                onTap: _bootstrap,
                                icon: Icons.refresh,
                                label: 'Thử lại',
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    return const Center(child: CircularProgressIndicator());
                  }

                  final docs = (snapshot.data?.docs ?? const [])
                      .where((d) => d.data()['deleted'] != true)
                      .toList()
                    ..sort((a, b) {
                      final ad = (a.data()['createdAt'] as Timestamp?)?.toDate();
                      final bd = (b.data()['createdAt'] as Timestamp?)?.toDate();
                      if (ad == null && bd == null) return 0;
                      if (ad == null) return 1;
                      if (bd == null) return -1;
                      return bd.compareTo(ad);
                    });
                  final targetPostId = (widget.initialPostId ?? '').trim();
                  if (targetPostId.isNotEmpty) {
                    final idx = docs.indexWhere((d) => d.id == targetPostId);
                    if (idx > 0) {
                      final target = docs.removeAt(idx);
                      docs.insert(0, target);
                    }
                  }
                  if (docs.isEmpty) {
                    return Center(
                      child: Text(
                        'Chưa có bài viết nào. Hãy là người đầu tiên chia sẻ!',
                        style: AppTextStyles.caption,
                      ),
                    );
                  }

                  final visibleDocs = docs.take(_visiblePostCount).toList();
                  final hasMore = docs.length > visibleDocs.length;

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: visibleDocs.length + (hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (hasMore && index == visibleDocs.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _visiblePostCount += 12;
                                _postsStream = _shopId.isEmpty
                                    ? null
                                    : CommunityService.streamPosts(
                                        shopId: _shopId,
                                        limit: _visiblePostCount + 8,
                                      );
                              });
                            },
                            icon: const Icon(Icons.expand_more_rounded),
                            label: Text(
                              'Tải thêm bài viết (${docs.length - visibleDocs.length})',
                            ),
                          ),
                        );
                      }

                      try {
                        final doc = visibleDocs[index];
                        final data = doc.data();

                        final authorUid = _safeString(data['authorUid']);
                        final authorName = _safeString(
                          data['authorName'],
                          fallback: 'Nhân viên',
                        );
                        final authorRole = _safeString(data['authorRole']);
                        final authorPhoto =
                            _safeString(data['authorPhotoUrl']).trim();
                        final content = _safeString(data['content']);
                        final imageUrl = _safeString(data['imageUrl']).trim();
                        final likedBy = _safeStringList(data['likedBy']);
                        final isLiked = likedBy.contains(currentUid);
                        final likeCount = _safeInt(
                          data['likeCount'],
                          fallback: likedBy.length,
                        );
                        final commentCount = _safeInt(data['commentCount']);
                        final createdAt =
                            (data['createdAt'] as Timestamp?)?.toDate();

                        final isTarget = targetPostId.isNotEmpty && doc.id == targetPostId;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isTarget ? Colors.blue.shade300 : Colors.grey.shade200,
                              width: isTarget ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            InkWell(
                              onTap: authorUid.isEmpty
                                  ? null
                                  : () => _openUserProfile(authorUid),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                                child: Row(
                                  children: [
                                    EntityAvatar(
                                      imageUrl: authorPhoto,
                                      name: authorName,
                                      radius: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            authorName,
                                            style: AppTextStyles.body1.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            createdAt == null
                                                ? _roleVi(authorRole)
                                                : '${_roleVi(authorRole)} • ${DateFormat('dd/MM HH:mm').format(createdAt)}',
                                            style: AppTextStyles.caption,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Icon(
                                      Icons.chevron_right,
                                      color: Colors.grey,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (content.trim().isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                child: Text(
                                  content,
                                  style: AppTextStyles.body1,
                                ),
                              ),
                            if (imageUrl.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                                child: InkWell(
                                  onTap: () {
                                    showDialog<void>(
                                      context: context,
                                      builder: (ctx) => Dialog.fullscreen(
                                        backgroundColor: Colors.black,
                                        child: Stack(
                                          children: [
                                            Positioned.fill(
                                              child: InteractiveViewer(
                                                maxScale: 5,
                                                minScale: 0.8,
                                                child: Center(
                                                  child: Image(
                                                    image: CachedNetworkImageProvider(
                                                      imageUrl,
                                                    ),
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            Positioned(
                                              top: 16,
                                              right: 16,
                                              child: IconButton(
                                                onPressed: () => Navigator.pop(ctx),
                                                icon: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: double.infinity,
                                      constraints: const BoxConstraints(
                                        minHeight: 120,
                                        maxHeight: 320,
                                      ),
                                      color: Colors.black.withValues(alpha: 0.04),
                                      child: Image(
                                        image: CachedNetworkImageProvider(imageUrl),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const Divider(height: 1),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: () async {
                                      await CommunityService.toggleLike(
                                        postId: doc.id,
                                        isLiked: isLiked,
                                      );
                                    },
                                    icon: Icon(
                                      isLiked
                                          ? Icons.favorite
                                          : Icons.favorite_border,
                                      color: isLiked
                                          ? Colors.red
                                          : Colors.grey.shade700,
                                      size: 18,
                                    ),
                                    label: Text('Thích ($likeCount)'),
                                  ),
                                ),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: () => _openComments(
                                      postId: doc.id,
                                      postAuthor: authorName,
                                    ),
                                    icon: const Icon(Icons.chat_bubble_outline),
                                    label: Text('Bình luận ($commentCount)'),
                                  ),
                                ),
                              ],
                            ),
                            ],
                          ),
                        );
                      } catch (e) {
                        _rt('feed:itemParseError index=$index err=$e');
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.orange.shade200),
                          ),
                          child: Text(
                            'Bỏ qua 1 bài viết lỗi dữ liệu. Hãy kiểm tra lại dữ liệu Firestore.',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.orange.shade700,
                            ),
                          ),
                        );
                      }
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _friendlyError(Object? error) {
    final raw = (error ?? '').toString();
    final normalized = raw.toLowerCase();
    if (normalized.contains('permission-denied')) {
      return 'Bạn chưa có quyền truy cập bảng tin của shop này. Vui lòng đăng nhập lại hoặc liên hệ quản lý.';
    }
    if (normalized.contains('failed-precondition') || normalized.contains('index')) {
      return 'Dữ liệu cộng đồng đang được tối ưu lần đầu. Vui lòng thử lại sau vài giây.';
    }
    if (normalized.contains('unavailable') || normalized.contains('network')) {
      return 'Mất kết nối mạng hoặc dịch vụ tạm gián đoạn. Vui lòng thử lại.';
    }
    if (normalized.contains('cloud_firestore')) {
      return 'Không tải được bảng tin do lỗi Firestore tạm thời. Vui lòng thử lại.';
    }
    return raw;
  }

  String _friendlyCommentError(Object? error) {
    final raw = (error ?? '').toString();
    final normalized = raw.toLowerCase();
    if (normalized.contains('permission-denied')) {
      return 'Bạn chưa có quyền xem bình luận của bài viết này.';
    }
    if (normalized.contains('cloud_firestore')) {
      return 'Không tải được bình luận do lỗi Firestore tạm thời. Vui lòng thử lại.';
    }
    return 'Không tải được bình luận: $raw';
  }

  String _roleVi(String role) {
    switch (role.trim().toLowerCase()) {
      case 'owner':
        return 'Chủ shop';
      case 'manager':
        return 'Quản lý';
      case 'technician':
        return 'Kỹ thuật';
      case 'employee':
        return 'Nhân viên';
      case 'admin':
        return 'Quản trị';
      default:
        return role.trim().isEmpty ? 'Nhân viên' : role;
    }
  }

  Widget _actionChipButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
  }) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(label, style: AppTextStyles.body2),
            ],
          ),
        ),
      ),
    );
  }

  String _safeString(dynamic value, {String fallback = ''}) {
    if (value == null) return fallback;
    return value.toString();
  }

  int _safeInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  List<String> _safeStringList(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const <String>[];
  }
}
