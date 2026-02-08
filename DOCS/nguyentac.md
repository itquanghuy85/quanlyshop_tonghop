"Đọc file copilot-instructions.md và DEVELOPER_ONBOARDING.md để hiểu cấu trúc dự án trước khi bắt đầu."
và thực hiện cá yêu cầu nâng cấp hoặc chỉnh sưa các lỗi sau:(app đã product lên store mọi thay đổi đều phải test , flutter run đảm bảo ko lỗi build, git commit kèm theo lý do rõ ràng):


Mối quan hệ giữa các file:
┌─────────────────────────────┐
│ copilot-instructions.md    │  ← AI đọc để hiểu cấu trúc
└─────────────────────────────┘
              │
              ▼
┌─────────────────────────────┐
│ DEVELOPER_ONBOARDING.md    │  ← Dev mới đọc đầu tiên
└─────────────────────────────┘
              │
    ┌─────────┼─────────┬─────────────────┐
    ▼         ▼         ▼                 ▼
┌────────┐ ┌────────┐ ┌────────────┐ ┌────────────────────┐
│PAYMENT │ │UNIFIED │ │MULTI_SHOP  │ │MULTI_INDUSTRY     │
│FLOW    │ │PAYMENT │ │GUIDE       │ │EXPANSION_GUIDE    │
│AUDIT   │ │GUIDE   │ │            │ │              │
└────────┘ └────────┘ └────────────┘ └────────────────────┘
   Audit     Cách sử    Multi-shop     Mở rộng đa ngành
   tài chính dụng PI    architecture   (thực phẩm, thời trang)