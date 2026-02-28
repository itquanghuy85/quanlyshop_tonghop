import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/db_helper.dart';
import '../models/financial_activity_model.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/expense_model.dart';
import '../models/attendance_model.dart';
import '../models/product_model.dart';
import '../models/inventory_check_model.dart';
import 'money_utils.dart';

/// Utility class for exporting data to Excel (.xlsx) files.
/// Supports date-range filtering and Vietnamese column headers.
class ExcelExportHelper {
  static final _db = DBHelper();
  static final _dateFormat = DateFormat('dd/MM/yyyy');
  static final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  static final _monthFormat = DateFormat('MM/yyyy');

  // ──────────────────────────────────────────────
  //  PRIVATE HELPERS
  // ──────────────────────────────────────────────

  /// Create header row with bold style
  static CellStyle _headerStyle() {
    return CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('#4472C4'),
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      horizontalAlign: HorizontalAlign.Center,
    );
  }

  /// Write header row to sheet
  static void _writeHeaders(Sheet sheet, List<String> headers) {
    final style = _headerStyle();
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = style;
    }
  }

  /// Write a row of values to sheet
  static void _writeRow(Sheet sheet, int rowIndex, List<dynamic> values) {
    for (int i = 0; i < values.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex),
      );
      final v = values[i];
      if (v is int) {
        cell.value = IntCellValue(v);
      } else if (v is double) {
        cell.value = DoubleCellValue(v);
      } else {
        cell.value = TextCellValue(v?.toString() ?? '');
      }
    }
  }

  /// Format timestamp (ms) to date string or empty
  static String _fmtDate(dynamic ms) {
    if (ms == null || ms == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(
      ms is int ? ms : int.tryParse(ms.toString()) ?? 0,
    );
    return _dateFormat.format(dt);
  }

  /// Format timestamp (ms) to datetime string or empty
  static String _fmtDateTime(dynamic ms) {
    if (ms == null || ms == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(
      ms is int ? ms : int.tryParse(ms.toString()) ?? 0,
    );
    return _dateTimeFormat.format(dt);
  }

  /// Format money
  static String _fmtMoney(dynamic v) {
    if (v == null) return '0';
    final n = v is int ? v : int.tryParse(v.toString()) ?? 0;
    return MoneyUtils.formatVND(n);
  }

  /// Repair status int → Vietnamese text
  static String _repairStatus(int status) {
    switch (status) {
      case 1:
        return 'Đã nhận';
      case 2:
        return 'Đang sửa';
      case 3:
        return 'Đã sửa';
      case 4:
        return 'Đã giao';
      default:
        return 'Không rõ';
    }
  }

  /// Save Excel to Downloads folder & optionally share
  static Future<void> _saveAndShare(
    Excel excel,
    String fileName,
    BuildContext context,
  ) async {
    try {
      final bytes = excel.save();
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lỗi tạo file Excel')),
          );
        }
        return;
      }

      // 1. Lưu vào thư mục Downloads trước
      String? savedPath;
      try {
        Directory? downloadsDir;
        if (Platform.isAndroid) {
          downloadsDir = Directory('/storage/emulated/0/Download');
          if (!await downloadsDir.exists()) {
            downloadsDir = await getExternalStorageDirectory();
          }
        } else {
          downloadsDir = await getApplicationDocumentsDirectory();
        }
        if (downloadsDir != null) {
          savedPath = '${downloadsDir.path}/$fileName';
          final savedFile = File(savedPath);
          await savedFile.writeAsBytes(bytes);
          debugPrint('Excel saved to: $savedPath');
        }
      } catch (e) {
        debugPrint('Failed to save to Downloads: $e');
      }

      // 2. Cũng lưu vào temp để share
      final dir = await getTemporaryDirectory();
      final tempPath = '${dir.path}/$fileName';
      final tempFile = File(tempPath);
      await tempFile.writeAsBytes(bytes);

      if (!context.mounted) return;

      // 3. Hiện thông báo đã lưu + hỏi mở/chia sẻ
      final action = await showDialog<String>(
        context: context,
        builder: (ctx) {
          final fName = savedPath?.split('/').last ?? fileName;
          final folder = savedPath != null
              ? savedPath.substring(0, savedPath.lastIndexOf('/'))
              : null;
          return AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
            title: const Text('Xuất file thành công!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (savedPath != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.folder, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Đã lưu vào:\n$fName',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (folder != null)
                    Text(
                      'Thư mục: $folder',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                ] else
                  const Text('File đã được tạo sẵn để chia sẻ.'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'close'),
                child: const Text('Đóng'),
              ),
              if (savedPath != null)
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'open'),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Mở'),
                ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(ctx, 'share'),
                icon: const Icon(Icons.share, size: 18),
                label: const Text('Chia sẻ'),
              ),
            ],
          );
        },
      );

      if (action == 'open' && savedPath != null) {
        await OpenFilex.open(savedPath);
      } else if (action == 'share' && context.mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(tempPath)],
            title: fileName,
          ),
        );
      }
    } catch (e) {
      debugPrint('Excel export error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất file: $e')),
        );
      }
    }
  }

  /// Build filename with date range
  static String _buildFileName(String prefix, int? startMs, int? endMs) {
    if (startMs != null && endMs != null) {
      final s = DateFormat('ddMMyyyy').format(
        DateTime.fromMillisecondsSinceEpoch(startMs),
      );
      final e = DateFormat('ddMMyyyy').format(
        DateTime.fromMillisecondsSinceEpoch(endMs),
      );
      return '${prefix}_${s}_$e.xlsx';
    }
    final now = DateFormat('ddMMyyyy_HHmm').format(DateTime.now());
    return '${prefix}_$now.xlsx';
  }

  // ──────────────────────────────────────────────
  //  FILTER HELPER: filter a list by ms timestamp
  // ──────────────────────────────────────────────

  static List<T> _filterByDate<T>(
    List<T> items,
    int? startMs,
    int? endMs,
    int Function(T) getTimestamp,
  ) {
    if (startMs == null && endMs == null) return items;
    return items.where((item) {
      final ts = getTimestamp(item);
      if (startMs != null && ts < startMs) return false;
      if (endMs != null && ts > endMs) return false;
      return true;
    }).toList();
  }

  // ──────────────────────────────────────────────
  //  1. EXPORT REPAIRS (ĐƠN SỬA)
  // ──────────────────────────────────────────────

  static Future<void> exportRepairs(
    BuildContext context, {
    int? startMs,
    int? endMs,
  }) async {
    List<Repair> repairs;
    if (startMs != null && endMs != null) {
      repairs = await _db.getRepairsByCreatedAtRange(startMs, endMs);
    } else {
      repairs = await _db.getAllRepairs();
    }
    // Filter out deleted
    repairs = repairs.where((r) => !r.deleted).toList();

    final excel = Excel.createExcel();
    final sheet = excel['Đơn sửa'];

    _writeHeaders(sheet, [
      'STT',
      'Ngày nhận',
      'Khách hàng',
      'SĐT',
      'Model',
      'IMEI',
      'Màu',
      'Lỗi',
      'Phụ kiện kèm',
      'Trạng thái',
      'Giá',
      'Chi phí',
      'Lợi nhuận',
      'PT thanh toán',
      'Người nhận',
      'Người sửa',
      'Người giao',
      'Ngày sửa xong',
      'Ngày giao',
      'Bảo hành',
      'Ghi chú',
    ]);

    for (int i = 0; i < repairs.length; i++) {
      final r = repairs[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        _fmtDateTime(r.createdAt),
        r.customerName,
        r.phone,
        r.model,
        r.imei ?? '',
        r.color ?? '',
        r.issue,
        r.accessories,
        _repairStatus(r.status),
        _fmtMoney(r.price),
        _fmtMoney(r.cost),
        _fmtMoney(r.price - r.cost),
        r.paymentMethod,
        r.createdBy ?? '',
        r.repairedBy ?? '',
        r.deliveredBy ?? '',
        _fmtDateTime(r.finishedAt),
        _fmtDateTime(r.deliveredAt),
        r.warranty,
        r.notes ?? '',
      ]);
    }

    // Remove default Sheet1
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('don_sua', startMs, endMs);
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  2. EXPORT SALES (ĐƠN BÁN)
  // ──────────────────────────────────────────────

  static Future<void> exportSales(
    BuildContext context, {
    int? startMs,
    int? endMs,
  }) async {
    List<SaleOrder> sales;
    if (startMs != null && endMs != null) {
      sales = await _db.getSalesByDateRange(startMs, endMs);
    } else {
      sales = await _db.getAllSales();
    }

    final excel = Excel.createExcel();
    final sheet = excel['Đơn bán'];

    _writeHeaders(sheet, [
      'STT',
      'Ngày bán',
      'Khách hàng',
      'SĐT',
      'Sản phẩm',
      'IMEI',
      'Giá bán',
      'Giá vốn',
      'Lợi nhuận',
      'Giảm giá',
      'Thành tiền',
      'PT thanh toán',
      'Tiền mặt',
      'Chuyển khoản',
      'Trả góp',
      'Trả trước',
      'Còn nợ',
      'Ngân hàng',
      'Người bán',
      'Bảo hành',
      'Quà tặng',
      'Ghi chú',
    ]);

    for (int i = 0; i < sales.length; i++) {
      final s = sales[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        _fmtDateTime(s.soldAt),
        s.customerName,
        s.phone,
        s.productNames,
        s.productImeis,
        _fmtMoney(s.totalPrice),
        _fmtMoney(s.totalCost),
        _fmtMoney(s.totalPrice - s.totalCost - s.discount),
        _fmtMoney(s.discount),
        _fmtMoney(s.finalPrice),
        s.paymentMethod,
        _fmtMoney(s.cashAmount),
        _fmtMoney(s.transferAmount),
        s.isInstallment ? 'Có' : 'Không',
        _fmtMoney(s.downPayment),
        _fmtMoney(s.remainingDebt),
        s.bankName ?? '',
        s.sellerName,
        s.warranty,
        s.gifts ?? '',
        s.notes ?? '',
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('don_ban', startMs, endMs);
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  3. EXPORT EXPENSES (THU CHI)
  // ──────────────────────────────────────────────

  static Future<void> exportExpenses(
    BuildContext context, {
    int? startMs,
    int? endMs,
  }) async {
    List<Map<String, dynamic>> maps;
    if (startMs != null && endMs != null) {
      maps = await _db.getExpensesByDateRange(startMs, endMs);
    } else {
      maps = await _db.getAllExpenses();
    }

    final expenses = maps.map((m) => Expense.fromMap(m)).toList();

    final excel = Excel.createExcel();
    final sheet = excel['Thu chi'];

    _writeHeaders(sheet, [
      'STT',
      'Ngày',
      'Loại',
      'Tiêu đề',
      'Số tiền',
      'Danh mục',
      'PT thanh toán',
      'Ghi chú',
    ]);

    for (int i = 0; i < expenses.length; i++) {
      final e = expenses[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        _fmtDateTime(e.date),
        e.type == 'THU' ? 'Thu' : 'Chi',
        e.title,
        _fmtMoney(e.amount),
        e.category,
        e.paymentMethod,
        e.note ?? '',
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('thu_chi', startMs, endMs);
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  4. EXPORT ATTENDANCE (CHẤM CÔNG)
  // ──────────────────────────────────────────────

  static Future<void> exportAttendance(
    BuildContext context, {
    int? startMs,
    int? endMs,
  }) async {
    List<Attendance> list;
    if (startMs != null && endMs != null) {
      // Convert ms → dateKey format yyyy-MM-dd
      final startKey = DateFormat('yyyy-MM-dd').format(
        DateTime.fromMillisecondsSinceEpoch(startMs),
      );
      final endKey = DateFormat('yyyy-MM-dd').format(
        DateTime.fromMillisecondsSinceEpoch(endMs),
      );
      list = await _db.getAttendanceByDateRange(startKey, endKey);
    } else {
      list = await _db.getAllAttendance();
    }

    final excel = Excel.createExcel();
    final sheet = excel['Chấm công'];

    _writeHeaders(sheet, [
      'STT',
      'Ngày',
      'Nhân viên',
      'Email',
      'Giờ vào',
      'Giờ ra',
      'Tăng ca (phút)',
      'Trạng thái',
      'Đi muộn',
      'Về sớm',
      'Duyệt bởi',
      'Ghi chú',
      'Vị trí',
    ]);

    for (int i = 0; i < list.length; i++) {
      final a = list[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        a.dateKey,
        a.name,
        a.email,
        _fmtDateTime(a.checkInAt),
        _fmtDateTime(a.checkOutAt),
        a.overtimeOn,
        a.status,
        a.isLate == 1 ? 'Có' : 'Không',
        a.isEarlyLeave == 1 ? 'Có' : 'Không',
        a.approvedBy ?? '',
        a.note ?? '',
        a.location ?? '',
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('cham_cong', startMs, endMs);
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  5. EXPORT PRODUCTS / INVENTORY (KHO)
  // ──────────────────────────────────────────────

  static Future<void> exportProducts(
    BuildContext context, {
    int? startMs,
    int? endMs,
  }) async {
    List<Product> products = await _db.getAllProducts();

    // Filter by createdAt if date range specified
    products = _filterByDate(
      products,
      startMs,
      endMs,
      (p) => p.createdAt,
    );

    final excel = Excel.createExcel();
    final sheet = excel['Kho hàng'];

    _writeHeaders(sheet, [
      'STT',
      'Tên sản phẩm',
      'Hãng',
      'Model',
      'IMEI',
      'Màu',
      'Dung lượng',
      'Tình trạng',
      'Số lượng',
      'Giá vốn',
      'Giá bán',
      'Nhà cung cấp',
      'Bảo hành',
      'Ngày nhập',
      'Mô tả',
      'SKU',
    ]);

    for (int i = 0; i < products.length; i++) {
      final p = products[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        p.name,
        p.brand,
        p.model ?? '',
        p.imei ?? '',
        p.color ?? '',
        p.capacity ?? '',
        p.condition,
        p.quantity,
        _fmtMoney(p.cost),
        _fmtMoney(p.price),
        p.supplier ?? '',
        p.warranty ?? '',
        _fmtDateTime(p.createdAt),
        p.description,
        p.sku ?? '',
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('kho_hang', startMs, endMs);
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  6. EXPORT CUSTOMERS (KHÁCH HÀNG)
  // ──────────────────────────────────────────────

  static Future<void> exportCustomers(
    BuildContext context, {
    int? startMs,
    int? endMs,
  }) async {
    List<Map<String, dynamic>> maps = await _db.getCustomers();

    // Filter by createdAt
    if (startMs != null || endMs != null) {
      maps = maps.where((m) {
        final ts = m['createdAt'] as int? ?? 0;
        if (startMs != null && ts < startMs) return false;
        if (endMs != null && ts > endMs) return false;
        return true;
      }).toList();
    }

    final excel = Excel.createExcel();
    final sheet = excel['Khách hàng'];

    _writeHeaders(sheet, [
      'STT',
      'Tên khách hàng',
      'SĐT',
      'Email',
      'Địa chỉ',
      'Tổng chi tiêu',
      'Số lần sửa',
      'Tổng tiền sửa',
      'Ngày tạo',
      'Lần ghé cuối',
      'Ghi chú',
    ]);

    for (int i = 0; i < maps.length; i++) {
      final c = maps[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        c['name'] ?? '',
        c['phone'] ?? '',
        c['email'] ?? '',
        c['address'] ?? '',
        _fmtMoney(c['totalSpent']),
        c['totalRepairs'] ?? 0,
        _fmtMoney(c['totalRepairCost']),
        _fmtDateTime(c['createdAt']),
        _fmtDateTime(c['lastVisitAt']),
        c['notes'] ?? '',
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('khach_hang', startMs, endMs);
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  7. EXPORT FINANCIAL ACTIVITY LOG (NHẬT KÝ)
  // ──────────────────────────────────────────────

  /// Export financial activity log from pre-loaded data.
  /// [activities] is the list already queried from Firestore by the view.
  static Future<void> exportActivityLog(
    BuildContext context, {
    required List<FinancialActivity> activities,
    int? startMs,
    int? endMs,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Nhật ký tài chính'];

    _writeHeaders(sheet, [
      'STT',
      'Thời gian',
      'Loại',
      'Chiều',
      'Tiêu đề',
      'Số tiền',
      'PT thanh toán',
      'Khách hàng',
      'SĐT',
      'Sản phẩm',
      'Mô tả',
      'Người tạo',
    ]);

    for (int i = 0; i < activities.length; i++) {
      final a = activities[i];
      String directionVi = '';
      switch (a.direction) {
        case 'IN':
          directionVi = 'Thu';
          break;
        case 'OUT':
          directionVi = 'Chi';
          break;
        case 'DEBT':
          directionVi = 'Nợ';
          break;
      }
      _writeRow(sheet, i + 1, [
        i + 1,
        _fmtDateTime(a.createdAt),
        _activityTypeVi(a.activityType),
        directionVi,
        a.title,
        _fmtMoney(a.amount),
        a.paymentMethod,
        a.customerName ?? '',
        a.phone ?? '',
        a.productInfo ?? '',
        a.description ?? '',
        a.createdBy ?? '',
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('nhat_ky_tai_chinh', startMs, endMs);
    await _saveAndShare(excel, fileName, context);
  }

  /// Export audit/system logs from pre-loaded data.
  static Future<void> exportAuditLog(
    BuildContext context, {
    required List<Map<String, dynamic>> auditLogs,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Nhật ký hệ thống'];

    _writeHeaders(sheet, [
      'STT',
      'Thời gian',
      'Hành động',
      'Mô tả',
      'Người thực hiện',
      'Đối tượng',
      'ID đối tượng',
    ]);

    for (int i = 0; i < auditLogs.length; i++) {
      final log = auditLogs[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        _fmtDateTime(log['createdAt']),
        log['action'] ?? '',
        log['description'] ?? log['summary'] ?? '',
        log['userName'] ?? '',
        log['targetType'] ?? log['entityType'] ?? '',
        log['targetId'] ?? log['entityId'] ?? '',
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final now = DateTime.now();
    final fileName = 'nhat_ky_he_thong_${DateFormat('ddMMyyyy').format(now)}.xlsx';
    await _saveAndShare(excel, fileName, context);
  }

  /// Vietnamese label for activity type
  static String _activityTypeVi(String type) {
    switch (type) {
      case 'SALE': return 'Bán hàng';
      case 'REPAIR': return 'Sửa chữa';
      case 'EXPENSE': return 'Chi phí';
      case 'PURCHASE': return 'Nhập hàng';
      case 'DEBT_COLLECT': return 'Thu nợ';
      case 'DEBT_PAY': return 'Trả nợ';
      case 'SUPPLIER_PAYMENT': return 'Trả NCC';
      case 'SETTLEMENT': return 'Tất toán';
      case 'REFUND': return 'Hoàn tiền';
      case 'ADJUSTMENT': return 'Điều chỉnh';
      case 'REPAIR_PARTNER_PAYMENT': return 'Trả đối tác SC';
      default: return type;
    }
  }

  // ──────────────────────────────────────────────
  //  8. EXPORT DEBTS (CÔNG NỢ)
  // ──────────────────────────────────────────────

  static Future<void> exportDebts(
    BuildContext context, {
    int? startMs,
    int? endMs,
  }) async {
    List<Map<String, dynamic>> maps = await _db.getAllDebts();

    if (startMs != null || endMs != null) {
      maps = maps.where((m) {
        final ts = m['createdAt'] as int? ?? 0;
        if (startMs != null && ts < startMs) return false;
        if (endMs != null && ts > endMs) return false;
        return true;
      }).toList();
    }

    final excel = Excel.createExcel();
    final sheet = excel['Công nợ'];

    _writeHeaders(sheet, [
      'STT',
      'Ngày tạo',
      'Khách hàng',
      'SĐT',
      'Loại nợ',
      'Tổng nợ',
      'Đã trả',
      'Còn lại',
      'Trạng thái',
      'Ghi chú',
    ]);

    for (int i = 0; i < maps.length; i++) {
      final d = maps[i];
      final total = d['totalAmount'] as int? ?? 0;
      final paid = d['paidAmount'] as int? ?? 0;
      String typeVi = '';
      switch (d['type']) {
        case 'CUSTOMER_OWES':
        case 'OWE':
          typeVi = 'Khách nợ';
          break;
        case 'SHOP_OWES':
        case 'OWED':
          typeVi = 'Shop nợ';
          break;
        case 'OTHER_CUSTOMER_OWES':
          typeVi = 'KH khác nợ';
          break;
        case 'OTHER_SHOP_OWES':
          typeVi = 'Shop nợ khác';
          break;
        default:
          typeVi = d['type'] ?? '';
      }

      String statusVi = '';
      switch (d['status']) {
        case 'ACTIVE':
        case 'unpaid':
          statusVi = 'Đang nợ';
          break;
        case 'PAID':
        case 'paid':
          statusVi = 'Đã trả';
          break;
        case 'CANCELLED':
          statusVi = 'Đã huỷ';
          break;
        default:
          statusVi = d['status'] ?? '';
      }

      _writeRow(sheet, i + 1, [
        i + 1,
        _fmtDateTime(d['createdAt']),
        d['personName'] ?? '',
        d['phone'] ?? '',
        typeVi,
        _fmtMoney(total),
        _fmtMoney(paid),
        _fmtMoney(total - paid),
        statusVi,
        d['note'] ?? '',
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('cong_no', startMs, endMs);
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  9. EXPORT INVENTORY CHECK (KIỂM KHO)
  // ──────────────────────────────────────────────

  static Future<void> exportInventoryCheck(
    BuildContext context,
    InventoryCheck check,
  ) async {
    final excel = Excel.createExcel();
    final typeVi =
        check.checkType == 'DIEN_THOAI' ? 'Điện thoại' : 'Phụ kiện';
    final sheet = excel['Kiểm kho $typeVi'];

    _writeHeaders(sheet, [
      'STT',
      'Tên sản phẩm',
      'Loại',
      'IMEI',
      'Màu',
      'Số lượng',
      'Đã kiểm',
      'Thời gian kiểm',
    ]);

    for (int i = 0; i < check.items.length; i++) {
      final item = check.items[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        item.itemName,
        item.itemType,
        item.imei ?? '',
        item.color ?? '',
        item.quantity,
        item.isChecked ? 'Đã kiểm' : 'Chưa kiểm',
        _fmtDateTime(item.checkedAt),
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final dateStr = DateFormat('ddMMyyyy_HHmm').format(
      DateTime.fromMillisecondsSinceEpoch(check.checkDate),
    );
    final fileName = 'kiem_kho_${check.checkType}_$dateStr.xlsx';
    await _saveAndShare(excel, fileName, context);
  }

  /// Export a list of inventory checks as summary
  static Future<void> exportInventoryCheckList(
    BuildContext context,
    List<InventoryCheck> checks,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['DS Kiểm kho'];

    _writeHeaders(sheet, [
      'STT',
      'Ngày kiểm',
      'Loại',
      'Người kiểm',
      'Tổng SP',
      'Đã kiểm',
      'Chưa kiểm',
      'Hoàn thành',
    ]);

    for (int i = 0; i < checks.length; i++) {
      final c = checks[i];
      final checkedCount = c.items.where((it) => it.isChecked).length;
      final uncheckedCount = c.items.length - checkedCount;
      _writeRow(sheet, i + 1, [
        i + 1,
        _fmtDateTime(c.checkDate),
        c.checkType == 'DIEN_THOAI' ? 'Điện thoại' : 'Phụ kiện',
        c.checkedBy,
        c.items.length,
        checkedCount,
        uncheckedCount,
        c.isCompleted ? 'Hoàn thành' : 'Chưa xong',
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('ds_kiem_kho', null, null);
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  10. EXPORT STAFF REPAIRS (MÁY ĐÃ SỬA CỦA NV)
  // ──────────────────────────────────────────────

  static Future<void> exportStaffRepairs(
    BuildContext context,
    String staffName,
    List<Repair> repairs, {
    int? startMs,
    int? endMs,
  }) async {
    repairs = _filterByDate(repairs, startMs, endMs, (r) => r.createdAt);

    final excel = Excel.createExcel();
    final sheet = excel['Máy đã sửa - $staffName'];

    _writeHeaders(sheet, [
      'STT',
      'Ngày nhận',
      'Khách hàng',
      'SĐT',
      'Model',
      'IMEI',
      'Lỗi',
      'Trạng thái',
      'Giá',
      'Chi phí',
      'Ngày sửa xong',
      'Bảo hành',
    ]);

    for (int i = 0; i < repairs.length; i++) {
      final r = repairs[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        _fmtDateTime(r.createdAt),
        r.customerName,
        r.phone,
        r.model,
        r.imei ?? '',
        r.issue,
        _repairStatus(r.status),
        _fmtMoney(r.price),
        _fmtMoney(r.cost),
        _fmtDateTime(r.finishedAt),
        r.warranty,
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName(
      'may_sua_${staffName.replaceAll(' ', '_')}',
      startMs,
      endMs,
    );
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  11. EXPORT STAFF SALES (ĐƠN BÁN CỦA NV)
  // ──────────────────────────────────────────────

  static Future<void> exportStaffSales(
    BuildContext context,
    String staffName,
    List<SaleOrder> sales, {
    int? startMs,
    int? endMs,
  }) async {
    sales = _filterByDate(sales, startMs, endMs, (s) => s.soldAt);

    final excel = Excel.createExcel();
    final sheet = excel['Đơn bán - $staffName'];

    _writeHeaders(sheet, [
      'STT',
      'Ngày bán',
      'Khách hàng',
      'SĐT',
      'Sản phẩm',
      'IMEI',
      'Giá bán',
      'Giảm giá',
      'Thành tiền',
      'PT thanh toán',
      'Bảo hành',
    ]);

    for (int i = 0; i < sales.length; i++) {
      final s = sales[i];
      _writeRow(sheet, i + 1, [
        i + 1,
        _fmtDateTime(s.soldAt),
        s.customerName,
        s.phone,
        s.productNames,
        s.productImeis,
        _fmtMoney(s.totalPrice),
        _fmtMoney(s.discount),
        _fmtMoney(s.finalPrice),
        s.paymentMethod,
        s.warranty,
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName(
      'don_ban_${staffName.replaceAll(' ', '_')}',
      startMs,
      endMs,
    );
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  12. EXPORT WARRANTY ITEMS (BẢO HÀNH)
  // ──────────────────────────────────────────────

  /// Export warranty items — repairs with status=4 (delivered) and non-empty warranty
  static Future<void> exportWarranty(
    BuildContext context, {
    int? startMs,
    int? endMs,
    List<Repair>? repairList,
    List<SaleOrder>? saleList,
  }) async {
    // Get repairs with warranty  
    List<Repair> repairs = repairList ?? await _db.getAllRepairs();
    repairs = repairs
        .where((r) =>
            !r.deleted &&
            r.warranty.isNotEmpty &&
            r.warranty != '0' &&
            r.warranty != 'Không')
        .toList();
    repairs = _filterByDate(repairs, startMs, endMs, (r) => r.createdAt);

    // Get sales with warranty
    List<SaleOrder> sales = saleList ?? await _db.getAllSales();
    sales = sales
        .where((s) =>
            s.warranty.isNotEmpty &&
            s.warranty != '0' &&
            s.warranty != 'Không')
        .toList();
    sales = _filterByDate(sales, startMs, endMs, (s) => s.soldAt);

    final excel = Excel.createExcel();

    // Sheet 1: Repair warranty
    final sheetRepair = excel['BH Sửa chữa'];
    _writeHeaders(sheetRepair, [
      'STT',
      'Ngày',
      'Khách hàng',
      'SĐT',
      'Model',
      'IMEI',
      'Lỗi',
      'Bảo hành',
      'Trạng thái',
      'Giá',
    ]);

    for (int i = 0; i < repairs.length; i++) {
      final r = repairs[i];
      _writeRow(sheetRepair, i + 1, [
        i + 1,
        _fmtDateTime(r.deliveredAt ?? r.createdAt),
        r.customerName,
        r.phone,
        r.model,
        r.imei ?? '',
        r.issue,
        r.warranty,
        _repairStatus(r.status),
        _fmtMoney(r.price),
      ]);
    }

    // Sheet 2: Sale warranty
    final sheetSale = excel['BH Bán hàng'];
    _writeHeaders(sheetSale, [
      'STT',
      'Ngày bán',
      'Khách hàng',
      'SĐT',
      'Sản phẩm',
      'IMEI',
      'Bảo hành',
      'Giá bán',
    ]);

    for (int i = 0; i < sales.length; i++) {
      final s = sales[i];
      _writeRow(sheetSale, i + 1, [
        i + 1,
        _fmtDateTime(s.soldAt),
        s.customerName,
        s.phone,
        s.productNames,
        s.productImeis,
        s.warranty,
        _fmtMoney(s.totalPrice),
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('bao_hanh', startMs, endMs);
    await _saveAndShare(excel, fileName, context);
  }
}
