import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/user_service.dart';
import '../services/sync_service.dart';
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

  @override
  void initState() {
    super.initState();
    _loadShops();
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
      // 1. Set shop cho super admin
      UserService.setAdminSelectedShop(shopId);
      debugPrint('✅ Super admin đã chọn shop: $shopId ($shopName)');

      // 2. Xóa local data cũ
      await DBHelper().clearAllData();
      debugPrint('✅ Đã xóa local data cũ');

      // 3. Download data của shop mới
      await SyncService.downloadAllFromCloud();
      debugPrint('✅ Đã download data từ cloud');

      // 4. Khởi động real-time sync
      await SyncService.initRealTimeSync(() {
        if (mounted) setState(() {});
      });
      debugPrint('✅ Đã khởi động real-time sync');

      // 5. Chuyển sang HomeView
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
        title: const Text('Chọn Shop để Xem'),
        centerTitle: true,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadShops,
            tooltip: 'Tải lại',
          ),
        ],
      ),
      body: _buildBody(),
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
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade700),
            ),
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
            Text(
              'Không có shop nào',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Header info
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.deepPurple.shade50,
          child: Column(
            children: [
              Icon(
                Icons.admin_panel_settings,
                size: 48,
                color: Colors.deepPurple.shade700,
              ),
              const SizedBox(height: 8),
              Text(
                'Super Admin',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple.shade700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Chọn một shop để xem dữ liệu',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_shops.length} shop có sẵn',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),

        // Shop list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _shops.length,
            itemBuilder: (context, index) {
              final shop = _shops[index];
              final shopId = shop['id'] as String;
              final shopName = shop['name'] as String? ?? 'Shop không tên';
              final ownerEmail = shop['ownerEmail'] as String? ?? '';
              final isSelecting = _switching && _selectedShopId == shopId;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: InkWell(
                  onTap: _switching ? null : () => _selectShop(shopId, shopName),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Shop icon
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.store,
                            size: 28,
                            color: Colors.deepPurple.shade700,
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Shop info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                shopName,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (ownerEmail.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  ownerEmail,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                'ID: ${shopId.substring(0, 8)}...',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade400,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Arrow or loading
                        if (isSelecting)
                          const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                            color: Colors.grey.shade400,
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
