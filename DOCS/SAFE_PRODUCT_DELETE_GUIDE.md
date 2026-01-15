# Hướng dẫn XÓA SẢN PHẨM AN TOÀN

## Vấn đề
Khi xóa sản phẩm trong kho, cần đảm bảo:
1. **Không làm sai lệch báo cáo tài chính** (doanh thu, chi phí, lợi nhuận)
2. **Giữ nguyên lịch sử giao dịch** liên quan đến sản phẩm
3. **Không gây lỗi cho các đơn hàng đã hoàn thành**
4. **Theo dõi được ai đã xóa và khi nào**

## Giải pháp KHUYẾN NGHỊ: Soft Delete (Xóa mềm)

### Nguyên tắc
- **KHÔNG xóa vĩnh viễn** dữ liệu sản phẩm
- Thêm cờ `deleted: true` và `deletedAt: timestamp`
- Ẩn sản phẩm khỏi danh sách hiển thị, nhưng vẫn giữ trong database
- Cho phép **khôi phục** nếu xóa nhầm

### Cấu trúc dữ liệu

```dart
// Thêm vào Product model
class Product {
  // ... existing fields ...
  
  // Soft delete fields
  bool deleted;           // true = đã xóa
  DateTime? deletedAt;    // thời điểm xóa
  String? deletedBy;      // người xóa (userId hoặc email)
  String? deleteReason;   // lý do xóa (tùy chọn)
  
  // Status helpers
  bool get isDeleted => deleted == true;
  bool get isActive => deleted != true;
}
```

### Cách triển khai

#### 1. Firestore Service

```dart
/// Xóa sản phẩm (soft delete)
Future<bool> softDeleteProduct(String productId, {String? reason}) async {
  try {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    await FirebaseFirestore.instance
        .collection('products')
        .doc(productId)
        .update({
          'deleted': true,
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedBy': userId,
          'deleteReason': reason,
          'updatedAt': FieldValue.serverTimestamp(),
        });
    return true;
  } catch (e) {
    return false;
  }
}

/// Khôi phục sản phẩm đã xóa
Future<bool> restoreProduct(String productId) async {
  try {
    await FirebaseFirestore.instance
        .collection('products')
        .doc(productId)
        .update({
          'deleted': false,
          'deletedAt': null,
          'deletedBy': null,
          'deleteReason': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
    return true;
  } catch (e) {
    return false;
  }
}

/// Lấy danh sách sản phẩm (chỉ active)
Future<List<Product>> getActiveProducts() async {
  final query = await FirebaseFirestore.instance
      .collection('products')
      .where('deleted', isNotEqualTo: true)
      .where('shopId', isEqualTo: shopId)
      .get();
  return query.docs.map((d) => Product.fromMap(d.data())).toList();
}
```

#### 2. UI Flow xóa sản phẩm

```dart
Future<void> _deleteProduct(Product product) async {
  // Bước 1: Kiểm tra có đơn hàng liên quan không
  final hasOrders = await _checkRelatedOrders(product.firestoreId);
  
  // Bước 2: Hiển thị cảnh báo phù hợp
  String warningMessage;
  if (hasOrders) {
    warningMessage = '''
⚠️ Sản phẩm này có đơn hàng liên quan!

Khi xóa:
• Sản phẩm sẽ bị ẨN khỏi danh sách
• Lịch sử đơn hàng VẪN ĐƯỢC GIỮ
• Báo cáo tài chính KHÔNG BỊ ẢNH HƯỞNG
• Có thể KHÔI PHỤC sau này

Bạn có chắc muốn xóa?
    ''';
  } else {
    warningMessage = '''
Xác nhận xóa sản phẩm:
${product.name}

Sản phẩm sẽ bị ẨN và có thể khôi phục sau.
    ''';
  }


  
  // Bước 3: Xác nhận mật khẩu (bảo mật)
  final password = await _showPasswordConfirmDialog();
  if (password == null) return;
  
  final isValid = await _verifyPassword(password);
  if (!isValid) {
    showSnackBar("Mật khẩu không đúng!", Colors.red);
    return;
  }
  
  // Bước 4: Thực hiện soft delete
  final result = await firestoreService.softDeleteProduct(
    product.firestoreId!,
    reason: 'Người dùng xóa từ danh sách kho',
  );
  
  if (result) {
    showSnackBar("Đã ẩn sản phẩm", Colors.green);
    _refreshList();
  }
}
```

