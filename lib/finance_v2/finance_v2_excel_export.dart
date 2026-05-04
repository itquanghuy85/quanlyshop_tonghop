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

// ──────────────────────────────────────────────────────────────────────────
//  Detailed daily report export — "Chi Tiết Ngày" sheet
// ──────────────────────────────────────────────────────────────────────────

class FinanceV2DetailedDailySection {
  final String title;
  final List<String> colHeaders;
  final List<List<dynamic>> rows;

  const FinanceV2DetailedDailySection({
    required this.title,
    required this.colHeaders,
    required this.rows,
  });
}

extension FinanceV2ExcelDetailed on FinanceV2ExcelExport {
  // Expose save/share for external callers that build their own excel.
  static Future<void> saveAndOpen(
    BuildContext context,
    xl.Excel excel,
    String filePrefix, {
    DateTime? start,
    DateTime? end,
  }) {
    final fileName = _buildFileNameStatic(filePrefix, start, end);
    return FinanceV2ExcelExport._saveAndShare(excel, fileName, context);
  }

  static String _buildFileNameStatic(
      String prefix, DateTime? start, DateTime? end) {
    final fmt = DateFormat('ddMMyyyy');
    if (start != null && end != null) {
      return '${prefix}_${fmt.format(start)}_${fmt.format(end)}.xlsx';
    }
    return '${prefix}_${fmt.format(DateTime.now())}.xlsx';
  }
}

class FinanceV2DetailedExporter {
  static xl.Border get _thin => xl.Border(
        borderColorHex: xl.ExcelColor.fromHexString('#BFBFBF'),
        borderStyle: xl.BorderStyle.Thin,
      );

  /// Section title style: dark blue #1565C0, white bold
  static xl.CellStyle _sectionTitleStyle() => xl.CellStyle(
        bold: true,
        backgroundColorHex: xl.ExcelColor.fromHexString('#1565C0'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: xl.HorizontalAlign.Left,
        topBorder: _thin,
        bottomBorder: _thin,
        leftBorder: _thin,
        rightBorder: _thin,
      );

  /// Column header style: lighter blue, white bold, centered
  static xl.CellStyle _colHeaderStyle() => xl.CellStyle(
        bold: true,
        backgroundColorHex: xl.ExcelColor.fromHexString('#1E88E5'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: xl.HorizontalAlign.Center,
        topBorder: _thin,
        bottomBorder: _thin,
        leftBorder: _thin,
        rightBorder: _thin,
      );

  /// Alternating data row: even = light gray, odd = white
  static xl.CellStyle _dataRowStyle(int relIndex) => xl.CellStyle(
        backgroundColorHex: relIndex.isEven
            ? xl.ExcelColor.fromHexString('#F5F5F5')
            : xl.ExcelColor.fromHexString('#FFFFFF'),
        topBorder: _thin,
        bottomBorder: _thin,
        leftBorder: _thin,
        rightBorder: _thin,
      );

  /// Write a section title spanning [colCount] columns at [row] (merged via repeated writes)
  static void _writeSectionTitle(
      xl.Sheet sheet, int row, String title, int colCount) {
    final style = _sectionTitleStyle();
    for (int c = 0; c < colCount; c++) {
      final cell = sheet.cell(
          xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      cell.value = c == 0 ? xl.TextCellValue(title) : xl.TextCellValue('');
      cell.cellStyle = style;
    }
  }

  /// Write column headers at [row]
  static void _writeColHeaders(
      xl.Sheet sheet, int row, List<String> headers) {
    final style = _colHeaderStyle();
    for (int c = 0; c < headers.length; c++) {
      final cell = sheet.cell(
          xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      cell.value = xl.TextCellValue(headers[c]);
      cell.cellStyle = style;
    }
  }

  /// Write a data row at [row], [relIndex] controls alternating color
  static void _writeDataRow(
      xl.Sheet sheet, int row, int relIndex, List<dynamic> values) {
    final style = _dataRowStyle(relIndex);
    for (int c = 0; c < values.length; c++) {
      final cell = sheet.cell(
          xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      final v = values[c];
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

  /// Write blank rows at [row]
  static void _writeBlankRows(xl.Sheet sheet, int row, int count) {
    for (int r = 0; r < count; r++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row + r))
          .value = xl.TextCellValue('');
    }
  }

  /// Build and export the "Chi Tiết Ngày" workbook (all sections in one sheet).
  /// Returns after saving/sharing.
  static Future<void> exportDetailedDailyReport(
    BuildContext context, {
    required List<FinanceV2DetailedDailySection> sections,
    required String filePrefix,
    DateTime? start,
    DateTime? end,
    List<FinanceV2ExcelSheet>? extraSheets,
  }) async {
    final excel = xl.Excel.createExcel();

    // ── Extra summary sheets (added first) ──────────────────────────
    if (extraSheets != null) {
      for (final extra in extraSheets) {
        final ws = excel[extra.sheetName];
        int row = 0;
        // Header row
        for (int c = 0; c < extra.headers.length; c++) {
          ws.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row))
            .value = xl.TextCellValue(extra.headers[c]);
        }
        row++;
        // Data rows
        for (final dataRow in extra.rows) {
          for (int c = 0; c < dataRow.length; c++) {
            final v = dataRow[c];
            final cell = ws.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
            if (v is int) {
              cell.value = xl.IntCellValue(v);
            } else if (v is double) {
              cell.value = xl.DoubleCellValue(v);
            } else {
              cell.value = xl.TextCellValue(v?.toString() ?? '');
            }
          }
          row++;
        }
      }
    }

    final sheet = excel['Chi Tiết Ngày'];

    // Find max col count
    final maxCols = sections.fold<int>(
        4, (m, s) => s.colHeaders.length > m ? s.colHeaders.length : m);

    int currentRow = 0;
    for (int si = 0; si < sections.length; si++) {
      final sec = sections[si];
      // Section title
      _writeSectionTitle(sheet, currentRow, sec.title, maxCols);
      currentRow++;
      // Column headers
      _writeColHeaders(sheet, currentRow, sec.colHeaders);
      currentRow++;
      // Data rows
      for (int ri = 0; ri < sec.rows.length; ri++) {
        _writeDataRow(sheet, currentRow, ri, sec.rows[ri]);
        currentRow++;
      }
      // 2 blank rows between sections (except after last)
      if (si < sections.length - 1) {
        _writeBlankRows(sheet, currentRow, 2);
        currentRow += 2;
      }
    }

    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    final fmt = DateFormat('ddMMyyyy');
    final fileName = (start != null && end != null)
        ? '${filePrefix}_${fmt.format(start)}_${fmt.format(end)}.xlsx'
        : '${filePrefix}_${fmt.format(DateTime.now())}.xlsx';

    await FinanceV2ExcelExport._saveAndShare(excel, fileName, context);
  }
}
