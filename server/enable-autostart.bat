@echo off
setlocal
set "SERVER_DIR=%~dp0"
if "%SERVER_DIR:~-1%"=="\" set "SERVER_DIR=%SERVER_DIR:~0,-1%"
set "STARTUP_VBS=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\AntigravityRemoteBridge.vbs"

(
  echo Set WshShell = CreateObject("WScript.Shell"^)
  echo WshShell.CurrentDirectory = "%SERVER_DIR%"
  echo WshShell.Run "cmd /c node src\index.js >> logs\bridge.log 2>&1", 0, False
) > "%STARTUP_VBS%"

if not exist "%SERVER_DIR%\logs" mkdir "%SERVER_DIR%\logs"

echo [OK] Da bat tu dong chay ngam Antigravity Bridge khi khoi dong Windows!
echo File khoi dong: "%STARTUP_VBS%"
echo De xem ma QR bat ky luc nao, chay: show-qr.bat
pause
