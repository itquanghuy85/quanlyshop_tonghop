/**
 * Seed test repair data to verify parts cost (giá vốn linh kiện) feature
 * 
 * Creates 4 repair orders with different cost scenarios:
 * 1. Cost recorded in fund (TIỀN MẶT), delivered (status 4)
 * 2. Cost recorded in fund (CHUYỂN KHOẢN), delivered (status 4) 
 * 3. Cost NOT recorded in fund, delivered (status 4)
 * 4. Cost recorded in fund (TIỀN MẶT), NOT delivered (status 3)
 * 
 * Usage: node scripts/seed_repair_cost_test_data.js <email> <password>
 * Example: node scripts/seed_repair_cost_test_data.js admin@huluca.com MyPass123
 */

const API_KEY = process.env.FIREBASE_API_KEY || (() => { console.error('Set FIREBASE_API_KEY env var'); process.exit(1); })();
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'huyaka-1809';
const SHOP_ID = process.argv[4] || process.env.SHOP_ID || (() => { console.error('Provide shopId as 3rd arg or set SHOP_ID env var'); process.exit(1); })();

const AUTH_URL = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;
const FIRESTORE_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

// ===== HELPERS =====

function toFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === "boolean") return { booleanValue: val };
  if (typeof val === "number") return { integerValue: String(val) };
  if (typeof val === "string") return { stringValue: val };
  if (Array.isArray(val)) return { arrayValue: { values: val.map(toFirestoreValue) } };
  if (typeof val === "object" && val._serverTimestamp) return { timestampValue: new Date().toISOString() };
  if (typeof val === "object") {
    const fields = {};
    for (const [k, v] of Object.entries(val)) {
      fields[k] = toFirestoreValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(val) };
}

function toFirestoreDoc(data) {
  const fields = {};
  for (const [k, v] of Object.entries(data)) {
    fields[k] = toFirestoreValue(v);
  }
  return { fields };
}

