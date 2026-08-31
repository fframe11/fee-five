import datetime
from sqlalchemy import Column, Integer, String, Boolean, Float, DateTime, ForeignKey, text
from sqlalchemy.orm import relationship as orm_relationship
from geoalchemy2 import Geometry
from .database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(100), nullable=False)
    email = Column(String(100), unique=True, index=True, nullable=False)
    password_hash = Column(String(255), nullable=False)
    accessibility_mode = Column(String(50), nullable=False)  # visual, wheelchair, speech_hearing
    created_at = Column(DateTime, default=datetime.datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow, nullable=False)

    # Relationships
    preferences = orm_relationship("UserPreference", back_populates="user", uselist=False, cascade="all, delete-orphan")
    emergency_contacts = orm_relationship("EmergencyContact", back_populates="user", cascade="all, delete-orphan")
    navigation_sessions = orm_relationship("NavigationSession", back_populates="user", cascade="all, delete-orphan")
    emergency_events = orm_relationship("EmergencyEvent", back_populates="user", cascade="all, delete-orphan")

class UserPreference(Base):
    __tablename__ = "user_preferences"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False)
    voice_enabled = Column(Boolean, default=True, nullable=False)
    haptic_enabled = Column(Boolean, default=True, nullable=False)
    high_contrast = Column(Boolean, default=False, nullable=False)
    font_scale = Column(Float, default=1.0, nullable=False)
    language = Column(String(10), default="th", nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow, nullable=False)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow, nullable=False)

    # Relationships
    user = orm_relationship("User", back_populates="preferences")

class EmergencyContact(Base):
    __tablename__ = "emergency_contacts"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(100), nullable=False)
    phone = Column(String(20), nullable=False)
    relationship = Column(String(50), nullable=False)
    created_at = Column(DateTime, default=datetime.datetime.utcnow, nullable=False)

    # Relationships
    user = orm_relationship("User", back_populates="emergency_contacts")

class AccessibilityPoint(Base):
    __tablename__ = "accessibility_points"

    id = Column(Integer, primary_key=True, index=True)
    type = Column(String(50), nullable=False)  # elevator, ramp, crossing
    name = Column(String(100), nullable=False)
    # PostGIS Point: Geometry type, SRID 4326 (WGS 84 GPS coordinates)
    geom = Column(Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False)
    status = Column(String(50), default="available", nullable=False)  # available, unavailable
    accessibility_level = Column(String(50), nullable=True)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow, nullable=False)

class Barrier(Base):
    __tablename__ = "barriers"

    id = Column(Integer, primary_key=True, index=True)
    type = Column(String(50), nullable=False)  # broken_sidewalk, flooding, obstacle
    # PostGIS Point: Geometry type, SRID 4326
    geom = Column(Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False)
    severity = Column(String(50), default="medium", nullable=False)  # low, medium, high
    status = Column(String(50), default="active", nullable=False)  # active, cleared
    reported_at = Column(DateTime, default=datetime.datetime.utcnow, nullable=False)
    expires_at = Column(DateTime, nullable=True)

class NavigationSession(Base):
    __tablename__ = "navigation_sessions"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    # PostGIS geometries
    origin_geom = Column(Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False)
    destination_geom = Column(Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False)
    route_geometry = Column(Geometry(geometry_type="LINESTRING", srid=4326, spatial_index=False), nullable=True)
    started_at = Column(DateTime, default=datetime.datetime.utcnow, nullable=False)
    ended_at = Column(DateTime, nullable=True)
    status = Column(String(50), default="navigating", nullable=False)  # navigating, completed, canceled

    # Relationships
    user = orm_relationship("User", back_populates="navigation_sessions")

class EmergencyEvent(Base):
    __tablename__ = "emergency_events"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    event_type = Column(String(50), default="SOS", nullable=False)
    trigger_method = Column(String(50), nullable=False)  # manual, gesture
    # PostGIS Point
    geom = Column(Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False)
    accuracy = Column(Float, nullable=True)
    status = Column(String(50), default="active", nullable=False)  # active, resolved
    created_at = Column(DateTime, default=datetime.datetime.utcnow, nullable=False)
    resolved_at = Column(DateTime, nullable=True)

    # Relationships
    user = orm_relationship("User", back_populates="emergency_events")


class GTFSRoute(Base):
    __tablename__ = "gtfs_routes"

    route_id = Column(String(50), primary_key=True)
    route_short_name = Column(String(50), nullable=True)
    route_long_name = Column(String(255), nullable=True)
    route_type = Column(Integer, nullable=False, default=3)  # 3 = Bus


class GTFSStop(Base):
    __tablename__ = "gtfs_stops"

    stop_id = Column(String(50), primary_key=True)
    stop_name = Column(String(255), nullable=False)
    stop_lat = Column(Float, nullable=True)
    stop_lon = Column(Float, nullable=True)
    geom = Column(Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=True)


class GTFSTrip(Base):
    __tablename__ = "gtfs_trips"

    trip_id = Column(String(50), primary_key=True)
    route_id = Column(String(50), ForeignKey("gtfs_routes.route_id", ondelete="CASCADE"), nullable=False)
    service_id = Column(String(50), nullable=True)


class GTFSStopTime(Base):
    __tablename__ = "gtfs_stop_times"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    trip_id = Column(String(50), ForeignKey("gtfs_trips.trip_id", ondelete="CASCADE"), nullable=False)
    stop_id = Column(String(50), ForeignKey("gtfs_stops.stop_id", ondelete="CASCADE"), nullable=False)
    arrival_time = Column(String(20), nullable=False)
    departure_time = Column(String(20), nullable=False)
    stop_sequence = Column(Integer, nullable=False)


class GTFSVehiclePosition(Base):
    __tablename__ = "gtfs_vehicle_positions"

    vehicle_id = Column(String(50), primary_key=True)
    trip_id = Column(String(50), ForeignKey("gtfs_trips.trip_id", ondelete="SET NULL"), nullable=True)
    geom = Column(Geometry(geometry_type="POINT", srid=4326, spatial_index=False), nullable=False)
    current_stop_id = Column(String(50), ForeignKey("gtfs_stops.stop_id", ondelete="SET NULL"), nullable=True)
    current_status = Column(String(50), nullable=True)  # IN_TRANSIT_TO, STOPPED_AT
    delay_seconds = Column(Integer, nullable=False, default=0)
    updated_at = Column(DateTime, default=datetime.datetime.utcnow, onupdate=datetime.datetime.utcnow, nullable=False)