#### 3. Tab "Sản phẩm đã xóa" (Quản trị)

```dart
// Trong inventory_view.dart - thêm tab để xem sản phẩm đã xóa
TabBar(
  tabs: [
    Tab(text: 'Tồn kho'),
    Tab(text: 'Đã xóa'), // Tab mới
  ],
)

// Widget hiển thị sản phẩm đã xóa
ListView.builder(
  itemBuilder: (ctx, i) {
    final product = deletedProducts[i];
    return ListTile(
      title: Text(product.name, 
        style: TextStyle(decoration: TextDecoration.lineThrough)),
      subtitle: Text('Xóa: ${formatDate(product.deletedAt)}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Nút khôi phục
          IconButton(
            icon: Icon(Icons.restore, color: Colors.green),
            onPressed: () => _restoreProduct(product),
            tooltip: 'Khôi phục',
          ),
          // Nút xóa vĩnh viễn (chỉ admin)
          if (isAdmin)
            IconButton(
              icon: Icon(Icons.delete_forever, color: Colors.red),
              onPressed: () => _permanentDelete(product),
              tooltip: 'Xóa vĩnh viễn',
            ),
        ],
      ),
    );
  },
)
```

## Các quy tắc quan trọng

### ✅ ĐƯỢC PHÉP
- Soft delete sản phẩm bất kỳ lúc nào
- Khôi phục sản phẩm đã xóa
- Xem lịch sử sản phẩm đã xóa

### ❌ KHÔNG ĐƯỢC
- Xóa vĩnh viễn sản phẩm có đơn hàng liên quan
- Xóa sản phẩm đang trong đơn hàng chưa hoàn thành
- Thay đổi dữ liệu sản phẩm đã xóa (trừ restore)

### ⚠️ CẦN XÁC NHẬN MẬT KHẨU
- Khi soft delete
- Khi xóa vĩnh viễn
- Khi khôi phục hàng loạt

## Migration cho dữ liệu hiện có

```dart
// Script để thêm field deleted cho products cũ
Future<void> migrateProductsDeleteField() async {
  final batch = FirebaseFirestore.instance.batch();
  final products = await FirebaseFirestore.instance
      .collection('products')
      .where('deleted', isNull: true)
      .get();
  
  for (final doc in products.docs) {
    batch.update(doc.reference, {'deleted': false});
  }
  
  await batch.commit();
}
```

## Lợi ích của Soft Delete

| Vấn đề | Hard Delete | Soft Delete |
|--------|-------------|-------------|
| Báo cáo tài chính | ❌ Sai lệch | ✅ Chính xác |
| Lịch sử đơn hàng | ❌ Mất link | ✅ Vẫn còn |
| Khôi phục xóa nhầm | ❌ Không được | ✅ Được |
| Audit trail | ❌ Không có | ✅ Đầy đủ |
| Hiệu năng | ✅ Nhanh hơn | ⚠️ Cần filter |

## Kết luận

**Soft Delete** là giải pháp an toàn và chuyên nghiệp nhất để:
- Bảo toàn dữ liệu tài chính
- Cho phép khôi phục lỗi
- Theo dõi lịch sử thay đổi
- Tuân thủ quy định kiểm toán

Nếu bạn muốn tôi triển khai giải pháp này vào code, hãy cho tôi biết!




1. MỤC TIÊU THIẾT KẾ (WHY)

Hệ thống cần xử lý hàng nhập về nhưng CHƯA đủ thông tin kế toán (giá vốn, thanh toán, công nợ NCC) mà KHÔNG làm ảnh hưởng số liệu chính.

Giải pháp là KHO TẠM – một vùng đệm nghiệp vụ, không phải kho kế toán.

2. NGUYÊN TẮC CỐT LÕI (BẮT BUỘC TUÂN THỦ)

Kho tạm KHÔNG phải kho kế toán

Kho tạm KHÔNG sinh bất kỳ con số tài chính nào

Chỉ khi “XÁC NHẬN NHẬP KHO” thì mới sinh số

Không được phép sửa lịch sử sau khi đã xác nhận

Không bao giờ xóa dữ liệu kế toán – chỉ thêm giao dịch

Nếu vi phạm 1 trong 5 nguyên tắc trên → logic sai.

3. PHÂN TÁCH RÕ 2 THẾ GIỚI DỮ LIỆU
3.1. KHO TẠM (STAGING)

