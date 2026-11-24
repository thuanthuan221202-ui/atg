@echo off
:: Tu dong xin quyen Admin de mo cong 8787 tren Windows Firewall
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -Command "Start-Process '%~f0' -Verb RunAs"
  exit /b
)
netsh advfirewall firewall delete rule name="Antigravity iOS Remote Bridge" >nul 2>&1
netsh advfirewall firewall add rule name="Antigravity iOS Remote Bridge" dir=in action=allow protocol=TCP localport=8787 profile=private,domain,public
echo [OK] Da mo cong TCP 8787 tren Windows Firewall cho Wi-Fi va Tailscale!
pause
