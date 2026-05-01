import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import '../services/user_service.dart';
import '../services/notification_service.dart';
import '../services/audit_service.dart';
import '../services/storage_service.dart';
import '../services/data_migration_service.dart';
import '../services/sync_service.dart';
import '../services/claims_service.dart';
import '../services/category_service.dart';
import '../services/osm_map_service.dart';
import '../widgets/app_cached_image.dart';
import '../widgets/entity_avatar.dart';
import '../models/shop_settings_model.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/responsive_wrapper.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_colors.dart';
import 'adjustment_history_view.dart';
import 'hr_salary_settings_view.dart';
import 'label_designer_view.dart';
import 'onboarding/business_type_wizard.dart';

class ShopSettingsView extends StatefulWidget {
  const ShopSettingsView({super.key});

  @override
  State<ShopSettingsView> createState() => _ShopSettingsViewState();
}

class _ShopSettingsViewState extends State<ShopSettingsView> {
  final _formKey = GlobalKey<FormState>();
  bool _isDisposing = false;
  bool _loading = true;
  bool _saving = false;

  // Shop data
  String _shopName = '';
  String _shopAddress = '';
  String _shopPhone = '';
  String _shopEmail = '';
  String _shopDescription = '';
  String _shopLogoUrl = '';
  String _shopCoverUrl = '';
  double _shopCoverAlignX = 0;
  double _shopCoverAlignY = 0;
  double? _shopLatitude;
  double? _shopLongitude;
  bool _requireLocationForAttendance = false;
  File? _selectedLogo;
  File? _selectedCover;

  // Multi-Industry: Shop Settings
  ShopSettings? _shopSettings;

