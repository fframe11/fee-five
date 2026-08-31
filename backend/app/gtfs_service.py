"""
Bangkok GTFS Integration Service for Fee Five Backend
Handles downloading snapshots from GitHub (asiripanich/bangkok-gtfs),
extracting ZIP files, parsing CSV tables in chunks, and syncing into database.
"""

import os
import csv
import io
import zipfile
import logging
import urllib.request
import math
from typing import Dict, Any, List, Optional, Generator
from sqlalchemy.orm import Session
from sqlalchemy import text, func

from .models import GTFSRoute, GTFSStop, GTFSTrip, GTFSStopTime, GTFSVehiclePosition
from .database import SessionLocal

logger = logging.getLogger("gtfs_service")
logger.setLevel(logging.INFO)

DEFAULT_GITHUB_REPO = "asiripanich/bangkok-gtfs"
DEFAULT_ZIP_URL = "https://github.com/asiripanich/bangkok-gtfs/archive/refs/heads/main.zip"
DEFAULT_LOCAL_GTFS_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "datasets",
    "bangkok-gtfs",
    "data",
    "gtfs"
)


class GTFSSyncResult:
    def __init__(self):
        self.routes_count: int = 0
        self.stops_count: int = 0
        self.trips_count: int = 0
        self.stop_times_count: int = 0
        self.status: str = "success"
        self.error: Optional[str] = None
        self.source: str = ""

    def to_dict(self) -> Dict[str, Any]:
        return {
            "status": self.status,
            "source": self.source,
            "routes_count": self.routes_count,
            "stops_count": self.stops_count,
            "trips_count": self.trips_count,
            "stop_times_count": self.stop_times_count,
            "error": self.error,
        }


def download_gtfs_zip(url: str = DEFAULT_ZIP_URL, target_dir: Optional[str] = None) -> str:
    """
    Downloads GTFS snapshot zip from GitHub repository.
    Returns path to extracted directory.
    """
    if target_dir is None:
        target_dir = os.path.join(os.path.dirname(__file__), "..", "gtfs_temp")
    os.makedirs(target_dir, exist_ok=True)
    
    zip_path = os.path.join(target_dir, "bangkok_gtfs_snapshot.zip")
    logger.info(f"Downloading GTFS from {url} to {zip_path}...")
    
    # Secure download with custom user-agent
    req = urllib.request.Request(
        url,
        headers={"User-Agent": "FeeFive-Transit-Agent/1.0"}
    )
    with urllib.request.urlopen(req, timeout=30) as response, open(zip_path, "wb") as out_file:
        out_file.write(response.read())
        
    logger.info(f"Extracting {zip_path}...")
    with zipfile.ZipFile(zip_path, "r") as zip_ref:
        zip_ref.extractall(target_dir)
        
    # Find data/gtfs folder inside extracted repo
    extracted_gtfs_dir = None
    for root, dirs, files in os.walk(target_dir):
        if "routes.txt" in files and "stops.txt" in files:
            extracted_gtfs_dir = root
            break
            
    if not extracted_gtfs_dir:
        extracted_gtfs_dir = target_dir
        
    logger.info(f"GTFS files extracted to: {extracted_gtfs_dir}")
    return extracted_gtfs_dir


def read_csv_dict(file_path: str, max_rows: Optional[int] = None) -> Generator[Dict[str, str], None, None]:
    """
    Safely reads GTFS CSV text files with UTF-8 / UTF-8-sig encoding and handles BOM.
    Yields rows as dictionaries.
    """
    if not os.path.exists(file_path):
        return
        
    with open(file_path, mode="r", encoding="utf-8-sig", errors="replace") as f:
        reader = csv.DictReader(f)
        count = 0
        for row in reader:
            if max_rows and count >= max_rows:
                break
            # Clean string values
            cleaned = {k.strip() if k else "": (v.strip() if v else "") for k, v in row.items()}
            yield cleaned
            count += 1


