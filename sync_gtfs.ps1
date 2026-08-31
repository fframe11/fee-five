Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "  Fee Five - Bangkok GTFS Integration Sync Tool" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan

python backend\scripts\sync_gtfs.py --source datasets\bangkok-gtfs\data\gtfs
