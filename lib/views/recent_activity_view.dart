import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/utils/money_utils.dart';
import '../services/event_bus.dart';
import '../services/recent_activity_service.dart';

class RecentActivityView extends StatefulWidget {
  const RecentActivityView({super.key});

  @override
  State<RecentActivityView> createState() => _RecentActivityViewState();
}

class _RecentActivityViewState extends State<RecentActivityView> {
  RecentActivitySnapshot? _snapshot;
  bool _isLoading = false;
  String? _error;

  String _sourceFilter = RecentActivitySource.all;
  Duration _window = const Duration(hours: 24);

  StreamSubscription<String>? _eventSub;
  Timer? _reloadDebounce;

  @override
  void initState() {
    super.initState();
    _load();
    _eventSub = EventBus().stream.listen((event) {
      if (event == 'repairs_changed' ||
          event == 'sales_changed' ||
          event == 'expenses_changed' ||
          event == EventBus.shopChanged) {
        debugPrint(
          '📋 [RecentActivityView] Nhận event "$event" → debounce reload',
        );
        _reloadDebounce?.cancel();
        _reloadDebounce = Timer(const Duration(milliseconds: 400), () {
          if (mounted) _load();
        });
      }
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _reloadDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final data = await RecentActivityService.load(
        sourceFilter: _sourceFilter,
        window: _window,
      );
      final visibleItems = data.items
          .where((item) => item.source != RecentActivitySource.sync)
          .toList();
      final sanitized = RecentActivitySnapshot(
        generatedAt: data.generatedAt,
        items: visibleItems,
      );
      if (!mounted) return;
      setState(() {
        _snapshot = sanitized;
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
        title: const Text('HOẠT ĐỘNG GẦN ĐÂY'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Làm mới',
            onPressed: _isLoading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilters(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Row(
            children: [
              const Text('Nguồn:'),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _sourceFilter,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: RecentActivitySource.all,
                      child: Text('Tất cả'),
                    ),
                    DropdownMenuItem(
                      value: RecentActivitySource.financial,
                      child: Text('Tài chính'),
                    ),
                    DropdownMenuItem(
                      value: RecentActivitySource.audit,
                      child: Text('Nhật ký hệ thống'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _sourceFilter = v);
                    _load();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _windowChip('24h', const Duration(hours: 24)),
              const SizedBox(width: 8),
              _windowChip('3 ngày', const Duration(days: 3)),
              const SizedBox(width: 8),
              _windowChip('7 ngày', const Duration(days: 7)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _windowChip(String label, Duration duration) {
    final active = _window == duration;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      onSelected: (_) {
        setState(() => _window = duration);
        _load();
      },
    );
  }

  Widget _buildBody() {
    if (_isLoading && _snapshot == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _snapshot == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 42, color: Colors.red),
              const SizedBox(height: 8),
              Text(
                'Không tải được hoạt động gần đây\n$_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              FilledButton(onPressed: _load, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }

    final snapshot = _snapshot;
    if (snapshot == null) {
      return const SizedBox.shrink();
    }

    if (snapshot.items.isEmpty) {
      return const Center(
        child: Text('Không có hoạt động nào trong khoảng thời gian đã chọn'),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildSummary(snapshot),
          const SizedBox(height: 10),
          ...snapshot.items.map(_buildItemCard),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSummary(RecentActivitySnapshot snapshot) {
    final generatedAt = DateFormat(
      'dd/MM/yyyy HH:mm',
    ).format(snapshot.generatedAt);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        children: [
          _summaryTag('Tổng', snapshot.totalCount, Colors.blue),
          _summaryTag('Tài chính', snapshot.financialCount, Colors.green),
          _summaryTag('Hệ thống', snapshot.auditCount, Colors.indigo),
          Text(
            'Cập nhật: $generatedAt',
            style: TextStyle(color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _summaryTag(String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildItemCard(RecentActivityItem item) {
    final icon = _iconFor(item);
    final color = _colorFor(item);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.12),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Text(
              DateFormat(
                'dd/MM HH:mm',
              ).format(DateTime.fromMillisecondsSinceEpoch(item.timestamp)),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        trailing: item.amount != null
            ? Text(
                _amountLabel(item),
                style: TextStyle(
                  color: _amountColor(item),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              )
            : null,
      ),
    );
  }

  IconData _iconFor(RecentActivityItem item) {
    if (item.source == RecentActivitySource.sync) {
      if (item.status == 'failed') return Icons.sync_problem;
      if (item.status == 'retry') return Icons.sync;
      return Icons.cloud_done;
    }
    if (item.source == RecentActivitySource.audit) {
      return Icons.history;
    }
    if ((item.direction ?? '').toUpperCase() == 'IN') {
      return Icons.arrow_downward;
    }
    return Icons.arrow_upward;
  }

  Color _colorFor(RecentActivityItem item) {
    if (item.source == RecentActivitySource.sync) {
      if (item.status == 'failed') return Colors.red;
      if (item.status == 'retry') return Colors.orange;
      return Colors.green;
    }
    if (item.source == RecentActivitySource.audit) return Colors.indigo;
    if ((item.direction ?? '').toUpperCase() == 'IN') return Colors.green;
    return Colors.red;
  }

  String _amountLabel(RecentActivityItem item) {
    final value = item.amount ?? 0;
    final direction = (item.direction ?? '').toUpperCase();
    final sign = direction == 'IN' ? '+' : '-';
    return '$sign${MoneyUtils.formatCompact(value)}';
  }

  Color _amountColor(RecentActivityItem item) {
    final direction = (item.direction ?? '').toUpperCase();
    return direction == 'IN' ? Colors.green : Colors.red;
  }
}
