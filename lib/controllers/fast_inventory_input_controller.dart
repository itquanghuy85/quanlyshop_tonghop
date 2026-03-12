import '../data/db_helper.dart';
import '../models/product_model.dart';
import '../services/user_service.dart';
import '../services/firestore_service.dart';
import '../services/supplier_service.dart';
import '../utils/sku_generator.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FastInventoryInputController {
  final DBHelper db = DBHelper();

  // Cached data
  static List<Map<String, dynamic>>? _cachedSuppliers;
  static Map<String, dynamic>? _cachedSettings;

  // Get cached suppliers
  Future<List<Map<String, dynamic>>> getSuppliers() async {
    if (_cachedSuppliers == null) {
      final supplierService = SupplierService();
      final suppliers = await supplierService.getSuppliers();
      _cachedSuppliers = suppliers.map((s) => s.toMap()).toList();
    }
    return _cachedSuppliers!;
  }

  // Clear supplier cache (call when suppliers are modified)
  void clearSupplierCache() {
    _cachedSuppliers = null;
  }

  // Get cached settings
  Future<Map<String, dynamic>> getSettings() async {
    _cachedSettings ??= await _loadSettings();
    return _cachedSettings!;
  }

  Future<Map<String, dynamic>> _loadSettings() async {
    // TODO: Load from SharedPreferences if needed
    return {};
  }

  // Pre-validation
  String? validateProductData({
    required String sku,
    required String supplier,
    required String cost,
    required String retail,
  }) {
    if (sku.isEmpty) return "Vui lòng tạo mã hàng trước!";
    if (supplier.isEmpty) return "Vui lòng chọn Nhà cung cấp!";
    if (cost.isEmpty || int.tryParse(cost.replaceAll('.', '')) == null) {
      return "Giá nhập không hợp lệ!";
    }
    if (retail.isEmpty || int.tryParse(retail.replaceAll('.', '')) == null) {
      return "Giá bán không hợp lệ!";
    }
    return null; // Valid
  }

  // Generate SKU
  Future<String> generateSKU({
    required String group,
    String? model,
    String? info,
  }) async {
    return await SKUGenerator.generateSKU(
      nhom: group,
      model: model,
      thongtin: info,
      dbHelper: db,
      firestoreService: null,
    );
  }

  // Batch save with transaction
  Future<void> saveProductBatch(Map<String, dynamic> productData) async {
    final database = await db.database;
    final suppliers = await getSuppliers();
    final shopId = UserService.getShopIdSync() ??
        await UserService.getCurrentShopId();

    await database.transaction((txn) async {
      // 1. Create and upsert product
      final product = _createProductFromData(productData);
      await _upsertInTxn(txn, 'products', product.toMap(), product.firestoreId!);

      // 2. Handle finance operations
      await _handleFinanceInTxn(txn, productData, product);

      // 3. Handle supplier operations
      await _handleSupplierOperationsInTxn(
        txn,
        productData,
        product,
        suppliers,
        shopId,
      );
    });

    // 4. Log action (outside transaction)
    final product = _createProductFromData(productData);
    await _logAction(productData, product);

    // 5. Sync to Firestore (outside transaction as it's network)
    await FirestoreService.addProduct(product);
  }

  // Save multiple products in parallel
  Future<void> saveBatchProducts(List<Map<String, dynamic>> batchItems) async {
    for (final item in batchItems) {
      await saveProductBatch(item);
    }
  }

  Product _createProductFromData(Map<String, dynamic> data) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final imei = data['imei'] ?? '';
    final fId = "prod_${ts}_${imei.isNotEmpty ? imei : ts}";

    return Product(
      firestoreId: fId,
      name: data['name'],
      model: data['model'],
      imei: imei,
      cost: data['cost'],
      price: data['price'],
      capacity: data['capacity'],
      quantity: data['quantity'] ?? 1,
      type: data['type'],
      createdAt: ts,
      supplier: data['supplier'],
      status: 1,
    );
  }

  Future<void> _upsertInTxn(dynamic txn, String table, Map<String, dynamic> map, String firestoreId) async {
    final List<Map<String, dynamic>> existing = await txn.query(
      table,
      where: 'firestoreId = ?',
      whereArgs: [firestoreId],
      limit: 1
    );

    Map<String, dynamic> data = Map<String, dynamic>.from(map);
    data.remove('id');

    if (existing.isNotEmpty) {
      await txn.update(table, data, where: 'id = ?', whereArgs: [existing.first['id']]);
    } else {
      await txn.insert(table, data);
    }
  }

  Future<void> _handleFinanceInTxn(dynamic txn, Map<String, dynamic> data, Product product) async {
    if (data['paymentMethod'] != "CÔNG NỢ") {
      // Insert expense
      final expense = {
        'firestoreId': "exp_${DateTime.now().millisecondsSinceEpoch}",
        'title': "NHẬP HÀNG: ${product.name}",
        'amount': product.cost * product.quantity,
        'category': "NHẬP HÀNG",
        'date': product.createdAt,
        'paymentMethod': data['paymentMethod'],
        'note': "Nhập từ ${data['supplier']}",
        'isSynced': 0,
      };
      await txn.insert('expenses', expense);
    } else {
      // Insert debt
      final debt = {
        'firestoreId': "debt_${product.createdAt}",
        'personName': data['supplier'],
        'totalAmount': product.cost * product.quantity,
        'paidAmount': 0,
        'type': "SHOP_OWES",
        'status': "unpaid",
        'createdAt': product.createdAt,
        'note': "Nợ tiền máy ${product.name}",
        'isSynced': 0,
      };
      await txn.insert('debts', debt);
    }
  }

  Future<void> _logAction(Map<String, dynamic> data, Product product) async {
    // Log action outside transaction since it might need special handling
    final user = FirebaseAuth.instance.currentUser;
    final userName = user?.email?.split('@').first.toUpperCase() ?? "NV";

    await db.logAction(
      userId: user?.uid ?? "0",
      userName: userName,
      action: "NHẬP KHO",
      type: "PRODUCT",
      targetId: product.imei,
      desc: "Đã nhập máy ${product.name}",
    );
  }
  Future<void> _handleSupplierOperationsInTxn(
    dynamic txn,
    Map<String, dynamic> data,
    Product product,
    List<Map<String, dynamic>> suppliers,
    String? shopId,
  ) async {
    final supplierData = suppliers.firstWhere(
      (s) {
        if (s['name'] != data['supplier']) return false;
        if (s['deleted'] == 1 || s['deleted'] == true) return false;
        if (shopId == null || shopId.isEmpty) return true;
        final supplierShopId = s['shopId'] as String?;
        return supplierShopId == null ||
            supplierShopId.isEmpty ||
            supplierShopId == shopId;
      },
      orElse: () => {},
    );

    if (supplierData.isNotEmpty) {
      final supplierId = supplierData['id'];

      // Insert import history
      final importHistory = {
        'supplierId': supplierId,
        'supplierName': data['supplier'],
        'productName': product.name,
        'productBrand': product.brand ?? '',
        'productModel': product.model,
        'imei': product.imei,
        'quantity': product.quantity,
        'costPrice': product.cost,
        'totalAmount': product.cost * product.quantity,
        'paymentMethod': data['paymentMethod'],
        'importDate': product.createdAt,
        'importedBy': data['importedBy'] ?? "NV",
        'notes': 'Nhập từ Fast Inventory Input',
        'shopId': shopId,
        'isSynced': 0,
      };
      await txn.insert('supplier_import_history', importHistory);

      // Update supplier product price
      await txn.rawUpdate(
        'UPDATE supplier_product_prices SET isActive = 0 WHERE supplierId = ? AND productName = ? AND productBrand = ? AND (productModel = ? OR productModel IS NULL)',
        [supplierId, product.name, product.brand ?? '', product.model]
      );

      final supplierPrice = {
        'supplierId': supplierId,
        'productName': product.name,
        'productBrand': product.brand ?? '',
        'productModel': product.model,
        'costPrice': product.cost,
        'lastUpdated': product.createdAt,
        'createdAt': product.createdAt,
        'isActive': 1,
        'shopId': shopId,
      };
      await txn.insert('supplier_product_prices', supplierPrice);

      // Update supplier stats
      await _updateSupplierStatsInTxn(txn, supplierId);
    }
  }

  Future<void> _updateSupplierStatsInTxn(dynamic txn, int supplierId) async {
    final stats = await txn.rawQuery('''
      SELECT
        COUNT(*) as totalImports,
        SUM(totalAmount) as totalAmount
      FROM supplier_import_history
      WHERE supplierId = ?
    ''', [supplierId]);

    if (stats.isNotEmpty) {
      final totalImports = stats.first['totalImports'] ?? 0;
      final totalAmount = stats.first['totalAmount'] ?? 0;

      await txn.update(
        'suppliers',
        {
          'importCount': totalImports,
          'totalAmount': totalAmount,
        },
        where: 'id = ?',
        whereArgs: [supplierId],
      );
    }
  }

  // Load recent products
  Future<List<Product>> loadRecentProducts() async {
    final products = await db.getInStockProducts();
    products.sort((a, b) => (b.createdAt ?? 0).compareTo(a.createdAt ?? 0));
    return products.take(10).toList();
  }

  // Clear cache when needed
  static void clearCache() {
    _cachedSuppliers = null;
    _cachedSettings = null;
  }
}