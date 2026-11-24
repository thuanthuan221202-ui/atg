const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const { URL } = require('url');
const { WebSocketServer } = require('ws');
const qrcode = require('qrcode-terminal');

const { loadOrCreateConfig, getNetworkAddresses, normalizeWindowsPath } = require('./config');
const { AcpClient } = require('./acp-client');

const config = loadOrCreateConfig();
const acp = new AcpClient({
  agyBin: config.agyBin,
  defaultCwd: config.defaultCwd
});

const PUBLIC_INDEX = path.join(__dirname, '..', 'public', 'index.html');

function isAuthorized(req, urlObj) {
  const authHeader = req.headers['authorization'] || '';
  if (authHeader.startsWith('Bearer ') && authHeader.slice(7).trim() === config.token) {
    return true;
  }
  const queryToken = urlObj.searchParams.get('token');
  if (queryToken && queryToken === config.token) {
    return true;
  }
  return false;
}

function sendJson(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization, Content-Type',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
  });
  res.end(body);
}

function listWindowsDrives() {
  const drives = [];
  for (let code = 65; code <= 90; code++) {
    const letter = String.fromCharCode(code);
    const root = `${letter}:\\`;
    try {
      if (fs.existsSync(root)) drives.push(root);
    } catch (_) {}
  }
  return drives;
}

function listDirectory(rawTarget) {
  const drives = process.platform === 'win32' ? listWindowsDrives() : ['/'];
  let target = normalizeWindowsPath(rawTarget || config.defaultCwd);
  if (!target || !fs.existsSync(target)) {
    target = config.defaultCwd;
  }
  const resolved = path.resolve(target);
  const parsed = path.parse(resolved);
  const parent = resolved === parsed.root ? null : path.dirname(resolved);

  const entries = [];
  try {
    const items = fs.readdirSync(resolved, { withFileTypes: true });
    for (const item of items) {
      if (item.name.startsWith('$') || item.name === 'System Volume Information') continue;
      if (item.isDirectory()) {
        entries.push({
          name: item.name,
          path: path.join(resolved, item.name),
          isDirectory: true
        });
      }
    }
    entries.sort((a, b) => a.name.localeCompare(b.name));
  } catch (err) {
    return { path: resolved, parent, drives, entries: [], error: err.message };
  }

  return { path: resolved, parent, drives, entries };
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'Authorization, Content-Type',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS'
    });
    return res.end();
  }

  const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  const pathname = urlObj.pathname;

  // Lightweight fallback Web UI compatible with iOS 16.1 Safari
  if (pathname === '/' || pathname === '/index.html') {
    try {
      const html = fs.readFileSync(PUBLIC_INDEX, 'utf8');
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(html);
    } catch (err) {
      res.writeHead(500);
      return res.end('Fallback UI missing');
    }
  }

  // Public health check (no secrets)
  if (pathname === '/health') {
    return sendJson(res, 200, {
      ok: true,
      name: 'Antigravity Remote Bridge',
      host: os.hostname(),
      agentName: acp.agentInfo.name,
      agentVersion: acp.agentInfo.version,
      acpReady: acp.initialized
    });
  }

  // Protected API routes
  if (!isAuthorized(req, urlObj)) {
    return sendJson(res, 401, { error: 'Unauthorized: invalid or missing token' });
  }

  if (pathname === '/api/info') {
    const nets = getNetworkAddresses();
    return sendJson(res, 200, {
      host: os.hostname(),
      defaultCwd: config.defaultCwd,
      agentName: acp.agentInfo.name,
      agentVersion: acp.agentInfo.version,
      tier: acp.tierName,
      activeSessionId: acp.activeSessionId,
      lan: nets.lan,
      tailscale: nets.tailscale
    });
  }

  if (pathname === '/api/fs/list') {
    const dir = urlObj.searchParams.get('path') || config.defaultCwd;
    return sendJson(res, 200, listDirectory(dir));
  }

  if (pathname === '/api/sessions') {
    try {
      const sessions = await acp.listSessions();
      return sendJson(res, 200, { sessions });
    } catch (err) {
      return sendJson(res, 500, { error: err.message });
    }
  }

  return sendJson(res, 404, { error: 'Not found' });
});

const wss = new WebSocketServer({ noServer: true, maxPayload: 25 * 1024 * 1024 });

function broadcast(payload) {
  const str = JSON.stringify(payload);
  for (const client of wss.clients) {
    if (client.readyState === 1) {
      client.send(str);
    }
  }
}

