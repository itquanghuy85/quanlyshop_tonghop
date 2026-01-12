AUTOMATION TEST – SALES + REPAIRS + DEBT + INSTALLMENT + SYNC
🎯 Mục tiêu

Chạy toàn bộ nghiệp vụ:

Bán

Sửa

Trả góp

Công nợ

NCC

Ngân hàng

Chốt quỹ
và so sánh 2 thiết bị phải cho ra cùng số tiền.

🧩 STEP 0 – RESET SHOP
Delete all:
sales, repairs, expenses, debts, debt_payments,
supplier_imports, supplier_payments, cash_closings

Set opening:
cash = 0
bank = 0
inventory = 0

🧩 STEP 1 – Seed inventory
Create product A:
 price=10,000,000
 cost=7,000,000
 qty=5

Create product B:
 price=5,000,000
 cost=3,000,000
 qty=5

🧩 STEP 2 – Sales
Sale 1:
 customer=KH01
 product=A
 payment=TIỀN_MẶT
 amount=10,000,000

Sale 2:
 customer=KH02
 product=B
 payment=CHUYỂN_KHOẢN
 amount=5,000,000

Sale 3:
 customer=KH01
 product=B
 payment=CÔNG_NỢ
 amount=5,000,000

Sale 4 (installment):
 customer=KH02
 product=A
 total=10,000,000
 downPayment=3,000,000
 payment=TIỀN_MẶT
 loan=7,000,000


Expected:

cash = 13,000,000
bank = 5,000,000
debt(KH01)=5,000,000

🧩 STEP 3 – Repairs
Repair:
 customer=KH01
 labor=2,000,000
 partCost=1,000,000
 payment=CHUYỂN_KHOẢN


Expected:

bank = 7,000,000

🧩 STEP 4 – Debt payments
KH01 pays:
 3,000,000 TIỀN_MẶT
 2,000,000 CHUYỂN_KHOẢN


Expected:

cash = 16,000,000
bank = 9,000,000
debt(KH01)=0

🧩 STEP 5 – Bank settlement
Bank pays installment:
 7,000,000


Expected:

bank = 16,000,000

🧩 STEP 6 – Supplier import
Import:
 3 x product A
 total cost = 21,000,000
 pay cash = 10,000,000
 debt supplier = 11,000,000


Expected:

cash = 6,000,000
supplierDebt = 11,000,000

🧩 STEP 7 – Pay supplier
Pay supplier:
 11,000,000 via BANK


Expected:

bank = 5,000,000
supplierDebt = 0

🧩 STEP 8 – Cash closing

Expected final:

cash = 6,000,000
bank = 5,000,000
total fund = 11,000,000
inventory A = 3
inventory B = 3

🧩 STEP 9 – Multi-device sync test
Device A: do all steps
Device B: only login, do nothing

After every step:
 assert deviceA.cash == deviceB.cash
 assert deviceA.bank == deviceB.bank
 assert deviceA.debt == deviceB.debt
 assert deviceA.inventory == deviceB.inventory


If ANY mismatch → SYNC BUG FOUND.