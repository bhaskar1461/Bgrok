@echo off
:: bgrok Signaling Relay Server Deployment Runner (Windows)
:: Starts the FastAPI Signaling Relay in background, writing outputs to relay.log

title bgrok Signaling Relay Server
echo ==================================================
echo       bgrok Signaling Relay Deployment Tool
echo ==================================================
echo.

:: Check if port 8765 is already in use
netstat -aon | findstr :8765 >nul
if %errorlevel% equ 0 (
    echo [ERROR] Port 8765 is already occupied. Relay may already be running.
    echo Please run relay_service_stop.bat first to stop any existing process.
    echo.
    pause
    exit /b 1
)

echo Starting FastAPI Signaling Relay in background on port 8765...
start /B "bgrok_relay_service" pythonw -m uvicorn relay.relay:app --host 0.0.0.0 --port 8765 > relay.log 2>&1

:: Wait a brief second and confirm it's running
timeout /t 2 /nobreak >nul
netstat -aon | findstr :8765 >nul
if %errorlevel% equ 0 (
    echo [SUCCESS] Relay server is successfully running in background on port 8765.
    echo Log file is actively capturing events at: %CD%\relay.log
) else (
    echo [WARNING] Could not verify port binding. Check %CD%\relay.log for startup failures.
)
echo.
pause
