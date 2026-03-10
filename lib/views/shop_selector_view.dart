import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/user_service.dart';
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
  String? _selectedShopId;
  String? _error;
  final _searchC = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchC.addListener(() {
      if (mounted) setState(() => _searchQuery = _searchC.text.trim().toLowerCase());
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
      if (mounted) setState(() { _loading = true; _error = null; });

      final shops = await UserService.getAllShops();
      debugPrint('ShopSelectorView: loaded ${shops.length} shops');
      if (mounted) {
        setState(() { _shops = shops; _loading = false; });
      }
    } catch (e) {
      debugPrint('ShopSelectorView error: $e');
      if (mounted) {
        setState(() { _error = '$e'; _loading = false; });
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
      body: SafeArea(child: _buildBody()),
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
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Colors.red.shade700)),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: _loadShops, icon: const Icon(Icons.refresh), label: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }

    if (_shops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.store_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('Không tìm thấy shop', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Text('Email: ${FirebaseAuth.instance.currentUser?.email ?? "N/A"}', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: _loadShops, icon: const Icon(Icons.refresh), label: const Text('Tải lại')),
            ],
          ),
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
            gradient: LinearGradient(colors: [Colors.deepPurple.shade50, Colors.blue.shade50]),
          ),
          child: Row(
            children: [
              Icon(Icons.admin_panel_settings, size: 28, color: Colors.deepPurple.shade700),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Super Admin · ${_shops.length} shop · $totalUsers user',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade700)),
              ),
            ],
          ),
        ),
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            controller: _searchC,
            decoration: InputDecoration(
              hintText: 'Tìm theo tên, email, loại hình...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _searchC.clear())
                  : null,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              filled: true,
              fillColor: Colors.white,
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
        // Shop list
        Expanded(
          child: filtered.isEmpty
              ? Center(child: Text('Không tìm thấy shop phù hợp', style: TextStyle(color: Colors.grey.shade500)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 80),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => _buildShopCard(filtered[index]),
                ),
        ),
      ],
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
    final businessType = shop['businessType'] as String?;
    final userCount = (shop['userCount'] as int?) ?? 0;
    final createdAt = shop['createdAt'];
    final isDeleted = shop['deleted'] == true;
    final isSelecting = _switching && _selectedShopId == shopId;
    final bColor = _businessColor(businessType);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: isSelecting ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelecting ? BorderSide(color: bColor, width: 2) : BorderSide.none,
      ),
      child: InkWell(
        onTap: _switching ? null : () => _selectShop(shopId, shopName),
        borderRadius: BorderRadius.circular(12),
        child: Opacity(
          opacity: isDeleted ? 0.5 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Icon + Name + Badge + Arrow
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: bColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(_businessIcon(businessType), size: 24, color: bColor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(shopName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 6,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: bColor.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                                child: Text(_businessLabel(businessType), style: TextStyle(fontSize: 11, color: bColor, fontWeight: FontWeight.w600)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
                                child: Text('$userCount NV', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                              ),
                              if (isDeleted)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                                  child: Text('Đã xoá', style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (isSelecting)
                      const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      Icon(Icons.chevron_right, size: 22, color: Colors.grey.shade400),
                  ],
                ),
                // Row 2: Details
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 54),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (ownerEmail.isNotEmpty)
                        _detailRow(Icons.email_outlined, ownerEmail),
                      _detailRow(Icons.calendar_today_outlined, 'Tạo: ${_formatTimestamp(createdAt)}'),
                      _detailRow(Icons.tag, 'ID: ${shopId.length > 20 ? '${shopId.substring(0, 20)}...' : shopId}'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade500),
          const SizedBox(width: 5),
          Flexible(
            child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

}
