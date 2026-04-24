import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../data/db_helper.dart';
import '../models/salvage_phone_model.dart';
import '../models/expense_model.dart';
import '../services/firestore_service.dart';
import '../services/sync_orchestrator.dart';
import '../services/storage_service.dart';
import '../services/user_service.dart';
import '../utils/money_utils.dart';
import '../utils/vietnamese_utils.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/currency_text_field.dart';
import '../widgets/gradient_fab.dart';
import '../widgets/responsive_wrapper.dart';

class SalvagePhoneView extends StatefulWidget {
  const SalvagePhoneView({super.key});

  @override
  State<SalvagePhoneView> createState() => _SalvagePhoneViewState();
}

class _SalvagePhoneViewState extends State<SalvagePhoneView> {
  List<SalvagePhone> _all = [];
  List<SalvagePhone> _filtered = [];
  bool _loading = true;
  String _search = '';
  String _statusFilter = 'ALL';

  final _searchC = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      // Get fresh shopId to avoid cross-shop data contamination
      final freshShopId = await UserService.getCurrentShopId();
      final maps = await DBHelper().getAllSalvagePhones();
      final list = maps
          .map((m) => SalvagePhone.fromMap(m))
          .where((p) {
            if (freshShopId == null || freshShopId.isEmpty) return true;
            final pShop = p.shopId ?? '';
            return pShop.isEmpty || pShop == freshShopId;
          })
          .toList();
      if (mounted) {
        setState(() {
          _all = list;
          _applyFilter();
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Load salvage phones error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    var result = List<SalvagePhone>.from(_all);

    // Status filter
    if (_statusFilter != 'ALL') {
      result = result.where((p) => p.status == _statusFilter).toList();
    }

    // Search
    if (_search.isNotEmpty) {
      result = result.where((p) {
        return VietnameseUtils.containsVietnamese(p.deviceName, _search) ||
            VietnameseUtils.containsVietnamese(
              p.customerName ?? '',
              _search,
            ) ||
            (p.customerPhone ?? '').contains(_search) ||
            VietnameseUtils.containsVietnamese(p.notes ?? '', _search);
      }).toList();
    }

    _filtered = result;
  }

  // === STATS ===
  int get _totalCount => _all.length;
  int get _storedCount => _all.where((p) => p.status == 'STORED').length;
  int get _totalCost => _all.fold<int>(0, (s, p) => s + p.cost);

  // === BUILD ===
  @override
  Widget build(BuildContext context) {
    final fab = GradientFab.primary(
      onPressed: () => _showAddEditDialog(null),
      icon: Icons.add,
      label: 'Thêm máy',
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomAppBar.build(
        title: 'KHO MÁY XÁC',
        subtitle: '$_totalCount máy · $_storedCount đang lưu',
        accentColor: AppBarAccents.repairs,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: Column(
          children: [
            _buildStatsCard(),
            _buildSearchBar(),
            _buildStatusChips(),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? _buildEmpty()
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          itemCount: _filtered.length,
                          itemBuilder: (_, i) => _buildCard(_filtered[i]),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: fab,
    );
  }

  // === STATS CARD ===
  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _statItem('Tổng máy', '$_totalCount', Icons.phone_android),
          _statDivider(),
          _statItem('Đang lưu', '$_storedCount', Icons.inventory_2),
          _statDivider(),
          _statItem(
            'Tổng vốn',
            MoneyUtils.formatCurrency(_totalCost),
            Icons.payments,
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 36,
      color: Colors.white24,
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }

  // === SEARCH BAR ===
  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: TextField(
        controller: _searchC,
        decoration: InputDecoration(
          hintText: 'Tìm theo tên máy, khách hàng, SĐT, ghi chú...',
          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
          suffixIcon: _search.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: Colors.grey.shade400,
                    size: 18,
                  ),
                  onPressed: () {
                    _searchC.clear();
                    setState(() {
                      _search = '';
                      _applyFilter();
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.primary),
          ),
        ),
        onChanged: (v) {
          setState(() {
            _search = v.trim();
            _applyFilter();
          });
        },
      ),
    );
  }

  // === STATUS CHIPS ===
  Widget _buildStatusChips() {
    const filters = [
      ('ALL', 'Tất cả', Icons.apps, Colors.blue),
      ('STORED', 'Lưu kho', Icons.inventory_2, Colors.blue),
      ('USED', 'Đã dùng', Icons.build, Colors.orange),
      ('SOLD', 'Đã bán', Icons.sell, Colors.green),
      ('DISCARDED', 'Đã hủy', Icons.delete_outline, Colors.grey),
    ];
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: filters.map((f) {
          final selected = _statusFilter == f.$1;
          final count = f.$1 == 'ALL'
              ? _all.length
              : _all.where((p) => p.status == f.$1).length;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilterChip(
              selected: selected,
              label: Text(
                '${f.$2} ($count)',
                style: TextStyle(
                  fontSize: 12,
                  color: selected ? Colors.white : Colors.grey.shade700,
                ),
              ),
              avatar: Icon(
                f.$3,
                size: 14,
                color: selected ? Colors.white : f.$4,
              ),
              selectedColor: f.$4,
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: selected ? f.$4 : Colors.grey.shade300,
                ),
              ),
              showCheckmark: false,
              onSelected: (_) {
                setState(() {
                  _statusFilter = f.$1;
                  _applyFilter();
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // === EMPTY ===
  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.phone_android, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(
            _search.isNotEmpty
                ? 'Không tìm thấy máy xác phù hợp'
                : 'Chưa có máy xác nào',
            style: const TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          if (_search.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Nhấn + để thêm máy xác mới',
              style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  // === CARD ===
  Widget _buildCard(SalvagePhone p) {
    final statusColor = Color(SalvagePhone.statusColor(p.status));
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(p.createdAt),
    );

    return GestureDetector(
      onTap: () => _showDetail(p),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade100),
        ),
        child: Row(
          children: [
            // Status indicator
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            // Images preview or icon
            _buildThumb(p),
            const SizedBox(width: 10),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.deviceName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  if (p.customerName != null && p.customerName!.isNotEmpty)
                    Text(
                      '${p.customerName}${p.customerPhone != null && p.customerPhone!.isNotEmpty ? ' · ${p.customerPhone}' : ''}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right side: cost + status badge
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  MoneyUtils.formatCurrency(p.cost),
                  style: AppTextStyles.priceStyle,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    p.statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumb(SalvagePhone p) {
    final imgs = p.imageList;
    if (imgs.isEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.phone_android, color: Colors.grey.shade400, size: 22),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        imgs.first,
        width: 40,
        height: 40,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.broken_image,
            color: Colors.grey.shade400,
            size: 22,
          ),
        ),
      ),
    );
  }

  // === DETAIL BOTTOM SHEET ===
  void _showDetail(SalvagePhone p) {
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(
      DateTime.fromMillisecondsSinceEpoch(p.createdAt),
    );
    final statusColor = Color(SalvagePhone.statusColor(p.status));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          builder: (_, scrollC) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: ListView(
                controller: scrollC,
                padding: const EdgeInsets.all(16),
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Title row
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          p.deviceName,
                          style: AppTextStyles.headline3,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          p.statusLabel,
                          style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Cost
                  _detailRow(
                    Icons.payments,
                    'Giá mua',
                    MoneyUtils.formatCurrency(p.cost),
                    valueColor: AppColors.success,
                    bold: true,
                  ),
                  if (p.customerName != null && p.customerName!.isNotEmpty)
                    _detailRow(Icons.person, 'Khách bán', p.customerName!),
                  if (p.customerPhone != null && p.customerPhone!.isNotEmpty)
                    _detailRow(Icons.phone, 'SĐT', p.customerPhone!),
                  _detailRow(Icons.calendar_today, 'Ngày nhập', dateStr),
                  if (p.createdBy != null && p.createdBy!.isNotEmpty)
                    _detailRow(
                      Icons.person_outline,
                      'Người nhập',
                      p.createdBy!,
                    ),
                  if (p.notes != null && p.notes!.isNotEmpty)
                    _detailRow(Icons.notes, 'Ghi chú', p.notes!),

                  // Images
                  if (p.imageList.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Hình ảnh (${p.imageList.length})',
                      style: AppTextStyles.subtitle1,
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 120,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: p.imageList.length,
                        itemBuilder: (_, i) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => _viewImage(p.imageList[i]),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  p.imageList[i],
                                  width: 120,
                                  height: 120,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 120,
                                    height: 120,
                                    color: Colors.grey.shade200,
                                    child: const Icon(Icons.broken_image),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 8),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _showAddEditDialog(p);
                          },
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('Sửa'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _showChangeStatus(p);
                          },
                          icon: const Icon(Icons.swap_horiz, size: 16),
                          label: const Text('Đổi TT'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orange,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            _confirmDelete(p);
                          },
                          icon: const Icon(Icons.delete, size: 16),
                          label: const Text('Xóa'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    bool bold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: valueColor ?? AppColors.onSurface,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _viewImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: InteractiveViewer(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
                  const Center(child: Icon(Icons.broken_image, size: 64)),
            ),
          ),
        ),
      ),
    );
  }

  // === ADD / EDIT DIALOG ===
  void _showAddEditDialog(SalvagePhone? existing) {
    final isEdit = existing != null;
    final nameC = TextEditingController(text: existing?.deviceName ?? '');
    final custNameC = TextEditingController(text: existing?.customerName ?? '');
    final custPhoneC = TextEditingController(
      text: existing?.customerPhone ?? '',
    );
    final costC = TextEditingController(
      text: existing != null && existing.cost > 0
          ? MoneyUtils.formatCurrency(existing.cost)
          : '',
    );
    final noteC = TextEditingController(text: existing?.notes ?? '');
    final List<XFile> newImages = [];
    List<String> existingImageUrls =
        existing != null ? List.from(existing.imageList) : [];
    bool saving = false;
    bool showImages = existing != null && existing.imageList.isNotEmpty;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              title: Text(
                isEdit ? 'SỬA MÁY XÁC' : 'THÊM MÁY XÁC',
                style: AppTextStyles.headline5,
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameC,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Tên thiết bị *',
                          hintText: 'VD: iPhone 8 Plus, Samsung A52...',
                          prefixIcon: Icon(Icons.phone_android),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      CurrencyTextField(
                        controller: costC,
                        label: 'Giá mua (VNĐ) *',
                        icon: Icons.payments,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: custNameC,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Tên khách bán',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: custPhoneC,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'SĐT khách',
                          prefixIcon: Icon(Icons.phone),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: noteC,
                        textCapitalization: TextCapitalization.characters,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Ghi chú',
                          hintText: 'VD: MÀN BỂ, MẤT VÂN TAY...',
                          prefixIcon: Icon(Icons.notes),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Image section
                      _buildImageSection(
                        existingImageUrls,
                        newImages,
                        setDlg,
                        showImages,
                        (v) => setDlg(() => showImages = v),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(ctx).pop(),
                  child: const Text('HỦY'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          // Validate
                          final name = nameC.text.trim().toUpperCase();
                          if (name.isEmpty) {
                            _showSnack('Vui lòng nhập tên thiết bị');
                            return;
                          }
                          CurrencyTextField.finalizeAll();
                          final cost = CurrencyTextField.getValue(costC);
                          if (cost <= 0) {
                            _showSnack('Vui lòng nhập giá mua hợp lệ');
                            return;
                          }

                          setDlg(() => saving = true);

                          try {
                            // Upload new images
                            final List<String> allUrls = [
                              ...existingImageUrls,
                            ];
                            if (newImages.isNotEmpty) {
                              _showSnack(
                                'Đang tải ảnh lên hệ thống, vui lòng không thoát ứng dụng.',
                                duration: const Duration(seconds: 7),
                              );
                            }
                            for (final img in newImages) {
                              final url =
                                  await StorageService.uploadXFileAndGetUrl(
                                    img,
                                    'salvage_phones',
                                  );
                              if (url != null && url.isNotEmpty) {
                                allUrls.add(url);
                              }
                            }

                            final now =
                                DateTime.now().millisecondsSinceEpoch;
                            final fbUser =
                                FirebaseAuth.instance.currentUser;
                            final user = fbUser?.displayName ??
                                fbUser?.email?.split('@').first ??
                                'Unknown';
                            final shopId =
                                UserService.getShopIdSync() ?? '';
                            final notes = noteC.text.trim().toUpperCase();

                            if (isEdit) {
                              // Update
                              final fId = existing.firestoreId ??
                                  'sp_${existing.createdAt}_${existing.deviceName.hashCode}';
                              final data = {
                                'firestoreId': fId,
                                'shopId': shopId,
                                'deviceName': name,
                                'customerName': custNameC.text.trim(),
                                'customerPhone': custPhoneC.text.trim(),
                                'cost': cost,
                                'notes': notes,
                                'images': allUrls.join(','),
                                'status': existing.status,
                                'createdAt': existing.createdAt,
                                'updatedAt': now,
                                'createdBy': existing.createdBy ?? user,
                                'isSynced': 0,
                                'deleted': 0,
                              };
                              await DBHelper().upsertSalvagePhone(data);
                              final saved = await DBHelper()
                                  .getSalvagePhoneByFirestoreId(fId);
                              final localId = saved?['id'] as int?;
                              if (localId != null) {
                                await SyncOrchestrator().enqueue(
                                  entityType: SyncEntityType.salvagePhone,
                                  entityId: localId,
                                  firestoreId: fId,
                                  operation: SyncOperation.update,
                                  data: data,
                                );
                                try {
                                  await SyncOrchestrator().syncAll();
                                } catch (_) {}
                              }
                            } else {
                              // Add new
                              final fId =
                                  'sp_${now}_${name.hashCode}';
                              final data = {
                                'firestoreId': fId,
                                'shopId': shopId,
                                'deviceName': name,
                                'customerName': custNameC.text.trim(),
                                'customerPhone': custPhoneC.text.trim(),
                                'cost': cost,
                                'notes': notes,
                                'images': allUrls.join(','),
                                'status': 'STORED',
                                'createdAt': now,
                                'updatedAt': now,
                                'createdBy': user,
                                'isSynced': 0,
                                'deleted': 0,
                              };
                              await DBHelper().upsertSalvagePhone(data);
                              final saved = await DBHelper()
                                  .getSalvagePhoneByFirestoreId(fId);
                              final localId = saved?['id'] as int?;
                              if (localId != null) {
                                await SyncOrchestrator().enqueue(
                                  entityType: SyncEntityType.salvagePhone,
                                  entityId: localId,
                                  firestoreId: fId,
                                  operation: SyncOperation.create,
                                  data: data,
                                );
                                try {
                                  await SyncOrchestrator().syncAll();
                                } catch (_) {}
                              }

                              // Auto-record expense (CHI) to sổ quỹ
                              await _recordExpense(
                                name,
                                cost,
                                now,
                                custNameC.text.trim(),
                              );
                            }

                            if (ctx.mounted) Navigator.of(ctx).pop();
                            _showSnack(
                              isEdit
                                  ? 'Đã cập nhật máy xác'
                                  : 'Đã thêm máy xác mới',
                            );
                            _load();
                          } catch (e) {
                            debugPrint('Save salvage phone error: $e');
                            setDlg(() => saving = false);
                            _showSnack('Lỗi: $e');
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(isEdit ? 'CẬP NHẬT' : 'THÊM'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildImageSection(
    List<String> existingUrls,
    List<XFile> newImages,
    StateSetter setDlg,
    bool showImages,
    void Function(bool) onToggle,
  ) {
    final totalImages = existingUrls.length + newImages.length;
    final canAdd = totalImages < 3;

    // Hidden by default — tap to expand
    if (!showImages && totalImages == 0) {
      return TextButton.icon(
        onPressed: () => onToggle(true),
        icon: Icon(Icons.add_a_photo, size: 16, color: Colors.grey.shade600),
        label: Text(
          'Thêm hình ảnh (tùy chọn)',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Hình ảnh ($totalImages/3)',
              style: AppTextStyles.body2,
            ),
            const Spacer(),
            if (canAdd && !kIsWeb)
              IconButton(
                onPressed: () async {
                  final f = await ImagePicker().pickImage(
                    source: ImageSource.camera,
                    imageQuality: 40,
                  );
                  if (f != null) setDlg(() => newImages.add(f));
                },
                icon: const Icon(Icons.camera_alt, size: 20),
                tooltip: 'Chụp ảnh',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
            if (canAdd)
              IconButton(
                onPressed: () async {
                  final f = await ImagePicker().pickImage(
                    source: ImageSource.gallery,
                    imageQuality: 40,
                  );
                  if (f != null) setDlg(() => newImages.add(f));
                },
                icon: const Icon(Icons.photo_library, size: 20),
                tooltip: 'Thư viện',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              ),
          ],
        ),
        if (existingUrls.isNotEmpty || newImages.isNotEmpty)
          SizedBox(
            height: 80,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Existing URLs
                ...existingUrls.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            entry.value,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 80,
                              height: 80,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image, size: 24),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () =>
                                setDlg(() => existingUrls.removeAt(entry.key)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                // New picked images
                ...newImages.asMap().entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primary),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.image,
                              color: Colors.grey,
                              size: 28,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () =>
                                setDlg(() => newImages.removeAt(entry.key)),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.white,
                              ),
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
      ],
    );
  }

  // === CHANGE STATUS ===
  void _showChangeStatus(SalvagePhone p) {
    const statuses = [
      ('STORED', 'Đang lưu kho', Icons.inventory_2, Colors.blue),
      ('USED', 'Đã dùng linh kiện', Icons.build, Colors.orange),
      ('SOLD', 'Đã bán', Icons.sell, Colors.green),
      ('DISCARDED', 'Đã hủy', Icons.delete_outline, Colors.grey),
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Đổi trạng thái', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: statuses.map((s) {
              final selected = p.status == s.$1;
              return ListTile(
                leading: Icon(s.$3, color: s.$4),
                title: Text(
                  s.$2,
                  style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: selected
                    ? Icon(Icons.check_circle, color: s.$4)
                    : null,
                onTap: selected
                    ? null
                    : () async {
                        Navigator.of(ctx).pop();
                        await _updateStatus(p, s.$1);
                      },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Future<void> _updateStatus(SalvagePhone p, String newStatus) async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final fId = p.firestoreId ??
          'sp_${p.createdAt}_${p.deviceName.hashCode}';
      final data = p.toMap();
      data['firestoreId'] = fId;
      data['status'] = newStatus;
      data['updatedAt'] = now;
      data['isSynced'] = 0;
      data.remove('id');

      await DBHelper().upsertSalvagePhone(data);
      final saved = await DBHelper().getSalvagePhoneByFirestoreId(fId);
      final localId = saved?['id'] as int?;
      if (localId != null) {
        await SyncOrchestrator().enqueue(
          entityType: SyncEntityType.salvagePhone,
          entityId: localId,
          firestoreId: fId,
          operation: SyncOperation.update,
          data: data,
        );
        try {
          await SyncOrchestrator().syncAll();
        } catch (_) {}
      }

      _showSnack('Đã đổi trạng thái → ${_statusLabel(newStatus)}');
      _load();
    } catch (e) {
      debugPrint('Update status error: $e');
      _showSnack('Lỗi: $e');
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'STORED':
        return 'Đang lưu kho';
      case 'USED':
        return 'Đã dùng linh kiện';
      case 'SOLD':
        return 'Đã bán';
      case 'DISCARDED':
        return 'Đã hủy';
      default:
        return s;
    }
  }

  // === DELETE ===
  void _confirmDelete(SalvagePhone p) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: Text('Bạn muốn xóa máy xác "${p.deviceName}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('HỦY'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  final fId = p.firestoreId ??
                      'sp_${p.createdAt}_${p.deviceName.hashCode}';
                  // Soft-delete: update local + cloud
                  final data = p.toMap();
                  data['firestoreId'] = fId;
                  data['deleted'] = 1;
                  data['updatedAt'] =
                      DateTime.now().millisecondsSinceEpoch;
                    data['isSynced'] = 0;
                  data.remove('id');
                  await DBHelper().upsertSalvagePhone(data);
                  final saved = await DBHelper().getSalvagePhoneByFirestoreId(fId);
                  final localId = saved?['id'] as int?;
                  if (localId != null) {
                    await SyncOrchestrator().enqueue(
                      entityType: SyncEntityType.salvagePhone,
                      entityId: localId,
                      firestoreId: fId,
                      operation: SyncOperation.delete,
                      data: data,
                    );
                    try {
                      await SyncOrchestrator().syncAll();
                    } catch (_) {}
                  }

                  _showSnack('Đã xóa "${p.deviceName}"');
                  _load();
                } catch (e) {
                  debugPrint('Delete salvage phone error: $e');
                  _showSnack('Lỗi: $e');
                }
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text(
                'XÓA',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  // === RECORD EXPENSE ===
  Future<void> _recordExpense(
    String deviceName,
    int cost,
    int now,
    String customerName,
  ) async {
    try {
      final title = 'Mua máy xác: $deviceName';
      final note = customerName.isNotEmpty
          ? 'Mua từ $customerName'
          : 'Mua máy xác';
      final fId = 'exp_salvage_${now}_${deviceName.hashCode}';

      final expData = {
        'firestoreId': fId,
        'title': title,
        'amount': cost,
        'category': 'MUA MÁY XÁC',
        'date': now,
        'note': note,
        'paymentMethod': 'TIỀN MẶT',
        'type': 'CHI',
      };

      // Save to local DB
      final localExpense = Expense(
        firestoreId: fId,
        title: title,
        amount: cost,
        category: 'MUA MÁY XÁC',
        date: now,
        note: note,
        paymentMethod: 'TIỀN MẶT',
        type: 'CHI',
        isSynced: true,
      );
      await DBHelper().upsertExpense(localExpense);

      // Save to Firestore
      await FirestoreService.addExpenseCloud(expData);
    } catch (e) {
      debugPrint('Record expense for salvage phone error: $e');
    }
  }

  // === UTILS ===
  void _showSnack(String msg, {Duration duration = const Duration(seconds: 2)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: duration),
    );
  }
}