async function signIn(email, password) {
  const res = await fetch(AUTH_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  if (!res.ok) {
    const err = await res.json();
    throw new Error(`Auth failed: ${JSON.stringify(err.error)}`);
  }
  const data = await res.json();
  return data.idToken;
}

async function writeDoc(token, collection, docId, data) {
  const fieldPaths = Object.keys(data).map(k => `updateMask.fieldPaths=${k}`).join("&");
  const url = `${FIRESTORE_BASE}/${collection}/${docId}?${fieldPaths}`;
  const doc = toFirestoreDoc(data);
  
  const res = await fetch(url, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(doc),
  });
  
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Firestore write failed for ${docId}: ${err}`);
  }
  return await res.json();
}

// ===== MAIN =====

async function main() {
  const email = process.argv[2];
  const password = process.argv[3];

  if (!email || !password) {
    console.log("Usage: node scripts/seed_repair_cost_test_data.js <email> <password>");
    console.log("Example: node scripts/seed_repair_cost_test_data.js admin@huluca.com MyPass123");
    process.exit(1);
  }

  console.log("=== SEED REPAIR COST TEST DATA ===\n");

  // 1. Sign in
  console.log(`Signing in as ${email}...`);
  const token = await signIn(email, password);
  console.log("Authenticated!\n");

  // 2. Build test data
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0).getTime();
  const ts = Date.now();

  const repairs = [
    {
      docId: `rep_test_cost_cash_${ts}`,
      data: {
        firestoreId: `rep_test_cost_cash_${ts}`,
        customerName: "TEST Von LK Tien mat",
        phone: "0901111001",
        model: "iPhone 14 Pro Max",
        issue: "Thay man hinh + kinh cuong luc",
        accessories: "Sac, op lung",
        address: "",
        warranty: "Bao hanh 3 thang",
        partsUsed: "Man hinh OLED iPhone 14 PM",
        status: 4,
        price: 3500000,
        cost: 1800000,
        paymentMethod: "TIỀN MẶT",
        createdAt: todayStart + 28800000,
        startedAt: todayStart + 32400000,
        finishedAt: todayStart + 43200000,
        deliveredAt: todayStart + 46800000,
        createdBy: SHOP_ID,
        repairedBy: SHOP_ID,
        deliveredBy: SHOP_ID,
        isSynced: true,
        deleted: false,
        isWalkIn: false,
        color: "Den",
        imei: "",
        condition: "Man nut goc phai",
        services: "[]",
        notes: "TEST: Gia von ghi so quy bang TIEN MAT",
        pendingDeliveryApproval: false,
        costRecordedInFund: true,
        costPaymentMethod: "TIỀN MẶT",
        costRecordedAt: todayStart + 46800000,
        shopId: SHOP_ID,
        updatedAt: { _serverTimestamp: true },
      },
      label: "Case 1: Cost->Fund TIEN MAT, Delivered",
    },
    {
      docId: `rep_test_cost_bank_${ts}`,
      data: {
        firestoreId: `rep_test_cost_bank_${ts}`,
        customerName: "TEST Von LK Chuyen khoan",
        phone: "0901111002",
        model: "Samsung S24 Ultra",
        issue: "Thay pin + ve sinh may",
        accessories: "Khong co",
        address: "",
        warranty: "Bao hanh 6 thang",
        partsUsed: "Pin Samsung S24 Ultra chinh hang",
        status: 4,
        price: 1500000,
        cost: 750000,
        paymentMethod: "CHUYỂN KHOẢN",
        createdAt: todayStart + 30600000,
        startedAt: todayStart + 34200000,
        finishedAt: todayStart + 39600000,
        deliveredAt: todayStart + 41400000,
        createdBy: SHOP_ID,
        repairedBy: SHOP_ID,
        deliveredBy: SHOP_ID,
        isSynced: true,
        deleted: false,
        isWalkIn: false,
        color: "Titanium",
        imei: "",
        condition: "Pin chai 60%",
        services: "[]",
        notes: "TEST: Gia von ghi so quy bang CHUYEN KHOAN",
        pendingDeliveryApproval: false,
        costRecordedInFund: true,
        costPaymentMethod: "CHUYỂN KHOẢN",
        costRecordedAt: todayStart + 41400000,
        shopId: SHOP_ID,
        updatedAt: { _serverTimestamp: true },
      },
      label: "Case 2: Cost->Fund CHUYEN KHOAN, Delivered",
    },
    {
      docId: `rep_test_cost_nofund_${ts}`,
      data: {
        firestoreId: `rep_test_cost_nofund_${ts}`,
        customerName: "TEST Von LK Khong ghi quy",
        phone: "0901111003",
        model: "OPPO Reno 10",
        issue: "Thay loa ngoai",
        accessories: "Khong co",
        address: "",
        warranty: "Bao hanh 1 thang",
        partsUsed: "Loa ngoai OPPO Reno 10",
        status: 4,
        price: 800000,
        cost: 200000,
        paymentMethod: "TIỀN MẶT",
        createdAt: todayStart + 36000000,
        startedAt: todayStart + 37800000,
        finishedAt: todayStart + 39600000,
        deliveredAt: todayStart + 43200000,
        createdBy: SHOP_ID,
        repairedBy: SHOP_ID,
        deliveredBy: SHOP_ID,
        isSynced: true,
        deleted: false,
        isWalkIn: false,
        color: "Xanh",
        imei: "",
        condition: "Loa bi re",
        services: "[]",
        notes: "TEST: Gia von KHONG ghi so quy",
        pendingDeliveryApproval: false,
        costRecordedInFund: false,
        costPaymentMethod: "",
        costRecordedAt: 0,
        shopId: SHOP_ID,
        updatedAt: { _serverTimestamp: true },
      },
      label: "Case 3: Cost NOT in fund, Delivered",
    },
    {
      docId: `rep_test_cost_notdelivered_${ts}`,
      data: {
        firestoreId: `rep_test_cost_notdelivered_${ts}`,
        customerName: "TEST Von LK Chua giao",
        phone: "0901111004",
        model: "Xiaomi 14",
        issue: "Thay mat kinh",
        accessories: "Op silicon",
        address: "",
        warranty: "Bao hanh 2 thang",
        partsUsed: "Kinh cuong luc Xiaomi 14",
        status: 3,
        price: 500000,
        cost: 150000,
        paymentMethod: "TIỀN MẶT",
        createdAt: todayStart + 32400000,
        startedAt: todayStart + 34200000,
        finishedAt: todayStart + 36000000,
        deliveredAt: 0,
        createdBy: SHOP_ID,
        repairedBy: SHOP_ID,
        deliveredBy: "",
        isSynced: true,
        deleted: false,
        isWalkIn: false,
        color: "Trang",
        imei: "",
        condition: "Kinh nut vo",
        services: "[]",
        notes: "TEST: Chua giao, gia von da ghi so quy",
        pendingDeliveryApproval: false,
        costRecordedInFund: true,
        costPaymentMethod: "TIỀN MẶT",
        costRecordedAt: todayStart + 36000000,
        shopId: SHOP_ID,
        updatedAt: { _serverTimestamp: true },
      },
      label: "Case 4: Cost->Fund TIEN MAT, NOT delivered (status 3)",
    },
  ];

  // 3. Write to Firestore
  for (const repair of repairs) {
    console.log(`${repair.label}`);
    console.log(`   Doc: ${repair.docId}`);
    console.log(`   Price: ${repair.data.price.toLocaleString()} | Cost: ${repair.data.cost.toLocaleString()}`);
    try {
      await writeDoc(token, "repairs", repair.docId, repair.data);
      console.log("   Written!\n");
    } catch (err) {
      console.error(`   Error: ${err.message}\n`);
    }
  }

  // 4. Print expected summary
  printExpectedSummary();
}

function printExpectedSummary() {
  console.log("\n" + "=".repeat(60));
  console.log("EXPECTED FINANCIAL SUMMARY (test data only)");
  console.log("=".repeat(60));
  
  console.log("\nTHU (income - only status=4 delivered):");
  console.log("   Case 1: 3,500,000 (TIEN MAT)     - iPhone 14 PM");
  console.log("   Case 2: 1,500,000 (CHUYEN KHOAN)  - Samsung S24 Ultra");
  console.log("   Case 3:   800,000 (TIEN MAT)     - OPPO Reno 10");
  console.log("   TOTAL: 5,800,000");
  console.log("   Cash: 4,300,000 | Bank: 1,500,000");
  
  console.log("\nCHI - Von LK SC (cost recorded in fund - ANY status):");
  console.log("   Case 1: 1,800,000 (TIEN MAT)     - iPhone screen");
  console.log("   Case 2:   750,000 (CHUYEN KHOAN)  - Samsung battery");
  console.log("   Case 4:   150,000 (TIEN MAT)     - Xiaomi glass (not delivered!)");
  console.log("   Case 3:   200,000 <- NOT in fund (should NOT appear)");
  console.log("   TOTAL in fund: 2,700,000");
  console.log("   Cash: 1,950,000 | Bank: 750,000");
  
  console.log("\nLOI NHUAN (profit from delivered):");
  console.log("   5,800,000 - 2,750,000 (all delivered costs) = 3,050,000");
  
  console.log("\nSO QUY impact (fund balance from test data):");
  console.log("   Cash: +4,300,000 - 1,950,000 = +2,350,000");
  console.log("   Bank: +1,500,000 - 750,000   = +750,000");
  console.log("   Total net: +3,100,000");
  
  console.log("\nVERIFICATION CHECKLIST:");
  console.log("   [ ] Tong quan tab: THU +5,800,000 / CHI includes 2,700,000 Von LK SC");
  console.log("   [ ] Chi tab: Shows 3 entries for Von LK SC (1.8M + 750K + 150K)");
  console.log("   [ ] Giao dich tab: Thu=5,800,000 / Chi includes 2,700,000");
  console.log("   [ ] Case 3 (200K): Should NOT appear in Von LK SC entries");
  console.log("   [ ] Case 4 (150K): SHOULD appear even though status=3");
  console.log("   [ ] Home dashboard: CHI includes Von LK SC entries");
}

main().catch((err) => {
  console.error("Fatal error:", err.message);
  process.exit(1);
});
