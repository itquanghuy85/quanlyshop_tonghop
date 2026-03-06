import 'dart:async';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class StorageService {
  static final FirebaseStorage _storage = FirebaseStorage.instance;

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

      if (kIsWeb) {
        // Web/mobile-browser: localPath thường là blob URL, upload theo bytes.
        final picked = XFile(localPath);
        return await uploadXFileAndGetUrl(picked, folder);
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
      Reference ref = _storage.ref().child(folder).child(fileName);
      
      UploadTask uploadTask = ref.putFile(fileToUpload);
      TaskSnapshot snapshot = await uploadTask.timeout(const Duration(seconds: 30));
      
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

      final ext = path.extension(picked.path).toLowerCase();
      final normalizedExt = ext.isEmpty ? '.jpg' : ext;
      final fileName =
          "${DateTime.now().millisecondsSinceEpoch}_${path.basenameWithoutExtension(picked.name.isEmpty ? 'image' : picked.name)}$normalizedExt";
      final ref = _storage.ref().child(folder).child(fileName);

      if (kIsWeb) {
        final bytes = await picked.readAsBytes();
        if (bytes.isEmpty) return null;
        final metadata = SettableMetadata(
          contentType: _guessImageMimeType(normalizedExt),
        );
        final snapshot = await ref
            .putData(bytes, metadata)
            .timeout(const Duration(seconds: 30));
        return await snapshot.ref.getDownloadURL();
      }

      final file = File(picked.path);
      if (!file.existsSync()) return null;
      final snapshot = await ref
          .putFile(file)
          .timeout(const Duration(seconds: 30));
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
