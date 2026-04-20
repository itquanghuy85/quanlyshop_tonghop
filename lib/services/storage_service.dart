import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;
  static final Map<String, String> _resolvedUrlCache = {};
  static const Set<String> _storageRoots = {
    'repairs',
    'attendance',
    'shop_logos',
    'user_photos',
    'chat_images',
    'products',
  };

  /// Normalize upload folder to match deployed storage.rules.
  /// Most roots only allow one segment (e.g. repairs/{fileName}),
  /// while chat_images/payment_requests require a shopId segment.
  static String _normalizeUploadFolderForRules(String folder) {
    final normalized = folder.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return 'products';

    final clean = normalized.startsWith('/')
        ? normalized.substring(1)
        : normalized;
    final parts = clean.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return 'products';

    final root = parts.first;
    if (root == 'chat_images' || root == 'payment_requests') {
      if (parts.length >= 2 && parts[1].isNotEmpty) {
        return '$root/${parts[1]}';
      }
      return root;
    }

    if (_storageRoots.contains(root)) {
      return root;
    }

    return clean;
  }

  static bool _isUnauthorizedStorageError(Object error) {
    if (error is FirebaseException) {
      return error.code == 'unauthorized' || error.code == 'permission-denied';
    }
    final message = error.toString().toLowerCase();
    return message.contains('firebase_storage/unauthorized') ||
        message.contains('permission denied');
  }

  static Future<String?> _getCurrentUserShopIdClaim() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final tokenResult = await user.getIdTokenResult();
      final claim = tokenResult.claims?['shopId'];
      if (claim is String && claim.trim().isNotEmpty) {
        return claim.trim();
      }
    } catch (_) {
      // Fallback handled by caller.
    }
    return null;
  }

  static Future<List<String>> _buildUploadFolderCandidates(
    String uploadFolder,
  ) async {
    final candidates = <String>[uploadFolder];
    final parts = uploadFolder
        .split('/')
        .where((e) => e.trim().isNotEmpty)
        .toList();

    if (parts.length == 1 &&
        parts.first != 'chat_images' &&
        parts.first != 'payment_requests') {
      final shopId = await _getCurrentUserShopIdClaim();
      if (shopId != null && shopId.isNotEmpty) {
        final scoped = '${parts.first}/$shopId';
        if (!candidates.contains(scoped)) {
          candidates.add(scoped);
        }
      }
    }

    return candidates;
  }

  static Future<TaskSnapshot> _uploadFileWithFolderFallback({
    required File file,
    required String fileName,
    required String uploadFolder,
    required SettableMetadata metadata,
  }) async {
    final candidates = await _buildUploadFolderCandidates(uploadFolder);
    Object? lastError;

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final isLast = i == candidates.length - 1;
      final ref = _storage.ref().child(candidate).child(fileName);
      final currentUser = FirebaseAuth.instance.currentUser;
      debugPrint(
        'StorageService: uploading ${path.basename(file.path)} to "$candidate" mime=${metadata.contentType} uid=${currentUser?.uid ?? 'null'}',
      );
      try {
        return await ref
            .putFile(file, metadata)
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        lastError = e;
        if (!isLast && _isUnauthorizedStorageError(e)) {
          debugPrint(
            'StorageService: unauthorized at "$candidate", retrying next fallback folder...',
          );
          continue;
        }
        rethrow;
      }
    }

    throw lastError ?? Exception('Unknown storage upload failure');
  }

  static Future<TaskSnapshot> _uploadBytesWithFolderFallback({
    required Uint8List bytes,
    required String fileName,
    required String uploadFolder,
    required SettableMetadata metadata,
  }) async {
    final candidates = await _buildUploadFolderCandidates(uploadFolder);
    Object? lastError;

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final isLast = i == candidates.length - 1;
      final ref = _storage.ref().child(candidate).child(fileName);
      final currentUser = FirebaseAuth.instance.currentUser;
      debugPrint(
        'StorageService: uploading bytes to "$candidate" mime=${metadata.contentType} uid=${currentUser?.uid ?? 'null'}',
      );
      try {
        return await ref
            .putData(bytes, metadata)
            .timeout(const Duration(seconds: 30));
      } catch (e) {
        lastError = e;
        if (!isLast && _isUnauthorizedStorageError(e)) {
          debugPrint(
            'StorageService: unauthorized at "$candidate", retrying next fallback folder...',
          );
          continue;
        }
        rethrow;
      }
    }

    throw lastError ?? Exception('Unknown storage upload failure');
  }

  /// Các extension hình ảnh được hỗ trợ nén
  static const List<String> _imageExtensions = [
    '.jpg', '.jpeg', '.png', '.webp', '.heic', '.heif'
  ];

  /// Kiểm tra file có phải là hình ảnh không
  static bool _isImageFile(String filePath) {
    final ext = path.extension(filePath).toLowerCase();
    return _imageExtensions.contains(ext);
  }

  /// Nén hình ảnh trước khi upload
  /// - Giảm quality xuống 70%
  /// - Giảm kích thước max 1920px
  /// - Chuyển sang JPEG để tiết kiệm dung lượng
  static Future<File?> _compressImage(File file) async {
    try {
      final filePath = file.path;
      final ext = path.extension(filePath).toLowerCase();

      // Lấy kích thước file gốc
      final originalSize = await file.length();
      debugPrint('📸 Nén ảnh: ${path.basename(filePath)} - Size gốc: ${(originalSize / 1024).toStringAsFixed(1)} KB');

      // Tạo đường dẫn file tạm để lưu ảnh nén
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final targetPath = '${tempDir.path}/compressed_$timestamp.jpg';

      // Xác định format output
      CompressFormat format = CompressFormat.jpeg;
      if (ext == '.png') {
        format = CompressFormat.png;
      } else if (ext == '.webp') {
        format = CompressFormat.webp;
      }

      // Nén ảnh
      final XFile? compressedXFile = await FlutterImageCompress.compressAndGetFile(
        filePath,
        targetPath,
        quality: 70, // Chất lượng 70%
        minWidth: 1920, // Max width
        minHeight: 1920, // Max height
        format: format,
        keepExif: false, // Bỏ metadata để giảm dung lượng
      );

      if (compressedXFile == null) {
        debugPrint('⚠️ Không thể nén ảnh, sử dụng file gốc');
        return file;
      }

      final compressedFile = File(compressedXFile.path);
      final compressedSize = await compressedFile.length();
      final savedPercent = ((originalSize - compressedSize) / originalSize * 100).toStringAsFixed(1);

      debugPrint('✅ Nén xong: ${(compressedSize / 1024).toStringAsFixed(1)} KB (giảm $savedPercent%)');

      // Nếu file nén lớn hơn file gốc, dùng file gốc
      if (compressedSize >= originalSize) {
        debugPrint('⚠️ File nén lớn hơn gốc, sử dụng file gốc');
        await compressedFile.delete();
        return file;
      }

      return compressedFile;
    } catch (e) {
      debugPrint('❌ Lỗi nén ảnh: $e');
      return file; // Trả về file gốc nếu nén lỗi
    }
  }

  /// Tự động upload và trả về URL để đồng bộ giữa các máy
  static Future<String?> uploadAndGetUrl(String localPath, String folder) async {
    try {
      if (localPath.startsWith('http')) return localPath; // Đã là link cloud

      final uploadFolder = _normalizeUploadFolderForRules(folder);
      if (uploadFolder != folder) {
        debugPrint(
          'StorageService: normalized folder "$folder" -> "$uploadFolder"',
        );
      }

      if (kIsWeb) {
        // Web/mobile-browser: localPath thường là blob URL, upload theo bytes.
        final picked = XFile(localPath);
        return await uploadXFileAndGetUrl(picked, uploadFolder);
      }

      File file = File(localPath);
      if (!file.existsSync()) return null;

      // Nén ảnh nếu là file hình ảnh
      File fileToUpload = file;
      if (_isImageFile(localPath)) {
        final compressedFile = await _compressImage(file);
        if (compressedFile != null) {
          fileToUpload = compressedFile;
        }
      }

      // Đặt tên file theo định dạng chuẩn: shopId_timestamp_name
      String fileName = "${DateTime.now().millisecondsSinceEpoch}_${path.basename(localPath)}";

      final ext = path.extension(fileToUpload.path).toLowerCase();
      final normalizedExt = ext.isEmpty ? '.jpg' : ext;
      final metadata = SettableMetadata(
        contentType: _guessImageMimeType(normalizedExt),
      );
      TaskSnapshot snapshot = await _uploadFileWithFolderFallback(
        file: fileToUpload,
        fileName: fileName,
        uploadFolder: uploadFolder,
        metadata: metadata,
      );

      // Xóa file nén tạm nếu có
      if (fileToUpload.path != file.path && fileToUpload.existsSync()) {
        try {
          await fileToUpload.delete();
        } catch (_) {}
      }

      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("STORAGE_ERROR: $e");
      return null;
    }
  }

  /// Upload trực tiếp từ XFile (an toàn cho web vì dùng bytes).
  static Future<String?> uploadXFileAndGetUrl(XFile picked, String folder) async {
    try {
      if (picked.path.startsWith('http')) return picked.path;

      final uploadFolder = _normalizeUploadFolderForRules(folder);
      if (uploadFolder != folder) {
        debugPrint(
          'StorageService: normalized folder "$folder" -> "$uploadFolder"',
        );
      }

      final ext = path.extension(picked.path).toLowerCase();
      final normalizedExt = ext.isEmpty ? '.jpg' : ext;
      final fileName =
          "${DateTime.now().millisecondsSinceEpoch}_${path.basenameWithoutExtension(picked.name.isEmpty ? 'image' : picked.name)}$normalizedExt";
      final ref = _storage.ref().child(uploadFolder).child(fileName);

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return null;
        final metadata = SettableMetadata(
          contentType: _guessImageMimeType(normalizedExt),
        );
        final snapshot = await _uploadBytesWithFolderFallback(
          bytes: bytes,
          fileName: fileName,
          uploadFolder: uploadFolder,
          metadata: metadata,
        );
        return await snapshot.ref.getDownloadURL();
      }

      final file = File(picked.path);
      if (!file.existsSync()) return null;

      // Compress image if applicable (attendance, repair photos)
      File fileToUpload = file;
      if (_isImageFile(picked.path)) {
        final compressed = await _compressImage(file);
        if (compressed != null) fileToUpload = compressed;
      }

      final nativeExt = path.extension(fileToUpload.path).toLowerCase();
      final nativeNormalizedExt = nativeExt.isEmpty ? '.jpg' : nativeExt;
      final nativeMetadata = SettableMetadata(
        contentType: _guessImageMimeType(nativeNormalizedExt),
      );

      final snapshot = await _uploadFileWithFolderFallback(
        file: fileToUpload,
        fileName: fileName,
        uploadFolder: uploadFolder,
        metadata: nativeMetadata,
      );

      // Clean up temp compressed file
      if (fileToUpload.path != file.path && fileToUpload.existsSync()) {
        try { await fileToUpload.delete(); } catch (_) {}
      }

      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      debugPrint("STORAGE_XFILE_ERROR: $e");
      return null;
    }
  }

  static String _guessImageMimeType(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
      case '.heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  static bool isGsStoragePath(String filePath) {
    return filePath.trim().toLowerCase().startsWith('gs://');
  }

  static bool isStorageRelativePath(String filePath) {
    final normalized = filePath.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    if (normalized.contains('://') ||
        normalized.startsWith('blob:') ||
        normalized.startsWith('data:')) {
      return false;
    }

    final cleanPath = normalized.startsWith('/')
        ? normalized.substring(1)
        : normalized;
    if (!cleanPath.contains('/')) return false;

    return _storageRoots.contains(cleanPath.split('/').first);
  }

  static bool isDisplayableCloudPath(String filePath) {
    final normalized = filePath.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.startsWith('http://') ||
        normalized.startsWith('https://') ||
        normalized.startsWith('blob:') ||
        normalized.startsWith('data:') ||
        isGsStoragePath(normalized) ||
        isStorageRelativePath(normalized);
  }

  static bool isResolvableDisplayPath(String filePath) {
    return isDisplayableCloudPath(filePath);
  }

  static Future<String?> resolveDisplayUrl(String filePath) async {
    final normalized = filePath.trim();
    if (normalized.isEmpty) return null;

    final lower = normalized.toLowerCase();
    if (lower.startsWith('http://') ||
        lower.startsWith('https://') ||
        lower.startsWith('blob:') ||
        lower.startsWith('data:')) {
      return normalized;
    }

    if (!isGsStoragePath(normalized) && !isStorageRelativePath(normalized)) {
      return kIsWeb ? null : normalized;
    }

    final cached = _resolvedUrlCache[normalized];
    if (cached != null && cached.isNotEmpty) return cached;

    try {
      final ref = isGsStoragePath(normalized)
          ? _storage.refFromURL(normalized)
          : _storage.ref(
              normalized.startsWith('/')
                  ? normalized.substring(1)
                  : normalized,
            );
      final url = await ref.getDownloadURL();
      _resolvedUrlCache[normalized] = url;
      return url;
    } catch (e) {
      debugPrint('StorageService: failed to resolve image path $normalized: $e');
      return null;
    }
  }

  /// Xử lý đồng loạt cho danh sách ảnh
  static Future<String> uploadMultipleAndJoin(String localPathsCsv, String folder) async {
    if (localPathsCsv.isEmpty) return "";
    List<String> paths = localPathsCsv.split(',').where((e) => e.trim().isNotEmpty).toList();
    List<String> urls = [];

    for (String p in paths) {
      String trimmed = p.trim();
      if (trimmed.isEmpty) continue;
      if (!kIsWeb && !File(trimmed).existsSync()) continue;
      String? url = await uploadAndGetUrl(trimmed, folder);
      if (url != null) urls.add(url);
    }
    return urls.join(',');
  }

  /// Upload multiple images and return list of URLs
  static Future<List<String>> uploadMultipleImages(List<String> localPaths, String folder) async {
    List<String> urls = [];
    for (String path in localPaths) {
      String? url = await uploadAndGetUrl(path, folder);
      if (url != null) urls.add(url);
    }
    return urls;
  }
}
