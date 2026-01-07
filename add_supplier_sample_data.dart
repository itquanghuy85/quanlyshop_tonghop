import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

void main() async {
  // Mở database
  final database = openDatabase(
    join(await getDatabasesPath(), 'repair_shop_v22.db'),
    version: 17,
  );

  final db = await database;

  // Thêm dữ liệu mẫu cho supplier
  await db.insert('suppliers', {
    'name': 'Nhà cung cấp ABC',
    'phone': '0123456789',
    'email': 'abc@supplier.com',
    'address': '123 Đường ABC, Quận 1, TP.HCM',
    'notes': 'Nhà cung cấp uy tín',
    'createdAt': DateTime.now().millisecondsSinceEpoch,
    'shopId': 'honC8KnKhOUG19wcYOFDTGVdKWP2',
  });

  final supplierResult = await db.query('suppliers', where: 'name = ?', whereArgs: ['Nhà cung cấp ABC']);
  final supplierId = supplierResult.first['id'];

  // Thêm dữ liệu lịch sử nhập hàng mẫu
  final importData = [
    {
      'supplierId': supplierId,
      'supplierName': 'Nhà cung cấp ABC',
      'productName': 'iPhone 12 Pro Max',
      'productBrand': 'Apple',
      'productModel': 'iPhone 12 Pro Max 128GB',
      'imei': '123456789012345',
      'quantity': 1,
      'costPrice': 15000000,
      'totalAmount': 15000000,
      'paymentMethod': 'Tiền mặt',
      'importDate': DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch,
      'importedBy': 'huy@hu.com',
      'notes': 'Máy mới 100%',
      'shopId': 'honC8KnKhOUG19wcYOFDTGVdKWP2',
    },
    {
      'supplierId': supplierId,
      'supplierName': 'Nhà cung cấp ABC',
      'productName': 'Samsung Galaxy S21',
      'productBrand': 'Samsung',
      'productModel': 'Galaxy S21 256GB',
      'imei': '987654321098765',
      'quantity': 1,
      'costPrice': 12000000,
      'totalAmount': 12000000,
      'paymentMethod': 'Chuyển khoản',
      'importDate': DateTime.now().subtract(const Duration(days: 20)).millisecondsSinceEpoch,
      'importedBy': 'huy@hu.com',
      'notes': 'Máy đẹp',
      'shopId': 'honC8KnKhOUG19wcYOFDTGVdKWP2',
    },
    {
      'supplierId': supplierId,
      'supplierName': 'Nhà cung cấp ABC',
      'productName': 'iPhone 13',
      'productBrand': 'Apple',
      'productModel': 'iPhone 13 128GB',
      'imei': '456789012345678',
      'quantity': 2,
      'costPrice': 18000000,
      'totalAmount': 36000000,
      'paymentMethod': 'Tiền mặt',
      'importDate': DateTime.now().subtract(const Duration(days: 10)).millisecondsSinceEpoch,
      'importedBy': 'huy@hu.com',
      'notes': '2 máy cùng lúc',
      'shopId': 'honC8KnKhOUG19wcYOFDTGVdKWP2',
    },
    {
      'supplierId': supplierId,
      'supplierName': 'Nhà cung cấp ABC',
      'productName': 'Xiaomi Redmi Note 10',
      'productBrand': 'Xiaomi',
      'productModel': 'Redmi Note 10 64GB',
      'imei': '789012345678901',
      'quantity': 1,
      'costPrice': 4000000,
      'totalAmount': 4000000,
      'paymentMethod': 'Tiền mặt',
      'importDate': DateTime.now().subtract(const Duration(days: 5)).millisecondsSinceEpoch,
      'importedBy': 'huy@hu.com',
      'notes': 'Máy Android giá rẻ',
      'shopId': 'honC8KnKhOUG19wcYOFDTGVdKWP2',
    },
    {
      'supplierId': supplierId,
      'supplierName': 'Nhà cung cấp ABC',
      'productName': 'iPhone 14 Pro',
      'productBrand': 'Apple',
      'productModel': 'iPhone 14 Pro 256GB',
      'imei': '012345678901234',
      'quantity': 1,
      'costPrice': 25000000,
      'totalAmount': 25000000,
      'paymentMethod': 'Chuyển khoản',
      'importDate': DateTime.now().subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      'importedBy': 'huy@hu.com',
      'notes': 'Máy mới nhất',
      'shopId': 'honC8KnKhOUG19wcYOFDTGVdKWP2',
    },
  ];

  for (final data in importData) {
    await db.insert('supplier_import_history', data);
  }

  // Thêm dữ liệu giá sản phẩm
  final priceData = [
    {
      'supplierId': supplierId,
      'productName': 'iPhone 12 Pro Max',
      'productBrand': 'Apple',
      'productModel': 'iPhone 12 Pro Max 128GB',
      'costPrice': 15000000,
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      'shopId': 'honC8KnKhOUG19wcYOFDTGVdKWP2',
    },
    {
      'supplierId': supplierId,
      'productName': 'Samsung Galaxy S21',
      'productBrand': 'Samsung',
      'productModel': 'Galaxy S21 256GB',
      'costPrice': 12000000,
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      'shopId': 'honC8KnKhOUG19wcYOFDTGVdKWP2',
    },
    {
      'supplierId': supplierId,
      'productName': 'iPhone 13',
      'productBrand': 'Apple',
      'productModel': 'iPhone 13 128GB',
      'costPrice': 18000000,
      'lastUpdated': DateTime.now().millisecondsSinceEpoch,
      'shopId': 'honC8KnKhOUG19wcYOFDTGVdKWP2',
    },
  ];

  for (final data in priceData) {
    await db.insert('supplier_product_prices', data);
  }

  print('Đã thêm dữ liệu mẫu thành công!');
  print('Supplier ID: $supplierId');
}