def sync_gtfs_data(
    gtfs_dir: Optional[str] = None,
    db: Optional[Session] = None,
    max_routes: Optional[int] = None,
    max_stops: Optional[int] = None,
    max_trips: Optional[int] = None,
    max_stop_times: Optional[int] = None,
    download_if_missing: bool = True
) -> GTFSSyncResult:
    """
    Synchronizes GTFS data from directory into database.
    """
    result = GTFSSyncResult()
    close_db = False
    
    if db is None:
        db = SessionLocal()
        close_db = True
        
    try:
        # Determine GTFS source directory
        actual_dir = gtfs_dir or DEFAULT_LOCAL_GTFS_DIR
        if not os.path.exists(actual_dir) or not os.path.exists(os.path.join(actual_dir, "routes.txt")):
            if download_if_missing:
                logger.info(f"Local GTFS directory {actual_dir} not found. Attempting download from GitHub...")
                actual_dir = download_gtfs_zip()
            else:
                raise FileNotFoundError(f"GTFS directory not found at {actual_dir}")
                
        result.source = actual_dir
        logger.info(f"Syncing GTFS data from: {actual_dir}")

        # 1. Ingest Routes (routes.txt)
        routes_path = os.path.join(actual_dir, "routes.txt")
        if os.path.exists(routes_path):
            existing_route_ids = {r[0] for r in db.query(GTFSRoute.route_id).all()}
            routes_to_add = []
            for row in read_csv_dict(routes_path, max_rows=max_routes):
                r_id = row.get("route_id")
                if not r_id:
                    continue
                short_name = row.get("route_short_name", "")
                long_name = row.get("route_long_name", "")
                try:
                    r_type = int(row.get("route_type", "3"))
                except ValueError:
                    r_type = 3

                if r_id in existing_route_ids:
                    # Update existing
                    route_obj = db.query(GTFSRoute).filter(GTFSRoute.route_id == r_id).first()
                    if route_obj:
                        route_obj.route_short_name = short_name
                        route_obj.route_long_name = long_name
                        route_obj.route_type = r_type
                else:
                    route_obj = GTFSRoute(
                        route_id=r_id,
                        route_short_name=short_name,
                        route_long_name=long_name,
                        route_type=r_type
                    )
                    routes_to_add.append(route_obj)
                    existing_route_ids.add(r_id)

                if len(routes_to_add) >= 500:
                    db.add_all(routes_to_add)
                    db.commit()
                    routes_to_add = []

            if routes_to_add:
                db.add_all(routes_to_add)
                db.commit()

            result.routes_count = db.query(GTFSRoute).count()
            logger.info(f"Total Routes in DB: {result.routes_count}")

        # 2. Ingest Stops (stops.txt)
        stops_path = os.path.join(actual_dir, "stops.txt")
        if os.path.exists(stops_path):
            existing_stop_ids = {s[0] for s in db.query(GTFSStop.stop_id).all()}
            stops_to_add = []
            for row in read_csv_dict(stops_path, max_rows=max_stops):
                s_id = row.get("stop_id")
                if not s_id:
                    continue
                s_name = row.get("stop_name", f"Stop {s_id}")
                try:
                    lat = float(row.get("stop_lat", "0"))
                    lon = float(row.get("stop_lon", "0"))
                except ValueError:
                    continue

                geom_point = f"SRID=4326;POINT({lon} {lat})"

                if s_id in existing_stop_ids:
                    stop_obj = db.query(GTFSStop).filter(GTFSStop.stop_id == s_id).first()
                    if stop_obj:
                        stop_obj.stop_name = s_name
                        stop_obj.stop_lat = lat
                        stop_obj.stop_lon = lon
                        stop_obj.geom = geom_point
                else:
                    stop_obj = GTFSStop(
                        stop_id=s_id,
                        stop_name=s_name,
                        stop_lat=lat,
                        stop_lon=lon,
                        geom=geom_point
                    )
                    stops_to_add.append(stop_obj)
                    existing_stop_ids.add(s_id)

                if len(stops_to_add) >= 500:
                    db.add_all(stops_to_add)
                    db.commit()
                    stops_to_add = []

            if stops_to_add:
                db.add_all(stops_to_add)
                db.commit()

            result.stops_count = db.query(GTFSStop).count()
            logger.info(f"Total Stops in DB: {result.stops_count}")

        # 3. Ingest Trips (trips.txt)
        trips_path = os.path.join(actual_dir, "trips.txt")
        if os.path.exists(trips_path):
            existing_trip_ids = {t[0] for t in db.query(GTFSTrip.trip_id).all()}
            available_route_ids = {r[0] for r in db.query(GTFSRoute.route_id).all()}
            trips_to_add = []
            for row in read_csv_dict(trips_path, max_rows=max_trips):
                t_id = row.get("trip_id")
                r_id = row.get("route_id")
                if not t_id or not r_id or r_id not in available_route_ids:
                    continue
                srv_id = row.get("service_id", "daily")

                if t_id in existing_trip_ids:
                    trip_obj = db.query(GTFSTrip).filter(GTFSTrip.trip_id == t_id).first()
                    if trip_obj:
                        trip_obj.route_id = r_id
                        trip_obj.service_id = srv_id
                else:
                    trip_obj = GTFSTrip(
                        trip_id=t_id,
                        route_id=r_id,
                        service_id=srv_id
                    )
                    trips_to_add.append(trip_obj)
                    existing_trip_ids.add(t_id)

                if len(trips_to_add) >= 500:
                    db.add_all(trips_to_add)
                    db.commit()
                    trips_to_add = []

            if trips_to_add:
                db.add_all(trips_to_add)
                db.commit()

            result.trips_count = db.query(GTFSTrip).count()
            logger.info(f"Total Trips in DB: {result.trips_count}")

        # 4. Ingest Stop Times (stop_times.txt)
        stop_times_path = os.path.join(actual_dir, "stop_times.txt")
        if os.path.exists(stop_times_path):
            available_trip_ids = {t[0] for t in db.query(GTFSTrip.trip_id).all()}
            available_stop_ids = {s[0] for s in db.query(GTFSStop.stop_id).all()}
            
            # If database already has many stop times, insert only newly needed
            current_st_count = db.query(GTFSStopTime).count()
            if current_st_count < 1000:
                stop_times_to_add = []
                for row in read_csv_dict(stop_times_path, max_rows=max_stop_times or 5000):
                    t_id = row.get("trip_id")
                    s_id = row.get("stop_id")
                    if not t_id or not s_id or t_id not in available_trip_ids or s_id not in available_stop_ids:
                        continue
                    arr_time = row.get("arrival_time", "00:00:00")
                    dep_time = row.get("departure_time", "00:00:00")
                    try:
                        seq = int(row.get("stop_sequence", "1"))
                    except ValueError:
                        seq = 1

                    st_obj = GTFSStopTime(
                        trip_id=t_id,
                        stop_id=s_id,
                        arrival_time=arr_time,
                        departure_time=dep_time,
                        stop_sequence=seq
                    )
                    stop_times_to_add.append(st_obj)

                    if len(stop_times_to_add) >= 1000:
                        db.add_all(stop_times_to_add)
                        db.commit()
                        stop_times_to_add = []

                if stop_times_to_add:
                    db.add_all(stop_times_to_add)
                    db.commit()

            result.stop_times_count = db.query(GTFSStopTime).count()
            logger.info(f"Total Stop Times in DB: {result.stop_times_count}")

    except Exception as e:
        logger.error(f"Error syncing GTFS: {e}")
        if db:
            db.rollback()
        result.status = "error"
        result.error = str(e)
    finally:
        if close_db and db:
            db.close()

    return result


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculates distance between two coordinates in meters."""
    R = 6371000.0  # Earth radius in meters
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)
    a = math.sin(delta_phi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2.0) ** 2
    c = 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))
    return R * c


def find_nearby_stops(
    lat: float,
    lon: float,
    radius_meters: float = 1000.0,
    limit: int = 10,
    db: Optional[Session] = None
) -> List[Dict[str, Any]]:
    """
    Finds GTFS stops near GPS coordinates within radius_meters.
    Uses stop_lat/stop_lon columns directly for SQLite compatibility.
    """
    close_db = False
    if db is None:
        db = SessionLocal()
        close_db = True

    results = []
    try:
        stops = db.query(GTFSStop).filter(
            GTFSStop.stop_lat.isnot(None),
            GTFSStop.stop_lon.isnot(None)
        ).all()
        for stop in stops:
            s_lat = stop.stop_lat
            s_lon = stop.stop_lon
            if s_lat is None or s_lon is None:
                continue
            dist = haversine_distance(lat, lon, s_lat, s_lon)
            if dist <= radius_meters:
                results.append({
                    "stop_id": stop.stop_id,
                    "stop_name": stop.stop_name,
                    "latitude": s_lat,
                    "longitude": s_lon,
                    "distance_meters": round(dist, 1)
                })
        # Sort by distance
        results.sort(key=lambda x: x["distance_meters"])
        results = results[:limit]
    except Exception as e:
        logger.error(f"Error finding nearby stops: {e}")
    finally:
        if close_db and db:
            db.close()

    return results


def get_gtfs_status(db: Optional[Session] = None) -> Dict[str, Any]:
    """Returns statistics of imported GTFS data in the database."""
    close_db = False
    if db is None:
        db = SessionLocal()
        close_db = True
    try:
        routes_count = db.query(GTFSRoute).count()
        stops_count = db.query(GTFSStop).count()
        trips_count = db.query(GTFSTrip).count()
        stop_times_count = db.query(GTFSStopTime).count()
        return {
            "status": "ready" if (routes_count > 0 and stops_count > 0) else "empty",
            "routes_count": routes_count,
            "stops_count": stops_count,
            "trips_count": trips_count,
            "stop_times_count": stop_times_count,
            "dataset": DEFAULT_GITHUB_REPO
        }
    except Exception as e:
        return {
            "status": "error",
            "error": str(e)
        }
    finally:
        if close_db and db:
            db.close()
