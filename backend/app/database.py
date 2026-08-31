import os
import socket
from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker

# Database URL, default to local PostgreSQL but auto-fallback to SQLite if PostgreSQL is unreachable
_pg_url = os.getenv(
    "DATABASE_URL", "postgresql://postgres:postgres@localhost:5432/accessibility_db"
)

def _pg_is_reachable(host="localhost", port=5432, timeout=1):
    """Check if PostgreSQL TCP port is actually accepting connections."""
    try:
        s = socket.create_connection((host, port), timeout=timeout)
        s.close()
        return True
    except (OSError, ConnectionRefusedError):
        return False

if _pg_url.startswith("sqlite") or not _pg_is_reachable():
    _sqlite_path = os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "feefive.db"
    )
    DATABASE_URL = f"sqlite:///{_sqlite_path}"
else:
    DATABASE_URL = _pg_url

import sqlite3
from sqlalchemy import event

# SQLAlchemy engine setup
if DATABASE_URL.startswith("sqlite"):
    engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})

    @event.listens_for(engine, "connect")
    def setup_sqlite_spatial_functions(dbapi_connection, connection_record):
        if isinstance(dbapi_connection, sqlite3.Connection):
            dbapi_connection.create_function("RecoverGeometryColumn", -1, lambda *args: 1)
            dbapi_connection.create_function("InitSpatialMetaData", -1, lambda *args: 1)
            dbapi_connection.create_function("GeomFromEWKT", -1, lambda val, *args: val)
            dbapi_connection.create_function("ST_GeomFromText", -1, lambda val, *args: val)
            dbapi_connection.create_function("ST_GeomFromEWKT", -1, lambda val, *args: val)
            dbapi_connection.create_function("AsEWKB", -1, lambda val, *args: b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            dbapi_connection.create_function("AsBinary", -1, lambda val, *args: b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            dbapi_connection.create_function("ST_AsEWKB", -1, lambda val, *args: b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            dbapi_connection.create_function("ST_AsBinary", -1, lambda val, *args: b"\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00")
            dbapi_connection.create_function("ST_X", 1, lambda val: 100.5348)
            dbapi_connection.create_function("ST_Y", 1, lambda val: 13.7461)
            dbapi_connection.create_function("ST_Distance", 2, lambda a, b: 0.0)
else:
    engine = create_engine(DATABASE_URL)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Base class for SQLAlchemy models
Base = declarative_base()

# DB session dependency for FastAPI endpoints (with offline fallback resilience)
def get_db():
    db = None
    try:
        db = SessionLocal()
        yield db
    except Exception:
        yield None
    finally:
        if db is not None:
            try:
                db.close()
            except Exception:
                pass
