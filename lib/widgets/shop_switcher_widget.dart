import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/current_shop_service.dart';
import '../services/user_service.dart';
import '../services/shop_deletion_service.dart';
import '../models/shop_settings_model.dart';
import '../l10n/app_localizations.dart';

/// ShopSwitcherWidget: Dropdown để owner chọn shop đang quản lý
///
/// VISIBILITY RULES:
/// - Chỉ hiển thị khi: role == owner VÀ có >= 2 shops
/// - Super admin: luôn hiển thị (dùng getAllShops)
/// - Employee/technician: không bao giờ thấy
///
/// USAGE:
/// ```dart
/// ShopSwitcherWidget(
///   onShopChanged: () {
///     // Reload data for new shop
///     _loadData();
///   },
/// )
/// ```
class ShopSwitcherWidget extends StatefulWidget {
  final VoidCallback? onShopChanged;
  final bool showLabel;
  final bool compact;

  const ShopSwitcherWidget({
    super.key,
    this.onShopChanged,
    this.showLabel = true,
    this.compact = false,
  });

  @override
  State<ShopSwitcherWidget> createState() => _ShopSwitcherWidgetState();
}

class _ShopSwitcherWidgetState extends State<ShopSwitcherWidget> {
  final _shopService = CurrentShopService();

