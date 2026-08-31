"""
Fee Five — Bangkok GTFS Integration Tests
Run: pytest backend/tests/test_gtfs.py -v
"""

import pytest
import os
import sys

# Ensure backend root is in sys.path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

os.environ["DATABASE_URL"] = "sqlite:///:memory:"

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.models import Base, GTFSRoute, GTFSStop, GTFSTrip, GTFSStopTime
from app.database import get_db, engine as app_engine
from app.main import app
from app.gtfs_service import sync_gtfs_data, find_nearby_stops, get_gtfs_status, haversine_distance


@pytest.fixture(scope="module")
def shared_engine():
    eng = create_engine("sqlite:///:memory:", connect_args={"check_same_thread": False}, poolclass=StaticPool)
    import sqlite3
    from sqlalchemy import event
    @event.listens_for(eng, "connect")
    def setup_sqlite(dbapi_conn, record):
        if isinstance(dbapi_conn, sqlite3.Connection):
            dbapi_conn.create_function("RecoverGeometryColumn", -1, lambda *a: 1)
            dbapi_conn.create_function("InitSpatialMetaData", -1, lambda *a: 1)
            dbapi_conn.create_function("GeomFromEWKT", -1, lambda val, *a: val)
            dbapi_conn.create_function("ST_GeomFromText", -1, lambda val, *a: val)
            dbapi_conn.create_function("ST_GeomFromEWKT", -1, lambda val, *a: val)
            dbapi_conn.create_function("AsEWKB", -1, lambda val, *a: b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            dbapi_conn.create_function("AsBinary", -1, lambda val, *a: b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            dbapi_conn.create_function("ST_AsEWKB", -1, lambda val, *a: b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            dbapi_conn.create_function("ST_AsBinary", -1, lambda val, *a: b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            dbapi_conn.create_function("ST_X", 1, lambda val: 100.5348)
            dbapi_conn.create_function("ST_Y", 1, lambda val: 13.7461)
            dbapi_conn.create_function("ST_Distance", 2, lambda a, b: 0.0)

    Base.metadata.create_all(bind=eng)
    return eng


@pytest.fixture(scope="module")
def test_db(shared_engine):
    Session = sessionmaker(autocommit=False, autoflush=False, bind=shared_engine)
    db = Session()
    yield db
    db.close()


@pytest.fixture(scope="module")
def client(shared_engine):
    Session = sessionmaker(autocommit=False, autoflush=False, bind=shared_engine)
    def override_get_db():
        db = Session()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def test_haversine_distance():
    # Distance between Siam Paragon (13.7461, 100.5348) and CentralWorld (13.7450, 100.5380) is ~370m
    dist = haversine_distance(13.7461, 100.5348, 13.7450, 100.5380)
    assert 300 < dist < 450


def test_sync_gtfs_from_local_folder(test_db):
    gtfs_dir = os.path.join(os.path.dirname(__file__), "..", "..", "datasets", "bangkok-gtfs", "data", "gtfs")
    if not os.path.exists(gtfs_dir):
        pytest.skip("Local bangkok-gtfs directory not cloned yet.")

    # Import limited subset for fast test
    result = sync_gtfs_data(
        gtfs_dir=gtfs_dir,
        db=test_db,
        max_routes=10,
        max_stops=20,
        max_trips=10,
        max_stop_times=50,
        download_if_missing=False
    )

    assert result.status == "success"
    assert result.routes_count > 0
    assert result.stops_count > 0

    status = get_gtfs_status(db=test_db)
    assert status["status"] == "ready"
    assert status["routes_count"] >= 10
    assert status["stops_count"] >= 20


def test_find_nearby_stops(test_db):
    # Search around Bangkok area
    stops = find_nearby_stops(13.7207, 100.4578, radius_meters=50000.0, limit=5, db=test_db)
    assert isinstance(stops, list)
    if stops:
        assert "stop_name" in stops[0]
        assert "distance_meters" in stops[0]


def test_gtfs_api_endpoints(client):
    # Test GET status
    resp_status = client.get("/api/v1/gtfs/status")
    assert resp_status.status_code == 200
    assert "routes_count" in resp_status.json()

    # Test GET routes
    resp_routes = client.get("/api/v1/gtfs/routes?limit=5")
    assert resp_routes.status_code == 200
    routes = resp_routes.json()
    assert isinstance(routes, list)

    # Test GET nearby stops
    resp_stops = client.get("/api/v1/gtfs/stops/nearby?latitude=13.7207&longitude=100.4578&radius_meters=50000")
    assert resp_stops.status_code == 200
    assert isinstance(resp_stops.json(), list)

    # Test GET Time-based Transit Simulation Estimate
    resp_sim = client.get("/api/v1/gtfs/transit/estimate?transit_type=bts_mrt&stop_name=Siam")
    assert resp_sim.status_code == 200
    sim_data = resp_sim.json()
    assert "next_arrival_minutes" in sim_data
    assert "frequency_text" in sim_data
    assert "transit_type" in sim_data

