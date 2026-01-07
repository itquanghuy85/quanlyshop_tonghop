import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/repair_model.dart';
import '../services/unified_printer_service.dart';
import '../services/bluetooth_printer_service.dart';
import '../models/printer_types.dart';
import '../widgets/printer_selection_dialog.dart';
import '../services/notification_service.dart';
import '../services/firestore_service.dart';
import '../services/user_service.dart';
import '../data/db_helper.dart';
import '../widgets/validated_text_field.dart';
import '../widgets/currency_text_field.dart';
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

  @override
  void initState() {
    super.initState();
    r = widget.repair;
    _checkPermission();
    _loadShopInfo();
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
    final repairsBefore = await db.getAllRepairs();
    debugPrint('Repairs count before update: ${repairsBefore.length}');
    if (newStatus <= r.status) {
      NotificationService.showSnackBar(
        "Không thể quay lại trạng thái trước!",
        color: AppColors.error,
      );
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
        };
        await db.insertDebt(debtData);
        // Sync debt lên cloud
        await FirestoreService.addDebtCloud(debtData);
      }
    }

    if (newStatus == 3) r.finishedAt = DateTime.now().millisecondsSinceEpoch;

    setState(() {
      r.status = newStatus;
      _isUpdating = true;
    });
    try {
      debugPrint(
        'Updating repair status to $newStatus for repair ${r.firestoreId}',
      );
      await db.upsertRepair(r);
      await FirestoreService.upsertRepair(r);
      debugPrint('Repair status updated successfully');
      final repairsAfter = await db.getAllRepairs();
      debugPrint('Repairs count after update: ${repairsAfter.length}');
      NotificationService.showSnackBar(
        "ĐÃ CẬP NHẬT: ${_getStatusText(newStatus)}",
        color: AppColors.success,
      );
    } catch (e) {
      debugPrint('Error updating repair status: $e');
    }
    setState(() => _isUpdating = false);
  }

  String _getStatusText(int s) {
    if (s == 1) return "MÁY CHỜ";
    if (s == 2) return "ĐANG SỬA";
    if (s == 3) return "ĐÃ XONG";
    if (s == 4) return "ĐÃ GIAO";
    return "KHÁC";
  }

  Future<void> _saveData() async {
    setState(() => _isUpdating = true);
    HapticFeedback.mediumImpact();
    try {
      await db.upsertRepair(r);
      await FirestoreService.upsertRepair(r);

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
          await FirestoreService.addDebtCloud(linkedDebt);
        }
        // Removed create new debt logic to avoid duplicates
      }

      NotificationService.showSnackBar(
        "ĐÃ LƯU THAY ĐỔI ĐƠN HÀNG",
        color: AppColors.success,
      );
    } catch (e) {
      NotificationService.showSnackBar(
        "Lỗi khi lưu: $e",
        color: AppColors.error,
      );
    }
    if (mounted) setState(() => _isUpdating = false);
  }

  /// Dialog chọn phụ tùng từ kho và tự động trừ kho
  Future<void> _selectPartsFromInventory() async {
    final parts = await db.getAllParts();
    if (parts.isEmpty) {
      NotificationService.showSnackBar(
        "Kho phụ tùng trống. Vui lòng thêm phụ tùng trước.",
        color: Colors.orange,
      );
      return;
    }

    // Map để lưu số lượng chọn cho mỗi part
    final Map<int, int> selectedQuantities = {};

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.inventory_2, color: Colors.purple),
              const SizedBox(width: 10),
              const Text("CHỌN PHỤ TÙNG"),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: ListView.builder(
              itemCount: parts.length,
              itemBuilder: (context, index) {
                final part = parts[index];
                final partId = part['id'] as int;
                final partName = part['partName'] ?? '';
                final partQty = part['quantity'] as int? ?? 0;
                final partCost = part['cost'] as int? ?? 0;
                final partPrice = part['price'] as int? ?? 0;
                final selectedQty = selectedQuantities[partId] ?? 0;

                return Card(
                  child: ListTile(
                    title: Text(
                      partName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Tồn kho: $partQty"),
                        Text(
                          "Vốn: ${NumberFormat('#,###').format(partCost)} | Bán: ${NumberFormat('#,###').format(partPrice)}",
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                    trailing: partQty > 0
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline),
                                onPressed: selectedQty > 0
                                    ? () => setDialogState(() {
                                          selectedQuantities[partId] = selectedQty - 1;
                                          if (selectedQuantities[partId] == 0) {
                                            selectedQuantities.remove(partId);
                                          }
                                        })
                                    : null,
                              ),
                              Text(
                                '$selectedQty',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline),
                                onPressed: selectedQty < partQty
                                    ? () => setDialogState(() {
                                          selectedQuantities[partId] = selectedQty + 1;
                                        })
                                    : null,
                              ),
                            ],
                          )
                        : const Text(
                            "Hết hàng",
                            style: TextStyle(color: Colors.red),
                          ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text("HỦY"),
            ),
            ElevatedButton(
              onPressed: selectedQuantities.isNotEmpty
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
              ),
              child: const Text("XÁC NHẬN", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedQuantities.isNotEmpty) {
      int totalCost = 0;
      List<String> usedParts = [];

      for (var entry in selectedQuantities.entries) {
        final partId = entry.key;
        final qty = entry.value;
        final part = parts.firstWhere((p) => p['id'] == partId);
        final partName = part['partName'] ?? '';
        final partCost = part['cost'] as int? ?? 0;

        // Trừ kho
        final success = await db.deductPartQuantity(partId, qty);
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
    final priceC = TextEditingController(
      text: CurrencyTextField.formatDisplay(r.price),
    );
    final costC = TextEditingController(
      text: CurrencyTextField.formatDisplay(r.cost),
    );
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text("TÀI CHÍNH ĐƠN SỬA"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CurrencyTextField(
                controller: priceC,
                label: "Giá thu khách",
                icon: Icons.attach_money,
                onChanged: (_) => setDialogState(() {}),
              ),
              const SizedBox(height: 12),
              CurrencyTextField(
                controller: costC,
                label: "Giá vốn linh kiện",
                icon: Icons.inventory,
                onChanged: (_) => setDialogState(() {}),
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
        r.price = CurrencyTextField.parseValueWithMultiply(priceC.text);
        r.cost = CurrencyTextField.parseValueWithMultiply(costC.text);
      });
      // If cost increased, create expense for the additional cost
      if (r.cost > oldCost) {
        final additionalCost = r.cost - oldCost;
        final exp = {
          'title': 'Chi phí linh kiện bổ sung - ${r.model}',
          'amount': additionalCost,
          'category': 'REPAIR_PARTS',
          'date': DateTime.now().millisecondsSinceEpoch,
          'note': 'Chi phí linh kiện bổ sung cho đơn sửa ${r.firestoreId}',
          'paymentMethod': 'TIỀN MẶT', // Assume cash for now
          'createdAt': DateTime.now().millisecondsSinceEpoch,
        };
        await db.insertExpense(exp);
        await FirestoreService.addExpenseCloud(exp);
        EventBus().emit('expenses_changed');
      }
      _saveData();
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
    Color color = r.status == 4
        ? AppColors.primary
        : (r.status == 3 ? AppColors.success : AppColors.warning);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(
            r.status == 4
                ? Icons.verified
                : (r.status == 3 ? Icons.check_circle : Icons.pending_actions),
            color: color,
            size: 40,
          ),
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
    return Row(
      children: [
        if (r.status < 3)
          Expanded(
            child: ElevatedButton(
              onPressed: () => _updateStatus(3),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: AppColors.onSuccess,
              ),
              child: Text("ĐÃ XONG", style: AppTextStyles.button),
            ),
          ),
        if (r.status < 3) const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _updateStatus(4),
            style: AppButtonStyles.elevatedButtonStyle,
            child: Text("GIAO MÁY", style: AppTextStyles.button),
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
                "${NumberFormat('#,###').format(r.price - r.cost)} đ",
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton.icon(
                onPressed: _selectPartsFromInventory,
                icon: const Icon(Icons.inventory_2, size: 14, color: Colors.purple),
                label: Text(
                  "Chọn phụ tùng",
                  style: AppTextStyles.caption.copyWith(color: Colors.purple),
                ),
              ),
              TextButton.icon(
                onPressed: _editFinancials,
                icon: const Icon(Icons.edit, size: 14),
                label: Text(
                  "Sửa giá",
                  style: AppTextStyles.caption,
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
          NumberFormat('#,###').format(v),
          style: AppTextStyles.body2.copyWith(
            color: c,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

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
      children: [
        Text(
          l,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.onSurface.withOpacity(0.6),
          ),
        ),
        Text(
          v,
          style: AppTextStyles.body2.copyWith(fontWeight: FontWeight.bold),
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
        "🌟 PHIẾU SỬA CHỮA/BẢO HÀNH 🌟\n----------------------------\nShop: $_shopName\nModel: ${r.model.toUpperCase()}\nKhách: ${r.customerName} - ${r.phone}\nLỗi: ${r.issue}\nBảo hành: ${r.warranty}\nTổng cộng: ${NumberFormat('#,###').format(r.price)} đ\n----------------------------\nCảm ơn quý khách đã tin tưởng!";
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
