# FINANCE V2 IMPLEMENTATION CHECKLIST

Cập nhật: 29/04/2026
Mục tiêu: thay thế hoàn toàn Finance V1 bằng Finance V2 theo lộ trình có kiểm soát, có tiêu chí hoàn thành, có điều kiện rollback an toàn.
Nguyên tắc vận hành: chỉ promote khi đã pass đủ checklist phase hiện tại.

## Trạng thái hiện tại

- [x] Finance V2 đã có entry từ Home
- [x] Finance V2 đã có màn Báo cáo ngày riêng
- [x] Có tracker thay thế: FINANCE_V2_REPLACEMENT_TRACKER.md
- [x] Rollout stage hiện tại đã chuyển sang `v2Only`
- [x] Hoàn thiện đủ drill-down cốt lõi để thay thế V1 ở lớp điều phối
- [ ] Loại bỏ hoàn toàn phụ thuộc view phân tích sâu của V1

## Phase 0 - Khóa nền tảng thay thế

Mục tiêu: dựng cơ chế rollout chính thức để thay V1 theo stage, tránh cắt đột ngột.

- [x] Thêm enum stage rollout trong Finance V2 feature flag
- [x] Đặt stage mặc định: `v2Primary`
- [x] Ưu tiên card mở Finance V2 ở tab Tài chính Home
- [x] Gate card V1 theo stage rollout
- [ ] Bổ sung log theo dõi lượt mở V2 vs V1 để quyết định promote

Điều kiện qua phase:
- [x] Không có lỗi compile/analyze ở các file tài chính chính
- [x] `flutter run` chạy ổn định trên Android test device

## Phase 1 - Hoàn thiện tab Giao dịch

Mục tiêu: tab Giao dịch đủ mạnh để thay lịch sử V1.

- [x] Tìm kiếm theo tiêu đề/nội dung
- [x] Lọc thu vào/chi ra
- [x] Lọc theo phương thức thanh toán đầy đủ
- [x] Tap item mở chứng từ gốc theo ref type (sale/repair/expense/debt)
- [ ] Chuẩn hóa hiển thị số tiền compact + full tooltip
- [ ] Giới hạn và phân trang danh sách lớn

Điều kiện qua phase:
- [ ] Test dữ liệu 5.000+ giao dịch vẫn mượt
- [ ] 100% mẫu giao dịch chính mở được chứng từ gốc

## Phase 2 - Hoàn thiện tab Tổng quan

Mục tiêu: Tổng quan có drill-down đầy đủ thay dashboard V1.

- [x] Drill-down từ Cơ cấu nguồn thu (Bán hàng/Sửa chữa/Thu khác)
- [x] Drill-down từ Dòng tiền trong kỳ (Tiền vào/Tiền ra)
- [x] Drill-down từ Nhóm chi phí chính theo category
- [x] Drill-down từ card công nợ nhanh (Phải thu/Phải trả)
- [x] Drill-down từ so sánh kỳ trước theo từng chỉ số

Điều kiện qua phase:
- [ ] Mọi card chính đều bấm được và dẫn về màn đích đúng bộ lọc
- [ ] Không có dead-end navigation

## Phase 3 - Hoàn thiện tab Báo cáo

Mục tiêu: thay phần lớn vai trò báo cáo V1.

- [x] Bucket theo ngày/tháng/năm
- [x] Drill-down từ bucket về danh sách giao dịch đúng kỳ
- [x] Breakdown sâu theo nguồn thu/chi trong từng bucket
- [x] Top sản phẩm bán chạy
- [x] Top khách hàng mua nhiều
- [x] Snapshot lãi/lỗ có đối chiếu kỳ trước trực tiếp trong tab

Điều kiện qua phase:
- [ ] Bao phủ đủ nhu cầu phân tích mà `revenue_view.dart` đang gánh
- [ ] User test chủ shop pass ít nhất 2 vòng vận hành thực tế

## Phase 4 - Hoàn thiện tab Công nợ

Mục tiêu: thay dashboard công nợ V1 với khả năng truy vết nhanh.

- [x] Drill-down bucket tuổi nợ 0-30 / 30-60 / >60
- [x] Tìm kiếm nhanh theo tên/sđt
- [x] Lọc theo loại đối tượng nợ (khách/NCC/đối tác)
- [x] Đồng bộ điều hướng sang DebtView khi cần xử lý nghiệp vụ sâu

