@echo off
title Antigravity iOS Remote Bridge
cd /d "%~dp0"
if not exist "node_modules" (
  echo Installing dependencies...
  call npm install
)
echo Starting Antigravity iOS Remote Bridge...
node src/index.js
pause