// Wire ACP events to all connected iOS/Web clients
acp.on('message_chunk', (data) => broadcast({ type: 'message_chunk', ...data }));
acp.on('tool_call', (data) => broadcast({ type: 'tool_call', ...data }));
acp.on('session_meta', (data) => broadcast({ type: 'session_meta', ...data }));
acp.on('permission_request', (data) => broadcast({ type: 'permission_request', ...data }));
acp.on('permission_resolved', (data) => broadcast({ type: 'permission_resolved', ...data }));
acp.on('turn_started', (data) => broadcast({ type: 'turn_started', ...data }));
acp.on('turn_finished', (data) => broadcast({ type: 'turn_finished', ...data }));
acp.on('disconnected', () => {
  broadcast({ type: 'error', message: 'Antigravity ACP process stopped; it will auto-restart on next action.' });
});

server.on('upgrade', (req, socket, head) => {
  const urlObj = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  if (urlObj.pathname !== '/ws') {
    socket.write('HTTP/1.1 404 Not Found\r\n\r\n');
    return socket.destroy();
  }
  if (!isAuthorized(req, urlObj)) {
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    return socket.destroy();
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    wss.emit('connection', ws, req);
  });
});

wss.on('connection', async (ws) => {
  console.log(`[ws] Client connected (total=${wss.clients.size})`);
  ws.isAlive = true;
  ws.on('pong', () => { ws.isAlive = true; });

  const send = (obj) => {
    if (ws.readyState === 1) ws.send(JSON.stringify(obj));
  };

  try {
    await acp.ensureStarted();
    let sessions = [];
    try {
      sessions = await acp.listSessions();
    } catch (_) {}

    if (!acp.activeSessionId) {
      await acp.newSession(config.defaultCwd);
      try {
        sessions = await acp.listSessions();
      } catch (_) {}
    }

    const snap = acp.getActiveSnapshot();
    send({
      type: 'hello',
      host: os.hostname(),
      defaultCwd: config.defaultCwd,
      agentName: acp.agentInfo.name,
      agentVersion: acp.agentInfo.version,
      tier: acp.tierName,
      sessions,
      ...snap
    });
  } catch (err) {
    send({ type: 'error', message: `Failed to initialize Antigravity ACP: ${err.message}` });
  }

  ws.on('message', async (raw) => {
    let msg;
    try {
      msg = JSON.parse(raw.toString('utf8'));
    } catch (_) {
      return send({ type: 'error', message: 'Invalid JSON payload' });
    }

    try {
      switch (msg.type) {
        case 'ping':
          send({ type: 'pong', ts: Date.now() });
          break;

        case 'list_sessions': {
          const sessions = await acp.listSessions();
          send({ type: 'sessions_list', sessions });
          break;
        }

        case 'new_session': {
          const state = await acp.newSession(msg.cwd || config.defaultCwd);
          broadcast({
            type: 'session_ready',
            sessionId: state.sessionId,
            cwd: state.cwd,
            title: state.title,
            configOptions: state.configOptions,
            availableCommands: state.availableCommands,
            messages: state.messages,
            usage: state.usage,
            isGenerating: state.isGenerating
          });
          const sessions = await acp.listSessions().catch(() => []);
          broadcast({ type: 'sessions_list', sessions });
          break;
        }

        case 'load_session': {
          if (!msg.sessionId) throw new Error('sessionId is required');
          const state = await acp.loadSession(msg.sessionId, msg.cwd);
          send({
            type: 'session_ready',
            sessionId: state.sessionId,
            cwd: state.cwd,
            title: state.title,
            configOptions: state.configOptions,
            availableCommands: state.availableCommands,
            messages: state.messages,
            usage: state.usage,
            isGenerating: state.isGenerating
          });
          break;
        }

        case 'prompt': {
          // Run prompt asynchronously so WS loop stays responsive for permission_response / cancel!
          acp.sendPrompt(msg.sessionId, msg.text || '', msg.images || []).catch((err) => {
            broadcast({ type: 'error', message: err.message });
          });
          break;
        }

        case 'cancel':
          acp.cancel(msg.sessionId);
          break;

        case 'set_config': {
          if (!msg.configId || !msg.value) throw new Error('configId and value are required');
          await acp.setConfigOption(msg.sessionId, msg.configId, msg.value);
          break;
        }

        case 'permission_response': {
          if (!msg.requestId) throw new Error('requestId is required');
          acp.respondPermission(msg.requestId, msg.optionId || null, Boolean(msg.cancelled));
          break;
        }

        default:
          send({ type: 'error', message: `Unknown message type: ${msg.type}` });
      }
    } catch (err) {
      send({ type: 'error', message: err.message });
    }
  });

  ws.on('close', () => {
    console.log(`[ws] Client disconnected (total=${wss.clients.size})`);
  });
});

