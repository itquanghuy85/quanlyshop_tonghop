import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../data/db_helper.dart';
import '../models/attendance_model.dart';
import '../models/product_model.dart';
import '../models/repair_model.dart';
import '../models/sale_order_model.dart';
import '../models/sales_return_model.dart';
import 'firestore_service.dart';
import 'firestore_write_helper.dart';
import 'sales_return_service.dart';
import 'sync_service.dart';
import 'encryption_service.dart';
import 'user_service.dart';

/// Service tạo dữ liệu mẫu toàn diện cho mục đích demo/kiểm thử.
/// Bao gồm: sản phẩm, bán hàng, sửa chữa, công nợ, chấm công,
/// lương nhân viên, nhà cung cấp, cộng đồng, chat, tài chính.
class TestDataService {
  static final _db = DBHelper();
  static final _fs = FirebaseFirestore.instance;

  static const String _scenarioTagPrefix = 'AUTO_FLOW_V1';

  // ─────────────────────────────────────────────
  // ENTRY POINT: seed toàn bộ dữ liệu
  // ─────────────────────────────────────────────
  static Future<String> seedTestData() async {
    final log = StringBuffer();
    final now = DateTime.now();
    final todayMs = now.millisecondsSinceEpoch;
    final shopId = UserService.getShopIdSync() ?? '';
    final userName = await UserService.getCurrentUserName();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    debugPrint('🧪 TEST DATA: Bắt đầu tạo dữ liệu mẫu cho shop $shopId...');

    // ══════════════════════════════════════════════
    // 1. NHÀ CUNG CẤP (Suppliers)
    // ══════════════════════════════════════════════
    final supplierIds = await _seedSuppliers(shopId, log);

    // ══════════════════════════════════════════════
    // 2. SẢN PHẨM (Products)
    // ══════════════════════════════════════════════
    final products = await _seedProducts(shopId, todayMs, log);

    // ══════════════════════════════════════════════
    // 3. BÁN HÀNG (Sales)
    // ══════════════════════════════════════════════
    final sales = await _seedSales(products, userName, todayMs, log);

    // ══════════════════════════════════════════════
    // 4. TRẢ HÀNG (Returns)
    // ══════════════════════════════════════════════
    await _seedReturns(products, sales, log);

    // ══════════════════════════════════════════════
    // 5. SỬA CHỮA (Repairs)
    // ══════════════════════════════════════════════
    await _seedRepairs(shopId, userName, uid, todayMs, log);

    // ══════════════════════════════════════════════
    // 6. CÔNG NỢ KHÁCH HÀNG (Customer Debts)
    // ══════════════════════════════════════════════
    await _seedDebts(shopId, todayMs, log);

    // ══════════════════════════════════════════════
    // 7. CHI PHÍ / THU NHẬP KHÁC (Expenses)
    // ══════════════════════════════════════════════
    await _seedExpenses(shopId, todayMs, log);

    // ══════════════════════════════════════════════
    // 8. NHÂN VIÊN & LƯƠNG (Salary Settings)
    // ══════════════════════════════════════════════
    await _seedEmployeeSalarySettings(shopId, uid, userName, todayMs, log);

    // ══════════════════════════════════════════════
    // 9. CHẤM CÔNG (Attendance)
    // ══════════════════════════════════════════════
    await _seedAttendance(shopId, uid, userName, todayMs, log);

    // ══════════════════════════════════════════════
    // 10. CỘNG ĐỒNG (Community Posts)
    // ══════════════════════════════════════════════
    await _seedCommunityPosts(shopId, uid, userName, todayMs, log);

    // ══════════════════════════════════════════════
    // 11. CHAT NỘI BỘ (Chat Messages)
    // ══════════════════════════════════════════════
    await _seedChatMessages(shopId, uid, userName, todayMs, log);

    // ══════════════════════════════════════════════
    // 12. NHẬP HÀNG (Import Orders)
    // ══════════════════════════════════════════════
    await _seedImportOrders(shopId, supplierIds, uid, userName, todayMs, log);

    log.writeln('\n✅ Hoàn thành tạo dữ liệu demo. Vui lòng reload app.');
    debugPrint('🧪 TEST DATA: Seed hoàn thành!');
    return log.toString();
  }

  // ─────────────────────────────────────────────
  // 1. Nhà cung cấp
  // ─────────────────────────────────────────────
  static Future<Map<String, String>> _seedSuppliers(
    String shopId,
    StringBuffer log,
  ) async {
    final ids = <String, String>{};
    final suppliers = [
      {
        'name': 'CÔNG TY TNHH APPLE VIỆT NAM',
        'phone': '02838123456',
        'email': 'supply@applevn.com',
        'address': '300 Điện Biên Phủ, Q3, TP.HCM',
        'taxCode': '0312345678',
        'note': 'NCC chính hàng Apple',
      },
      {
        'name': 'KHO SÌ SAMSUNG MIỀN NAM',
        'phone': '02822345678',
        'email': 'order@samsungmn.vn',
        'address': '56 Lê Lai, Q1, TP.HCM',
        'taxCode': '0323456789',
        'note': 'NCC Samsung chính hãng',
      },
      {
        'name': 'PHỤ KIỆN ĐIỆN THOẠI HOÀNG GIA',
        'phone': '0901888999',
        'email': 'hoanggiaphone@gmail.com',
        'address': 'Chợ Nhật Tảo, Q10, TP.HCM',
        'taxCode': '',
        'note': 'NCC phụ kiện giá sỉ',
      },
    ];

    for (final s in suppliers) {
      try {
        final docId =
            'sup_${DateTime.now().millisecondsSinceEpoch}_${s['name']!.hashCode.abs()}';
        final data = {
          'firestoreId': docId,
          'shopId': shopId,
          'name': s['name'],
          'phone': s['phone'],
          'email': s['email'],
          'address': s['address'],
          'taxCode': s['taxCode'],
          'note': s['note'],
          'totalDebt': 0,
          'totalPurchased': 0,
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
          'deleted': false,
        };
        await _fs.collection('suppliers').doc(docId).set(data);
        ids[s['name']!] = docId;
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('⚠️ seedSuppliers: ${s['name']} - $e');
      }
    }
    log.writeln('✅ ${ids.length} nhà cung cấp');
    return ids;
  }

  // ─────────────────────────────────────────────
  // 2. Sản phẩm
  // ─────────────────────────────────────────────
  static Future<List<Product>> _seedProducts(
    String shopId,
    int todayMs,
    StringBuffer log,
  ) async {
    final products = <Product>[];
    final productData = [
      {
        'name': 'IPHONE 15 PRO MAX 256GB',
        'imei': '350111222333441',
        'cost': 28000000,
        'price': 32000000,
        'type': 'DIEN_THOAI',
        'brand': 'APPLE',
        'color': 'ĐEN',
        'capacity': '256GB',
      },
      {
        'name': 'IPHONE 14 128GB',
        'imei': '350111222333442',
        'cost': 16000000,
        'price': 19500000,
        'type': 'DIEN_THOAI',
        'brand': 'APPLE',
        'color': 'TRẮNG',
        'capacity': '128GB',
      },
      {
        'name': 'SAMSUNG GALAXY S24 ULTRA 256GB',
        'imei': '350111222333443',
        'cost': 25000000,
        'price': 29900000,
        'type': 'DIEN_THOAI',
        'brand': 'SAMSUNG',
        'color': 'TÍM',
        'capacity': '256GB',
      },
      {
        'name': 'OPPO RENO 11 5G 256GB',
        'imei': '350111222333444',
        'cost': 7500000,
        'price': 9990000,
        'type': 'DIEN_THOAI',
        'brand': 'OPPO',
        'color': 'XANH',
        'capacity': '256GB',
      },
      {
        'name': 'ỐP LƯNG IPHONE 15 PRO',
        'imei': 'PKX-OL-001',
        'cost': 50000,
        'price': 150000,
        'type': 'PHU_KIEN',
        'brand': 'KHÁC',
        'qty': 10,
      },
      {
        'name': 'CÁP SẠC TYPE-C 1M',
        'imei': 'PKX-CAP-001',
        'cost': 30000,
        'price': 80000,
        'type': 'PHU_KIEN',
        'brand': 'KHÁC',
        'qty': 20,
      },
      {
        'name': 'TAI NGHE BLUETOOTH JBL TUNE 510BT',
        'imei': 'PKX-TN-001',
        'cost': 200000,
        'price': 450000,
        'type': 'PHU_KIEN',
        'brand': 'JBL',
        'qty': 5,
      },
      {
        'name': 'KÍNH CƯỜNG LỰC IPHONE 15 (2 LỚP)',
        'imei': 'PKX-KCL-001',
        'cost': 15000,
        'price': 80000,
        'type': 'PHU_KIEN',
        'brand': 'KHÁC',
        'qty': 30,
      },
      {
        'name': 'PIN IPHONE 14 CHÍNH HÃNG',
        'imei': 'LK-PIN-001',
        'cost': 250000,
        'price': 500000,
        'type': 'LINH_KIEN',
        'brand': 'APPLE',
        'qty': 5,
      },
      {
        'name': 'MÀN HÌNH SAMSUNG S23 AMOLED',
        'imei': 'LK-MH-001',
        'cost': 1200000,
        'price': 1800000,
        'type': 'LINH_KIEN',
        'brand': 'SAMSUNG',
        'qty': 3,
      },
    ];

    for (final pd in productData) {
      try {
        final p = Product(
          name: pd['name'] as String,
          brand: pd['brand'] as String,
          imei: pd['imei'] as String,
          cost: pd['cost'] as int,
          price: pd['price'] as int,
          type: pd['type'] as String,
          color: pd['color'] as String? ?? '',
          capacity: pd['capacity'] as String? ?? '',
          condition: 'Mới',
          status: 1,
          quantity: (pd['qty'] as int?) ?? 1,
          description: '',
          createdAt: todayMs - 86400000 * 3,
        );
        final fsId = await FirestoreService.addProduct(p);
        p.firestoreId = fsId;
        p.shopId = shopId; // Ensure shopId is set so inventory view can find it
        await _db.upsertProduct(p);
        final dbProduct = await _db.getProductByImei(p.imei ?? '');
        if (dbProduct != null) p.id = dbProduct.id;
        products.add(p);
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        debugPrint('⚠️ seedProducts: ${pd['name']} - $e');
      }
    }
    log.writeln('✅ ${products.length} sản phẩm (điện thoại, phụ kiện, linh kiện)');
    return products;
  }

