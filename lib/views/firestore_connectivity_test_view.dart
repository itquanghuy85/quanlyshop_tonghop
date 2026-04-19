import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/firestore_connectivity_service.dart';
import '../services/notification_service.dart';

class FirestoreConnectivityTestView extends StatefulWidget {
  const FirestoreConnectivityTestView({super.key});

  @override
  State<FirestoreConnectivityTestView> createState() =>
      _FirestoreConnectivityTestViewState();
}

class _FirestoreConnectivityTestViewState
    extends State<FirestoreConnectivityTestView> {
  FirestoreConnectivityReport? _report;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final report = await FirestoreConnectivityService.runDiagnostics();
      if (!mounted) return;
      setState(() {
        _report = report;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('TEST KẾT NỐI FIRESTORE'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _run,
            icon: const Icon(Icons.refresh),
            tooltip: 'Kiểm tra lại',
          ),
          IconButton(
            onPressed: _report == null ? null : _copyReport,
            icon: const Icon(Icons.copy_all),
            tooltip: 'Copy báo cáo',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _report == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _report == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 44, color: Colors.red),
              const SizedBox(height: 10),
              Text('Không thể chạy test Firestore\n$_error', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _run,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    final report = _report;
    if (report == null) {
      return const SizedBox.shrink();
    }

    return RefreshIndicator(
      onRefresh: _run,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSummaryCard(report),
          const SizedBox(height: 10),
          _buildChecksCard(report),
          if (report.warnings.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildBulletCard(
              title: 'Cảnh báo',
              icon: Icons.warning_amber_rounded,
              color: Colors.orange,
              items: report.warnings,
            ),
          ],
          if (report.errors.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildBulletCard(
              title: 'Lỗi phát hiện',
              icon: Icons.error_outline,
              color: Colors.red,
              items: report.errors,
            ),
          ],
          const SizedBox(height: 10),
          _buildBulletCard(
            title: 'Khuyến nghị xử lý',
            icon: Icons.tips_and_updates,
            color: Colors.blue,
            items: report.recommendations,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(FirestoreConnectivityReport report) {
    final healthy = report.isHealthy;
    final color = healthy ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        border: Border.all(color: color.withOpacity(0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(healthy ? Icons.check_circle : Icons.info_outline, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  healthy ? 'KẾT NỐI FIRESTORE ỔN ĐỊNH' : 'FIRESTORE CẦN KIỂM TRA',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Tổng quan: ${report.summary}'),
          const SizedBox(height: 4),
          Text('Độ trễ trung bình: ${report.latencyMs} ms'),
          const SizedBox(height: 4),
          Text(
            'Thời điểm test: ${DateFormat('dd/MM/yyyy HH:mm:ss').format(report.checkedAt.toLocal())}',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildChecksCard(FirestoreConnectivityReport report) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Checklist kết nối',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _checkRow('Có internet', report.hasNetwork),
            _checkRow('Đăng nhập Firebase Auth', report.hasAuthenticatedUser),
            _checkRow('Kết nối được Firestore server', report.canReachFirestoreServer),
            _checkRow('Đọc được users/{uid}', report.canReadCurrentUserDocument),
            _checkRow(
              report.hasShopContext
                  ? 'Đọc được dữ liệu theo shop'
                  : 'Có ngữ cảnh shop',
              report.hasShopContext ? report.canReadShopScopedData : true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _checkRow(String title, bool ok) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.cancel,
            color: ok ? Colors.green : Colors.red,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(title)),
        ],
      ),
    );
  }

  Widget _buildBulletCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<String> items,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $item'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyReport() async {
    final report = _report;
    if (report == null) return;

    final buffer = StringBuffer();
    buffer.writeln('=== FIRESTORE CONNECTIVITY REPORT ===');
    buffer.writeln('checkedAt: ${report.checkedAt.toIso8601String()}');
    buffer.writeln('summary: ${report.summary}');
    buffer.writeln('latencyMs: ${report.latencyMs}');
    buffer.writeln('hasNetwork: ${report.hasNetwork}');
    buffer.writeln('hasAuthenticatedUser: ${report.hasAuthenticatedUser}');
    buffer.writeln('hasShopContext: ${report.hasShopContext}');
    buffer.writeln('canReachFirestoreServer: ${report.canReachFirestoreServer}');
    buffer.writeln('canReadCurrentUserDocument: ${report.canReadCurrentUserDocument}');
    buffer.writeln('canReadShopScopedData: ${report.canReadShopScopedData}');
    if (report.warnings.isNotEmpty) {
      buffer.writeln('warnings:');
      for (final w in report.warnings) {
        buffer.writeln('- $w');
      }
    }
    if (report.errors.isNotEmpty) {
      buffer.writeln('errors:');
      for (final e in report.errors) {
        buffer.writeln('- $e');
      }
    }
    buffer.writeln('recommendations:');
    for (final tip in report.recommendations) {
      buffer.writeln('- $tip');
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));
    NotificationService.showSnackBar('Đã copy báo cáo kết nối Firestore', color: Colors.green);
  }
}
