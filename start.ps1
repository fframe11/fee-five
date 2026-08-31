# Fee Five - PowerShell Startup Script
# Run with: powershell -ExecutionPolicy Bypass -File .\start.ps1

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  Fee Five - Accessible Mobile & Transit AI System" -ForegroundColor Yellow
Write-Host "  Starting Backend (FastAPI) and Frontend (Flutter Web)" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host ""

$PSScriptRoot = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition
Set-Location $PSScriptRoot

# 1. Check Python
$pythonCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pythonCmd) {
    Write-Host "[ERROR] Python was not found in PATH! Please install Python 3.10+." -ForegroundColor Red
    Pause
    Exit 1
}

# 2. Check Flutter
$flutterBin = "C:\src\flutter\bin\flutter.bat"
if (-not (Test-Path $flutterBin)) {
    $flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCmd) {
        $flutterBin = "flutter"
    } else {
        Write-Host "[ERROR] Flutter SDK not found at C:\src\flutter\bin\flutter.bat or in PATH!" -ForegroundColor Red
        Pause
        Exit 1
    }
}

# 3. Ingest Local GTFS Data into Database
Write-Host "[1/3] Syncing local Bangkok GTFS dataset into database..." -ForegroundColor Green
python backend/scripts/sync_gtfs.py --source datasets/bangkok-gtfs/data/gtfs

# 4. Start Backend FastAPI
Write-Host "[2/3] Starting FastAPI Backend on http://localhost:8000 ..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot\backend'; Write-Host 'FastAPI Backend Running on http://localhost:8000' -ForegroundColor Cyan; python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload"

# 5. Start Flutter Web
Write-Host "[3/3] Starting Flutter Web Server on http://localhost:8080 ..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd '$PSScriptRoot\mobile'; Write-Host 'Flutter Web Running on http://localhost:8080' -ForegroundColor Cyan; & '$flutterBin' run -d web-server --web-port 8080 --web-hostname localhost"

# 6. Wait for Web Server to be reachable and launch browser
Write-Host "Waiting for Web Server to be ready..." -ForegroundColor Yellow

$maxRetries = 90
$retry = 0
$serverReady = $false

while ($retry -lt $maxRetries -and -not $serverReady) {
    Start-Sleep -Seconds 1
    $retry++
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8080" -UseBasicParsing -TimeoutSec 1 -ErrorAction SilentlyContinue
        if ($response.StatusCode -eq 200) {
            $serverReady = $true
        }
    } catch {
        # Keep waiting
    }
    Write-Host "." -NoNewline -ForegroundColor Gray
}

Write-Host ""
Write-Host "Opening web browser at http://localhost:8080 ..." -ForegroundColor Green
Start-Process "http://localhost:8080"

Write-Host ""
Write-Host "========================================================" -ForegroundColor Cyan
Write-Host "  System is RUNNING!" -ForegroundColor Green
Write-Host "  - Frontend: http://localhost:8080" -ForegroundColor White
Write-Host "  - Backend API Docs: http://localhost:8000/docs" -ForegroundColor White
Write-Host "  - GTFS Transit API: http://localhost:8000/api/v1/gtfs/status" -ForegroundColor White
Write-Host "========================================================" -ForegroundColor Cyan
