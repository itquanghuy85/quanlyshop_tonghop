import 'package:flutter/material.dart';
import '../utils/qr_parser.dart';
import '../data/db_helper.dart';
import '../views/sale_detail_view.dart';
import '../views/repair_detail_view.dart';

class QRRouter {
  static const String TYPE_ORDER = 'ORDER';
  static const String TYPE_REPAIR = 'REPAIR';
  static const String TYPE_PHONE = 'PHONE';
  static const String TYPE_ACCESSORY = 'ACCESSORY';

  /// Central QR routing method
  /// Automatically routes based on QR type
  static Future<void> routeQR(BuildContext context, String qrData) async {
    try {
      // Parse QR into key-value map
      final qrMap = QRParser.parse(qrData);
      
      // Check for legacy QR formats first
      if (_handleLegacyQRFormat(context, qrData, qrMap)) {
        return;
      }
      
      // Validate QR for new format
      if (!QRParser.isValidQR(qrMap)) {
        _showError(context, 'QR không hợp lệ - thiếu trường type');
        return;
      }
      
      final type = QRParser.getType(qrMap)!;
      
      // Route based on type
      switch (type) {
        case TYPE_ORDER:
          await _handleOrderQR(context, qrMap);
          break;
        case TYPE_REPAIR:
          await _handleRepairQR(context, qrMap);
          break;
        case TYPE_PHONE:
          await _handlePhoneInventoryQR(context, qrMap);
          break;
        case TYPE_ACCESSORY:
          await _handleAccessoryInventoryQR(context, qrMap);
          break;
        default:
          _showError(context, 'Loại QR không được hỗ trợ: $type');
      }
    } catch (e) {
      _showError(context, 'Lỗi xử lý QR: $e');
    }
  }

  /// Handle legacy QR formats (without type field)
  static bool _handleLegacyQRFormat(BuildContext context, String qrData, Map<String, String> qrMap) {
    // Handle repair_check:ID format
    if (qrData.startsWith('repair_check:')) {
      final repairId = qrData.substring('repair_check:'.length);
      if (repairId.isNotEmpty) {
        _handleLegacyRepairQR(context, repairId);
        return true;
      }
    }
    
    // Handle sale_check:ID format (if exists)
    if (qrData.startsWith('sale_check:')) {
      final saleId = qrData.substring('sale_check:'.length);
      if (saleId.isNotEmpty) {
        _handleLegacySaleQR(context, saleId);
        return true;
      }
    }
    
    // Handle check_inv:ID format (inventory check)
    if (qrData.startsWith('check_inv:')) {
      final productId = qrData.substring('check_inv:'.length);
      if (productId.isNotEmpty) {
        _handleLegacyInventoryQR(context, productId);
        return true;
      }
    }
    
    return false; // Not a legacy format
  }

