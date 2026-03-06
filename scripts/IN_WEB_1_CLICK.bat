@echo off
setlocal
chcp 65001 >nul

REM ===== Cấu hình cố định cho shop =====
set BRIDGE_PORT=19191
set PRINTER_IP=192.168.1.199
set PRINTER_PORT=9100
set WEB_URL=https://quanlyshop.web.app/?bridgeUrl=http://127.0.0.1:19191/print

echo ===============================================
echo   QUAN LY SHOP - IN WEB 1 CLICK
echo ===============================================
echo May in POS : %PRINTER_IP%:%PRINTER_PORT%
echo Bridge     : http://127.0.0.1:%BRIDGE_PORT%
echo.

where node >nul 2>&1
if errorlevel 1 (
  echo [LOI] May chua cai Node.js.
  echo Cai Node.js tu: https://nodejs.org
  echo Xong mo lai file nay.
  pause
  exit /b 1
)

REM Chay bridge o cua so rieng
start "WEB PRINT BRIDGE" cmd /k "set BRIDGE_PORT=%BRIDGE_PORT% && set DEFAULT_PRINTER_IP=%PRINTER_IP% && set DEFAULT_PRINTER_PORT=%PRINTER_PORT% && node "%~dp0web_print_bridge_server.js""

REM Cho bridge khoi dong 1 nhịp
timeout /t 2 /nobreak >nul

REM Mo web dung link in
start "" "%WEB_URL%"

echo Da mo web in.
echo.
echo Cach dung moi ngay:
echo 1) Double-click file IN_WEB_1_CLICK.bat
echo 2) Vao phieu va bam IN
echo.
echo Luu y: KHONG tat cua so "WEB PRINT BRIDGE" khi dang in.
pause
endlocal
