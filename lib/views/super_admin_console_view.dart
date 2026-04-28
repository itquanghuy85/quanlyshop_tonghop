import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/claims_service.dart';
import '../services/firestore_service.dart';
import '../services/super_admin_security_service.dart';
import '../services/user_service.dart';
import '../theme/app_text_styles.dart';
import '../widgets/responsive_wrapper.dart';
import '../l10n/app_localizations.dart';

enum _AdminSection {
  dashboard,
  shops,
  users,
  permissions,
  audit,
  settings,
  danger,
}

class SuperAdminConsoleView extends StatefulWidget {
  const SuperAdminConsoleView({super.key});

  @override
  State<SuperAdminConsoleView> createState() => _SuperAdminConsoleViewState();
}

class _SuperAdminConsoleViewState extends State<SuperAdminConsoleView> {
  final _db = FirebaseFirestore.instance;
  _AdminSection _section = _AdminSection.dashboard;

  Timer? _idleTimer;
  bool _checkingAccess = true;
  bool _hasAccess = false;

  String? _auditShopFilter;
  String _auditActionFilter = 'all';
  String _auditTextFilter = '';

  @override
  void initState() {
    super.initState();
    _bootstrapAccess();
    _startIdleGuard();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapAccess() async {
    try {
      final claims = await ClaimsService().getClaimsFromToken(forceRefresh: true);
      final ok = claims?['isSuperAdmin'] == true ||
          claims?['role'] == 'super_admin';
      UserService.setCurrentUserSuperAdmin(ok);
      if (ok) {
        SuperAdminSecurityService.touchActivity();
      }
      if (!mounted) return;
      setState(() {
        _hasAccess = ok;
        _checkingAccess = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasAccess = false;
        _checkingAccess = false;
      });
    }
  }

  void _startIdleGuard() {
    _idleTimer?.cancel();
    _idleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (!SuperAdminSecurityService.isSessionValid()) {
        SuperAdminSecurityService.lockSession();
      }
    });
  }

  Future<bool> _requirePinReauth({String title = 'Xác thực PIN'}) async {
    if (!mounted) return false;

    final pinC = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.lock, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text(title),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Nhập PIN Super Admin để tiếp tục thao tác nguy hiểm.'),
              const SizedBox(height: 12),
              TextField(
                controller: pinC,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 6,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'PIN (4-6 số)',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                final verified =
                    await SuperAdminSecurityService.verifyPin(pinC.text.trim());
                if (!verified) {
                  setDialogState(() => error = 'PIN không đúng');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Xác nhận'),
            ),
          ],
        ),
      ),
    );

    return ok == true;
  }

  Future<void> _enterShop(Map<String, dynamic> shop) async {
    final shopId = (shop['id'] ?? '').toString();
    final shopName = (shop['name'] ?? '').toString();
    if (shopId.isEmpty) return;

    UserService.setAdminSelectedShop(shopId);
    await SuperAdminSecurityService.logShopAccess(shopId, shopName);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã chọn shop $shopName để xem dữ liệu.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _toggleShopLock({
    required String shopId,
    required String flagName,
    required bool newValue,
    required String label,
  }) async {
    final requiresPin =
        flagName == 'appLocked' || flagName == 'adminFinanceLocked';
    if (requiresPin) {
      final ok = await _requirePinReauth(title: 'Xác thực để thay đổi $label');
      if (!ok) return;
    }

    await UserService.updateShopControlFlags(
      shopId: shopId,
      flagName: flagName,
      flagValue: newValue,
    );

    await SuperAdminSecurityService.logAction(
      action: 'toggle_$flagName',
      shopId: shopId,
      metadata: {'value': newValue, 'label': label},
      success: true,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newValue ? 'Đã khóa $label' : 'Đã mở khóa $label'),
        backgroundColor: newValue ? Colors.orange : Colors.green,
      ),
    );
  }

  Future<void> _resetShopData(Map<String, dynamic> shop) async {
    final shopId = (shop['id'] ?? '').toString();
    final shopName = (shop['name'] ?? '').toString();
    if (shopId.isEmpty) return;

    final nameC = TextEditingController();
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset dữ liệu shop'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Shop mục tiêu: $shopName'),
            const SizedBox(height: 8),
            const Text('Nhập đúng tên shop để xác nhận:'),
            const SizedBox(height: 8),
            TextField(
              controller: nameC,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Nhập tên shop',
              ),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (nameC.text.trim() != shopName.trim()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tên shop xác nhận không khớp.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final pinOk = await _requirePinReauth(title: 'Xác thực reset shop');
    if (!pinOk) return;

    final error = await FirestoreService.resetEntireShopData(
      shopIdOverride: shopId,
    );

    await SuperAdminSecurityService.logAction(
      action: 'reset_shop_data',
      shopId: shopId,
      metadata: {'shopName': shopName, 'error': error},
      success: error == null,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error == null
            ? 'Đã reset dữ liệu shop $shopName'
            : 'Reset thất bại: $error'),
        backgroundColor: error == null ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _softDeleteShop(Map<String, dynamic> shop) async {
    final shopId = (shop['id'] ?? '').toString();
    final shopName = (shop['name'] ?? '').toString();
    if (shopId.isEmpty) return;

    final pinOk = await _requirePinReauth(title: 'Xác thực xóa shop');
    if (!pinOk) return;

    await _db.collection('shops').doc(shopId).set({
      'deleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await SuperAdminSecurityService.logAction(
      action: 'soft_delete_shop',
      shopId: shopId,
      metadata: {'shopName': shopName},
      success: true,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã soft-delete shop $shopName'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  Future<void> _editUser(
    BuildContext context,
    String uid,
    Map<String, dynamic> data,
  ) async {
    final nameC = TextEditingController(text: (data['displayName'] ?? '').toString());
    final phoneC = TextEditingController(text: (data['phone'] ?? '').toString());
    final addressC = TextEditingController(text: (data['address'] ?? '').toString());
    final roleC = TextEditingController(text: (data['role'] ?? 'user').toString());
    final shopC = TextEditingController(text: (data['shopId'] ?? '').toString());

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sửa user'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Tên')),
              TextField(controller: phoneC, decoration: const InputDecoration(labelText: 'SĐT')),
              TextField(controller: addressC, decoration: const InputDecoration(labelText: 'Địa chỉ')),
              TextField(controller: roleC, decoration: const InputDecoration(labelText: 'Role')),
              TextField(controller: shopC, decoration: const InputDecoration(labelText: 'Shop ID')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (saved != true) return;

    await UserService.updateUserInfo(
      uid: uid,
      name: nameC.text,
      phone: phoneC.text,
      address: addressC.text,
      role: roleC.text,
      shopId: shopC.text.trim().isEmpty ? null : shopC.text.trim(),
      loc: AppLocalizations.of(context)!,
    );

    await SuperAdminSecurityService.logAction(
      action: 'edit_user_profile',
      targetUserId: uid,
      shopId: shopC.text.trim().isEmpty ? null : shopC.text.trim(),
      metadata: {'role': roleC.text.trim()},
      success: true,
    );
  }

  Future<void> _deleteUser(String uid, String email, {required bool withData}) async {
    final pinOk = await _requirePinReauth(title: 'Xác thực xóa user');
    if (!pinOk) return;

    if (withData) {
      await UserService.deleteUserWithData(uid);
    } else {
      await UserService.deleteUser(uid);
    }

    await SuperAdminSecurityService.logAction(
      action: withData ? 'delete_user_with_data_ui' : 'delete_user_doc_ui',
      targetUserId: uid,
      metadata: {'email': email},
      success: true,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(withData
            ? 'Đã xóa user + dữ liệu: $email'
            : 'Đã xóa user doc: $email'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccess) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_hasAccess) {
      return const Scaffold(
        body: Center(
          child: Text('Bạn không có quyền truy cập Super Admin Console.'),
        ),
      );
    }

    final isDesktop = MediaQuery.of(context).size.width >= 980;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: SuperAdminSecurityService.touchActivity,
      onPanDown: (_) => SuperAdminSecurityService.touchActivity(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF7FAFF),
        appBar: AppBar(
          title: Text(
            'SUPER ADMIN CONSOLE',
            style: TextStyle(fontSize: AppTextStyles.headline4.fontSize),
          ),
          actions: [
            IconButton(
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.refresh),
              tooltip: 'Tải lại',
            ),
          ],
        ),
        body: ResponsiveCenter(
          child: isDesktop
              ? Row(
                  children: [
                    _buildSidebar(),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildContent()),
                  ],
                )
              : _buildContent(),
        ),
        bottomNavigationBar: isDesktop
            ? null
            : BottomNavigationBar(
                type: BottomNavigationBarType.fixed,
                currentIndex: _mobileIndexFor(_section),
                onTap: (i) {
                  setState(() {
                    _section = _sectionFromMobileIndex(i);
                  });
                },
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.dashboard_outlined),
                    activeIcon: Icon(Icons.dashboard),
                    label: 'Dashboard',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.store_outlined),
                    activeIcon: Icon(Icons.store),
                    label: 'Shops',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.people_outline),
                    activeIcon: Icon(Icons.people),
                    label: 'Users',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long_outlined),
                    activeIcon: Icon(Icons.receipt_long),
                    label: 'Logs',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.more_horiz),
                    activeIcon: Icon(Icons.more_horiz),
                    label: 'More',
                  ),
                ],
              ),
      ),
    );
  }

  int _mobileIndexFor(_AdminSection section) {
    switch (section) {
      case _AdminSection.dashboard:
        return 0;
      case _AdminSection.shops:
        return 1;
      case _AdminSection.users:
        return 2;
      case _AdminSection.audit:
        return 3;
      case _AdminSection.permissions:
      case _AdminSection.settings:
      case _AdminSection.danger:
        return 4;
    }
  }

  _AdminSection _sectionFromMobileIndex(int i) {
    if (i == 4) {
      _showMoreSheet();
      return _section;
    }
    switch (i) {
      case 0:
        return _AdminSection.dashboard;
      case 1:
        return _AdminSection.shops;
      case 2:
        return _AdminSection.users;
      case 3:
        return _AdminSection.audit;
      default:
        return _AdminSection.dashboard;
    }
  }

  void _showMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.shield_outlined),
              title: const Text('Permissions'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _section = _AdminSection.permissions);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _section = _AdminSection.settings);
              },
            ),
            ListTile(
              leading: const Icon(Icons.warning_amber_rounded, color: Colors.red),
              title: const Text('Danger Zone'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _section = _AdminSection.danger);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return SizedBox(
      width: 230,
      child: ListView(
        children: [
          const SizedBox(height: 8),
          _navItem(Icons.dashboard, 'Dashboard', _AdminSection.dashboard),
          _navItem(Icons.store, 'Shops', _AdminSection.shops),
          _navItem(Icons.people, 'Users', _AdminSection.users),
          _navItem(Icons.shield, 'Permissions', _AdminSection.permissions),
          _navItem(Icons.receipt_long, 'Audit Logs', _AdminSection.audit),
          _navItem(Icons.settings, 'Settings', _AdminSection.settings),
          _navItem(Icons.warning_amber_rounded, 'Danger Zone', _AdminSection.danger, danger: true),
        ],
      ),
    );
  }

  Widget _navItem(IconData icon, String label, _AdminSection value, {bool danger = false}) {
    final selected = _section == value;
    return ListTile(
      leading: Icon(icon, color: danger ? Colors.red : null),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          color: danger ? Colors.red : null,
        ),
      ),
      selected: selected,
      onTap: () => setState(() => _section = value),
    );
  }

  Widget _buildContent() {
    switch (_section) {
      case _AdminSection.dashboard:
        return _DashboardSection(db: _db);
      case _AdminSection.shops:
        return _ShopsSection(
          db: _db,
          onEnterShop: _enterShop,
          onToggleLock: _toggleShopLock,
          onResetShop: _resetShopData,
        );
      case _AdminSection.users:
        return _UsersSection(onEdit: _editUser, onDelete: _deleteUser);
      case _AdminSection.permissions:
        return const _PermissionsSection();
      case _AdminSection.audit:
        return _AuditSection(
          db: _db,
          shopFilter: _auditShopFilter,
          actionFilter: _auditActionFilter,
          textFilter: _auditTextFilter,
          onFilterChanged: (shop, action, text) {
            setState(() {
              _auditShopFilter = shop;
              _auditActionFilter = action;
              _auditTextFilter = text;
            });
          },
        );
      case _AdminSection.settings:
        return const _SettingsSection();
      case _AdminSection.danger:
        return _DangerSection(db: _db, onResetShop: _resetShopData, onDeleteShop: _softDeleteShop);
    }
  }
}

