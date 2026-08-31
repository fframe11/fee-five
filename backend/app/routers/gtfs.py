"""
GTFS Router for Bangkok Transit Data Integration
Endpoints for manual/automatic GTFS synchronization, status checks, route lookup, and nearby stops.
"""

from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks, status
from sqlalchemy.orm import Session
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field

from ..database import get_db
from ..models import GTFSRoute, GTFSStop, GTFSTrip, GTFSStopTime
from ..gtfs_service import sync_gtfs_data, find_nearby_stops, get_gtfs_status

router = APIRouter(prefix="/api/v1/gtfs", tags=["GTFS Bangkok Transit"])


class GTFSSyncRequest(BaseModel):
    source_dir: Optional[str] = Field(None, description="Custom local path to GTFS directory containing routes.txt, stops.txt, etc.")
    download_latest: bool = Field(False, description="Whether to download latest snapshot from GitHub asiripanich/bangkok-gtfs")
    max_routes: Optional[int] = Field(None, description="Maximum number of routes to import (None for all)")
    max_stops: Optional[int] = Field(None, description="Maximum number of stops to import (None for all)")
    max_trips: Optional[int] = Field(None, description="Maximum number of trips to import (None for all)")
    max_stop_times: Optional[int] = Field(10000, description="Maximum number of stop_times to import")


class GTFSSyncResponse(BaseModel):
    status: str
    source: str
    routes_count: int
    stops_count: int
    trips_count: int
    stop_times_count: int
    message: str
    error: Optional[str] = None


class GTFSRouteItem(BaseModel):
    route_id: str
    route_short_name: Optional[str] = None
    route_long_name: Optional[str] = None
    route_type: int


class GTFSStopItem(BaseModel):
    stop_id: str
    stop_name: str
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    distance_meters: Optional[float] = None


class TransitEstimateResponse(BaseModel):
    is_operating: bool
    transit_type: str
    headway_minutes: int
    next_arrival_minutes: int
    following_arrival_minutes: int
    frequency_text: str
    operating_hours: str
    simulated_server_time: str


@router.get("/status", summary="Get GTFS Dataset Summary")
def get_status(db: Session = Depends(get_db)):
    """Returns the current number of routes, stops, trips, and stop times in the system."""
    if db is None:
        return {"status": "offline_mock", "routes_count": 0, "stops_count": 0}
    return get_gtfs_status(db)


@router.post("/sync", response_model=GTFSSyncResponse, summary="Sync GTFS Data into Database")
def trigger_sync(
    payload: GTFSSyncRequest,
    background_tasks: BackgroundTasks,
    run_async: bool = Query(False, description="Run synchronization in background"),
    db: Session = Depends(get_db)
):
    """
    Imports or updates Bangkok GTFS transit data (routes, stops, trips, stop_times).
    Can ingest from local cloned repository (datasets/bangkok-gtfs) or download fresh snapshot from GitHub.
    """
    if db is None:
        raise HTTPException(status_code=503, detail="Database connection unavailable")

    if run_async:
        background_tasks.add_task(
            sync_gtfs_data,
            gtfs_dir=payload.source_dir,
            max_routes=payload.max_routes,
            max_stops=payload.max_stops,
            max_trips=payload.max_trips,
            max_stop_times=payload.max_stop_times,
            download_if_missing=payload.download_latest
        )
        return GTFSSyncResponse(
            status="processing",
            source=payload.source_dir or "default",
            routes_count=0,
            stops_count=0,
            trips_count=0,
            stop_times_count=0,
            message="GTFS synchronization started in background task."
        )

    result = sync_gtfs_data(
        gtfs_dir=payload.source_dir,
        db=db,
        max_routes=payload.max_routes,
        max_stops=payload.max_stops,
        max_trips=payload.max_trips,
        max_stop_times=payload.max_stop_times,
        download_if_missing=payload.download_latest
    )

    if result.status == "error":
        return GTFSSyncResponse(
            status="error",
            source=result.source,
            routes_count=result.routes_count,
            stops_count=result.stops_count,
            trips_count=result.trips_count,
            stop_times_count=result.stop_times_count,
            message=f"Sync failed: {result.error}",
            error=result.error
        )

    return GTFSSyncResponse(
        status="success",
        source=result.source,
        routes_count=result.routes_count,
        stops_count=result.stops_count,
        trips_count=result.trips_count,
        stop_times_count=result.stop_times_count,
        message="Successfully synchronized Bangkok GTFS dataset into database."
    )


@router.get("/routes", response_model=List[GTFSRouteItem], summary="Search and list transit routes")
def list_routes(
    q: Optional[str] = Query(None, description="Search route short name or long name (e.g. 511, BTS, Sukhumvit)"),
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db)
):
    """Lists Bangkok transit routes with optional search filter."""
    if db is None:
        return []
    query = db.query(GTFSRoute)
    if q:
        search_pattern = f"%{q.strip()}%"
        query = query.filter(
            (GTFSRoute.route_short_name.ilike(search_pattern)) |
            (GTFSRoute.route_long_name.ilike(search_pattern))
        )
    routes = query.offset(offset).limit(limit).all()
    return [
        GTFSRouteItem(
            route_id=r.route_id,
            route_short_name=r.route_short_name,
            route_long_name=r.route_long_name,
            route_type=r.route_type
        )
        for r in routes
    ]


