import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/responsive_wrapper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/user_service.dart';
import '../theme/app_text_styles.dart';
import '../services/sync_service.dart';
import '../services/claims_service.dart';
import '../data/db_helper.dart';
import 'home_view.dart';

/// Màn hình chọn shop cho Super Admin
/// Super admin phải chọn shop trước khi xem dữ liệu
class ShopSelectorView extends StatefulWidget {
  final void Function(Locale)? setLocale;

  const ShopSelectorView({super.key, this.setLocale});

  @override
  State<ShopSelectorView> createState() => _ShopSelectorViewState();
}

class _ShopSelectorViewState extends State<ShopSelectorView> {
  List<Map<String, dynamic>> _shops = [];
  bool _loading = true;
  bool _switching = false;
  bool _isSyncingClaims = false;
  String? _selectedShopId;
  String? _error;
  final _searchC = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchC.addListener(() {
      setState(() => _searchQuery = _searchC.text.trim().toLowerCase());
    });
    _loadShops();
  }

  @override
  void dispose() {
    _searchC.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredShops {
    if (_searchQuery.isEmpty) return _shops;
    return _shops.where((shop) {
      final name = (shop['name'] as String? ?? '').toLowerCase();
      final email = (shop['ownerEmail'] as String? ?? '').toLowerCase();
      final id = (shop['id'] as String? ?? '').toLowerCase();
      final biz = (shop['businessType'] as String? ?? '').toLowerCase();
      return name.contains(_searchQuery) ||
          email.contains(_searchQuery) ||
          id.contains(_searchQuery) ||
          biz.contains(_searchQuery);
    }).toList();
  }

  Future<void> _loadShops() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final shops = await UserService.getAllShops();
      if (mounted) {
        setState(() {
          _shops = shops;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading shops: $e');
      if (mounted) {
        setState(() {
          _error = 'Không thể tải danh sách shop: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectShop(String shopId, String shopName) async {
    setState(() {
      _switching = true;
      _selectedShopId = shopId;
    });

    try {
      // 1. Set shop cho super admin (local)
      UserService.setAdminSelectedShop(shopId);
      debugPrint('✅ Super admin đã chọn shop (local): $shopId ($shopName)');

      // 2. Update shopId trong Firestore user document để claims được sync đúng
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'shopId': shopId,
          'email': user.email,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint('✅ Đã update shopId trong Firestore user doc');
        
        // 2.1 Refresh claims để token có shopId mới
        try {
          await ClaimsService().refreshMyClaims();
          debugPrint('✅ Đã refresh claims');
          
          // 2.2 Force refresh token
          await user.getIdToken(true);
          debugPrint('✅ Đã refresh token');
        } catch (e) {
          debugPrint('⚠️ Lỗi refresh claims (có thể tiếp tục): $e');
        }
      }

      // 3. Xóa local data cũ + reset sync timestamps
      await DBHelper().clearAllData();
      await SyncService.resetSyncTimestamps();
      debugPrint('✅ Đã xóa local data cũ');

      // 4. Download data của shop mới
      await SyncService.downloadAllFromCloud(force: true);
      debugPrint('✅ Đã download data từ cloud');

      // 5. Khởi động real-time sync
      await SyncService.initRealTimeSync(() {
        if (mounted) setState(() {});
      });
      debugPrint('✅ Đã khởi động real-time sync');

      // 6. Chuyển sang HomeView
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => HomeView(
              role: 'admin',
              setLocale: widget.setLocale,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Lỗi khi chọn shop: $e');
      if (mounted) {
        setState(() {
          _switching = false;
          _selectedShopId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi khi chọn shop: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
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
        title: const Text('QUẢN LÝ SHOP', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 1)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              UserService.clearCache();
              FirebaseAuth.instance.signOut();
            },
            tooltip: 'Đăng xuất',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadShops,
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: ResponsiveCenter(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Đang tải danh sách shop...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade700)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadShops,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }

    if (_shops.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Không có shop nào', style: TextStyle(fontSize: AppTextStyles.headline2.fontSize, color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    final filtered = _filteredShops;
    final totalUsers = _shops.fold<int>(0, (sum, s) => sum + ((s['userCount'] as int?) ?? 0));

    return Column(
      children: [
        // Summary bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple.shade50, Colors.blue.shade50],
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.admin_panel_settings, size: 32, color: Colors.deepPurple.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Super Admin', style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                    Text('Chọn shop để quản lý dữ liệu', style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              _summaryChip(Icons.store, '${_shops.length}', 'Shop'),
              const SizedBox(width: 8),
              _summaryChip(Icons.people, '$totalUsers', 'User'),
            ],
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            controller: _searchC,
            decoration: InputDecoration(
              hintText: 'Tìm theo tên, email, loại hình...',
              prefixIcon: const Icon(Icons.search, size: 22),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 20), onPressed: () => _searchC.clear())
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
        ),

        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${filtered.length} kết quả', style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade500)),
            ),
          ),

        // Shop list
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('Không tìm thấy shop', style: TextStyle(color: Colors.grey.shade500)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _buildShopCard(filtered[index]),
                ),
        ),

        // Claims sync bar (collapsed)
        _buildClaimsSyncBar(),
      ],
    );
  }

  Widget _summaryChip(IconData icon, String value, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.deepPurple.shade600),
              const SizedBox(width: 4),
              Text(value, style: TextStyle(fontSize: AppTextStyles.headline4.fontSize, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
            ],
          ),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  IconData _businessIcon(String? type) {
    switch (type) {
      case 'electronics': return Icons.phone_android;
      case 'fashion': return Icons.checkroom;
      case 'food': return Icons.restaurant;
      case 'pharmacy': return Icons.local_pharmacy;
      case 'grocery': return Icons.shopping_basket;
      default: return Icons.store;
    }
  }

  String _businessLabel(String? type) {
    switch (type) {
      case 'electronics': return 'Điện tử';
      case 'fashion': return 'Thời trang';
      case 'food': return 'Ẩm thực';
      case 'pharmacy': return 'Dược phẩm';
      case 'grocery': return 'Tạp hoá';
      default: return type ?? 'Chung';
    }
  }

  Color _businessColor(String? type) {
    switch (type) {
      case 'electronics': return Colors.blue;
      case 'fashion': return Colors.pink;
      case 'food': return Colors.orange;
      case 'pharmacy': return Colors.green;
      case 'grocery': return Colors.teal;
      default: return Colors.deepPurple;
    }
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '—';
    if (ts is Timestamp) {
      return DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate());
    }
    return '—';
  }

  Widget _buildShopCard(Map<String, dynamic> shop) {
    final shopId = shop['id'] as String;
    final shopName = shop['name'] as String? ?? 'Shop không tên';
    final ownerEmail = shop['ownerEmail'] as String? ?? '';
    final ownerUid = shop['ownerUid'] as String? ?? '';
    final businessType = shop['businessType'] as String?;
    final userCount = (shop['userCount'] as int?) ?? 0;
    final createdAt = shop['createdAt'];
    final isDeleted = shop['deleted'] == true;
    final isSelecting = _switching && _selectedShopId == shopId;
    final bColor = _businessColor(businessType);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isSelecting ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: isSelecting
            ? BorderSide(color: bColor, width: 2)
            : isDeleted
                ? BorderSide(color: Colors.red.shade200)
                : BorderSide.none,
      ),
      child: InkWell(
        onTap: _switching ? null : () => _selectShop(shopId, shopName),
        borderRadius: BorderRadius.circular(14),
        child: Opacity(
          opacity: isDeleted ? 0.5 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Icon + Name + Badge
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: bColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_businessIcon(businessType), size: 26, color: bColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shopName,
                            style: TextStyle(fontSize: AppTextStyles.headline3.fontSize, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: bColor.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                child: Text(_businessLabel(businessType), style: TextStyle(fontSize: 12, color: bColor, fontWeight: FontWeight.w600)),
                              ),
                              if (isDeleted) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                                  child: Text('Đã xoá', style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isSelecting)
                      const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                  ],
                ),

                const Divider(height: 20),

                // Row 2: Details grid
                Row(
                  children: [
                    _infoItem(Icons.email_outlined, ownerEmail.isNotEmpty ? ownerEmail : '—'),
                    const SizedBox(width: 16),
                    _infoItem(Icons.people_outline, '$userCount nhân viên'),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _infoItem(Icons.calendar_today_outlined, _formatTimestamp(createdAt)),
                    const SizedBox(width: 16),
                    _infoItem(Icons.tag, shopId.length > 12 ? '${shopId.substring(0, 12)}...' : shopId),
                  ],
                ),
                if (ownerUid.isNotEmpty && ownerUid != shopId) ...[
                  const SizedBox(height: 6),
                  _infoItem(Icons.person_outline, 'Owner UID: ${ownerUid.length > 16 ? '${ownerUid.substring(0, 16)}...' : ownerUid}'),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoItem(IconData icon, String text) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade500),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.grey.shade600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact claims sync bar at bottom
  Widget _buildClaimsSyncBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        border: Border(top: BorderSide(color: Colors.orange.shade200)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_sync, size: 20, color: Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Đồng bộ quyền truy cập cho tất cả tài khoản',
              style: TextStyle(fontSize: AppTextStyles.body1.fontSize, color: Colors.orange.shade800),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: _isSyncingClaims ? null : _syncAllClaims,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(fontSize: 13),
              ),
              child: _isSyncingClaims
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('SYNC CLAIMS'),
            ),
          ),
        ],
      ),
    );
  }

  /// Sync all claims for all users
  Future<void> _syncAllClaims() async {
    setState(() => _isSyncingClaims = true);

    try {
      final result = await ClaimsService().batchSyncAllClaims();

      if (!mounted) return;

      if (result['success'] == true) {
        // Safely cast stats map
        final statsRaw = result['stats'];
        final stats = statsRaw is Map ? Map<String, dynamic>.from(statsRaw) : <String, dynamic>{};
        final total = stats['total'] ?? 0;
        final success = stats['success'] ?? 0;
        final skipped = stats['skipped'] ?? 0;
        final failed = stats['failed'] ?? 0;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Đồng bộ hoàn tất!\n'
              'Tổng: $total | Thành công: $success | Bỏ qua: $skipped | Lỗi: $failed',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Lỗi: ${result['error'] ?? 'Không xác định'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Lỗi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncingClaims = false);
      }
    }
  }
}