  // ─────────────────────────────────────────────
  // 3. Bán hàng
  // ─────────────────────────────────────────────
  static Future<List<SaleOrder>> _seedSales(
    List<Product> products,
    String userName,
    int todayMs,
    StringBuffer log,
  ) async {
    final sales = <SaleOrder>[];
    if (products.isEmpty) return sales;

    final saleData = [
      {
        'customerName': 'NGUYỄN VĂN ANH',
        'phone': '0901234567',
        'address': 'Q1 TP.HCM',
        'productNames': 'IPHONE 15 PRO MAX 256GB x1, ỐP LƯNG IPHONE 15 PRO x2',
        'totalPrice': 32300000,
        'totalCost': 28100000,
        'discount': 0,
        'paymentMethod': 'TIỀN MẶT',
        'hoursAgo': 6,
        'warranty': '12 tháng',
      },
      {
        'customerName': 'TRẦN THỊ MAI',
        'phone': '0912345678',
        'address': 'Q7 TP.HCM',
        'productNames': 'SAMSUNG GALAXY S24 ULTRA 256GB x1',
        'totalPrice': 29400000,
        'totalCost': 25000000,
        'discount': 500000,
        'paymentMethod': 'CHUYỂN KHOẢN',
        'hoursAgo': 5,
        'warranty': '12 tháng',
      },
      {
        'customerName': 'LÊ HOÀNG NAM',
        'phone': '0923456789',
        'address': 'THỦ ĐỨC',
        'productNames': 'OPPO RENO 11 5G 256GB x1, CÁP SẠC TYPE-C 1M x3',
        'totalPrice': 10230000,
        'totalCost': 7590000,
        'discount': 100000,
        'paymentMethod': 'TIỀN MẶT',
        'hoursAgo': 4,
        'warranty': '12 tháng',
      },
      {
        'customerName': 'PHẠM MINH TUẤN',
        'phone': '0934567890',
        'address': 'BÌNH THẠNH',
        'productNames': 'IPHONE 14 128GB x1, TAI NGHE BLUETOOTH JBL TUNE 510BT x1',
        'totalPrice': 19950000,
        'totalCost': 16200000,
        'discount': 0,
        'paymentMethod': 'CÔNG NỢ',
        'hoursAgo': 2,
        'warranty': '12 tháng',
      },
      {
        'customerName': 'HOÀNG THỊ LAN',
        'phone': '0945678901',
        'address': 'GÒ VẤP',
        'productNames': 'KÍNH CƯỜNG LỰC IPHONE 15 (2 LỚP) x5, CÁP SẠC TYPE-C 1M x2',
        'totalPrice': 560000,
        'totalCost': 135000,
        'discount': 0,
        'paymentMethod': 'TIỀN MẶT',
        'hoursAgo': 1,
        'warranty': '3 tháng',
      },
    ];

    for (final sd in saleData) {
      try {
        final sale = SaleOrder(
          customerName: sd['customerName'] as String,
          phone: sd['phone'] as String,
          isWalkIn: false,
          address: sd['address'] as String,
          productNames: sd['productNames'] as String,
          productImeis: '',
          totalPrice: sd['totalPrice'] as int,
          totalCost: sd['totalCost'] as int,
          discount: sd['discount'] as int,
          paymentMethod: sd['paymentMethod'] as String,
          sellerName: userName,
          soldAt: todayMs - 3600000 * (sd['hoursAgo'] as int),
          warranty: sd['warranty'] as String,
        );
        final saleId = await FirestoreService.addSale(sale);
        if (saleId != null) {
          sale.firestoreId = saleId;
          await _db.insertSale(sale);
          final dbSale = await _db.getSaleByFirestoreId(saleId);
          if (dbSale != null) sale.id = dbSale.id;
          sales.add(sale);
        }
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint('⚠️ seedSales: ${sd['customerName']} - $e');
      }
    }
    log.writeln('✅ ${sales.length} đơn bán hàng (tiền mặt, chuyển khoản, công nợ)');
    return sales;
  }

