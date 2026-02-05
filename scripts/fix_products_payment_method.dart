/// Script để cập nhật paymentMethod cho các sản phẩm cũ
/// Chạy script này trong Firestore Console hoặc qua Cloud Functions
/// 
/// Cách chạy:
/// 1. Mở Firebase Console > Firestore Database
/// 2. Hoặc tạo Cloud Function để chạy script này
/// 
/// Logic:
/// - Nếu product có supplierId và supplier_debts có record → paymentMethod = 'CÔNG NỢ'
/// - Nếu product có stockEntryId → lấy paymentMethod từ stock_entries
/// - Mặc định → 'TIỀN MẶT'
library;

/*
// JavaScript code để chạy trong Cloud Functions hoặc Node.js script

const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function fixProductsPaymentMethod() {
  const productsRef = db.collection('products');
  const snapshot = await productsRef.where('paymentMethod', '==', null).get();
  
  console.log(`Found ${snapshot.size} products without paymentMethod`);
  
  const batch = db.batch();
  let count = 0;
  
  for (const doc of snapshot.docs) {
    const data = doc.data();
    let paymentMethod = 'TIỀN MẶT'; // Default
    
    // Nếu có stockEntryId, lấy paymentMethod từ stock_entries
    if (data.stockEntryId) {
      const entryDoc = await db.collection('stock_entries').doc(data.stockEntryId).get();
      if (entryDoc.exists) {
        paymentMethod = entryDoc.data().paymentMethod || 'TIỀN MẶT';
      }
    }
    // Nếu có supplierId và có debt record → CÔNG NỢ
    else if (data.supplierId) {
      const debtSnap = await db.collection('supplier_debts')
        .where('supplierId', '==', data.supplierId)
        .where('shopId', '==', data.shopId)
        .limit(1)
        .get();
      
      if (!debtSnap.empty) {
        paymentMethod = 'CÔNG NỢ';
      }
    }
    
    batch.update(doc.ref, { 
      paymentMethod: paymentMethod,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    count++;
    
    // Firestore batch limit is 500
    if (count % 500 === 0) {
      await batch.commit();
      console.log(`Updated ${count} products...`);
    }
  }
  
  if (count % 500 !== 0) {
    await batch.commit();
  }
  
  console.log(`✅ Done! Updated ${count} products with paymentMethod`);
}

// Chạy function
fixProductsPaymentMethod().catch(console.error);
*/

/// ============================================================
/// HƯỚNG DẪN CHẠY NHANH TRONG FIREBASE CONSOLE
/// ============================================================
/// 
/// 1. Mở Firebase Console: https://console.firebase.google.com
/// 2. Chọn project "huyaka-1809"
/// 3. Vào Firestore Database
/// 4. Tìm collection "products"
/// 5. Với mỗi product thiếu paymentMethod:
///    - Click vào document
///    - Click "Add field"
///    - Field name: paymentMethod
///    - Type: string
///    - Value: TIỀN MẶT (hoặc CÔNG NỢ hoặc CHUYỂN KHOẢN tùy thực tế)
/// 
/// HOẶC dùng Cloud Shell:
/// 
/// ```bash
/// # Trong Firebase Console, click vào Cloud Shell icon
/// # Chạy các lệnh sau:
/// 
/// gcloud firestore documents list projects/huyaka-1809/databases/(default)/documents/products --filter="paymentMethod=null"
/// ```

/// ============================================================
/// DART CODE ĐỂ FIX TRONG APP (chạy 1 lần)
/// ============================================================
/// 
/// Thêm đoạn code sau vào một nơi trong app và chạy 1 lần:
/// 
/// ```dart
/// import 'package:cloud_firestore/cloud_firestore.dart';
/// 
/// Future<void> fixProductsPaymentMethod() async {
///   final firestore = FirebaseFirestore.instance;
///   final shopId = UserService.getCurrentShopId();
///   
///   // Lấy tất cả products của shop
///   final snapshot = await firestore
///       .collection('products')
///       .where('shopId', isEqualTo: shopId)
///       .where('deleted', isEqualTo: false)
///       .get();
///   
///   int fixed = 0;
///   final batch = firestore.batch();
///   
///   for (final doc in snapshot.docs) {
///     final data = doc.data();
///     
///     // Chỉ fix nếu chưa có paymentMethod
///     if (data['paymentMethod'] == null) {
///       String paymentMethod = 'TIỀN MẶT';
///       
///       // Nếu có stockEntryId, lấy từ stock_entries
///       if (data['stockEntryId'] != null) {
///         final entryDoc = await firestore
///             .collection('stock_entries')
///             .doc(data['stockEntryId'])
///             .get();
///         if (entryDoc.exists) {
///           paymentMethod = entryDoc.data()?['paymentMethod'] ?? 'TIỀN MẶT';
///         }
///       }
///       
///       batch.update(doc.reference, {
///         'paymentMethod': paymentMethod,
///         'updatedAt': FieldValue.serverTimestamp(),
///       });
///       fixed++;
///     }
///   }
///   
///   if (fixed > 0) {
///     await batch.commit();
///     print('✅ Fixed $fixed products with paymentMethod');
///   }
/// }
/// ```

void main() {
  print('Script hướng dẫn fix paymentMethod cho products cũ');
  print('Xem comments trong file để biết cách chạy');
}
