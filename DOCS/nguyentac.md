📘 BỘ NGUYÊN TẮC CHI TIẾT CHO AI TRƯỚC KHI SỬA ỨNG DỤNG
I. NGUYÊN TẮC NHẬN THỨC & TRÁCH NHIỆM
1️⃣ AI KHÔNG ĐƯỢC GIẢ ĐỊNH

Không được giả định:

App đã deploy

Feature đã hoạt động

Data đã sạch

Mọi kết luận phải dựa trên code nhìn thấy

Nếu thiếu thông tin → bắt buộc nói “chưa đủ dữ liệu để kết luận”

2️⃣ AI PHẢI XÁC ĐỊNH ĐÚNG VAI TRÒ

Trước khi làm, AI phải tự xác định:

Đang là Developer hay Reviewer hay QA

Không được vừa sửa vừa đánh giá trong cùng 1 bước nếu không được cho phép

II. NGUYÊN TẮC PHẠM VI & KIỂM SOÁT THAY ĐỔI
3️⃣ KHÔNG LÀM NGOÀI PHẠM VI

Chỉ sửa đúng phần được yêu cầu

Không tiện tay “tối ưu thêm”

Không đụng sang module khác

Nếu cần sửa ngoài phạm vi → phải xin phép trước

4️⃣ KHÔNG REFACTOR LỚN

Không đổi kiến trúc

Không đổi pattern state management

Không đổi cách tổ chức thư mục

Không rename hàng loạt file

5️⃣ KHÔNG THÊM DEPENDENCY

Chỉ dùng thư viện đã có trong project

Nếu bắt buộc cần thêm → phải nêu rõ:

Vì sao không thể làm bằng cách cũ

Rủi ro khi thêm

III. NGUYÊN TẮC VỀ CODE & BUILD
6️⃣ SỬA TỚI ĐÂU → BUILD TỚI ĐÓ

Mỗi lần sửa:

App phải build được

Không warning nghiêm trọng

Nếu build fail → coi như chưa hoàn thành

7️⃣ CODE PHẢI CỤ THỂ – KHÔNG NÓI MỒM

“Đã implement” → phải có code

“Đã xử lý” → phải chỉ ra file + method

Không chấp nhận mô tả suông

8️⃣ NULL-SAFETY & EDGE CASE LÀ BẮT BUỘC

Mọi dữ liệu từ:

Firestore

Network

Local storage
→ đều có thể null / lỗi

Phải xử lý trước khi render UI

IV. NGUYÊN TẮC AN TOÀN DỮ LIỆU & NGHIỆP VỤ
9️⃣ BACKWARD COMPATIBLE TUYỆT ĐỐI

Không làm hỏng data cũ

Không bắt migrate DB nếu chưa được phép

Field mới phải optional / có default

🔟 KHÔNG ĐƯỢC LÀM SAI TIỀN – KHO – CÔNG

Tài chính

Tồn kho

Chấm công

👉 Nếu không chắc → không được sửa

V. NGUYÊN TẮC ERROR HANDLING
1️⃣1️⃣ ERROR KHÔNG ĐƯỢC GIẾT APP

Lỗi FCM / network / permission:

App vẫn chạy

Không crash

Không throw exception ra UI

1️⃣2️⃣ FAIL GRACEFULLY

Lỗi → log

Lỗi → fallback

Không im lặng, không sập

VI. NGUYÊN TẮC KIỂM CHỨNG & KẾT LUẬN
1️⃣3️⃣ KHÔNG TIN “ĐÃ XONG” – PHẢI KIỂM

Sau mỗi phase, AI bắt buộc trả lời:

Đã xong cái gì

Chưa xong cái gì

Rủi ro còn lại

1️⃣4️⃣ KẾT LUẬN RÕ RÀNG

Mỗi lần trả lời phải có:

✅ ĐẠT / ❌ CHƯA ĐẠT

Có được deploy hay không

Có được làm phase tiếp theo hay không

VII. NGUYÊN TẮC LÀM VIỆC THEO PHASE
1️⃣5️⃣ KHÔNG NHẢY PHASE

Phase trước chưa đạt → cấm phase sau

Không làm song song

1️⃣6️⃣ MỖI LẦN CHỈ 1 MỤC TIÊU

Không sửa nhiều thứ trong 1 request

Mỗi request = 1 mục tiêu rõ ràng