  // Controllers
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadShopData();
    _loadShopSettings();
  }

  @override
  void dispose() {
    _isDisposing = true;
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted || _isDisposing) return;
    setState(fn);
  }

  Future<void> _loadShopData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      NotificationService.showSnackBar("Vui lòng đăng nhập", color: Colors.red);
      _safeSetState(() => _loading = false);
      return;
    }

    // Strategy: Try multiple sources to get shopId
    // 1. UserService cache/claims
    // 2. Firestore users doc
    // 3. Fallback to uid (owner case)
    String? shopId;

    try {
      shopId = await UserService.getCurrentShopId();
    } catch (e) {
      debugPrint('UserService.getCurrentShopId failed: $e');
    }

    // If no shopId from claims, try reading from users doc directly
    if (shopId == null || shopId.isEmpty) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists) {
          shopId = userDoc.data()?['shopId'] as String?;
          debugPrint('Got shopId from users doc: $shopId');
        }
      } catch (e) {
        debugPrint('Failed to read users doc: $e');
      }
    }

    // Final fallback: use uid as shopId (owner case)
    if (shopId == null || shopId.isEmpty) {
      shopId = user.uid;
      debugPrint('Using uid as shopId fallback: $shopId');
    }

    // Now try to load shop data with retry
    for (int retry = 0; retry < 3; retry++) {
      try {
        final shopDoc = await FirebaseFirestore.instance
            .collection('shops')
            .doc(shopId)
            .get();
        Map<String, dynamic>? data = shopDoc.data();

        // Legacy fallback: some shops cannot update top-level doc due old owner metadata.
        // In that case profile is stored under shops/{shopId}/settings/shop_profile.
        final shouldTryProfileFallback = data == null ||
            (((data['name'] ?? '').toString().trim().isEmpty) &&
                ((data['address'] ?? '').toString().trim().isEmpty) &&
                ((data['phone'] ?? '').toString().trim().isEmpty));
        if (shouldTryProfileFallback) {
          final profile = await _loadShopProfileFallback(shopId);
          if (profile != null && profile.isNotEmpty) {
            data = {...?data, ...profile};
            debugPrint('Loaded shop profile fallback from settings/shop_profile');
          }
        }

        if (shopDoc.exists) {
          final safeData = data ?? <String, dynamic>{};
          _safeSetState(() {
            _shopName = safeData['name'] ?? '';
            _shopAddress = safeData['address'] ?? '';
            _shopPhone = safeData['phone'] ?? '';
            _shopEmail = safeData['email'] ?? '';
            _shopDescription = safeData['description'] ?? '';
            _shopLogoUrl = safeData['logoUrl'] ?? '';
            _shopCoverUrl =
              (safeData['coverUrl'] ?? safeData['bannerUrl'] ?? '')
                .toString();
            _shopCoverAlignX =
                (safeData['coverAlignX'] as num?)?.toDouble() ?? 0;
            _shopCoverAlignY =
                (safeData['coverAlignY'] as num?)?.toDouble() ?? 0;
            _shopLatitude = (safeData['latitude'] as num?)?.toDouble();
            _shopLongitude = (safeData['longitude'] as num?)?.toDouble();
            _requireLocationForAttendance =
                safeData['requireLocationForAttendance'] == true;

            _nameController.text = _shopName;
            _addressController.text = _shopAddress;
            _phoneController.text = _shopPhone;
            _emailController.text = _shopEmail;
            _descriptionController.text = _shopDescription;
          });
          await _syncToSharedPreferences(_shopName, _shopAddress, _shopPhone);
          debugPrint('Shop data loaded successfully');
          break;
        } else {
          final profileOnly = await _loadShopProfileFallback(shopId);
          if (profileOnly != null && profileOnly.isNotEmpty) {
            _safeSetState(() {
              _shopName = profileOnly['name'] ?? '';
              _shopAddress = profileOnly['address'] ?? '';
              _shopPhone = profileOnly['phone'] ?? '';
              _shopEmail = profileOnly['email'] ?? '';
              _shopDescription = profileOnly['description'] ?? '';
              _shopLogoUrl = profileOnly['logoUrl'] ?? '';
                _shopCoverUrl =
                  (profileOnly['coverUrl'] ?? profileOnly['bannerUrl'] ?? '')
                    .toString();
              _shopCoverAlignX =
                  (profileOnly['coverAlignX'] as num?)?.toDouble() ?? 0;
              _shopCoverAlignY =
                  (profileOnly['coverAlignY'] as num?)?.toDouble() ?? 0;
              _shopLatitude = (profileOnly['latitude'] as num?)?.toDouble();
              _shopLongitude = (profileOnly['longitude'] as num?)?.toDouble();

              _nameController.text = _shopName;
              _addressController.text = _shopAddress;
              _phoneController.text = _shopPhone;
              _emailController.text = _shopEmail;
              _descriptionController.text = _shopDescription;
            });
            await _syncToSharedPreferences(_shopName, _shopAddress, _shopPhone);
            debugPrint('Shop profile loaded from fallback document');
            break;
          }

          // Shop doc doesn't exist yet - this is normal for new registration
          debugPrint('Shop doc not found, may be new registration');
          break;
        }
      } catch (e) {
        debugPrint('Retry ${retry + 1}/3 - Load shop failed: $e');

        // Permission on top-level doc can fail for legacy shops; try profile fallback.
        final profileFallback = await _loadShopProfileFallback(shopId);
        if (profileFallback != null && profileFallback.isNotEmpty) {
          _safeSetState(() {
            _shopName = profileFallback['name'] ?? '';
            _shopAddress = profileFallback['address'] ?? '';
            _shopPhone = profileFallback['phone'] ?? '';
            _shopEmail = profileFallback['email'] ?? '';
            _shopDescription = profileFallback['description'] ?? '';
            _shopLogoUrl = profileFallback['logoUrl'] ?? '';
            _shopCoverUrl =
              (profileFallback['coverUrl'] ??
                  profileFallback['bannerUrl'] ??
                  '')
                .toString();
            _shopCoverAlignX =
                (profileFallback['coverAlignX'] as num?)?.toDouble() ?? 0;
            _shopCoverAlignY =
                (profileFallback['coverAlignY'] as num?)?.toDouble() ?? 0;
            _shopLatitude = (profileFallback['latitude'] as num?)?.toDouble();
            _shopLongitude = (profileFallback['longitude'] as num?)?.toDouble();

            _nameController.text = _shopName;
            _addressController.text = _shopAddress;
            _phoneController.text = _shopPhone;
            _emailController.text = _shopEmail;
            _descriptionController.text = _shopDescription;
          });
          await _syncToSharedPreferences(_shopName, _shopAddress, _shopPhone);
          debugPrint('Loaded shop profile fallback after load error');
          break;
        }

        if (retry < 2) {
          // Wait a bit for claims to sync before retry
          await Future.delayed(const Duration(seconds: 2));
          // Try refreshing token
          try {
            await user.getIdToken(true);
          } catch (_) {}
        } else {
          // Final retry failed - show user-friendly error
          NotificationService.showSnackBar(
            "Đang chờ quyền truy cập. Vui lòng thử lại sau vài giây.",
            color: Colors.orange,
          );
        }
      }
    }

    _safeSetState(() => _loading = false);
  }

  bool _isPermissionDeniedError(Object error) {
    if (error is FirebaseException) {
      return error.code == 'permission-denied';
    }
    final message = error.toString().toLowerCase();
    return message.contains('permission-denied') ||
        message.contains('insufficient permissions');
  }

  Future<Map<String, dynamic>?> _loadShopProfileFallback(String shopId) async {
    try {
      final profileDoc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .collection('settings')
          .doc('shop_profile')
          .get();
      if (!profileDoc.exists) return null;
      return profileDoc.data();
    } catch (e) {
      debugPrint('Failed to load shop_profile fallback: $e');
      return null;
    }
  }

  Future<void> _saveShopProfileFallback(
    String shopId,
    Map<String, dynamic> profile,
  ) async {
    final safePayload = {
      'name': profile['name'] ?? '',
      'address': profile['address'] ?? '',
      'phone': profile['phone'] ?? '',
      'email': profile['email'] ?? '',
      'description': profile['description'] ?? '',
      'logoUrl': profile['logoUrl'] ?? '',
      'coverUrl': profile['coverUrl'] ?? '',
      'coverAlignX': profile['coverAlignX'] ?? 0,
      'coverAlignY': profile['coverAlignY'] ?? 0,
      'latitude': profile['latitude'],
      'longitude': profile['longitude'],
      'shopId': shopId,
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': FirebaseAuth.instance.currentUser?.uid,
    };

    await FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .collection('settings')
        .doc('shop_profile')
        .set(safePayload, SetOptions(merge: true));
  }

  Future<void> _saveMainShopProfile(
    String shopId,
    Map<String, dynamic> shopData,
    User? currentUser,
  ) async {
    final shopRef = FirebaseFirestore.instance.collection('shops').doc(shopId);
    final shopDoc = await shopRef.get();
    final payload = <String, dynamic>{...shopData, 'shopId': shopId};

    if (shopDoc.exists) {
      await shopRef.set(payload, SetOptions(merge: true));
      return;
    }

    await shopRef.set({
      ...payload,
      'ownerUid': currentUser?.uid,
      'ownerEmail': currentUser?.email,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> _refreshClaimsForShopSave() async {
    try {
      await ClaimsService().refreshMyClaims();
    } catch (e) {
      debugPrint('refreshMyClaims before save shop failed: $e');
    }

    try {
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } catch (e) {
      debugPrint('force refresh ID token before save shop failed: $e');
    }
  }

  Future<void> _saveShopProfileViaCallable(
    String shopId,
    Map<String, dynamic> profile,
  ) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('updateShopProfileSecure');

    final result = await callable.call({
      'shopId': shopId,
      'profile': {
        'name': profile['name'] ?? '',
        'address': profile['address'] ?? '',
        'phone': profile['phone'] ?? '',
        'email': profile['email'] ?? '',
        'description': profile['description'] ?? '',
        'logoUrl': profile['logoUrl'] ?? '',
        'coverUrl': profile['coverUrl'] ?? '',
        'coverAlignX': profile['coverAlignX'] ?? 0,
        'coverAlignY': profile['coverAlignY'] ?? 0,
        'latitude': profile['latitude'],
        'longitude': profile['longitude'],
      },
    });

    final data = result.data;
    if (data is Map && data['success'] == true) return;
    throw Exception('Callable updateShopProfileSecure không trả về success=true');
  }

  /// Đồng bộ thông tin shop vào SharedPreferences để các màn hình in hóa đơn đọc được
  Future<void> _syncToSharedPreferences(
    String name,
    String address,
    String phone,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('shop_name', name);
    await prefs.setString('shop_address', address);
    await prefs.setString('shop_phone', phone);
  }

  /// Load shop settings for multi-industry features
  Future<void> _loadShopSettings() async {
    try {
      final settings = await CategoryService().getShopSettings();
      debugPrint('🏪 ShopSettings: Loaded - businessType=${settings?.businessType}');
      _safeSetState(() => _shopSettings = settings);
    } catch (e) {
      debugPrint('Error loading shop settings: $e');
    }
  }

  /// Open business type wizard to change business type
  Future<void> _openBusinessTypeWizard() async {
    final shopId = await UserService.getCurrentShopId();
    if (shopId == null) {
      NotificationService.showSnackBar('Không tìm thấy thông tin shop', color: Colors.red);
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BusinessTypeWizard(
          shopId: shopId,
          shopName: _shopName,
          onComplete: (settings) async {
            await CategoryService().saveShopSettings(settings);
            if (!mounted) return;
            await _loadShopSettings();
            NotificationService.showSnackBar(
              'Đã cập nhật loại hình kinh doanh',
              color: Colors.green,
            );
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  ImageProvider? _buildShopCoverImageProvider() {
    if (_selectedCover != null) {
      return kIsWeb
          ? NetworkImage(_selectedCover!.path)
          : FileImage(_selectedCover!) as ImageProvider;
    }
    if (_shopCoverUrl.trim().isNotEmpty) {
      return CachedNetworkImageProvider(
        _shopCoverUrl,
        maxWidth: 2400,
        maxHeight: 1400,
      );
    }
    return null;
  }

  Future<void> _openCoverPositionEditor() async {
    final coverProvider = _buildShopCoverImageProvider();
    if (coverProvider == null) {
      NotificationService.showSnackBar(
        'Vui lòng chọn ảnh bìa trước',
        color: Colors.orange,
      );
      return;
    }

    double localX = _shopCoverAlignX;
    double localY = _shopCoverAlignY;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Chỉnh vùng hiển thị ảnh bìa'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LayoutBuilder(
                        builder: (context, constraints) => GestureDetector(
                          onPanUpdate: (details) {
                            final w = constraints.maxWidth <= 0
                                ? 1.0
                                : constraints.maxWidth;
                            final h = 180.0;
                            setDialogState(() {
                              localX =
                                  (localX + (details.delta.dx / (w / 2))).clamp(
                                    -1.0,
                                    1.0,
                                  );
                              localY =
                                  (localY + (details.delta.dy / (h / 2))).clamp(
                                    -1.0,
                                    1.0,
                                  );
                            });
                          },
                          child: Container(
                            height: 180,
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.shade100,
                              image: DecorationImage(
                                image: coverProvider,
                                fit: BoxFit.cover,
                                alignment: Alignment(localX, localY),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Kéo ảnh để chọn vùng hiển thị đẹp nhất',
                      style: AppTextStyles.caption,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Hủy'),
                ),
                TextButton(
                  onPressed: () {
                    _safeSetState(() {
                      _shopCoverAlignX = localX;
                      _shopCoverAlignY = localY;
                    });
                    Navigator.pop(dialogContext);
                    NotificationService.showSnackBar(
                      'Đã căn ảnh. Nhấn Lưu thay đổi để áp dụng.',
                      color: Colors.blue,
                    );
                  },
                  child: const Text('Áp dụng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2000,
    );

    if (pickedFile != null) {
      _safeSetState(() {
        _selectedLogo = File(pickedFile.path);
      });
    }
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 3200,
    );

    if (pickedFile != null) {
      final cropped = await _cropShopCoverToDisplay(File(pickedFile.path));
      if (cropped == null) return;
      _safeSetState(() {
        _selectedCover = cropped;
        _shopCoverAlignX = 0;
        _shopCoverAlignY = 0;
      });
    }
  }

  Future<File?> _cropShopCoverToDisplay(File sourceFile) async {
    try {
      final bytes = await sourceFile.readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        NotificationService.showSnackBar(
          'Không đọc được ảnh đã chọn',
          color: Colors.red,
        );
        return null;
      }

      const targetAspect = 16 / 9;
      final imageAspect = decoded.width / decoded.height;
      double cropTopFactor = 0.5;
      double cropZoom = 1.0;

      final accepted = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDialogState) {
              return AlertDialog(
                title: const Text('Crop ảnh bìa shop (16:9)'),
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
                      const SizedBox(height: 8),
                      Slider(
                        value: cropTopFactor,
                        onChanged: (v) {
                          setDialogState(() => cropTopFactor = v);
                        },
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Text('Phóng to vùng crop'),
                    Slider(
                      value: cropZoom,
                      min: 1,
                      max: 4,
                      divisions: 30,
                      onChanged: (v) {
                        setDialogState(() => cropZoom = v);
                      },
                    ),
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
        final baseH = decoded.height;
        final zoomedH = (baseH / cropZoom).round().clamp(1, decoded.height);
        cropH = zoomedH;
        cropW = (cropH * targetAspect).round().clamp(1, decoded.width);
        cropX = ((decoded.width - cropW) / 2).round();
        cropY = ((decoded.height - cropH) / 2).round();
      } else {
        cropW = (decoded.width / cropZoom).round().clamp(1, decoded.width);
        cropH = (cropW / targetAspect).round();
        if (cropH > decoded.height) {
          cropH = decoded.height;
          cropW = (cropH * targetAspect).round().clamp(1, decoded.width);
        }
        final maxTop = (decoded.height - cropH).clamp(0, decoded.height);
        cropY = (maxTop * cropTopFactor).round();
        cropX = ((decoded.width - cropW) / 2).round();
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
        'shop_cover_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final outFile = File(outPath);
      await outFile.writeAsBytes(img.encodeJpg(cropped, quality: 92), flush: true);
      return outFile;
    } catch (e) {
      NotificationService.showSnackBar(
        'Không thể crop ảnh bìa: $e',
        color: Colors.red,
      );
      return null;
    }
  }

  Future<void> _saveShopData() async {
    // Manual validation
    if (_nameController.text.trim().isEmpty) {
      NotificationService.showSnackBar(
        "Vui lòng nhập tên cửa hàng",
        color: Colors.red,
      );
      return;
    }

    _safeSetState(() => _saving = true);

    try {
      var shopId = await UserService.getCurrentShopId();
      final currentUser = FirebaseAuth.instance.currentUser;
      // Fallback: thử dùng uid của user làm shopId (owner case)
      if (shopId == null || shopId.isEmpty) {
        if (currentUser != null) {
          shopId = currentUser.uid;
        }
      }

      if (shopId == null || shopId.isEmpty) {
        NotificationService.showSnackBar(
          "Không tìm thấy thông tin shop",
          color: Colors.red,
        );
        return;
      }

      String logoUrl = _shopLogoUrl;
      String coverUrl = _shopCoverUrl;

      // Upload song song logo + cover khi cùng thay đổi để giảm thời gian chờ lưu.
      if (_selectedLogo != null && _selectedCover != null) {
        NotificationService.showSnackBar(
          'Đang tải logo và ảnh bìa lên hệ thống...',
          color: Colors.blue,
          duration: const Duration(seconds: 7),
        );
        final uploadResults = await Future.wait<List<String>>([
          StorageService.uploadMultipleImages([
            _selectedLogo!.path,
          ], 'shop_logos'),
          StorageService.uploadMultipleImages([
            _selectedCover!.path,
          ], 'shop_logos'),
        ]);

        final logoUrls = uploadResults[0];
        final coverUrls = uploadResults[1];
        if (logoUrls.isNotEmpty) logoUrl = logoUrls.first;
        if (coverUrls.isNotEmpty) coverUrl = coverUrls.first;

        if (logoUrls.isEmpty || coverUrls.isEmpty) {
          final denied = StorageService.lastUploadPermissionDenied ||
              (StorageService.lastUploadErrorMessage ?? '')
                  .toLowerCase()
                  .contains('unauthorized') ||
              (StorageService.lastUploadErrorMessage ?? '')
                  .toLowerCase()
                  .contains('permission');
          if (mounted) {
            NotificationService.showSnackBar(
              denied
                  ? 'Không có quyền tải ảnh lên (lỗi 403). Kiểm tra cấu hình Firebase.'
                  : 'Một phần ảnh tải lên thất bại. Vui lòng kiểm tra mạng và thử lại.',
              color: Colors.red,
              duration: const Duration(seconds: 6),
            );
          }
        }
      }

      // Upload logo if selected
      if (_selectedLogo != null && _selectedCover == null) {
        NotificationService.showSnackBar(
          'Đang tải logo lên hệ thống, vui lòng không thoát ứng dụng.',
          color: Colors.blue,
          duration: const Duration(seconds: 7),
        );
        final urls = await StorageService.uploadMultipleImages([
          _selectedLogo!.path,
        ], 'shop_logos');
        if (urls.isNotEmpty) {
          logoUrl = urls.first;
        } else {
          final denied = StorageService.lastUploadPermissionDenied ||
              (StorageService.lastUploadErrorMessage ?? '').toLowerCase().contains('unauthorized') ||
              (StorageService.lastUploadErrorMessage ?? '').toLowerCase().contains('permission');
          if (mounted) {
            NotificationService.showSnackBar(
              denied
                  ? 'Không có quyền tải logo lên (lỗi 403). Kiểm tra cấu hình App Check/Storage Firebase.'
                  : 'Tải logo thất bại. Vui lòng kiểm tra kết nối mạng và thử lại.',
              color: Colors.red,
              duration: const Duration(seconds: 6),
            );
          }
        }
      }

      // Upload cover if selected
      if (_selectedCover != null && _selectedLogo == null) {
        NotificationService.showSnackBar(
          'Đang tải ảnh bìa shop lên hệ thống...',
          color: Colors.blue,
          duration: const Duration(seconds: 6),
        );
        final urls = await StorageService.uploadMultipleImages([
          _selectedCover!.path,
        ], 'shop_logos');
        if (urls.isNotEmpty) {
          coverUrl = urls.first;
        } else {
          final denied = StorageService.lastUploadPermissionDenied ||
              (StorageService.lastUploadErrorMessage ?? '')
                  .toLowerCase()
                  .contains('unauthorized') ||
              (StorageService.lastUploadErrorMessage ?? '')
                  .toLowerCase()
                  .contains('permission');
          if (mounted) {
            NotificationService.showSnackBar(
              denied
                  ? 'Không có quyền tải ảnh bìa lên (lỗi 403). Kiểm tra cấu hình Firebase.'
                  : 'Tải ảnh bìa thất bại. Vui lòng kiểm tra mạng và thử lại.',
              color: Colors.red,
              duration: const Duration(seconds: 6),
            );
          }
        }
      }

      // Update shop data
      final shopData = {
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'phone': _phoneController.text.trim(),
        'email': _emailController.text.trim(),
        'description': _descriptionController.text.trim(),
        'logoUrl': logoUrl,
        'coverUrl': coverUrl,
        'coverAlignX': _shopCoverAlignX,
        'coverAlignY': _shopCoverAlignY,
        'latitude': _shopLatitude,
        'longitude': _shopLongitude,
        'requireLocationForAttendance': _requireLocationForAttendance,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': currentUser?.uid,
      };

      bool savedToMainShopDoc = false;
      bool savedToFallbackProfile = false;
      bool savedViaCallable = false;

      try {
        await _saveMainShopProfile(shopId, shopData, currentUser);
        savedToMainShopDoc = true;
      } catch (e) {
        debugPrint('Primary save to shops/$shopId failed: $e');
        if (_isPermissionDeniedError(e)) {
          await _refreshClaimsForShopSave();

          try {
            await _saveMainShopProfile(shopId, shopData, currentUser);
            savedToMainShopDoc = true;
            debugPrint(
              'Saved shop profile to main doc after claims/token refresh',
            );
          } catch (retryError) {
            if (_isPermissionDeniedError(retryError)) {
              try {
                await _saveShopProfileFallback(shopId, shopData);
                savedToFallbackProfile = true;
                debugPrint('Saved shop profile to fallback settings/shop_profile');
              } catch (fallbackError) {
                if (_isPermissionDeniedError(fallbackError)) {
                  await _saveShopProfileViaCallable(shopId, shopData);
                  savedViaCallable = true;
                  debugPrint(
                    'Saved shop profile via callable updateShopProfileSecure',
                  );
                } else {
                  rethrow;
                }
              }
            } else {
              rethrow;
            }
          }
        } else {
          rethrow;
        }
      }

      // Đồng bộ thông tin shop vào SharedPreferences để các màn hình in hóa đơn đọc được
      await _syncToSharedPreferences(
        _nameController.text.trim(),
        _addressController.text.trim(),
        _phoneController.text.trim(),
      );

      _safeSetState(() {
        _shopName = _nameController.text.trim();
        _shopAddress = _addressController.text.trim();
        _shopPhone = _phoneController.text.trim();
        _shopEmail = _emailController.text.trim();
        _shopDescription = _descriptionController.text.trim();
        _shopLogoUrl = logoUrl;
        _shopCoverUrl = coverUrl;
        _selectedLogo = null;
        _selectedCover = null;
      });

      await AuditService.logAction(
        action: 'SHOP_SETTINGS_UPDATED',
        entityType: 'SHOP',
        entityId: shopId,
        summary: 'Cập nhật cấu hình nhạy cảm của cửa hàng',
        payload: {
          'requireLocationForAttendance': _requireLocationForAttendance,
          'hasLogo': logoUrl.trim().isNotEmpty,
          'hasCover': coverUrl.trim().isNotEmpty,
          'saveMode': savedToMainShopDoc
              ? 'main_doc'
              : (savedViaCallable
                  ? 'callable'
                  : (savedToFallbackProfile ? 'fallback' : 'unknown')),
        },
      );

      NotificationService.showSnackBar(
        savedToMainShopDoc
            ? "✅ Đã cập nhật thông tin shop!"
          : (savedViaCallable
            ? "✅ Đã lưu thông tin cửa hàng (chế độ bảo mật)!"
            : (savedToFallbackProfile
                  ? "✅ Đã lưu thông tin cửa hàng (chế độ tương thích)!"
            : "✅ Đã lưu thông tin cửa hàng!")),
        color: Colors.green,
      );
    } catch (e) {
      final message = _isPermissionDeniedError(e)
          ? "❌ Tài khoản hiện tại chưa có quyền chỉnh sửa thông tin cửa hàng. Vui lòng đăng xuất/đăng nhập lại tài khoản chủ shop để đồng bộ quyền."
          : "❌ Lỗi cập nhật: $e";
      NotificationService.showSnackBar(message, color: Colors.red);
    } finally {
      _safeSetState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0068FF), Color(0xFF0084FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Text(
          "CÀI ĐẶT SHOP",
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              onPressed: _saveShopData,
              icon: const Icon(Icons.save),
              tooltip: 'Lưu thay đổi',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveCenter(
              maxWidth: 800,
              child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // === LOGO + THÔNG TIN CƠ BẢN ===
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            // Profile-style cover + logo
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                LayoutBuilder(
                                  builder: (context, _) => GestureDetector(
                                    onTap: _pickCover,
                                    child: Container(
                                      height: 150,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.blueGrey.shade100,
                                        borderRadius: BorderRadius.circular(12),
                                        image: _selectedCover != null
                                            ? DecorationImage(
                                                image: kIsWeb
                                                    ? NetworkImage(
                                                        _selectedCover!.path,
                                                      )
                                                    : FileImage(_selectedCover!)
                                                        as ImageProvider,
                                                fit: BoxFit.cover,
                                                alignment: Alignment(
                                                  _shopCoverAlignX,
                                                  _shopCoverAlignY,
                                                ),
                                              )
                                            : (_shopCoverUrl.trim().isNotEmpty
                                                ? DecorationImage(
                                                    image: NetworkImage(
                                                      _shopCoverUrl,
                                                    ),
                                                    fit: BoxFit.cover,
                                                    alignment: Alignment(
                                                      _shopCoverAlignX,
                                                      _shopCoverAlignY,
                                                    ),
                                                  )
                                                : null),
                                      ),
                                      child: (_selectedCover == null &&
                                              _shopCoverUrl.trim().isEmpty)
                                          ? Center(
                                              child: Text(
                                                'Thêm ảnh bìa shop',
                                                style: AppTextStyles.body1.copyWith(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                if (_selectedCover != null || _shopCoverUrl.trim().isNotEmpty)
                                  Positioned(
                                    left: 10,
                                    top: 10,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.35),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        'Chọn ảnh trước, cân chỉnh sau rồi bấm Lưu',
                                        style: AppTextStyles.caption.copyWith(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  top: 6,
                                  right: 6,
                                  child: Row(
                                    children: [
                                      if (_selectedCover != null ||
                                          _shopCoverUrl.trim().isNotEmpty)
                                        IconButton(
                                          tooltip: 'Xem ảnh bìa',
                                          onPressed: () => EntityAvatar.showPreview(
                                            context,
                                            _selectedCover != null
                                                ? _selectedCover!.path
                                                : _shopCoverUrl,
                                            _nameController.text,
                                          ),
                                          icon: const Icon(
                                            Icons.fullscreen,
                                            color: Colors.white,
                                          ),
                                        ),
                                      if (_selectedCover != null ||
                                          _shopCoverUrl.trim().isNotEmpty)
                                        IconButton(
                                          tooltip: 'Căn giữa ảnh bìa',
                                          onPressed: () {
                                            _safeSetState(() {
                                              _shopCoverAlignX = 0;
                                              _shopCoverAlignY = 0;
                                            });
                                            NotificationService.showSnackBar(
                                              'Đã căn giữa. Nhấn Lưu thay đổi để áp dụng.',
                                              color: Colors.blue,
                                            );
                                          },
                                          icon: const Icon(
                                            Icons.filter_center_focus,
                                            color: Colors.white,
                                          ),
                                        ),
                                      if (_selectedCover != null ||
                                          _shopCoverUrl.trim().isNotEmpty)
                                        IconButton(
                                          tooltip: 'Chỉnh vùng hiển thị',
                                          onPressed: _openCoverPositionEditor,
                                          icon: const Icon(
                                            Icons.tune,
                                            color: Colors.white,
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: 'Đổi ảnh bìa',
                                        onPressed: _pickCover,
                                        icon: const Icon(
                                          Icons.camera_alt,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  left: 16,
                                  bottom: -28,
                                  child: GestureDetector(
                                    onTap: () {
                                      if (_selectedLogo != null ||
                                          _shopLogoUrl.isNotEmpty) {
                                        EntityAvatar.showPreview(
                                          context,
                                          _selectedLogo != null
                                              ? _selectedLogo!.path
                                              : _shopLogoUrl,
                                          _nameController.text,
                                        );
                                      } else {
                                        _pickLogo();
                                      }
                                    },
                                    child: Stack(
                                      alignment: Alignment.bottomRight,
                                      children: [
                                        Container(
                                          width: 76,
                                          height: 76,
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                          ),
                                          child: ClipOval(
                                            child: _selectedLogo != null
                                                ? (kIsWeb
                                                    ? Image.network(
                                                        _selectedLogo!.path,
                                                        fit: BoxFit.cover,
                                                      )
                                                    : Image.file(
                                                        _selectedLogo!,
                                                        fit: BoxFit.cover,
                                                      ))
                                                : _shopLogoUrl.isNotEmpty
                                                    ? AppCachedImage(
                                                        imageUrl: _shopLogoUrl,
                                                        fit: BoxFit.cover,
                                                        memCacheWidth: 200,
                                                        memCacheHeight: 200,
                                                      )
                                                    : const Icon(
                                                        Icons.store_rounded,
                                                        size: 34,
                                                        color: Colors.grey,
                                                      ),
                                          ),
                                        ),
                                        GestureDetector(
                                          onTap: _pickLogo,
                                          child: Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white,
                                                width: 1.5,
                                              ),
                                            ),
                                            child: const Icon(
                                              Icons.camera_alt,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 34),
                            ValidatedTextField(
                              controller: _nameController,
                              label: "Tên cửa hàng *",
                              icon: Icons.store,
                            ),
                            const SizedBox(height: 10),
                            ValidatedTextField(
                              controller: _addressController,
                              label: "Địa chỉ",
                              icon: Icons.location_on,
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: ValidatedTextField(
                                    controller: _phoneController,
                                    label: "SĐT",
                                    icon: Icons.phone,
                                    keyboardType: TextInputType.phone,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: ValidatedTextField(
                                    controller: _emailController,
                                    label: "Email",
                                    icon: Icons.email,
                                    keyboardType: TextInputType.emailAddress,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ValidatedTextField(
                              controller: _descriptionController,
                              label: "Mô tả cửa hàng",
                              icon: Icons.description,
                              maxLines: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // === LOẠI HÌNH KINH DOANH ===
                    _buildBusinessTypeSection(),
                    const SizedBox(height: 12),

                    // === VỊ TRÍ CHẤM CÔNG ===
                    _buildCompactLocationSection(),
                    const SizedBox(height: 12),

                    // === QUICK ACTIONS ===
                    _buildQuickActionsSection(),
                    const SizedBox(height: 12),

                    // === ADVANCED SETTINGS (Collapsible) ===
                    _buildAdvancedSettingsSection(),
                    const SizedBox(height: 12),

                    // === THÀNH VIÊN ===
                    _buildSection("THÀNH VIÊN"),
                    const SizedBox(height: 8),
                    _buildMembersList(),

                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Widget _buildSection(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: AppTextStyles.body1.fontSize,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF2962FF),
      ),
    );
  }

  /// Business Type Section - Multi-Industry support
  Widget _buildBusinessTypeSection() {
    final businessType = _shopSettings?.businessType ?? 'electronics';
    final businessTypeName = _shopSettings?.businessTypeName ?? 'Điện thoại & Điện tử';
    
    // Get icon and color based on business type
    IconData icon;
    Color color;
    switch (businessType) {
      case 'food':
        icon = Icons.restaurant;
        color = Colors.orange;
        break;
      case 'fashion':
        icon = Icons.checkroom;
        color = Colors.pink;
        break;
      case 'general':
        icon = Icons.store;
        color = Colors.blue;
        break;
      default: // electronics
        icon = Icons.phone_android;
        color = Colors.indigo;
    }
    
    // Get enabled features
    final features = <String>[];
    if (_shopSettings?.enableRepair == true) features.add('Sửa chữa');
    if (_shopSettings?.enableSerial == true) features.add('IMEI/Serial');
    if (_shopSettings?.enableWarranty == true) features.add('Bảo hành');
    if (_shopSettings?.enableExpiry == true) features.add('Hạn sử dụng');
    if (_shopSettings?.enableBatch == true) features.add('Số lô');
    if (_shopSettings?.enableVariants == true) features.add('Biến thể');
    
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Loại hình kinh doanh',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      Text(
                        businessTypeName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                // Lock icon instead of edit - business type is fixed after shop creation
                Icon(Icons.lock_outline, size: 18, color: Colors.grey.shade400),
              ],
            ),
            if (features.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: features.map((f) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    f,
                      style: TextStyle(fontSize: 13, color: color),
                    ),
                  )).toList(),
                ),
              ],
            ],
          ),
        ),
    );
  }

  /// Compact location section - chỉ 1 row
  Widget _buildCompactLocationSection() {
    final hasLocation = _shopLatitude != null && _shopLongitude != null;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            leading: Icon(
              hasLocation ? Icons.location_on : Icons.location_off,
              color: hasLocation ? Colors.green : Colors.orange,
            ),
            title: Text(
              hasLocation ? 'Vị trí chấm công đã cài' : 'Chưa cài vị trí chấm công',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: hasLocation
                ? Text(
                    '${_shopLatitude!.toStringAsFixed(4)}, ${_shopLongitude!.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 13),
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasLocation)
                  IconButton(
                    icon: const Icon(Icons.map_outlined, size: 20, color: Colors.blue),
                    onPressed: _openShopMap,
                    tooltip: 'Mở bản đồ OSM',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                if (hasLocation)
                  IconButton(
                    icon: const Icon(Icons.alt_route, size: 20, color: Colors.teal),
                    onPressed: _openDirectionsToShop,
                    tooltip: 'Chỉ đường miễn phí tới shop',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                if (hasLocation)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    onPressed: _clearLocation,
                    tooltip: 'Xóa vị trí',
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                IconButton(
                  icon: Icon(
                    Icons.my_location,
                    size: 20,
                    color: hasLocation ? Colors.blue : Colors.green,
                  ),
              onPressed: _setCurrentLocation,
              tooltip: hasLocation ? 'Cập nhật vị trí' : 'Cài vị trí',
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.all(8),
            ),
          ],
        ),
      ),
      const Divider(height: 1),
      SwitchListTile(
        dense: true,
        value: _requireLocationForAttendance,
        onChanged: (v) => _safeSetState(() => _requireLocationForAttendance = v),
        title: const Text(
          'Bắt buộc vị trí khi chấm công',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          'Nhân viên phải ở trong phạm vi 100m mới được chấm công',
          style: TextStyle(fontSize: 12),
        ),
        secondary: Icon(
          Icons.location_searching,
          color: _requireLocationForAttendance ? Colors.green : Colors.grey,
          size: 20,
        ),
      ),
        ],
      ),
    );
  }

  /// Quick Actions - các shortcut hay dùng
  Widget _buildQuickActionsSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.account_balance_wallet, color: Colors.green.shade700, size: 22),
            title: const Text('Cài đặt lương & hoa hồng', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HRSalarySettingsView()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: Icon(Icons.history, color: Colors.orange.shade700, size: 22),
            title: const Text('Lịch sử điều chỉnh tài chính', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdjustmentHistoryView()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: Icon(Icons.cloud_download, color: Colors.blue.shade700, size: 22),
            title: const Text('Tải dữ liệu shop từ cloud', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: _showDownloadDataDialog,
          ),
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: Icon(Icons.qr_code_2, color: Colors.blue.shade700, size: 22),
            title: const Text('Thiết kế Tem sản phẩm', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LabelDesignerView()),
            ),
          ),
        ],
      ),
    );
  }

  /// Advanced Settings - gom các cài đặt ít dùng vào ExpansionTile
  Widget _buildAdvancedSettingsSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: ExpansionTile(
        dense: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(Icons.settings_suggest, color: Colors.grey.shade600, size: 22),
        title: const Text('Cài đặt nâng cao', style: TextStyle(fontSize: 14)),
        children: [
          ListTile(
            dense: true,
            leading: Icon(Icons.restore, color: Colors.amber.shade700, size: 20),
            title: const Text('Khôi phục dữ liệu cũ', style: TextStyle(fontSize: 14)),
            subtitle: const Text('Migrate từ shop/tài khoản khác', style: TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.chevron_right, size: 18),
            onTap: _showDataMigrationDialog,
          ),
        ],
      ),
    );
  }

  // Old methods removed - functionality moved to _buildQuickActionsSection() and _buildAdvancedSettingsSection()

  Future<void> _showDataMigrationDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text("Đang quét dữ liệu trên cloud..."),
          ],
        ),
      ),
    );

    try {
      final currentShopId = await UserService.getCurrentShopId();
      final orphanData = await DataMigrationService.findOrphanData();

      if (!mounted) return;
      Navigator.pop(context); // Đóng loading

      if (orphanData.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 10),
                Text("KHÔNG CÓ DỮ LIỆU CŨ"),
              ],
            ),
            content: const Text(
              "Không tìm thấy dữ liệu nào từ tài khoản/shop khác trên cloud.\n\n"
              "Nếu bạn chắc chắn có dữ liệu cũ, hãy kiểm tra:\n"
              "• Đăng nhập đúng email\n"
              "• Kết nối internet ổn định",
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text("ĐÓNG"),
              ),
            ],
          ),
        );
        return;
      }

      // Nhóm dữ liệu theo shopId
      final groupedByShopId = <String, List<OrphanDataInfo>>{};
      for (var item in orphanData) {
        groupedByShopId.putIfAbsent(item.shopId, () => []).add(item);
      }

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.cloud_queue, color: Colors.blue),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  "TÌM THẤY DỮ LIỆU CŨ",
                  style: TextStyle(fontSize: 17),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    "Shop hiện tại: ${currentShopId ?? 'N/A'}",
                    style: TextStyle(
                      fontSize: AppTextStyles.body1.fontSize,
                      color: Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Dữ liệu từ các nguồn khác:",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextStyles.headline5.fontSize,
                  ),
                ),
                const SizedBox(height: 10),
                ...groupedByShopId.entries.map((entry) {
                  final shopId = entry.key;
                  final items = entry.value;
                  final totalCount = items.fold<int>(
                    0,
                    (sum, item) => sum + item.count,
                  );

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              shopId == 'null'
                                  ? Icons.help_outline
                                  : Icons.store,
                              size: 16,
                              color: shopId == 'null'
                                  ? Colors.orange
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                shopId == 'null'
                                    ? "Dữ liệu chưa gán shop"
                                    : "Shop: ${shopId.substring(0, 8)}...",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextStyles.subtitle1.fontSize,
                                ),
                              ),
                            ),
                            Text(
                              "$totalCount bản ghi",
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextStyles.subtitle1.fontSize,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: items
                              .map(
                                (item) => Chip(
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                  labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                  ),
                                  label: Text(
                                    "${item.collection}: ${item.count}",
                                    style: TextStyle(
                                      fontSize: AppTextStyles.caption.fontSize,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmMigration(shopId, totalCount);
                            },
                            icon: const Icon(Icons.download, size: 16),
                            label: const Text("MIGRATE VỀ SHOP NÀY"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("ĐÓNG"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      NotificationService.showSnackBar("❌ Lỗi: $e", color: Colors.red);
    }
  }

  Future<void> _confirmMigration(String fromShopId, int totalCount) async {
    final currentShopId = await UserService.getCurrentShopId();
    if (currentShopId == null) {
      NotificationService.showSnackBar(
        "❌ Không xác định được shop hiện tại",
        color: Colors.red,
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange),
            SizedBox(width: 10),
            Expanded(
              child: Text("XÁC NHẬN MIGRATE", style: TextStyle(fontSize: 17)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Bạn sắp migrate $totalCount bản ghi từ:"),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                fromShopId == 'null'
                    ? "Dữ liệu chưa gán shop"
                    : "Shop: $fromShopId",
                style: TextStyle(
                  fontSize: AppTextStyles.body1.fontSize,
                  color: Colors.red.shade800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text("Sang shop hiện tại:"),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "Shop: $currentShopId",
                style: TextStyle(
                  fontSize: AppTextStyles.body1.fontSize,
                  color: Colors.green.shade800,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              "⚠️ Hành động này không thể hoàn tác!",
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: AppTextStyles.subtitle1.fontSize,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("MIGRATE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Thực hiện migration
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text("Đang migrate dữ liệu..."),
                const SizedBox(height: 8),
                Text(
                  _migrationProgress,
                  style: TextStyle(
                    fontSize: AppTextStyles.body1.fontSize,
                    color: Colors.grey,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            );
          },
        ),
      ),
    );

    try {
      final results = await DataMigrationService.migrateData(
        fromShopId: fromShopId,
        toShopId: currentShopId,
        onProgress: (message) {
          _safeSetState(() => _migrationProgress = message);
        },
      );

      if (!mounted) return;
      Navigator.pop(context); // Đóng loading

      final totalMigrated = results.values.fold<int>(
        0,
        (sum, count) => sum + count,
      );

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 10),
              Text("MIGRATE THÀNH CÔNG"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Đã migrate $totalMigrated bản ghi:"),
              const SizedBox(height: 10),
              ...results.entries.map(
                (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        "${e.key}: ${e.value}",
                        style: TextStyle(
                          fontSize: AppTextStyles.subtitle1.fontSize,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Vui lòng khởi động lại app để dữ liệu được cập nhật đầy đủ.",
                style: TextStyle(
                  fontSize: AppTextStyles.body1.fontSize,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                // Có thể trigger reload data ở đây
              },
              child: const Text("ĐÓNG"),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      NotificationService.showSnackBar("❌ Lỗi migrate: $e", color: Colors.red);
    }
  }

  String _migrationProgress = '';

  Widget _buildMembersList() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadShopMembers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Text("Lỗi tải danh sách thành viên: ${snapshot.error}");
        }

        final members = snapshot.data ?? [];

        if (members.isEmpty) {
          return const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text("Chưa có thành viên nào trong shop"),
            ),
          );
        }

        return Column(
          children: members
              .map(
                (member) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _getRoleColor(member['role']),
                      child: Text(
                        member['name']?.substring(0, 1).toUpperCase() ?? '?',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(member['name'] ?? 'Chưa cập nhật'),
                    subtitle: Text(
                      "${member['email'] ?? ''} • ${_getRoleDisplayName(member['role'])}",
                    ),
                    trailing: Icon(
                      _getRoleIcon(member['role']),
                      color: _getRoleColor(member['role']),
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadShopMembers() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) return [];

      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('shopId', isEqualTo: shopId)
          .get();

      final members = <Map<String, dynamic>>[];
      for (var doc in usersSnapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        members.add(data);
      }

      return members;
    } catch (e) {
      debugPrint("Error loading shop members: $e");
      return [];
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'owner':
        return Colors.blue;
      case 'manager':
        return Colors.blue;
      case 'technician':
        return Colors.orange;
      case 'employee':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getRoleIcon(String? role) {
    switch (role) {
      case 'owner':
        return Icons.admin_panel_settings;
      case 'manager':
        return Icons.manage_accounts;
      case 'technician':
        return Icons.build;
      case 'employee':
        return Icons.work;
      default:
        return Icons.person;
    }
  }

  String _getRoleDisplayName(String? role) {
    switch (role) {
      case 'owner':
        return 'Chủ shop';
      case 'manager':
        return 'Quản lý';
      case 'technician':
        return 'Kỹ thuật';
      case 'employee':
        return 'Nhân viên';
      default:
        return 'Thành viên';
    }
  }

  // _buildDownloadShopDataSection removed - moved to _buildQuickActionsSection()

  Future<void> _showDownloadDataDialog() async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.cloud_download, color: Colors.blue.shade600),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "TẢI DỮ LIỆU SHOP",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style: const TextStyle(color: Colors.black87, fontSize: 16),
                children: [
                  const TextSpan(text: 'Tải dữ liệu của shop '),
                  TextSpan(
                    text: '"$_shopName"',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const TextSpan(text: ' từ đám mây về máy này.'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDataItem(Icons.build, 'Đơn sửa chữa'),
                  _buildDataItem(Icons.shopping_cart, 'Đơn bán hàng'),
                  _buildDataItem(Icons.inventory, 'Sản phẩm trong kho'),
                  _buildDataItem(Icons.receipt, 'Công nợ & Chi phí'),
                  _buildDataItem(Icons.people, 'Khách hàng & NCC'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.orange.shade700,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chỉ tải dữ liệu của shop này, không ảnh hưởng shop khác.',
                      style: TextStyle(
                        fontSize: AppTextStyles.body1.fontSize,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Quá trình có thể mất vài phút tùy lượng dữ liệu.",
              style: TextStyle(
                fontSize: AppTextStyles.body1.fontSize,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.download, size: 18),
            label: const Text("BẮT ĐẦU TẢI"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      // Show loading overlay
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text(
                  'Đang tải dữ liệu shop...',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(
                  'Vui lòng đợi trong giây lát',
                  style: TextStyle(
                    fontSize: AppTextStyles.subtitle1.fontSize,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      try {
        await SyncService.downloadAllFromCloud(force: true);
        if (mounted) Navigator.of(context).pop(); // Close loading dialog
        NotificationService.showSnackBar(
          "✅ Đã tải xong dữ liệu shop!",
          color: Colors.green,
        );
      } catch (e) {
        if (mounted) Navigator.of(context).pop(); // Close loading dialog
        NotificationService.showSnackBar("❌ Lỗi: $e", color: Colors.red);
      }
    }
  }

  Widget _buildDataItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue.shade600),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(fontSize: AppTextStyles.headline5.fontSize),
          ),
        ],
      ),
    );
  }

  // _buildLocationSection removed - moved to _buildCompactLocationSection()

  Future<void> _setCurrentLocation() async {
    try {
      // Check permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          NotificationService.showSnackBar(
            'Cần quyền truy cập vị trí',
            color: Colors.red,
          );
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        NotificationService.showSnackBar(
          'Vui lòng bật quyền vị trí trong cài đặt',
          color: Colors.red,
        );
        return;
      }

      NotificationService.showSnackBar(
        'Đang lấy vị trí...',
        color: Colors.blue,
      );

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _safeSetState(() {
        _shopLatitude = position.latitude;
        _shopLongitude = position.longitude;
      });

      NotificationService.showSnackBar(
        '✅ Đã cập nhật vị trí! Nhấn Lưu để hoàn tất.',
        color: Colors.green,
      );
    } catch (e) {
      NotificationService.showSnackBar('Lỗi lấy vị trí: $e', color: Colors.red);
    }
  }

  void _clearLocation() {
    _safeSetState(() {
      _shopLatitude = null;
      _shopLongitude = null;
    });
    NotificationService.showSnackBar(
      'Đã xóa vị trí. Nhấn Lưu để hoàn tất.',
      color: Colors.orange,
    );
  }

  Future<void> _openShopMap() async {
    if (_shopLatitude == null || _shopLongitude == null) return;
    final ok = await OsmMapService.openPoint(_shopLatitude!, _shopLongitude!);
    if (!ok && mounted) {
      NotificationService.showSnackBar('Không thể mở bản đồ OSM', color: Colors.red);
    }
  }

  Future<void> _openDirectionsToShop() async {
    if (_shopLatitude == null || _shopLongitude == null) return;
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        final ok = await OsmMapService.openDirections(
          toLat: _shopLatitude!,
          toLon: _shopLongitude!,
        );
        if (!ok && mounted) {
          NotificationService.showSnackBar('Không thể mở chỉ đường OSM', color: Colors.red);
        }
        return;
      }

      final current = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final ok = await OsmMapService.openDirections(
        fromLat: current.latitude,
        fromLon: current.longitude,
        toLat: _shopLatitude!,
        toLon: _shopLongitude!,
      );
      if (!ok && mounted) {
        NotificationService.showSnackBar('Không thể mở chỉ đường OSM', color: Colors.red);
      }
    } catch (e) {
      final fallback = Uri.parse(
        'https://www.openstreetmap.org/?mlat=${_shopLatitude!}&mlon=${_shopLongitude!}#map=18/${_shopLatitude!}/${_shopLongitude!}',
      );
      await launchUrl(fallback, mode: LaunchMode.externalApplication);
      if (mounted) {
        NotificationService.showSnackBar('Đã mở bản đồ shop (không lấy được vị trí hiện tại)', color: Colors.orange);
      }
    }
  }
}
