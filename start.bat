@echo off
title Fee Five - AI Accessibility & Transit System Launcher
echo ========================================================
echo   Fee Five - Accessible Mobile & Transit AI System
echo   Starting Backend (FastAPI) and Frontend (Flutter Web)
echo ========================================================
echo.

cd /d "%~dp0"

:: 1. Check Python
where python >nul 2>nul
if %errorlevel% neq 0 (
    echo [ERROR] Python not found in PATH! Please install Python 3.10+.
    pause
    exit /b 1
)

:: 2. Check Flutter
set FLUTTER_BIN=C:\src\flutter\bin\flutter.bat
if not exist "%FLUTTER_BIN%" (
    where flutter >nul 2>nul
    if %errorlevel% equ 0 (
        set FLUTTER_BIN=flutter
    ) else (
        echo [ERROR] Flutter SDK not found at C:\src\flutter\bin\flutter.bat or PATH!
        pause
        exit /b 1
    )
)

:: 3. Ingest Local GTFS Data into Database
echo [1/3] Syncing local Bangkok GTFS dataset into database...
python backend\scripts\sync_gtfs.py --source datasets\bangkok-gtfs\data\gtfs

:: 4. Start Backend in separate window
echo [2/3] Starting FastAPI Backend on http://localhost:8000 ...
start "TAM - Backend (FastAPI)" cmd /k "cd /d %~dp0backend && python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload"

:: 5. Start Flutter Web in separate window
echo [3/3] Starting Flutter Web Server on http://localhost:8080 ...
start "TAM - Frontend (Flutter Web)" cmd /k "cd /d %~dp0mobile && %FLUTTER_BIN% run -d web-server --web-port 8080 --web-hostname localhost"

:: 6. Wait for Web Server and Open Browser
echo Waiting for servers to initialize (7 seconds)...
timeout /t 7 /nobreak >nul

echo Opening web application at http://localhost:8080 ...
start http://localhost:8080

echo.
echo ========================================================
echo   System is running!
echo   - Frontend: http://localhost:8080
echo   - Backend API Docs: http://localhost:8000/docs
echo   - GTFS Transit API: http://localhost:8000/api/v1/gtfs/status
echo ========================================================
echo.
pause