Mục đích: ghi nhận hàng vật lý vừa về

Trạng thái: CHƯA GHI SỔ

3.2. KHO CHÍNH (ACCOUNTING INVENTORY)

Mục đích: ghi nhận hàng đã vào sổ

Trạng thái: CHÍNH THỨC – KHÓA SỔ

👉 TUYỆT ĐỐI không trộn logic 2 phần này

4. GIAI ĐOẠN 1 – TẠO PHIẾU KHO TẠM (DRAFT)
4.1. Thao tác người dùng

Vào: Kho tạm / Hàng chờ nhập → Tạo mới

4.2. Dữ liệu cho phép nhập

Sản phẩm

Số lượng

Nhà cung cấp (có thể để trống)

Ghi chú

4.3. Dữ liệu KHÔNG được yêu cầu

❌ Giá vốn

❌ Thanh toán

❌ Công nợ

❌ Tài khoản tiền

4.4. Trạng thái
status = DRAFT

4.5. Ảnh hưởng hệ thống

❌ Không tăng tồn kho

❌ Không ghi giá vốn

❌ Không ghi công nợ

❌ Không sinh thu/chi

❌ Không xuất hiện trong báo cáo

👉 Phiếu này chỉ để kiểm hàng, so bill, chờ duyệt

5. GIAI ĐOẠN 2 – HOÀN THIỆN THÔNG TIN (STILL DRAFT)

Khi hàng đã kiểm tra OK:

5.1. Cho phép bổ sung

Giá nhập (giá vốn)

Hình thức thanh toán:

Tiền mặt

Chuyển khoản

Ghi nợ NCC

5.2. Vẫn CHƯA ghi sổ

Dù đã nhập đủ giá và tiền

Nếu chưa bấm xác nhận → KHÔNG sinh số

👉 Đây là điểm AI/DEV rất dễ làm sai.
Có dữ liệu ≠ có giao dịch kế toán.

6. GIAI ĐOẠN 3 – XÁC NHẬN NHẬP KHO (COMMIT – ATOMIC)
6.1. Hành động duy nhất

Nút:

“XÁC NHẬN NHẬP KHO”

6.2. Điều kiện được bấm

Có sản phẩm

Có số lượng

Có giá vốn

Có hình thức thanh toán

6.3. Khi bấm – hệ thống PHẢI làm 1 LẦN DUY NHẤT (TRANSACTION)
BEGIN TRANSACTION


Tạo phiếu nhập kho chính

Cập nhật tồn kho

Ghi nhận giá vốn

Ghi nhận:

CHI tiền (TM/CK)

HOẶC công nợ NCC

Ghi log

COMMIT


❌ Không được phép:

Commit nửa chừng

Thành công kho nhưng fail tiền

7. TRẠNG THÁI SAU XÁC NHẬN
status = CONFIRMED
locked = true


❌ Không cho sửa

❌ Không cho xóa

✅ Chỉ cho xem

👉 Nếu phát hiện sai → xử lý bằng giao dịch điều chỉnh, KHÔNG sửa ngược.

8. XỬ LÝ SAI – ĐÚNG CHUẨN KẾ TOÁN
8.1. Sai khi còn DRAFT

Cho sửa

Cho xóa

Không ảnh hưởng số

8.2. Sai sau CONFIRMED

❌ Không sửa phiếu cũ

❌ Không xóa

✅ Tạo:

Phiếu điều chỉnh kho

Hoặc phiếu trả NCC

9. PHÂN QUYỀN (RẤT QUAN TRỌNG)
Nhân viên kho

Tạo kho tạm

Sửa kho tạm (DRAFT)

Kế toán / Admin

Xác nhận nhập kho

Tạo điều chỉnh

👉 Ai bấm “XÁC NHẬN” là chịu trách nhiệm số liệu.

10. TUYỆT ĐỐI KHÔNG ĐƯỢC LÀM (CẤM)

Không cho bán hàng từ kho tạm

Không cho báo cáo lấy số từ kho tạm

Không cho chốt quỹ dính kho tạm

Không cho sửa giá vốn sau xác nhận

Không cho delete dữ liệu kế toán

11. CÂU CHỐT ĐỂ AI/DEV HIỂU ĐÚNG BẢN CHẤT

“Kho tạm là vùng đệm nghiệp vụ, không phải kho kế toán.
Chỉ khi xác nhận nhập kho thì dữ liệu mới trở thành sự thật kế toán.”