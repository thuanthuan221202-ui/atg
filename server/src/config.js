const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const CONFIG_PATH = path.join(__dirname, '..', 'bridge-config.json');

function findAgyBinary() {
  const candidates = [
    process.env.AGY_BIN,
    path.join(process.env.LOCALAPPDATA || '', 'agy', 'bin', 'agy.exe'),
    path.join(os.homedir(), '.local', 'bin', 'agy'),
    'agy'
  ].filter(Boolean);

  for (const c of candidates) {
    if (c === 'agy') return c;
    try {
      if (fs.existsSync(c)) return c;
    } catch (_) {}
  }
  return 'agy';
}

function loadOrCreateConfig() {
  let saved = {};
  try {
    if (fs.existsSync(CONFIG_PATH)) {
      saved = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
    }
  } catch (err) {
    console.warn('[config] Failed to parse existing bridge-config.json, regenerating:', err.message);
  }

  const config = {
    host: process.env.BRIDGE_HOST || saved.host || '0.0.0.0',
    port: Number(process.env.BRIDGE_PORT || saved.port || 8787),
    token: process.env.BRIDGE_TOKEN || saved.token || crypto.randomBytes(18).toString('base64url'),
    defaultCwd: process.env.BRIDGE_CWD || saved.defaultCwd || path.resolve(__dirname, '..', '..'),
    agyBin: process.env.AGY_BIN || saved.agyBin || findAgyBinary(),
    autoApproveSafe: Boolean(saved.autoApproveSafe || false)
  };

  // Validate saved agyBin still exists if it's an absolute path
  if (path.isAbsolute(config.agyBin) && !fs.existsSync(config.agyBin)) {
    config.agyBin = findAgyBinary();
  }

  // Validate defaultCwd exists
  if (!fs.existsSync(config.defaultCwd)) {
    config.defaultCwd = os.homedir();
  }

  try {
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), 'utf8');
  } catch (err) {
    console.warn('[config] Could not persist bridge-config.json:', err.message);
  }

  return config;
}

function getTailscaleCliIp() {
  const candidates = [
    'C:\\Program Files\\Tailscale\\tailscale.exe',
    'tailscale'
  ];
  for (const bin of candidates) {
    if (path.isAbsolute(bin) && !fs.existsSync(bin)) continue;
    try {
      const out = execFileSync(bin, ['ip', '-4'], { timeout: 2500, encoding: 'utf8', windowsHide: true }).trim();
      const firstLine = out.split(/\r?\n/)[0]?.trim();
      if (firstLine && /^100\./.test(firstLine)) {
        return { installed: true, ip: firstLine };
      }
      return { installed: true, ip: null };
    } catch (_) {
      if (path.isAbsolute(bin) && fs.existsSync(bin)) {
        return { installed: true, ip: null };
      }
    }
  }
  return { installed: false, ip: null };
}

function getNetworkAddresses() {
  const nets = os.networkInterfaces();
  const lan = [];
  const tailscale = [];
  const seenTs = new Set();

  for (const [name, addrs] of Object.entries(nets)) {
    if (!addrs) continue;
    for (const addr of addrs) {
      if (addr.family !== 'IPv4' || addr.internal) continue;
      const ip = addr.address;
      const isTailscale = name.toLowerCase().includes('tailscale') || /^100\.(6[4-9]|[7-9]\d|1[0-1]\d|12[0-7])\./.test(ip);
      if (isTailscale) {
        if (!seenTs.has(ip)) {
          seenTs.add(ip);
          tailscale.push({ name, ip });
        }
      } else {
        lan.push({ name, ip });
      }
    }
  }

  const tsCli = getTailscaleCliIp();
  if (tsCli.ip && !seenTs.has(tsCli.ip)) {
    seenTs.add(tsCli.ip);
    tailscale.unshift({ name: 'Tailscale', ip: tsCli.ip });
  }

  // Prefer Wi-Fi / Ethernet over virtual Hyper-V / VMware / vEthernet adapters
  const score = (item) => {
    const n = item.name.toLowerCase();
    if (n.includes('wi-fi') || n.includes('wifi') || n.includes('wlan')) return 0;
    if (n.includes('ethernet') && !n.includes('vethernet')) return 1;
    if (n.includes('vethernet') || n.includes('vmware') || n.includes('virtual') || n.includes('wsl')) return 10;
    return 5;
  };
  lan.sort((a, b) => score(a) - score(b));

  return { lan, tailscale, tailscaleInstalled: tsCli.installed || tailscale.length > 0 };
}

function normalizeWindowsPath(rawPath) {
  if (!rawPath || typeof rawPath !== 'string') return '';
  let p = rawPath.trim();
  // Convert URI-style Windows paths returned by Electron App, e.g. "/d%3A/Downloads"
  if (/^\/[a-zA-Z]%3[aA]\//.test(p)) {
    try {
      p = decodeURIComponent(p).slice(1); // "d:/Downloads"
    } catch (_) {}
  } else if (/^\/[a-zA-Z]:\//.test(p)) {
    p = p.slice(1);
  }
  if (/^[a-zA-Z]:[\\/]/.test(p)) {
    p = p[0].toUpperCase() + p.slice(1).replace(/\//g, '\\');
  }
  return p;
}

module.exports = {
  CONFIG_PATH,
  loadOrCreateConfig,
  getNetworkAddresses,
  normalizeWindowsPath
};
