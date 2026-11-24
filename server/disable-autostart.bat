@echo off
set "STARTUP_VBS=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\AntigravityRemoteBridge.vbs"
if exist "%STARTUP_VBS%" (
  del /f /q "%STARTUP_VBS%"
  echo [OK] Da tat tu dong chay ngam Antigravity Bridge.
) else (
  echo Chua bat tu dong chay ngam.
)
pause
