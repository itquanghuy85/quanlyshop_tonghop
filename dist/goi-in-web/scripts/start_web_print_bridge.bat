@echo off
setlocal

set BRIDGE_PORT=19191
set PRINTER_IP=%1
if "%PRINTER_IP%"=="" set PRINTER_IP=192.168.1.199

set /p INPUT_PRINTER_IP=Nhap IP may in (Enter de dung %PRINTER_IP%): 
if not "%INPUT_PRINTER_IP%"=="" set PRINTER_IP=%INPUT_PRINTER_IP%

echo ==============================================
echo  WEB PRINT BRIDGE - QUAN LY SHOP
echo ==============================================
echo Bridge Port   : %BRIDGE_PORT%
echo Printer IP    : %PRINTER_IP%
echo Printer Port  : 9100
echo.
echo Keep this window open while printing from web.
echo.

set DEFAULT_PRINTER_IP=%PRINTER_IP%
set DEFAULT_PRINTER_PORT=9100
set BRIDGE_PORT=%BRIDGE_PORT%

node "%~dp0web_print_bridge_server.js"

endlocal