  /// Handle ORDER type QR
  static Future<void> _handleOrderQR(BuildContext context, Map<String, String> qrMap) async {
    final orderId = qrMap['id'];
    if (orderId == null || orderId.isEmpty) {
      _showError(context, 'QR đơn hàng thiếu ID');
      return;
    }

    try {
      final db = DBHelper();
      final order = await db.getSaleByFirestoreId(orderId);
      if (order == null) {
        _showError(context, 'Không tìm thấy đơn hàng với ID: $orderId');
        return;
      }

      // Navigate to Sale Order Detail
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SaleDetailView(sale: order),
        ),
      );
    } catch (e) {
      _showError(context, 'Lỗi khi tải đơn hàng: $e');
    }
  }

  /// Handle REPAIR type QR
  static Future<void> _handleRepairQR(BuildContext context, Map<String, String> qrMap) async {
    final repairId = qrMap['id'];
    if (repairId == null || repairId.isEmpty) {
      _showError(context, 'QR đơn sửa chữa thiếu ID');
      return;
    }

    try {
      final db = DBHelper();
      final repair = await db.getRepairByFirestoreId(repairId);
      if (repair == null) {
        _showError(context, 'Không tìm thấy đơn sửa chữa với ID: $repairId');
        return;
      }

      // Navigate to Repair Order Detail
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RepairDetailView(repair: repair!),
        ),
      );
    } catch (e) {
      _showError(context, 'Lỗi khi tải đơn sửa chữa: $e');
    }
  }

  /// Handle PHONE inventory type QR
  static Future<void> _handlePhoneInventoryQR(BuildContext context, Map<String, String> qrMap) async {
    final imei = qrMap['imei'];
    final code = qrMap['code'];

    if (imei == null || imei.isEmpty) {
      _showError(context, 'QR kiểm tra điện thoại thiếu IMEI');
      return;
    }

    // Find phone by IMEI and perform inventory check
    final db = DBHelper();
    final product = await db.getProductByImei(imei);

    if (product == null) {
      _showError(context, 'Không tìm thấy điện thoại với IMEI: $imei');
      return;
    }

    // Show inventory check result
    _showInventoryResult(context, 'Điện thoại', product.name, imei, code);
  }

  /// Handle ACCESSORY inventory type QR
  static Future<void> _handleAccessoryInventoryQR(BuildContext context, Map<String, String> qrMap) async {
    final code = qrMap['code'];
    if (code == null || code.isEmpty) {
      _showError(context, 'QR kiểm tra phụ kiện thiếu code');
      return;
    }

    // Find accessory by code and perform inventory check
    final db = DBHelper();
    final product = await db.getProductByFirestoreId(code);

    if (product == null) {
      _showError(context, 'Không tìm thấy phụ kiện với code: $code');
      return;
    }

    // Show inventory check result
    _showInventoryResult(context, 'Phụ kiện', product.name, null, code);
  }

  /// Show inventory check result
  static void _showInventoryResult(BuildContext context, String type, String name, String? imei, String? code) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Kết quả kiểm tra $type'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tên: $name'),
            if (imei != null) Text('IMEI: $imei'),
            if (code != null) Text('Code: $code'),
            const SizedBox(height: 16),
            const Text('✅ Sản phẩm có trong kho', style: TextStyle(color: Colors.green)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ĐÓNG'),
          ),
        ],
      ),
    );
  }

  /// Handle legacy repair QR format
  static Future<void> _handleLegacyRepairQR(BuildContext context, String repairId) async {
    try {
      final db = DBHelper();
      var repair = await db.getRepairByFirestoreId(repairId);
      if (repair == null) {
        // Try to find by createdAt timestamp
        final repairs = await db.getAllRepairs();
        final foundRepair = repairs.where((r) => r.createdAt.toString() == repairId).toList();
        if (foundRepair.isNotEmpty) {
          repair = foundRepair.first;
        }
      }
      
      if (repair == null) {
        _showError(context, 'Không tìm thấy đơn sửa chữa với ID: $repairId');
        return;
      }

      // Navigate to Repair Order Detail
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => RepairDetailView(repair: repair!),
        ),
      );
    } catch (e) {
      _showError(context, 'Lỗi khi tải đơn sửa chữa: $e');
    }
  }

  /// Handle legacy sale QR format
  static Future<void> _handleLegacySaleQR(BuildContext context, String saleId) async {
    try {
      final db = DBHelper();
      final sale = await db.getSaleByFirestoreId(saleId);
      if (sale == null) {
        _showError(context, 'Không tìm thấy đơn bán hàng với ID: $saleId');
        return;
      }

      // Navigate to Sale Order Detail
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SaleDetailView(sale: sale),
        ),
      );
    } catch (e) {
      _showError(context, 'Lỗi khi tải đơn bán hàng: $e');
    }
  }

  /// Handle legacy inventory QR format
  static Future<void> _handleLegacyInventoryQR(BuildContext context, String productId) async {
    try {
      final db = DBHelper();
      final product = await db.getProductById(int.tryParse(productId) ?? -1);
      if (product == null) {
        _showError(context, 'Không tìm thấy sản phẩm với ID: $productId');
        return;
      }

      _showInventoryResult(context, 'sản phẩm', product.name, product.imei, null);
    } catch (e) {
      _showError(context, 'Lỗi khi kiểm tra sản phẩm: $e');
    }
  }

  /// Show error message
  static void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}