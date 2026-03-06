/*
  LAN Print Bridge for web -> POS printer
  Run: node scripts/web_print_bridge_server.js

  Optional env:
    BRIDGE_PORT=19191
    BRIDGE_TOKEN=your_secret_token
    DEFAULT_PRINTER_IP=192.168.1.100
    DEFAULT_PRINTER_PORT=9100
*/

const http = require('http');
const net = require('net');

const PORT = Number(process.env.BRIDGE_PORT || 19191);
const TOKEN = (process.env.BRIDGE_TOKEN || '').trim();
const DEFAULT_PRINTER_IP = (process.env.DEFAULT_PRINTER_IP || '').trim();
const DEFAULT_PRINTER_PORT = Number(process.env.DEFAULT_PRINTER_PORT || 9100);

function sendJson(res, status, payload) {
  const body = JSON.stringify(payload);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type, x-bridge-token',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  });
  res.end(body);
}

function writeToPrinter({ host, port, bytes }) {
  return new Promise((resolve, reject) => {
    const socket = new net.Socket();
    let done = false;

    const finish = (err) => {
      if (done) return;
      done = true;
      try {
        socket.destroy();
      } catch (_) {}
      if (err) reject(err);
      else resolve(true);
    };

    socket.setTimeout(8000);

    socket.once('connect', () => {
      socket.write(bytes, (err) => {
        if (err) return finish(err);
        socket.end();
      });
    });

    socket.once('timeout', () => finish(new Error('Printer socket timeout')));
    socket.once('error', (err) => finish(err));
    socket.once('close', () => finish());

    socket.connect(port, host);
  });
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    return sendJson(res, 200, { ok: true });
  }

  if (req.method === 'GET' && req.url === '/health') {
    return sendJson(res, 200, {
      ok: true,
      service: 'web-print-bridge',
      port: PORT,
      defaultPrinterIp: DEFAULT_PRINTER_IP || null,
      time: Date.now(),
    });
  }

  if (req.method !== 'POST' || req.url !== '/print') {
    return sendJson(res, 404, { ok: false, error: 'Not found' });
  }

  if (TOKEN) {
    const provided = (req.headers['x-bridge-token'] || '').toString().trim();
    if (!provided || provided !== TOKEN) {
      return sendJson(res, 401, { ok: false, error: 'Invalid bridge token' });
    }
  }

  const chunks = [];
  req.on('data', (chunk) => chunks.push(chunk));
  req.on('error', (err) => {
    sendJson(res, 400, { ok: false, error: err.message || String(err) });
  });

  req.on('end', async () => {
    try {
      const raw = Buffer.concat(chunks).toString('utf8');
      const payload = raw ? JSON.parse(raw) : {};

      const bytesBase64 = (payload.bytesBase64 || '').toString();
      if (!bytesBase64) {
        return sendJson(res, 400, { ok: false, error: 'bytesBase64 is required' });
      }

      const bytes = Buffer.from(bytesBase64, 'base64');
      if (!bytes.length) {
        return sendJson(res, 400, { ok: false, error: 'Decoded bytes are empty' });
      }

      const printerIp = (payload.printerIp || DEFAULT_PRINTER_IP || '').toString().trim();
      const printerPort = Number(payload.port || DEFAULT_PRINTER_PORT || 9100);

      if (!printerIp) {
        return sendJson(res, 400, {
          ok: false,
          error: 'Missing printerIp. Provide payload.printerIp or DEFAULT_PRINTER_IP env.',
        });
      }

      await writeToPrinter({ host: printerIp, port: printerPort, bytes });

      return sendJson(res, 200, {
        ok: true,
        printerIp,
        printerPort,
        bytes: bytes.length,
        printedAt: Date.now(),
      });
    } catch (err) {
      return sendJson(res, 500, {
        ok: false,
        error: err.message || String(err),
      });
    }
  });
});

server.listen(PORT, () => {
  console.log(`[web-print-bridge] Listening on http://0.0.0.0:${PORT}`);
  if (DEFAULT_PRINTER_IP) {
    console.log(
      `[web-print-bridge] Default printer: ${DEFAULT_PRINTER_IP}:${DEFAULT_PRINTER_PORT}`,
    );
  }
  if (TOKEN) {
    console.log('[web-print-bridge] Token auth: enabled');
  } else {
    console.log('[web-print-bridge] Token auth: disabled');
  }
});
