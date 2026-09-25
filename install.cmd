@echo off
setlocal EnableExtensions
title VPN Access installer

set "SCRIPT_DIR=%~dp0"
set "PS1=%SCRIPT_DIR%Install-VpnAccess.ps1"

net session >nul 2>&1
if errorlevel 1 (
  echo Requesting Administrator rights...
  powershell.exe -NoProfile -Command "Start-Process -FilePath '%ComSpec%' -ArgumentList '/c \"\"%~f0\" %*\"' -Verb RunAs"
  exit /b
)

if not exist "%PS1%" (
  echo ERROR: Missing "%PS1%"
  pause
  exit /b 1
)

echo Running Install-VpnAccess.ps1
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"
echo.
if not "%RC%"=="0" (
  echo Install failed with exit code %RC%
  echo See C:\Temp\vpnaccess-install.log
) else (
  echo Install finished.
)
echo.
pause
exit /b %RC%