@router.get("/stops/nearby", response_model=List[GTFSStopItem], summary="Find transit stops near GPS coordinate")
def get_nearby_stops(
    latitude: float = Query(..., ge=-90.0, le=90.0, description="User GPS latitude"),
    longitude: float = Query(..., ge=-180.0, le=180.0, description="User GPS longitude"),
    radius_meters: float = Query(1000.0, ge=50.0, le=50000.0, description="Search radius in meters"),
    limit: int = Query(10, ge=1, le=50),
    db: Session = Depends(get_db)
):
    """Finds nearest bus stops, BTS, MRT, and pier stations within specified radius."""
    if db is None:
        return []
    stops = find_nearby_stops(
        lat=latitude,
        lon=longitude,
        radius_meters=radius_meters,
        limit=limit,
        db=db
    )
    return [
        GTFSStopItem(
            stop_id=s["stop_id"],
            stop_name=s["stop_name"],
            latitude=s["latitude"],
            longitude=s["longitude"],
            distance_meters=s["distance_meters"]
        )
        for s in stops
    ]


@router.get("/routes/{route_id}/stops", response_model=List[GTFSStopItem], summary="Get ordered stops for a route")
def get_route_stops(route_id: str, db: Session = Depends(get_db)):
    """Retrieves all stops in order for a given route."""
    if db is None:
        raise HTTPException(status_code=503, detail="Database unavailable")

    trip = db.query(GTFSTrip).filter(GTFSTrip.route_id == route_id).first()
    if not trip:
        raise HTTPException(status_code=404, detail=f"No trips found for route {route_id}")

    stop_times = db.query(GTFSStopTime, GTFSStop).join(
        GTFSStop, GTFSStopTime.stop_id == GTFSStop.stop_id
    ).filter(GTFSStopTime.trip_id == trip.trip_id).order_by(GTFSStopTime.stop_sequence).all()

    results = []
    for st, stop in stop_times:
        geom_str = str(stop.geom) if stop.geom is not None else ""
        lat, lon = None, None
        if "POINT" in geom_str:
            coords = geom_str.split("POINT")[-1].replace("(", "").replace(")", "").strip().split()
            if len(coords) >= 2:
                try:
                    lon, lat = float(coords[0]), float(coords[1])
                except ValueError:
                    pass
        results.append(
            GTFSStopItem(
                stop_id=stop.stop_id,
                stop_name=stop.stop_name,
                latitude=lat,
                longitude=lon
            )
        )
    return results


@router.get("/transit/estimate", response_model=TransitEstimateResponse, summary="Time-based Headway & Arrival Simulation for Transit")
def estimate_transit_arrival(
    transit_type: str = Query("bts_mrt", description="Type of transit: 'bts_mrt', 'bus', or 'srt'"),
    stop_name: Optional[str] = Query(None, description="Optional name of stop or station")
):
    """
    Deterministic Time-based simulation for BTS/MRT/Bus arrivals.
    Calculates estimated headway and arrival countdown according to official operating timetables
    without depending on unstable scrapers or reverse-engineered endpoints.
    """
    from datetime import datetime, timezone, timedelta
    
    # Bangkok Local Time (UTC+7)
    bkk_time = datetime.now(timezone(timedelta(hours=7)))
    hour = bkk_time.hour
    minute = bkk_time.minute
    total_minutes = hour * 60 + minute
    
    is_bts = "bts" in transit_type.lower() or "mrt" in transit_type.lower() or "rail" in transit_type.lower()
    
    # Standard Operating Hours 05:30 - 24:00 (330 to 1440 mins)
    if total_minutes < 330:
        return TransitEstimateResponse(
            is_operating=False,
            transit_type="BTS/MRT" if is_bts else "Bus",
            headway_minutes=0,
            next_arrival_minutes=330 - total_minutes,
            following_arrival_minutes=330 - total_minutes + 5,
            frequency_text="ปิดให้บริการชั่วคราว (เปิดให้บริการเที่ยวแรก 05:30 น.)",
            operating_hours="05:30 - 24:00 น.",
            simulated_server_time=bkk_time.strftime("%H:%M:%S")
        )
    
    # Peak Hours: 07:00-09:00 (420-540) & 17:00-19:30 (1020-1170)
    is_peak = (420 <= total_minutes <= 540) or (1020 <= total_minutes <= 1170)
    # Late Night: 22:00-24:00 (1320-1440)
    is_late = total_minutes >= 1320
    
    if is_bts:
        headway = 3 if is_peak else (8 if is_late else 5)
        type_name = "รถไฟฟ้า BTS / MRT"
    else:
        headway = 8 if is_peak else (20 if is_late else 12)
        type_name = "รถโดยสารประจำทาง (Bus)"
        
    next_arrival = (headway - (minute % headway))
    if next_arrival == 0:
        next_arrival = headway
    following_arrival = next_arrival + headway
    
    peak_label = " (ช่วงเวลาเร่งด่วน)" if is_peak else (" (ช่วงดึก)" if is_late else " (ช่วงเวลาปกติ)")
    freq_desc = f"ขบวนถัดไปในอีก {next_arrival} นาที (ความถี่ทุก {headway} นาที{peak_label})"
    
    return TransitEstimateResponse(
        is_operating=True,
        transit_type=type_name,
        headway_minutes=headway,
        next_arrival_minutes=next_arrival,
        following_arrival_minutes=following_arrival,
        frequency_text=freq_desc,
        operating_hours="05:30 - 24:00 น.",
        simulated_server_time=bkk_time.strftime("%H:%M:%S")
    )

