"""
Bangkok GTFS Synchronization CLI Script
Can be run manually or as a scheduled task (cron / Windows Task Scheduler).

Usage:
    python backend/scripts/sync_gtfs.py
    python backend/scripts/sync_gtfs.py --download
    python backend/scripts/sync_gtfs.py --source datasets/bangkok-gtfs/data/gtfs --max-routes 100 --max-stops 500
"""

import sys
import os
import argparse
import logging

# Ensure backend root is in sys.path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from app.gtfs_service import sync_gtfs_data, get_gtfs_status
from app.database import engine, Base

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("gtfs_cli")


def main():
    parser = argparse.ArgumentParser(description="Synchronize Bangkok GTFS dataset into Fee Five database")
    parser.add_argument("--source", type=str, default=None, help="Path to GTFS directory containing routes.txt, stops.txt, etc.")
    parser.add_argument("--download", action="store_true", help="Force download latest snapshot zip from GitHub")
    parser.add_argument("--max-routes", type=int, default=None, help="Limit number of routes to import")
    parser.add_argument("--max-stops", type=int, default=None, help="Limit number of stops to import")
    parser.add_argument("--max-trips", type=int, default=None, help="Limit number of trips to import")
    parser.add_argument("--max-stop-times", type=int, default=10000, help="Limit number of stop_times to import (default: 10000)")
    parser.add_argument("--status-only", action="store_true", help="Only check and print current database status")

    args = parser.parse_args()

    # Ensure tables exist
    try:
        Base.metadata.create_all(bind=engine)
    except Exception as e:
        logger.warning(f"Could not initialize tables automatically: {e}")

    if args.status_only:
        status = get_gtfs_status()
        logger.info(f"GTFS Status: {status}")
        return

    logger.info("Starting Bangkok GTFS sync...")
    result = sync_gtfs_data(
        gtfs_dir=args.source,
        max_routes=args.max_routes,
        max_stops=args.max_stops,
        max_trips=args.max_trips,
        max_stop_times=args.max_stop_times,
        download_if_missing=args.download
    )

    logger.info("--------------------------------------------------")
    logger.info(f"Sync Status: {result.status.upper()}")
    logger.info(f"Source: {result.source}")
    logger.info(f"Routes imported: {result.routes_count}")
    logger.info(f"Stops imported: {result.stops_count}")
    logger.info(f"Trips imported: {result.trips_count}")
    logger.info(f"Stop Times imported: {result.stop_times_count}")
    if result.error:
        logger.error(f"Errors: {result.error}")
    logger.info("--------------------------------------------------")


if __name__ == "__main__":
    main()
