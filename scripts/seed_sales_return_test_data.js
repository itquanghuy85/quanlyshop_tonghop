/**
 * Seed realistic Sales Return test data for end-to-end testing.
 *
 * Creates:
 * 1. A sample sale order (phone + accessories) 
 * 2. A sales return for that order (partial return: just the accessory)
 * 3. A financial activity log entry for the refund
 *
 * Usage:
 *   node scripts/seed_sales_return_test_data.js <email> <password> [shopId]
 *
 * Example:
 *   node scripts/seed_sales_return_test_data.js admin@huluca.com YourPassword honC8KnKhOUG19wcYOFDTGVdKWP2
 *
 * Requires: Node.js 18+
 */

const crypto = require('crypto');

const API_KEY = process.env.FIREBASE_API_KEY || (() => { console.error('Set FIREBASE_API_KEY env var'); process.exit(1); })();
const PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'huyaka-1809';

const AUTH_URL = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;
const FIRESTORE_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

// ─── Encryption (matches EncryptionService in Dart) ────────────────────
const MASTER_SECRET = 'HuLuCa_Shop_2024_Secure_Key_@!#';

function createEncrypter(shopId) {
  const keySource = `${shopId}${MASTER_SECRET}`;
  const keyBytes = crypto.createHash('sha256').update(keySource, 'utf8').digest();
  const ivSource = `IV_${shopId}`;
  const ivBytes = crypto.createHash('md5').update(ivSource, 'utf8').digest();
  return { key: keyBytes, iv: ivBytes };
}

function encryptValue(plainText, encrypter) {
  if (!plainText || typeof plainText !== 'string' || plainText.length === 0) return plainText;
  const cipher = crypto.createCipheriv('aes-256-cbc', encrypter.key, encrypter.iv);
  let encrypted = cipher.update(plainText, 'utf8', 'base64');
  encrypted += cipher.final('base64');
  return `ENC:${encrypted}`;
}

const SENSITIVE_FIELDS = [
  'customerName', 'phone', 'address', 'email', 'notes', 'note',
  'issue', 'password', 'screenPassword', 'imei', 'productImeis',
  'sellerName', 'receiverName', 'personName', 'staffName', 'name',
  'bankName', 'settlementCode', 'settlementNote', 'description',
  'accessories', 'warranty',
];

function encryptMap(data, encrypter) {
  const encrypted = { ...data };
  for (const field of SENSITIVE_FIELDS) {
    if (encrypted[field] && typeof encrypted[field] === 'string' && encrypted[field].length > 0) {
      encrypted[field] = encryptValue(encrypted[field], encrypter);
    }
  }
  encrypted['_encrypted'] = true;
  return encrypted;
}

