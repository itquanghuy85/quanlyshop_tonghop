# BÁO CÁO PHÂN TÍCH TỔNG THỂ APP QUẢN LÝ SHOP

## Mục lục
1. Kiến trúc tổng thể (logic & nghiệp vụ)
2. Lỗi logic, code dư thừa/trùng, rủi ro tài chính, rủi ro bảo trì
3. Đề xuất kiến trúc tối ưu 3–5 năm
4. Cách refactor an toàn, không làm hỏng dữ liệu
5. Checklist sửa theo thứ tự an toàn

---

## 1. Kiến trúc tổng thể (logic & nghiệp vụ)

### 1.1. Tổng quan
- **Flutter + Firebase**: Quản lý cửa hàng sửa chữa điện thoại, đa tenant (nhiều shop), offline-first (SQLite sync Firestore).
- **Luồng chính**:
  - Đăng nhập → xác thực role → chọn shop → vào dashboard.
  - Quản lý: đơn sửa chữa, sản phẩm, bán hàng, công nợ, nhân sự, chấm công, chi phí.
  - Mọi thao tác ghi Firestore qua service, đồng bộ về local DB.
- **Phân quyền**: Super-admin (email cứng), admin/shop, nhân viên.
- **Tài chính**: Quản lý thu/chi, công nợ, tồn kho, báo cáo.
- **Đồng bộ**: Real-time Firestore → SQLite, soft delete, isSynced, conflict resolution.
- **Thông báo**: In-app, push, rate-limit.

### 1.2. Luồng dữ liệu
- **CRUD**: UI → Service → Firestore (có shopId) → SyncService → SQLite.
- **Đồng bộ**: Khi đăng nhập, khi có thay đổi Firestore, khi offline/online.
- **Tài chính**: Mọi thay đổi liên quan tiền đều qua service, có validate.
- **Trạng thái**: Đơn sửa chữa (enum 1–4), soft delete, cập nhật trạng thái.

### 1.3. Luồng nghiệp vụ
- **Đơn sửa chữa**: Tạo → cập nhật trạng thái → hoàn thành → thanh toán.
- **Bán hàng**: Kiểm tra tồn kho, trừ kho, ghi nhận doanh thu.
- **Công nợ**: Ghi nhận, thanh toán, validate không cho trả quá số nợ.
- **Nhân sự**: Chấm công, phân quyền, quản lý lương.
- **Chi phí**: Ghi nhận, báo cáo.

---

## 2. Lỗi logic, code dư thừa/trùng, rủi ro tài chính, rủi ro bảo trì

### 2.1. Lỗi logic & rủi ro tài chính
- **Bán vượt tồn kho**: Nếu thiếu validate, có thể bán âm kho.
- **Thanh toán công nợ vượt số nợ**: Nếu thiếu check, có thể trả quá số nợ.
- **Chuyển trạng thái đơn sửa chữa không hợp lệ**: Có thể nhảy trạng thái sai.
- **Đồng bộ lỗi**: Nếu mất kết nối, có thể mất dữ liệu hoặc sync sai.
- **Soft delete**: Nếu không kiểm tra deleted, có thể hiển thị dữ liệu rác.
- **Role check**: Nếu hardcode email, dễ bỏ sót quyền hoặc lộ quyền admin.

### 2.2. Code dư thừa/trùng
- **Service lặp code**: Một số hàm CRUD lặp lại validate, có thể gom lại.
- **Widget trùng lặp**: Một số UI component lặp lại logic hiển thị trạng thái, có thể tách widget.
- **Model toMap/fromMap**: Có thể sinh code tự động để tránh lỗi tay.

### 2.3. Rủi ro bảo trì lâu dài
- **Hardcode role/email**: Khó mở rộng, dễ lỗi khi đổi domain.
- **Sync phức tạp**: Nếu không test kỹ, dễ phát sinh bug khi nâng cấp DB.
- **Thiếu unit test**: Dễ phát sinh lỗi ngầm về tiền, kho, công nợ.
- **Tiền tệ/format**: Nếu parse tiền không chặt, dễ sai số khi nhập liệu.

---

