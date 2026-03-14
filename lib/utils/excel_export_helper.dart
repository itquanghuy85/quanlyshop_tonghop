import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'web_download_helper.dart'
    if (dart.library.js_interop) 'web_download_helper_web.dart';

import '../data/db_helper.dart';
import '../models/financial_activity_model.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/expense_model.dart';
import '../models/attendance_model.dart';
import '../models/attendance_monthly_summary_model.dart';
import '../models/product_model.dart';
import '../models/inventory_check_model.dart';
import '../services/user_service.dart';
import 'money_utils.dart';

/// Utility class for exporting data to Excel (.xlsx) files.
/// Supports date-range filtering and Vietnamese column headers.
class ExcelExportHelper {
  static final _db = DBHelper();
  static final _dateFormat = DateFormat('dd/MM/yyyy');
  static final _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');
  static final _monthFormat = DateFormat('MM/yyyy');

  static String _attendanceStatusLabel(String status) {
    switch (status) {
      case 'approved':
        return 'Đã duyệt';
      case 'rejected':
        return 'Từ chối';
      case 'completed':
      case 'pending':
      default:
        return 'Chờ duyệt';
    }
  }

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

  static String _fmtMinutes(int totalMinutes) {
    return AttendanceMonthlySummary.formatMinutes(totalMinutes);
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Lỗi tạo file Excel')));
        }
        return;
      }

      // Web: download via browser with proper filename
      if (kIsWeb) {
        await downloadFileWeb(bytes, fileName);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Đã tải xuống: $fileName'),
              backgroundColor: Colors.green,
            ),
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
                      style: const TextStyle(fontSize: 13, color: Colors.grey),
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
          ShareParams(files: [XFile(tempPath)], title: fileName),
        );
      }
    } catch (e) {
      debugPrint('Excel export error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Lỗi xuất file: $e')));
      }
    }
  }

  /// Build filename with date range
  static String _buildFileName(String prefix, int? startMs, int? endMs) {
    if (startMs != null && endMs != null) {
      final s = DateFormat(
        'ddMMyyyy',
      ).format(DateTime.fromMillisecondsSinceEpoch(startMs));
      final e = DateFormat(
        'ddMMyyyy',
      ).format(DateTime.fromMillisecondsSinceEpoch(endMs));
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
    // Check cost price permission
    final perms = await UserService.getCurrentUserPermissions();
    final canViewCost = perms['allowViewCostPrice'] ?? false;

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
        canViewCost ? _fmtMoney(r.cost) : '***',
        canViewCost ? _fmtMoney(r.price - r.cost) : '***',
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
    // Check cost price permission
    final perms = await UserService.getCurrentUserPermissions();
    final canViewCost = perms['allowViewCostPrice'] ?? false;

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
        canViewCost ? _fmtMoney(s.totalCost) : '***',
        canViewCost ? _fmtMoney(s.totalPrice - s.totalCost - s.discount) : '***',
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
      final startKey = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime.fromMillisecondsSinceEpoch(startMs));
      final endKey = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime.fromMillisecondsSinceEpoch(endMs));
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
      'Số giờ làm',
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
      // Calculate work hours
      String workHours = '';
      if (a.checkInAt != null && a.checkOutAt != null) {
        final minutes = ((a.checkOutAt! - a.checkInAt!) / 60000).round();
        final h = minutes ~/ 60;
        final m = minutes % 60;
        workHours = '${h}h${m > 0 ? ' ${m}p' : ''}';
      }
      _writeRow(sheet, i + 1, [
        i + 1,
        a.dateKey,
        a.name,
        a.email,
        _fmtDateTime(a.checkInAt),
        _fmtDateTime(a.checkOutAt),
        workHours,
        a.overtimeOn,
        _attendanceStatusLabel(a.status),
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

  static Future<void> exportAttendanceMonthlySummary(
    BuildContext context, {
    required DateTime month,
    required List<AttendanceMonthlySummary> summaries,
    required Map<String, List<Attendance>> staffAttendance,
  }) async {
    final excel = Excel.createExcel();
    final summarySheet = excel['Tong hop thang'];
    final detailSheet = excel['Chi tiet'];

    _writeHeaders(summarySheet, [
      'STT',
      'Nhân viên',
      'Email',
      'Vai trò',
      'Ngày công',
      'Đã duyệt',
      'Chờ duyệt',
      'Từ chối',
      'Đi muộn',
      'Về sớm',
      'Thiếu giờ ra',
      'Giờ công',
      'Tăng ca',
      'Tỷ lệ duyệt',
    ]);

    for (int i = 0; i < summaries.length; i++) {
      final summary = summaries[i];
      _writeRow(summarySheet, i + 1, [
        i + 1,
        summary.name,
        summary.email,
        summary.role,
        summary.workDays,
        summary.approvedDays,
        summary.pendingDays,
        summary.rejectedDays,
        summary.lateDays,
        summary.earlyLeaveDays,
        summary.incompleteDays,
        _fmtMinutes(summary.totalWorkMinutes),
        _fmtMinutes(summary.overtimeMinutes),
        '${(summary.approvalRate * 100).toStringAsFixed(0)}%',
      ]);
    }

    _writeHeaders(detailSheet, [
      'STT',
      'Nhân viên',
      'Ngày',
      'Giờ vào',
      'Giờ ra',
      'Giờ công',
      'OT',
      'Trạng thái',
      'Đi muộn',
      'Về sớm',
      'Ghi chú',
    ]);

    var rowIndex = 1;
    for (final summary in summaries) {
      final records = List<Attendance>.from(
        staffAttendance[summary.userId] ?? const [],
      )..sort((a, b) => a.dateKey.compareTo(b.dateKey));

      for (final record in records) {
        var workMinutes = 0;
        if (record.checkInAt != null && record.checkOutAt != null) {
          workMinutes = ((record.checkOutAt! - record.checkInAt!) / 60000)
              .round();
        }

        _writeRow(detailSheet, rowIndex, [
          rowIndex,
          summary.name,
          record.dateKey,
          _fmtDateTime(record.checkInAt),
          _fmtDateTime(record.checkOutAt),
          _fmtMinutes(workMinutes),
          _fmtMinutes(record.overtimeOn),
          _attendanceStatusLabel(record.status),
          record.isLate == 1 ? 'Có' : 'Không',
          record.isEarlyLeave == 1 ? 'Có' : 'Không',
          record.note ?? '',
        ]);
        rowIndex++;
      }
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName =
        'tong_hop_cham_cong_${DateFormat('MMyyyy').format(month)}.xlsx';
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
    // Check cost price permission
    final perms = await UserService.getCurrentUserPermissions();
    final canViewCost = perms['allowViewCostPrice'] ?? false;

    List<Product> products = await _db.getAllProducts();

    // Filter by createdAt if date range specified
    products = _filterByDate(products, startMs, endMs, (p) => p.createdAt);

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
        canViewCost ? _fmtMoney(p.cost) : '***',
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
  //  5b. EXPORT REPAIR PARTS (KHO LINH KIỆN SỬA CHỮA)
  // ──────────────────────────────────────────────

  static Future<void> exportRepairParts(
    BuildContext context, {
    int? startMs,
    int? endMs,
  }) async {
    // Check cost price permission
    final perms = await UserService.getCurrentUserPermissions();
    final canViewCost = perms['allowViewCostPrice'] ?? false;

    List<Map<String, dynamic>> parts = await _db.getAllParts();

    // Filter by createdAt if date range specified
    if (startMs != null || endMs != null) {
      parts = parts.where((p) {
        final ts = p['createdAt'] as int? ?? 0;
        if (startMs != null && ts < startMs) return false;
        if (endMs != null && ts > endMs) return false;
        return true;
      }).toList();
    }

    // Load suppliers for name lookup
    final suppliers = await _db.getSuppliers();
    String getSupplierName(int? id) {
      if (id == null) return '';
      final s = suppliers.firstWhere((s) => s['id'] == id, orElse: () => {});
      return s['name'] as String? ?? '';
    }

    final excel = Excel.createExcel();
    final sheet = excel['Kho linh kiện'];

    _writeHeaders(sheet, [
      'STT',
      'Tên linh kiện',
      'Dòng máy tương thích',
      'Số lượng tồn',
      'Giá vốn',
      'Giá bán',
      'Tổng vốn tồn',
      'Nhà cung cấp',
      'Hình thức TT',
      'Ngày nhập',
      'Cập nhật lần cuối',
    ]);

    for (int i = 0; i < parts.length; i++) {
      final p = parts[i];
      final qty = p['quantity'] as int? ?? 0;
      final cost = p['cost'] as int? ?? 0;
      _writeRow(sheet, i + 1, [
        i + 1,
        p['partName'] ?? '',
        p['compatibleModels'] ?? '',
        qty,
        canViewCost ? _fmtMoney(cost) : '***',
        _fmtMoney(p['price'] ?? 0),
        canViewCost ? _fmtMoney(cost * qty) : '***',
        getSupplierName(p['supplierId'] as int?),
        p['paymentMethod'] ?? '',
        _fmtDateTime(p['createdAt']),
        _fmtDateTime(p['updatedAt']),
      ]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName('kho_linh_kien', startMs, endMs);
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
    final fileName =
        'nhat_ky_he_thong_${DateFormat('ddMMyyyy').format(now)}.xlsx';
    await _saveAndShare(excel, fileName, context);
  }

  /// Vietnamese label for activity type
  static String _activityTypeVi(String type) {
    switch (type) {
      case 'SALE':
        return 'Bán hàng';
      case 'REPAIR':
        return 'Sửa chữa';
      case 'EXPENSE':
        return 'Chi phí';
      case 'PURCHASE':
        return 'Nhập hàng';
      case 'DEBT_COLLECT':
        return 'Thu nợ';
      case 'DEBT_PAY':
        return 'Trả nợ';
      case 'SUPPLIER_PAYMENT':
        return 'Trả NCC';
      case 'SETTLEMENT':
        return 'Tất toán';
      case 'REFUND':
        return 'Hoàn tiền';
      case 'ADJUSTMENT':
        return 'Điều chỉnh';
      case 'REPAIR_PARTNER_PAYMENT':
        return 'Trả đối tác SC';
      default:
        return type;
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
    final typeVi = check.checkType == 'DIEN_THOAI' ? 'Điện thoại' : 'Phụ kiện';
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

    final dateStr = DateFormat(
      'ddMMyyyy_HHmm',
    ).format(DateTime.fromMillisecondsSinceEpoch(check.checkDate));
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
        .where(
          (r) =>
              !r.deleted &&
              r.warranty.isNotEmpty &&
              r.warranty != '0' &&
              r.warranty != 'Không',
        )
        .toList();
    repairs = _filterByDate(repairs, startMs, endMs, (r) => r.createdAt);

    // Get sales with warranty
    List<SaleOrder> sales = saleList ?? await _db.getAllSales();
    sales = sales
        .where(
          (s) =>
              s.warranty.isNotEmpty &&
              s.warranty != '0' &&
              s.warranty != 'Không',
        )
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

  // ──────────────────────────────────────────────
  //  13. EXPORT CASH CLOSING TRANSACTIONS (SỔ QUỸ)
  // ──────────────────────────────────────────────

  static Future<void> exportCashClosingTransactions(
    BuildContext context, {
    required DateTime selectedDate,
    required List<Map<String, dynamic>> incomeList,
    required List<Map<String, dynamic>> expenseList,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['So_quy'];

    _writeHeaders(sheet, [
      'STT',
      'Ngày',
      'Giờ',
      'Loại',
      'Nhóm',
      'Nội dung',
      'Đối tượng',
      'PTTT',
      'Thu',
      'Chi',
      'Ghi chú',
    ]);

    final all = <Map<String, dynamic>>[];
    for (final t in incomeList) {
      all.add({...t, '_isIncome': true});
    }
    for (final t in expenseList) {
      all.add({...t, '_isIncome': false});
    }
    all.sort((a, b) => (b['time'] as String).compareTo(a['time'] as String));

    int totalIn = 0;
    int totalOut = 0;
    final dateStr = DateFormat('dd/MM/yyyy').format(selectedDate);

    for (int i = 0; i < all.length; i++) {
      final t = all[i];
      final amount = (t['amount'] as int?) ?? 0;
      final isIncome = (t['_isIncome'] as bool?) ?? false;
      final customerName = (t['customerName'] as String?) ?? '';
      final detail = (t['detail'] as String?) ?? '';
      final note = (t['note'] as String?) ?? '';

      if (isIncome) {
        totalIn += amount;
      } else {
        totalOut += amount;
      }

      _writeRow(sheet, i + 1, [
        i + 1,
        dateStr,
        t['time']?.toString() ?? '',
        isIncome ? 'THU' : 'CHI',
        t['title']?.toString() ?? '',
        detail,
        customerName,
        t['paymentMethod']?.toString() ?? '',
        isIncome ? _fmtMoney(amount) : '',
        isIncome ? '' : _fmtMoney(amount),
        note,
      ]);
    }

    final summaryRow = all.length + 2;
    _writeRow(sheet, summaryRow, [
      '',
      'TỔNG',
      '',
      '',
      '',
      '',
      '',
      '',
      _fmtMoney(totalIn),
      _fmtMoney(totalOut),
      'NET: ${_fmtMoney(totalIn - totalOut)}',
    ]);

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final startOfDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    ).millisecondsSinceEpoch;
    final endOfDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      23,
      59,
      59,
    ).millisecondsSinceEpoch;

    final fileName = _buildFileName('so_quy_giao_dich', startOfDay, endOfDay);
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  16. EXPORT SUPPLIER IMPORT HISTORY (LỊCH SỬ NHẬP NCC)
  // ──────────────────────────────────────────────

  static Future<void> exportSupplierImportHistory(
    BuildContext context, {
    required String supplierName,
    required List<Map<String, dynamic>> imports,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Lịch sử nhập'];

    _writeHeaders(sheet, [
      'STT',
      'Sản phẩm',
      'Ngày nhập',
      'Số tiền',
      'Ghi chú',
    ]);

    int totalAmount = 0;
    for (int i = 0; i < imports.length; i++) {
      final h = imports[i];
      final amount = h['totalAmount'] as int? ?? 0;
      totalAmount += amount;
      _writeRow(sheet, i + 1, [
        i + 1,
        h['productName'] ?? '',
        _fmtDate(h['importDate']),
        _fmtMoney(amount),
        h['notes'] ?? '',
      ]);
    }

    // Summary row
    final summaryRow = imports.length + 2;
    _writeRow(sheet, summaryRow, [
      '',
      'TỔNG',
      '${imports.length} lần nhập',
      _fmtMoney(totalAmount),
      '',
    ]);

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final safeName = supplierName
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(' ', '_');
    final now = DateFormat('ddMMyyyy_HHmm').format(DateTime.now());
    final fileName = 'nhap_hang_${safeName}_$now.xlsx';
    await _saveAndShare(excel, fileName, context);
  }

  // ──────────────────────────────────────────────
  //  17. EXPORT PARTNER REPAIR ORDERS (ĐƠN GỬI SỬA ĐỐI TÁC)
  // ──────────────────────────────────────────────

  static Future<void> exportPartnerRepairOrders(
    BuildContext context, {
    required String partnerName,
    required List<Map<String, dynamic>> orders,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['Đơn gửi sửa'];

    _writeHeaders(sheet, [
      'STT',
      'Dòng máy',
      'Khách hàng',
      'Lỗi / Yêu cầu',
      'Nội dung sửa',
      'Chi phí',
      'Ngày gửi',
    ]);

    int totalCost = 0;
    for (int i = 0; i < orders.length; i++) {
      final h = orders[i];
      final cost = h['partnerCost'] as int? ?? 0;
      totalCost += cost;
      _writeRow(sheet, i + 1, [
        i + 1,
        h['deviceModel'] ?? '',
        h['customerName'] ?? '',
        h['issue'] ?? '',
        h['repairContent'] ?? '',
        _fmtMoney(cost),
        _fmtDateTime(h['sentAt']),
      ]);
    }

    // Summary row
    final summaryRow = orders.length + 2;
    _writeRow(sheet, summaryRow, [
      '',
      'TỔNG',
      '${orders.length} đơn',
      '',
      '',
      _fmtMoney(totalCost),
      '',
    ]);

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final safeName = partnerName
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(' ', '_');
    final now = DateFormat('ddMMyyyy_HHmm').format(DateTime.now());
    final fileName = 'don_gui_sua_${safeName}_$now.xlsx';
    await _saveAndShare(excel, fileName, context);
  }

  // ==================== DAILY ACTIVITY REPORT ====================

  /// Export a comprehensive daily activity report with multiple sheets.
  static Future<void> exportDailyActivityReport({
    required BuildContext context,
    required dynamic report, // DailyActivityReport
  }) async {
    final excel = Excel.createExcel();
    final dateStr = DateFormat('dd/MM/yyyy').format(report.date as DateTime);
    final enableRepair = report.shopSettings.enableRepair as bool;

    // --- Sheet 1: Summary ---
    final summary = excel['Tổng quan'];
    summary.appendRow([
      TextCellValue('BÁO CÁO HOẠT ĐỘNG NGÀY $dateStr'),
    ]);
    summary.appendRow([TextCellValue('')]);

    final f = report.financial;
    final summaryRows = <List<CellValue>>[
      [TextCellValue('Chỉ tiêu'), TextCellValue('Giá trị (đ)')],
      [TextCellValue('Tổng thu'), IntCellValue(f.totalIn as int)],
      [TextCellValue('Tổng chi'), IntCellValue(f.totalOut as int)],
      [TextCellValue('Lợi nhuận'), IntCellValue(f.netProfit as int)],
      [TextCellValue(''), TextCellValue('')],
      [TextCellValue('Thu bán hàng'), IntCellValue(f.saleIncome as int)],
      [TextCellValue('Lãi bán hàng'), IntCellValue(f.saleProfit as int)],
    ];
    if (enableRepair) {
      summaryRows.addAll([
        [TextCellValue('Thu sửa chữa'), IntCellValue(f.repairIncome as int)],
        [TextCellValue('Lãi sửa chữa'), IntCellValue(f.repairProfit as int)],
      ]);
    }
    summaryRows.addAll([
      [TextCellValue('Thu nợ'), IntCellValue(f.debtCollected as int)],
      [TextCellValue('Thu khác'), IntCellValue(f.miscIncome as int)],
      [TextCellValue(''), TextCellValue('')],
      [TextCellValue('Chi phí'), IntCellValue(f.expenseOut as int)],
      [TextCellValue('Nhập hàng'), IntCellValue(f.importOut as int)],
      [TextCellValue('Trả NCC'), IntCellValue(f.supplierPaid as int)],
      [TextCellValue('Giá vốn bán'), IntCellValue(f.saleCost as int)],
    ]);
    if (enableRepair) {
      summaryRows.addAll([
        [TextCellValue('Trả ĐT sửa chữa'), IntCellValue(f.partnerPaid as int)],
        [TextCellValue('Giá vốn sửa'), IntCellValue(f.repairCost as int)],
      ]);
    }
    if ((f.refundOut as int) > 0) {
      summaryRows.add([TextCellValue('Hoàn trả'), IntCellValue(f.refundOut as int)]);
    }
    for (final row in summaryRows) {
      summary.appendRow(row);
    }

    // --- Sheet 2: Sales ---
    final sales = report.sales as List<Map<String, dynamic>>;
    if (sales.isNotEmpty) {
      final sSheet = excel['Bán hàng'];
      _writeHeaders(sSheet, [
        'STT', 'Thời gian', 'Mã đơn', 'Khách hàng', 'Tổng tiền',
        'Giảm giá', 'Thực thu', 'Giá vốn', 'Lãi',
      ]);
      for (var i = 0; i < sales.length; i++) {
        final s = sales[i];
        final total = (s['totalPrice'] as int?) ?? 0;
        final discount = (s['discount'] as int?) ?? 0;
        final cost = (s['totalCost'] as int?) ?? 0;
        _writeRow(sSheet, i + 1, [
          '${i + 1}',
          _fmtDateTime(s['soldAt'] as int?),
          s['code'] ?? '',
          s['customerName'] ?? 'Khách lẻ',
          _fmtMoney(total),
          _fmtMoney(discount),
          _fmtMoney(total - discount),
          _fmtMoney(cost),
          _fmtMoney(total - discount - cost),
        ]);
      }
    }

    // --- Sheet 3: Repairs ---
    final repairs = report.allRepairsToday as List<Map<String, dynamic>>;
    if (enableRepair && repairs.isNotEmpty) {
      final rSheet = excel['Sửa chữa'];
      _writeHeaders(rSheet, [
        'STT', 'Thời gian', 'Trạng thái', 'Khách hàng', 'Thiết bị',
        'Lỗi', 'Giá', 'Linh kiện',
      ]);
      for (var i = 0; i < repairs.length; i++) {
        final r = repairs[i];
        final status = (r['status'] as int?) ?? 1;
        final ts = status == 4 ? (r['deliveredAt'] as int?) : (r['createdAt'] as int?);
        _writeRow(rSheet, i + 1, [
          '${i + 1}',
          _fmtDateTime(ts),
          _repairStatus(status),
          r['customerName'] ?? '',
          r['deviceName'] ?? '',
          r['issue'] ?? '',
          _fmtMoney((r['price'] as int?) ?? 0),
          _fmtMoney((r['partsCost'] as int?) ?? 0),
        ]);
      }
    }

    // --- Sheet 4: Expenses ---
    final expenses = report.expenses as List<Map<String, dynamic>>;
    if (expenses.isNotEmpty) {
      final eSheet = excel['Chi phí'];
      _writeHeaders(eSheet, [
        'STT', 'Thời gian', 'Loại', 'Danh mục', 'Mô tả', 'Số tiền',
      ]);
      for (var i = 0; i < expenses.length; i++) {
        final e = expenses[i];
        final type = (e['type'] ?? 'CHI') == 'CHI' ? 'Chi' : 'Thu';
        _writeRow(eSheet, i + 1, [
          '${i + 1}',
          _fmtDateTime(e['date'] as int?),
          type,
          e['category'] ?? '',
          e['description'] ?? e['note'] ?? '',
          _fmtMoney((e['amount'] as int?) ?? 0),
        ]);
      }
    }

    // --- Sheet 5: Debts ---
    final debtPayments = report.debtPayments as List<Map<String, dynamic>>;
    final supplierPayments =
        report.supplierPayments as List<Map<String, dynamic>>;
    if (debtPayments.isNotEmpty || supplierPayments.isNotEmpty) {
      final dSheet = excel['Công nợ'];
      _writeHeaders(dSheet, [
        'STT', 'Loại', 'Đối tượng', 'Số tiền',
      ]);
      var idx = 0;
      for (final p in debtPayments) {
        idx++;
        _writeRow(dSheet, idx, [
          '$idx',
          'Thu nợ KH',
          p['customerName'] ?? p['debtorName'] ?? '',
          _fmtMoney((p['amount'] as int?) ?? 0),
        ]);
      }
      for (final p in supplierPayments) {
        idx++;
        _writeRow(dSheet, idx, [
          '$idx',
          'Trả nợ NCC',
          p['supplierName'] ?? '',
          _fmtMoney((p['amount'] as int?) ?? 0),
        ]);
      }
    }

    // --- Sheet 6: Staff ---
    final attendance = report.attendance as List;
    if (attendance.isNotEmpty) {
      final aSheet = excel['Nhân viên'];
      _writeHeaders(aSheet, [
        'STT', 'Tên', 'Giờ vào', 'Giờ ra', 'Trễ', 'Về sớm',
      ]);
      for (var i = 0; i < attendance.length; i++) {
        final a = attendance[i];
        _writeRow(aSheet, i + 1, [
          '${i + 1}',
          a.name ?? '',
          a.checkInAt != null ? _fmtDateTime(a.checkInAt as int?) : '',
          a.checkOutAt != null ? _fmtDateTime(a.checkOutAt as int?) : '',
          a.isLate == 1 ? 'Có' : '',
          a.isEarlyLeave == 1 ? 'Có' : '',
        ]);
      }
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final dateFile = DateFormat('ddMMyyyy').format(report.date as DateTime);
    final fileName = 'bao_cao_ngay_$dateFile.xlsx';
    await _saveAndShare(excel, fileName, context);
  }
}
