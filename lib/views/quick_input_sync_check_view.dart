import 'package:flutter/material.dart';
import '../data/db_helper.dart';
import '../models/quick_input_code_model.dart';
import '../services/sync_service.dart';
import '../services/notification_service.dart';

class QuickInputSyncCheckView extends StatefulWidget {
  const QuickInputSyncCheckView({super.key});

  @override
  State<QuickInputSyncCheckView> createState() => _QuickInputSyncCheckViewState();
}

class _QuickInputSyncCheckViewState extends State<QuickInputSyncCheckView> {
  List<QuickInputCode> _unsyncedCodes = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _checkSyncStatus();
  }

  Future<void> _checkSyncStatus() async {
    setState(() => _isLoading = true);
    try {
      final db = DBHelper();
      _unsyncedCodes = await db.getUnsyncedQuickInputCodes();
    } catch (e) {
      debugPrint('Lỗi kiểm tra đồng bộ: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _syncToCloud() async {
    if (_isSyncing) return;

    setState(() => _isSyncing = true);
    try {
      await SyncService.syncQuickInputCodesToCloud();
      await SyncService.downloadAllFromCloud(); // Download latest data
      NotificationService.showSnackBar('Đã đồng bộ thành công mã nhập nhanh!', color: Colors.green);
      await _checkSyncStatus(); // Refresh list
    } catch (e) {
      NotificationService.showSnackBar('Lỗi đồng bộ: $e', color: Colors.red);
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kiểm tra đồng bộ mã nhập nhanh'),
        actions: [
          if (_unsyncedCodes.isNotEmpty)
            IconButton(
              onPressed: _isSyncing ? null : _syncToCloud,
              icon: _isSyncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload, color: Colors.blue),
              tooltip: 'Đồng bộ lên Cloud',
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkSyncStatus,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _unsyncedCodes.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, color: Colors.green, size: 64),
                      SizedBox(height: 16),
                      Text(
                        'Tất cả mã nhập nhanh đã được đồng bộ!',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _unsyncedCodes.length,
                  itemBuilder: (context, index) {
                    final code = _unsyncedCodes[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(code.name),
                        subtitle: Text('Loại: ${code.type} • Tạo: ${DateTime.fromMillisecondsSinceEpoch(code.createdAt)}'),
                        leading: const Icon(Icons.sync_problem, color: Colors.orange),
                        trailing: const Text('Chưa đồng bộ', style: TextStyle(color: Colors.red)),
                      ),
                    );
                  },
                ),
    );
  }
}