class _DashboardSection extends StatelessWidget {
  const _DashboardSection({required this.db});

  final FirebaseFirestore db;

  Future<Map<String, int>> _loadStats() async {
    final shops = await db.collection('shops').where('deleted', isNotEqualTo: true).get();
    final users = await db.collection('users').get();
    final locked = await db.collection('shops').where('appLocked', isEqualTo: true).get();
    return {
      'shops': shops.size,
      'users': users.size,
      'locked': locked.size,
      'active': shops.size - locked.size,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, int>>(
      future: _loadStats(),
      builder: (context, snap) {
        final stats = snap.data ?? {'shops': 0, 'users': 0, 'locked': 0, 'active': 0};
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _statCard('Tổng shop', '${stats['shops']}', Icons.store, Colors.blue),
                _statCard('Shop active', '${stats['active']}', Icons.check_circle, Colors.green),
                _statCard('Tổng user', '${stats['users']}', Icons.people, Colors.indigo),
                _statCard('Shop bị khóa', '${stats['locked']}', Icons.lock, Colors.orange),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                title: const Text('Cảnh báo hệ thống'),
                subtitle: Text(stats['locked'] == 0
                    ? 'Không có shop đang khóa toàn bộ app.'
                    : 'Có ${stats['locked']} shop đang bị khóa app.'),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 8),
              Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShopsSection extends StatelessWidget {
  const _ShopsSection({
    required this.db,
    required this.onEnterShop,
    required this.onToggleLock,
    required this.onResetShop,
  });

  final FirebaseFirestore db;
  final Future<void> Function(Map<String, dynamic> shop) onEnterShop;
  final Future<void> Function({
    required String shopId,
    required String flagName,
    required bool newValue,
    required String label,
  }) onToggleLock;
  final Future<void> Function(Map<String, dynamic> shop) onResetShop;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('shops').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final shops = snap.data!.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          data['id'] = d.id;
          return data;
        }).toList();

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemBuilder: (_, i) {
            final s = shops[i];
            final appLocked = s['appLocked'] == true;
            final deleted = s['deleted'] == true;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            (s['name'] ?? 'Shop').toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        if (deleted)
                          const Chip(label: Text('DELETED')),
                        const SizedBox(width: 6),
                        Chip(
                          backgroundColor: appLocked ? Colors.red.shade50 : Colors.green.shade50,
                          label: Text(appLocked ? 'LOCKED' : 'ACTIVE'),
                        ),
                      ],
                    ),
                    Text('Owner: ${(s['ownerEmail'] ?? 'N/A')}'),
                    Text('Shop ID: ${(s['id'] ?? '')}'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => _showShopDetail(context, s),
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('View'),
                        ),
                        FilledButton.icon(
                          onPressed: () => onEnterShop(s),
                          icon: const Icon(Icons.login),
                          label: const Text('Enter Shop'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => onToggleLock(
                            shopId: (s['id'] ?? '').toString(),
                            flagName: 'appLocked',
                            newValue: !appLocked,
                            label: 'Toàn bộ app',
                          ),
                          icon: Icon(appLocked ? Icons.lock_open : Icons.lock),
                          label: Text(appLocked ? 'Unlock App' : 'Lock App'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => onResetShop(s),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemCount: shops.length,
        );
      },
    );
  }

