# Hướng dẫn cập nhật Trung tâm hướng dẫn

## 1. Mục tiêu
- Cung cấp tài liệu chính thức cho nhân sự sử dụng app Shopmanager.
- Đảm bảo nội dung luôn đồng bộ giữa dữ liệu nội bộ và giao diện người dùng.
- Chuẩn hóa quy trình thêm/chỉnh sửa các chủ đề hướng dẫn mới.

## 2. Kiến trúc tính năng
### 2.1 Tệp nguồn dữ liệu
- `lib/data/help_center_repository.dart` chứa danh sách `HelpCategory` và `HelpTopic`.
- Mỗi `HelpTopic` bao gồm:
  - `id`: định danh duy nhất, viết dạng `topic_ten_chu_de`.
  - `categoryId`: trỏ về `HelpCategory.id`.
  - `title`, `summary`, `steps`: nội dung hiển thị chính.
  - Metadata bổ trợ: `difficulty`, `estimatedTime`, `prerequisites`, `resources`, `tips`, `audience`, `relatedTopicIds`, `isFeatured`.

### 2.2 Giao diện người dùng
- `lib/views/help_center_view.dart` hiển thị tìm kiếm, danh mục, chủ đề nổi bật, thẻ hành động nhanh và chi tiết từng bước.
- Shortcut truy cập nhanh nằm trong `lib/views/settings_view.dart` (mục Trung tâm hướng dẫn).

## 3. Quy trình bổ sung/chỉnh sửa nội dung
1. **Xác định danh mục:**
   - Nếu chủ đề mới thuộc danh mục hiện có, dùng `categoryId` tương ứng.
   - Nếu cần danh mục mới, thêm `HelpCategory` vào danh sách `categories` với mô tả và biểu tượng.
2. **Tạo/Chỉnh sửa HelpTopic:**
   - Thêm phần tử mới vào danh sách `topics` với đầy đủ trường bắt buộc.
   - `audience`: khai báo vai trò áp dụng (`all`, `owner`, `manager`, `technician`, `cashier`, `admin`).
   - `steps`: liệt kê từng bước chi tiết (ưu tiên câu lệnh ngắn, gạch đầu dòng rõ ràng).
   - `tips`: ghi chú bổ sung, có thể rỗng nếu không cần.
   - `prerequisites`: chuẩn bị trước khi thực hiện.
   - `resources`: tên tài liệu, file, link cần tham chiếu (hiện hiển thị dạng thông báo, chưa mở link trực tiếp).
   - `relatedTopicIds`: danh sách `id` các chủ đề liên quan để gợi ý trong phần chi tiết.
   - `isFeatured`: đặt `true` nếu muốn xuất hiện trong mục "Nổi bật".
3. **Rà soát ngôn ngữ:**
   - Nội dung hiển thị cho người dùng phải **tiếng Việt**.
   - Comment trong code giữ tiếng Anh ngắn gọn khi cần.
4. **Kiểm thử:**
   - Chạy `flutter run` hoặc `flutter test` (nếu bổ sung test) để chắc chắn không lỗi cú pháp.
   - Kiểm tra giao diện Help Center xem chủ đề hiển thị đúng danh mục, đủ metadata, liên kết liên quan hoạt động.

## 4. Best Practices
- Luôn cập nhật `summary` súc tích (2-3 câu) để người dùng hiểu nhanh.
- Giữ `steps` ở dạng mệnh lệnh, mỗi bước < 120 ký tự.
- Dùng `difficulty` theo 3 mức khuyến nghị: `Dễ`, `Trung bình`, `Nâng cao`.
- `estimatedTime` trình bày dạng "~5 phút", "~10-15 phút", ...
- `tips` nên bao gồm cảnh báo lỗi phổ biến hoặc mẹo tăng tốc.
- Khi gắn `relatedTopicIds`, đảm bảo chủ đề đó đã tồn tại.
- Đặt `isFeatured` tối đa 4 chủ đề để tránh carousel quá dài.

## 5. Lộ trình phát triển tiếp theo
- Kết nối `resources` với URL hoặc viewer tài liệu.
- Đồng bộ nội dung với Firestore để cập nhật trực tuyến (khi cần).
- Bổ sung hình ảnh/video minh họa trực tiếp trong bước thực hiện.

Giữ file này đồng bộ với thay đổi cấu trúc dữ liệu để đội vận hành dễ dàng bảo trì Trung tâm hướng dẫn.