  // ─────────────────────────────────────────────
  // 4. Trả hàng
  // ─────────────────────────────────────────────
  static Future<void> _seedReturns(
    List<Product> products,
    List<SaleOrder> sales,
    StringBuffer log,
  ) async {
    if (sales.length < 3) {
      log.writeln('⚠️ Bỏ qua trả hàng (không đủ đơn)');
      return;
    }
    try {
      final sale3 = sales[2]; // Oppo sale
      if (sale3.id != null && sale3.id! > 0 && products.length >= 4) {
        final returnResult = await SalesReturnService.processReturn(
          salesOrderId: sale3.id!,
          salesOrderFirestoreId: sale3.firestoreId,
          customerName: sale3.customerName,
          customerPhone: sale3.phone,
          refundMethod: 'TIỀN MẶT',
          items: [
            SalesReturnItem(
              productId: products[3].id,
              productFirestoreId: products[3].firestoreId,
              productName: 'OPPO RENO 11 5G 256GB',
              productImei: '350111222333444',
              quantity: 1,
              price: 9990000,
              cost: 7500000,
              amount: 9990000,
            ),
          ],
          note: 'Khách đổi ý, chuyển sang Samsung S24',
        );
        if (returnResult['success'] == true) {
          log.writeln('✅ 1 phiếu trả hàng: Oppo Reno 11 — hoàn 9.99tr tiền mặt');
        }
      }
    } catch (e) {
      debugPrint('⚠️ seedReturns: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 5. Sửa chữa
  // ─────────────────────────────────────────────
  static Future<void> _seedRepairs(
    String shopId,
    String userName,
    String uid,
    int todayMs,
    StringBuffer log,
  ) async {
    final repairData = [
      {
        'customerName': 'VÕ THỊ BÍCH',
        'phone': '0956789012',
        'model': 'IPHONE 13 PRO MAX',
        'issue': 'Vỡ màn hình, không cảm ứng',
        'accessories': 'Không có phụ kiện',
        'partsUsed': 'Màn hình OLED chính hãng',
        'price': 2500000,
        'cost': 1200000,
        'status': 3, // Xong
        'paymentMethod': 'TIỀN MẶT',
        'hoursAgo': 8,
        'warranty': '3 tháng',
        'color': 'Xanh Alpine',
      },
      {
        'customerName': 'NGUYỄN THANH BÌNH',
        'phone': '0967890123',
        'model': 'SAMSUNG GALAXY A54',
        'issue': 'Pin chai, sạc không vào',
        'accessories': 'Cáp sạc',
        'partsUsed': 'Pin Samsung A54 chính hãng',
        'price': 450000,
        'cost': 180000,
        'status': 2, // Đang sửa
        'paymentMethod': 'CHUYỂN KHOẢN',
        'hoursAgo': 3,
        'warranty': '6 tháng',
        'color': 'Đen',
      },
      {
        'customerName': 'PHAN QUỐC HÙNG',
        'phone': '0978901234',
        'model': 'XIAOMI 13T PRO',
        'issue': 'Loa ngoài bị rè, mất tiếng',
        'accessories': 'Hộp máy',
        'partsUsed': 'Loa ngoài Xiaomi 13T',
        'price': 350000,
        'cost': 120000,
        'status': 1, // Mới nhận
        'paymentMethod': 'TIỀN MẶT',
        'hoursAgo': 1,
        'warranty': '3 tháng',
        'color': 'Bạc',
      },
      {
        'customerName': 'LÝ MỸ HẠNH',
        'phone': '0989012345',
        'model': 'IPHONE 12 MINI',
        'issue': 'Không nhận sim, mất sóng',
        'accessories': 'Không',
        'partsUsed': 'Khay SIM, ăng-ten trong',
        'price': 800000,
        'cost': 300000,
        'status': 4, // Đã giao
        'paymentMethod': 'TIỀN MẶT',
        'hoursAgo': 24,
        'warranty': '3 tháng',
        'color': 'Đỏ',
      },
      {
        'customerName': 'ĐẶNG MINH KHÔI',
        'phone': '0990123456',
        'model': 'OPPO FIND X7',
        'issue': 'Màn hình bị chảy mực, có sọc',
        'accessories': 'Ốp lưng',
        'partsUsed': 'Màn hình OLED Oppo Find X7',
        'price': 3200000,
        'cost': 2000000,
        'status': 3,
        'paymentMethod': 'CHUYỂN KHOẢN',
        'hoursAgo': 12,
        'warranty': '3 tháng',
        'color': 'Vàng',
      },
    ];

    int count = 0;
    for (final rd in repairData) {
      try {
        final createdAt = todayMs - 3600000 * (rd['hoursAgo'] as int);
        final repair = Repair(
          customerName: rd['customerName'] as String,
          phone: rd['phone'] as String,
          isWalkIn: false,
          model: rd['model'] as String,
          issue: rd['issue'] as String,
          accessories: rd['accessories'] as String,
          address: 'TP.HCM',
          warranty: rd['warranty'] as String,
          partsUsed: rd['partsUsed'] as String,
          status: rd['status'] as int,
          price: rd['price'] as int,
          cost: rd['cost'] as int,
          paymentMethod: rd['paymentMethod'] as String,
          createdAt: createdAt,
          createdBy: userName,
          createdByUid: uid,
          color: rd['color'] as String?,
          isSynced: true,
          deleted: false,
          services: [],
          shopId: shopId,
        );
        final fsId = await FirestoreService.addRepair(repair);
        if (fsId != null) {
          repair.firestoreId = fsId;
          await _db.upsertRepair(repair);
          count++;
        }
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        debugPrint('⚠️ seedRepairs: ${rd['customerName']} - $e');
      }
    }
    log.writeln('✅ $count đơn sửa chữa (trạng thái: nhận, sửa, xong, giao)');
  }

  // ─────────────────────────────────────────────
  // 6. Công nợ khách hàng
  // ─────────────────────────────────────────────
  static Future<void> _seedDebts(
    String shopId,
    int todayMs,
    StringBuffer log,
  ) async {
    final debts = [
      {
        'customerName': 'PHẠM MINH TUẤN',
        'phone': '0934567890',
        'address': 'Bình Thạnh, TP.HCM',
        'totalAmount': 19950000,
        'paidAmount': 5000000,
        'remainAmount': 14950000,
        'orderId': '',
        'note': 'Mua iPhone 14 + tai nghe, trả trước 5tr',
        'daysAgo': 0,
      },
      {
        'customerName': 'BÙI THỊ THẢO',
        'phone': '0912000111',
        'address': 'Tân Bình, TP.HCM',
        'totalAmount': 9990000,
        'paidAmount': 3000000,
        'remainAmount': 6990000,
        'orderId': '',
        'note': 'Mua Oppo Reno 11, đặt cọc 3tr',
        'daysAgo': 2,
      },
      {
        'customerName': 'TRƯƠNG CÔNG MINH',
        'phone': '0923111222',
        'address': 'Q.9, TP.HCM',
        'totalAmount': 32000000,
        'paidAmount': 20000000,
        'remainAmount': 12000000,
        'orderId': '',
        'note': 'Mua iPhone 15 Pro Max, còn nợ 12tr',
        'daysAgo': 5,
      },
    ];

    int count = 0;
    for (final d in debts) {
      try {
        final createdAt = todayMs - 86400000 * (d['daysAgo'] as int);
        final docId = 'debt_${createdAt}_${d['phone']}';
        final debtData = {
          'firestoreId': docId,
          'shopId': shopId,
          'customerName': d['customerName'],
          'phone': d['phone'],
          'address': d['address'],
          'totalAmount': d['totalAmount'],
          'paidAmount': d['paidAmount'],
          'remainAmount': d['remainAmount'],
          'orderId': d['orderId'],
          'note': d['note'],
          'status': 'UNPAID',
          'createdAt': createdAt,
          'updatedAt': createdAt,
          'isSynced': 1,
          'deleted': false,
        };
        await FirestoreService.addDebtCloud(debtData);
        debtData.remove('updatedAt');
        debtData['isSynced'] = 1;
        await _db.insertDebt(debtData);
        count++;
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('⚠️ seedDebts: ${d['customerName']} - $e');
      }
    }
    log.writeln('✅ $count công nợ khách hàng (tổng ~43tr)');
  }

  // ─────────────────────────────────────────────
  // 7. Chi phí / Thu nhập khác
  // ─────────────────────────────────────────────
  static Future<void> _seedExpenses(
    String shopId,
    int todayMs,
    StringBuffer log,
  ) async {
    final expenses = [
      {
        'title': 'TIỀN ĐIỆN THÁNG 4/2026',
        'amount': 2800000,
        'category': 'Tiện ích',
        'method': 'CHUYỂN KHOẢN',
        'type': 'CHI',
        'daysAgo': 2,
      },
      {
        'title': 'TIỀN THUÊ MẶT BẰNG THÁNG 4',
        'amount': 15000000,
        'category': 'Mặt bằng',
        'method': 'CHUYỂN KHOẢN',
        'type': 'CHI',
        'daysAgo': 1,
      },
      {
        'title': 'MUA VẬT DỤNG VĂN PHÒNG',
        'amount': 850000,
        'category': 'Văn phòng phẩm',
        'method': 'TIỀN MẶT',
        'type': 'CHI',
        'daysAgo': 3,
      },
      {
        'title': 'DỊCH VỤ WIFI THÁNG 4',
        'amount': 350000,
        'category': 'Tiện ích',
        'method': 'CHUYỂN KHOẢN',
        'type': 'CHI',
        'daysAgo': 3,
      },
      {
        'title': 'THU TIỀN BẢO HÀNH NGOÀI HẠN - A.THÀNH',
        'amount': 300000,
        'category': 'Thu bảo hành',
        'method': 'TIỀN MẶT',
        'type': 'THU',
        'daysAgo': 1,
      },
      {
        'title': 'THU TIỀN SỬA MÀN HÌNH IPAD - C.LAN',
        'amount': 1200000,
        'category': 'Thu sửa chữa',
        'method': 'TIỀN MẶT',
        'type': 'THU',
        'daysAgo': 0,
      },
      {
        'title': 'CHI LƯƠNG NHÂN VIÊN THÁNG 3',
        'amount': 28000000,
        'category': 'Lương',
        'method': 'CHUYỂN KHOẢN',
        'type': 'CHI',
        'daysAgo': 7,
      },
      {
        'title': 'CHI PHÍ QUẢNG CÁO FACEBOOK',
        'amount': 2000000,
        'category': 'Marketing',
        'method': 'CHUYỂN KHOẢN',
        'type': 'CHI',
        'daysAgo': 5,
      },
    ];

    int count = 0;
    for (final exp in expenses) {
      try {
        final expDate = todayMs - 86400000 * (exp['daysAgo'] as int);
        final expData = {
          'title': exp['title'],
          'amount': exp['amount'],
          'category': exp['category'],
          'date': expDate,
          'paymentMethod': exp['method'],
          'type': exp['type'],
          'note': 'Dữ liệu demo',
          'shopId': shopId,
          'createdAt': expDate,
          'isSynced': 0,
        };
        await FirestoreService.addExpenseCloud(expData);
        expData.remove('updatedAt');
        expData['isSynced'] = 1;
        await _db.insertExpense(expData);
        count++;
        await Future.delayed(const Duration(milliseconds: 150));
      } catch (e) {
        debugPrint('⚠️ seedExpenses: ${exp['title']} - $e');
      }
    }
    log.writeln('✅ $count khoản thu/chi (điện, thuê mặt bằng, lương, marketing...)');
  }

  // ─────────────────────────────────────────────
  // 8. Cài đặt lương nhân viên
  // ─────────────────────────────────────────────
  static Future<void> _seedEmployeeSalarySettings(
    String shopId,
    String ownerUid,
    String ownerName,
    int todayMs,
    StringBuffer log,
  ) async {
    final staffList = [
      {
        'staffId': 'staff_nguyen_thi_hong_001',
        'staffName': 'NGUYỄN THỊ HỒNG',
        'role': 'employee',
        'baseSalary': 8000000.0,
        'salaryType': 'monthly',
        'saleCommType': 'percent',
        'saleCommValue': 1.5,
        'repairCommType': 'percent',
        'repairCommValue': 10.0,
        'transportAllowance': 500000.0,
        'mealAllowance': 600000.0,
        'monthlyTarget': 100000000.0,
        'targetBonusPercent': 5.0,
      },
      {
        'staffId': 'staff_tran_van_duc_002',
        'staffName': 'TRẦN VĂN ĐỨC',
        'role': 'employee',
        'baseSalary': 7500000.0,
        'salaryType': 'monthly',
        'saleCommType': 'percent',
        'saleCommValue': 1.0,
        'repairCommType': 'percent',
        'repairCommValue': 8.0,
        'transportAllowance': 400000.0,
        'mealAllowance': 500000.0,
        'monthlyTarget': 80000000.0,
        'targetBonusPercent': 3.0,
      },
      {
        'staffId': 'staff_le_thi_phuong_003',
        'staffName': 'LÊ THỊ PHƯƠNG',
        'role': 'manager',
        'baseSalary': 12000000.0,
        'salaryType': 'monthly',
        'saleCommType': 'percent',
        'saleCommValue': 2.0,
        'repairCommType': 'percent',
        'repairCommValue': 12.0,
        'transportAllowance': 800000.0,
        'mealAllowance': 700000.0,
        'phoneAllowance': 300000.0,
        'monthlyTarget': 200000000.0,
        'targetBonusPercent': 8.0,
      },
    ];

    // Tạo user docs cho nhân viên trong Firestore
    int count = 0;
    for (final staff in staffList) {
      try {
        final staffId = staff['staffId'] as String;

        // Tạo user doc cho nhân viên
        await _fs.collection('users').doc(staffId).set({
          'uid': staffId,
          'shopId': shopId,
          'role': staff['role'],
          'displayName': staff['staffName'],
          'name': staff['staffName'],
          'email': '${staffId.split('_').take(3).join('.')}@huluca.shop',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
          'isActive': true,
        }, SetOptions(merge: true));

        // Lưu cài đặt lương
        final salarySettings = {
          'staffId': staffId,
          'staffName': staff['staffName'],
          'baseSalary': staff['baseSalary'],
          'dailyRate': 0.0,
          'salaryType': staff['salaryType'],
          'saleCommType': staff['saleCommType'],
          'saleCommValue': staff['saleCommValue'],
          'saleCommTier1Max': 10000000.0,
          'saleCommTier1Value': 20000.0,
          'saleCommTier2Max': 50000000.0,
          'saleCommTier2Value': 50000.0,
          'saleCommTier3Value': 100000.0,
          'repairCommType': staff['repairCommType'],
          'repairCommValue': staff['repairCommValue'],
          'transportAllowance': staff['transportAllowance'] ?? 0.0,
          'mealAllowance': staff['mealAllowance'] ?? 0.0,
          'phoneAllowance': staff['phoneAllowance'] ?? 0.0,
          'otherAllowance': 0.0,
          'otherAllowanceNote': '',
          'monthlyTarget': staff['monthlyTarget'],
          'targetBonusPercent': staff['targetBonusPercent'],
          'standardHoursPerDay': 8.0,
          'overtimeRate': 150.0,
          'isActive': true,
        };
        await FirestoreService.saveEmployeeSalarySettings(salarySettings);

        // Lưu vào local DB
        final localData = {
          'id': 'salary_${staffId}_$todayMs',
          ...salarySettings,
          'shopId': shopId,
          'updatedBy': ownerName,
          'createdAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        };
        await _db.upsertEmployeeSalarySettings(localData);
        count++;
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('⚠️ seedSalary: ${staff['staffName']} - $e');
      }
    }
    log.writeln('✅ $count nhân viên với cài đặt lương (cơ bản, hoa hồng, phụ cấp)');
  }

  // ─────────────────────────────────────────────
  // 9. Chấm công
  // ─────────────────────────────────────────────
  static Future<void> _seedAttendance(
    String shopId,
    String ownerUid,
    String ownerName,
    int todayMs,
    StringBuffer log,
  ) async {
    final staffForAttendance = [
      {'id': 'staff_nguyen_thi_hong_001', 'name': 'NGUYỄN THỊ HỒNG'},
      {'id': 'staff_tran_van_duc_002', 'name': 'TRẦN VĂN ĐỨC'},
      {'id': 'staff_le_thi_phuong_003', 'name': 'LÊ THỊ PHƯƠNG'},
    ];

    // Tạo chấm công cho 7 ngày gần nhất
    int count = 0;
    final today = DateTime.now();
    for (int daysBack = 0; daysBack < 7; daysBack++) {
      final day = today.subtract(Duration(days: daysBack));
      if (day.weekday == DateTime.saturday ||
          day.weekday == DateTime.sunday) {
        continue;
      }
      final dateKey =
          '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

      for (final staff in staffForAttendance) {
        try {
          final checkInHour = 8 + (staff['id']!.hashCode.abs() % 2);
          final checkInMs = DateTime(day.year, day.month, day.day, checkInHour, 0)
              .millisecondsSinceEpoch;
          final checkOutMs = DateTime(day.year, day.month, day.day, 17, 30)
              .millisecondsSinceEpoch;
          final isLate = checkInHour > 8 ? 1 : 0;
          final fsId = 'att_${staff['id']}_$dateKey';

          final attendance = Attendance(
            firestoreId: fsId,
            userId: staff['id']!,
            email: '${staff['id']!.split('_').take(3).join('.')}@huluca.shop',
            name: staff['name']!,
            dateKey: dateKey,
            checkInAt: checkInMs,
            checkOutAt: daysBack == 0 ? null : checkOutMs,
            status: daysBack == 0 ? 'pending' : 'approved',
            approvedBy: daysBack == 0 ? null : ownerName,
            approvedAt: daysBack == 0 ? null : checkOutMs + 1800000,
            locked: daysBack < 1 ? 0 : 1,
            createdAt: checkInMs,
            isLate: isLate,
            isEarlyLeave: 0,
            isSynced: true,
          );

          await FirestoreService.addAttendance(attendance);
          await _db.upsertAttendance(attendance);
          count++;
          await Future.delayed(const Duration(milliseconds: 100));
        } catch (e) {
          debugPrint('⚠️ seedAttendance: ${staff['name']} $dateKey - $e');
        }
      }
    }
    log.writeln('✅ $count bản ghi chấm công (7 ngày, 3 nhân viên, có trễ giờ)');
  }

  // ─────────────────────────────────────────────
  // 10. Cộng đồng
  // ─────────────────────────────────────────────
  static Future<void> _seedCommunityPosts(
    String shopId,
    String ownerUid,
    String ownerName,
    int todayMs,
    StringBuffer log,
  ) async {
    final posts = [
      {
        'content':
            '📱 IPHONE 15 PRO MAX VỀ HÀNG RỒI NHÉ! Màu Đen Titan siêu đẹp, giá cạnh tranh nhất khu vực. DM ngay để được tư vấn miễn phí! 🔥',
        'hoursAgo': 10,
      },
      {
        'content':
            '🔧 TIPS SỬA CHỮA: Điện thoại bị nước vào — ngay lập tức TẮT NGUỒN, KHÔNG sạc, KHÔNG bật lại. Mang đến shop ngay trong 24h để tăng tỷ lệ cứu máy lên 80%! 💧',
        'hoursAgo': 24,
      },
      {
        'content':
            '✅ KHÁCH HÀNG HÀI LÒNG! Bạn Nguyễn Văn Anh vừa mua iPhone 15 Pro Max và nhận xét: "Shop tư vấn nhiệt tình, hàng chính hãng, giá tốt!". Cảm ơn bạn rất nhiều! 🙏',
        'hoursAgo': 36,
      },
      {
        'content':
            '🎉 KHUYẾN MÃI THÁNG 5: Mua điện thoại từ 15tr tặng ngay ốp lưng + kính cường lực + gói bảo hành mở rộng 6 tháng. Áp dụng đến hết tháng!',
        'hoursAgo': 48,
      },
      {
        'content':
            '📊 Báo cáo nhanh tuần này: Doanh thu bán hàng đạt 85% kế hoạch. Sửa chữa tăng 20% so với tuần trước. Tiếp tục cố gắng nhé team! 💪',
        'hoursAgo': 72,
      },
    ];

    int count = 0;
    for (final post in posts) {
      try {
        final postRef = _fs.collection('community_posts').doc();
        await postRef.set({
          'shopId': shopId,
          'authorUid': ownerUid,
          'authorName': ownerName.isNotEmpty ? ownerName : 'Chủ shop',
          'authorRole': 'owner',
          'authorPhotoUrl': '',
          'content': post['content'],
          'imageUrl': '',
          'likeCount': count * 2 + 1,
          'commentCount': count,
          'likedBy': [ownerUid],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
          'deleted': false,
        });

        // Thêm 1 bình luận cho bài đầu tiên
        if (count == 0) {
          final commentRef = postRef.collection('comments').doc();
          await commentRef.set({
            'postId': postRef.id,
            'authorUid': 'staff_le_thi_phuong_003',
            'authorName': 'LÊ THỊ PHƯƠNG',
            'authorRole': 'manager',
            'authorPhotoUrl': '',
            'content': 'Hàng đẹp quá chị ơi! Em đang tư vấn khách đây 😊',
            'createdAt': FieldValue.serverTimestamp(),
            'deleted': false,
          });
        }

        count++;
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('⚠️ seedCommunity: $e');
      }
    }
    log.writeln('✅ $count bài đăng cộng đồng (có like, comment)');
  }

  // ─────────────────────────────────────────────
  // 11. Chat nội bộ
  // ─────────────────────────────────────────────
  static Future<void> _seedChatMessages(
    String shopId,
    String ownerUid,
    String ownerName,
    int todayMs,
    StringBuffer log,
  ) async {
    final messages = [
      {
        'senderId': 'staff_le_thi_phuong_003',
        'senderName': 'LÊ THỊ PHƯƠNG',
        'message': 'Anh/chị ơi, hôm nay mình có 3 máy nhận sửa rồi ạ! 🔧',
        'minutesAgo': 120,
      },
      {
        'senderId': ownerUid,
        'senderName': ownerName.isNotEmpty ? ownerName : 'Chủ shop',
        'message': 'Tốt lắm! Nhớ ưu tiên cái iPhone 13 Pro Max khách hỏi nhiều nhé',
        'minutesAgo': 115,
      },
      {
        'senderId': 'staff_nguyen_thi_hong_001',
        'senderName': 'NGUYỄN THỊ HỒNG',
        'message': 'Em vừa chốt được đơn Samsung S24 Ultra 29.4tr rồi anh ơi! 🎉',
        'minutesAgo': 90,
      },
      {
        'senderId': ownerUid,
        'senderName': ownerName.isNotEmpty ? ownerName : 'Chủ shop',
        'message': 'Giỏi lắm Hồng! Nhớ cập nhật vào hệ thống và ghi biên bản bán hàng',
        'minutesAgo': 85,
      },
      {
        'senderId': 'staff_tran_van_duc_002',
        'senderName': 'TRẦN VĂN ĐỨC',
        'message': 'Anh cho em hỏi, kho còn iPhone 15 Pro Max màu trắng không ạ?',
        'minutesAgo': 60,
      },
      {
        'senderId': ownerUid,
        'senderName': ownerName.isNotEmpty ? ownerName : 'Chủ shop',
        'message': 'Hết màu trắng rồi, còn màu đen và titan. Để anh đặt thêm hàng nhé',
        'minutesAgo': 55,
      },
      {
        'senderId': 'staff_le_thi_phuong_003',
        'senderName': 'LÊ THỊ PHƯƠNG',
        'message': 'Team ơi, cuối tháng review KPI ngày 28 nhé, mọi người chuẩn bị báo cáo! 📊',
        'minutesAgo': 30,
      },
    ];

    int count = 0;
    for (final msg in messages) {
      try {
        final msgRef = _fs.collection('shop_chats').doc();
        await msgRef.set({
          'shopId': shopId,
          'senderId': msg['senderId'],
          'senderName': msg['senderName'],
          'senderAvatar': null,
          'message': msg['message'],
          'messageType': 'text',
          'replyToId': null,
          'replyToMessage': null,
          'replyToSender': null,
          'mentions': [],
          'readBy': [ownerUid, msg['senderId']],
          'priority': 0,
          'createdAt': FieldValue.serverTimestamp(),
          'deleted': false,
        });
        count++;
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        debugPrint('⚠️ seedChat: $e');
      }
    }
    log.writeln('✅ $count tin nhắn chat nội bộ (đa người dùng, có hội thoại)');
  }

  // ─────────────────────────────────────────────
  // 12. Phiếu nhập hàng
  // ─────────────────────────────────────────────
  static Future<void> _seedImportOrders(
    String shopId,
    Map<String, String> supplierIds,
    String ownerUid,
    String ownerName,
    int todayMs,
    StringBuffer log,
  ) async {
    final orders = [
      {
        'supplierKey': 'CÔNG TY TNHH APPLE VIỆT NAM',
        'orderCode': 'NK-0001',
        'totalQty': 5,
        'totalAmount': 145000000,
        'paymentMethod': 'CHUYỂN KHOẢN',
        'paymentStatus': 'PAID',
        'notes': 'Nhập 3 iPhone 15 Pro Max + 2 iPhone 14',
        'daysAgo': 5,
      },
      {
        'supplierKey': 'KHO SÌ SAMSUNG MIỀN NAM',
        'orderCode': 'NK-0002',
        'totalQty': 3,
        'totalAmount': 78000000,
        'paymentMethod': 'CÔNG NỢ',
        'paymentStatus': 'DEBT',
        'notes': 'Nhập 3 Samsung S24 Ultra, còn nợ 30tr',
        'daysAgo': 3,
      },
      {
        'supplierKey': 'PHỤ KIỆN ĐIỆN THOẠI HOÀNG GIA',
        'orderCode': 'NK-0003',
        'totalQty': 200,
        'totalAmount': 8500000,
        'paymentMethod': 'TIỀN MẶT',
        'paymentStatus': 'PAID',
        'notes': 'Nhập phụ kiện: ốp lưng, cáp, kính cường lực',
        'daysAgo': 2,
      },
    ];

    int count = 0;
    for (final order in orders) {
      try {
        final importDate =
            todayMs - 86400000 * (order['daysAgo'] as int);
        final supplierId = supplierIds[order['supplierKey'] as String] ?? '';

        final docRef = _fs.collection('import_orders').doc();
        await docRef.set({
          'shopId': shopId,
          'orderCode': order['orderCode'],
          'supplierId': supplierId,
          'supplierName': order['supplierKey'],
          'totalQuantity': order['totalQty'],
          'totalAmount': order['totalAmount'],
          'paymentMethod': order['paymentMethod'],
          'paymentStatus': order['paymentStatus'],
          'paidAmount': order['paymentStatus'] == 'PAID'
              ? order['totalAmount']
              : (order['totalAmount'] as int) - 30000000,
          'status': 'CONFIRMED',
          'importDate': importDate,
          'importedBy': ownerName,
          'importedByUid': ownerUid,
          'notes': order['notes'],
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FirestoreWriteHelper.serverUpdatedAt(),
          'deleted': false,
        });
        count++;
        await Future.delayed(const Duration(milliseconds: 200));
      } catch (e) {
        debugPrint('⚠️ seedImportOrders: ${order['orderCode']} - $e');
      }
    }
    log.writeln('✅ $count phiếu nhập hàng (Apple, Samsung, phụ kiện)');
  }

  // ─────────────────────────────────────────────
  // BUSINESS FLOW SCENARIO (1-click cho người không biết code)
  // ─────────────────────────────────────────────
  static Future<String> seedBusinessFlowData() async {
    final log = StringBuffer();
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    final runTag = '${_scenarioTagPrefix}_$nowMs';
    final shopId = UserService.getShopIdSync() ?? '';
    final userName = await UserService.getCurrentUserName();
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';

    if (shopId.isEmpty) {
      return '❌ Không tìm thấy shopId. Vui lòng đăng nhập lại.';
    }

    log.writeln('🚀 BẮT ĐẦU TẠO DỮ LIỆU NGHIỆP VỤ TỰ ĐỘNG');
    log.writeln('🏷️ Mã phiên: $runTag');
    log.writeln('🏪 Shop: $shopId');
    log.writeln('');

    final supplierIds = await _seedSuppliers(shopId, log);
    final products = await _seedProducts(shopId, nowMs, log);

    await _seedBusinessFlowImports(
      runTag: runTag,
      shopId: shopId,
      uid: uid,
      userName: userName,
      nowMs: nowMs,
      supplierIds: supplierIds,
      products: products,
      log: log,
    );

    final sales = await _seedBusinessFlowSales(
      runTag: runTag,
      nowMs: nowMs,
      userName: userName,
      products: products,
      log: log,
    );

    await _seedBusinessFlowReturns(
      runTag: runTag,
      sales: sales,
      products: products,
      log: log,
    );

    await _seedBusinessFlowRepairs(
      runTag: runTag,
      shopId: shopId,
      uid: uid,
      userName: userName,
      nowMs: nowMs,
      log: log,
    );

    await _seedBusinessFlowDebtsAndPayments(
      runTag: runTag,
      shopId: shopId,
      nowMs: nowMs,
      log: log,
    );

    await _seedBusinessFlowIncomeExpense(
      runTag: runTag,
      shopId: shopId,
      nowMs: nowMs,
      log: log,
    );

    log.writeln('');
    log.writeln('✅ HOÀN TẤT: Đã tạo full luồng nghiệp vụ test.');
    log.writeln('ℹ️ Nếu chưa thấy ngay, vào Đồng bộ và bấm tải dữ liệu.');
    return log.toString();
  }

  static Future<String> resetBusinessFlowData() async {
    try {
      final shopId = UserService.getShopIdSync() ?? '';
      if (shopId.isEmpty) {
        return '❌ Không tìm thấy shopId để xóa dữ liệu.';
      }

      final deleteError = await FirestoreService.resetEntireShopData(
        shopIdOverride: shopId,
      );
      if (deleteError != null) {
        return '❌ Xóa cloud thất bại: $deleteError';
      }

      // Các collection chưa có trong resetEntireShopData
      final extraCollections = <String>[
        'import_orders',
        'supplier_import_history',
        'repair_partners',
        'repair_partner_payments',
        'partner_repair_history',
        'sales_returns',
        'sales_return_items',
      ];

      for (final col in extraCollections) {
        final snap = await _fs
            .collection(col)
            .where('shopId', isEqualTo: shopId)
            .get();
        if (snap.docs.isEmpty) continue;
        const batchSize = 400;
        for (int i = 0; i < snap.docs.length; i += batchSize) {
          final batch = _fs.batch();
          final end = (i + batchSize < snap.docs.length)
              ? i + batchSize
              : snap.docs.length;
          for (int j = i; j < end; j++) {
            batch.delete(snap.docs[j].reference);
          }
          await batch.commit();
        }
      }

      await _db.clearAllData();
      await SyncService.cancelAllSubscriptions();
      await SyncService.resetSyncTimestamps();

      return '✅ Đã xóa sạch dữ liệu test (cloud + local).';
    } catch (e) {
      return '❌ Lỗi khi xóa dữ liệu test: $e';
    }
  }

  static Future<void> _seedBusinessFlowImports({
    required String runTag,
    required String shopId,
    required String uid,
    required String userName,
    required int nowMs,
    required Map<String, String> supplierIds,
    required List<Product> products,
    required StringBuffer log,
  }) async {
    final productByName = <String, Product>{
      for (final p in products) p.name.toUpperCase(): p,
    };

    final importRows = <Map<String, dynamic>>[
      {
        'supplierName': 'CÔNG TY TNHH APPLE VIỆT NAM',
        'productName': 'IPHONE 15 PRO MAX 256GB',
        'paymentMethod': 'TIỀN MẶT',
        'quantity': 2,
        'costPrice': 28000000,
        'hoursAgo': 20,
      },
      {
        'supplierName': 'KHO SÌ SAMSUNG MIỀN NAM',
        'productName': 'SAMSUNG GALAXY S24 ULTRA 256GB',
        'paymentMethod': 'CHUYỂN KHOẢN',
        'quantity': 1,
        'costPrice': 25000000,
        'hoursAgo': 18,
      },
      {
        'supplierName': 'PHỤ KIỆN ĐIỆN THOẠI HOÀNG GIA',
        'productName': 'CÁP SẠC TYPE-C 1M',
        'paymentMethod': 'CÔNG NỢ',
        'quantity': 50,
        'costPrice': 30000,
        'hoursAgo': 16,
      },
      {
        'supplierName': 'KHO TỔNG LINH KIỆN NỘI BỘ',
        'productName': 'PIN IPHONE 14 CHÍNH HÃNG',
        'paymentMethod': 'CÔNG NỢ ĐỐI TÁC',
        'quantity': 10,
        'costPrice': 250000,
        'hoursAgo': 14,
      },
      {
        'supplierName': 'KHO TỔNG LINH KIỆN NỘI BỘ',
        'productName': 'MÀN HÌNH SAMSUNG S23 AMOLED',
        'paymentMethod': 'TIỀN MẶT',
        'quantity': 4,
        'costPrice': 1200000,
        'hoursAgo': 12,
      },
    ];

    int count = 0;
    for (final row in importRows) {
      final productName = (row['productName'] as String).toUpperCase();
      final p = productByName[productName];
      final quantity = row['quantity'] as int;
      final costPrice = row['costPrice'] as int;
      final totalAmount = quantity * costPrice;
      final ts = nowMs - ((row['hoursAgo'] as int) * 3600000);
      final firestoreId = 'imp_${runTag}_$count';
      final supplierName = row['supplierName'] as String;
      final paymentMethod = row['paymentMethod'] as String;
      final supplierId = supplierIds[supplierName] ?? '';

      final importData = <String, dynamic>{
        'firestoreId': firestoreId,
        'shopId': shopId,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'productName': p?.name ?? productName,
        'productBrand': p?.brand ?? '',
        'productModel': p?.capacity ?? '',
        'imei': p?.imei ?? '',
        'quantity': quantity,
        'costPrice': costPrice,
        'totalAmount': totalAmount,
        'paymentMethod': paymentMethod,
        'importDate': ts,
        'importedBy': userName,
        'importedByUid': uid,
        'referenceId': runTag,
        'createdAt': ts,
        'notes': 'Seed flow: $runTag',
        'isSynced': 1,
      };

      try {
        await _fs
            .collection('supplier_import_history')
            .doc(firestoreId)
            .set(EncryptionService.encryptMap(importData), SetOptions(merge: true));
        await _db.insertSupplierImportHistory(importData);

        // Ghi nhận dòng tiền nhập hàng vào expenses (để khớp tài chính)
        if (paymentMethod == 'TIỀN MẶT' || paymentMethod == 'CHUYỂN KHOẢN') {
          final expId = 'exp_import_${runTag}_$count';
          final expData = <String, dynamic>{
            'firestoreId': expId,
            'title': 'Nhập hàng: ${p?.name ?? productName}',
            'amount': totalAmount,
            'category': 'Nhập hàng',
            'date': ts,
            'paymentMethod': paymentMethod,
            'type': 'CHI',
            'note': 'Tự động seed nghiệp vụ $runTag',
            'referenceId': firestoreId,
            'shopId': shopId,
            'createdAt': ts,
            'isSynced': 1,
          };
          await FirestoreService.addExpenseCloud(expData);
          await _db.insertExpense(expData);
        } else {
          // Nhập hàng công nợ NCC/đối tác
          final debtId = 'debt_import_${runTag}_$count';
          final isPartnerDebt = paymentMethod == 'CÔNG NỢ ĐỐI TÁC';
          final debtData = <String, dynamic>{
            'firestoreId': debtId,
            'shopId': shopId,
            'personName': supplierName,
            'customerName': supplierName,
            'phone': '',
            'totalAmount': totalAmount,
            'paidAmount': 0,
            'remainAmount': totalAmount,
            'type': isPartnerDebt ? 'OTHER_SHOP_OWES' : 'SHOP_OWES',
            'debtType': isPartnerDebt ? 'OTHER_SHOP_OWES' : 'SHOP_OWES',
            'note': 'Công nợ nhập hàng $runTag',
            'status': 'ACTIVE',
            'linkedId': firestoreId,
            'createdAt': ts,
            'isSynced': 1,
            'deleted': false,
          };
          await FirestoreService.addDebtCloud(debtData);
          await _db.insertDebt(debtData);
        }
        count++;
      } catch (e) {
        debugPrint('⚠️ seedBusinessFlowImports error: $e');
      }
    }

    log.writeln('✅ Nhập kho: $count dòng (điện thoại, phụ kiện, linh kiện; TM/CK/công nợ NCC/đối tác)');
  }

  static Future<List<Map<String, dynamic>>> _seedBusinessFlowSales({
    required String runTag,
    required int nowMs,
    required String userName,
    required List<Product> products,
    required StringBuffer log,
  }) async {
    Product? findProduct(String contains) {
      final key = contains.toUpperCase();
      for (final p in products) {
        if (p.name.toUpperCase().contains(key)) return p;
      }
      return null;
    }

    final iphone15 = findProduct('IPHONE 15 PRO MAX');
    final iphone14 = findProduct('IPHONE 14');
    final samsung = findProduct('SAMSUNG GALAXY S24 ULTRA');
    final oppo = findProduct('OPPO RENO 11');
    final cap = findProduct('CÁP SẠC TYPE-C');
    final opLung = findProduct('ỐP LƯNG IPHONE 15');
    final taiNghe = findProduct('TAI NGHE BLUETOOTH');
    final pin = findProduct('PIN IPHONE 14');

    final createdSales = <Map<String, dynamic>>[];

    Future<void> createSale({
      required String customer,
      required String phone,
      required String method,
      required int totalPrice,
      required int totalCost,
      required int hoursAgo,
      int discount = 0,
      bool isInstallment = false,
      int downPayment = 0,
      String? downPaymentMethod,
      int loanAmount = 0,
      String? bankName,
      String? bankName2,
      int loanAmount2 = 0,
      int settlementAmount = 0,
      int cashAmount = 0,
      int transferAmount = 0,
      required List<Map<String, dynamic>> items,
      String? marker,
    }) async {
      final soldAt = nowMs - (hoursAgo * 3600000);
      final fid = 'sale_${runTag}_${createdSales.length + 1}';
      final snapshots = items
          .map((item) => {
                'productId': item['productId'],
                'productFirestoreId': item['productFirestoreId'],
                'productName': item['productName'],
                'productImei': item['productImei'],
                'quantity': item['quantity'],
                'unitPrice': item['unitPrice'],
                'unitCost': item['unitCost'],
                'exactPricing': true,
              })
          .toList(growable: false);

      final sale = SaleOrder(
        firestoreId: fid,
        customerName: customer,
        phone: phone,
        address: 'TP.HCM',
        productNames: items
            .map((e) => '${e['productName']} x${e['quantity']}')
            .join(', '),
        productImeis: items.map((e) => '${e['productImei'] ?? ''}').join(', '),
        itemSnapshotsJson: jsonEncode(snapshots),
        totalPrice: totalPrice,
        totalCost: totalCost,
        discount: discount,
        paymentMethod: method,
        sellerName: userName,
        soldAt: soldAt,
        warranty: '12 tháng',
        notes: 'Seed flow $runTag ${marker ?? ''}',
        isInstallment: isInstallment,
        downPayment: downPayment,
        downPaymentMethod: downPaymentMethod,
        loanAmount: loanAmount,
        bankName: bankName,
        bankName2: bankName2,
        loanAmount2: loanAmount2,
        settlementAmount: settlementAmount,
        settlementReceivedAt: settlementAmount > 0 ? soldAt + 7200000 : null,
        cashAmount: cashAmount,
        transferAmount: transferAmount,
      );

      final saleId = await FirestoreService.addSale(sale);
      if (saleId != null) {
        sale.firestoreId = saleId;
      }
      await _db.insertSale(sale);
      final dbSale = await _db.getSaleByFirestoreId(sale.firestoreId ?? fid);
      createdSales.add({
        'sale': sale,
        'dbId': dbSale?.id,
        'marker': marker ?? '',
      });
    }

    await createSale(
      customer: 'KH TEST TM',
      phone: '0901000001',
      method: 'TIỀN MẶT',
      totalPrice: 32000000,
      totalCost: 28000000,
      hoursAgo: 11,
      items: [
        {
          'productId': iphone15?.id,
          'productFirestoreId': iphone15?.firestoreId,
          'productName': iphone15?.name ?? 'IPHONE 15 PRO MAX 256GB',
          'productImei': iphone15?.imei ?? 'SEED-IMEI-15PM',
          'quantity': 1,
          'unitPrice': 32000000,
          'unitCost': 28000000,
        }
      ],
    );

    await createSale(
      customer: 'KH TEST CK',
      phone: '0901000002',
      method: 'CHUYỂN KHOẢN',
      totalPrice: 29900000,
      totalCost: 25000000,
      hoursAgo: 10,
      items: [
        {
          'productId': samsung?.id,
          'productFirestoreId': samsung?.firestoreId,
          'productName': samsung?.name ?? 'SAMSUNG GALAXY S24 ULTRA 256GB',
          'productImei': samsung?.imei ?? 'SEED-IMEI-S24U',
          'quantity': 1,
          'unitPrice': 29900000,
          'unitCost': 25000000,
        }
      ],
    );

    await createSale(
      customer: 'KH TEST KẾT HỢP',
      phone: '0901000003',
      method: 'KẾT HỢP',
      totalPrice: 10550000,
      totalCost: 7750000,
      hoursAgo: 9,
      cashAmount: 5000000,
      transferAmount: 5550000,
      items: [
        {
          'productId': oppo?.id,
          'productFirestoreId': oppo?.firestoreId,
          'productName': oppo?.name ?? 'OPPO RENO 11 5G 256GB',
          'productImei': oppo?.imei ?? 'SEED-IMEI-OPPO',
          'quantity': 1,
          'unitPrice': 9990000,
          'unitCost': 7500000,
        },
        {
          'productId': cap?.id,
          'productFirestoreId': cap?.firestoreId,
          'productName': cap?.name ?? 'CÁP SẠC TYPE-C 1M',
          'productImei': cap?.imei ?? 'SEED-CAP',
          'quantity': 7,
          'unitPrice': 80000,
          'unitCost': 30000,
        },
      ],
    );

    await createSale(
      customer: 'KH TEST CÔNG NỢ',
      phone: '0901000004',
      method: 'CÔNG NỢ',
      totalPrice: 19500000,
      totalCost: 16000000,
      hoursAgo: 8,
      items: [
        {
          'productId': iphone14?.id,
          'productFirestoreId': iphone14?.firestoreId,
          'productName': iphone14?.name ?? 'IPHONE 14 128GB',
          'productImei': iphone14?.imei ?? 'SEED-IMEI-14',
          'quantity': 1,
          'unitPrice': 19500000,
          'unitCost': 16000000,
        }
      ],
    );

    await createSale(
      customer: 'KH TEST TRẢ GÓP 1 NH',
      phone: '0901000005',
      method: 'TRẢ GÓP',
      totalPrice: 29900000,
      totalCost: 25000000,
      hoursAgo: 7,
      isInstallment: true,
      downPayment: 9000000,
      downPaymentMethod: 'TIỀN MẶT',
      loanAmount: 20900000,
      bankName: 'HD SAISON',
      settlementAmount: 20900000,
      items: [
        {
          'productId': samsung?.id,
          'productFirestoreId': samsung?.firestoreId,
          'productName': samsung?.name ?? 'SAMSUNG GALAXY S24 ULTRA 256GB',
          'productImei': '${samsung?.imei ?? 'SEED-IMEI-S24U'}-TG1',
          'quantity': 1,
          'unitPrice': 29900000,
          'unitCost': 25000000,
        }
      ],
    );

    await createSale(
      customer: 'KH TEST TRẢ GÓP 2 NH',
      phone: '0901000006',
      method: 'TRẢ GÓP',
      totalPrice: 33000000,
      totalCost: 28000000,
      hoursAgo: 6,
      isInstallment: true,
      downPayment: 7000000,
      downPaymentMethod: 'CHUYỂN KHOẢN',
      loanAmount: 13000000,
      bankName: 'FE CREDIT',
      loanAmount2: 13000000,
      bankName2: 'MIRAE ASSET',
      settlementAmount: 26000000,
      items: [
        {
          'productId': iphone15?.id,
          'productFirestoreId': iphone15?.firestoreId,
          'productName': iphone15?.name ?? 'IPHONE 15 PRO MAX 256GB',
          'productImei': '${iphone15?.imei ?? 'SEED-IMEI-15PM'}-TG2',
          'quantity': 1,
          'unitPrice': 33000000,
          'unitCost': 28000000,
        }
      ],
    );

    await createSale(
      customer: 'KH TEST TRẢ HÀNG MỘT PHẦN',
      phone: '0901000007',
      method: 'TIỀN MẶT',
      totalPrice: 6400000,
      totalCost: 4900000,
      hoursAgo: 5,
      marker: 'PARTIAL_RETURN_TARGET',
      items: [
        {
          'productId': taiNghe?.id,
          'productFirestoreId': taiNghe?.firestoreId,
          'productName': taiNghe?.name ?? 'TAI NGHE BLUETOOTH JBL TUNE 510BT',
          'productImei': taiNghe?.imei ?? 'SEED-TN',
          'quantity': 1,
          'unitPrice': 450000,
          'unitCost': 200000,
        },
        {
          'productId': opLung?.id,
          'productFirestoreId': opLung?.firestoreId,
          'productName': opLung?.name ?? 'ỐP LƯNG IPHONE 15 PRO',
          'productImei': opLung?.imei ?? 'SEED-OPL',
          'quantity': 10,
          'unitPrice': 150000,
          'unitCost': 50000,
        },
        {
          'productId': pin?.id,
          'productFirestoreId': pin?.firestoreId,
          'productName': pin?.name ?? 'PIN IPHONE 14 CHÍNH HÃNG',
          'productImei': pin?.imei ?? 'SEED-PIN',
          'quantity': 5,
          'unitPrice': 890000,
          'unitCost': 840000,
        },
      ],
    );

    await createSale(
      customer: 'KH TEST TRẢ HÀNG TOÀN BỘ',
      phone: '0901000008',
      method: 'CHUYỂN KHOẢN',
      totalPrice: 10500000,
      totalCost: 8000000,
      hoursAgo: 4,
      marker: 'FULL_RETURN_TARGET',
      items: [
        {
          'productId': oppo?.id,
          'productFirestoreId': oppo?.firestoreId,
          'productName': oppo?.name ?? 'OPPO RENO 11 5G 256GB',
          'productImei': '${oppo?.imei ?? 'SEED-OPPO'}-FULL',
          'quantity': 1,
          'unitPrice': 10500000,
          'unitCost': 8000000,
        },
      ],
    );

    log.writeln('✅ Bán hàng: ${createdSales.length} đơn (TM, CK, KẾT HỢP, CÔNG NỢ, trả góp 1 NH, trả góp 2 NH)');
    return createdSales;
  }

  static Future<void> _seedBusinessFlowReturns({
    required String runTag,
    required List<Map<String, dynamic>> sales,
    required List<Product> products,
    required StringBuffer log,
  }) async {
    try {
      final partial = sales.firstWhere(
        (e) => e['marker'] == 'PARTIAL_RETURN_TARGET',
        orElse: () => {},
      );
      final full = sales.firstWhere(
        (e) => e['marker'] == 'FULL_RETURN_TARGET',
        orElse: () => {},
      );

      int created = 0;
      if (partial.isNotEmpty) {
        final sale = partial['sale'] as SaleOrder;
        final saleId = partial['dbId'] as int?;
        if (saleId != null && sale.firestoreId != null) {
          final opLung = products.firstWhere(
            (p) => p.name.toUpperCase().contains('ỐP LƯNG IPHONE 15'),
          );
          final pin = products.firstWhere(
            (p) => p.name.toUpperCase().contains('PIN IPHONE 14'),
          );
          final res = await SalesReturnService.processReturn(
            salesOrderId: saleId,
            salesOrderFirestoreId: sale.firestoreId,
            customerName: sale.customerName,
            customerPhone: sale.phone,
            refundMethod: 'TIỀN MẶT',
            items: [
              SalesReturnItem(
                productId: opLung.id,
                productFirestoreId: opLung.firestoreId,
                productName: opLung.name,
                productImei: opLung.imei ?? '',
                quantity: 3,
                price: 150000,
                cost: 50000,
                amount: 450000,
              ),
              SalesReturnItem(
                productId: pin.id,
                productFirestoreId: pin.firestoreId,
                productName: pin.name,
                productImei: pin.imei ?? '',
                quantity: 1,
                price: 890000,
                cost: 840000,
                amount: 890000,
              ),
            ],
            note: 'Trả hàng một phần đơn 3 mặt hàng - $runTag',
          );
          if (res['success'] == true) created++;
        }
      }

      if (full.isNotEmpty) {
        final sale = full['sale'] as SaleOrder;
        final saleId = full['dbId'] as int?;
        if (saleId != null && sale.firestoreId != null) {
          final oppo = products.firstWhere(
            (p) => p.name.toUpperCase().contains('OPPO RENO 11'),
          );
          final res = await SalesReturnService.processReturn(
            salesOrderId: saleId,
            salesOrderFirestoreId: sale.firestoreId,
            customerName: sale.customerName,
            customerPhone: sale.phone,
            refundMethod: 'CHUYỂN KHOẢN',
            items: [
              SalesReturnItem(
                productId: oppo.id,
                productFirestoreId: oppo.firestoreId,
                productName: oppo.name,
                productImei: '${oppo.imei ?? 'SEED-OPPO'}-FULL',
                quantity: 1,
                price: 10500000,
                cost: 8000000,
                amount: 10500000,
              ),
            ],
            note: 'Trả hàng toàn bộ - $runTag',
          );
          if (res['success'] == true) created++;
        }
      }

      log.writeln('✅ Trả hàng: $created phiếu (1 phần đơn 3 mặt hàng + 1 toàn bộ)');
    } catch (e) {
      debugPrint('⚠️ seedBusinessFlowReturns error: $e');
      log.writeln('⚠️ Trả hàng: lỗi $e');
    }
  }

  static Future<void> _seedBusinessFlowRepairs({
    required String runTag,
    required String shopId,
    required String uid,
    required String userName,
    required int nowMs,
    required StringBuffer log,
  }) async {
    final repairs = <Map<String, dynamic>>[
      {
        'customerName': 'KH SC TM 1',
        'phone': '0919000001',
        'model': 'IPHONE 13',
        'issue': 'Thay màn hình',
        'partsUsed': 'Màn hình OLED',
        'price': 1800000,
        'cost': 1100000,
        'paymentMethod': 'TIỀN MẶT',
        'hoursAgo': 13,
      },
      {
        'customerName': 'KH SC CK 2',
        'phone': '0919000002',
        'model': 'SAMSUNG S22',
        'issue': 'Thay pin',
        'partsUsed': 'Pin chính hãng',
        'price': 650000,
        'cost': 280000,
        'paymentMethod': 'CHUYỂN KHOẢN',
        'hoursAgo': 12,
      },
      {
        'customerName': 'KH SC CN 3',
        'phone': '0919000003',
        'model': 'XIAOMI 13T',
        'issue': 'Sửa main mất nguồn',
        'partsUsed': 'IC nguồn',
        'price': 2200000,
        'cost': 1200000,
        'paymentMethod': 'CÔNG NỢ',
        'hoursAgo': 10,
      },
      {
        'customerName': 'KH SC TM 4',
        'phone': '0919000004',
        'model': 'OPPO FIND X5',
        'issue': 'Thay loa ngoài',
        'partsUsed': 'Loa ngoài',
        'price': 500000,
        'cost': 180000,
        'paymentMethod': 'TIỀN MẶT',
        'hoursAgo': 8,
      },
      {
        'customerName': 'KH SC CK 5',
        'phone': '0919000005',
        'model': 'IPHONE 12 MINI',
        'issue': 'Sửa Face ID',
        'partsUsed': 'Cụm Face ID',
        'price': 2500000,
        'cost': 1500000,
        'paymentMethod': 'CHUYỂN KHOẢN',
        'hoursAgo': 6,
      },
    ];

    int count = 0;
    for (int i = 0; i < repairs.length; i++) {
      final row = repairs[i];
      final createdAt = nowMs - ((row['hoursAgo'] as int) * 3600000);
      try {
        final repair = Repair(
          firestoreId: 'rep_${runTag}_${i + 1}',
          customerName: row['customerName'] as String,
          phone: row['phone'] as String,
          model: row['model'] as String,
          issue: row['issue'] as String,
          accessories: 'Không có',
          address: 'TP.HCM',
          warranty: '3 tháng',
          partsUsed: row['partsUsed'] as String,
          status: 1,
          price: row['price'] as int,
          cost: row['cost'] as int,
          paymentMethod: row['paymentMethod'] as String,
          createdAt: createdAt,
          createdBy: userName,
          createdByUid: uid,
          repairedBy: userName,
          repairedByUid: uid,
          deliveredBy: userName,
          deliveredByUid: uid,
          services: [],
          isSynced: true,
          deleted: false,
          notes: 'Seed repair flow $runTag',
        );

        final fsId = await FirestoreService.addRepair(repair);
        if (fsId == null) continue;
        repair.firestoreId = fsId;
        await _db.upsertRepair(repair);

        // Flow nghiệp vụ: tiếp nhận -> sửa -> xong -> giao máy
        final started = repair.copyWith(
          status: 2,
          startedAt: createdAt + 1800000,
          lastCaredAt: createdAt + 1800000,
        );
        await FirestoreService.upsertRepair(started);
        await _db.upsertRepair(started);

        final finished = started.copyWith(
          status: 3,
          finishedAt: createdAt + 3600000,
          lastCaredAt: createdAt + 3600000,
        );
        await FirestoreService.upsertRepair(finished);
        await _db.upsertRepair(finished);

        final delivered = finished.copyWith(
          status: 4,
          deliveredAt: createdAt + 5400000,
          lastCaredAt: createdAt + 5400000,
          pendingDeliveryApproval: false,
        );
        await FirestoreService.upsertRepair(delivered);
        await _db.upsertRepair(delivered);

        // Với đơn sửa công nợ, tạo phải thu khách
        if ((row['paymentMethod'] as String).toUpperCase() == 'CÔNG NỢ') {
          final debtData = <String, dynamic>{
            'firestoreId': 'debt_repair_${runTag}_${i + 1}',
            'shopId': shopId,
            'personName': row['customerName'],
            'customerName': row['customerName'],
            'phone': row['phone'],
            'totalAmount': row['price'],
            'paidAmount': 0,
            'remainAmount': row['price'],
            'type': 'CUSTOMER_OWES',
            'debtType': 'CUSTOMER_OWES',
            'status': 'ACTIVE',
            'note': 'Công nợ từ sửa chữa $runTag',
            'linkedId': fsId,
            'createdAt': createdAt + 5400000,
            'isSynced': 1,
            'deleted': false,
          };
          await FirestoreService.addDebtCloud(debtData);
          await _db.insertDebt(debtData);
        }

        count++;
      } catch (e) {
        debugPrint('⚠️ seedBusinessFlowRepairs error: $e');
      }
    }

    log.writeln('✅ Sửa chữa: $count đơn (đủ flow tiếp nhận → sửa → xong → giao; TM/CK/CN)');
  }

  static Future<void> _seedBusinessFlowDebtsAndPayments({
    required String runTag,
    required String shopId,
    required int nowMs,
    required StringBuffer log,
  }) async {
    final debtRows = <Map<String, dynamic>>[
      {
        'id': 'debt_customer_${runTag}_1',
        'personName': 'KH CÔNG NỢ ĐẶC BIỆT',
        'phone': '0903333000',
        'type': 'CUSTOMER_OWES',
        'total': 12000000,
        'paid': 2000000,
        'hoursAgo': 15,
      },
      {
        'id': 'debt_supplier_${runTag}_1',
        'personName': 'NCC LINH KIỆN VIP',
        'phone': '',
        'type': 'SHOP_OWES',
        'total': 18000000,
        'paid': 4000000,
        'hoursAgo': 15,
      },
      {
        'id': 'debt_partner_${runTag}_1',
        'personName': 'ĐỐI TÁC ÉP KÍNH A',
        'phone': '',
        'type': 'OTHER_SHOP_OWES',
        'total': 9000000,
        'paid': 1000000,
        'hoursAgo': 15,
      },
    ];

    int debtCount = 0;
    for (final row in debtRows) {
      try {
        final createdAt = nowMs - ((row['hoursAgo'] as int) * 3600000);
        final total = row['total'] as int;
        final paid = row['paid'] as int;
        final debtData = <String, dynamic>{
          'firestoreId': row['id'],
          'shopId': shopId,
          'personName': row['personName'],
          'customerName': row['personName'],
          'phone': row['phone'],
          'totalAmount': total,
          'paidAmount': paid,
          'remainAmount': (total - paid).clamp(0, total),
          'type': row['type'],
          'debtType': row['type'],
          'status': paid >= total ? 'PAID' : 'ACTIVE',
          'note': 'Seed debt $runTag',
          'createdAt': createdAt,
          'isSynced': 1,
          'deleted': false,
        };
        await FirestoreService.addDebtCloud(debtData);
        await _db.insertDebt(debtData);
        debtCount++;

        // Tạo 1 giao dịch thanh toán/thu nợ để test pipeline công nợ
        final payAmount = (total ~/ 4).clamp(500000, total - paid);
        if (payAmount > 0) {
          final paymentData = <String, dynamic>{
            'firestoreId': 'pay_${row['id']}_$runTag',
            'shopId': shopId,
            'debtFirestoreId': row['id'],
            'debtType': row['type'],
            'personName': row['personName'],
            'customerName': row['personName'],
            'amount': payAmount,
            'paymentMethod': (row['type'] == 'CUSTOMER_OWES')
                ? 'TIỀN MẶT'
                : 'CHUYỂN KHOẢN',
            'paidAt': createdAt + 7200000,
            'totalDebt': total,
            'alreadyPaid': paid,
            'receivedBy': 'SEED BOT',
            'createdAt': createdAt + 7200000,
            'isSynced': 1,
            'deleted': 0,
          };
          await FirestoreService.addDebtPaymentCloud(paymentData);
          await _db.insertDebtPayment(paymentData);
        }
      } catch (e) {
        debugPrint('⚠️ seedBusinessFlowDebtsAndPayments error: $e');
      }
    }

    log.writeln('✅ Công nợ: $debtCount hồ sơ (KH/NCC/Đối tác) + giao dịch thu/trả nợ');
  }

  static Future<void> _seedBusinessFlowIncomeExpense({
    required String runTag,
    required String shopId,
    required int nowMs,
    required StringBuffer log,
  }) async {
    final flows = <Map<String, dynamic>>[
      {
        'title': 'Chi lương nhân viên tháng này',
        'amount': 22000000,
        'category': 'Lương',
        'paymentMethod': 'CHUYỂN KHOẢN',
        'type': 'CHI',
        'hoursAgo': 22,
      },
      {
        'title': 'Chi phí vận hành shop',
        'amount': 3500000,
        'category': 'Chi phí shop',
        'paymentMethod': 'TIỀN MẶT',
        'type': 'CHI',
        'hoursAgo': 19,
      },
      {
        'title': 'Chi cá nhân chủ shop',
        'amount': 1200000,
        'category': 'Chi cá nhân',
        'paymentMethod': 'TIỀN MẶT',
        'type': 'CHI',
        'hoursAgo': 17,
      },
      {
        'title': 'Thu thêm từ dịch vụ ngoài',
        'amount': 1800000,
        'category': 'Thu thêm',
        'paymentMethod': 'CHUYỂN KHOẢN',
        'type': 'THU',
        'hoursAgo': 15,
      },
    ];

    int count = 0;
    for (int i = 0; i < flows.length; i++) {
      final row = flows[i];
      try {
        final ts = nowMs - ((row['hoursAgo'] as int) * 3600000);
        final exp = <String, dynamic>{
          'firestoreId': 'exp_${runTag}_$i',
          'shopId': shopId,
          'title': row['title'],
          'amount': row['amount'],
          'category': row['category'],
          'date': ts,
          'paymentMethod': row['paymentMethod'],
          'type': row['type'],
          'note': 'Seed flow $runTag',
          'createdAt': ts,
          'isSynced': 1,
        };
        await FirestoreService.addExpenseCloud(exp);
        await _db.insertExpense(exp);
        count++;
      } catch (e) {
        debugPrint('⚠️ seedBusinessFlowIncomeExpense error: $e');
      }
    }

    log.writeln('✅ Thu/chi: $count dòng (lương, chi phí shop, chi cá nhân, thu thêm)');
  }
}
