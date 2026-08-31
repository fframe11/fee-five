#!/bin/bash
# Fee Five - Accessible Mobile & Transit System Launcher
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR"

echo "========================================================"
echo "  Fee Five - Accessible Mobile & Transit AI System"
echo "  Starting GTFS Sync, Backend (FastAPI) and Frontend"
echo "========================================================"
echo ""

# 1. Ingest Local GTFS Data into Database
echo "[1/3] Syncing local Bangkok GTFS dataset into database..."
python3 backend/scripts/sync_gtfs.py --source datasets/bangkok-gtfs/data/gtfs || true

# 2. Start Backend
echo "[2/3] Starting FastAPI Backend on http://localhost:8000 ..."
(cd "$DIR/backend" && python3 -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload) &
BACKEND_PID=$!

# 3. Start Frontend
echo "[3/3] Starting Flutter Web Server on http://localhost:8080 ..."
(cd "$DIR/mobile" && flutter run -d web-server --web-port 8080 --web-hostname localhost) &
FRONTEND_PID=$!

# 4. Wait and open browser
echo "Waiting for servers to initialize..."
sleep 6

if which xdg-open > /dev/null; then
  xdg-open "http://localhost:8080"
elif which open > /dev/null; then
  open "http://localhost:8080"
fi

echo "System is running. Press Ctrl+C to stop."
wait $BACKEND_PID $FRONTEND_PID
