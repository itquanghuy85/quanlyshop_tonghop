import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Reusable cached network image widget.
/// Automatically caches images on disk + memory, shows placeholder & error.
class AppCachedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  /// Memory cache dimensions — decode at this size instead of full resolution.
  /// Dramatically reduces memory for thumbnails in lists.
  final int? memCacheWidth;
  final int? memCacheHeight;

  const AppCachedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      placeholder: (_, __) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.grey.shade400,
            ),
          ),
        ),
      ),
      errorWidget: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Colors.grey.shade200,
        child: Icon(Icons.broken_image, color: Colors.grey.shade400, size: 24),
      ),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}
