import 'dart:io';

import 'package:excel/excel.dart' as xl;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Finance V2 Excel export utility.
/// Uses `as xl` alias to avoid Border/BorderStyle conflicts with Flutter.
class FinanceV2ExcelExport {
  static final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');
  static final _dFmt = DateFormat('dd/MM/yyyy');
  static final _fileDateFmt = DateFormat('ddMMyyyy');

  // ── Thin dark border ──────────────────────────────────
  static xl.Border get _thin => xl.Border(
        borderColorHex: xl.ExcelColor.fromHexString('#BFBFBF'),
        borderStyle: xl.BorderStyle.Thin,
      );

  // ── Header style: indigo bg, white bold text, thin border ──
  static xl.CellStyle _headerStyle() => xl.CellStyle(
        bold: true,
        backgroundColorHex: xl.ExcelColor.fromHexString('#164A9E'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: xl.HorizontalAlign.Center,
        topBorder: _thin,
        bottomBorder: _thin,
        leftBorder: _thin,
        rightBorder: _thin,
      );

  // ── Alternating data row style ─────────────────────────
  static xl.CellStyle _rowStyle(int rowIndex) => xl.CellStyle(
        backgroundColorHex: rowIndex.isOdd
            ? xl.ExcelColor.fromHexString('#EEF3FB') // light blue-grey
            : xl.ExcelColor.fromHexString('#FFFFFF'),
        topBorder: _thin,
        bottomBorder: _thin,
        leftBorder: _thin,
        rightBorder: _thin,
      );

  static void _writeHeaders(xl.Sheet sheet, List<String> headers) {
    final style = _headerStyle();
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0),
      );
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = style;
    }
  }

  static void _writeDataRow(
      xl.Sheet sheet, int rowIndex, List<dynamic> values) {
    final style = _rowStyle(rowIndex);
    for (int i = 0; i < values.length; i++) {
      final cell = sheet.cell(
        xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex),
      );
      final v = values[i];
      if (v is int) {
        cell.value = xl.IntCellValue(v);
      } else if (v is double) {
        cell.value = xl.DoubleCellValue(v);
      } else {
        cell.value = xl.TextCellValue(v?.toString() ?? '');
      }
      cell.cellStyle = style;
    }
  }

  /// Generic table export — headers + rows.
  static Future<void> exportTable(
    BuildContext context, {
    required String sheetName,
    required String filePrefix,
    required List<String> headers,
    required List<List<dynamic>> rows,
    DateTime? start,
    DateTime? end,
  }) async {
    final excel = xl.Excel.createExcel();
    final sheet = excel[sheetName];

    _writeHeaders(sheet, headers);
    for (int i = 0; i < rows.length; i++) {
      _writeDataRow(sheet, i + 1, rows[i]);
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName(filePrefix, start, end);
    await _saveAndShare(excel, fileName, context);
  }

  static Future<void> exportWorkbook(
    BuildContext context, {
    required String filePrefix,
    required List<FinanceV2ExcelSheet> sheets,
    DateTime? start,
    DateTime? end,
  }) async {
    final excel = xl.Excel.createExcel();

    for (final spec in sheets) {
      final sheet = excel[spec.sheetName];
      _writeHeaders(sheet, spec.headers);
      for (int i = 0; i < spec.rows.length; i++) {
        _writeDataRow(sheet, i + 1, spec.rows[i]);
      }
    }

    if (excel.sheets.containsKey('Sheet1') && sheets.every((s) => s.sheetName != 'Sheet1')) {
      excel.delete('Sheet1');
    }

    final fileName = _buildFileName(filePrefix, start, end);
    await _saveAndShare(excel, fileName, context);
  }

  // ─────────────────────────────────────────────────────
  //  Format helpers (public for use by callers)
  // ─────────────────────────────────────────────────────

  static String fmtDate(int ms) =>
      ms > 0 ? _dFmt.format(DateTime.fromMillisecondsSinceEpoch(ms)) : '';

  static String fmtDateTime(int ms) =>
      ms > 0 ? _dtFmt.format(DateTime.fromMillisecondsSinceEpoch(ms)) : '';

  static String _buildFileName(String prefix, DateTime? start, DateTime? end) {
    if (start != null && end != null) {
      final s = _fileDateFmt.format(start);
      final e = _fileDateFmt.format(end);
      return '${prefix}_${s}_$e.xlsx';
    }
    return '${prefix}_${_fileDateFmt.format(DateTime.now())}.xlsx';
  }

  // ─────────────────────────────────────────────────────
  //  Save & share
  // ─────────────────────────────────────────────────────

  static Future<void> _saveAndShare(
    xl.Excel excel,
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

      if (kIsWeb) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Đang tải xuống: $fileName')),
          );
        }
        return;
      }

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
          await File(savedPath).writeAsBytes(bytes);
        }
      } catch (_) {}

      final dir = await getTemporaryDirectory();
      final tempPath = '${dir.path}/$fileName';
      await File(tempPath).writeAsBytes(bytes);

      if (!context.mounted) return;

      final action = await showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
            title: const Text('Xuất file thành công!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (savedPath != null)
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
                            'Đã lưu:\n$fileName',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const Text('File đã sẵn sàng để chia sẻ.'),
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
      debugPrint('Finance V2 Excel export error: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xuất file: $e')),
        );
      }
    }
  }
}

class FinanceV2ExcelSheet {
  final String sheetName;
  final List<String> headers;
  final List<List<dynamic>> rows;

  const FinanceV2ExcelSheet({
    required this.sheetName,
    required this.headers,
    required this.rows,
  });
}