  List<Map<String, dynamic>> _shops = [];
  String? _currentShopId;
  bool _loading = true;
  bool _shouldShow = false;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    setState(() => _loading = true);

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        setState(() {
          _shouldShow = false;
          _loading = false;
        });
        return;
      }

      // Check role from multiple sources to ensure accuracy
      var role = await UserService.getRoleFast();

      // If role is 'user' (default/unknown), try getting from Firestore
      if (role == 'user' || role.isEmpty) {
        role = await UserService.getUserRole(uid);
      }

      // Also check if this user owns any shops directly from Firestore
      final ownedShopsQuery = await FirebaseFirestore.instance
          .collection('shops')
          .where('ownerUid', isEqualTo: uid)
          .limit(1)
          .get();
      final hasOwnedShops = ownedShopsQuery.docs.isNotEmpty;

      // Consider as owner if: role is owner/admin OR user owns any shops
      final isOwnerOrAdmin =
          role == 'owner' || role == 'admin' || hasOwnedShops;

      if (!isOwnerOrAdmin) {
        setState(() {
          _shouldShow = false;
          _loading = false;
        });
        return;
      }

      // Get owned shops
      final shops = await _shopService.getOwnedShops();
      final currentShopId = await _shopService.getActiveShopId();

      // Validate currentShopId exists in shops list to prevent DropdownButton assertion
      final validShopId = currentShopId != null &&
              shops.any((s) => s['id'] == currentShopId)
          ? currentShopId
          : (shops.isNotEmpty ? shops.first['id'] as String? : null);

      setState(() {
        _shops = shops;
        _currentShopId = validShopId;
        // Show for owner/admin to allow creating new branches
        // Show even if shops list is empty so owner can create their first branch
        _shouldShow = isOwnerOrAdmin;
        _loading = false;
      });

      // If we had to correct the shopId, persist the valid one
      if (validShopId != null && validShopId != currentShopId) {
        await _shopService.switchShop(validShopId);
      }
    } catch (e) {
      setState(() {
        _shouldShow = false;
        _loading = false;
      });
    }
  }

  Future<void> _onShopSelected(String? shopId) async {
    if (shopId == null || shopId == _currentShopId) return;

    setState(() => _loading = true);

    final success = await _shopService.switchShop(shopId);

    if (success) {
      setState(() {
        _currentShopId = shopId;
        _loading = false;
      });

      // Notify parent to reload data
      widget.onShopChanged?.call();

      // Show confirmation
      if (mounted) {
        final selectedShop = _shops.firstWhere(
          (s) => s['id'] == shopId,
          orElse: () => <String, dynamic>{},
        );
        final shopName = _shopDisplayLabel(selectedShop);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã chuyển sang: $shopName'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      setState(() => _loading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Không thể chuyển shop'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _shopDisplayLabel(Map<String, dynamic> shop) {
    final name = (shop['name'] ?? '').toString().trim();
    if (name.isEmpty) return 'Cửa hàng chưa đặt tên';
    return name;
  }

  @override
  Widget build(BuildContext context) {
    // Don't render anything if shouldn't show
    if (!_shouldShow && !_loading) {
      return const SizedBox.shrink();
    }

    if (_loading) {
      return widget.compact
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Padding(
              padding: EdgeInsets.all(8.0),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
    }

    final loc = AppLocalizations.of(context);

    if (widget.compact) {
      return _buildCompactDropdown(loc);
    }

    return _buildFullDropdown(loc);
  }

  Widget _buildCompactDropdown(AppLocalizations? loc) {
    return PopupMenuButton<String>(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.store, size: 20),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
      tooltip: loc?.switchShop ?? 'Switch shop',
      onSelected: _onShopSelected,
      itemBuilder: (context) => _shops.map((shop) {
        final isSelected = shop['id'] == _currentShopId;
        return PopupMenuItem<String>(
          value: shop['id'],
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 18,
                color: isSelected ? Theme.of(context).primaryColor : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _shopDisplayLabel(shop),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFullDropdown(AppLocalizations? loc) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showLabel)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.store, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Text(
                      loc?.switchShop ?? 'Chọn cửa hàng',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            // Only show dropdown if there are shops
            if (_shops.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                isExpanded: true,
                menuMaxHeight: 320,
                // Safety: ensure value exists in items to prevent assertion error
                value: _currentShopId != null &&
                        _shops.any((s) => s['id'] == _currentShopId)
                    ? _currentShopId
                    : null,
                selectedItemBuilder: (context) {
                  return _shops.map((shop) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        _shopDisplayLabel(shop),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList();
                },
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  prefixIcon: const Icon(Icons.storefront),
                ),
                items: _shops.map((shop) {
                  return DropdownMenuItem<String>(
                    value: shop['id'],
                    child: Text(
                      _shopDisplayLabel(shop),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _onShopSelected,
              ),
              const SizedBox(height: 12),
            ] else ...[
              // No shops yet - show info text
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bạn chưa có cửa hàng nào. Tạo chi nhánh đầu tiên!',
                        style: TextStyle(
                          color: Colors.orange.shade800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            // Button tạo chi nhánh mới
            OutlinedButton.icon(
              onPressed: _showCreateShopDialog,
              icon: const Icon(Icons.add_business, size: 18),
              label: Text(loc?.createNewBranch ?? 'Tạo chi nhánh mới'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.blue,
                side: const BorderSide(color: Colors.blue),
                minimumSize: const Size(double.infinity, 40),
              ),
            ),
            // Button xóa chi nhánh (chỉ hiện khi có >= 2 shops)
            if (_shops.length >= 2) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _showDeleteShopDialog,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Xóa chi nhánh'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateShopDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();
    final loc = AppLocalizations.of(context);
    String selectedBusinessType = 'electronics';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.add_business, color: Colors.blue),
              const SizedBox(width: 8),
              Expanded(child: Text(loc?.createNewBranch ?? 'Create New Branch')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: loc?.branchName ?? 'Branch Name',
                  hintText: 'Chi nhánh 2',
                  prefixIcon: const Icon(Icons.store),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: addressController,
                decoration: InputDecoration(
                  labelText: loc?.address ?? 'Address',
                  hintText: '123 Đường ABC',
                  prefixIcon: const Icon(Icons.location_on),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              // Business type dropdown
              DropdownButtonFormField<String>(
                value: selectedBusinessType,
                decoration: InputDecoration(
                  labelText: 'Ngành kinh doanh',
                  prefixIcon: const Icon(Icons.business_center),
                  border: const OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'electronics',
                    child: Text('📱 Điện thoại & Điện tử'),
                  ),
                  DropdownMenuItem(
                    value: 'fashion',
                    child: Text('👗 Thời trang & May mặc'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setDialogState(() => selectedBusinessType = value);
                  }
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text(loc?.cancel ?? 'Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, {
                'name': nameController.text.trim(),
                'address': addressController.text.trim(),
                'businessType': selectedBusinessType,
              }),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: Text(loc?.create ?? 'Create'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['name']?.isNotEmpty == true) {
      await _createNewShop(
        result['name'],
        result['address'] ?? '',
        result['businessType'] ?? 'electronics',
      );
    }
  }

  Future<void> _createNewShop(String name, String address, String businessType) async {
    setState(() => _loading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('Not logged in');

      // Step 1: Create shop document first (must exist before settings)
      final newShopRef = FirebaseFirestore.instance.collection('shops').doc();
      final shopId = newShopRef.id;
      
      await newShopRef.set({
        'name': name,
        'address': address,
        'ownerUid': currentUser.uid,
        'ownerEmail': currentUser.email,
        'createdAt': FieldValue.serverTimestamp(),
        'shopId': shopId,
        'businessType': businessType,
      });
      debugPrint('✅ Shop document created: $shopId');

      // Step 2: Create shop_settings (rules check isShopOwner which needs shop to exist)
      try {
        final settings = ShopSettings.fromBusinessType(businessType, shopId);
        final settingsRef = FirebaseFirestore.instance
            .collection('shops')
            .doc(shopId)
            .collection('settings')
            .doc('shop_settings');
        await settingsRef.set(settings.toFirestoreMap());
        debugPrint('✅ Shop settings created for $shopId');
      } catch (e) {
        // Settings creation failed but shop was created - non-critical
        // CategoryService will auto-create defaults from shop businessType
        debugPrint('⚠️ Settings creation failed (non-critical): $e');
      }

      // Invalidate cache and reload
      _shopService.invalidateCache();
      await _loadShops();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã tạo chi nhánh: $name'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Error creating branch: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi tạo chi nhánh: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => _loading = false);
  }

  Future<void> _showDeleteShopDialog() async {
    // Only allow deleting non-current shops
    final deletableShops = _shops
        .where((s) => s['id'] != _currentShopId)
        .toList();

    if (deletableShops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Không thể xóa shop đang hoạt động. Chuyển sang shop khác trước!',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String? selectedShopId;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.delete_forever, color: Colors.red),
              SizedBox(width: 8),
              Text('Xóa chi nhánh'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚠️ Cảnh báo: Xóa chi nhánh sẽ xóa TẤT CẢ dữ liệu liên quan (đơn sửa chữa, sản phẩm, công nợ...). Hành động này KHÔNG THỂ hoàn tác!',
                style: TextStyle(color: Colors.red, fontSize: 14),
              ),
              const SizedBox(height: 16),
              const Text('Chọn chi nhánh cần xóa:'),
              const SizedBox(height: 8),
              ...deletableShops.map(
                (shop) => RadioListTile<String>(
                  title: Text(shop['name'] ?? 'Unknown'),
                  subtitle: Text(
                    shop['address'] ?? '',
                    style: const TextStyle(fontSize: 14),
                  ),
                  value: shop['id'],
                  groupValue: selectedShopId,
                  onChanged: (value) {
                    setDialogState(() => selectedShopId = value);
                  },
                  dense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: selectedShopId == null
                  ? null
                  : () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Xóa vĩnh viễn'),
            ),
          ],
        ),
      ),
    );

    if (result == true && selectedShopId != null) {
      await _confirmDeleteShop(selectedShopId!);
    }
  }

  Future<void> _confirmDeleteShop(String shopId) async {
    final shopName = _shops.firstWhere(
      (s) => s['id'] == shopId,
      orElse: () => {'name': 'Unknown'},
    )['name'];

    // Require typing shop name to confirm
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Nhập tên chi nhánh "$shopName" để xác nhận xóa:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: shopName,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim() == shopName) {
                Navigator.pop(ctx, true);
              } else {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('Tên không khớp!'),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('XÓA', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteShop(shopId, shopName);
    }
  }

  Future<void> _deleteShop(String shopId, String shopName) async {
    setState(() => _loading = true);

    try {
      // Kiểm tra quyền xóa
      final canDelete = await ShopDeletionService.canDeleteShop(shopId);
      if (!canDelete) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Bạn không có quyền xóa chi nhánh này'),
              backgroundColor: Colors.red,
            ),
          );
        }
        if (mounted) setState(() => _loading = false);
        return;
      }

      // Tìm fallback shop
      String? fallbackShopId;
      for (final shop in _shops) {
        if (shop['id'] != shopId) {
          fallbackShopId = shop['id'];
          break;
        }
      }

      // Sử dụng ShopDeletionService để xóa an toàn
      final result = await ShopDeletionService.deleteShopSafe(
        shopId: shopId,
        shopName: shopName,
        fallbackShopId: fallbackShopId,
        onNavigateAway: () {
          // Nếu đang ở trong dialog, đóng tất cả dialogs
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          }
        },
      );

      if (result.success) {
        // Invalidate cache and reload
        _shopService.invalidateCache();
        await _loadShops();

        // Notify parent to reload data
        widget.onShopChanged?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Đã xóa chi nhánh: $shopName'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Lỗi xóa chi nhánh: ${result.errorMessage}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi xóa chi nhánh: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (mounted) setState(() => _loading = false);
  }
}

/// Compact shop indicator for AppBar (shows current shop name)
class CurrentShopIndicator extends StatefulWidget {
  const CurrentShopIndicator({super.key});

  @override
  State<CurrentShopIndicator> createState() => _CurrentShopIndicatorState();
}

class _CurrentShopIndicatorState extends State<CurrentShopIndicator> {
  String? _shopName;

  @override
  void initState() {
    super.initState();
    _loadShopName();
  }

  Future<void> _loadShopName() async {
    final shopInfo = await CurrentShopService().getActiveShopInfo();
    if (mounted && shopInfo != null) {
      setState(() {
        _shopName = shopInfo['name'] as String?;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shopName == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.store, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            _shopName!,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
