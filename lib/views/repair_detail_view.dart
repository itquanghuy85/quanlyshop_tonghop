import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../utils/money_utils.dart';
import '../utils/repair_status_validator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/repair_model.dart';
import '../models/repair_service_model.dart';
import '../models/repair_partner_model.dart';
import '../services/unified_printer_service.dart';
import '../services/repair_partner_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../models/printer_types.dart';
import '../widgets/printer_selection_dialog.dart';
import '../services/notification_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../data/db_helper.dart';
import '../services/event_bus.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../theme/app_button_styles.dart';

class RepairDetailView extends StatefulWidget {
  final Repair repair;
  const RepairDetailView({super.key, required this.repair});

  @override
  State<RepairDetailView> createState() => _RepairDetailViewState();
}

class _RepairDetailViewState extends State<RepairDetailView> {
  final db = DBHelper();
  late Repair r;
  bool _isUpdating = false;
  bool _isPrinting = false;
  String _shopName = "";
  String _shopAddr = "";
  String _shopPhone = "";
  bool _hasPermission = false;
  List<RepairPartner> _partners = [];

  @override
  void initState() {
    super.initState();
    r = widget.repair;
    _checkPermission();
    _loadShopInfo();
    _loadPartners();
  }

  Future<void> _loadPartners() async {
    final partnerService = RepairPartnerService();
    final partners = await partnerService.getRepairPartners();
    if (!mounted) return;
    setState(() => _partners = partners);
  }

  Future<void> _checkPermission() async {
    final perms = await UserService.getCurrentUserPermissions();
    if (!mounted) return;
    setState(() => _hasPermission = perms['allowViewRepairs'] ?? false);
  }

