import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Widget avatar chung cho khách hàng, nhà cung cấp, đối tác sửa chữa.
/// - Hiển thị ảnh từ URL hoặc fallback chữ cái đầu tên
/// - Bấm ảnh để xem phóng to (nếu tappableToView = true)
/// - Hiển thị nút camera để đổi ảnh (nếu showEditButton = true)
class EntityAvatar extends StatelessWidget {
  final String? imageUrl;
  final String name;
  final double radius;
  final Color? backgroundColor;
  final bool showEditButton;
  final VoidCallback? onEditTap;
  final bool tappableToView;

  const EntityAvatar({
    super.key,
    this.imageUrl,
    required this.name,
    this.radius = 22,
    this.backgroundColor,
    this.showEditButton = false,
    this.onEditTap,
    this.tappableToView = true,
  });

  // Lấy 1-2 ký tự đầu tên
  String get _initials {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    final parts = trimmed.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts.first[0] + parts.last[0]).toUpperCase();
    }
    return trimmed[0].toUpperCase();
  }

  // Màu nền tự động theo hash tên
  static const _bgColors = [
    Color(0xFF4285F4),
    Color(0xFF34A853),
    Color(0xFFEA4335),
    Color(0xFFFBBC04),
    Color(0xFF9C27B0),
    Color(0xFF00BCD4),
    Color(0xFFFF5722),
    Color(0xFF607D8B),
    Color(0xFF00897B),
    Color(0xFF1976D2),
  ];

  Color get _autoColor {
    if (name.isEmpty) return AppColors.primary;
    int hash = 0;
    for (final c in name.codeUnits) {
      hash = hash * 31 + c;
    }
    return _bgColors[hash.abs() % _bgColors.length];
  }

  static ImageProvider? imageProviderFromUrl(String url) {
    if (url.isEmpty) return null;
    if (url.startsWith('http') ||
        url.startsWith('blob:') ||
        url.startsWith('data:')) {
      return CachedNetworkImageProvider(url, maxWidth: 400, maxHeight: 400);
    }
    if (!kIsWeb) {
      final f = File(url);
      if (f.existsSync()) return FileImage(f);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final url = (imageUrl ?? '').trim();
    final bg = backgroundColor ?? _autoColor;
    final imgProv = imageProviderFromUrl(url);

    Widget avatar = CircleAvatar(
      radius: radius,
      backgroundColor: bg,
      backgroundImage: imgProv,
      child: imgProv == null
          ? Text(
              _initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: radius * 0.65,
              ),
            )
          : null,
    );

    if (showEditButton) {
      avatar = Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          Positioned(
            bottom: -2,
            right: -2,
            child: GestureDetector(
              onTap: onEditTap,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Icon(
                  Icons.camera_alt,
                  color: Colors.white,
                  size: radius * 0.5,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (tappableToView && imgProv != null) {
      avatar = GestureDetector(
        onTap: () => showPreview(context, url, name),
        child: avatar,
      );
    }

    return SizedBox(
      width: radius * 2 + (showEditButton ? 8 : 0),
      height: radius * 2 + (showEditButton ? 8 : 0),
      child: avatar,
    );
  }

  /// Mở dialog xem ảnh lớn
  static void showPreview(BuildContext context, String? imageUrl, String name) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return;
    final imgProv = imageProviderFromUrl(imageUrl.trim());
    if (imgProv == null) return;
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              constraints:
                  const BoxConstraints(maxWidth: 420, maxHeight: 420),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: Image(
                    image: imgProv,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Container(
                      width: 200,
                      height: 200,
                      color: Colors.grey.shade800,
                      child: const Icon(Icons.broken_image,
                          color: Colors.white54, size: 64),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ),
            ),
            if (name.isNotEmpty)
              Positioned(
                bottom: 16,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