## 3. Đề xuất kiến trúc tối ưu 3–5 năm

- **Tách rõ service layer**: Mọi thao tác Firestore/SQLite đều qua service, không gọi trực tiếp ở UI.
- **Bổ sung repository pattern**: Tách interface cho Firestore/SQLite, dễ test/mock.
- **Tách logic validate**: Gom validate tiền/kho/công nợ vào 1 chỗ, dùng lại toàn app.
- **Tách role/permission**: Không hardcode email, dùng role-based access control.
- **Bổ sung unit test**: Đặc biệt cho logic tiền, kho, công nợ.
- **Bổ sung migration cho SQLite**: Đảm bảo nâng cấp DB không mất dữ liệu.
- **Quy chuẩn hóa model**: Dùng codegen cho toMap/fromMap, tránh lỗi tay.
- **Tách config**: Đưa các giá trị cứng (email admin, trạng thái, enum) vào config/constant.

---

## 4. Cách refactor an toàn, không làm hỏng dữ liệu

- **Luôn backup DB trước khi refactor**.
- **Refactor từng bước nhỏ, test từng bước**.
- **Viết migration script cho SQLite khi đổi schema**.
- **Thêm unit test cho các hàm validate tiền/kho/công nợ trước khi sửa**.
- **Dùng SetOptions(merge: true) khi upsert Firestore để tránh overwrite**.
- **Test sync offline/online kỹ sau mỗi thay đổi**.
- **Không xóa code cũ ngay, comment lại và test kỹ trước khi remove**.

---

## 5. Checklist sửa theo thứ tự an toàn

1. **Bổ sung try-catch cho toàn bộ thao tác DB, async/await** (Phase 1)
2. **Validate bán hàng, công nợ, trạng thái đơn sửa chữa** (Phase 2)
3. **Bổ sung migration, chuẩn hóa format tiền, ảnh, locale** (Phase 3)
4. **Bổ sung CRUD còn thiếu, validate input, feedback UI** (Phase 4)
5. **Bổ sung unit test cho logic tài chính, kho, công nợ** (Phase 5)
6. **Tách role, config, chuẩn hóa model, refactor service** (song song, sau khi ổn định)

---

## Kết luận

- App có nền tảng tốt, nhưng cần bổ sung validate, test, chuẩn hóa model, tách role, migration DB để đảm bảo an toàn tài chính và bảo trì lâu dài.
- Ưu tiên fix crash, validate logic tiền/kho/công nợ, sau đó mới refactor lớn.
- Luôn làm từng bước nhỏ, test kỹ, không sửa hàng loạt.

---

Dưới đây là phân tích và đề xuất tối ưu riêng cho dòng tiền (quản lý thu/chi, công nợ, bán hàng) nhằm đảm bảo an toàn tài chính, dễ bảo trì, không rủi ro lâu dài:

1. Phân tích hiện trạng dòng tiền
1.1. Luồng nghiệp vụ liên quan dòng tiền
Bán hàng: Ghi nhận doanh thu, trừ tồn kho, cập nhật công nợ nếu khách chưa trả đủ.
Công nợ: Ghi nhận khi bán chịu, thanh toán từng phần, kiểm tra không cho trả vượt số nợ.
Chi phí: Ghi nhận chi phí vận hành, vật tư, lương, v.v.
Báo cáo: Tổng hợp thu/chi, tồn kho, công nợ theo thời gian.
1.2. Rủi ro tiềm ẩn
Bán vượt tồn kho: Nếu validate không chặt, có thể ghi nhận doanh thu ảo, âm kho.
Thanh toán công nợ vượt số nợ: Nếu không kiểm tra, có thể sinh số dư âm, sai báo cáo.
Ghi nhận chi phí sai loại: Dễ nhầm lẫn, ảnh hưởng báo cáo lợi nhuận.
Đồng bộ lỗi: Nếu sync lỗi, có thể mất hoặc nhân đôi giao dịch.
Format tiền tệ không chuẩn: Dễ sai số khi nhập/xuất dữ liệu, đặc biệt khi dùng nhiều locale.
1.3. Rủi ro bảo trì
Logic validate phân tán: Nếu validate tiền/kho/công nợ nằm rải rác, khó kiểm soát, dễ sót khi sửa.
Thiếu unit test: Dễ phát sinh lỗi ngầm, khó phát hiện khi nâng cấp.
Hardcode trạng thái, loại giao dịch: Khó mở rộng, dễ lỗi khi thêm loại mới.
2. Đề xuất tối ưu dòng tiền an toàn & dễ bảo trì
2.1. Tách riêng service quản lý dòng tiền
MoneyService: Gom toàn bộ logic liên quan thu/chi, công nợ, kiểm tra số dư, validate số tiền.
ExpenseService: Quản lý chi phí, phân loại rõ ràng, validate loại chi phí.
2.2. Chuẩn hóa model & transaction
Model giao dịch chuẩn: Mỗi giao dịch (thu, chi, công nợ) có các trường bắt buộc: amount, type, createdAt, relatedOrderId, note, userId, shopId.
Enum loại giao dịch: Không hardcode string, dùng enum/type rõ ràng cho các loại: SALE, DEBT_PAYMENT, EXPENSE, REFUND, v.v.
2.3. Gom validate về một nơi duy nhất
Validate số dư kho trước khi bán: Chỉ cho phép bán khi đủ hàng.
Validate số nợ trước khi thanh toán: Không cho phép trả vượt số nợ.
Validate số tiền hợp lệ: Không cho phép nhập số âm, số quá lớn, hoặc format sai.
Kiểm tra trạng thái đơn trước khi ghi nhận dòng tiền: Đảm bảo không ghi nhận doanh thu cho đơn chưa hoàn thành.
2.4. Đảm bảo đồng bộ an toàn
Giao dịch atomic: Mỗi thay đổi liên quan tiền phải là 1 transaction (Firestore batch hoặc local transaction).
Flag isSynced rõ ràng: Chỉ khi sync thành công mới cập nhật trạng thái đã đồng bộ.
Log lịch sử thay đổi: Lưu lại mọi thay đổi liên quan tiền để audit.
2.5. Chuẩn hóa format tiền tệ
Dùng 1 format duy nhất: Lưu số tiền dưới dạng số (int/num), không lưu string có dấu phẩy/chấm.
Format khi hiển thị: Chỉ format khi render ra UI, không lưu format vào DB.
2.6. Bổ sung unit test & báo cáo
Test cho mọi hàm validate tiền/kho/công nợ.
Test cho các trường hợp biên: bán hết hàng, trả hết nợ, nhập số tiền lớn/nhỏ.
Báo cáo đối soát: Có màn hình đối soát dòng tiền, phát hiện bất thường.
2.7. Tách config & trạng thái
Tách enum, trạng thái, loại giao dịch vào file constant/config.
Không hardcode email, role, loại giao dịch trong code.
3. Checklist triển khai tối ưu dòng tiền
Tạo MoneyService/ExpenseService gom toàn bộ logic liên quan tiền
Chuẩn hóa model giao dịch, dùng enum/type cho loại giao dịch
Gom validate về 1 nơi, gọi từ mọi điểm ghi nhận dòng tiền
Bổ sung unit test cho validate tiền/kho/công nợ
Đảm bảo mọi thao tác liên quan tiền là transaction, có log lịch sử
Chuẩn hóa format tiền tệ, chỉ format khi hiển thị
Tách enum, trạng thái, loại giao dịch vào constant/config
Bổ sung màn hình đối soát dòng tiền, phát hiện bất thường
4. Kết luận
Tách riêng service dòng tiền, gom validate, chuẩn hóa model, bổ sung test là chìa khóa để an toàn tài chính và bảo trì lâu dài.
Không để logic validate phân tán, không hardcode trạng thái/loại giao dịch.
Luôn kiểm tra số dư kho, số nợ, trạng thái đơn trước khi ghi nhận dòng tiền.
Đảm bảo đồng bộ an toàn, có log lịch sử, test kỹ mọi trường hợp biên.
Nếu cần ví dụ code hoặc checklist chi tiết cho từng bước, vui lòng xác nhận!