  Future<void> _loadShopInfo() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shopName = prefs.getString('shop_name') ?? "SHOP NEW";
      _shopAddr = prefs.getString('shop_address') ?? "Chuyên Smartphone";
      _shopPhone = prefs.getString('shop_phone') ?? "0123.456.789";
    });
  }

  Widget _buildSmartImage(String path) {
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) => progress == null
            ? child
            : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        errorBuilder: (ctx, err, stack) =>
            const Icon(Icons.broken_image, color: AppColors.error),
      );
    }
    File file = File(path);
    if (file.existsSync()) return Image.file(file, fit: BoxFit.cover);
    return const Icon(Icons.cloud_download, color: AppColors.primary);
  }

  Future<void> _updateStatus(int newStatus) async {
    debugPrint(
      'Starting status update from ${r.status} to $newStatus for repair ${r.firestoreId}',
    );

    // Validate status transition using state machine
    final transitionError = RepairStatusValidator.getTransitionError(
      r.status,
      newStatus,
    );
    if (transitionError != null) {
      NotificationService.showSnackBar(transitionError, color: AppColors.error);
      return;
    }

    final repairsBefore = await db.getAllRepairs();
    debugPrint('Repairs count before update: ${repairsBefore.length}');

    // Kiểm tra nếu bấm "Đã giao" (status 4) và user không phải admin/owner
    // thì chuyển sang trạng thái 5 (Chờ duyệt giao) thay vì 4
    if (newStatus == 4) {
      final currentRole = await UserService.getRoleFast();
      final isManagerOrOwner = currentRole == 'admin' || currentRole == 'owner';

      if (!isManagerOrOwner) {
        // Nhân viên thường: chuyển sang trạng thái "Chờ duyệt giao" (5)
        await _submitForDeliveryApproval();
        return;
      }
    }

    // Duyệt đơn chờ giao (từ status 5 -> 4) - chỉ admin/owner mới thấy nút này
    if (r.status == 5 && newStatus == 4) {
      // Admin/owner duyệt đơn chờ giao
      await _approveDelivery();
      return;
    }

    if (newStatus == 4) {
      // GIAO MÁY
      String payMethod = "TIỀN MẶT";
      String selectedWarranty = r.warranty.isEmpty ? "1 THÁNG" : r.warranty;
      final List<String> warrantyOptions = [
        "KO BH",
        "1 THÁNG",
        "3 THÁNG",
        "6 THÁNG",
        "12 THÁNG",
      ];

      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setS) => AlertDialog(
            title: const Text("XÁC NHẬN GIAO MÁY & THANH TOÁN"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Chọn thời gian bảo hành:",
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: warrantyOptions
                      .map(
                        (opt) => ChoiceChip(
                          label: Text(opt, style: AppTextStyles.caption),
                          selected: selectedWarranty == opt,
                          onSelected: (v) => setS(() => selectedWarranty = opt),
                          selectedColor: AppColors.primary.withOpacity(0.2),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
                Text(
                  "Hình thức thanh toán:",
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ["TIỀN MẶT", "CHUYỂN KHOẢN", "CÔNG NỢ"]
                      .map(
                        (m) => ChoiceChip(
                          label: Text(m, style: AppTextStyles.caption),
                          selected: payMethod == m,
                          onSelected: (v) => setS(() => payMethod = m),
                          selectedColor: AppColors.secondary.withOpacity(0.2),
                        ),
                      )
                      .toList(),
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
                style: AppButtonStyles.elevatedButtonStyle,
                child: Text("HOÀN TẤT GIAO MÁY", style: AppTextStyles.button),
              ),
            ],
          ),
        ),
      );

      if (confirm != true) return;
      r.warranty = selectedWarranty;
      r.paymentMethod = payMethod;
      r.deliveredAt = DateTime.now().millisecondsSinceEpoch;

      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";

      // GHI NHẬT KÝ GIAO MÁY
      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: "GIAO MÁY",
        type: "REPAIR",
        targetId: r.firestoreId,
        desc:
            "Đã giao máy ${r.model} cho khách ${r.customerName}. Bảo hành: $selectedWarranty",
      );

      if (payMethod == "CÔNG NỢ") {
        // FIX: Tạo firestoreId TRƯỚC khi insert để tránh duplicate khi sync
        final debtFId =
            "debt_${DateTime.now().millisecondsSinceEpoch}_${r.phone.hashCode}";
        final debtData = {
          'personName': r.customerName,
          'phone': r.phone,
          'totalAmount': r.price,
          'paidAmount': 0,
          'type': "CUSTOMER_OWES",
          'status': "ACTIVE",
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'note': "Nợ tiền sửa máy: ${r.model}",
          'linkedId': r.firestoreId,
          'firestoreId': debtFId, // Set firestoreId ngay từ đầu
        };
        final debtId = await db.insertDebt(debtData);

        // Queue sync debt to cloud via SyncOrchestrator
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.debt,
          entityId: debtId,
          firestoreId: debtFId,
          operation: SyncOperation.create,
          data: debtData,
        );
      }

      // GHIM ĐƠN SỬA VÀO CHAT NỘI BỘ KHI GIAO MÁY
      final key = r.firestoreId ?? "repair_${r.createdAt}";
      final summary =
          "ĐƠN SỬA - ${r.customerName} - ${r.phone} - ${r.model} - ${MoneyUtils.formatCurrency(r.price)} đ";
      final msg = "✅ ĐÃ GIAO MÁY: $summary";
      await FirestoreService.sendChat(
        message: msg,
        senderId: user?.uid ?? 'guest',
        senderName: userName,
        linkedType: 'repair',
        linkedKey: key,
        linkedSummary: summary,
      );
    }

    if (newStatus == 3) r.finishedAt = DateTime.now().millisecondsSinceEpoch;

    // Update lastCaredAt for conflict resolution during sync
    r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
    r.isSynced = false; // Mark as needing sync

    setState(() {
      r.status = newStatus;
      _isUpdating = true;
    });
    try {
      debugPrint(
        'Updating repair status to $newStatus for repair ${r.firestoreId}',
      );
      await db.upsertRepair(r);

      // Queue sync repair to cloud via SyncOrchestrator
      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );
      }

      debugPrint('Repair status updated successfully');
      final repairsAfter = await db.getAllRepairs();
      debugPrint('Repairs count after update: ${repairsAfter.length}');
      NotificationService.showSnackBar(
        "ĐÃ CẬP NHẬT: ${_getStatusText(newStatus)}",
        color: AppColors.success,
      );
      EventBus().emit('repairs_changed');

      // GỬI PUSH NOTIFICATION khi thay đổi trạng thái (trừ status 4 đã xử lý riêng)
      if (newStatus != 4) {
        try {
          final user = FirebaseAuth.instance.currentUser;
          final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";
          final key = r.firestoreId ?? "repair_${r.createdAt}";
          final summary =
              "ĐƠN SỬA - ${r.customerName} - ${r.phone} - ${r.model}";

          String emoji = "";
          String statusMsg = "";
          switch (newStatus) {
            case 1:
              emoji = "📥";
              statusMsg = "NHẬN MÁY";
              break;
            case 2:
              emoji = "🔧";
              statusMsg = "BẮT ĐẦU SỬA";
              break;
            case 3:
              emoji = "✔️";
              statusMsg = "SỬA XONG";
              break;
          }

          final msg = "$emoji $statusMsg: $summary";

          // Gửi push notification cho mọi người
          await NotificationService.sendCloudNotification(
            title: '$emoji $statusMsg',
            body: '${r.customerName} - ${r.model}',
            type: 'new_order',
          );

          // Ghim vào chat nội bộ
          await FirestoreService.sendChat(
            message: msg,
            senderId: user?.uid ?? 'guest',
            senderName: userName,
            linkedType: 'repair',
            linkedKey: key,
            linkedSummary: summary,
          );
        } catch (e) {
          debugPrint('Failed to send status notification/chat: $e');
        }
      }
    } catch (e) {
      debugPrint('Error updating repair status: $e');
    }
    setState(() => _isUpdating = false);
  }

  String _getStatusText(int s) {
    switch (s) {
      case 1:
        return "TIẾP NHẬN";
      case 2:
        return "ĐANG SỬA";
      case 3:
        return "SỬA XONG";
      case 4:
        return "ĐÃ GIAO";
      case 5:
        return "CHỜ DUYỆT GIAO";
      default:
        return "KHÁC";
    }
  }

  Color _getStatusColor(int s) {
    switch (s) {
      case 1:
        return Colors.blue;
      case 2:
        return Colors.orange;
      case 3:
        return AppColors.success;
      case 4:
        return AppColors.primary;
      case 5:
        return Colors.deepOrange; // Màu cho trạng thái chờ duyệt
      default:
        return Colors.grey;
    }
  }

  /// Nhân viên submit đơn chờ duyệt giao (status 5)
  Future<void> _submitForDeliveryApproval() async {
    String payMethod = "TIỀN MẶT";
    String selectedWarranty = r.warranty.isEmpty ? "1 THÁNG" : r.warranty;
    final List<String> warrantyOptions = [
      "KO BH",
      "1 THÁNG",
      "3 THÁNG",
      "6 THÁNG",
      "12 THÁNG",
    ];

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text("GỬI YÊU CẦU GIAO MÁY"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Đơn sẽ được gửi cho quản lý duyệt trước khi hoàn tất giao máy',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                "Chọn thời gian bảo hành:",
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: warrantyOptions
                    .map(
                      (opt) => ChoiceChip(
                        label: Text(opt, style: AppTextStyles.caption),
                        selected: selectedWarranty == opt,
                        onSelected: (v) => setS(() => selectedWarranty = opt),
                        selectedColor: AppColors.primary.withOpacity(0.2),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              Text(
                "Hình thức thanh toán:",
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ["TIỀN MẶT", "CHUYỂN KHOẢN", "CÔNG NỢ"]
                    .map(
                      (m) => ChoiceChip(
                        label: Text(m, style: AppTextStyles.caption),
                        selected: payMethod == m,
                        onSelected: (v) => setS(() => payMethod = m),
                        selectedColor: AppColors.secondary.withOpacity(0.2),
                      ),
                    )
                    .toList(),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepOrange,
              ),
              child: const Text(
                "GỬI YÊU CẦU DUYỆT",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirm != true) return;

    r.warranty = selectedWarranty;
    r.paymentMethod = payMethod;
    r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
    r.isSynced = false;

    setState(() {
      r.status = 5; // Chờ duyệt giao
      _isUpdating = true;
    });

    try {
      await db.upsertRepair(r);

      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );
      }

      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";

      // Gửi notification cho quản lý
      await NotificationService.sendCloudNotification(
        title: '📋 YÊU CẦU DUYỆT GIAO MÁY',
        body:
            '${r.customerName} - ${r.model} (${MoneyUtils.formatCurrency(r.price)}đ)',
        type: 'approval_needed',
      );

      // Log và chat
      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: "YÊU CẦU DUYỆT GIAO",
        type: "REPAIR",
        targetId: r.firestoreId,
        desc: "Yêu cầu duyệt giao máy ${r.model} cho khách ${r.customerName}",
      );

      final key = r.firestoreId ?? "repair_${r.createdAt}";
      await FirestoreService.sendChat(
        message:
            "📋 YÊU CẦU DUYỆT GIAO: ${r.model} - ${r.customerName} - ${MoneyUtils.formatCurrency(r.price)}đ",
        senderId: user?.uid ?? 'guest',
        senderName: userName,
        linkedType: 'repair',
        linkedKey: key,
        linkedSummary: "Chờ duyệt giao - ${r.customerName}",
      );

      NotificationService.showSnackBar(
        "Đã gửi yêu cầu duyệt giao máy",
        color: Colors.deepOrange,
      );
      EventBus().emit('repairs_changed');
    } catch (e) {
      debugPrint('Error submitting for approval: $e');
    }
    setState(() => _isUpdating = false);
  }

  /// Quản lý duyệt đơn giao máy (status 5 -> 4)
  Future<void> _approveDelivery() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("DUYỆT GIAO MÁY"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Khách: ${r.customerName}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text("Máy: ${r.model}"),
                  Text("Giá: ${MoneyUtils.formatCurrency(r.price)}đ"),
                  Text("Bảo hành: ${r.warranty}"),
                  Text("Thanh toán: ${r.paymentMethod}"),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "Xác nhận duyệt giao máy và hoàn tất giao dịch?",
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("HỦY"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx, false);
              // Từ chối - quay lại status 3
              await _rejectDeliveryApproval();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("TỪ CHỐI"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text("DUYỆT", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    r.deliveredAt = DateTime.now().millisecondsSinceEpoch;
    r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
    r.isSynced = false;

    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@').first.toUpperCase() ?? "QL";

    setState(() {
      r.status = 4; // Đã giao
      _isUpdating = true;
    });

    try {
      // Tạo công nợ nếu thanh toán công nợ
      if (r.paymentMethod == "CÔNG NỢ") {
        final debtFId =
            "debt_${DateTime.now().millisecondsSinceEpoch}_${r.phone.hashCode}";
        final debtData = {
          'personName': r.customerName,
          'phone': r.phone,
          'totalAmount': r.price,
          'paidAmount': 0,
          'type': "CUSTOMER_OWES",
          'status': "ACTIVE",
          'createdAt': DateTime.now().millisecondsSinceEpoch,
          'note': "Nợ tiền sửa máy: ${r.model}",
          'linkedId': r.firestoreId,
          'firestoreId': debtFId,
        };
        final debtId = await db.insertDebt(debtData);
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.debt,
          entityId: debtId,
          firestoreId: debtFId,
          operation: SyncOperation.create,
          data: debtData,
        );
      }

      await db.upsertRepair(r);

      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );
      }

      // Log
      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: "DUYỆT GIAO MÁY",
        type: "REPAIR",
        targetId: r.firestoreId,
        desc:
            "Đã duyệt giao máy ${r.model} cho khách ${r.customerName}. Bảo hành: ${r.warranty}",
      );

      // Chat notification
      final key = r.firestoreId ?? "repair_${r.createdAt}";
      final summary =
          "ĐƠN SỬA - ${r.customerName} - ${r.phone} - ${r.model} - ${MoneyUtils.formatCurrency(r.price)}đ";
      await FirestoreService.sendChat(
        message: "✅ ĐÃ DUYỆT GIAO MÁY: $summary",
        senderId: user?.uid ?? 'guest',
        senderName: userName,
        linkedType: 'repair',
        linkedKey: key,
        linkedSummary: summary,
      );

      NotificationService.showSnackBar(
        "Đã duyệt và hoàn tất giao máy",
        color: Colors.green,
      );
      EventBus().emit('repairs_changed');
    } catch (e) {
      debugPrint('Error approving delivery: $e');
    }
    setState(() => _isUpdating = false);
  }

  /// Từ chối duyệt giao - quay lại status 3 (Sửa xong)
  Future<void> _rejectDeliveryApproval() async {
    r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
    r.isSynced = false;

    setState(() {
      r.status = 3;
      _isUpdating = true;
    });

    try {
      await db.upsertRepair(r);
      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );
      }

      final user = FirebaseAuth.instance.currentUser;
      final userName = user?.email?.split('@').first.toUpperCase() ?? "QL";

      await db.logAction(
        userId: user?.uid ?? "0",
        userName: userName,
        action: "TỪ CHỐI GIAO",
        type: "REPAIR",
        targetId: r.firestoreId,
        desc: "Từ chối duyệt giao máy ${r.model}",
      );

      NotificationService.showSnackBar(
        "Đã từ chối - đơn quay lại trạng thái Sửa xong",
        color: Colors.red,
      );
      EventBus().emit('repairs_changed');
    } catch (e) {
      debugPrint('Error rejecting delivery: $e');
    }
    setState(() => _isUpdating = false);
  }

  Future<void> _saveData() async {
    setState(() => _isUpdating = true);
    HapticFeedback.mediumImpact();
    try {
      // Update lastCaredAt for conflict resolution during sync
      r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
      r.isSynced = false; // Mark as needing sync

      await db.upsertRepair(r);

      // Ghi nhật ký sửa đơn
      final user = FirebaseAuth.instance.currentUser;
      await db.logAction(
        userId: user?.uid ?? '0',
        userName: user?.email?.split('@').first.toUpperCase() ?? 'NV',
        action: 'SỬA ĐƠN SỬA',
        type: 'REPAIR',
        targetId: r.firestoreId,
        desc:
            'Cập nhật đơn sửa ${r.model} - ${r.customerName} - Giá: ${r.price}đ',
      );

      // Queue sync repair to cloud via SyncOrchestrator
      if (r.id != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.repair,
          entityId: r.id!,
          firestoreId: r.firestoreId,
          operation: SyncOperation.update,
          data: r.toMap(),
        );
      }

      // Update debt if payment method is debt and repair is delivered
      if (r.paymentMethod == 'CÔNG NỢ' && r.status == 4) {
        final existingDebts = await db.getAllDebts();
        final linkedDebt = existingDebts
            .where((d) => d['linkedId'] == r.firestoreId)
            .firstOrNull;
        final debtAmount = r.price - r.cost; // Profit amount
        if (linkedDebt != null) {
          // Update existing debt
          linkedDebt['amount'] = debtAmount;
          linkedDebt['remainingAmount'] =
              debtAmount - (linkedDebt['paidAmount'] ?? 0);
          linkedDebt['status'] = linkedDebt['remainingAmount'] > 0
              ? 'ACTIVE'
              : 'PAID';
          await db.updateDebt(linkedDebt);

          // Queue sync debt to cloud via SyncOrchestrator
          final debtId = linkedDebt['id'] as int?;
          if (debtId != null) {
            await SyncOrchestrator().enqueue(
              entityType: SyncEntityType.debt,
              entityId: debtId,
              firestoreId: linkedDebt['firestoreId'] as String?,
              operation: SyncOperation.update,
              data: linkedDebt,
            );
          }
        }
        // Removed create new debt logic to avoid duplicates
      }

      NotificationService.showSnackBar(
        "ĐÃ LƯU THAY ĐỔI ĐƠN HÀNG",
        color: AppColors.success,
      );
      EventBus().emit('repairs_changed');
    } catch (e) {
      NotificationService.showSnackBar(
        "Lỗi khi lưu: $e",
        color: AppColors.error,
      );
    }
    if (mounted) setState(() => _isUpdating = false);
  }

  /// Dialog chọn phụ tùng từ kho và tự động trừ kho
  /// LƯU Ý: Mỗi lần chọn và xác nhận sẽ THÊM vào đơn và TRỪ KHO ngay lập tức
  Future<void> _selectPartsFromInventory() async {
    // Hiển thị cảnh báo nếu đã có phụ tùng
    if (r.partsUsed.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text("LƯU Ý"),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Đơn này đã có phụ tùng:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(r.partsUsed, style: const TextStyle(color: Colors.purple)),
              const SizedBox(height: 16),
              const Text(
                "Nếu tiếp tục chọn, phụ tùng mới sẽ được THÊM VÀO và TRỪ KHO NGAY.\n\nBạn có muốn tiếp tục?",
                style: TextStyle(fontSize: 13),
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
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              child: const Text(
                "TIẾP TỤC CHỌN THÊM",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Lấy linh kiện từ CẢ 2 nguồn: repair_parts (kho cũ) + products type='LINH KIỆN' (kho mới)
    final parts = await db.getAllPartsUnified();
    if (parts.isEmpty) {
      // Thử load products để xem có nhưng chưa đánh đúng loại
      final allProducts = await db.getAllProducts();
      final linhKienProducts = allProducts
          .where((p) => p.type == 'LINH KIỆN')
          .toList();
      final phuKienProducts = allProducts
          .where((p) => p.type == 'PHỤ KIỆN')
          .toList();

      String msg = "Kho Linh Kiện trống. ";
      if (allProducts.isEmpty) {
        msg += "Chưa có sản phẩm nào trong kho.";
      } else {
        msg +=
            "Tổng: ${allProducts.length}, LINH KIỆN: ${linhKienProducts.length}. ";
        if (linhKienProducts.isEmpty) {
          msg += "Vào Kho → Nhập SP → Chọn loại 'LINH KIỆN'";
        }
      }

      NotificationService.showSnackBar(msg, color: Colors.orange);
      return;
    }

    // Hiển thị dialog chọn linh kiện
    final result = await showDialog<Map<String, int>?>(
      context: context,
      builder: (ctx) => _PartsSelectionDialog(parts: parts),
    );

    if (result != null && result.isNotEmpty) {
      int totalCost = 0;
      List<String> usedParts = [];

      for (var entry in result.entries) {
        final uniqueKey = entry.key;
        final qty = entry.value;

        // Parse uniqueKey = "source_id" (source có thể chứa underscore như "repair_parts")
        // Lấy phần cuối cùng sau dấu _ làm id
        final lastUnderscoreIndex = uniqueKey.lastIndexOf('_');
        final source = uniqueKey.substring(0, lastUnderscoreIndex);
        final partId = int.parse(uniqueKey.substring(lastUnderscoreIndex + 1));

        final part = parts.firstWhere(
          (p) => p['id'] == partId && p['source'] == source,
        );
        final partName = part['partName'] ?? '';
        final partCost = part['cost'] as int? ?? 0;

        // Trừ kho từ nguồn phù hợp
        final success = await db.deductPartQuantityUnified(partId, source, qty);
        if (success) {
          totalCost += partCost * qty;
          usedParts.add("$partName x$qty");
        }
      }

      // Cập nhật giá vốn và partsUsed
      setState(() {
        r.cost += totalCost;
        if (r.partsUsed.isNotEmpty) {
          r.partsUsed = "${r.partsUsed}, ${usedParts.join(', ')}";
        } else {
          r.partsUsed = usedParts.join(', ');
        }
      });

      await _saveData();

      NotificationService.showSnackBar(
        "Đã thêm phụ tùng và trừ kho: ${usedParts.join(', ')}",
        color: Colors.green,
      );
    }
  }

  Future<void> _editFinancials() async {
    final formKey = GlobalKey<FormState>();
    final priceC = TextEditingController(
      text: MoneyUtils.formatCurrency(r.price),
    );
    final costC = TextEditingController(
      text: MoneyUtils.formatCurrency(r.cost),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("TÀI CHÍNH ĐƠN SỬA"),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: priceC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyUtils.currencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: "Giá thu khách (VNĐ)",
                  ),
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 0,
                    fieldName: 'Giá thu khách',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: costC,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyUtils.currencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: "Giá vốn linh kiện (VNĐ)",
                  ),
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 0,
                    fieldName: 'Giá vốn',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("HỦY"),
            ),
            ElevatedButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                Navigator.pop(ctx, true);
              },
              child: const Text("LƯU"),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      final oldCost = r.cost;
      final oldPrice = r.price;
      setState(() {
        final parsedPrice = MoneyUtils.parseCurrency(priceC.text);
        final parsedCost = MoneyUtils.parseCurrency(costC.text);
        r.price = parsedPrice;
        r.cost = parsedCost;
      });
      // Note: Chi phí linh kiện được theo dõi qua repair.cost và tính vào repairCost trong báo cáo
      // Không cần tạo expense riêng để tránh double-counting
      _saveData();
    }
  }

  /// Cho phép KTV ghi chú cho đơn sửa (vd: kt thay ic hay sàng main ...)
  Future<void> _editTechnicianNotes() async {
    final notesC = TextEditingController(text: r.notes ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("GHI CHÚ KỸ THUẬT VIÊN"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Ghi chú quá trình sửa chữa:",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesC,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: "VD: KT thay IC nguồn, sàng main, thay cáp sạc...",
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
            ),
            child: const Text("LƯU"),
          ),
        ],
      ),
    );
    if (result == true) {
      setState(() {
        r.notes = notesC.text.trim().isEmpty ? null : notesC.text.trim();
      });
      _saveData();
      NotificationService.showSnackBar(
        "Đã lưu ghi chú KTV",
        color: Colors.green,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_hasPermission) {
      return Scaffold(
        appBar: AppBar(title: const Text("CHI TIẾT ĐƠN SỬA")),
        body: Center(
          child: Text(
            "Bạn không có quyền truy cập tính năng này",
            style: AppTextStyles.body1.copyWith(
              color: AppColors.onSurface.withOpacity(0.6),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF2962FF),
                const Color(0xFF2962FF).withOpacity(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Tooltip(
          message: "Theo dõi tiến độ sửa chữa và cập nhật trạng thái.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "CHI TIẾT ĐƠN SỬA",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              Text(
                r.model,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
            ],
          ),
        ),
        automaticallyImplyLeading: true,
        actions: [
          IconButton(
            onPressed: _shareToZalo,
            icon: const Icon(Icons.share_rounded, color: Colors.white),
          ),
          IconButton(
            onPressed: _printReceipt,
            icon: const Icon(Icons.print_rounded, color: Colors.white),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildStatusCard(),
            const SizedBox(height: 15),
            _buildActionButtons(),
            const SizedBox(height: 20),
            _buildFinancialSummary(),
            const SizedBox(height: 20),
            _buildServicesSection(),
            const SizedBox(height: 20),
            _buildImageGallery(),
            const SizedBox(height: 20),
            _buildCustomerCard(),
            const SizedBox(height: 100),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomActions(),
    );
  }

  Widget _buildStatusCard() {
    Color color;
    IconData icon;

    switch (r.status) {
      case 1:
        color = Colors.blue;
        icon = Icons.assignment_turned_in;
        break;
      case 2:
        color = Colors.orange;
        icon = Icons.build;
        break;
      case 3:
        color = AppColors.success;
        icon = Icons.check_circle;
        break;
      case 4:
        color = AppColors.primary;
        icon = Icons.verified;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(r.model.toUpperCase(), style: AppTextStyles.headline5),
                Text(
                  _getStatusText(r.status),
                  style: AppTextStyles.body2.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (r.status == 4) return const SizedBox();

    // Status 5: Chờ duyệt giao - chỉ quản lý mới thấy nút duyệt
    if (r.status == 5) {
      return FutureBuilder<String>(
        future: UserService.getRoleFast(),
        builder: (context, snapshot) {
          final role = snapshot.data ?? 'user';
          final isManager = role == 'admin' || role == 'owner';

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.deepOrange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepOrange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hourglass_empty,
                      color: Colors.deepOrange.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isManager
                            ? 'Đơn đang chờ bạn duyệt giao máy'
                            : 'Đang chờ quản lý duyệt giao máy',
                        style: TextStyle(
                          color: Colors.deepOrange.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isManager) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _approveDelivery(),
                    icon: const Icon(Icons.check_circle, size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    label: const Text(
                      "DUYỆT GIAO MÁY",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      );
    }

    return Column(
      children: [
        // Row 1: Đang sửa + Đã xong
        if (r.status < 3)
          Row(
            children: [
              // Nút ĐANG SỬA - chỉ hiện khi status = 1 (Tiếp nhận)
              if (r.status == 1)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _updateStatus(2),
                    icon: const Icon(Icons.build, size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    label: Text("ĐANG SỬA", style: AppTextStyles.button),
                  ),
                ),
              if (r.status == 1) const SizedBox(width: 10),
              // Nút ĐÃ XONG
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _updateStatus(3),
                  icon: const Icon(Icons.check_circle, size: 18),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: AppColors.onSuccess,
                  ),
                  label: Text("ĐÃ XONG", style: AppTextStyles.button),
                ),
              ),
            ],
          ),
        if (r.status < 3) const SizedBox(height: 10),
        // Row 2: Giao máy
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _updateStatus(4),
            icon: const Icon(Icons.handshake, size: 18),
            style: AppButtonStyles.elevatedButtonStyle,
            label: Text("GIAO MÁY", style: AppTextStyles.button),
          ),
        ),
      ],
    );
  }

  Widget _buildFinancialSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Lợi nhuận dự kiến",
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "${MoneyUtils.formatCurrency(r.price - r.cost)} đ",
                style: AppTextStyles.headline5.copyWith(
                  color: AppColors.success,
                ),
              ),
            ],
          ),
          const Divider(height: 25),
          Row(
            children: [
              _miniFin("GIÁ THU", r.price, AppColors.primary),
              _miniFin("GIÁ VỐN", r.cost, AppColors.warning),
            ],
          ),
          const SizedBox(height: 10),
          // Hiển thị phụ tùng đã dùng
          if (r.partsUsed.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              children: [
                const Icon(Icons.build, size: 16, color: Colors.purple),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Phụ tùng: ${r.partsUsed}",
                    style: AppTextStyles.caption.copyWith(color: Colors.purple),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceEvenly,
            spacing: 4,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: _selectPartsFromInventory,
                icon: const Icon(
                  Icons.inventory_2,
                  size: 14,
                  color: Colors.purple,
                ),
                label: Text(
                  "Phụ tùng",
                  style: AppTextStyles.caption.copyWith(color: Colors.purple),
                ),
              ),
              TextButton.icon(
                onPressed: _editFinancials,
                icon: const Icon(Icons.edit, size: 14),
                label: Text("Sửa giá", style: AppTextStyles.caption),
              ),
              TextButton.icon(
                onPressed: _editTechnicianNotes,
                icon: const Icon(
                  Icons.note_add,
                  size: 14,
                  color: Colors.orange,
                ),
                label: Text(
                  "KTV",
                  style: AppTextStyles.caption.copyWith(color: Colors.orange),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniFin(String l, int v, Color c) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l,
          style: AppTextStyles.overline.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          MoneyUtils.formatCurrency(v),
          style: AppTextStyles.body2.copyWith(
            color: c,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _buildServicesSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "DỊCH VỤ SỬA CHỮA",
                style: AppTextStyles.body1.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (r.status != 4)
                TextButton.icon(
                  onPressed: _showAddServiceDialog,
                  icon: const Icon(Icons.add, size: 18, color: Colors.blue),
                  label: Text(
                    "THÊM DỊCH VỤ",
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.blue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const Divider(height: 16),
          if (r.services.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                "Chưa có dịch vụ nào",
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.onSurface.withOpacity(0.5),
                  fontStyle: FontStyle.italic,
                ),
              ),
            )
          else
            ...r.services.asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              return Container(
                margin: EdgeInsets.only(
                  bottom: i < r.services.length - 1 ? 10 : 0,
                ),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.build_circle,
                      size: 20,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.serviceName,
                            style: AppTextStyles.body2.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (s.partnerName != null)
                            Text(
                              "Đối tác: ${s.partnerName}",
                              style: AppTextStyles.caption.copyWith(
                                color: Colors.purple,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      "${MoneyUtils.formatCurrency(s.cost)} đ",
                      style: AppTextStyles.body2.copyWith(
                        color: AppColors.warning,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (r.status != 4)
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          size: 18,
                          color: Colors.grey,
                        ),
                        onPressed: () => _showAddServiceDialog(s, i),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              );
            }),
          if (r.services.isNotEmpty) ...[
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Tổng chi phí dịch vụ",
                  style: AppTextStyles.body2.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "${MoneyUtils.formatCurrency(r.services.fold(0, (sum, s) => sum + s.cost))} đ",
                  style: AppTextStyles.body1.copyWith(
                    color: AppColors.warning,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showAddServiceDialog([RepairService? editService, int? editIndex]) {
    final formKey = GlobalKey<FormState>();
    final serviceCtrl = TextEditingController(
      text: editService?.serviceName ?? '',
    );
    final costCtrl = TextEditingController(
      text: editService != null
          ? MoneyUtils.formatCurrency(editService.cost)
          : '',
    );
    RepairPartner? selectedPartner =
        editService != null && editService.partnerId != null
        ? _partners.firstWhere(
            (p) => p.id == editService.partnerId,
            orElse: () => _partners.first,
          )
        : null;
    if (editService != null &&
        selectedPartner == _partners.firstOrNull &&
        editService.partnerId == null) {
      selectedPartner = null;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(editService != null ? "Sửa dịch vụ" : "Thêm dịch vụ"),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: serviceCtrl,
                  decoration: const InputDecoration(labelText: "Tên dịch vụ *"),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) => (v ?? '').trim().isEmpty
                      ? 'Vui lòng nhập tên dịch vụ'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: costCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [MoneyUtils.currencyInputFormatter()],
                  decoration: const InputDecoration(labelText: "Chi phí (VNĐ)"),
                  validator: (v) => MoneyUtils.validateAmount(
                    v ?? '',
                    min: 1,
                    fieldName: 'Chi phí',
                  ),
                ),
                const SizedBox(height: 10),
                if (_partners.isNotEmpty)
                  DropdownButtonFormField<RepairPartner?>(
                    decoration: const InputDecoration(
                      labelText: "Đối tác (tùy chọn)",
                    ),
                    value: selectedPartner,
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text("Không có đối tác"),
                      ),
                      ..._partners.map(
                        (p) => DropdownMenuItem(value: p, child: Text(p.name)),
                      ),
                    ],
                    onChanged: (p) => setS(() => selectedPartner = p),
                  ),
              ],
            ),
          ),
          actions: [
            if (editService != null)
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _deleteService(editIndex!);
                },
                child: const Text("Xóa", style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Hủy"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final parsed = MoneyUtils.parseCurrency(costCtrl.text);
                final cost = parsed >= 1000 && parsed < 100000
                    ? parsed * 1000
                    : parsed;
                final service = RepairService(
                  serviceName: serviceCtrl.text.trim().toUpperCase(),
                  cost: cost,
                  partnerId: selectedPartner?.id,
                  partnerName: selectedPartner?.name,
                );
                Navigator.pop(ctx);
                await _saveService(service, editIndex);
              },
              child: Text(editService != null ? "Cập nhật" : "Thêm"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveService(RepairService service, int? editIndex) async {
    setState(() => _isUpdating = true);
    try {
      final newServices = List<RepairService>.from(r.services);
      if (editIndex != null) {
        newServices[editIndex] = service;
      } else {
        newServices.add(service);
      }
      r.services = newServices;
      r.cost = newServices.fold(0, (sum, s) => sum + s.cost);
      r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
      r.isSynced = false;
      await db.upsertRepair(r);

      // Handle partner history if service has partner
      if (service.partnerId != null && r.firestoreId != null) {
        final partnerService = RepairPartnerService();
        await partnerService.createPartnerHistoryForRepair(
          repairOrderId: r.firestoreId!,
          partnerId: service.partnerId!,
          partnerCost: service.cost,
          customerName: r.customerName,
          deviceModel: r.model,
          issue: service.serviceName,
          repairContent: service.serviceName,
        );
      }

      NotificationService.showSnackBar(
        editIndex != null ? "ĐÃ CẬP NHẬT DỊCH VỤ" : "ĐÃ THÊM DỊCH VỤ",
        color: AppColors.success,
      );
      EventBus().emit('repair_services_changed');
    } catch (e) {
      NotificationService.showSnackBar("Lỗi: $e", color: AppColors.error);
    }
    setState(() => _isUpdating = false);
  }

  Future<void> _deleteService(int index) async {
    setState(() => _isUpdating = true);
    try {
      final newServices = List<RepairService>.from(r.services);
      newServices.removeAt(index);
      r.services = newServices;
      r.cost = newServices.fold(0, (sum, s) => sum + s.cost);
      r.lastCaredAt = DateTime.now().millisecondsSinceEpoch;
      r.isSynced = false;
      await db.upsertRepair(r);
      NotificationService.showSnackBar(
        "ĐÃ XÓA DỊCH VỤ",
        color: AppColors.warning,
      );
      EventBus().emit('repair_services_changed');
    } catch (e) {
      NotificationService.showSnackBar("Lỗi: $e", color: AppColors.error);
    }
    setState(() => _isUpdating = false);
  }

  Widget _buildImageGallery() {
    final images = r.receiveImages;
    if (images.isEmpty) return const SizedBox();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "HÌNH ẢNH LÚC NHẬN MÁY",
          style: AppTextStyles.caption.copyWith(
            fontWeight: FontWeight.bold,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: images.length,
            itemBuilder: (ctx, i) => GestureDetector(
              onTap: () => _showFullImage(images, i),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                width: 120,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildSmartImage(images[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showFullImage(List<String> images, int initialIndex) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            PhotoViewGallery.builder(
              itemCount: images.length,
              builder: (context, index) {
                final path = images[index];
                return PhotoViewGalleryPageOptions(
                  imageProvider: path.startsWith('http')
                      ? NetworkImage(path) as ImageProvider
                      : FileImage(File(path)),
                  initialScale: PhotoViewComputedScale.contained,
                  minScale: PhotoViewComputedScale.contained,
                  maxScale: PhotoViewComputedScale.covered * 3,
                );
              },
              pageController: PageController(initialPage: initialIndex),
              scrollPhysics: const BouncingScrollPhysics(),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          _infoRow("Khách hàng", r.customerName),
          _phoneRow("Số điện thoại", r.phone),
          _infoRow("Tình trạng lỗi", r.issue),
          _infoRow(
            "Phụ kiện kèm",
            r.accessories.isEmpty ? "Không có" : r.accessories,
          ),
          _infoRow("Bảo hành", r.warranty.isEmpty ? "Chưa có" : r.warranty),
          if (r.notes != null && r.notes!.isNotEmpty)
            _infoRow("Ghi chú", r.notes!),
          if (r.deliveredAt != null)
            _infoRow(
              "Ngày giao",
              DateFormat(
                'dd/MM/yyyy HH:mm',
              ).format(DateTime.fromMillisecondsSinceEpoch(r.deliveredAt!)),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            v,
            style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
      ],
    ),
  );

  Widget _phoneRow(String label, String phone) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
          ),
        ),
        Row(
          children: [
            Text(
              phone,
              style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _callCustomer(phone),
              icon: const Icon(Icons.call, color: AppColors.success, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Gọi điện',
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _callCustomer(String phone) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final url = Uri.parse('tel:$cleanPhone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      NotificationService.showSnackBar(
        'Không thể gọi điện: $phone',
        color: Colors.red,
      );
    }
  }

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withAlpha(13), blurRadius: 10),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isUpdating ? null : _saveData,
                icon: _isUpdating
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: const Text(
                  "LƯU ĐƠN",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isPrinting ? null : _printReceipt,
                icon: _isPrinting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.print, color: Colors.white),
                label: const Text(
                  "IN PHIẾU",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2962FF),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _shareToZalo,
                icon: const Icon(Icons.send_rounded, color: Colors.white),
                label: const Text(
                  "ZALO",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareToZalo() async {
    final String content =
        "🌟 PHIẾU SỬA CHỮA/BẢO HÀNH 🌟\n----------------------------\nShop: $_shopName\nModel: ${r.model.toUpperCase()}\nKhách: ${r.customerName} - ${r.phone}\nLỗi: ${r.issue}\nBảo hành: ${r.warranty}\nTổng cộng: ${MoneyUtils.formatCurrency(r.price)} đ\n----------------------------\nCảm ơn quý khách đã tin tưởng!";
    await Share.share(content);
  }

  Future<void> _printReceipt() async {
    // Show printer selection dialog giống như in hóa đơn bán hàng
    final messenger = ScaffoldMessenger.of(context);
    final printerConfig = await showPrinterSelectionDialog(context);
    if (printerConfig == null) return; // User cancelled

    // Extract printer configuration
    final printerType = printerConfig['type'] as PrinterType?;
    final bluetoothPrinter =
        printerConfig['bluetoothPrinter'] as BluetoothPrinterConfig?;
    final wifiIp = printerConfig['wifiIp'] as String?;

    if (_isPrinting) return;
    setState(() => _isPrinting = true);
    HapticFeedback.mediumImpact();
    NotificationService.showSnackBar(
      "Đang chuẩn bị lệnh in...",
      color: Colors.blue,
    );

    try {
      final success = await UnifiedPrinterService.printRepairReceiptFromRepair(
        r,
        {'shopName': _shopName, 'shopAddr': _shopAddr, 'shopPhone': _shopPhone},
        printerType: printerType,
        bluetoothPrinter: bluetoothPrinter,
        wifiIp: wifiIp,
      );

      if (success) {
        NotificationService.showSnackBar(
          "Đã in phiếu thành công!",
          color: Colors.green,
        );
      } else {
        NotificationService.showSnackBar(
          "In thất bại! Vui lòng kiểm tra cài đặt máy in.",
          color: Colors.red,
        );
      }
    } catch (e) {
      NotificationService.showSnackBar("Lỗi khi in: $e", color: Colors.red);
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }
}

/// Dialog widget riêng biệt để chọn linh kiện - tách ra để quản lý state đúng cách
class _PartsSelectionDialog extends StatefulWidget {
  final List<Map<String, dynamic>> parts;

  const _PartsSelectionDialog({required this.parts});

  @override
  State<_PartsSelectionDialog> createState() => _PartsSelectionDialogState();
}

class _PartsSelectionDialogState extends State<_PartsSelectionDialog> {
  final Map<String, int> selectedQuantities = {};

  int get totalSelected => selectedQuantities.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.inventory_2, color: Colors.purple),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "CHỌN PHỤ TÙNG / LINH KIỆN",
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: ListView.builder(
          itemCount: widget.parts.length,
          itemBuilder: (context, index) {
            final part = widget.parts[index];
            final partId = part['id'] as int;
            final source = part['source'] as String;
            final uniqueKey = "${source}_$partId";
            final partName = part['partName'] ?? '';
            final partQty = part['quantity'] as int? ?? 0;
            final partCost = part['cost'] as int? ?? 0;
            final partPrice = part['price'] as int? ?? 0;
            final isFromProducts = source == 'products';
            final currentQty = selectedQuantities[uniqueKey] ?? 0;

            return Card(
              color: currentQty > 0
                  ? Colors.green.shade50
                  : (isFromProducts ? Colors.blue.shade50 : null),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Dòng 1: Icon + Tên + Tag nguồn
                    Row(
                      children: [
                        Icon(
                          isFromProducts ? Icons.inventory : Icons.build,
                          color: isFromProducts ? Colors.blue : Colors.purple,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            partName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isFromProducts
                                ? Colors.blue.withOpacity(0.2)
                                : Colors.purple.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isFromProducts ? "Kho tổng" : "Kho cũ",
                            style: TextStyle(
                              fontSize: 10,
                              color: isFromProducts
                                  ? Colors.blue
                                  : Colors.purple,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    // Dòng 2: Tồn + Giá
                    Text(
                      "Tồn: $partQty | Vốn: ${MoneyUtils.formatCurrency(partCost)} | Bán: ${MoneyUtils.formatCurrency(partPrice)}",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Dòng 3: Nút +/-
                    if (partQty > 0)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Nút trừ
                          Material(
                            color: currentQty > 0
                                ? Colors.red
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: currentQty > 0
                                  ? () {
                                      setState(() {
                                        if (currentQty <= 1) {
                                          selectedQuantities.remove(uniqueKey);
                                        } else {
                                          selectedQuantities[uniqueKey] =
                                              currentQty - 1;
                                        }
                                      });
                                    }
                                  : null,
                              child: Container(
                                width: 48,
                                height: 40,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.remove,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                          // Số lượng
                          Container(
                            width: 60,
                            alignment: Alignment.center,
                            child: Text(
                              '$currentQty',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: currentQty > 0
                                    ? Colors.green.shade700
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          // Nút cộng
                          Material(
                            color: currentQty < partQty
                                ? Colors.green
                                : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: currentQty < partQty
                                  ? () {
                                      setState(() {
                                        selectedQuantities[uniqueKey] =
                                            currentQty + 1;
                                      });
                                    }
                                  : null,
                              child: Container(
                                width: 48,
                                height: 40,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.add,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        alignment: Alignment.center,
                        child: const Text(
                          "HẾT HÀNG",
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text("HỦY"),
        ),
        ElevatedButton(
          onPressed: totalSelected > 0
              ? () => Navigator.pop(
                  context,
                  Map<String, int>.from(selectedQuantities),
                )
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.purple,
            disabledBackgroundColor: Colors.grey.shade300,
          ),
          child: Text(
            totalSelected > 0 ? "XÁC NHẬN ($totalSelected)" : "XÁC NHẬN",
            style: TextStyle(
              color: totalSelected > 0 ? Colors.white : Colors.grey,
            ),
          ),
        ),
      ],
    );
  }
}
