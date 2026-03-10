import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../models/payment_request_model.dart';
import '../models/customer_model.dart';
import '../services/payment_request_service.dart';
import '../services/user_service.dart';
import '../services/customer_service.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/currency_text_field.dart';

/// Danh sách ngân hàng Việt Nam phổ biến
const List<String> kVietnameseBanks = [
  'Vietcombank',
  'BIDV',
  'VietinBank',
  'Agribank',
  'Techcombank',
  'ACB',
  'MBBank',
  'TPBank',
  'VPBank',
  'Sacombank',
  'HDBank',
  'OCB',
  'SHB',
  'MSB',
  'LPBank',
  'SeABank',
  'VIB',
  'NamABank',
  'BacABank',
  'KienLongBank',
  'ABBank',
  'NCB',
  'PGBank',
  'VietABank',
  'BaoVietBank',
  'VietCapitalBank',
  'CBBank',
  'GPBank',
  'PublicBank',
  'UOB',
  'HSBC',
  'Shinhan',
  'Woori',
  'CIMB',
  'Khác',
];

/// Màn hình yêu cầu đóng tiền - giao diện giống chat
class PaymentRequestChatView extends StatefulWidget {
  const PaymentRequestChatView({super.key});

  @override
  State<PaymentRequestChatView> createState() => _PaymentRequestChatViewState();
}

class _PaymentRequestChatViewState extends State<PaymentRequestChatView> {
  final ScrollController _scrollCtrl = ScrollController();
  final _currencyFmt = NumberFormat('#,###', 'vi_VN');

  List<PaymentRequest> _requests = [];
  StreamSubscription? _subscription;
  bool _isLoading = true;

  // Filter
  PaymentRequestStatus? _statusFilter;

