const crypto = require('crypto');
const MS = 'HuLuCa_Shop_2024_Secure_Key_@!#';
const sid = 'ISTjckXdiqOE2TGDC3HCzNpyEGg1';
const API_KEY = 'AIzaSyBjeyh1irlquOPS_9NE1LhnQGkGoqNmwZo';

function dec(enc) {
  if (!enc || !enc.startsWith('ENC:')) return enc;
  const key = crypto.createHash('sha256').update(sid + MS, 'utf8').digest();
  const iv = crypto.createHash('md5').update('IV_' + sid, 'utf8').digest();
  const d = crypto.createDecipheriv('aes-256-cbc', key, iv);
  let r = d.update(enc.substring(4), 'base64', 'utf8');
  r += d.final('utf8');
  return r;
}

async function main() {
  const r = await fetch(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${API_KEY}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: 'tuan@mobile.com', password: '123123', returnSecureToken: true })
  });
  const a = await r.json();
  const t = a.idToken;

  // Get real sales (not test)
  const qr = await fetch(`https://firestore.googleapis.com/v1/projects/huyaka-1809/databases/(default)/documents:runQuery`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${t}` },
    body: JSON.stringify({
      structuredQuery: {
        from: [{ collectionId: 'sales' }],
        where: { fieldFilter: { field: { fieldPath: 'shopId' }, op: 'EQUAL', value: { stringValue: sid } } },
        limit: 5
      }
    })
  });
  const docs = await qr.json();
  
  console.log('Total docs returned:', docs.length);
  for (const d of docs) {
    if (!d.document) { console.log('No document in response entry'); continue; }
    const f = d.document.fields;
    const encNames = f.productNames?.stringValue || '';
    const encImeis = f.productImeis?.stringValue || '';
    const names = dec(encNames);
    const imeis = dec(encImeis);
    console.log('names:', names);
    console.log('imeis:', imeis);
    console.log('soldAt:', f.soldAt?.integerValue);
    console.log('---');
  }
}

main().catch(e => console.error('Error:', e.message || e));
