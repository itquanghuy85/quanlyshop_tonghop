/**
 * Seed E2E realistic repair data for full-flow testing.
 *
 * Covers:
 * - Repair list thumbnail loading with mixed image paths (local + cloud URL)
 * - Outsourced partner service accounting (paid now vs debt)
 * - Partner history + partner payment records for finance screens
 * - Cross-check that service cost and payment totals are coherent
 *
 * Usage:
 *   node scripts/seed_repair_e2e_real_data.js <email> <password> [shopId]
 *
 * Example:
 *   node scripts/seed_repair_e2e_real_data.js admin@huluca.com YourPassword123
 */

const API_KEY = 'AIzaSyA5wW6zMHiWB_5xme99MVl0eSj7bhpO-S0';
const PROJECT_ID = 'huyaka-1809';

const AUTH_URL = `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`;
const FIRESTORE_BASE = `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

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

function fromFirestoreValue(v) {
  if (!v) return null;
  if (Object.prototype.hasOwnProperty.call(v, 'stringValue')) return v.stringValue;
  if (Object.prototype.hasOwnProperty.call(v, 'integerValue')) return Number(v.integerValue || 0);
  if (Object.prototype.hasOwnProperty.call(v, 'doubleValue')) return Number(v.doubleValue || 0);
  if (Object.prototype.hasOwnProperty.call(v, 'booleanValue')) return Boolean(v.booleanValue);
  if (Object.prototype.hasOwnProperty.call(v, 'timestampValue')) return v.timestampValue;
  if (Object.prototype.hasOwnProperty.call(v, 'nullValue')) return null;
  if (v.arrayValue?.values) return v.arrayValue.values.map(fromFirestoreValue);
  if (v.mapValue?.fields) {
    const out = {};
    for (const [k, val] of Object.entries(v.mapValue.fields)) {
      out[k] = fromFirestoreValue(val);
    }
    return out;
  }
  return null;
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
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(`Auth failed: ${JSON.stringify(err.error || err)}`);
  }
  const data = await res.json();
  return {
    idToken: data.idToken,
    uid: data.localId,
    email: data.email,
  };
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
  const doc = await res.json();
  const data = {};
  for (const [k, v] of Object.entries(doc.fields || {})) {
    data[k] = fromFirestoreValue(v);
  }
  return data;
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

async function tryWriteDoc(token, collection, docId, data, { required = true } = {}) {
  try {
    await writeDoc(token, collection, docId, data);
    return { ok: true, collection, docId };
  } catch (e) {
    const message = (e && e.message) ? e.message : String(e);
    if (required) {
      throw e;
    }
    console.warn(`WARN optional write skipped: ${collection}/${docId} -> ${message}`);
    return { ok: false, collection, docId, error: message };
  }
}

async function resolveShopId(token, uid, explicitShopId) {
  if (explicitShopId && explicitShopId.trim()) return explicitShopId.trim();

  const userDoc = await getDoc(token, 'users', uid);
  if (!userDoc) {
    throw new Error('Cannot resolve shopId: users/{uid} doc not found, please pass shopId manually.');
  }

  const shopId = (userDoc.shopId || '').toString().trim();
  if (!shopId) {
    throw new Error('Cannot resolve shopId: users/{uid}.shopId is empty, please pass shopId manually.');
  }

  return shopId;
}

function makeRepairDoc({
  id,
  shopId,
  customerName,
  phone,
  model,
  issue,
  imagePath,
  status,
  price,
  cost,
  paymentMethod,
  createdAt,
  deliveredAt,
  notes,
  services,
  costRecordedInFund,
  costPaymentMethod,
  costRecordedAt,
}) {
  return {
    firestoreId: id,
    customerName,
    phone,
    model,
    issue,
    accessories: 'Cáp sạc',
    address: 'TP.HCM',
    imagePath,
    deliveredImage: '',
    warranty: '3 tháng',
    partsUsed: services.map((s) => s.serviceName).join(', '),
    status,
    price,
    cost,
    paymentMethod,
    createdAt,
    startedAt: createdAt + 30 * 60 * 1000,
    finishedAt: status >= 3 ? createdAt + 3 * 60 * 60 * 1000 : 0,
    deliveredAt,
    createdBy: shopId,
    repairedBy: shopId,
    deliveredBy: status === 4 ? shopId : '',
    lastCaredAt: createdAt + 4 * 60 * 60 * 1000,
    isSynced: true,
    deleted: false,
    isWalkIn: false,
    color: 'ĐEN',
    imei: '',
    condition: 'Máy cấn nhẹ viền',
    services: JSON.stringify(services),
    notes,
    pendingDeliveryApproval: false,
    costRecordedInFund,
    costPaymentMethod,
    costRecordedAt,
    shopId,
    updatedAt: { _serverTimestamp: true },
  };
}

async function main() {
  const email = process.argv[2];
  const password = process.argv[3];
  const explicitShopId = process.argv[4];

  if (!email || !password) {
    console.log('Usage: node scripts/seed_repair_e2e_real_data.js <email> <password> [shopId]');
    process.exit(1);
  }

  console.log('=== SEED E2E REPAIR REAL DATA ===');
  console.log(`Login: ${email}`);

  const auth = await signIn(email, password);
  const shopId = await resolveShopId(auth.idToken, auth.uid, explicitShopId);

  console.log(`Authenticated uid=${auth.uid}`);
  console.log(`Using shopId=${shopId}`);

  const now = Date.now();
  const seedId = String(now);
  const dayStart = new Date();
  dayStart.setHours(0, 0, 0, 0);
  const base = dayStart.getTime();

  const partnerNumericId = 900100 + (now % 1000);
  const partnerDocId = `partner_e2e_${seedId}`;

  const partnerDoc = {
    firestoreId: partnerDocId,
    id: partnerNumericId,
    name: `Đối tác test E2E ${seedId.slice(-4)}`,
    phone: '0909998888',
    note: 'Dữ liệu test thực chiến cho luồng đối tác sửa chữa',
    active: 1,
    createdAt: now,
    updatedAt: now,
    shopId,
    deleted: 0,
    isSynced: 1,
  };

  await writeDoc(auth.idToken, 'repair_partners', partnerDocId, partnerDoc);
  console.log(`Created partner: repair_partners/${partnerDocId}`);

  const servicePaidNow = {
    id: 1,
    firestoreId: `svc_paid_${seedId}`,
    serviceName: 'ÉP KÍNH + CĂN CHỈNH VIỀN',
    partnerId: partnerNumericId,
    partnerName: partnerDoc.name,
    cost: 380000,
    paymentMethod: 'TIỀN MẶT',
    isSynced: 1,
    deleted: 0,
  };

  const serviceDebt = {
    id: 2,
    firestoreId: `svc_debt_${seedId}`,
    serviceName: 'THAY CỤM FACE ID',
    partnerId: partnerNumericId,
    partnerName: partnerDoc.name,
    cost: 1200000,
    paymentMethod: 'CÔNG NỢ',
    isSynced: 1,
    deleted: 0,
  };

  const serviceInternal = {
    id: 3,
    firestoreId: `svc_internal_${seedId}`,
    serviceName: 'VỆ SINH MÁY + THAY KEO',
    partnerId: null,
    partnerName: null,
    cost: 120000,
    paymentMethod: null,
    isSynced: 1,
    deleted: 0,
  };

  const repairs = [
    {
      id: `rep_e2e_paid_${seedId}`,
      data: makeRepairDoc({
        id: `rep_e2e_paid_${seedId}`,
        shopId,
        customerName: 'KH TEST THANH TOÁN ĐỐI TÁC',
        phone: '0901112201',
        model: 'IPHONE 13 PRO MAX',
        issue: 'NỨT KÍNH NGOÀI',
        imagePath: `C:\\offline\\camera_${seedId}.jpg,https://picsum.photos/seed/repair_paid_${seedId}/800/600`,
        status: 4,
        price: 1200000,
        cost: servicePaidNow.cost,
        paymentMethod: 'TIỀN MẶT',
        createdAt: base + 8 * 60 * 60 * 1000,
        deliveredAt: base + 11 * 60 * 60 * 1000,
        notes: 'Case test: dịch vụ đối tác đã thanh toán ngay, ảnh local + cloud',
        services: [servicePaidNow],
        costRecordedInFund: false,
        costPaymentMethod: null,
        costRecordedAt: 0,
      }),
      expectedPartnerCost: servicePaidNow.cost,
      expectedPartnerPaid: servicePaidNow.cost,
    },
    {
      id: `rep_e2e_debt_${seedId}`,
      data: makeRepairDoc({
        id: `rep_e2e_debt_${seedId}`,
        shopId,
        customerName: 'KH TEST CÔNG NỢ ĐỐI TÁC',
        phone: '0901112202',
        model: 'IPHONE 14 PRO',
        issue: 'MẤT FACE ID',
        imagePath: `https://picsum.photos/seed/repair_debt_${seedId}/800/600`,
        status: 3,
        price: 2200000,
        cost: serviceDebt.cost,
        paymentMethod: 'CHUYỂN KHOẢN',
        createdAt: base + 9 * 60 * 60 * 1000,
        deliveredAt: 0,
        notes: 'Case test: dịch vụ đối tác công nợ chưa trả',
        services: [serviceDebt],
        costRecordedInFund: false,
        costPaymentMethod: null,
        costRecordedAt: 0,
      }),
      expectedPartnerCost: serviceDebt.cost,
      expectedPartnerPaid: 0,
    },
    {
      id: `rep_e2e_mix_${seedId}`,
      data: makeRepairDoc({
        id: `rep_e2e_mix_${seedId}`,
        shopId,
        customerName: 'KH TEST ẢNH LIST MIX',
        phone: '0901112203',
        model: 'SAMSUNG S23 ULTRA',
        issue: 'LOA NHỎ',
        imagePath: `D:\\temp\\capture_${seedId}.jpg,https://picsum.photos/seed/repair_mix_${seedId}/800/600,https://picsum.photos/seed/repair_mix2_${seedId}/800/600`,
        status: 2,
        price: 650000,
        cost: serviceInternal.cost,
        paymentMethod: 'TIỀN MẶT',
        createdAt: base + 10 * 60 * 60 * 1000,
        deliveredAt: 0,
        notes: 'Case test: list ưu tiên ảnh cloud khi path đầu là local',
        services: [serviceInternal],
        costRecordedInFund: true,
        costPaymentMethod: 'TIỀN MẶT',
        costRecordedAt: base + 10 * 60 * 60 * 1000,
      }),
      expectedPartnerCost: 0,
      expectedPartnerPaid: 0,
    },
  ];

  for (const repair of repairs) {
    await writeDoc(auth.idToken, 'repairs', repair.id, repair.data);
    console.log(`Created repair: repairs/${repair.id}`);
  }

  const partnerHistoryDocs = [
    {
      id: `prh_paid_${seedId}`,
      data: {
        firestoreId: `prh_paid_${seedId}`,
        repairOrderId: `rep_e2e_paid_${seedId}`,
        repairId: `rep_e2e_paid_${seedId}`,
        partnerId: partnerNumericId,
        partnerFirestoreId: partnerDocId,
        customerName: 'KH TEST THANH TOÁN ĐỐI TÁC',
        deviceModel: 'IPHONE 13 PRO MAX',
        issue: 'NỨT KÍNH NGOÀI',
        partnerCost: servicePaidNow.cost,
        repairContent: servicePaidNow.serviceName,
        sentAt: base + 8 * 60 * 60 * 1000,
        shopId,
        deleted: 0,
        isSynced: 1,
        updatedAt: { _serverTimestamp: true },
      },
    },
    {
      id: `prh_debt_${seedId}`,
      data: {
        firestoreId: `prh_debt_${seedId}`,
        repairOrderId: `rep_e2e_debt_${seedId}`,
        repairId: `rep_e2e_debt_${seedId}`,
        partnerId: partnerNumericId,
        partnerFirestoreId: partnerDocId,
        customerName: 'KH TEST CÔNG NỢ ĐỐI TÁC',
        deviceModel: 'IPHONE 14 PRO',
        issue: 'MẤT FACE ID',
        partnerCost: serviceDebt.cost,
        repairContent: serviceDebt.serviceName,
        sentAt: base + 9 * 60 * 60 * 1000,
        shopId,
        deleted: 0,
        isSynced: 1,
        updatedAt: { _serverTimestamp: true },
      },
    },
  ];

  const optionalWriteResults = [];

  for (const entry of partnerHistoryDocs) {
    const result = await tryWriteDoc(
      auth.idToken,
      'partner_repair_history',
      entry.id,
      entry.data,
      { required: false },
    );
    optionalWriteResults.push(result);
    if (result.ok) {
      console.log(`Created partner history: partner_repair_history/${entry.id}`);
    }
  }

  const partnerPaymentDocId = `rpp_paid_${seedId}`;
  const partnerPaymentData = {
    firestoreId: partnerPaymentDocId,
    partnerId: partnerNumericId,
    partnerName: partnerDoc.name,
    amount: servicePaidNow.cost,
    paymentMethod: 'TIỀN MẶT',
    paidAt: base + 11 * 60 * 60 * 1000,
    note: `Thanh toán test cho ${servicePaidNow.serviceName}`,
    shopId,
    deleted: 0,
    isSynced: 1,
    updatedAt: { _serverTimestamp: true },
  };
  const partnerPaymentWrite = await tryWriteDoc(
    auth.idToken,
    'repair_partner_payments',
    partnerPaymentDocId,
    partnerPaymentData,
    { required: false },
  );
  optionalWriteResults.push(partnerPaymentWrite);
  if (partnerPaymentWrite.ok) {
    console.log(`Created partner payment: repair_partner_payments/${partnerPaymentDocId}`);
  }

  const debtDocId = `debt_partner_seed_${seedId}`;
  const debtData = {
    firestoreId: debtDocId,
    type: 'SHOP_OWES',
    debtType: 'SHOP_OWES',
    personName: partnerDoc.name,
    phone: partnerDoc.phone,
    totalAmount: serviceDebt.cost,
    paidAmount: 0,
    note: `Công nợ test cho ${serviceDebt.serviceName}`,
    status: 'ACTIVE',
    createdAt: base + 9 * 60 * 60 * 1000,
    shopId,
    linkedId: `rep_e2e_debt_${seedId}`,
    relatedPartId: String(partnerNumericId),
    deleted: 0,
    isSynced: 1,
    updatedAt: { _serverTimestamp: true },
  };
  const debtWrite = await tryWriteDoc(auth.idToken, 'debts', debtDocId, debtData, {
    required: false,
  });
  optionalWriteResults.push(debtWrite);
  if (debtWrite.ok) {
    console.log(`Created debt: debts/${debtDocId}`);
  }

  // Run manifest for cleanup and traceability.
  const runDocId = `seed_repair_e2e_${seedId}`;
  const runDoc = {
    firestoreId: runDocId,
    seedType: 'repair_e2e_real',
    shopId,
    seededByEmail: auth.email,
    seededAt: now,
    partnerId: partnerNumericId,
    partnerDocId,
    repairIds: repairs.map((r) => r.id),
    partnerHistoryIds: partnerHistoryDocs.map((d) => d.id),
    partnerPaymentIds: [partnerPaymentDocId],
    debtIds: [debtDocId],
    deleted: 0,
    updatedAt: { _serverTimestamp: true },
  };
  const seedRunWrite = await tryWriteDoc(auth.idToken, 'seed_runs', runDocId, runDoc, {
    required: false,
  });
  optionalWriteResults.push(seedRunWrite);
  if (seedRunWrite.ok) {
    console.log(`Created seed run manifest: seed_runs/${runDocId}`);
  }

  // Basic post-seed verification for this run.
  const paidRepair = await getDoc(auth.idToken, 'repairs', `rep_e2e_paid_${seedId}`);
  const debtRepair = await getDoc(auth.idToken, 'repairs', `rep_e2e_debt_${seedId}`);
  const partnerPayment = partnerPaymentWrite.ok
    ? await getDoc(auth.idToken, 'repair_partner_payments', partnerPaymentDocId)
    : null;

  const checks = [];
  checks.push({
    name: 'repair_paid.services parse',
    ok: paidRepair && typeof paidRepair.services === 'string' && paidRepair.services.includes('ÉP KÍNH'),
  });
  checks.push({
    name: 'repair_debt exists',
    ok: !!debtRepair,
  });
  checks.push({
    name: 'partner payment single amount (if permission allows)',
    ok: !partnerPaymentWrite.ok ||
      (partnerPayment && Number(partnerPayment.amount || 0) === servicePaidNow.cost),
  });

  const failed = checks.filter((c) => !c.ok);

  console.log('\n=== VERIFY RESULT ===');
  for (const c of checks) {
    console.log(`${c.ok ? 'PASS' : 'FAIL'} - ${c.name}`);
  }

  if (failed.length > 0) {
    throw new Error(`Verification failed: ${failed.map((f) => f.name).join(', ')}`);
  }

  const skippedOptional = optionalWriteResults.filter((r) => !r.ok);
  if (skippedOptional.length > 0) {
    console.log('\nOptional collections skipped by Firestore rules:');
    for (const item of skippedOptional) {
      console.log(`- ${item.collection}/${item.docId}`);
    }
  }

  console.log('\nSeed completed successfully.');
  console.log(`Run ID: ${runDocId}`);
  console.log('You can now test:');
  console.log('- Repair list image thumbnail loading (mixed image paths)');
  console.log('- Partner paid-now flow vs partner debt flow');
  console.log('- Home finance: partner payment should be one expense record only');
}

main().catch((e) => {
  console.error('\nSEED FAILED');
  console.error(e.message || e);
  process.exit(1);
});