  // Current user info
  String? _currentUid;
  String _userRole = 'employee';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _currentUid = FirebaseAuth.instance.currentUser?.uid;
    final role = await UserService.getUserRole(_currentUid ?? '');
    if (mounted) {
      setState(() => _userRole = role ?? 'employee');
    }
    _subscribeToRequests();
  }

  void _subscribeToRequests() {
    _subscription?.cancel();
    _subscription = PaymentRequestService.requestsStream(
      statusFilter: _statusFilter,
    ).listen(
      (data) {
        if (mounted) {
          setState(() {
            _requests = data;
            _isLoading = false;
          });
        }
      },
      onError: (e) {
        debugPrint('❌ PaymentRequest stream error: $e');
        if (mounted) setState(() => _isLoading = false);
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollCtrl.dispose();
    super.dispose();
  }

  bool get _isOwnerOrAdmin =>
      _userRole == 'owner' || _userRole == 'admin' || _userRole == 'superadmin';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFECE5DD), // WhatsApp-like bg
      appBar: CustomAppBar.build(
        title: 'Yêu cầu đóng tiền',
        actions: [
          // Filter button
          PopupMenuButton<PaymentRequestStatus?>(
            icon: Badge(
              isLabelVisible: _statusFilter != null,
              backgroundColor: Colors.orange,
              child: const Icon(Icons.filter_list),
            ),
            onSelected: (val) {
              setState(() {
                _statusFilter = val;
                _isLoading = true;
              });
              _subscribeToRequests();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: null, child: Text('Tất cả')),
              const PopupMenuItem(value: PaymentRequestStatus.pending, child: Text('⏳ Chờ xử lý')),
              const PopupMenuItem(value: PaymentRequestStatus.processing, child: Text('🔄 Đang xử lý')),
              const PopupMenuItem(value: PaymentRequestStatus.completed, child: Text('✅ Đã thanh toán')),
              const PopupMenuItem(value: PaymentRequestStatus.rejected, child: Text('❌ Từ chối')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary bar
          _buildSummaryBar(),
          // Chat-like list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _requests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.payment, size: 64, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text(
                              _statusFilter != null
                                  ? 'Không có yêu cầu ${_statusFilter!.name}'
                                  : 'Chưa có yêu cầu đóng tiền',
                              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Nhấn + để tạo yêu cầu mới',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        itemCount: _requests.length,
                        itemBuilder: (ctx, i) => _buildRequestBubble(_requests[i]),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreateRequestSheet,
        backgroundColor: const Color(0xFF075E54), // WhatsApp green
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildSummaryBar() {
    final pending = _requests.where((r) => r.status == PaymentRequestStatus.pending).length;
    final processing = _requests.where((r) => r.status == PaymentRequestStatus.processing).length;
    final completed = _requests.where((r) => r.status == PaymentRequestStatus.completed).length;
    final totalAmount = _requests
        .where((r) => r.status == PaymentRequestStatus.pending || r.status == PaymentRequestStatus.processing)
        .fold<double>(0, (sum, r) => sum + r.amount);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          _statChip('⏳', '$pending', Colors.orange),
          const SizedBox(width: 8),
          _statChip('🔄', '$processing', Colors.blue),
          const SizedBox(width: 8),
          _statChip('✅', '$completed', Colors.green),
          const Spacer(),
          if (totalAmount > 0)
            Text(
              '${_currencyFmt.format(totalAmount)}đ',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red),
            ),
        ],
      ),
    );
  }

  Widget _statChip(String emoji, String count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$emoji $count',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  // ============== CHAT BUBBLE ==============

  Widget _buildRequestBubble(PaymentRequest req) {
    final isMe = req.senderId == _currentUid;
    final align = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = isMe ? const Color(0xFFDCF8C6) : Colors.white; // WhatsApp bubble colors

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: align,
        children: [
          // Sender name + time
          Padding(
            padding: EdgeInsets.only(left: isMe ? 60 : 4, right: isMe ? 4 : 60, bottom: 2),
            child: Text(
              '${req.senderName} · ${DateFormat('dd/MM HH:mm').format(req.createdAt)}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
          // Bubble
          Align(
            alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
            child: GestureDetector(
              onLongPress: () => _showActionSheet(req),
              child: Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                margin: EdgeInsets.only(left: isMe ? 48 : 0, right: isMe ? 0 : 48),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft: Radius.circular(isMe ? 12 : 0),
                    bottomRight: Radius.circular(isMe ? 0 : 12),
                  ),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 3, offset: const Offset(0, 1))],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status badge
                    _buildStatusBadge(req),
                    // Content
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Payment type + amount
                          Row(
                            children: [
                              Text(req.paymentTypeIcon, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  req.paymentTypeDisplay,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Text(
                                '${_currencyFmt.format(req.amount)}đ',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red),
                              ),
                            ],
                          ),
                          const Divider(height: 12),
                          // Customer info
                          _infoRow(Icons.person, req.customerName),
                          _infoRow(Icons.phone, req.customerPhone),
                          if (req.customerAddress != null && req.customerAddress!.isNotEmpty)
                            _infoRow(Icons.location_on, req.customerAddress!),
                          if (req.accountNumber != null && req.accountNumber!.isNotEmpty)
                            _infoRow(Icons.account_balance, '${req.bankName ?? ''} · ${req.accountNumber}'),
                          if (req.description != null && req.description!.isNotEmpty)
                            _infoRow(Icons.note, req.description!),
                          if (req.customerNote != null && req.customerNote!.isNotEmpty)
                            _infoRow(Icons.comment, req.customerNote!),
                          if (req.paymentMethod != null && req.status == PaymentRequestStatus.completed)
                            _infoRow(Icons.payments, req.paymentMethod == 'CHUYỂN KHOẢN' ? 'Chuyển khoản' : 'Tiền mặt'),
                        ],
                      ),
                    ),
                    // Images
                    if (req.imageUrls.isNotEmpty) _buildImageGrid(req.imageUrls),
                    // Reject reason
                    if (req.status == PaymentRequestStatus.rejected && req.rejectReason != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '❌ ${req.rejectReason}',
                          style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                        ),
                      ),
                    // Processed info
                    if (req.processedByName != null && req.processedAt != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                        child: Text(
                          '${req.statusDisplay} bởi ${req.processedByName} · ${DateFormat('dd/MM HH:mm').format(req.processedAt!)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                        ),
                      ),
                    // Action buttons for owner/admin on pending/processing requests
                    if (_isOwnerOrAdmin && (req.status == PaymentRequestStatus.pending || req.status == PaymentRequestStatus.processing))
                      _buildActionButtons(req),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(PaymentRequest req) {
    Color bgColor;
    Color textColor;
    switch (req.status) {
      case PaymentRequestStatus.pending:
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade800;
        break;
      case PaymentRequestStatus.processing:
        bgColor = Colors.blue.shade100;
        textColor = Colors.blue.shade800;
        break;
      case PaymentRequestStatus.completed:
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade800;
        break;
      case PaymentRequestStatus.rejected:
        bgColor = Colors.red.shade100;
        textColor = Colors.red.shade800;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      child: Text(
        req.statusDisplay,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid(List<String> urls) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: urls.map((url) {
          return GestureDetector(
            onTap: () => _showFullImage(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                url,
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
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionButtons(PaymentRequest req) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (req.status == PaymentRequestStatus.pending) ...[
            // Mark processing
            _actionBtn(
              icon: Icons.play_arrow,
              label: 'Xử lý',
              color: Colors.blue,
              onTap: () => _confirmStatus(req, PaymentRequestStatus.processing),
            ),
            const SizedBox(width: 6),
          ],
          // Complete
          _actionBtn(
            icon: Icons.check_circle,
            label: 'Đã TT',
            color: Colors.green,
            onTap: () => _confirmStatus(req, PaymentRequestStatus.completed),
          ),
          const SizedBox(width: 6),
          // Reject
          _actionBtn(
            icon: Icons.cancel,
            label: 'Từ chối',
            color: Colors.red,
            onTap: () => _showRejectDialog(req),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 3),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }

  // ============== ACTIONS ==============

  Future<void> _confirmStatus(PaymentRequest req, PaymentRequestStatus newStatus) async {
    if (newStatus == PaymentRequestStatus.completed) {
      // Show payment method selection dialog
      await _showCompleteDialog(req);
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bắt đầu xử lý?'),
          content: Text(
            '${req.paymentTypeDisplay} · ${_currencyFmt.format(req.amount)}đ\n'
            'Khách: ${req.customerName}',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('Xác nhận', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed == true && req.id != null) {
        await PaymentRequestService.updateStatus(req.id!, newStatus);
      }
    }
  }

  /// Dialog xác nhận hoàn thành với chọn phương thức thanh toán
  Future<void> _showCompleteDialog(PaymentRequest req) async {
    String selectedMethod = 'TIỀN MẶT';
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Xác nhận đã thanh toán'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${req.paymentTypeDisplay} · ${_currencyFmt.format(req.amount)}đ\n'
                'Khách: ${req.customerName}',
              ),
              const SizedBox(height: 16),
              const Text('Phương thức thanh toán:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Tiền mặt'),
                      avatar: const Icon(Icons.payments, size: 18),
                      selected: selectedMethod == 'TIỀN MẶT',
                      selectedColor: Colors.green.shade100,
                      onSelected: (_) => setDialogState(() => selectedMethod = 'TIỀN MẶT'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ChoiceChip(
                      label: const Text('Chuyển khoản'),
                      avatar: const Icon(Icons.account_balance, size: 18),
                      selected: selectedMethod == 'CHUYỂN KHOẢN',
                      selectedColor: Colors.blue.shade100,
                      onSelected: (_) => setDialogState(() => selectedMethod = 'CHUYỂN KHOẢN'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Khoản chi này sẽ được ghi vào sổ quỹ',
                        style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, selectedMethod),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Xác nhận đã thanh toán', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (result != null && req.id != null) {
      await PaymentRequestService.updateStatus(
        req.id!,
        PaymentRequestStatus.completed,
        paymentMethod: result,
      );
    }
  }

  Future<void> _showRejectDialog(PaymentRequest req) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Từ chối yêu cầu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${req.paymentTypeDisplay} · ${_currencyFmt.format(req.amount)}đ'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'Lý do từ chối',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Từ chối', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true && req.id != null) {
      await PaymentRequestService.updateStatus(
        req.id!,
        PaymentRequestStatus.rejected,
        rejectReason: reasonCtrl.text.trim().isNotEmpty ? reasonCtrl.text.trim() : null,
      );
    }
    reasonCtrl.dispose();
  }

  void _showActionSheet(PaymentRequest req) {
    if (req.id == null) return;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Chi tiết'),
              onTap: () {
                Navigator.pop(ctx);
                _showDetailSheet(req);
              },
            ),
            if (_isOwnerOrAdmin && req.status == PaymentRequestStatus.pending)
              ListTile(
                leading: const Icon(Icons.play_arrow, color: Colors.blue),
                title: const Text('Đánh dấu đang xử lý'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmStatus(req, PaymentRequestStatus.processing);
                },
              ),
            if (_isOwnerOrAdmin && (req.status == PaymentRequestStatus.pending || req.status == PaymentRequestStatus.processing))
              ListTile(
                leading: const Icon(Icons.check_circle, color: Colors.green),
                title: const Text('Đã thanh toán'),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmStatus(req, PaymentRequestStatus.completed);
                },
              ),
            if (req.senderId == _currentUid && req.status == PaymentRequestStatus.pending)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Xóa yêu cầu'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await PaymentRequestService.deleteRequest(req.id!);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showDetailSheet(PaymentRequest req) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(16),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(
                '${req.paymentTypeIcon} ${req.paymentTypeDisplay}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '${_currencyFmt.format(req.amount)}đ',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const Divider(height: 24),
              _detailTile('Trạng thái', req.statusDisplay),
              _detailTile('Khách hàng', req.customerName),
              _detailTile('Số điện thoại', req.customerPhone),
              if (req.customerAddress != null && req.customerAddress!.isNotEmpty)
                _detailTile('Địa chỉ', req.customerAddress!),
              if (req.accountNumber != null) _detailTile('Số TK / Hợp đồng', req.accountNumber!),
              if (req.bankName != null) _detailTile('Ngân hàng / Đơn vị', req.bankName!),
              if (req.description != null) _detailTile('Mô tả', req.description!),
              if (req.customerNote != null) _detailTile('Ghi chú', req.customerNote!),
              if (req.paymentMethod != null) _detailTile('Phương thức TT', req.paymentMethod == 'CHUYỂN KHOẢN' ? 'Chuyển khoản' : 'Tiền mặt'),
              _detailTile('Nhân viên gửi', req.senderName),
              _detailTile('Ngày tạo', DateFormat('dd/MM/yyyy HH:mm').format(req.createdAt)),
              if (req.processedByName != null) _detailTile('Người xử lý', req.processedByName!),
              if (req.processedAt != null) _detailTile('Ngày xử lý', DateFormat('dd/MM/yyyy HH:mm').format(req.processedAt!)),
              if (req.rejectReason != null) _detailTile('Lý do từ chối', req.rejectReason!),
              if (req.imageUrls.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Hình ảnh đính kèm:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: req.imageUrls.map((url) {
                    return GestureDetector(
                      onTap: () => _showFullImage(url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(url, width: 100, height: 100, fit: BoxFit.cover),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _showFullImage(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url),
            ),
          ),
        ),
      ),
    );
  }

  // ============== CREATE FORM ==============

  void _showCreateRequestSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreatePaymentRequestSheet(
        onCreated: () {
          // Scroll to top to see new request
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
          }
        },
      ),
    );
  }
}

// ============== CREATE SHEET (separate widget for cleaner state) ==============

class _CreatePaymentRequestSheet extends StatefulWidget {
  final VoidCallback? onCreated;

  const _CreatePaymentRequestSheet({this.onCreated});

  @override
  State<_CreatePaymentRequestSheet> createState() => _CreatePaymentRequestSheetState();
}

class _CreatePaymentRequestSheetState extends State<_CreatePaymentRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _accountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _otherTypeCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  PaymentType _selectedType = PaymentType.electricity;
  String? _selectedBank;
  List<File> _selectedImages = [];
  bool _isSending = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    _accountCtrl.dispose();
    _descCtrl.dispose();
    _noteCtrl.dispose();
    _otherTypeCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  /// Tìm kiếm và chọn khách hàng từ danh sách có sẵn
  void _showCustomerSearch() async {
    final result = await showDialog<Customer>(
      context: context,
      builder: (ctx) => _CustomerSearchDialog(),
    );
    if (result != null) {
      setState(() {
        _nameCtrl.text = result.name;
        _phoneCtrl.text = result.phone;
        if (result.address != null && result.address!.isNotEmpty) {
          _addressCtrl.text = result.address!;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.send, color: Color(0xFF075E54)),
                const SizedBox(width: 8),
                const Text('Gửi yêu cầu đóng tiền', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Payment type selector
                    const Text('Loại thanh toán', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: PaymentType.values.map((type) {
                        final isSelected = _selectedType == type;
                        return ChoiceChip(
                          label: Text(_getTypeLabel(type)),
                          selected: isSelected,
                          selectedColor: const Color(0xFF075E54).withOpacity(0.15),
                          onSelected: (_) => setState(() => _selectedType = type),
                          avatar: Text(_getTypeEmoji(type), style: const TextStyle(fontSize: 14)),
                        );
                      }).toList(),
                    ),
                    if (_selectedType == PaymentType.other) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _otherTypeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tên loại thanh toán',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Customer info
                    Row(
                      children: [
                        const Text('Thông tin khách hàng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: _showCustomerSearch,
                          icon: const Icon(Icons.search, size: 18),
                          label: const Text('Tìm KH'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Tên khách hàng *',
                        prefixIcon: Icon(Icons.person, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Nhập tên khách hàng' : null,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                        prefixIcon: Icon(Icons.phone, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _addressCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ',
                        prefixIcon: Icon(Icons.location_on, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Amount & account
                    const Text('Chi tiết thanh toán', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    CurrencyTextField(
                      controller: _amountCtrl,
                      label: 'Số tiền (đ)',
                      icon: Icons.attach_money,
                      required: true,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _accountCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Số TK / Mã hợp đồng',
                        prefixIcon: Icon(Icons.account_balance, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: _selectedBank,
                      decoration: const InputDecoration(
                        labelText: 'Ngân hàng / Đơn vị',
                        prefixIcon: Icon(Icons.business, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      isExpanded: true,
                      items: kVietnameseBanks.map((bank) => DropdownMenuItem(
                        value: bank,
                        child: Text(bank, style: const TextStyle(fontSize: 14)),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedBank = v),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Mô tả',
                        prefixIcon: Icon(Icons.description, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _noteCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ghi chú cho chủ shop',
                        prefixIcon: Icon(Icons.note, size: 20),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Image picker
                    const Text('Hình ảnh (hóa đơn, biên nhận...)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._selectedImages.asMap().entries.map((e) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.file(e.value, width: 80, height: 80, fit: BoxFit.cover),
                              ),
                              Positioned(
                                top: -4,
                                right: -4,
                                child: GestureDetector(
                                  onTap: () => setState(() => _selectedImages.removeAt(e.key)),
                                  child: Container(
                                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                    padding: const EdgeInsets.all(2),
                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                        // Add button
                        GestureDetector(
                          onTap: _pickImages,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.camera_alt, color: Colors.grey.shade500),
                                Text('Thêm ảnh', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 80), // Space for button
                  ],
                ),
              ),
            ),
          ),
          // Submit button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, -2))],
            ),
            child: ElevatedButton.icon(
              onPressed: _isSending ? null : _submitRequest,
              icon: _isSending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, color: Colors.white),
              label: Text(_isSending ? 'Đang gửi...' : 'GỬI YÊU CẦU', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF075E54),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    // Show choice: camera or gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Chụp ảnh'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Chọn từ thư viện'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    if (source == ImageSource.camera) {
      final photo = await picker.pickImage(source: ImageSource.camera, imageQuality: 75);
      if (photo != null) {
        setState(() => _selectedImages.add(File(photo.path)));
      }
    } else {
      final photos = await picker.pickMultiImage(imageQuality: 75);
      if (photos.isNotEmpty) {
        setState(() {
          for (final p in photos) {
            _selectedImages.add(File(p.path));
          }
        });
      }
    }
  }

  Future<void> _submitRequest() async {
    CurrencyTextField.finalizeAll();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    final amount = CurrencyTextField.getValue(_amountCtrl).toDouble();

    final result = await PaymentRequestService.createRequest(
      customerName: _nameCtrl.text.trim(),
      customerPhone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
      customerAddress: _addressCtrl.text.trim().isNotEmpty ? _addressCtrl.text.trim() : null,
      customerNote: _noteCtrl.text.trim().isNotEmpty ? _noteCtrl.text.trim() : null,
      paymentType: _selectedType,
      paymentTypeLabel: _selectedType == PaymentType.other ? _otherTypeCtrl.text.trim() : null,
      amount: amount,
      accountNumber: _accountCtrl.text.trim().isNotEmpty ? _accountCtrl.text.trim() : null,
      bankName: _selectedBank,
      description: _descCtrl.text.trim().isNotEmpty ? _descCtrl.text.trim() : null,
      images: _selectedImages.isNotEmpty ? _selectedImages : null,
    );

    if (!mounted) return;

    setState(() => _isSending = false);

    if (result != null) {
      Navigator.pop(context);
      widget.onCreated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Đã gửi yêu cầu đóng tiền'), backgroundColor: Colors.green),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Lỗi gửi yêu cầu'), backgroundColor: Colors.red),
      );
    }
  }

  String _getTypeLabel(PaymentType type) {
    switch (type) {
      case PaymentType.electricity: return 'Tiền điện';
      case PaymentType.water: return 'Tiền nước';
      case PaymentType.internet: return 'Tiền mạng';
      case PaymentType.bankLoan: return 'Vay NH';
      case PaymentType.bankInstallment: return 'Trả góp';
      case PaymentType.insurance: return 'Bảo hiểm';
      case PaymentType.other: return 'Khác';
    }
  }

  String _getTypeEmoji(PaymentType type) {
    switch (type) {
      case PaymentType.electricity: return '⚡';
      case PaymentType.water: return '💧';
      case PaymentType.internet: return '🌐';
      case PaymentType.bankLoan: return '🏦';
      case PaymentType.bankInstallment: return '💳';
      case PaymentType.insurance: return '🛡️';
      case PaymentType.other: return '📋';
    }
  }
}

// ============== CUSTOMER SEARCH DIALOG ==============

class _CustomerSearchDialog extends StatefulWidget {
  @override
  State<_CustomerSearchDialog> createState() => _CustomerSearchDialogState();
}

class _CustomerSearchDialogState extends State<_CustomerSearchDialog> {
  final _searchCtrl = TextEditingController();
  List<Customer> _allCustomers = [];
  List<Customer> _filtered = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    final customers = await CustomerService().getCustomers();
    if (!mounted) return;
    setState(() {
      _allCustomers = customers;
      _filtered = customers;
      _isLoading = false;
    });
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      if (q.isEmpty) {
        _filtered = _allCustomers;
      } else {
        _filtered = _allCustomers.where((c) {
          return c.name.toLowerCase().contains(q) ||
              c.phone.contains(q) ||
              (c.address?.toLowerCase().contains(q) ?? false);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: double.infinity,
        height: MediaQuery.of(context).size.height * 0.6,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.people, color: Color(0xFF075E54)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Chọn khách hàng', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Tìm theo tên, SĐT, địa chỉ...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              ),
              onChanged: _filter,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Center(child: Text('Không tìm thấy khách hàng', style: TextStyle(color: Colors.grey.shade600)))
                      : ListView.separated(
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final c = _filtered[i];
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFF075E54).withOpacity(0.1),
                                child: Text(
                                  c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Color(0xFF075E54), fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                [c.phone, if (c.address != null && c.address!.isNotEmpty) c.address!].join(' · '),
                                style: const TextStyle(fontSize: 12),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => Navigator.pop(context, c),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
