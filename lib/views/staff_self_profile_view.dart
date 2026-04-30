import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/db_helper.dart';
import '../l10n/app_localizations.dart';
import '../models/attendance_model.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../services/event_bus.dart';
import '../services/notification_service.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/entity_avatar.dart';
import '../widgets/responsive_wrapper.dart';
import 'repair_detail_view.dart';
import 'sale_detail_view.dart';

class StaffSelfProfileView extends StatefulWidget {
  const StaffSelfProfileView({super.key});

  @override
  State<StaffSelfProfileView> createState() => _StaffSelfProfileViewState();
}

class _StaffSelfProfileViewState extends State<StaffSelfProfileView> {
  final _db = DBHelper();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;

  String _uid = '';
  String _shopId = '';
  String _role = 'employee';
  String _email = '';
  String _avatarUrl = '';
  String _coverUrl = '';
  String _coverOriginalUrl = '';
  File? _selectedCover;
  File? _selectedCoverOriginal;
  double _coverAspectRatio = 16 / 9;
  String _shopName = '';

  int _salesCount = 0;
  int _repairsCount = 0;
  String _scheduleText = 'Chưa cài lịch';
  int _attendanceCount = 0;
  int _lateCount = 0;
  List<Attendance> _recentAttendance = const [];
  List<SaleOrder> _monthlySales = const [];
  List<Repair> _monthlyRepairs = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        Navigator.pop(context);
        return;
      }
      _uid = user.uid;
      _email = user.email ?? '';

      final userInfo = await UserService.getUserInfo(_uid);
      _nameCtrl.text = ((userInfo['displayName'] ?? userInfo['name'] ?? '').toString().trim());
      _phoneCtrl.text = (userInfo['phone'] ?? '').toString().trim();
      _addressCtrl.text = (userInfo['address'] ?? '').toString().trim();
      _role = (userInfo['role'] ?? 'employee').toString();
      _avatarUrl = (userInfo['photoUrl'] ?? '').toString().trim();
      _coverUrl = (userInfo['coverUrl'] ?? '').toString().trim();
      _coverOriginalUrl =
          (userInfo['coverOriginalUrl'] ?? userInfo['coverUrl'] ?? '').toString().trim();
      final storedAspect = (userInfo['coverAspectRatio'] as num?)?.toDouble();
      _coverAspectRatio = (storedAspect != null && storedAspect > 0)
          ? storedAspect
          : 16 / 9;

      final shopId = await UserService.getCurrentShopId();
      _shopId = (shopId ?? '').trim();
      if (_shopId.isNotEmpty) {
        final shopDoc = await FirebaseFirestore.instance.collection('shops').doc(_shopId).get();
        if (shopDoc.exists) {
          final data = shopDoc.data() ?? const <String, dynamic>{};
          _shopName = (data['name'] ?? '').toString().trim();
        }
      }

      try {
        _role = await UserService.getUserRole(_uid);
      } catch (_) {}

      await _loadStatsAndSchedule();
    } catch (e) {
      NotificationService.showSnackBar('Lỗi tải hồ sơ nhân viên: $e', color: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadStatsAndSchedule() async {
    final emailPrefix = _email.split('@').first.toUpperCase();
    final displayName = _nameCtrl.text.trim().toUpperCase();

    bool matchesStaff(String? value) {
      if (value == null || value.isEmpty) return false;
      final v = value.toUpperCase();
      return v == emailPrefix || v == displayName || v.contains(emailPrefix);
    }

    final repairs = await _db.getAllRepairs();
    final sales = await _db.getAllSales();

    final monthlyRepairs = repairs.where((r) {
      if (!_isTimestampInCurrentMonth(_repairActivityAt(r))) return false;
      if (matchesStaff(r.repairedBy)) return true;
      if ((r.repairedBy == null || r.repairedBy!.isEmpty) && r.status >= 3 && matchesStaff(r.createdBy)) {
        return true;
      }
      return false;
    }).toList()
      ..sort((a, b) => _repairActivityAt(b).compareTo(_repairActivityAt(a)));

    final monthlySales = sales.where((s) {
      if (!_isTimestampInCurrentMonth(s.soldAt)) return false;
      return matchesStaff(s.sellerName);
    }).toList()
      ..sort((a, b) => b.soldAt.compareTo(a.soldAt));

    _monthlyRepairs = monthlyRepairs;
    _monthlySales = monthlySales;
    _repairsCount = monthlyRepairs.length;
    _salesCount = monthlySales.length;

    if (_shopId.isNotEmpty) {
      final doc = await FirebaseFirestore.instance.collection('work_schedules').doc('staff_${_uid}_$_shopId').get();
      Map<String, dynamic>? schedule;
      if (doc.exists) {
        schedule = doc.data();
        await _db.upsertWorkSchedule(_uid, schedule!);
      }
      schedule ??= await _db.getWorkSchedule(_uid);
      if (schedule != null) {
        final start = (schedule['startTime'] ?? '08:00').toString();
        final end = (schedule['endTime'] ?? '17:00').toString();
        final breakTime = schedule['breakTime'] ?? 1;
        final ot = schedule['maxOtHours'] ?? 4;
        _scheduleText = '$start - $end | Nghỉ: ${breakTime}h | OT: ${ot}h';
      }
    }

    final attendance = await _db.getAttendanceByUser(_uid, limit: 120);
    final monthlyAttendance = attendance.where(_isAttendanceInCurrentMonth).toList();
    _recentAttendance = monthlyAttendance;
    _attendanceCount = monthlyAttendance.length;
    _lateCount = monthlyAttendance.where((a) => a.isLate == 1).length;
  }

  int _repairActivityAt(Repair repair) {
    return repair.finishedAt ?? repair.deliveredAt ?? repair.startedAt ?? repair.createdAt;
  }

  bool _isTimestampInCurrentMonth(int timestamp) {
    if (timestamp <= 0) return false;
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month;
  }

  bool _isAttendanceInCurrentMonth(Attendance attendance) {
    final now = DateTime.now();
    DateTime? date;
    if (attendance.dateKey.trim().isNotEmpty) {
      date = DateTime.tryParse(attendance.dateKey.trim());
    }
    date ??= attendance.checkInAt != null
        ? DateTime.fromMillisecondsSinceEpoch(attendance.checkInAt!)
        : DateTime.fromMillisecondsSinceEpoch(attendance.createdAt);
    return date.year == now.year && date.month == now.month;
  }

  Future<void> _pickAvatar() async {
    if (_saving) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
      maxWidth: 2200,
    );
    if (picked == null) return;
    setState(() => _saving = true);
    try {
      final uploadedUrl = await StorageService.uploadXFileAndGetUrl(picked, 'user_photos/$_uid');
      if (uploadedUrl == null || uploadedUrl.trim().isEmpty) {
        NotificationService.showSnackBar('Không thể tải ảnh đại diện', color: Colors.red);
        return;
      }
      await FirebaseFirestore.instance.collection('users').doc(_uid).set({
        'photoUrl': uploadedUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() => _avatarUrl = uploadedUrl);
      EventBus().emit('user_profile_changed');
      NotificationService.showSnackBar('Đã cập nhật ảnh đại diện', color: Colors.green);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseCoverSource() async {
    if (_saving) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Chọn từ thư viện'),
              onTap: () {
                Navigator.pop(ctx);
                _pickCoverFrom(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Chụp ảnh mới'),
              onTap: () {
                Navigator.pop(ctx);
                _pickCoverFrom(ImageSource.camera);
              },
            ),
            if (_selectedCoverOriginal != null || _coverOriginalUrl.trim().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Chỉnh ảnh hiện tại'),
                onTap: () {
                  Navigator.pop(ctx);
                  _editStoredOrSelectedCover();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCoverFrom(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        imageQuality: 92,
        maxWidth: 3000,
      );
      if (picked == null) return;
      final originalFile = File(picked.path);
      final result = await _openCoverEditor(originalFile);
      if (result == null) return;
      setState(() {
        _selectedCoverOriginal = originalFile;
        _selectedCover = result.croppedFile;
        _coverAspectRatio = result.aspectRatio;
      });
      NotificationService.showSnackBar(
        'Đã chọn vùng ảnh bìa. Nhấn Lưu hồ sơ để tải lên.',
        color: Colors.blue,
      );
    } catch (e) {
      NotificationService.showSnackBar('Không thể chọn ảnh bìa: $e', color: Colors.red);
    }
  }

  Future<void> _editStoredOrSelectedCover() async {
    File? source = _selectedCoverOriginal;
    source ??= await _loadCoverSourceFromStorage();
    if (source == null) {
      NotificationService.showSnackBar(
        'Không có ảnh gốc để chỉnh. Hãy chọn ảnh mới.',
        color: Colors.orange,
      );
      return;
    }

    final result = await _openCoverEditor(source);
    if (result == null) return;
    setState(() {
      _selectedCoverOriginal = source;
      _selectedCover = result.croppedFile;
      _coverAspectRatio = result.aspectRatio;
    });
    NotificationService.showSnackBar(
      'Đã cập nhật vùng crop ảnh bìa.',
      color: Colors.blue,
    );
  }

  Future<File?> _loadCoverSourceFromStorage() async {
    final url = _coverOriginalUrl.trim().isNotEmpty ? _coverOriginalUrl.trim() : _coverUrl.trim();
    if (url.isEmpty) return null;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final tempDir = await getTemporaryDirectory();
      final filePath = p.join(
        tempDir.path,
        'cover_source_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes, flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveInfo() async {
    if (_saving) return;
    final loc = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    try {
      String finalCoverUrl = _coverUrl;
      String finalCoverOriginalUrl = _coverOriginalUrl.isNotEmpty ? _coverOriginalUrl : _coverUrl;
      if (_selectedCover != null && _selectedCoverOriginal != null) {
        NotificationService.showSnackBar(
          'Đang tải ảnh bìa và ảnh gốc lên hệ thống...',
          color: Colors.blue,
          duration: const Duration(seconds: 6),
        );

        final uploadResults = await Future.wait<String?>([
          StorageService.uploadAndGetUrl(
            _selectedCover!.path,
            'user_photos/$_uid',
          ),
          StorageService.uploadAndGetUrl(
            _selectedCoverOriginal!.path,
            'user_photos/$_uid',
          ),
        ]);
        final croppedUrl = uploadResults[0];
        final originalUrl = uploadResults[1];
        if (croppedUrl == null || croppedUrl.trim().isEmpty || originalUrl == null || originalUrl.trim().isEmpty) {
          NotificationService.showSnackBar(
            'Tải ảnh bìa thất bại, vui lòng thử lại',
            color: Colors.red,
          );
          return;
        }
        finalCoverUrl = croppedUrl;
        finalCoverOriginalUrl = originalUrl;
      }

      await UserService.updateUserInfo(
        uid: _uid,
        name: _nameCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        role: null,
        loc: loc,
        photoUrl: _avatarUrl,
      );
      await FirebaseFirestore.instance.collection('users').doc(_uid).set({
        'coverUrl': finalCoverUrl,
        'coverOriginalUrl': finalCoverOriginalUrl,
        'coverAspectRatio': _coverAspectRatio,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      _coverUrl = finalCoverUrl;
      _coverOriginalUrl = finalCoverOriginalUrl;
      _selectedCover = null;
      _selectedCoverOriginal = null;
      EventBus().emit('user_profile_changed');
      if (!mounted) return;
      NotificationService.showSnackBar('Đã lưu hồ sơ nhân viên', color: Colors.green);
      await _loadStatsAndSchedule();
      setState(() {});
    } catch (e) {
      NotificationService.showSnackBar('Lỗi lưu hồ sơ: $e', color: Colors.red);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  ImageProvider? _buildCoverImageProvider() {
    if (_selectedCover != null) {
      return kIsWeb
          ? NetworkImage(_selectedCover!.path)
          : FileImage(_selectedCover!) as ImageProvider;
    }
    if (_coverUrl.trim().isNotEmpty) {
      return CachedNetworkImageProvider(
        _coverUrl,
        maxWidth: 2200,
        maxHeight: 1300,
      );
    }
    return null;
  }

  ImageProvider? _buildCoverOriginalImageProvider() {
    if (_selectedCoverOriginal != null) {
      return kIsWeb
          ? NetworkImage(_selectedCoverOriginal!.path)
          : FileImage(_selectedCoverOriginal!) as ImageProvider;
    }
    final source = _coverOriginalUrl.trim().isNotEmpty ? _coverOriginalUrl : _coverUrl;
    if (source.trim().isNotEmpty) {
      return CachedNetworkImageProvider(
        source,
        maxWidth: 3200,
        maxHeight: 3200,
      );
    }
    return null;
  }

  Future<_CoverCropResult?> _openCoverEditor(File sourceFile) async {
    final sourceBytes = await sourceFile.readAsBytes();
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      NotificationService.showSnackBar('Không đọc được ảnh đã chọn.', color: Colors.red);
      return null;
    }
    if (!mounted) return null;

    double localAspect = _coverAspectRatio;
    final controller = TransformationController();
    Rect? localCropRect;
    Rect localImageRect = Rect.zero;
    Size localViewportSize = Size.zero;
    double lastAspect = localAspect;
    double localZoom = 1.0;

    final result = await showDialog<_CoverCropResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog.fullscreen(
              backgroundColor: const Color(0xFF0E2236),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: const Icon(Icons.close, color: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Chỉnh ảnh bìa',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          ChoiceChip(
                            label: const Text('16:9'),
                            selected: (localAspect - (16 / 9)).abs() < 0.01,
                            onSelected: (_) {
                              setDialogState(() {
                                localAspect = 16 / 9;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('3:1'),
                            selected: (localAspect - 3).abs() < 0.01,
                            onSelected: (_) {
                              setDialogState(() {
                                localAspect = 3;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final viewport = Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          );
                          localViewportSize = viewport;
                          final imageRect = _fitContainRect(
                            sourceWidth: decoded.width.toDouble(),
                            sourceHeight: decoded.height.toDouble(),
                            canvasSize: viewport,
                          );
                          localImageRect = imageRect;

                          if (localCropRect == null ||
                              (lastAspect - localAspect).abs() > 0.0001) {
                            localCropRect =
                                _buildDefaultCropRect(imageRect, localAspect);
                            lastAspect = localAspect;
                          }

                          return Stack(
                            children: [
                              Positioned.fill(
                                child: Container(
                                  color: const Color(0xFF102235),
                                  child: InteractiveViewer(
                                    transformationController: controller,
                                    minScale: 1,
                                    maxScale: 5,
                                    boundaryMargin:
                                        const EdgeInsets.all(200),
                                    child: SizedBox(
                                      width: viewport.width,
                                      height: viewport.height,
                                      child: Image.file(
                                        sourceFile,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _buildCropMask(
                                imageRect: imageRect,
                                cropRect: localCropRect!,
                                containerSize: viewport,
                              ),
                              Positioned.fromRect(
                                rect: localCropRect!,
                                child: GestureDetector(
                                  onPanUpdate: (details) {
                                    setDialogState(() {
                                      final shifted =
                                          localCropRect!.shift(details.delta);
                                      localCropRect =
                                          _clampRectToBounds(shifted, imageRect);
                                    });
                                  },
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      color: Colors.black.withValues(alpha: 0.35),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                      child: Column(
                        children: [
                          Text(
                            'Dùng 2 ngón để pinch zoom ảnh, sau đó kéo khung trắng để chọn vùng bìa.',
                            style: AppTextStyles.caption.copyWith(
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                'Zoom',
                                style: TextStyle(color: Colors.white),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Slider(
                                  value: localZoom,
                                  min: 1,
                                  max: 5,
                                  divisions: 40,
                                  onChanged: (v) {
                                    setDialogState(() {
                                      localZoom = v;
                                      controller.value =
                                          Matrix4.identity()..scale(localZoom);
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () async {
                                final cropRect = localCropRect;
                                if (cropRect == null) return;
                                final croppedFile = await _cropCoverFile(
                                  sourceFile: sourceFile,
                                  sourceBytes: sourceBytes,
                                  imageRect: localImageRect,
                                  cropRect: cropRect,
                                  transform: controller.value,
                                  viewportSize: localViewportSize,
                                );
                                if (croppedFile == null) {
                                  NotificationService.showSnackBar(
                                    'Không thể crop ảnh bìa.',
                                    color: Colors.red,
                                  );
                                  return;
                                }
                                if (!dialogContext.mounted) return;
                                Navigator.pop(
                                  dialogContext,
                                  _CoverCropResult(
                                    croppedFile: croppedFile,
                                    aspectRatio: localAspect,
                                  ),
                                );
                              },
                              child: const Text('Áp dụng vùng ảnh bìa'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> _openFullCoverPreview() async {
    final provider = _buildCoverOriginalImageProvider();
    if (provider == null) {
      _chooseCoverSource();
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                minScale: 0.7,
                child: Center(
                  child: Image(
                    image: provider,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Rect _fitContainRect({
    required double sourceWidth,
    required double sourceHeight,
    required Size canvasSize,
  }) {
    if (canvasSize.width <= 0 || canvasSize.height <= 0 || sourceWidth <= 0 || sourceHeight <= 0) {
      return Rect.fromLTWH(0, 0, canvasSize.width, canvasSize.height);
    }
    final sourceRatio = sourceWidth / sourceHeight;
    final canvasRatio = canvasSize.width / canvasSize.height;

    if (sourceRatio > canvasRatio) {
      final width = canvasSize.width;
      final height = width / sourceRatio;
      final top = (canvasSize.height - height) / 2;
      return Rect.fromLTWH(0, top, width, height);
    }

    final height = canvasSize.height;
    final width = height * sourceRatio;
    final left = (canvasSize.width - width) / 2;
    return Rect.fromLTWH(left, 0, width, height);
  }

  Rect _buildDefaultCropRect(Rect imageRect, double aspectRatio) {
    if (imageRect.width <= 0 || imageRect.height <= 0) {
      return imageRect;
    }
    final availableRatio = imageRect.width / imageRect.height;
    double cropWidth;
    double cropHeight;

    if (availableRatio > aspectRatio) {
      cropHeight = imageRect.height * 0.82;
      cropWidth = cropHeight * aspectRatio;
    } else {
      cropWidth = imageRect.width * 0.82;
      cropHeight = cropWidth / aspectRatio;
    }

    final left = imageRect.left + (imageRect.width - cropWidth) / 2;
    final top = imageRect.top + (imageRect.height - cropHeight) / 2;
    return Rect.fromLTWH(left, top, cropWidth, cropHeight);
  }

  Rect _clampRectToBounds(Rect rect, Rect bounds) {
    final dx = rect.left < bounds.left
        ? bounds.left - rect.left
        : rect.right > bounds.right
            ? bounds.right - rect.right
            : 0.0;
    final dy = rect.top < bounds.top
        ? bounds.top - rect.top
        : rect.bottom > bounds.bottom
            ? bounds.bottom - rect.bottom
            : 0.0;
    return rect.shift(Offset(dx, dy));
  }

  Future<File?> _cropCoverFile({
    required File sourceFile,
    required Uint8List sourceBytes,
    required Rect imageRect,
    required Rect cropRect,
    required Matrix4 transform,
    required Size viewportSize,
  }) async {
    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) return null;

    if (imageRect.width <= 0 || imageRect.height <= 0) return null;
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return null;

    final inv = Matrix4.copy(transform);
    if (inv.invert() == 0) return null;

    final cropInChild = Rect.fromPoints(
      MatrixUtils.transformPoint(inv, cropRect.topLeft),
      MatrixUtils.transformPoint(inv, cropRect.bottomRight),
    );
    final normalizedCrop = Rect.fromLTRB(
      cropInChild.left < cropInChild.right ? cropInChild.left : cropInChild.right,
      cropInChild.top < cropInChild.bottom ? cropInChild.top : cropInChild.bottom,
      cropInChild.left < cropInChild.right ? cropInChild.right : cropInChild.left,
      cropInChild.top < cropInChild.bottom ? cropInChild.bottom : cropInChild.top,
    );

    final effective = normalizedCrop.intersect(imageRect);
    if (effective.width <= 1 || effective.height <= 1) return null;

    final relativeLeft = ((effective.left - imageRect.left) / imageRect.width).clamp(0.0, 1.0);
    final relativeTop = ((effective.top - imageRect.top) / imageRect.height).clamp(0.0, 1.0);
    final relativeWidth = (effective.width / imageRect.width).clamp(0.05, 1.0);
    final relativeHeight = (effective.height / imageRect.height).clamp(0.05, 1.0);

    final x = (relativeLeft * decoded.width).round().clamp(0, decoded.width - 2);
    final y = (relativeTop * decoded.height).round().clamp(0, decoded.height - 2);
    final w = (relativeWidth * decoded.width).round().clamp(1, decoded.width - x);
    final h = (relativeHeight * decoded.height).round().clamp(1, decoded.height - y);

    final cropped = img.copyCrop(
      decoded,
      x: x,
      y: y,
      width: w,
      height: h,
    );

    final tempDir = await getTemporaryDirectory();
    final fileName = 'cover_crop_${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourceFile.path)}.jpg';
    final outFile = File(p.join(tempDir.path, fileName));
    final encoded = img.encodeJpg(cropped, quality: 92);
    await outFile.writeAsBytes(encoded, flush: true);
    return outFile;
  }

  Widget _buildCropMask({
    required Rect imageRect,
    required Rect cropRect,
    required Size containerSize,
  }) {
    return Stack(
      children: [
        Positioned(
          left: imageRect.left,
          right: containerSize.width - imageRect.right,
          top: imageRect.top,
          height: (cropRect.top - imageRect.top).clamp(0, imageRect.height),
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
        Positioned(
          left: imageRect.left,
          right: containerSize.width - imageRect.right,
          top: cropRect.bottom,
          height: (imageRect.bottom - cropRect.bottom).clamp(0, imageRect.height),
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
        Positioned(
          left: imageRect.left,
          width: (cropRect.left - imageRect.left).clamp(0, imageRect.width),
          top: cropRect.top,
          height: cropRect.height,
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
        Positioned(
          left: cropRect.right,
          width: (imageRect.right - cropRect.right).clamp(0, imageRect.width),
          top: cropRect.top,
          height: cropRect.height,
          child: Container(color: Colors.black.withValues(alpha: 0.45)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final coverProvider = _buildCoverImageProvider();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Hồ sơ nhân viên'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0A56C2), Color(0xFF0E74DB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: ResponsiveCenter(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    onTap: _openFullCoverPreview,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 170,
                        color: const Color(0xFF123B63),
                        child: Stack(
                          children: [
                            if (coverProvider != null)
                              Positioned.fill(
                                child: SizedBox(
                                  width: constraints.maxWidth,
                                  height: 170,
                                  child: Image(
                                    image: coverProvider,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                            if (coverProvider == null)
                              Center(
                                child: Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.18),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 10,
                              bottom: 10,
                              child: Material(
                                color: Colors.black.withValues(alpha: 0.32),
                                borderRadius: BorderRadius.circular(999),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: _chooseCoverSource,
                                  child: const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: Icon(
                                      Icons.camera_alt_outlined,
                                      color: Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (_selectedCoverOriginal != null ||
                                _coverOriginalUrl.trim().isNotEmpty)
                              Positioned(
                                left: 10,
                                bottom: 10,
                                child: Material(
                                  color: Colors.black.withValues(alpha: 0.32),
                                  borderRadius: BorderRadius.circular(999),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(999),
                                    onTap: _editStoredOrSelectedCover,
                                    child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Icon(
                                        Icons.tune,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 18,
                  bottom: -32,
                  child: EntityAvatar(
                    imageUrl: _avatarUrl,
                    name: _nameCtrl.text.trim().isEmpty ? _email : _nameCtrl.text.trim(),
                    radius: 46,
                    showEditButton: true,
                    onEditTap: _pickAvatar,
                    heroTag: 'hero_staff_avatar_$_uid',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 42),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                _nameCtrl.text.trim().isEmpty ? _email : _nameCtrl.text.trim(),
                style: AppTextStyles.headline2.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            if (_shopName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  '${_roleLabel(_role)} thuộc shop ${_shopName.trim()}',
                  style: AppTextStyles.subtitle1.copyWith(color: Colors.grey.shade700),
                ),
              ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(child: _statCard('Đơn bán tháng', _salesCount.toString(), Icons.point_of_sale)),
                  const SizedBox(width: 8),
                  Expanded(child: _statCard('Đơn sửa tháng', _repairsCount.toString(), Icons.build_circle_outlined)),
                  const SizedBox(width: 8),
                  Expanded(child: _statCard('Công tháng', _attendanceCount.toString(), Icons.event_available)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thông tin cá nhân', style: AppTextStyles.headline6),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Họ và tên', prefixIcon: Icon(Icons.person)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _addressCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'Địa chỉ', prefixIcon: Icon(Icons.location_on)),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _saveInfo,
                        icon: _saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'ĐANG LƯU...' : 'LƯU HỒ SƠ'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B66D1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Chấm công cá nhân', style: AppTextStyles.headline6),
                        const Spacer(),
                        Text('Đi muộn: $_lateCount', style: AppTextStyles.caption.copyWith(color: Colors.orange.shade700)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_recentAttendance.isEmpty)
                      Text('Chưa có dữ liệu chấm công', style: AppTextStyles.caption)
                    else
                      ..._recentAttendance.take(8).map((a) {
                        final checkIn = a.checkInAt != null
                            ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(a.checkInAt!))
                            : '--:--';
                        final checkOut = a.checkOutAt != null
                            ? DateFormat('HH:mm').format(DateTime.fromMillisecondsSinceEpoch(a.checkOutAt!))
                            : '--:--';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: a.isLate == 1 ? Colors.orange.shade100 : Colors.green.shade100,
                            child: Icon(
                              a.isLate == 1 ? Icons.warning_amber_rounded : Icons.check,
                              size: 14,
                              color: a.isLate == 1 ? Colors.orange.shade700 : Colors.green.shade700,
                            ),
                          ),
                          title: Text(a.dateKey, style: AppTextStyles.body1),
                          subtitle: Text('Vào: $checkIn • Ra: $checkOut', style: AppTextStyles.caption),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Đơn bán tháng này', style: AppTextStyles.headline6),
                        const Spacer(),
                        if (_monthlySales.isNotEmpty)
                          TextButton(
                            onPressed: _showAllMonthlySales,
                            child: const Text('Xem tất cả'),
                          ),
                        Text('${_monthlySales.length} đơn', style: AppTextStyles.caption),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_monthlySales.isEmpty)
                      Text('Chưa có đơn bán trong tháng', style: AppTextStyles.caption)
                    else
                      ..._monthlySales.take(8).map((sale) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.blue.shade50,
                              child: Icon(Icons.point_of_sale, size: 14, color: Colors.blue.shade700),
                            ),
                            title: Text(
                              sale.customerName.isEmpty ? 'Khách lẻ' : sale.customerName,
                              style: AppTextStyles.body1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(sale.soldAt))} • ${sale.productNames}',
                              style: AppTextStyles.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              sale.totalPrice.toString(),
                              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
                            ),
                            onTap: () => _openSaleDetail(sale),
                          )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Đơn sửa tháng này', style: AppTextStyles.headline6),
                        const Spacer(),
                        if (_monthlyRepairs.isNotEmpty)
                          TextButton(
                            onPressed: _showAllMonthlyRepairs,
                            child: const Text('Xem tất cả'),
                          ),
                        Text('${_monthlyRepairs.length} đơn', style: AppTextStyles.caption),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_monthlyRepairs.isEmpty)
                      Text('Chưa có đơn sửa trong tháng', style: AppTextStyles.caption)
                    else
                      ..._monthlyRepairs.take(8).map((repair) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: Colors.orange.shade50,
                              child: Icon(Icons.build_circle_outlined, size: 14, color: Colors.orange.shade700),
                            ),
                            title: Text(
                              '${repair.customerName} • ${repair.model}',
                              style: AppTextStyles.body1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_repairActivityAt(repair)))} • ${_getRepairStatusText(repair.status)}',
                              style: AppTextStyles.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              repair.price.toString(),
                              style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
                            ),
                            onTap: () => _openRepairDetail(repair),
                          )),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: const Color(0xFF0B66D1), size: 18),
          const SizedBox(height: 4),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(title, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  String _roleLabel(String role) {
    switch (role.trim().toLowerCase()) {
      case 'owner':
        return 'Chủ shop';
      case 'manager':
      case 'admin':
        return 'Quản lý';
      case 'technician':
        return 'Kỹ thuật viên';
      default:
        return 'Nhân viên';
    }
  }

  String _getRepairStatusText(int status) {
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
        return 'Không rõ';
    }
  }

  Future<void> _openSaleDetail(SaleOrder sale) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => SaleDetailView(sale: sale)),
    );
  }

  Future<void> _openRepairDetail(Repair repair) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RepairDetailView(repair: repair)),
    );
  }

  Future<void> _showAllMonthlySales() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Text('Tất cả đơn bán tháng này', style: AppTextStyles.headline6),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _monthlySales.length,
                  itemBuilder: (context, index) {
                    final sale = _monthlySales[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.blue.shade50,
                        child: Icon(Icons.point_of_sale, size: 16, color: Colors.blue.shade700),
                      ),
                      title: Text(
                        sale.customerName.isEmpty ? 'Khách lẻ' : sale.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(sale.soldAt))} • ${sale.productNames}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(sale.totalPrice.toString(), style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _openSaleDetail(sale);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAllMonthlyRepairs() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.78,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
                child: Row(
                  children: [
                    Text('Tất cả đơn sửa tháng này', style: AppTextStyles.headline6),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _monthlyRepairs.length,
                  itemBuilder: (context, index) {
                    final repair = _monthlyRepairs[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.orange.shade50,
                        child: Icon(Icons.build_circle_outlined, size: 16, color: Colors.orange.shade700),
                      ),
                      title: Text(
                        '${repair.customerName} • ${repair.model}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${DateFormat('dd/MM HH:mm').format(DateTime.fromMillisecondsSinceEpoch(_repairActivityAt(repair)))} • ${_getRepairStatusText(repair.status)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(repair.price.toString(), style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700)),
                      onTap: () async {
                        Navigator.pop(ctx);
                        await _openRepairDetail(repair);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverCropResult {
  const _CoverCropResult({
    required this.croppedFile,
    required this.aspectRatio,
  });

  final File croppedFile;
  final double aspectRatio;
}
