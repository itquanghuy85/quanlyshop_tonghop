Kịch Bản Test Duy Nhất (Bao Phủ Full Logic)
Ngày test: 1 ngày duy nhất, làm theo đúng thứ tự dưới đây.

Nhập kho không công nợ NCC
Hàng:
Điện thoại A (IMEI A001): giá vốn 10,000,000
Ốp A: giá vốn 80,000                                70,0000
Sạc A: giá vốn 70,000
Tổng nhập: 10,150,000
Thanh toán: tiền mặt 100%
Nhập kho có công nợ NCC
Hàng:
Tai nghe B: 5 cái, giá vốn 600,000/cái, tổng 3,000,000
Thanh toán: chuyển khoản 1,000,000
Công nợ NCC phát sinh: 2,000,000
Bán hàng tiền mặt (đơn bundle để test trả hàng partial)
Đơn S001:
Điện thoại A: 12,000,000
Ốp A: 150,000
Sạc A: 120,000
Tổng: 12,270,000
Thanh toán: tiền mặt
Bán hàng chuyển khoản
Đơn S002:
Tai nghe B: 2 cái x 900,000 = 1,800,000
Thanh toán: chuyển khoản
Bán hàng công nợ
Đơn S003:
Tai nghe B: 1 cái x 900,000 = 900,000
Thanh toán: công nợ (chưa thu tiền)
Thu nợ khách
Thu từ S003: 500,000
Phương thức: tiền mặt
Trả nợ NCC
Trả nợ từ khoản nợ NCC ở bước 2: 700,000
Phương thức: chuyển khoản
Ghi nhận chi phí
Chi phí vận hành: 200,000
Phương thức: tiền mặt
Trả hàng partial đơn S001 (lần 1)
Trả: chỉ Điện thoại A
Hoàn tiền: tiền mặt
Số hoàn đúng: 12,000,000
Trả hàng lần 2 cùng đơn S001
Trả: Ốp A + Sạc A
Hoàn tiền: tiền mặt
Số hoàn đúng: 270,000
Mục tiêu bắt lỗi: không được bị “đội giá” ốp/sạc lên vài triệu
Sửa đơn (nếu app cho phép)
Chỉ sửa ghi chú S002 (không đổi số tiền)
Mục tiêu: không phát sinh thêm giao dịch tài chính/kho
Số Liệu Kỳ Vọng Chuẩn (Để So Với App)

Doanh thu gộp bán hàng: 14,970,000

Hoàn trả bán hàng: 12,270,000

Doanh thu thuần: 2,700,000

Giá vốn gộp: 11,950,000

Giá vốn hoàn nhập do trả hàng: 10,150,000

Giá vốn thuần: 1,800,000

Lợi nhuận gộp thuần: 900,000

Tiền mặt vào:

Bán S001: 12,270,000
Thu nợ: 500,000
Tổng cash in: 12,770,000
Tiền mặt ra:
Nhập kho bước 1: 10,150,000
Chi phí: 200,000
Hoàn trả hàng lần 1 + lần 2: 12,270,000
Tổng cash out: 22,620,000
Dòng tiền mặt ròng: -9,850,000

Tiền ngân hàng vào:

Bán S002: 1,800,000
Tiền ngân hàng ra:
Nhập kho bước 2: 1,000,000
Trả nợ NCC: 700,000
Tổng bank out: 1,700,000
Dòng tiền ngân hàng ròng: +100,000

Công nợ cuối kỳ:

Phải thu khách: 400,000
Phải trả NCC: 1,300,000
Tồn kho cuối kỳ (theo giá vốn):
Điện thoại A: 1 cái = 10,000,000
Ốp A: 1 cái = 80,000
Sạc A: 1 cái = 70,000
Tai nghe B: 2 cái = 1,200,000
Tổng tồn kho vốn: 11,350,000
Khi Bạn Gửi 2 File Excel, Mình Sẽ Trả Kết Quả Đúng Format Bạn Yêu Cầu

Bảng tái dựng timeline toàn bộ giao dịch.
Bảng so sánh chi tiết: tính lại vs app (doanh thu, vốn, lãi, cash flow, nợ, tồn).
Danh sách sai lệch theo mức độ:
Critical
Medium
Minor
Mỗi lỗi có đủ:
Số liệu chứng minh
Giao dịch liên quan
Nguyên nhân gốc (logic/sync/ghi nhận)
Đề xuất fix cụ thể (flow, rule validation, unique, lock)