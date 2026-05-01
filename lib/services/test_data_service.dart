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
import 'user_service.dart';

/// Service tạo dữ liệu mẫu toàn diện cho mục đích demo/kiểm thử.
/// Bao gồm: sản phẩm, bán hàng, sửa chữa, công nợ, chấm công,
/// lương nhân viên, nhà cung cấp, cộng đồng, chat, tài chính.
class TestDataService {
  static final _db = DBHelper();
  static final _fs = FirebaseFirestore.instance;

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
          day.weekday == DateTime.sunday) continue;
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
}
