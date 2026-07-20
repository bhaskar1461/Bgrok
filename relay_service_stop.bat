@echo off
:: bgrok Signaling Relay Server Stopper (Windows)
:: Kills the background relay server tasks listening on port 8765

title bgrok Stopper Tool
echo ==================================================
echo       bgrok Signaling Relay Stopper Tool
echo ==================================================
echo.

set pid=
for /f "tokens=5" %%a in ('netstat -aon ^| findstr :8765') do (
    set pid=%%a
)

if "%pid%"=="" (
    echo [INFO] No active processes detected listening on port 8765. Relay is already stopped.
    echo.
    pause
    exit /b 0
)

echo Found active Relay process on PID: %pid%
echo Stopping and terminating task...
taskkill /F /PID %pid% >nul 2>&1

if %errorlevel% equ 0 (
    echo [SUCCESS] Terminated background relay process successfully.
) else (
    echo [ERROR] Failed to terminate process. You may need to run as Administrator.
)
echo.
pause