  void _showShopDetail(BuildContext context, Map<String, dynamic> shop) {
    showDialog<void>(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 4,
        child: AlertDialog(
          title: Text('Shop: ${shop['name'] ?? ''}'),
          content: SizedBox(
            width: 760,
            height: 520,
            child: Column(
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Overview'),
                    Tab(text: 'Users'),
                    Tab(text: 'Locks'),
                    Tab(text: 'Activity'),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      ListView(
                        children: [
                          ListTile(title: const Text('Shop ID'), subtitle: Text((shop['id'] ?? '').toString())),
                          ListTile(title: const Text('Owner'), subtitle: Text((shop['ownerEmail'] ?? 'N/A').toString())),
                          ListTile(title: const Text('Business Type'), subtitle: Text((shop['businessType'] ?? 'N/A').toString())),
                        ],
                      ),
                      _ShopUsersTab(shopId: (shop['id'] ?? '').toString()),
                      ListView(
                        children: [
                          SwitchListTile(value: shop['adminFinanceLocked'] == true, onChanged: null, title: const Text('Khóa tài chính quản lý')),
                          SwitchListTile(value: shop['staffInventoryLocked'] == true, onChanged: null, title: const Text('Khóa kho cho nhân viên')),
                          SwitchListTile(value: shop['staffSalesLocked'] == true, onChanged: null, title: const Text('Khóa bán hàng cho nhân viên')),
                          SwitchListTile(value: shop['staffDebtLocked'] == true, onChanged: null, title: const Text('Khóa công nợ cho nhân viên')),
                        ],
                      ),
                      _ShopActivityTab(shopId: (shop['id'] ?? '').toString()),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Đóng')),
          ],
        ),
      ),
    );
  }
}

