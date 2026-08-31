@echo off
echo ===================================================
echo   Fee Five - Bangkok GTFS Integration Sync Tool
echo ===================================================
python backend\scripts\sync_gtfs.py --source datasets\bangkok-gtfs\data\gtfs
pause
