const os = require('os');
const qrcode = require('qrcode-terminal');
const { loadOrCreateConfig, getNetworkAddresses } = require('./config');

const config = loadOrCreateConfig();
const { lan, tailscale, tailscaleInstalled } = getNetworkAddresses();
const lanIp = lan[0] && lan[0].ip;
const tsIp = tailscale[0] && tailscale[0].ip;

console.log('\n==============================================================');
console.log('  Antigravity Remote — QR Codes & Connection Info');
console.log('==============================================================');
console.log(`  PC Name   : ${os.hostname()}`);
console.log(`  Port      : ${config.port}`);
console.log(`  Auth Token: ${config.token}`);

if (tsIp) {
  const tsUrl = `http://${tsIp}:${config.port}`;
  const tsPair = `agyr://connect?url=${encodeURIComponent(tsUrl)}&token=${encodeURIComponent(config.token)}&name=${encodeURIComponent(os.hostname() + ' (Tailscale 4G)')}`;
  console.log(`\n  [1] TAILSCALE 4G/5G (Dung moi noi): ${tsUrl}`);
  qrcode.generate(tsPair, { small: true });
} else if (tailscaleInstalled) {
  console.log('\n  [!] Tailscale da cai dat nhung chua dang nhap / chua bat.');
  console.log('      Hay mo Tailscale o goc duoi ben phai Windows -> Sign in, sau do chay lai file nay.');
} else {
  console.log('\n  [!] Chua tim thay Tailscale tren may tinh nay.');
}

if (lanIp) {
  const lanUrl = `http://${lanIp}:${config.port}`;
  const lanPair = `agyr://connect?url=${encodeURIComponent(lanUrl)}&token=${encodeURIComponent(config.token)}&name=${encodeURIComponent(os.hostname() + ' (Wi-Fi)')}`;
  console.log(`\n  [2] WI-FI LAN (Cung mang Wi-Fi): ${lanUrl}`);
  qrcode.generate(lanPair, { small: true });
}
console.log('==============================================================\n');
