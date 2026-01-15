# ✅ CHECKLIST TEST TRẢ GÓP - 10 PHÚT

## 📌 MỤC TIÊU
Kiểm tra dòng tiền trả góp: 1 NH, 2 NH, tất toán, phí NH.

---

## 🚀 CHUẨN BỊ

1. **Shop trống hoặc biết rõ số dư hiện tại**
2. **Chốt quỹ hôm qua** (nếu chưa): TM=10tr, NH=5tr

---

## 🧪 TEST CASES

### Test 1: Trả góp 1 NH - Trả trước TIỀN MẶT
**Nhập hàng:**
- Tên: `TEST TRA GOP 1`
- IMEI: `111111111111111`
- Giá nhập: `7,000,000` (TIỀN MẶT)

**Bán hàng:**
- Khách: `KHACH TG1` / `0911111111`
- Giá bán: `10,000,000`
- ✅ Tick "TRẢ GÓP"
- Trả trước: `3,000,000`
- Phương thức trả trước: `TIỀN MẶT`
- Ngân hàng: `FE CREDIT`
- Số tiền vay: `7,000,000`

**✓ Kiểm tra CHỐT QUỸ (ngày bán):**
| Chỉ số | Kỳ vọng | Thực tế | ✓/✗ |
|--------|---------|---------|-----|
| TM thu vào | +3,000,000 | | |
| NH thu vào | 0 | | |
| Doanh thu | 3,000,000 | | |
| Giá vốn | 2,100,000 (30%) | | |
| Lợi nhuận | 900,000 | | |

---

### Test 2: Trả góp 1 NH - Trả trước CHUYỂN KHOẢN
**Nhập hàng:**
- Tên: `TEST TRA GOP 2`
- IMEI: `222222222222222`
- Giá nhập: `14,000,000` (TIỀN MẶT)

**Bán hàng:**
- Khách: `KHACH TG2` / `0922222222`
- Giá bán: `20,000,000`
- ✅ Tick "TRẢ GÓP"
- Trả trước: `5,000,000`
- Phương thức trả trước: `CHUYỂN KHOẢN`
- Ngân hàng: `HOME CREDIT`
- Số tiền vay: `15,000,000`

**✓ Kiểm tra CHỐT QUỸ:**
| Chỉ số | Kỳ vọng | Thực tế | ✓/✗ |
|--------|---------|---------|-----|
| TM thu vào | 0 | | |
| NH thu vào | +5,000,000 | | |
| Doanh thu | 5,000,000 | | |
| Giá vốn | 3,500,000 (25%) | | |
| Lợi nhuận | 1,500,000 | | |

---

### Test 3: Trả góp 2 NGÂN HÀNG
**Nhập hàng:**
- Tên: `TEST TRA GOP 3`
- IMEI: `333333333333333`
- Giá nhập: `20,000,000` (TIỀN MẶT)

**Bán hàng:**
- Khách: `KHACH TG3` / `0933333333`
- Giá bán: `30,000,000`
- ✅ Tick "TRẢ GÓP"
- Trả trước: `10,000,000` (TIỀN MẶT)
- ✅ Tick "THÊM NGÂN HÀNG 2"
- NH1: `FE CREDIT` - `15,000,000`
- NH2: `HD SAISON` - `5,000,000`

**✓ Kiểm tra CHỐT QUỸ:**
| Chỉ số | Kỳ vọng | Thực tế | ✓/✗ |
|--------|---------|---------|-----|
| TM thu vào | +10,000,000 | | |
| NH thu vào | 0 | | |
| Doanh thu | 10,000,000 | | |
| Giá vốn | 6,666,667 (33.33%) | | |
| Lợi nhuận | 3,333,333 | | |

---

### Test 4: NGÂN HÀNG TẤT TOÁN
**Thao tác:** Vào chi tiết đơn Test 1 → Cập nhật tất toán:
- Ngày nhận tiền: `HÔM NAY`
- Số tiền thực nhận: `7,000,000`
- Mã hồ sơ: `FE123456`

**✓ Kiểm tra CHỐT QUỸ (ngày tất toán):**
| Chỉ số | Kỳ vọng | Thực tế | ✓/✗ |
|--------|---------|---------|-----|
| TM thu vào | 0 | | |
| NH thu vào | +7,000,000 | | |
| Settlement | 7,000,000 | | |
| Giá vốn thêm | 4,900,000 (70%) | | |
| Lợi nhuận | 2,100,000 | | |

**Tổng lợi nhuận đơn này:**
- Ngày bán: 900,000
- Ngày tất toán: 2,100,000
- **Tổng: 3,000,000** (= 10tr - 7tr giá vốn) ✓

---

### Test 5: Tất toán TRỪ PHÍ
**Thao tác:** Vào chi tiết đơn Test 2 → Cập nhật tất toán:
- Ngày nhận tiền: `HÔM NAY`
- Số tiền thực nhận: `14,500,000` (NH giữ 500k phí)
- Phí NH: `500,000`

**✓ Kiểm tra CHỐT QUỸ:**
| Chỉ số | Kỳ vọng | Thực tế | ✓/✗ |
|--------|---------|---------|-----|
| NH thu vào | +14,500,000 | | |
| Settlement | 14,500,000 | | |

**Tổng lợi nhuận đơn này:**
- Ngày bán: 1,500,000
- Ngày tất toán: 14,500,000 - 10,500,000 = 4,000,000
- **Tổng: 5,500,000** (= 20tr - 14tr - 0.5tr phí) ✓

---

## 📊 BẢNG TỔNG HỢP (Cuối ngày test)

| Đơn | Giá bán | Giá vốn | Down | Vay | Settlement | LN tổng |
|-----|---------|---------|------|-----|------------|---------|
| TG1 | 10tr | 7tr | 3tr TM | 7tr | 7tr | 3tr |
| TG2 | 20tr | 14tr | 5tr CK | 15tr | 14.5tr | 5.5tr |
| TG3 | 30tr | 20tr | 10tr TM | 20tr | (chưa) | (chưa) |

---

## 🔑 QUY TẮC QUAN TRỌNG

### Ngày BÁN (có trả góp):
```
TM/NH thu = Down payment
Doanh thu = Down payment  
Giá vốn = Giá vốn × (Down / Giá bán)
```

### Ngày TẤT TOÁN:
```
NH thu = Settlement amount
Doanh thu thêm = Settlement amount
Giá vốn thêm = Giá vốn × (1 - Down / Giá bán)
```

### 2 Ngân hàng:
```
Tổng vay = NH1 + NH2
Settlement = Tổng tiền nhận từ cả 2 NH
```

---

## ✅ PASS NẾU:
1. Down payment vào đúng TM/NH theo phương thức
2. Settlement vào NH (luôn chuyển khoản từ NH)
3. Giá vốn tính theo TỶ LỆ đã thu
4. Lợi nhuận tổng = Giá bán - Giá vốn - Phí NH

---

**Unit test đã PASSED: 7/7 ✅**
**File test:** `test/installment_cash_flow_test.dart`