// ─── Firestore helpers ──────────────────────────────────────────────────
function toFirestoreValue(val) {
  if (val === null || val === undefined) return { nullValue: null };
  if (typeof val === 'boolean') return { booleanValue: val };
  if (typeof val === 'number') return { integerValue: String(Math.trunc(val)) };
  if (typeof val === 'string') return { stringValue: val };
  if (Array.isArray(val)) return { arrayValue: { values: val.map(toFirestoreValue) } };
  if (typeof val === 'object' && val._serverTimestamp) {
    return { timestampValue: new Date().toISOString() };
  }
  if (typeof val === 'object') {
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

// ─── Auth & Firestore I/O ───────────────────────────────────────────────
async function signIn(email, password) {
  const res = await fetch(AUTH_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(`Auth failed: ${JSON.stringify(err.error || err)}`);
  }
  const data = await res.json();
  return { idToken: data.idToken, uid: data.localId, email: data.email };
}

async function writeDoc(token, collection, docId, data) {
  const fieldPaths = Object.keys(data)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&');
  const url = `${FIRESTORE_BASE}/${collection}/${docId}${fieldPaths ? `?${fieldPaths}` : ''}`;
  const doc = toFirestoreDoc(data);

  const res = await fetch(url, {
    method: 'PATCH',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify(doc),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Firestore write failed for ${collection}/${docId}: ${err}`);
  }
  return await res.json();
}

async function getDoc(token, collection, docId) {
  const url = `${FIRESTORE_BASE}/${collection}/${docId}`;
  const res = await fetch(url, {
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });
  if (res.status === 404) return null;
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Firestore get failed for ${collection}/${docId}: ${err}`);
  }
  return await res.json();
}

async function resolveShopId(token, uid, explicitShopId) {
  if (explicitShopId && explicitShopId.trim()) return explicitShopId.trim();
  const url = `${FIRESTORE_BASE}/users/${uid}`;
  const res = await fetch(url, {
    method: 'GET',
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error('Cannot resolve shopId from users doc');
  const doc = await res.json();
  const shopId = doc.fields?.shopId?.stringValue;
  if (!shopId) throw new Error('No shopId found in user doc. Pass it as 3rd arg.');
  return shopId;
}

// ─── Main ───────────────────────────────────────────────────────────────
async function main() {
  const [email, password, explicitShopId] = process.argv.slice(2);
  if (!email || !password) {
    console.error('Usage: node scripts/seed_sales_return_test_data.js <email> <password> [shopId]');
    process.exit(1);
  }

  console.log('🔑 Signing in…');
  const auth = await signIn(email, password);
  console.log(`   ✔ Authenticated as ${auth.email} (uid: ${auth.uid})`);

  const shopId = await resolveShopId(auth.idToken, auth.uid, explicitShopId);
  console.log(`   ✔ Shop ID: ${shopId}`);

  const enc = createEncrypter(shopId);

  const now = Date.now();
  const twoDaysAgo = now - 2 * 24 * 60 * 60 * 1000;

  // ── 1. Sale Order ─────────────────────────────────────────────────────
  const saleTimestamp = twoDaysAgo;
  const saleDocId = `sale_${saleTimestamp}`;

  const saleData = {
    customerName: 'NGUYỄN THỊ TEST TRẢ HÀNG',
    phone: '0987654321',
    isWalkIn: false,
    walkInName: '',
    walkInPhone: '',
    address: 'HÀ NỘI',
    productNames: 'IPHONE 15 PRO MAX 256GB,ỐP LƯNG IPHONE 15 PRO MAX,SẠC NHANH 20W APPLE',
    productImeis: '359876543210001,NO_IMEI,NO_IMEI',
    totalPrice: 34000000,
    totalCost: 28500000,
    discount: 500000,
    paymentMethod: 'TIỀN MẶT',
    sellerName: 'ADMIN',
    soldAt: saleTimestamp,
    notes: 'Đơn test cho tính năng trả hàng',
    gifts: '',
    warranty: '12 THÁNG',
    isInstallment: false,
    downPayment: 0,
    downPaymentMethod: '',
    loanAmount: 0,
    installmentTerm: 0,
    bankName: '',
    bankName2: '',
    loanAmount2: 0,
    cashAmount: 0,
    transferAmount: 0,
    settlementPlannedAt: 0,
    settlementReceivedAt: 0,
    settlementAmount: 0,
    settlementFee: 0,
    settlementNote: '',
    settlementCode: '',
    shopId: shopId,
    deleted: false,
    updatedAt: { _serverTimestamp: true },
  };

  console.log('\n📦 Creating sale order…');
  const encryptedSale = encryptMap(saleData, enc);
  await writeDoc(auth.idToken, 'sales', saleDocId, encryptedSale);
  console.log(`   ✔ Sale: ${saleDocId}`);
  console.log(`     Customer: NGUYỄN THỊ TEST TRẢ HÀNG`);
  console.log(`     Products: iPhone 15 Pro Max + Ốp lưng + Sạc nhanh`);
  console.log(`     Total: 34,000,000₫ (discount 500,000₫ → final 33,500,000₫)`);

  // ── 2. Sales Return (partial: return ốp lưng + sạc) ──────────────────
  const returnTimestamp = now;
  const returnDocId = `sr_${returnTimestamp}`;

  const returnData = {
    salesOrderId: 0,  // local DB id (will be assigned on sync)
    salesOrderFirestoreId: saleDocId,
    customerName: 'NGUYỄN THỊ TEST TRẢ HÀNG',
    customerPhone: '0987654321',
    returnDate: returnTimestamp,
    totalReturnAmount: 1500000, // ốp lưng 500k + sạc 1M
    totalReturnCost: 900000,    // ốp lưng 250k + sạc 650k
    refundMethod: 'TIỀN MẶT',
    note: 'Khách đổi ý, không cần phụ kiện',
    createdAt: returnTimestamp,
    createdBy: 'ADMIN',
    approvedBy: 'ADMIN',
    approvedAt: returnTimestamp,
    status: 'APPROVED',
    shopId: shopId,
    deleted: false,
    updatedAt: { _serverTimestamp: true },
  };

  console.log('\n🔄 Creating sales return…');
  const encryptedReturn = encryptMap(returnData, enc);
  await writeDoc(auth.idToken, 'sales_returns', returnDocId, encryptedReturn);
  console.log(`   ✔ Return: ${returnDocId}`);
  console.log(`     Refund: 1,500,000₫ (TIỀN MẶT)`);
  console.log(`     Reason: Khách đổi ý, không cần phụ kiện`);

  // ── 3. Return Items (2 items) ─────────────────────────────────────────
  const items = [
    {
      salesReturnId: 0,
      salesReturnFirestoreId: returnDocId,
      productId: 0,
      productFirestoreId: '',
      productName: 'ỐP LƯNG IPHONE 15 PRO MAX',
      productImei: 'NO_IMEI',
      quantity: 1,
      price: 500000,
      cost: 250000,
      amount: 500000,
      shopId: shopId,
      deleted: false,
      updatedAt: { _serverTimestamp: true },
    },
    {
      salesReturnId: 0,
      salesReturnFirestoreId: returnDocId,
      productId: 0,
      productFirestoreId: '',
      productName: 'SẠC NHANH 20W APPLE',
      productImei: 'NO_IMEI',
      quantity: 1,
      price: 1000000,
      cost: 650000,
      amount: 1000000,
      shopId: shopId,
      deleted: false,
      updatedAt: { _serverTimestamp: true },
    },
  ];

  console.log('\n📋 Creating return items…');
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const itemDocId = `${returnDocId}_item_${i + 1}`;
    item.firestoreId = itemDocId;
    const encryptedItem = encryptMap(item, enc);
    await writeDoc(auth.idToken, 'sales_return_items', itemDocId, encryptedItem);
    console.log(`   ✔ Item ${i + 1}: ${item.productName} — ${item.price.toLocaleString('vi-VN')}₫`);
  }

  // ── 4. Financial Activity Log (refund entry) ─────────────────────────
  const faDocId = `fa_refund_${returnTimestamp}`;
  const faData = {
    activityType: 'REFUND',
    amount: 1500000,
    direction: 'OUT',
    paymentMethod: 'TIỀN MẶT',
    referenceType: 'sales_return',
    referenceId: returnDocId,
    title: 'Hoàn tiền trả hàng',
    description: 'Trả hàng phụ kiện: ỐP LƯNG IPHONE 15 PRO MAX x1, SẠC NHANH 20W APPLE x1',
    customerName: 'NGUYỄN THỊ TEST TRẢ HÀNG',
    phone: '0987654321',
    productInfo: 'ỐP LƯNG IPHONE 15 PRO MAX x1, SẠC NHANH 20W APPLE x1',
    createdAt: returnTimestamp,
    createdBy: 'ADMIN',
    shopId: shopId,
    deleted: false,
    updatedAt: { _serverTimestamp: true },
  };

  console.log('\n💰 Creating financial activity log (refund)…');
  const encryptedFa = encryptMap(faData, enc);
  await writeDoc(auth.idToken, 'financial_activity_log', faDocId, encryptedFa);
  console.log(`   ✔ FA Log: ${faDocId}`);
  console.log(`     Type: REFUND | Direction: OUT | Amount: 1,500,000₫`);

  // ── 5. SECOND scenario: Sale with installment + debt return ──────────
  const sale2Timestamp = twoDaysAgo + 3600000; // 1 hour later
  const sale2DocId = `sale_${sale2Timestamp}`;

  const sale2Data = {
    customerName: 'TRẦN VĂN TEST CÔNG NỢ',
    phone: '0912345678',
    isWalkIn: false,
    walkInName: '',
    walkInPhone: '',
    address: 'TP.HCM',
    productNames: 'SAMSUNG GALAXY S24 ULTRA,TAI NGHE GALAXY BUDS 3 PRO',
    productImeis: '356789012345678,NO_IMEI',
    totalPrice: 35000000,
    totalCost: 29000000,
    discount: 0,
    paymentMethod: 'KẾT HỢP',
    sellerName: 'ADMIN',
    soldAt: sale2Timestamp,
    notes: 'Đơn test trả hàng công nợ',
    gifts: 'Tặng dán cường lực',
    warranty: '12 THÁNG',
    isInstallment: false,
    downPayment: 0,
    downPaymentMethod: '',
    loanAmount: 0,
    installmentTerm: 0,
    bankName: '',
    bankName2: '',
    loanAmount2: 0,
    cashAmount: 30000000,
    transferAmount: 5000000,
    settlementPlannedAt: 0,
    settlementReceivedAt: 0,
    settlementAmount: 0,
    settlementFee: 0,
    settlementNote: '',
    settlementCode: '',
    shopId: shopId,
    deleted: false,
    updatedAt: { _serverTimestamp: true },
  };

  console.log('\n📦 Creating 2nd sale order (combined payment)…');
  const encryptedSale2 = encryptMap(sale2Data, enc);
  await writeDoc(auth.idToken, 'sales', sale2DocId, encryptedSale2);
  console.log(`   ✔ Sale: ${sale2DocId}`);
  console.log(`     Customer: TRẦN VĂN TEST CÔNG NỢ`);
  console.log(`     Products: Samsung S24 Ultra + Tai nghe Buds 3 Pro`);
  console.log(`     Total: 35,000,000₫ (cash 30M + transfer 5M)`);

  // Return: tai nghe → refund as CÔNG NỢ (reduce debt)
  const return2Timestamp = now + 1000;
  const return2DocId = `sr_${return2Timestamp}`;

  const return2Data = {
    salesOrderId: 0,
    salesOrderFirestoreId: sale2DocId,
    customerName: 'TRẦN VĂN TEST CÔNG NỢ',
    customerPhone: '0912345678',
    returnDate: return2Timestamp,
    totalReturnAmount: 5500000,
    totalReturnCost: 3800000,
    refundMethod: 'CÔNG NỢ',
    note: 'Tai nghe lỗi, giảm công nợ thay vì hoàn tiền mặt',
    createdAt: return2Timestamp,
    createdBy: 'ADMIN',
    approvedBy: 'ADMIN',
    approvedAt: return2Timestamp,
    status: 'APPROVED',
    shopId: shopId,
    deleted: false,
    updatedAt: { _serverTimestamp: true },
  };

  console.log('\n🔄 Creating 2nd sales return (CÔNG NỢ)…');
  const encryptedReturn2 = encryptMap(return2Data, enc);
  await writeDoc(auth.idToken, 'sales_returns', return2DocId, encryptedReturn2);
  console.log(`   ✔ Return: ${return2DocId}`);
  console.log(`     Refund: 5,500,000₫ (CÔNG NỢ — reduce debt)`);

  const item2 = {
    salesReturnId: 0,
    salesReturnFirestoreId: return2DocId,
    productId: 0,
    productFirestoreId: '',
    productName: 'TAI NGHE GALAXY BUDS 3 PRO',
    productImei: 'NO_IMEI',
    quantity: 1,
    price: 5500000,
    cost: 3800000,
    amount: 5500000,
    shopId: shopId,
    deleted: false,
    updatedAt: { _serverTimestamp: true },
  };

  const item2DocId = `${return2DocId}_item_1`;
  item2.firestoreId = item2DocId;

  console.log('\n📋 Creating return item for 2nd return…');
  const encryptedItem2 = encryptMap(item2, enc);
  await writeDoc(auth.idToken, 'sales_return_items', item2DocId, encryptedItem2);
  console.log(`   ✔ Item: ${item2.productName} — 5,500,000₫`);

  // Financial activity for debt return
  const fa2DocId = `fa_refund_${return2Timestamp}`;
  const fa2Data = {
    activityType: 'REFUND',
    amount: 5500000,
    direction: 'DEBT',
    paymentMethod: 'CÔNG NỢ',
    referenceType: 'sales_return',
    referenceId: return2DocId,
    title: 'Giảm công nợ - Trả hàng',
    description: 'Trả hàng: TAI NGHE GALAXY BUDS 3 PRO x1 — giảm công nợ thay hoàn tiền',
    customerName: 'TRẦN VĂN TEST CÔNG NỢ',
    phone: '0912345678',
    productInfo: 'TAI NGHE GALAXY BUDS 3 PRO x1',
    createdAt: return2Timestamp,
    createdBy: 'ADMIN',
    shopId: shopId,
    deleted: false,
    updatedAt: { _serverTimestamp: true },
  };

  console.log('\n💰 Creating financial activity log (debt reduction)…');
  const encryptedFa2 = encryptMap(fa2Data, enc);
  await writeDoc(auth.idToken, 'financial_activity_log', fa2DocId, encryptedFa2);
  console.log(`   ✔ FA Log: ${fa2DocId}`);
  console.log(`     Type: REFUND | Direction: DEBT | Amount: 5,500,000₫`);

  // ── Summary ───────────────────────────────────────────────────────────
  console.log('\n' + '═'.repeat(60));
  console.log('✅ TEST DATA SEEDED SUCCESSFULLY');
  console.log('═'.repeat(60));
  console.log('\nScenario 1: Cash refund (partial return)');
  console.log(`  Sale:   ${saleDocId}`);
  console.log(`  Return: ${returnDocId} (ốp lưng + sạc → 1,500,000₫ TIỀN MẶT)`);
  console.log(`  FA Log: ${faDocId}`);
  console.log('\nScenario 2: Debt reduction return');
  console.log(`  Sale:   ${sale2DocId}`);
  console.log(`  Return: ${return2DocId} (tai nghe → 5,500,000₫ CÔNG NỢ)`);
  console.log(`  FA Log: ${fa2DocId}`);
  console.log('\n📱 Open the app → Sales tab → Trả hàng to see returns.');
  console.log('💰 Open Finance tab → Nhật ký tài chính to see refund entries.');
}

main().catch((e) => {
  console.error('❌ Error:', e.message || e);
  process.exit(1);
});
