/// Script tạo dữ liệu test cho shop settings
/// Chạy bằng: dart run scripts/seed_shop_settings.dart
///
/// Script này tạo shop_settings document trong Firestore cho các shop test
/// với các loại ngành kinh doanh khác nhau.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

/// Tạo shop settings cho loại ngành điện tử
Map<String, dynamic> electronicsSettings(String shopId) => {
      'shopId': shopId,
      'businessType': 'electronics',
      'businessTypeName': 'Điện thoại & Điện tử',
      'enableRepair': true,
      'enableExpiry': false,
      'enableVariants': false,
      'enableSerial': true,
      'enableWarranty': true,
      'enableBatch': false,
      'defaultUnit': 'cái',
      'expiryWarningDays': 7,
      'lowStockWarning': 5,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isSynced': true,
    };

/// Tạo shop settings cho loại ngành thực phẩm
Map<String, dynamic> foodSettings(String shopId) => {
      'shopId': shopId,
      'businessType': 'food',
      'businessTypeName': 'Thực phẩm & Đồ tươi sống',
      'enableRepair': false,
      'enableExpiry': true,
      'enableVariants': false,
      'enableSerial': false,
      'enableWarranty': false,
      'enableBatch': true,
      'defaultUnit': 'kg',
      'expiryWarningDays': 7,
      'lowStockWarning': 10,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isSynced': true,
    };

/// Tạo shop settings cho loại ngành thời trang
Map<String, dynamic> fashionSettings(String shopId) => {
      'shopId': shopId,
      'businessType': 'fashion',
      'businessTypeName': 'Thời trang & May mặc',
      'enableRepair': false,
      'enableExpiry': false,
      'enableVariants': true,
      'enableSerial': false,
      'enableWarranty': false,
      'enableBatch': false,
      'defaultUnit': 'cái',
      'expiryWarningDays': 0,
      'lowStockWarning': 3,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isSynced': true,
    };

/// Tạo shop settings cho loại ngành tổng hợp
Map<String, dynamic> generalSettings(String shopId) => {
      'shopId': shopId,
      'businessType': 'general',
      'businessTypeName': 'Tổng hợp',
      'enableRepair': false,
      'enableExpiry': false,
      'enableVariants': false,
      'enableSerial': false,
      'enableWarranty': false,
      'enableBatch': false,
      'defaultUnit': 'cái',
      'expiryWarningDays': 0,
      'lowStockWarning': 5,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'isSynced': true,
    };

/// Seed shop settings vào Firestore
Future<void> seedShopSettings(String shopId, String businessType) async {
  final db = FirebaseFirestore.instance;
  final settingsRef = db.collection('shops').doc(shopId).collection('settings').doc('shop_settings');
  
  Map<String, dynamic> settings;
  switch (businessType) {
    case 'electronics':
      settings = electronicsSettings(shopId);
      break;
    case 'food':
      settings = foodSettings(shopId);
      break;
    case 'fashion':
      settings = fashionSettings(shopId);
      break;
    case 'general':
    default:
      settings = generalSettings(shopId);
  }
  
  await settingsRef.set(settings, SetOptions(merge: true));
  print('✅ Created $businessType settings for shop: $shopId');
}

/// Main function - chạy khi gọi script
Future<void> main() async {
  print('🚀 Shop Settings Seed Script');
  print('=============================');
  print('');
  print('Hướng dẫn sử dụng:');
  print('1. Mở Firebase Console: https://console.firebase.google.com');
  print('2. Vào Firestore Database');
  print('3. Tìm collection shops > [shopId] > settings');
  print('4. Tạo document với id: shop_settings');
  print('5. Thêm các field theo mẫu dưới đây:');
  print('');
  
  print('=== ELECTRONICS (Điện thoại) ===');
  print('''
{
  "shopId": "<your_shop_id>",
  "businessType": "electronics",
  "businessTypeName": "Điện thoại & Điện tử",
  "enableRepair": true,
  "enableExpiry": false,
  "enableVariants": false,
  "enableSerial": true,
  "enableWarranty": true,
  "enableBatch": false,
  "defaultUnit": "cái",
  "expiryWarningDays": 7,
  "lowStockWarning": 5,
  "isSynced": true
}
''');

  print('=== FOOD (Thực phẩm) ===');
  print('''
{
  "shopId": "<your_shop_id>",
  "businessType": "food",
  "businessTypeName": "Thực phẩm & Đồ tươi sống",
  "enableRepair": false,
  "enableExpiry": true,
  "enableVariants": false,
  "enableSerial": false,
  "enableWarranty": false,
  "enableBatch": true,
  "defaultUnit": "kg",
  "expiryWarningDays": 7,
  "lowStockWarning": 10,
  "isSynced": true
}
''');

  print('=== FASHION (Thời trang) ===');
  print('''
{
  "shopId": "<your_shop_id>",
  "businessType": "fashion",
  "businessTypeName": "Thời trang & May mặc",
  "enableRepair": false,
  "enableExpiry": false,
  "enableVariants": true,
  "enableSerial": false,
  "enableWarranty": false,
  "enableBatch": false,
  "defaultUnit": "cái",
  "expiryWarningDays": 0,
  "lowStockWarning": 3,
  "isSynced": true
}
''');

  print('=== GENERAL (Tổng hợp) ===');
  print('''
{
  "shopId": "<your_shop_id>",
  "businessType": "general",
  "businessTypeName": "Tổng hợp",
  "enableRepair": false,
  "enableExpiry": false,
  "enableVariants": false,
  "enableSerial": false,
  "enableWarranty": false,
  "enableBatch": false,
  "defaultUnit": "cái",
  "expiryWarningDays": 0,
  "lowStockWarning": 5,
  "isSynced": true
}
''');

  print('=============================');
  print('📍 Firestore path: shops/{shopId}/settings/shop_settings');
}