Điều kiện qua phase:
- [ ] Không lệch số với DebtView trong cùng kỳ lọc
- [ ] Mọi bucket tuổi nợ truy được danh sách nền

## Phase 5 - Hoàn thiện tab Nhật ký

Mục tiêu: thay được nhật ký tài chính điều hành V1.

- [x] Bổ sung preset lọc bất thường/rủi ro/giá trị lớn
- [x] Chuẩn hóa mapping nguồn và kiểu hoạt động
- [x] Hoàn thiện mở chứng từ gốc cho các entry còn thiếu
- [x] Export theo đúng filter hiện tại

Điều kiện qua phase:
- [ ] Nhật ký đủ dùng cho chủ shop truy vết sự cố tài chính

## Phase 6 - Chuyển đổi chính thức V2 Only

Mục tiêu: hoàn tất thay thế V1 ở lớp điều phối tài chính.

- [x] Chuyển stage sang `v2Only`
- [x] Ẩn toàn bộ entry point V1 trùng chức năng khỏi Home
- [x] Giữ lại view nghiệp vụ sâu chưa thay thế 1-1 (DebtView/ExpenseView/CashClosingView)
- [x] Chốt migration note trong FINANCE_V2_REPLACEMENT_TRACKER.md

Điều kiện qua phase:
- [x] Không còn luồng người dùng chính đi qua dashboard/report V1
- [ ] V2 pass regression checklist + run thực tế ổn định

## Regression checklist bắt buộc mỗi phase

- [x] flutter analyze các file tài chính chính
- [x] flutter run trên thiết bị Android chính
- [ ] Kiểm tra số liệu V2 vs V1 trong cùng kỳ lọc
- [ ] Kiểm tra điều hướng Home -> V2 -> view sâu
- [ ] Kiểm tra export/in nếu phase chạm vào báo cáo

## Cập nhật kiểm tra gần nhất (29/04/2026)

- [x] `lib/finance_v2/finance_v2_view.dart` đã sạch analyzer (`No issues found`)
- [x] Đã chạy `flutter run` và app lên ổn định trên Android test device
- [x] Đã chuẩn hóa text tiếng Việt có dấu cho UI Finance V2
- [x] Đã vá lỗi tràn ngang tab tài chính bằng `isScrollable: true`
- [x] Đã chuyển rollout stage sang `v2Only` trong feature flag
- [x] Đã chuyển các entry “Báo cáo” ở Home sang mở Finance V2 khi V2 là primary
- [x] Đã bổ sung drill-down khối So sánh kỳ trước và Nhóm chi phí chính ở tab Tổng quan
- [x] Đã bổ sung tìm kiếm/lọc đối tượng nợ và drill-down tuổi nợ ở tab Công nợ
- [x] Đã bổ sung breakdown theo bucket + top sản phẩm + top khách hàng ở tab Báo cáo
- [x] Đã bổ sung preset lọc rủi ro/giá trị lớn ở tab Nhật ký
- [x] Đã bổ sung snapshot lãi/lỗ có đối chiếu kỳ trước trực tiếp trong tab Báo cáo
- [x] Đã đồng bộ điều hướng tab Công nợ sang DebtView khi cần xử lý nghiệp vụ sâu
- [ ] Chưa hoàn tất QA thao tác tay đủ 5 tab theo checklist nghiệp vụ
- [ ] Chưa hoàn tất đối soát số liệu V2 vs V1 cùng kỳ lọc
- [ ] Chưa hoàn tất test export/in theo filter ở luồng vận hành thật

## Quy tắc rollback

- [ ] Mỗi phase phải có commit mốc rõ ràng
- [ ] Không gộp nhiều phase trong một commit
- [ ] Nếu fail acceptance: rollback về commit phase trước ngay

## Cam kết thực thi

- Tôi sẽ bám checklist này làm nguồn sự thật triển khai.
- Mỗi lần thay đổi sẽ cập nhật trạng thái checklist ngay trong file này.
- Mục tiêu là hoàn thiện thay thế V1 theo từng phase, không đánh đổi độ ổn định.