class _ShopUsersTab extends StatelessWidget {
  const _ShopUsersTab({required this.shopId});
  final String shopId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('shopId', isEqualTo: shopId)
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.docs.isEmpty) return const Center(child: Text('Không có user trong shop'));
        return ListView(
          children: snap.data!.docs.map((d) {
            final u = d.data();
            return ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text((u['displayName'] ?? u['email'] ?? '').toString()),
              subtitle: Text('Role: ${(u['role'] ?? 'user')}'),
            );
          }).toList(),
        );
      },
    );
  }
}

class _ShopActivityTab extends StatelessWidget {
  const _ShopActivityTab({required this.shopId});
  final String shopId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('admin_audit_log')
          .where('shopId', isEqualTo: shopId)
          .orderBy('timestamp', descending: true)
          .limit(50)
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.docs.isEmpty) return const Center(child: Text('Chưa có activity'));
        return ListView(
          children: snap.data!.docs.map((d) {
            final a = d.data();
            return ListTile(
              title: Text((a['action'] ?? '').toString()),
              subtitle: Text((a['email'] ?? '').toString()),
              trailing: Text(_fmtTs(a['timestamp'])),
            );
          }).toList(),
        );
      },
    );
  }

  String _fmtTs(dynamic ts) {
    if (ts is! Timestamp) return '—';
    final dt = ts.toDate();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _UsersSection extends StatelessWidget {
  const _UsersSection({required this.onEdit, required this.onDelete});

  final Future<void> Function(BuildContext, String, Map<String, dynamic>) onEdit;
  final Future<void> Function(String uid, String email, {required bool withData}) onDelete;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: UserService.getAllUsersStream(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        if (snap.data!.docs.isEmpty) {
          return const Center(
            child: Text('Không có user để hiển thị (đảm bảo đã chọn shop nếu không phải Super Admin).'),
          );
        }

        final users = snap.data!.docs;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemBuilder: (_, i) {
            final d = users[i];
            final u = Map<String, dynamic>.from(d.data() as Map<String, dynamic>);
            final uid = d.id;
            final email = (u['email'] ?? '').toString();
            return Card(
              child: ListTile(
                title: Text((u['displayName'] ?? email).toString()),
                subtitle: Text('Role: ${u['role'] ?? 'user'} · Shop: ${u['shopId'] ?? 'N/A'}'),
                trailing: Wrap(
                  spacing: 6,
                  children: [
                    IconButton(
                      onPressed: () => onEdit(context, uid, u),
                      icon: const Icon(Icons.edit, color: Colors.orange),
                    ),
                    IconButton(
                      onPressed: () => onDelete(uid, email, withData: false),
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                    IconButton(
                      onPressed: () => onDelete(uid, email, withData: true),
                      icon: const Icon(Icons.delete_forever, color: Colors.red),
                    ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemCount: users.length,
        );
      },
    );
  }
}

class _PermissionsSection extends StatelessWidget {
  const _PermissionsSection();

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['owner', '✓', '✓', '✓', '✓'],
      ['manager', '✓', '✓', '✗', '✗'],
      ['staff', '✓', '✗', '✗', '✗'],
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Permission Panel'),
            subtitle: Text('Chuẩn role-based baseline cho owner/manager/staff. Các khóa cấp shop sẽ override tại runtime.'),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Role')),
                DataColumn(label: Text('Sửa đơn')),
                DataColumn(label: Text('Xem tài chính')),
                DataColumn(label: Text('Đổi lock flags')),
                DataColumn(label: Text('Danger actions')),
              ],
              rows: rows
                  .map(
                    (r) => DataRow(cells: [
                      DataCell(Text(r[0])),
                      DataCell(Text(r[1])),
                      DataCell(Text(r[2])),
                      DataCell(Text(r[3])),
                      DataCell(Text(r[4])),
                    ]),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditSection extends StatelessWidget {
  const _AuditSection({
    required this.db,
    required this.shopFilter,
    required this.actionFilter,
    required this.textFilter,
    required this.onFilterChanged,
  });

  final FirebaseFirestore db;
  final String? shopFilter;
  final String actionFilter;
  final String textFilter;
  final void Function(String? shop, String action, String text) onFilterChanged;

  @override
  Widget build(BuildContext context) {
    Query<Map<String, dynamic>> query =
        db.collection('admin_audit_log').orderBy('timestamp', descending: true).limit(200);

    if (shopFilter != null && shopFilter!.isNotEmpty) {
      query = query.where('shopId', isEqualTo: shopFilter);
    }

    if (actionFilter != 'all') {
      query = query.where('action', isEqualTo: actionFilter);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Filter shopId',
                    isDense: true,
                  ),
                  onChanged: (v) => onFilterChanged(v.trim().isEmpty ? null : v.trim(), actionFilter, textFilter),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Filter action',
                    isDense: true,
                  ),
                  onChanged: (v) => onFilterChanged(shopFilter, v.trim().isEmpty ? 'all' : v.trim(), textFilter),
                ),
              ),
              SizedBox(
                width: 260,
                child: TextField(
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Search email/user',
                    isDense: true,
                  ),
                  onChanged: (v) => onFilterChanged(shopFilter, actionFilter, v.trim()),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: query.snapshots(),
            builder: (_, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());

              final docs = snap.data!.docs.where((d) {
                if (textFilter.isEmpty) return true;
                final data = d.data();
                final email = (data['email'] ?? '').toString().toLowerCase();
                final target = (data['targetUserId'] ?? '').toString().toLowerCase();
                final q = textFilter.toLowerCase();
                return email.contains(q) || target.contains(q);
              }).toList();

              if (docs.isEmpty) return const Center(child: Text('Không có audit logs phù hợp.'));

              return ListView.separated(
                itemCount: docs.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final a = docs[i].data();
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.receipt_long, size: 18),
                    title: Text((a['action'] ?? '').toString()),
                    subtitle: Text('User: ${(a['email'] ?? '')} · Shop: ${(a['shopId'] ?? '-') }'),
                    trailing: Text(_fmtTs(a['timestamp'])),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  String _fmtTs(dynamic ts) {
    if (ts is! Timestamp) return '—';
    final dt = ts.toDate();
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.pin),
            title: const Text('PIN & Session Security'),
            subtitle: const Text('Quản lý PIN ở màn Cài đặt chính. Console này tự động touch activity và khóa khi idle timeout.'),
            trailing: TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vào Cài đặt -> Bảo mật Super Admin để đổi PIN.')),
                );
              },
              child: const Text('Mở hướng dẫn'),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: const Text('Sync custom claims'),
            subtitle: const Text('Đồng bộ claims cho toàn bộ user khi thay đổi rules/roles.'),
            onTap: () async {
              final result = await ClaimsService().batchSyncAllClaims();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(result['success'] == true
                    ? 'Sync claims thành công.'
                    : 'Sync claims lỗi: ${result['error'] ?? 'unknown'}')),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DangerSection extends StatelessWidget {
  const _DangerSection({
    required this.db,
    required this.onResetShop,
    required this.onDeleteShop,
  });

  final FirebaseFirestore db;
  final Future<void> Function(Map<String, dynamic> shop) onResetShop;
  final Future<void> Function(Map<String, dynamic> shop) onDeleteShop;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('shops').orderBy('name').snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final shops = snap.data!.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          data['id'] = d.id;
          return data;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Card(
              color: Color(0xFFFFF3F3),
              child: ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: Colors.red),
                title: Text('Danger Zone'),
                subtitle: Text('Mọi thao tác tại đây đều yêu cầu xác thực PIN và được ghi audit log.'),
              ),
            ),
            const SizedBox(height: 12),
            ...shops.map((s) => Card(
                  child: ListTile(
                    title: Text((s['name'] ?? 'Shop').toString()),
                    subtitle: Text('ID: ${(s['id'] ?? '').toString()}'),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => onResetShop(s),
                          icon: const Icon(Icons.restart_alt),
                          label: const Text('Reset'),
                        ),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          onPressed: () => onDeleteShop(s),
                          icon: const Icon(Icons.delete_forever),
                          label: const Text('Delete Shop'),
                        ),
                      ],
                    ),
                  ),
                )),
          ],
        );
      },
    );
  }
}
