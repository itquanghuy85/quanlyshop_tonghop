import 'dart:typed_data';
import 'package:flutter/material.dart' show Colors;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/salary_breakdown_model.dart';
import 'user_service.dart';

/// Service tạo và in phiếu lương PDF chuyên nghiệp
class SalarySlipPdfService {
  static final _currencyFormat = NumberFormat('#,###', 'vi_VN');

  /// Lấy thông tin shop
  static Future<Map<String, dynamic>> _getShopInfo() async {
    try {
      final shopId = await UserService.getCurrentShopId();
      if (shopId == null) {
        return {
          'name': 'CỬA HÀNG',
          'address': '',
          'phone': '',
        };
      }

      final doc = await FirebaseFirestore.instance
          .collection('shops')
          .doc(shopId)
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        return {
          'name': data['name'] ?? 'CỬA HÀNG',
          'address': data['address'] ?? '',
          'phone': data['phone'] ?? '',
          'email': data['email'] ?? '',
          'taxCode': data['taxCode'] ?? '',
        };
      }
    } catch (e) {
      debugPrint('Error getting shop info: $e');
    }
    return {
      'name': 'CỬA HÀNG',
      'address': '',
      'phone': '',
    };
  }

  /// Format tiền tệ
  static String _formatCurrency(double amount) {
    return '${_currencyFormat.format(amount)} đ';
  }

  /// Tạo PDF phiếu lương cho 1 nhân viên
  static Future<Uint8List> generateSalarySlipPdf(
    SalaryBreakdown data, {
    Map<String, dynamic>? shopInfo,
  }) async {
    shopInfo ??= await _getShopInfo();

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();
    final fontItalic = await PdfGoogleFonts.robotoItalic();

    final baseStyle = pw.TextStyle(font: font, fontSize: 10);
    final boldStyle = pw.TextStyle(font: fontBold, fontSize: 10);
    final headerStyle = pw.TextStyle(font: fontBold, fontSize: 14);
    final titleStyle = pw.TextStyle(font: fontBold, fontSize: 18);
    final smallStyle = pw.TextStyle(font: font, fontSize: 8);
    final italicStyle = pw.TextStyle(font: fontItalic, fontSize: 9);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // ===== HEADER - THÔNG TIN SHOP =====
              _buildHeader(shopInfo!, titleStyle, baseStyle, smallStyle),
              pw.SizedBox(height: 20),

              // ===== TIÊU ĐỀ PHIẾU LƯƠNG =====
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 30,
                    vertical: 10,
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.blue800, width: 2),
                    borderRadius: pw.BorderRadius.circular(8),
                  ),
                  child: pw.Text(
                    'PHIẾU LƯƠNG THÁNG ${data.month.toString().padLeft(2, '0')}/${data.year}',
                    style: titleStyle.copyWith(color: PdfColors.blue800),
                  ),
                ),
              ),
              pw.SizedBox(height: 20),

              // ===== THÔNG TIN NHÂN VIÊN =====
              _buildEmployeeInfo(data, headerStyle, baseStyle, boldStyle),
              pw.SizedBox(height: 15),

              // ===== BẢNG CHI TIẾT LƯƠNG =====
              _buildSalaryTable(data, headerStyle, baseStyle, boldStyle),
              pw.SizedBox(height: 20),

              // ===== TỔNG KẾT =====
              _buildSummary(data, headerStyle, boldStyle),
              pw.SizedBox(height: 30),

              // ===== CHỮ KÝ =====
              _buildSignatures(baseStyle, boldStyle),

              // ===== FOOTER =====
              pw.Spacer(),
              _buildFooter(smallStyle, italicStyle),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Header với logo và thông tin shop
  static pw.Widget _buildHeader(
    Map<String, dynamic> shopInfo,
    pw.TextStyle titleStyle,
    pw.TextStyle baseStyle,
    pw.TextStyle smallStyle,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.blue200),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Logo placeholder
          pw.Container(
            width: 60,
            height: 60,
            decoration: pw.BoxDecoration(
              color: PdfColors.blue800,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Center(
              child: pw.Text(
                shopInfo['name']?.toString().substring(0, 1).toUpperCase() ??
                    'S',
                style: titleStyle.copyWith(color: PdfColors.white, fontSize: 30),
              ),
            ),
          ),
          pw.SizedBox(width: 15),
          // Thông tin shop
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  shopInfo['name']?.toString().toUpperCase() ?? 'CỬA HÀNG',
                  style: titleStyle.copyWith(color: PdfColors.blue900),
                ),
                if (shopInfo['address']?.toString().isNotEmpty == true)
                  pw.Text(
                    'Địa chỉ: ${shopInfo['address']}',
                    style: baseStyle,
                  ),
                if (shopInfo['phone']?.toString().isNotEmpty == true)
                  pw.Text(
                    'Điện thoại: ${shopInfo['phone']}',
                    style: baseStyle,
                  ),
                if (shopInfo['taxCode']?.toString().isNotEmpty == true)
                  pw.Text(
                    'Mã số thuế: ${shopInfo['taxCode']}',
                    style: smallStyle,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Thông tin nhân viên
  static pw.Widget _buildEmployeeInfo(
    SalaryBreakdown data,
    pw.TextStyle headerStyle,
    pw.TextStyle baseStyle,
    pw.TextStyle boldStyle,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('THÔNG TIN NHÂN VIÊN', style: headerStyle),
          pw.Divider(color: PdfColors.grey400),
          pw.SizedBox(height: 5),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildInfoRow('Họ và tên:', data.staffName, boldStyle, baseStyle),
              ),
              pw.Expanded(
                child: _buildInfoRow('Mã NV:', data.staffId.substring(0, 8), boldStyle, baseStyle),
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Row(
            children: [
              pw.Expanded(
                child: _buildInfoRow(
                  'Loại lương:',
                  data.salaryType == 'monthly' ? 'Lương tháng' : 'Lương ngày',
                  boldStyle,
                  baseStyle,
                ),
              ),
              pw.Expanded(
                child: _buildInfoRow(
                  'Ngày công:',
                  '${data.workDays} ngày',
                  boldStyle,
                  baseStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildInfoRow(
    String label,
    String value,
    pw.TextStyle labelStyle,
    pw.TextStyle valueStyle,
  ) {
    return pw.Row(
      children: [
        pw.Text(label, style: labelStyle),
        pw.SizedBox(width: 5),
        pw.Text(value, style: valueStyle),
      ],
    );
  }

  /// Bảng chi tiết lương
  static pw.Widget _buildSalaryTable(
    SalaryBreakdown data,
    pw.TextStyle headerStyle,
    pw.TextStyle baseStyle,
    pw.TextStyle boldStyle,
  ) {
    final rows = <pw.TableRow>[];

    // Header
    rows.add(
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.blue100),
        children: [
          _tableCell('STT', boldStyle, isHeader: true),
          _tableCell('KHOẢN MỤC', boldStyle, isHeader: true, align: pw.Alignment.centerLeft),
          _tableCell('CHI TIẾT', boldStyle, isHeader: true),
          _tableCell('SỐ TIỀN', boldStyle, isHeader: true, align: pw.Alignment.centerRight),
        ],
      ),
    );

    int stt = 0;

    // === THU NHẬP ===
    rows.add(_sectionRow('A. THU NHẬP', boldStyle));

    // 1. Lương cơ bản
    stt++;
    rows.add(_dataRow(
      stt.toString(),
      'Lương cơ bản',
      data.salaryType == 'monthly'
          ? 'Lương tháng'
          : '${data.workDays} ngày x ${_formatCurrency(data.baseSalary / 26)}',
      data.calculatedBaseSalary,
      baseStyle,
    ));

    // 2. Hoa hồng bán hàng
    if (data.calculatedSaleComm > 0) {
      stt++;
      rows.add(_dataRow(
        stt.toString(),
        'Hoa hồng bán hàng',
        '${data.saleOrderCount} đơn - ${data.saleCommType == 'percent' ? '${data.saleCommValue}%' : 'Cố định'}',
        data.calculatedSaleComm,
        baseStyle,
      ));
    }

    // 3. Hoa hồng sửa chữa
    if (data.calculatedRepairComm > 0) {
      stt++;
      rows.add(_dataRow(
        stt.toString(),
        'Hoa hồng sửa chữa',
        '${data.repairOrderCount} đơn - ${data.repairCommType == 'percent' ? '${data.repairCommValue}%' : 'Cố định'}',
        data.calculatedRepairComm,
        baseStyle,
      ));
    }

    // 4. Phụ cấp
    if (data.calculatedAllowance > 0) {
      stt++;
      rows.add(_dataRow(
        stt.toString(),
        'Phụ cấp',
        'Xăng xe, ăn trưa, điện thoại...',
        data.calculatedAllowance,
        baseStyle,
      ));
    }

    // 5. Làm thêm giờ
    if (data.calculatedOT > 0) {
      stt++;
      rows.add(_dataRow(
        stt.toString(),
        'Làm thêm giờ (OT)',
        '${data.overtimeHours.toStringAsFixed(1)}h x ${data.overtimeRate.toStringAsFixed(0)}%',
        data.calculatedOT,
        baseStyle,
      ));
    }

    // 6. Thưởng đạt chỉ tiêu
    if (data.calculatedBonus > 0) {
      stt++;
      rows.add(_dataRow(
        stt.toString(),
        'Thưởng đạt chỉ tiêu',
        'Đạt/vượt target tháng',
        data.calculatedBonus,
        baseStyle,
      ));
    }

    // 7. Thưởng tùy chỉnh
    for (final bonus in data.customBonuses) {
      stt++;
      rows.add(_dataRow(
        stt.toString(),
        '🎉 ${bonus.name}',
        bonus.note ?? 'Thưởng',
        bonus.amount,
        baseStyle,
        isBonus: true,
      ));
    }

    // Tổng thu nhập
    rows.add(_subtotalRow('TỔNG THU NHẬP (GROSS)', data.grossIncome, boldStyle));

    // === KHẤU TRỪ ===
    if (data.totalDeductions > 0) {
      rows.add(_sectionRow('B. KHẤU TRỪ', boldStyle, isDeduction: true));

      // Trừ đi muộn
      if (data.lateDeduction > 0) {
        stt++;
        rows.add(_dataRow(
          stt.toString(),
          'Trừ đi muộn',
          '${data.lateDays} lần',
          -data.lateDeduction,
          baseStyle,
          isNegative: true,
        ));
      }

      // Trừ về sớm
      if (data.earlyLeaveDeduction > 0) {
        stt++;
        rows.add(_dataRow(
          stt.toString(),
          'Trừ về sớm',
          '${data.earlyLeaveDays} lần',
          -data.earlyLeaveDeduction,
          baseStyle,
          isNegative: true,
        ));
      }

      // Trừ nghỉ quá phép
      if (data.absenceDeduction > 0) {
        stt++;
        rows.add(_dataRow(
          stt.toString(),
          'Nghỉ quá phép',
          '${data.absentDays} ngày',
          -data.absenceDeduction,
          baseStyle,
          isNegative: true,
        ));
      }

      // Khấu trừ tùy chỉnh
      for (final deduct in data.customDeductions) {
        stt++;
        rows.add(_dataRow(
          stt.toString(),
          '📌 ${deduct.name}',
          deduct.note ?? 'Khấu trừ',
          -deduct.amount,
          baseStyle,
          isNegative: true,
        ));
      }

      // BHXH
      if (data.socialInsurance > 0) {
        stt++;
        rows.add(_dataRow(
          stt.toString(),
          'BHXH',
          '8% lương đóng BH',
          -data.socialInsurance,
          baseStyle,
          isNegative: true,
        ));
      }

      // BHYT
      if (data.healthInsurance > 0) {
        stt++;
        rows.add(_dataRow(
          stt.toString(),
          'BHYT',
          '1.5% lương đóng BH',
          -data.healthInsurance,
          baseStyle,
          isNegative: true,
        ));
      }

      // BHTN
      if (data.unemploymentInsurance > 0) {
        stt++;
        rows.add(_dataRow(
          stt.toString(),
          'BHTN',
          '1% lương đóng BH',
          -data.unemploymentInsurance,
          baseStyle,
          isNegative: true,
        ));
      }

      // Thuế TNCN
      if (data.personalIncomeTax > 0) {
        stt++;
        rows.add(_dataRow(
          stt.toString(),
          'Thuế TNCN',
          'Theo biểu thuế lũy tiến',
          -data.personalIncomeTax,
          baseStyle,
          isNegative: true,
        ));
      }

      // Tổng khấu trừ
      rows.add(_subtotalRow(
        'TỔNG KHẤU TRỪ',
        -data.totalDeductions,
        boldStyle,
        isNegative: true,
      ));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FixedColumnWidth(35),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      children: rows,
    );
  }

  static pw.Widget _tableCell(
    String text,
    pw.TextStyle style, {
    bool isHeader = false,
    pw.Alignment align = pw.Alignment.center,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      alignment: align,
      child: pw.Text(text, style: style),
    );
  }

  static pw.TableRow _sectionRow(String title, pw.TextStyle boldStyle, {bool isDeduction = false}) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(
        color: isDeduction ? PdfColors.red50 : PdfColors.green50,
      ),
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(''),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(
            title,
            style: boldStyle.copyWith(
              color: isDeduction ? PdfColors.red800 : PdfColors.green800,
            ),
          ),
        ),
        pw.Container(padding: const pw.EdgeInsets.all(6)),
        pw.Container(padding: const pw.EdgeInsets.all(6)),
      ],
    );
  }

  static pw.TableRow _dataRow(
    String stt,
    String name,
    String detail,
    double amount,
    pw.TextStyle baseStyle, {
    bool isNegative = false,
    bool isBonus = false,
  }) {
    final color = isNegative
        ? PdfColors.red700
        : isBonus
            ? PdfColors.green700
            : PdfColors.black;

    return pw.TableRow(
      children: [
        _tableCell(stt, baseStyle),
        _tableCell(name, baseStyle, align: pw.Alignment.centerLeft),
        _tableCell(detail, baseStyle),
        _tableCell(
          _formatCurrency(amount),
          baseStyle.copyWith(color: color),
          align: pw.Alignment.centerRight,
        ),
      ],
    );
  }

  static pw.TableRow _subtotalRow(
    String title,
    double amount,
    pw.TextStyle boldStyle, {
    bool isNegative = false,
  }) {
    final color = isNegative ? PdfColors.red800 : PdfColors.blue800;
    final bgColor = isNegative ? PdfColors.red100 : PdfColors.blue100;

    return pw.TableRow(
      decoration: pw.BoxDecoration(color: bgColor),
      children: [
        pw.Container(padding: const pw.EdgeInsets.all(6)),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          child: pw.Text(title, style: boldStyle.copyWith(color: color)),
        ),
        pw.Container(padding: const pw.EdgeInsets.all(6)),
        pw.Container(
          padding: const pw.EdgeInsets.all(6),
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            _formatCurrency(amount),
            style: boldStyle.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  /// Tổng kết
  static pw.Widget _buildSummary(
    SalaryBreakdown data,
    pw.TextStyle headerStyle,
    pw.TextStyle boldStyle,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(15),
      decoration: pw.BoxDecoration(
        color: PdfColors.green100,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColors.green400, width: 2),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'THỰC NHẬN (NET)',
                style: headerStyle.copyWith(color: PdfColors.green900),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Bằng chữ: ${_numberToVietnamese(data.totalSalary.round())}',
                style: pw.TextStyle(
                  font: boldStyle.font,
                  fontSize: 9,
                  color: PdfColors.green800,
                  fontStyle: pw.FontStyle.italic,
                ),
              ),
            ],
          ),
          pw.Text(
            _formatCurrency(data.totalSalary),
            style: pw.TextStyle(
              font: boldStyle.font,
              fontSize: 22,
              color: PdfColors.green900,
            ),
          ),
        ],
      ),
    );
  }

  /// Chữ ký
  static pw.Widget _buildSignatures(
    pw.TextStyle baseStyle,
    pw.TextStyle boldStyle,
  ) {
    final now = DateTime.now();
    final dateStr =
        'Ngày ${now.day} tháng ${now.month} năm ${now.year}';

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        // Người lập
        pw.Column(
          children: [
            pw.Text('Người lập phiếu', style: boldStyle),
            pw.SizedBox(height: 5),
            pw.Text('(Ký, ghi rõ họ tên)', style: baseStyle),
            pw.SizedBox(height: 40),
            pw.Container(
              width: 100,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide()),
              ),
            ),
          ],
        ),
        // Ngày tháng và Giám đốc
        pw.Column(
          children: [
            pw.Text(dateStr, style: baseStyle),
            pw.SizedBox(height: 5),
            pw.Text('Giám đốc/Chủ cửa hàng', style: boldStyle),
            pw.Text('(Ký, đóng dấu)', style: baseStyle),
            pw.SizedBox(height: 40),
            pw.Container(
              width: 100,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide()),
              ),
            ),
          ],
        ),
        // Nhân viên
        pw.Column(
          children: [
            pw.Text('Người nhận lương', style: boldStyle),
            pw.SizedBox(height: 5),
            pw.Text('(Ký, ghi rõ họ tên)', style: baseStyle),
            pw.SizedBox(height: 40),
            pw.Container(
              width: 100,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide()),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Footer
  static pw.Widget _buildFooter(
    pw.TextStyle smallStyle,
    pw.TextStyle italicStyle,
  ) {
    return pw.Column(
      children: [
        pw.Divider(color: PdfColors.grey400),
        pw.SizedBox(height: 5),
        pw.Text(
          'Phiếu lương được tạo tự động bởi phần mềm Quản Lý Shop',
          style: italicStyle.copyWith(color: PdfColors.grey600),
        ),
        pw.Text(
          'In lúc: ${DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())}',
          style: smallStyle.copyWith(color: PdfColors.grey500),
        ),
      ],
    );
  }

  /// Chuyển số thành chữ tiếng Việt
  static String _numberToVietnamese(int number) {
    if (number == 0) return 'Không đồng';

    final units = ['', 'một', 'hai', 'ba', 'bốn', 'năm', 'sáu', 'bảy', 'tám', 'chín'];
    final groups = ['', 'nghìn', 'triệu', 'tỷ'];

    String result = '';
    int groupIndex = 0;

    while (number > 0) {
      int group = number % 1000;
      if (group > 0) {
        String groupStr = _threeDigitsToVietnamese(group, units);
        result = '$groupStr ${groups[groupIndex]} $result';
      }
      number ~/= 1000;
      groupIndex++;
    }

    result = result.trim();
    // Capitalize first letter
    if (result.isNotEmpty) {
      result = result[0].toUpperCase() + result.substring(1);
    }
    return '$result đồng';
  }

  static String _threeDigitsToVietnamese(int number, List<String> units) {
    int hundreds = number ~/ 100;
    int tens = (number % 100) ~/ 10;
    int ones = number % 10;

    String result = '';

    if (hundreds > 0) {
      result += '${units[hundreds]} trăm ';
    }

    if (tens > 0) {
      if (tens == 1) {
        result += 'mười ';
      } else {
        result += '${units[tens]} mươi ';
      }
    } else if (hundreds > 0 && ones > 0) {
      result += 'lẻ ';
    }

    if (ones > 0) {
      if (tens > 1 && ones == 1) {
        result += 'mốt';
      } else if (tens >= 1 && ones == 5) {
        result += 'lăm';
      } else {
        result += units[ones];
      }
    }

    return result.trim();
  }

  /// In phiếu lương
  static Future<void> printSalarySlip(SalaryBreakdown data) async {
    final pdfData = await generateSalarySlipPdf(data);
    await Printing.layoutPdf(
      onLayout: (format) async => pdfData,
      name: 'Phieu_luong_${data.staffName}_T${data.month}_${data.year}',
    );
  }

  /// Chia sẻ PDF
  static Future<void> shareSalarySlip(SalaryBreakdown data) async {
    final pdfData = await generateSalarySlipPdf(data);
    await Printing.sharePdf(
      bytes: pdfData,
      filename: 'Phieu_luong_${data.staffName}_T${data.month}_${data.year}.pdf',
    );
  }

  /// Tạo PDF bảng lương tổng hợp cho tất cả nhân viên
  static Future<Uint8List> generateAllStaffSalaryPdf(
    List<SalaryBreakdown> salaries,
    int month,
    int year,
  ) async {
    final shopInfo = await _getShopInfo();

    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final fontBold = await PdfGoogleFonts.robotoBold();

    final baseStyle = pw.TextStyle(font: font, fontSize: 9);
    final boldStyle = pw.TextStyle(font: fontBold, fontSize: 9);
    final headerStyle = pw.TextStyle(font: fontBold, fontSize: 12);
    final titleStyle = pw.TextStyle(font: fontBold, fontSize: 16);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => pw.Column(
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  shopInfo['name']?.toString().toUpperCase() ?? 'CỬA HÀNG',
                  style: headerStyle,
                ),
                pw.Text(
                  'Trang ${context.pageNumber}/${context.pagesCount}',
                  style: baseStyle,
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Center(
              child: pw.Text(
                'BẢNG LƯƠNG THÁNG ${month.toString().padLeft(2, '0')}/$year',
                style: titleStyle.copyWith(color: PdfColors.blue800),
              ),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Column(
          children: [
            pw.Divider(),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'In lúc: ${DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())}',
                  style: baseStyle,
                ),
                pw.Text(
                  'Phần mềm Quản Lý Shop',
                  style: baseStyle,
                ),
              ],
            ),
          ],
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400),
            columnWidths: {
              0: const pw.FixedColumnWidth(30),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FixedColumnWidth(40),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(1.2),
              6: const pw.FlexColumnWidth(1.2),
              7: const pw.FlexColumnWidth(1.2),
              8: const pw.FlexColumnWidth(1.2),
              9: const pw.FlexColumnWidth(1.5),
            },
            children: [
              // Header
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue100),
                children: [
                  _tableCell('STT', boldStyle, isHeader: true),
                  _tableCell('HỌ TÊN', boldStyle, isHeader: true),
                  _tableCell('CÔNG', boldStyle, isHeader: true),
                  _tableCell('LƯƠNG CB', boldStyle, isHeader: true),
                  _tableCell('HOA HỒNG', boldStyle, isHeader: true),
                  _tableCell('PHỤ CẤP', boldStyle, isHeader: true),
                  _tableCell('THƯỞNG', boldStyle, isHeader: true),
                  _tableCell('GROSS', boldStyle, isHeader: true),
                  _tableCell('KHẤU TRỪ', boldStyle, isHeader: true),
                  _tableCell('THỰC NHẬN', boldStyle, isHeader: true),
                ],
              ),
              // Data rows
              ...salaries.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                final totalComm = s.calculatedSaleComm + s.calculatedRepairComm;
                final totalBonus = s.calculatedBonus +
                    s.customBonuses.fold(0.0, (sum, b) => sum + b.amount);

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: i % 2 == 0 ? PdfColors.white : PdfColors.grey100,
                  ),
                  children: [
                    _tableCell('${i + 1}', baseStyle),
                    _tableCell(s.staffName, baseStyle, align: pw.Alignment.centerLeft),
                    _tableCell('${s.workDays}', baseStyle),
                    _tableCell(_formatCurrency(s.calculatedBaseSalary), baseStyle),
                    _tableCell(_formatCurrency(totalComm), baseStyle),
                    _tableCell(_formatCurrency(s.calculatedAllowance), baseStyle),
                    _tableCell(_formatCurrency(totalBonus), baseStyle),
                    _tableCell(
                      _formatCurrency(s.grossIncome),
                      boldStyle.copyWith(color: PdfColors.blue700),
                    ),
                    _tableCell(
                      _formatCurrency(s.totalDeductions),
                      baseStyle.copyWith(color: PdfColors.red700),
                    ),
                    _tableCell(
                      _formatCurrency(s.totalSalary),
                      boldStyle.copyWith(color: PdfColors.green800),
                    ),
                  ],
                );
              }),
              // Total row
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.green100),
                children: [
                  _tableCell('', boldStyle),
                  _tableCell('TỔNG CỘNG', boldStyle),
                  _tableCell('', boldStyle),
                  _tableCell(
                    _formatCurrency(salaries.fold(0.0, (s, d) => s + d.calculatedBaseSalary)),
                    boldStyle,
                  ),
                  _tableCell(
                    _formatCurrency(salaries.fold(0.0, (s, d) => s + d.calculatedSaleComm + d.calculatedRepairComm)),
                    boldStyle,
                  ),
                  _tableCell(
                    _formatCurrency(salaries.fold(0.0, (s, d) => s + d.calculatedAllowance)),
                    boldStyle,
                  ),
                  _tableCell(
                    _formatCurrency(salaries.fold(0.0, (s, d) => s + d.calculatedBonus)),
                    boldStyle,
                  ),
                  _tableCell(
                    _formatCurrency(salaries.fold(0.0, (s, d) => s + d.grossIncome)),
                    boldStyle.copyWith(color: PdfColors.blue800),
                  ),
                  _tableCell(
                    _formatCurrency(salaries.fold(0.0, (s, d) => s + d.totalDeductions)),
                    boldStyle.copyWith(color: PdfColors.red800),
                  ),
                  _tableCell(
                    _formatCurrency(salaries.fold(0.0, (s, d) => s + d.totalSalary)),
                    boldStyle.copyWith(color: PdfColors.green900, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 30),
          // Signatures
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                children: [
                  pw.Text('Người lập bảng', style: boldStyle),
                  pw.SizedBox(height: 50),
                  pw.Text('_______________', style: baseStyle),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text('Kế toán', style: boldStyle),
                  pw.SizedBox(height: 50),
                  pw.Text('_______________', style: baseStyle),
                ],
              ),
              pw.Column(
                children: [
                  pw.Text(
                    'Ngày ${DateTime.now().day} tháng ${DateTime.now().month} năm ${DateTime.now().year}',
                    style: baseStyle,
                  ),
                  pw.Text('Giám đốc', style: boldStyle),
                  pw.SizedBox(height: 50),
                  pw.Text('_______________', style: baseStyle),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    return pdf.save();
  }

  /// In bảng lương tổng hợp
  static Future<void> printAllStaffSalary(
    List<SalaryBreakdown> salaries,
    int month,
    int year,
  ) async {
    final pdfData = await generateAllStaffSalaryPdf(salaries, month, year);
    await Printing.layoutPdf(
      onLayout: (format) async => pdfData,
      name: 'Bang_luong_T${month}_$year',
    );
  }

  /// Chia sẻ bảng lương tổng hợp
  static Future<void> shareAllStaffSalary(
    List<SalaryBreakdown> salaries,
    int month,
    int year,
  ) async {
    final pdfData = await generateAllStaffSalaryPdf(salaries, month, year);
    await Printing.sharePdf(
      bytes: pdfData,
      filename: 'Bang_luong_T${month}_$year.pdf',
    );
  }
}

void debugPrint(String message) {
  // ignore: avoid_print
  print(message);
}