// Heartbeat to clean up dead mobile sockets
const heartbeat = setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.isAlive) {
      ws.terminate();
      continue;
    }
    ws.isAlive = false;
    ws.ping();
  }
}, 25000);

function printConnectionBanner() {
  const { lan, tailscale, tailscaleInstalled, funnelUrl } = getNetworkAddresses();
  const lanIp = lan[0] && lan[0].ip;
  const tsIp = tailscale[0] && tailscale[0].ip;
  const fallbackUrl = funnelUrl || `http://${tsIp || lanIp || '127.0.0.1'}:${config.port}`;

  console.log('\n==============================================================');
  console.log('  Antigravity iOS Remote Bridge is RUNNING');
  console.log('==============================================================');
  console.log(`  PC Name       : ${os.hostname()}`);
  console.log(`  Default Folder: ${config.defaultCwd}`);
  console.log(`  Auth Token    : ${config.token}`);
  console.log('');
  if (funnelUrl) {
    console.log(`  [4G/5G HTTPS - Khong can app VPN tren iPhone]:`);
    console.log(`    - ${funnelUrl}`);
  }
  if (tailscale.length) {
    console.log('  [Tailscale VPN] URLs:');
    for (const n of tailscale) {
      console.log(`    - http://${n.ip}:${config.port}  (${n.name})`);
    }
  } else if (tailscaleInstalled) {
    console.log('  [Tailscale] Da cai dat nhung chua dang nhap.');
    console.log('              Hay mo Tailscale o khay he thong Windows va Sign in!');
  }
  if (lan.length) {
    console.log('  [Wi-Fi LAN] Local URLs:');
    for (const n of lan) {
      console.log(`    - http://${n.ip}:${config.port}  (${n.name})`);
    }
  }

  if (funnelUrl) {
    const funnelPair = `agyr://connect?url=${encodeURIComponent(funnelUrl)}&token=${encodeURIComponent(config.token)}&name=${encodeURIComponent(os.hostname() + ' (4G/5G HTTPS)')}`;
    console.log('\n  --- QR #1: 4G/5G HTTPS CO DINH (Khong can cai Tailscale tren iPhone) ---');
    console.log(`  URI: ${funnelPair}\n`);
    qrcode.generate(funnelPair, { small: true });
  } else if (tsIp) {
    const tsUrl = `http://${tsIp}:${config.port}`;
    const tsPair = `agyr://connect?url=${encodeURIComponent(tsUrl)}&token=${encodeURIComponent(config.token)}&name=${encodeURIComponent(os.hostname() + ' (Tailscale 4G)')}`;
    console.log('\n  --- QR #1: TAILSCALE (Dung moi noi qua 4G/5G & Wi-Fi) ---');
    console.log(`  URI: ${tsPair}\n`);
    qrcode.generate(tsPair, { small: true });
  }

  if (lanIp) {
    const lanUrl = `http://${lanIp}:${config.port}`;
    const lanPair = `agyr://connect?url=${encodeURIComponent(lanUrl)}&token=${encodeURIComponent(config.token)}&name=${encodeURIComponent(os.hostname() + ' (Wi-Fi)')}`;
    console.log(`\n  --- QR ${(funnelUrl || tsIp) ? '#2' : '#1'}: WI-FI LAN (Cung mang Wi-Fi) ---`);
    console.log(`  URI: ${lanPair}\n`);
    qrcode.generate(lanPair, { small: true });
  }

  console.log(`  iOS 16.1 Safari Backup Web UI: ${fallbackUrl}/?token=${config.token}`);
  console.log('==============================================================\n');
}

async function main() {
  server.on('error', (err) => {
    if (err.code === 'EADDRINUSE') {
      if (acp.proc) acp.proc.kill();
      console.log(`\n[OK] Antigravity Bridge DANG CHAY NGAM SAN tren cong ${config.port}!`);
      console.log('     Ban KHONG can mo them cua so start-bridge.bat nua.');
      printConnectionBanner();
      return;
    }
    console.error('[server] Error:', err);
    process.exit(1);
  });

  try {
    await acp.start();
  } catch (err) {
    console.error(`[startup] Warning: could not pre-start agy acp: ${err.message}`);
    console.error('Make sure Antigravity CLI (agy) is installed and signed in.');
  }

  server.listen(config.port, config.host, () => {
    printConnectionBanner();
  });
}

process.on('SIGINT', () => {
  clearInterval(heartbeat);
  if (acp.proc) acp.proc.kill();
  process.exit(0);
});

main();
