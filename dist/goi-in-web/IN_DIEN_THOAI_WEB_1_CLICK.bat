@echo off
setlocal
chcp 65001 >nul

set BRIDGE_PORT=19191
set PRINTER_IP=192.168.1.199

set /p INPUT_PRINTER_IP=Nhap IP may in (Enter de dung %PRINTER_IP%): 
if not "%INPUT_PRINTER_IP%"=="" set PRINTER_IP=%INPUT_PRINTER_IP%

echo ===============================================
echo   QUAN LY SHOP - IN TU DIEN THOAI (1 CLICK)
echo ===============================================
echo IP may in POS: %PRINTER_IP%
echo.

where node >nul 2>&1
if errorlevel 1 (
  echo [LOI] May chua cai Node.js.
  echo Cai Node.js tai: https://nodejs.org
  pause
  exit /b 1
)

start "WEB PRINT BRIDGE" cmd /k "call \"%~dp0scripts\start_web_print_bridge.bat\" %PRINTER_IP%"

timeout /t 2 /nobreak >nul

for /f "delims=" %%i in ('powershell -NoProfile -Command "(Get-NetIPAddress -AddressFamily IPv4 ^| Where-Object {$_.IPAddress -notlike '169.*' -and $_.IPAddress -notlike '127.*'} ^| Select-Object -First 1 -ExpandProperty IPAddress)"') do set LOCAL_IP=%%i
if "%LOCAL_IP%"=="" set LOCAL_IP=127.0.0.1

set MOBILE_LINK=https://quanlyshop.web.app/?bridgeUrl=http://%LOCAL_IP%:%BRIDGE_PORT%/print

echo Link mo tren dien thoai:
echo %MOBILE_LINK%
echo.
echo %MOBILE_LINK% | clip
echo Da copy link vao clipboard.
echo.
echo CACH DUNG:
echo 1) Mo link tren dien thoai cung wifi
echo 2) Vao phieu va bam IN
echo.
echo Khong dong cua so "WEB PRINT BRIDGE" khi dang in.
pause
endlocal
